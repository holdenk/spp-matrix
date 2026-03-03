#!/bin/sh
set -e

DATA_DIR="${DATA_DIR:-/data/backup}"
BACKUP_INTERVAL="${BACKUP_INTERVAL:-21600}"  # 6 hours default
RCLONE_REMOTE="${RCLONE_REMOTE:-b2}"
BUCKET="${BUCKET:?BUCKET env var is required}"
PREFIX="${PREFIX:-tuwunel}"
RCLONE_CONF="${RCLONE_CONF:-/config/rclone.conf}"

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $1"
}

restore_from_s3() {
  log "Checking if data directory needs restore..."
  if [ -z "$(ls -A "$DATA_DIR/" 2>/dev/null)" ]; then
    log "Data directory is empty. Attempting restore from ${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/"
    if rclone ls "${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/" --config "$RCLONE_CONF" --max-depth 1 2>/dev/null | head -1 | grep -q .; then
      log "Backup found. Restoring..."
      if rclone sync "${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/" "$DATA_DIR/" \
        --config "$RCLONE_CONF" \
        --transfers 4 \
        --checkers 8 \
        --log-level INFO; then
        log "Restore complete. Files restored:"
        ls -la "$DATA_DIR/"
      else
        log "WARNING: Restore failed with exit code $?. Starting with empty data."
      fi
    else
      log "No backup found in ${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/. Starting fresh."
    fi
  else
    log "Data directory is not empty. Skipping restore."
  fi
}

run_backup() {
  log "Starting backup to ${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/"
  if rclone copy "$DATA_DIR/" "${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/" \
    --config "$RCLONE_CONF" \
    --transfers 4 \
    --checkers 8 \
    --log-level INFO; then
    log "Backup completed successfully."
  else
    log "ERROR: Backup failed with exit code $?"
  fi
}

# Run restore check on startup
restore_from_s3

# Periodic backup loop
log "Starting backup loop. Interval: ${BACKUP_INTERVAL}s"
while true; do
  sleep "$BACKUP_INTERVAL"
  run_backup
done
