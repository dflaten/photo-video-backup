#!/usr/bin/env bash
#
# Backup Immich media and database dumps to S3.
#
# Media is COPIED, never deleted: removing a photo from Immich, or a drive that
# fails to mount, cannot delete anything from the archive. Pruning is a manual
# operation (see README).
#
# Database dumps go to a separate prefix in Standard storage (not Deep Archive)
# so they can be restored in minutes instead of hours.

set -uo pipefail

# cron runs with a minimal PATH; add the usual install locations as fallbacks.
export PATH="${PATH:-/usr/local/bin:/usr/bin:/bin}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:${HOME}/.local/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"

if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "ERROR: config file $CONFIG_FILE is missing or unreadable." >&2
    echo "Copy config.example.txt to config.txt and edit it." >&2
    exit 1
fi

# shellcheck source=/dev/null
if ! source "$CONFIG_FILE"; then
    echo "ERROR: failed to load $CONFIG_FILE" >&2
    exit 1
fi

: "${SOURCE_DIR:?SOURCE_DIR must be set in config.txt}"
: "${BUCKET_PATH:?BUCKET_PATH must be set in config.txt}"
: "${AWS_REGION:?AWS_REGION must be set in config.txt}"

# Optional settings and defaults.
BUCKET_PATH="${BUCKET_PATH%/}"
LOG_DIRECTORY="${LOG_DIRECTORY:-./log}"
MIN_SOURCE_FILES="${MIN_SOURCE_FILES:-100}"
REQUIRE_MOUNT="${REQUIRE_MOUNT:-false}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-90}"
# Empty DB_BACKUP_DIR (not unset) disables database backups.
DB_BACKUP_DIR="${DB_BACKUP_DIR-$SOURCE_DIR/backups}"
DB_BACKUP_PREFIX="${DB_BACKUP_PREFIX:-backups/db}"
DB_BACKUP_GLOB="${DB_BACKUP_GLOB:-*.sql.gz}"
DB_BACKUP_MAX_AGE="${DB_BACKUP_MAX_AGE:-90d}"
DB_BACKUP_MIN_AGE="${DB_BACKUP_MIN_AGE:-5m}"
DB_BACKUP_FRESH_DAYS="${DB_BACKUP_FRESH_DAYS:-8}"

