#!/bin/sh
set -e

BACKUP_INTERVAL="${BACKUP_INTERVAL:-21600}"  # 6 hours default
RCLONE_REMOTE="${RCLONE_REMOTE:-b2}"
BUCKET="${BUCKET:?BUCKET env var is required}"
PREFIX="${PREFIX:-tuwunel}"
RCLONE_CONF="${RCLONE_CONF:-/config/rclone.conf}"

ADMIN_TOKEN="${ADMIN_TOKEN:?ADMIN_TOKEN env var is required}"
TUWUNEL_URL="${TUWUNEL_URL:-http://localhost:6167}"
SERVER_NAME="${SERVER_NAME:?SERVER_NAME env var is required}"

BACKUP_PATH="/data/backup"
MEDIA_PATH="/data/db/media"

log() {
  echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $1"
}

resolve_admin_room() {
  alias_encoded=$(printf '%s' "#admins:${SERVER_NAME}" | sed 's/#/%23/g; s/:/%3A/g')

  response=$(curl -sf \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${TUWUNEL_URL}/_matrix/client/v3/directory/room/${alias_encoded}") || {
    log "ERROR: Failed to resolve admin room alias #admins:${SERVER_NAME}"
    return 1
  }

  echo "$response" | jq -r '.room_id'
}

trigger_backup() {
  room_id="$1"
  txn_id="backup_$(date +%s)"

  room_id_encoded=$(printf '%s' "$room_id" | jq -sRr @uri)

  curl -sf \
    -X PUT \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"msgtype":"m.text","body":"!admin server backup_database"}' \
    "${TUWUNEL_URL}/_matrix/client/v3/rooms/${room_id_encoded}/send/m.room.message/${txn_id}" \
    > /dev/null || {
    log "ERROR: Failed to send backup command to admin room"
    return 1
  }

  log "Backup command sent successfully (txn: ${txn_id})"
}

run_backup() {
  log "=== Starting backup cycle ==="

  log "Resolving admin room alias..."
  room_id=$(resolve_admin_room) || return 1
  if [ -z "$room_id" ] || [ "$room_id" = "null" ]; then
    log "ERROR: Could not resolve admin room ID"
    return 1
  fi
  log "Admin room ID: ${room_id}"

  log "Triggering RocksDB backup via admin API..."
  trigger_backup "$room_id" || return 1

  log "Waiting 30s for backup snapshot to complete..."
  sleep 30

  if [ -d "$BACKUP_PATH" ] && [ -n "$(ls -A "$BACKUP_PATH" 2>/dev/null)" ]; then
    log "Uploading RocksDB backup from ${BACKUP_PATH}..."
    if rclone copy "$BACKUP_PATH/" "${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/backup/" \
      --config "$RCLONE_CONF" \
      --transfers 4 \
      --checkers 8 \
      --log-level INFO; then
      log "RocksDB backup upload completed."
    else
      log "ERROR: RocksDB backup upload failed with exit code $?"
    fi
  else
    log "WARNING: Backup path ${BACKUP_PATH} is empty or missing. Skipping RocksDB upload."
  fi

  if [ -d "$MEDIA_PATH" ]; then
    log "Uploading media files from ${MEDIA_PATH}..."
    if rclone copy "$MEDIA_PATH/" "${RCLONE_REMOTE}:${BUCKET}/${PREFIX}/media/" \
      --config "$RCLONE_CONF" \
      --transfers 4 \
      --checkers 8 \
      --log-level INFO; then
      log "Media backup upload completed."
    else
      log "ERROR: Media backup upload failed with exit code $?"
    fi
  else
    log "WARNING: Media path ${MEDIA_PATH} does not exist. Skipping media upload."
  fi

  log "=== Backup cycle complete ==="
}

log "Starting backup loop. Interval: ${BACKUP_INTERVAL}s"
log "Tuwunel URL: ${TUWUNEL_URL}"
log "Server name: ${SERVER_NAME}"

while true; do
  sleep "$BACKUP_INTERVAL"
  run_backup || log "Backup cycle failed. Will retry next interval."
done
