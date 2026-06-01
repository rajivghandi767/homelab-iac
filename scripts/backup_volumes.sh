#!/bin/bash

# --- Configuration ---
BACKUP_ROOT="/opt/homelab-iac/backups/staging"
DATE=$(date +%Y-%m-%d)
GCS_BUCKET="gs://homelab-backups-rajiv-wallace" 
SECRETS_FILE="/opt/homelab-iac/services/database/postgres-core/.env"
GLOBAL_SECRETS="/opt/homelab-iac/secrets/.env"

# Load Passphrases, DB Credentials, and the Backup Webhook from Ansible Vault
source $GLOBAL_SECRETS
source $SECRETS_FILE

# Start the stopwatch immediately for accurate duration reporting
SECONDS=0
HOSTNAME=$(hostname)

# --- Observability: Structured JSON Logging for Grafana Loki ---
log_event() {
    local LEVEL=$1
    local MESSAGE=$2
    local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Output to stdout and append to the system log file simultaneously
    echo "{\"timestamp\": \"$TIMESTAMP\", \"level\": \"$LEVEL\", \"service\": \"backup_job\", \"message\": \"$MESSAGE\"}" | tee -a /var/log/homelab_backup.log
}

# --- Resilience: Alerting & Cleanup Exit Trap ---
cleanup_and_alert() {
    local EXIT_CODE=$?
    local DURATION_MINUTES=$((SECONDS / 60))
    local DURATION_SECONDS=$((SECONDS % 60))

    if [ $EXIT_CODE -ne 0 ]; then
        log_event "ERROR" "Backup pipeline encountered a fatal error after ${DURATION_MINUTES}m ${DURATION_SECONDS}s."
        curl -s -H "Content-Type: application/json" -X POST -d "{
          \"embeds\": [{
            \"title\": \"🚨 Backup Failed ($HOSTNAME)\",
            \"description\": \"The backup script exited prematurely on an error block. Inspect /var/log/homelab_backup.log or check your Grafana dashboard.\",
            \"color\": 16711680
          }]
        }" $BACKUP_DISCORD_WEBHOOK_URL > /dev/null
    else
        log_event "INFO" "Backup pipeline executed successfully in ${DURATION_MINUTES}m ${DURATION_SECONDS}s."
        curl -s -H "Content-Type: application/json" -X POST -d "{
          \"embeds\": [{
            \"title\": \"✅ Backup Complete ($HOSTNAME)\",
            \"description\": \"All Docker volumes and logical database dumps successfully encrypted and synchronized to Google Cloud Storage in ${DURATION_MINUTES}m ${DURATION_SECONDS}s.\",
            \"color\": 65280
          }]
        }" $BACKUP_DISCORD_WEBHOOK_URL > /dev/null
    fi

    log_event "INFO" "Executing file cleanup and staging environment takedown."
    rm -rf $BACKUP_ROOT/*
    if mountpoint -q $BACKUP_ROOT; then
        umount $BACKUP_ROOT || log_event "WARN" "Failed to cleanly unmount $BACKUP_ROOT."
    fi
}

# Bind the lifecycle trap to the EXIT state
trap 'cleanup_and_alert' EXIT

# --- Storage Layer: Idempotent Mount with Disk Fallback ---
mkdir -p $BACKUP_ROOT
if ! mountpoint -q $BACKUP_ROOT; then
    log_event "INFO" "Attempting to mount 1.5GB tmpfs partition to $BACKUP_ROOT to preserve MicroSD health."
    if ! mount -t tmpfs -o size=1536M tmpfs $BACKUP_ROOT; then
        log_event "WARN" "tmpfs mounting failed. Spawning staging area directly on physical flash memory instead."
    fi
fi

# --- Security: Secure GCP Upload Function (No Env Secret Leak) ---
upload_to_gcs() {
    local FILE_PATH=$1
    local FILENAME=$(basename $FILE_PATH)
    local KEY_FILE="$BACKUP_ROOT/gcp_temp_key.json"
    
    # Write the static service account json directly to the encrypted staging mount
    echo "$GCS_SA_KEY_JSON" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    
    log_event "INFO" "Streaming $FILENAME to Google Cloud Storage bucket."
    
    # Mount the key file read-only directly as a volume rather than passing it via '-e'
    docker run --rm \
        -v $BACKUP_ROOT:/backup \
        -v "$KEY_FILE":/tmp/key.json:ro \
        gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine \
        sh -c "gcloud auth activate-service-account --key-file=/tmp/key.json && \
               gsutil cp /backup/$FILENAME $GCS_BUCKET/$DATE/$FILENAME && \
               gsutil cp /backup/$FILENAME $GCS_BUCKET/latest/$FILENAME"
               
    local STATUS=$?
    
    # Securely overwrite and shred the temporary key file from storage
    shred -u "$KEY_FILE" 2>/dev/null || rm -f "$KEY_FILE"
    
    return $STATUS
}

# --- Execution Matrix: Optimally Ordered Volumes ---
VOLUMES=(
    # Tier 1: Peripheral & Observability Applications
    "jellyfin:jellyfin_config:jellyfin_config"
    "grafana:grafana_data:grafana_data"
    "portainer:portainer_data:portainer_data"
    "pgadmin:pgadmin_data:pgadmin_data"

    # Tier 2: State Services
    "unifi-db:unifi_db_data:unifi_db_data"
    "unifi-db:unifi_config:unifi_config"

    # Tier 3: Core Edge Ingress & Network DNS
    "nginx-proxy-manager:npm_data:npm_data"
    "nginx-proxy-manager:npm_letsencrypt:npm_letsencrypt"
    "pihole:pihole_config:pihole_config"
    "pihole:pihole_dnsmasq:pihole_dnsmasq"

    # Tier 4: Mission-Critical Automation & Secret Backends
    "jenkins:jenkins_data:jenkins"
    "vault:vault_data:vault_data"
)

log_event "INFO" "Starting scheduled backup serialization routine."

# 1. DOCKER VOLUME BACKUPS LOOP
for entry in "${VOLUMES[@]}"; do
    IFS=':' read -r CONTAINER VOLUME FILENAME <<< "$entry"
    log_event "INFO" "Processing serialization target: $FILENAME"

    docker stop $CONTAINER || log_event "WARN" "Container $CONTAINER was not actively running."

    docker run --rm \
        -v $VOLUME:/source:ro \
        -v $BACKUP_ROOT:/backup \
        alpine tar -czf /backup/$FILENAME.tar.gz -C /source .
    if [ $? -ne 0 ]; then exit 1; fi

    docker start $CONTAINER

    gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
        -c -o $BACKUP_ROOT/$FILENAME.tar.gz.gpg $BACKUP_ROOT/$FILENAME.tar.gz
    if [ $? -ne 0 ]; then exit 1; fi
    
    rm $BACKUP_ROOT/$FILENAME.tar.gz
    
    upload_to_gcs "$BACKUP_ROOT/$FILENAME.tar.gz.gpg"
    if [ $? -ne 0 ]; then exit 1; fi

    rm $BACKUP_ROOT/$FILENAME.tar.gz.gpg
done

# 2. LOGICAL DATABASE BACKUP
log_event "INFO" "Initiating logical engine dump for postgres-core container."
docker exec postgres-core pg_dumpall -U "$POSTGRES_ROOT_USER" > $BACKUP_ROOT/postgres_logical.sql
if [ $? -ne 0 ]; then exit 1; fi

tar -czf $BACKUP_ROOT/postgres_logical.tar.gz -C $BACKUP_ROOT postgres_logical.sql
gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
    -c -o $BACKUP_ROOT/postgres_logical.tar.gz.gpg $BACKUP_ROOT/postgres_logical.tar.gz
if [ $? -ne 0 ]; then exit 1; fi

rm $BACKUP_ROOT/postgres_logical.sql $BACKUP_ROOT/postgres_logical.tar.gz

upload_to_gcs "$BACKUP_ROOT/postgres_logical.tar.gz.gpg"
if [ $? -ne 0 ]; then exit 1; fi

# Explicitly evaluate success state to drop smoothly into the clean exit trap
exit 0