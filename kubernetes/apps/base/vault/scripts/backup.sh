#!/bin/sh
set -e

# Install AWS CLI
echo "Installing AWS CLI..."
apk add --no-cache aws-cli

echo "Starting Vault backup at $(date)"

# Login using Kubernetes auth
echo "Authenticating to Vault..."
VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login \
        role=vault-backup \
    jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token)

export VAULT_TOKEN

# Take snapshot
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="vault-snapshot-${DATE}.snap"

echo "Taking Raft snapshot..."
vault operator raft snapshot save /tmp/${BACKUP_FILE}

# Verify snapshot
echo "Verifying snapshot integrity..."
vault operator raft snapshot inspect /tmp/${BACKUP_FILE}

# Upload to MinIO
echo "Uploading to MinIO..."
aws --endpoint-url=$S3_ENDPOINT \
    s3 cp /tmp/${BACKUP_FILE} \
    s3://${S3_BUCKET}/${BACKUP_FILE}

# Verify upload
echo "Verifying upload..."
aws --endpoint-url=$S3_ENDPOINT \
    s3 ls s3://${S3_BUCKET}/${BACKUP_FILE}

# Optional: Keep only last 30 days of backups in S3
echo "Cleaning up old backups..."
RETENTION_SECONDS=$((${RETENTION_DAYS:-30} * 24 * 60 * 60))
CUTOFF_TIMESTAMP=$(($(date +%s) - $RETENTION_SECONDS))  # 30 days = 2592000 seconds
CUTOFF_DATE=$(date -d @${CUTOFF_TIMESTAMP} +%Y%m%d)
aws --endpoint-url=$S3_ENDPOINT \
    s3 ls s3://${S3_BUCKET}/ | \
    awk '{print $4}' | \
    grep '^vault-snapshot-' | \
    while read backup; do
    backup_date=$(echo $backup | sed 's/vault-snapshot-\([0-9]\{8\}\).*/\1/')
    if [ "$backup_date" -lt "$CUTOFF_DATE" ]; then
        echo "Deleting old backup: $backup"
        aws --endpoint-url=${S3_ENDPOINT} \
            s3 rm s3://${S3_BUCKET}/$backup
    fi
done

# Cleanup local file
rm /tmp/${BACKUP_FILE}

echo "Backup completed successfully at $(date)"
