#!/bin/bash

# Auto-sync script for htdocs changes
# Watches for file changes and syncs to the nginx container

set -euo pipefail

# Get the directory of this script and set HTDOCS_DIR relative to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTDOCS_DIR="${SCRIPT_DIR}/helpers/navigator/htdocs"
DEBOUNCE_DELAY=1
LAST_SYNC=0
NAMESPACE="jam-in-a-box"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

sync_files() {
    local current_time
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
    pod_name=$(oc --namespace=${NAMESPACE} get po \
        --selector=app=navigator -o name | \
        sed -e 's/^[^\/]*\///' | head -1)
    
    if [[ -z "$pod_name" ]]; then
        log_message "ERROR: No pod found with selector " \
            "app=navigator"
        return 1
    fi
    
    log_message "Syncing to pod: $pod_name"
    
    # Execute the tar sync command
    if tar -C "$HTDOCS_DIR" -czf - . | \
        oc --namespace=${NAMESPACE} exec -i "$pod_name" -c nginx -- \
        tar -C /usr/share/nginx/html -xzf -; then
        LAST_SYNC=$(date +%s)
        log_message "✅ Sync completed successfully at " \
            "$(date '+%Y-%m-%d %H:%M:%S')"
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
        "$HTDOCS_DIR" | while read -r file event time; do
        log_message "File change: $file ($event) at $time"
        sync_files
    done
    
else
    # Fallback - polling method
    log_message "WARNING: Neither fswatch nor inotifywait found, " \
        "using polling method"
    log_message "Monitoring: $HTDOCS_DIR"
    
    last_check=0
    while true; do
        current_mtime=$(find "$HTDOCS_DIR" -type f \
            -exec stat -f "%m" {} \; 2>/dev/null | sort -n | tail -1)
        
        if [[ -z "$current_mtime" ]]; then
            current_mtime=0
        fi
        
        if (( current_mtime > last_check )); then
            log_message "File changes detected (mtime: $current_mtime)"
            sync_files
            last_check=$current_mtime
        fi
        
        sleep 2
    done
fi