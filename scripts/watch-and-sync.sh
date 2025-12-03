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
  local current_time folder="$1" pod_folder=''
  current_time=$(date +%s)

  # Debounce: only sync if enough time has passed since last sync
  if (( current_time - LAST_SYNC < DEBOUNCE_DELAY )); then
    return 0
  fi

  log_message "File changes detected, syncing to nginx container..."

  # Wait for debounce period
  sleep $DEBOUNCE_DELAY

  # Get the pod name
  local pod_name
  pod_name=archive-helper
  if ! oc --namespace="${NAMESPACE}" get pod "archive-helper" >/dev/null 2>&1; then
    log_message "ERROR: No pod archive-helper found in namespace ${NAMESPACE}"
    return 1
  fi

  log_message "Syncing to pod: $pod_name"

  if [[ "$folder" == "$HTDOCS_DIR" ]] || [[ "$folder" == "$HTDOCS_DIR"/* ]]
  then
    pod_folder="/usr/share/nginx/html"
    folder="$HTDOCS_DIR"
  elif [[ "$folder" == "$MATERIALS_DIR" ]] ||
       [[ "$folder" == "$MATERIALS_DIR"/* ]]
  then
    pod_folder="/materials"
    folder="$MATERIALS_DIR"
  else
    log_message "ERROR: Unknown folder to sync: $folder"
    log_message "Expected to be under:"
    log_message "  $HTDOCS_DIR or"
    log_message "  $MATERIALS_DIR"
    return 1
  fi

  # Execute the tar sync command
  # Use --no-xattrs to avoid macOS extended attribute warnings
  # Use --no-same-owner on extraction to avoid permission issues in OpenShift
  if tar -C "$folder" -czf - \
    --exclude='.git' --exclude='.DS_Store' \
    --exclude='*/._*' --exclude='._*' \
    --no-xattrs . | \
    oc --namespace=${NAMESPACE} exec -i "$pod_name" -c nginx -- \
    sh -c "tar -C '${pod_folder}' -xzf - --no-same-owner --no-xattrs && \
           chmod -R a+w '${pod_folder}'"; then
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

# Check which file watcher is available
if command -v fswatch >/dev/null 2>&1; then
  # macOS - use fswatch
  log_message "Starting file watcher using fswatch..."
  log_message "Monitoring: $HTDOCS_DIR"

  fswatch -o -r --event Created --event Updated \
    --event Removed --event Renamed "$HTDOCS_DIR" | \
    while read -r _; do
      sync_files
    done

elif command -v inotifywait >/dev/null 2>&1; then
  # Linux - use inotifywait
  log_message "Starting file watcher using inotifywait..."
  log_message "Monitoring: $HTDOCS_DIR"

  inotifywait -m -r -e modify,create,delete,move \
    --format '%w%f %e %T' --timefmt '%Y-%m-%d %H:%M:%S' \
    "$HTDOCS_DIR" "$MATERIALS_DIR" | \
    while read -r file event time; do
      sync_files "$file"
    done

else
  # Fallback - polling method
  log_message "WARNING: Neither fswatch nor inotifywait found, using polling method"
  log_message "Monitoring: $HTDOCS_DIR"

  last_check=0
  while true; do
    current_mtime=$(find "$HTDOCS_DIR" -type f \
      -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1)

    if [[ -z "$current_mtime" ]]; then
      current_mtime=0
    fi

    if (( current_mtime > last_check )); then
      log_message "HTDOCS File changes detected (mtime: $current_mtime)"
      sync_files "$HTDOCS_DIR"
      last_check=$current_mtime
    fi

    current_mtime=$(find "$MATERIALS_DIR" -type f \
      -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1)

    if [[ -z "$current_mtime" ]]; then
      current_mtime=0
    fi

    if (( current_mtime > last_check )); then
      log_message "MATERIALS File changes detected (mtime: $current_mtime)"
      sync_files "$MATERIALS_DIR"
      last_check=$current_mtime
    fi

    sleep 2
  done
fi