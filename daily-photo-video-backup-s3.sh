#!/bin/bash

# Set variables from config.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"

source "$CONFIG_FILE"

# Resolve relative paths against the script directory so manual runs and cron
# (which starts in $HOME) write to the same log directory.
if [[ "$LOG_DIRECTORY" != /* ]]; then
    LOG_DIRECTORY="$SCRIPT_DIR/$LOG_DIRECTORY"
fi

# Ensure log directory exists
mkdir -p "$LOG_DIRECTORY"

# Start logging
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="${LOG_DIRECTORY}/${TIMESTAMP}.log"

echo "Starting backup at $(date)" >> "$LOG_FILE"

emit_metric() {
    aws cloudwatch put-metric-data \
        --region "$AWS_REGION" \
        --namespace "MediaBackup" \
        --metric-name "BackupSuccess" \
        --value "$1" \
        --unit Count
}

fail() {
    echo "$1" >> "$LOG_FILE"
    emit_metric 0
    exit 1
}

# Refuse to run if the source is missing or empty. Without this, a drive that
# failed to mount would make rclone sync delete the entire remote backup
# (and Deep Archive deletes before 180 days are also billed).
if [ ! -d "$SOURCE_DIR" ] || [ -z "$(find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
    fail "Source directory $SOURCE_DIR is missing or empty; refusing to sync."
fi

# Only draw progress when attached to a terminal; otherwise it fills the log
# with repaint escape sequences.
PROGRESS_ARGS=()
if [ -t 1 ]; then
    PROGRESS_ARGS+=(--progress)
fi

# Run rclone sync with specific settings
# TEST WITH --dry-run (https://rclone.org/docs/)
if rclone sync "$SOURCE_DIR" "$BUCKET_PATH" \
    --ignore-existing \
    --exclude "**/thumbs/**" \
    --max-delete 100 \
    --s3-storage-class=DEEP_ARCHIVE \
    --log-file="$LOG_FILE" \
    --log-level INFO \
    --stats 30s \
    "${PROGRESS_ARGS[@]}"; then

    # Emit success metric to CloudWatch
    emit_metric 1

    echo "Backup completed successfully at $(date)" >> "$LOG_FILE"
else
    # Emit failure metric to CloudWatch
    emit_metric 0

    echo "Backup failed at $(date)" >> "$LOG_FILE"
    exit 1
fi
