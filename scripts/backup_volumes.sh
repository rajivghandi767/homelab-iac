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

# 1. DOCKER VOLUME BACKUPS (Apps that use flat files/sqlite)
VOLUMES=(
    "jenkins:jenkins_data:jenkins"
    "vault:vault_data:vault_data"
    "nginx-proxy-manager:npm_data:npm_data"
    "nginx-proxy-manager:npm_letsencrypt:npm_letsencrypt"
)

echo "Starting Backup Job - $DATE"

for entry in "${VOLUMES[@]}"; do
    IFS=':' read -r CONTAINER VOLUME FILENAME <<< "$entry"
    echo "Processing Volume: $FILENAME..."

    # Pause container to prevent flat-file corruption
    docker stop $CONTAINER || echo "Warning: $CONTAINER not running."

    docker run --rm \
        -v $VOLUME:/source:ro \
        -v $BACKUP_ROOT:/backup \
        alpine tar -czf /backup/$FILENAME.tar.gz -C /source .

    docker start $CONTAINER

    gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
        -c -o $BACKUP_ROOT/$FILENAME.tar.gz.gpg $BACKUP_ROOT/$FILENAME.tar.gz
    
    rm $BACKUP_ROOT/$FILENAME.tar.gz
    gsutil cp $BACKUP_ROOT/$FILENAME.tar.gz.gpg $GCS_BUCKET/$DATE/$FILENAME.tar.gz.gpg
    gsutil cp $BACKUP_ROOT/$FILENAME.tar.gz.gpg $GCS_BUCKET/latest/$FILENAME.tar.gz.gpg
done

# 2. LOGICAL DATABASE BACKUP (Zero-Downtime)
echo "Processing Logical DB Dump..."
# Dump directly to the staging folder without stopping the container
docker exec postgres-core pg_dumpall -U "$POSTGRES_USER" > $BACKUP_ROOT/postgres_logical.sql

# Compress and Encrypt
tar -czf $BACKUP_ROOT/postgres_logical.tar.gz -C $BACKUP_ROOT postgres_logical.sql
gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
    -c -o $BACKUP_ROOT/postgres_logical.tar.gz.gpg $BACKUP_ROOT/postgres_logical.tar.gz

rm $BACKUP_ROOT/postgres_logical.sql $BACKUP_ROOT/postgres_logical.tar.gz
gsutil cp $BACKUP_ROOT/postgres_logical.tar.gz.gpg $GCS_BUCKET/$DATE/postgres_logical.tar.gz.gpg
gsutil cp $BACKUP_ROOT/postgres_logical.tar.gz.gpg $GCS_BUCKET/latest/postgres_logical.tar.gz.gpg

# Cleanup Staging
rm -rf $BACKUP_ROOT/*
echo "Backup Complete!"