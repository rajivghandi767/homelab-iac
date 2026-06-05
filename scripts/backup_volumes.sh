#!/bin/bash

# --- Core Parameters ---
BASE_DIR="/opt/homelab-iac"
GCS_BUCKET="gs://homelab-backups-rajiv-wallace" 

# ENFORCE STRICT FILE CREATION MASK
umask 077

# --- Derived Paths ---
BACKUP_ROOT="${BASE_DIR}/backups/staging"
DOWNLOAD_ROOT="${BASE_DIR}/backups/downloads"
POSTGRES_SECRETS="${BASE_DIR}/services/database/postgres-core/.env"
GLOBAL_SECRETS="${BASE_DIR}/secrets/.env"
DATE=$(date +%Y-%m-%d)

# --- Observability: Structured JSON Logging for Grafana Loki ---
log_event() {
    local LEVEL=$1
    local MESSAGE=$2
    local TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\": \"$TIMESTAMP\", \"level\": \"$LEVEL\", \"service\": \"backup_job\", \"message\": \"$MESSAGE\"}"
}

# --- Pre-Flight Assertions ---
if [ ! -f "$GLOBAL_SECRETS" ] || [ ! -f "$POSTGRES_SECRETS" ]; then
    log_event "FATAL" "Required .env files are missing. Did the Ansible dynamic templating task run?"
    exit 1
fi

source "$GLOBAL_SECRETS"
source "$POSTGRES_SECRETS"

SECONDS=0
HOSTNAME=$(hostname)

# --- Resilience: Alerting & Cleanup Exit Trap ---
cleanup_and_alert() {
    local EXIT_CODE=$?
    local DURATION_MINUTES=$((SECONDS / 60))
    local DURATION_SECONDS=$((SECONDS % 60))

    if [ $EXIT_CODE -ne 0 ]; then
        log_event "ERROR" "Backup pipeline encountered a fatal error after ${DURATION_MINUTES}m ${DURATION_SECONDS}s."
        
        # Extract the last 5 lines of the log and safely escape quotes/newlines for the JSON payload
        ERROR_SNIPPET=$(tail -n 5 "$BASE_DIR/backups/logs/homelab_backup.log" | awk '{gsub(/["\\]/,"\\\\&"); printf "%s\\n", $0}')

        curl -s -H "Content-Type: application/json" -X POST -d "{
          \"embeds\": [{
            \"title\": \"🚨 Backup Failed ($HOSTNAME)\",
            \"description\": \"The backup script exited prematurely. \\n\\n**Last Output:**\\n\`\`\`\\n${ERROR_SNIPPET}\`\`\`\",
            \"color\": 16711680
          }]
        }" "$BACKUP_DISCORD_WEBHOOK_URL" > /dev/null
    else
        log_event "INFO" "Backup pipeline executed successfully in ${DURATION_MINUTES}m ${DURATION_SECONDS}s."
        curl -s -H "Content-Type: application/json" -X POST -d "{
          \"embeds\": [{
            \"title\": \"✅ Backup Complete ($HOSTNAME)\",
            \"description\": \"All Docker volumes and databases successfully encrypted and synchronized in ${DURATION_MINUTES}m ${DURATION_SECONDS}s.\",
            \"color\": 65280
          }]
        }" "$BACKUP_DISCORD_WEBHOOK_URL" > /dev/null
    fi

    log_event "INFO" "Executing file cleanup and staging environment takedown."
    rm -rf "$BACKUP_ROOT"/*
    if mountpoint -q "$BACKUP_ROOT"; then
        umount "$BACKUP_ROOT" || log_event "WARN" "Failed to cleanly unmount $BACKUP_ROOT."
    fi
}

trap 'cleanup_and_alert' EXIT

# --- Storage Layer: Idempotent Mount with Disk Fallback ---
mkdir -p -m 0700 "$BACKUP_ROOT"
mkdir -p -m 0700 "$DOWNLOAD_ROOT"

if ! mountpoint -q "$BACKUP_ROOT"; then
    log_event "INFO" "Attempting to mount 1.5GB tmpfs partition to $BACKUP_ROOT to preserve flash memory health."
    if ! mount -t tmpfs -o size=1536M tmpfs "$BACKUP_ROOT"; then
        log_event "WARN" "tmpfs mounting failed. Spawning staging area directly on physical disk instead."
    fi
fi

# --- Security: Secure GCP Upload Function ---
upload_to_gcs() {
    local FILE_PATH=$1
    local FILENAME=$(basename "$FILE_PATH")
    local KEY_FILE="$BACKUP_ROOT/gcp_temp_key.json"
    
    echo "$GCS_SA_KEY_JSON" > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    
    log_event "INFO" "Streaming $FILENAME to Google Cloud Storage bucket."
    
    docker run --rm \
        -v "$BACKUP_ROOT":/backup \
        -v "$KEY_FILE":/tmp/key.json:ro \
        gcr.io/google.com/cloudsdktool/google-cloud-cli:alpine \
        sh -c "gcloud auth activate-service-account --key-file=/tmp/key.json && \
               gsutil cp /backup/$FILENAME $GCS_BUCKET/$DATE/$FILENAME && \
               gsutil cp /backup/$FILENAME $GCS_BUCKET/latest/$FILENAME"
               
    local STATUS=$?
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

    docker stop "$CONTAINER" || log_event "WARN" "Container $CONTAINER was not actively running."

    # OPTIMIZATION: Piped tar stream into pigz to distribute compression across all 4 CPU cores
    docker run --rm \
        -v "$VOLUME":/source:ro \
        -v "$BACKUP_ROOT":/backup \
        alpine sh -c "apk add --no-cache pigz && tar -cf - -C /source . | pigz > /backup/$FILENAME.tar.gz"
    if [ $? -ne 0 ]; then exit 1; fi

    # Container immediately restarted after tar process completes
    docker start "$CONTAINER"

    gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
        -c -o "$BACKUP_ROOT/$FILENAME.tar.gz.gpg" "$BACKUP_ROOT/$FILENAME.tar.gz"
    if [ $? -ne 0 ]; then exit 1; fi
    
    rm "$BACKUP_ROOT/$FILENAME.tar.gz"
    
    upload_to_gcs "$BACKUP_ROOT/$FILENAME.tar.gz.gpg"
    if [ $? -ne 0 ]; then exit 1; fi

    rm "$BACKUP_ROOT/$FILENAME.tar.gz.gpg"
done

# 2. LOGICAL DATABASE BACKUP
log_event "INFO" "Initiating logical engine dump for postgres-core container."
docker exec postgres-core pg_dumpall -U "$POSTGRES_ROOT_USER" > "$BACKUP_ROOT/postgres_logical.sql"
if [ $? -ne 0 ]; then exit 1; fi

# OPTIMIZATION: Leverage host-level pigz for the SQL dump 
tar -cf - -C "$BACKUP_ROOT" postgres_logical.sql | pigz > "$BACKUP_ROOT/postgres_logical.tar.gz"
gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
    -c -o "$BACKUP_ROOT/postgres_logical.tar.gz.gpg" "$BACKUP_ROOT/postgres_logical.tar.gz"
if [ $? -ne 0 ]; then exit 1; fi

rm "$BACKUP_ROOT/postgres_logical.sql" "$BACKUP_ROOT/postgres_logical.tar.gz"

upload_to_gcs "$BACKUP_ROOT/postgres_logical.tar.gz.gpg"
if [ $? -ne 0 ]; then exit 1; fi

exit 0