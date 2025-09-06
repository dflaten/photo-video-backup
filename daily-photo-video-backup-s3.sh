#!/bin/bash

# Set variables from config.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"

source "$CONFIG_FILE"
# Ensure log directory exists
mkdir -p "$(dirname "$LOG_DIR")"

# Start logging
TIMESTAMP=$(date +%s)
LOG_FILE="${LOG_DIRECTORY}/${TIMESTAMP}.log"

echo "Starting backup at $(date)" >> "$LOG_FILE"

# Run rclone sync with specific settings
#TODO: TEST WITH --dry-run (https://rclone.org/docs/)
if rclone sync "$SOURCE_DIR" "$RCLONE_REMOTE:$BUCKET_PATH" \
    --ignore-existing \
    --s3-storage-class=DEEP_ARCHIVE \
    --log-file="$LOG_FILE" \
    --log-level INFO \
    --stats 30s ; then

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
