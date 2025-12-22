#!/bin/bash

# Auto-sync script for htdocs changes
# Watches for file changes and syncs to the nginx container

set -euo pipefail

# Get the directory of this script and set HTDOCS_DIR relative to it
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTDOCS_DIR="$(cd "${SCRIPT_DIR}/../../jam-navigator/htdocs" && pwd)"
MATERIALS_DIR="$(cd "${SCRIPT_DIR}/../../jam-materials" && pwd)"
NAMESPACE="jam-in-a-box"

# these are either true/false or arrays of directories to scan
debugMode="${DEBUG:-false}"
doScanHtdocs=''
doScanMaterials=''
skipInitialSync=false

lastLogIsAScan=false

for arg in "$@"; do
  case $arg in
    --debug)
      debugMode="true"
      ;;
    --debug=*)
      debugMode="${arg#*=}"
      ;;
    -q|--quick|--skip-initial-sync)
      skipInitialSync=$arg
      ;;
    --scan-htdocs)
      doScanHtdocs=true
      ;;
    --scan-htdocs=*)
      value="${arg#*=}"
      if [ "$value" == "true" ]; then
        doScanHtdocs=true
      elif [ "$value" == "false" ]; then
        doScanHtdocs=false
      else
        IFS=',' read -r -a dirs <<< "$value"
        doScanHtdocs=("${dirs[@]}")
      fi
      ;;
    --scan-materials)
      doScanMaterials=true
      ;;
    --scan-materials=*)
      value="${arg#*=}"
      if [ "$value" == "true" ]; then
        doScanMaterials=true
      elif [ "$value" == "false" ]; then
        doScanMaterials=false
      else
        IFS=',' read -r -a dirs <<< "$value"
        doScanMaterials=("${dirs[@]}")
      fi
      ;;
  esac
done

if [ -z "${doScanHtdocs[*]}" ] && [ -z "${doScanMaterials[*]}" ]; then
  doScanHtdocs=true
  doScanMaterials=true
elif [ -z "${doScanHtdocs[*]}" ]; then
  doScanHtdocs=false
elif [ -z "${doScanMaterials[*]}" ]; then
  doScanMaterials=false
fi

# the total list of directories to scan, calculated from the above settings
dirsToScan=()
# calculate dirsToScan based on the settings
if [ "${doScanHtdocs[*]}" == true ]; then
  dirsToScan+=("$HTDOCS_DIR")
elif [ -n "${doScanHtdocs+x}" ] && [ "${doScanHtdocs[*]}" != false ]; then
  dirsToScan+=("${doScanHtdocs[@]}")
fi
if [ "${doScanMaterials[*]}" == true ]; then
  dirsToScan+=("$MATERIALS_DIR")
elif [ -n "${doScanMaterials+x}" ] && [ "${doScanMaterials[*]}" != false ]
then
  dirsToScan+=("${doScanMaterials[@]}")
fi

function debug_message {
  if [[ "${debugMode:-false}" == "true" ]]; then
    if [ "${lastLogIsAScan}" == "true" ]; then
      echo ''
      lastLogIsAScan=false
    fi
    echo "[$(date '+           %H:%M:%S')] $*"
  fi
}

function getPathType {
  if [[ "$1" == "$HTDOCS_DIR" ]] || [[ "$1" == "$HTDOCS_DIR/*" ]]; then
    echo "htdocs"
  elif [[ "$1" == "$MATERIALS_DIR" ]] || [[ "$1" == "$MATERIALS_DIR/*" ]]; then
    echo "materials"
  fi
}

