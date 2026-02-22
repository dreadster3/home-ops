#!/bin/sh
set -e

# Install AWS CLI
echo "Installing Dependencies..."
apk add --no-cache aws-cli zip

echo "Starting backup at $(date)"

# Take snapshot
APPLICATION="uptime"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${APPLICATION}-${DATE}.zip"
FOLDER_TO_BACKUP="/data"

echo "Zipping ${FOLDER_TO_BACKUP}..."
zip -r /tmp/${BACKUP_FILE} ${FOLDER_TO_BACKUP}

# Upload to MinIO
echo "Uploading to S3..."
aws --endpoint-url=$S3_ENDPOINT \
    s3 cp /tmp/${BACKUP_FILE} \
    s3://${S3_BUCKET}/${BACKUP_FILE}

# Verify upload
echo "Verifying upload..."
aws --endpoint-url=$S3_ENDPOINT \
    s3 ls s3://${S3_BUCKET}/${BACKUP_FILE}

# Optional: Keep retention days of backups in S3
echo "Cleaning up old backups..."
RETENTION_SECONDS=$((${RETENTION_DAYS:-30} * 24 * 60 * 60))
CUTOFF_TIMESTAMP=$(($(date +%s) - $RETENTION_SECONDS))  # 30 days = 2592000 seconds
CUTOFF_DATE=$(date -d @${CUTOFF_TIMESTAMP} +%Y%m%d)
aws --endpoint-url=$S3_ENDPOINT \
    s3 ls s3://${S3_BUCKET}/ | \
    awk '{print $4}' | \
    grep "^${APPLICATION}-" | \
    while read backup; do
    backup_date=$(echo $backup | sed "s/${APPLICATION}-\([0-9]\{8\}\).*/\1/")
    if [ "$backup_date" -lt "$CUTOFF_DATE" ]; then
        echo "Deleting old backup: $backup"
        aws --endpoint-url=${S3_ENDPOINT} \
            s3 rm s3://${S3_BUCKET}/$backup
    fi
done

# Cleanup local file
rm /tmp/${BACKUP_FILE}

echo "Backup completed successfully at $(date)"