# Resolve relative paths against the script directory so manual runs and cron
# (which starts in $HOME) write to the same log directory.
if [[ "$LOG_DIRECTORY" != /* ]]; then
    LOG_DIRECTORY="$SCRIPT_DIR/$LOG_DIRECTORY"
fi

if ! mkdir -p "$LOG_DIRECTORY"; then
    echo "ERROR: cannot create log directory $LOG_DIRECTORY" >&2
    exit 1
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="${LOG_DIRECTORY}/${TIMESTAMP}.log"

# Only allow one run at a time. The initial upload of a large library can take
# longer than the gap between scheduled runs.
exec 9>"$LOG_DIRECTORY/.backup.lock"
if ! flock -n 9; then
    echo "Another backup run is already in progress; exiting." >&2
    exit 0
fi

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

emit_metric() {
    if ! aws cloudwatch put-metric-data \
        --region "$AWS_REGION" \
        --namespace "MediaBackup" \
        --metric-name "BackupSuccess" \
        --value "$1" \
        --unit Count; then
        log "WARNING: failed to publish CloudWatch metric ($1)."
    fi
}

fail() {
    log "ERROR: $1"
    emit_metric 0
    exit 1
}

log "Starting backup."
find "$LOG_DIRECTORY" -maxdepth 1 -type f -name '*.log' -mtime +"$LOG_RETENTION_DAYS" -delete 2>/dev/null

# Refuse to run if the source is missing, not mounted, or suspiciously small.
# With `rclone copy` nothing would be deleted, but a broken source still means
# a green run that backed up nothing.
if [[ ! -d "$SOURCE_DIR" ]]; then
    fail "Source directory $SOURCE_DIR does not exist."
fi

if [[ "$REQUIRE_MOUNT" == "true" ]] && ! mountpoint -q "$SOURCE_DIR"; then
    fail "Source directory $SOURCE_DIR is not a mountpoint; refusing to run."
fi

# Count only files that will actually be copied: a stale thumbs/ or backups/
# directory must not make a broken media source look healthy.
SOURCE_FILE_COUNT=$(find "$SOURCE_DIR" -mindepth 1 \
    -type d \( -name thumbs -o -name backups \) -prune -o \
    -type f -printf '.' 2>/dev/null | wc -c)
if (( SOURCE_FILE_COUNT < MIN_SOURCE_FILES )); then
    fail "Only $SOURCE_FILE_COUNT media files under $SOURCE_DIR (minimum $MIN_SOURCE_FILES); refusing to run."
fi
log "Source contains $SOURCE_FILE_COUNT media files."

# Only draw progress when attached to a terminal; otherwise it fills the log
# with repaint escape sequences.
PROGRESS_ARGS=()
if [[ -t 1 ]]; then
    PROGRESS_ARGS+=(--progress)
fi

MEDIA_RESULT=0
log "Copying media to $BUCKET_PATH (Deep Archive)."
# --size-only compares sizes instead of modification times. rclone normally
# compares the mtime metadata it stores in S3; size-only still repairs
# different-size objects without re-uploading the library if metadata is lost.
if rclone copy "$SOURCE_DIR" "$BUCKET_PATH" \
    --size-only \
    --exclude "/thumbs/**" \
    --exclude "**/thumbs/**" \
    --exclude "/backups/**" \
    --s3-storage-class=DEEP_ARCHIVE \
    --log-file="$LOG_FILE" \
    --log-level INFO \
    --stats 30s \
    "${PROGRESS_ARGS[@]}"; then
    log "Media copy finished."
else
    rc=$?
    MEDIA_RESULT=1
    log "ERROR: media copy failed (rclone exit $rc)."
fi

DB_RESULT=0
if [[ -z "$DB_BACKUP_DIR" ]]; then
    log "Database backup disabled (DB_BACKUP_DIR is empty)."
elif [[ ! -d "$DB_BACKUP_DIR" ]]; then
    DB_RESULT=1
    log "ERROR: database backup directory $DB_BACKUP_DIR does not exist."
elif ! compgen -G "$DB_BACKUP_DIR/$DB_BACKUP_GLOB" >/dev/null; then
    DB_RESULT=1
    log "ERROR: no $DB_BACKUP_GLOB dumps found in $DB_BACKUP_DIR."
elif [[ -z "$(find "$DB_BACKUP_DIR" -maxdepth 1 -type f -name "$DB_BACKUP_GLOB" \
        -mtime -"$DB_BACKUP_FRESH_DAYS" -print -quit 2>/dev/null)" ]]; then
    # Immich can silently stop writing dumps (or the path can change). Old
    # dumps would make the copy succeed without backing up anything current.
    DB_RESULT=1
    log "ERROR: no $DB_BACKUP_GLOB dump modified in the last $DB_BACKUP_FRESH_DAYS days in $DB_BACKUP_DIR."
else
    log "Copying database dumps to $BUCKET_PATH/$DB_BACKUP_PREFIX (Standard)."
    # Standard storage class so a restore does not need a 12-48h thaw,
    # --max-age so old dumps are not re-uploaded after lifecycle expiry, and
    # --min-age so a dump still being written is not uploaded half-finished.
    if rclone copy "$DB_BACKUP_DIR" "$BUCKET_PATH/$DB_BACKUP_PREFIX" \
        --include "$DB_BACKUP_GLOB" \
        --size-only \
        --max-age "$DB_BACKUP_MAX_AGE" \
        --min-age "$DB_BACKUP_MIN_AGE" \
        --s3-storage-class=STANDARD \
        --log-file="$LOG_FILE" \
        --log-level INFO \
        --stats 30s \
        "${PROGRESS_ARGS[@]}"; then
        log "Database copy finished."
    else
        rc=$?
        DB_RESULT=1
        log "ERROR: database copy failed (rclone exit $rc)."
    fi
fi

if (( MEDIA_RESULT == 0 && DB_RESULT == 0 )); then
    emit_metric 1
    log "Backup completed successfully."
    exit 0
fi

emit_metric 0
log "Backup failed (media=$MEDIA_RESULT db=$DB_RESULT)."
exit 1