function log_message {
  if [ "${lastLogIsAScan}" == "true" ]; then
    echo ''
    lastLogIsAScan=false
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

function log_scan {
  local c='▷'
  if [ "$1" == "start" ]; then
    c='◀︎'
  fi
  if [ "$lastLogIsAScan" == "false" ]; then
    lastLogIsAScan=true
  fi
  echo -n "$c"
}

# Check if htdocs directory exists
if [[ ! -d "$HTDOCS_DIR" ]]; then
  log_message "ERROR: htdocs directory not found: $HTDOCS_DIR"
  exit 1
fi

function scanForUpdates {
  local sinceMTime="$1"
  local folder="$2"

  # Find all regular files modified since the given mtime. If a file other
  # than a regular file (e.g. a directory created) is found modified, log the
  # changed filename to stderr but do not return it as part of the output.
  local dateStr
  dateStr=$(date -r "$sinceMTime" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00")
  find "$folder" -type f -newermt "$dateStr" -print 2>/dev/null | \
    while read -r file; do
      if [[ ! -f "$file" ]]; then
        local file_type
        if [[ -d "$file" ]]; then
          file_type="directory"
        elif [[ -L "$file" ]]; then
          file_type="symlink"
        elif [[ -b "$file" ]]; then
          file_type="block device"
        elif [[ -c "$file" ]]; then
          file_type="character device"
        elif [[ -p "$file" ]]; then
          file_type="named pipe"
        elif [[ -S "$file" ]]; then
          file_type="socket"
        else
          file_type="unknown"
        fi
        echo "Non-regular file modified ($file_type): $file" >&2
      else
        echo "$file"
      fi
    done
}

# sync a single file to the pod
function sync_file {
  local file="$1"
  local container_name='nginx'
  local pod_name='archive-helper'
  local remoteBaseFolder=''
  local relativePath=''
  local fileType=''

  if [[ "$file" == "$HTDOCS_DIR"/* ]]
  then
    remoteBaseFolder="/usr/share/nginx/html"
    relativePath="${file#"$HTDOCS_DIR"/}"
    fileType='htdocs'
  elif [[ "$file" == "$MATERIALS_DIR"/* ]]
  then
    remoteBaseFolder="/materials"
    relativePath="${file#"$MATERIALS_DIR"/}"
    fileType='materials'
  else
    log_message "ERROR: Unknown folder to sync: $file"
    log_message "Expected to be under:"
    log_message "  $HTDOCS_DIR or"
    log_message "  $MATERIALS_DIR"
    return 1
  fi

  log_message "Syncing file: ($fileType)/$relativePath to $remoteBaseFolder/$relativePath"
  oc cp -n $NAMESPACE -c "$container_name" \
    "$file" \
    "$pod_name:$remoteBaseFolder/$relativePath"
}

# sync all the files to the pod
function sync_files {
  local localFolder='' container_dir=''
  local relativePath remotePath=''
  local pathType=''
  local podName='archive-helper' container_name='nginx'
  local scanDir

  log_message "Full sync to archive-helper pod..."

  for scanDir in "${dirsToScan[@]}"; do
    log_message " --> full sync on directory: $scanDir"
    pathType=$(getPathType "$scanDir")
    if [ "${pathType}" == "htdocs" ]; then
      container_dir="/usr/share/nginx/html"
      localFolder="$HTDOCS_DIR"
    elif [ "${pathType}" == "materials" ]; then
      container_dir="/materials"
      localFolder="$MATERIALS_DIR"
    fi
    if [ "${localFolder}" == "$scanDir" ]; then
      relativePath="."
      remotePath="${container_dir}"
    else
      relativePath="${scanDir#"$localFolder"/}"
      remotePath="${container_dir}/$relativePath"
    fi

    debug_message scanDir = "$scanDir"
    debug_message container_dir = "$container_dir"
    debug_message remotePath = "$remotePath"
    debug_message relativePath = "$relativePath"

    log_message "Syncing folder ($pathType): $relativePath"

    # Execute the tar sync command
    # Use --no-xattrs to avoid macOS extended attribute warnings
    # Use --no-same-owner on extraction to avoid permission issues in OpenShift
    if tar -C "$scanDir" -czf - \
      --exclude='.git' --exclude='.DS_Store' \
      --exclude='*/._*' --exclude='._*' \
      --no-xattrs . | \
      oc --namespace=${NAMESPACE} exec -i "${podName}" -c "$container_name" -- \
      sh -c "tar -C '${remotePath}' -xzf - --no-same-owner && \
            chmod -R a+w '${remotePath}'"; then
      log_message "✅ Sync completed successfully at $(date '+%Y-%m-%d %H:%M:%S')"
    else
      log_message "❌ Sync failed"
      return 1
    fi
  done
  relativePath="${folder#"$HTDOCS_DIR"/}"

  log_message "Completed full sync to archive-helper pod..."
}

debug_message HTDOCS_DIR = "$HTDOCS_DIR"
debug_message MATERIALS_DIR = "$MATERIALS_DIR"
debug_message dirsToScan = "${dirsToScan[@]}"

# initial full sync
lastSync=$(date +%s)
if [ "${skipInitialSync}" == "false" ]; then
  log_message "Performing initial full sync..."
  sync_files
  log_message "Initial full sync completed."
else
  log_message "Skipping initial full sync as per ${skipInitialSync} flag."
fi

debug_message "Initial sync completed at $lastSync"

while true; do
  scanTime=$(date +%s)

  log_scan start
  for d in "${dirsToScan[@]}"; do
    debug_message "Scanning directory for changes since $lastSync: $d"
    for update in $(scanForUpdates "$lastSync" "$d" || true); do
      debug_message " --> Modified file detected: $update"
      sync_file "$update"
    done
  done
  if [ "${lastLogIsAScan}" == "true" ]; then
    log_scan end
  fi

  lastSync=$scanTime
  sleep 2
done
