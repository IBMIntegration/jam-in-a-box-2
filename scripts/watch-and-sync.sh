#!/bin/bash

# Auto-sync script for htdocs changes
# Watches for file changes and syncs to the nginx container

set -euo pipefail

# Get the directory of this script and set HTDOCS_DIR relative to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTDOCS_DIR="$(cd "${SCRIPT_DIR}/../../jam-navigator/htdocs" && pwd)"
MATERIALS_DIR="$(cd "${SCRIPT_DIR}/../../jam-materials" && pwd)"
DEBOUNCE_DELAY=1
LAST_SYNC=0
NAMESPACE="jam-in-a-box"

log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

sync_files() {
  local current_time folder="$1" container_dir='' container_name='nginx'
  local detected_file="$2"
  current_time=$(date +%s)

  # Debounce: only sync if enough time has passed since last sync
  if (( current_time - LAST_SYNC < DEBOUNCE_DELAY )); then
    return 0
  fi

  if [[ "$detected_file" == "true" ]]; then
    log_message "File changes detected, syncing to archive-helper pod..."
  else
    log_message "Syncing to archive-helper pod..."
  fi

  # Wait for debounce period
  sleep $DEBOUNCE_DELAY

  # Get the pod name
  local pod_name

  if [[ "$folder" == "$HTDOCS_DIR" ]] || [[ "$folder" == "$HTDOCS_DIR"/* ]]
  then
    container_dir="/usr/share/nginx/html"
    container_name='nginx'
    folder="$HTDOCS_DIR"
    pod_name="archive-helper"
  elif [[ "$folder" == "$MATERIALS_DIR" ]] ||
       [[ "$folder" == "$MATERIALS_DIR"/* ]]
  then
    container_dir="/materials"
    container_name='nginx'
    folder="$MATERIALS_DIR"
    pod_name="archive-helper"
  else
    log_message "ERROR: Unknown folder to sync: $folder"
    log_message "Expected to be under:"
    log_message "  $HTDOCS_DIR or"
    log_message "  $MATERIALS_DIR"
    return 1
  fi

  log_message "Syncing to pod: $pod_name"
  log_message "Container: $container_name"

  # Execute the tar sync command
  # Use --no-xattrs to avoid macOS extended attribute warnings
  # Use --no-same-owner on extraction to avoid permission issues in OpenShift
  if tar -C "$folder" -czf - \
    --exclude='.git' --exclude='.DS_Store' \
    --exclude='*/._*' --exclude='._*' \
    --no-xattrs . | \
    oc --namespace=${NAMESPACE} exec -i "${pod_name}" -c "$container_name" -- \
    sh -c "tar -C '${container_dir}' -xzf - --no-same-owner && \
           chmod -R a+w '${container_dir}'"; then
    LAST_SYNC=$(date +%s)
    log_message "✅ Sync completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
  else
    log_message "❌ Sync failed"
    return 1
  fi
}

# Check if htdocs directory exists
if [[ ! -d "$HTDOCS_DIR" ]]; then
  log_message "ERROR: htdocs directory not found: $HTDOCS_DIR"
  exit 1
fi

# Poll files for changes
log_message "Monitoring: $HTDOCS_DIR"

sync_files "$HTDOCS_DIR" false
sync_files "$MATERIALS_DIR" false

last_check=0
while true; do
  current_mtime=$(find "$HTDOCS_DIR" -type f \
    -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1)

  if [[ -z "$current_mtime" ]]; then
    current_mtime=0
  fi

  if (( current_mtime > last_check )); then
    log_message "HTDOCS File changes detected (mtime: $current_mtime)"
    sync_files "$HTDOCS_DIR" true
    last_check=$current_mtime
  fi

  current_mtime=$(find "$MATERIALS_DIR" -type f \
    -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1)

  if [[ -z "$current_mtime" ]]; then
    current_mtime=0
  fi

  if (( current_mtime > last_check )); then
    log_message "MATERIALS File changes detected (mtime: $current_mtime)"
    sync_files "$MATERIALS_DIR" true
    last_check=$current_mtime
  fi

  sleep 2
done
