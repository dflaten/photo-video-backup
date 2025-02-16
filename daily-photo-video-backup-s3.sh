#!/bin/bash

# Set variables
SOURCE_DIR="/path/to/your/photos/and/videos"
RCLONE_REMOTE="your-s3-remote"
BUCKET_PATH="your-bucket/backup"
LOG_FILE="/var/log/media_backup.log"
AWS_REGION="your-aws-region"  # e.g., us-east-1

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Start logging
echo "Starting backup at $(date)" >> "$LOG_FILE"

# Run rclone sync with specific settings
if rclone sync "$SOURCE_DIR" "$RCLONE_REMOTE:$BUCKET_PATH" \
    --include "*.{jpg,jpeg,png,gif,mp4,mov,avi,mkv,raw,cr2,arw,heic,heif}" \
    --ignore-existing \
    --s3-storage-class=DEEP_ARCHIVE \
    --log-file="$LOG_FILE" \
    --log-level INFO \
    --stats 30s \
    --stats-one-line; then

    # Emit success metric to CloudWatch
    aws cloudwatch put-metric-data \
        --region "$AWS_REGION" \
        --namespace "MediaBackup" \
        --metric-name "BackupSuccess" \
        --value 1 \
        --unit Count

    echo "Backup completed successfully at $(date)" >> "$LOG_FILE"
else
    # Emit failure metric to CloudWatch
    aws cloudwatch put-metric-data \
        --region "$AWS_REGION" \
        --namespace "MediaBackup" \
        --metric-name "BackupSuccess" \
        --value 0 \
        --unit Count

    echo "Backup failed at $(date)" >> "$LOG_FILE"
fi
