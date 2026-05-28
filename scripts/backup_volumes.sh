#!/bin/bash
set -e

# --- Configuration ---
BACKUP_ROOT="/opt/homelab-iac/backups/staging"
DATE=$(date +%Y-%m-%d)
GCS_BUCKET="gs://homelab-backups-rajiv" 
SECRETS_FILE="/opt/homelab-iac/services/database/postgres-core/.env"
GLOBAL_SECRETS="/opt/homelab-iac/secrets/.env"

# Load Passphrases and DB Credentials
source $GLOBAL_SECRETS
source $SECRETS_FILE

mkdir -p $BACKUP_ROOT

# --- Helper Function for GCP Upload ---
upload_to_gcs() {
    local FILE_PATH=$1
    local FILENAME=$(basename $FILE_PATH)
    
    docker run --rm \
        -v $BACKUP_ROOT:/backup \
        -e GCP_SA_JSON="$GCS_SA_KEY_JSON" \
        google/cloud-cli:alpine \
        sh -c "echo \"\$GCP_SA_JSON\" > /tmp/key.json && \
               gcloud auth activate-service-account --key-file=/tmp/key.json && \
               gsutil cp /backup/$FILENAME $GCS_BUCKET/$DATE/$FILENAME && \
               gsutil cp /backup/$FILENAME $GCS_BUCKET/latest/$FILENAME && \
               rm -f /tmp/key.json"
}

# 1. DOCKER VOLUME BACKUPS
VOLUMES=(
    "jenkins:jenkins_data:jenkins"
    "vault:vault_data:vault_data"
    "nginx-proxy-manager:npm_data:npm_data"
    "nginx-proxy-manager:npm_letsencrypt:npm_letsencrypt"
    "pihole:pihole_config:pihole_config"
    "pihole:pihole_dnsmasq:pihole_dnsmasq"
    "portainer:portainer_data:portainer_data"
    "unifi-db:unifi_db_data:unifi_db_data"
    "unifi-db:unifi_config:unifi_config"
    "pgadmin:pgadmin_data:pgadmin_data"
    "grafana:grafana_data:grafana_data"
    "jellyfin:jellyfin_config:jellyfin_config"
)

echo "Starting Backup Job - $DATE"

for entry in "${VOLUMES[@]}"; do
    IFS=':' read -r CONTAINER VOLUME FILENAME <<< "$entry"
    echo "Processing Volume: $FILENAME..."

    docker stop $CONTAINER || echo "Warning: $CONTAINER not running."

    docker run --rm \
        -v $VOLUME:/source:ro \
        -v $BACKUP_ROOT:/backup \
        alpine tar -czf /backup/$FILENAME.tar.gz -C /source .

    docker start $CONTAINER

    gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
        -c -o $BACKUP_ROOT/$FILENAME.tar.gz.gpg $BACKUP_ROOT/$FILENAME.tar.gz
    
    rm $BACKUP_ROOT/$FILENAME.tar.gz
    
    echo "Uploading $FILENAME.tar.gz.gpg to GCP..."
    upload_to_gcs "$BACKUP_ROOT/$FILENAME.tar.gz.gpg"
done

# 2. LOGICAL DATABASE BACKUP
echo "Processing Logical DB Dump..."
docker exec postgres-core pg_dumpall -U "$POSTGRES_ROOT_USER" > $BACKUP_ROOT/postgres_logical.sql

tar -czf $BACKUP_ROOT/postgres_logical.tar.gz -C $BACKUP_ROOT postgres_logical.sql
gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
    -c -o $BACKUP_ROOT/postgres_logical.tar.gz.gpg $BACKUP_ROOT/postgres_logical.tar.gz

rm $BACKUP_ROOT/postgres_logical.sql $BACKUP_ROOT/postgres_logical.tar.gz

echo "Uploading postgres_logical.tar.gz.gpg to GCP..."
upload_to_gcs "$BACKUP_ROOT/postgres_logical.tar.gz.gpg"

rm -rf $BACKUP_ROOT/*
echo "Backup Complete!"