#!/bin/bash
set -e

# --- Configuration ---
BACKUP_ROOT="/opt/homelab/backups/staging"
DATE=$(date +%Y-%m-%d)
GCS_BUCKET="gs://homelab-backups-rajiv" # Matches your Terraform output
SECRETS_FILE="../secrets/.env"

# Load Secrets for GPG passphrase
if [ -f "$SECRETS_FILE" ]; then
    export $(grep -v '^#' $SECRETS_FILE | xargs)
else
    echo "Error: Secrets file not found at $SECRETS_FILE"
    exit 1
fi

mkdir -p $BACKUP_ROOT

# List of critical volumes to backup
# format: "container_name:volume_name:backup_filename"
VOLUMES=(
    "jenkins:jenkins_data:jenkins"
    "vault:vault_data:vault_data"
    "nginx:npm_data:npm_data"
    "nginx:npm_letsencrypt:npm_letsencrypt"
    "postgres-dev:postgres_dev_data:postgres_data"
)

echo "Starting Backup Job - $DATE"

for entry in "${VOLUMES[@]}"; do
    IFS=':' read -r CONTAINER VOLUME FILENAME <<< "$entry"
    
    echo "Processing $FILENAME..."

    # 1. Stop Container (Prevent DB corruption)
    echo "  -> Stopping $CONTAINER..."
    docker stop $CONTAINER || echo "  Warning: $CONTAINER not running, proceeding..."

    # 2. Create Tarball
    # We use a temporary container to mount the volume and tar it. 
    # This is safer than accessing /var/lib/docker/volumes directly.
    echo "  -> Compressing volume..."
    docker run --rm \
        -v $VOLUME:/source:ro \
        -v $BACKUP_ROOT:/backup \
        alpine tar -czf /backup/$FILENAME.tar.gz -C /source .

    # 3. Start Container Immediately
    echo "  -> Restarting $CONTAINER..."
    docker start $CONTAINER

    # 4. Encrypt (Optional but recommended)
    echo "  -> Encrypting..."
    # Uses symmetric encryption with the passphrase from .env
    gpg --batch --yes --passphrase "$BACKUP_ENCRYPTION_KEY" \
        -c -o $BACKUP_ROOT/$FILENAME.tar.gz.gpg $BACKUP_ROOT/$FILENAME.tar.gz
    
    # Remove unencrypted tar
    rm $BACKUP_ROOT/$FILENAME.tar.gz
    
    # 5. Upload to GCP
    echo "  -> Uploading to GCS..."
    gsutil cp $BACKUP_ROOT/$FILENAME.tar.gz.gpg $GCS_BUCKET/$DATE/$FILENAME.tar.gz.gpg
    # Also update "latest" folder for easy restore
    gsutil cp $BACKUP_ROOT/$FILENAME.tar.gz.gpg $GCS_BUCKET/latest/$FILENAME.tar.gz.gpg

done

# Cleanup Staging
rm -rf $BACKUP_ROOT/*

echo "Backup Complete!"