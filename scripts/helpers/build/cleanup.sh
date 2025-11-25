#!/bin/bash

set -e

# =============================================================================
# Cleanup Functions
# =============================================================================

function cleanup() {
  local resourceTypes globalParams
  
  if ! $doClean; then
    log_debug "Cleanup not requested, skipping"
    return 0
  fi
  
  log_header "Cleaning Up Existing Resources"
  
  # Clean up any materials loader/checker pods first
  cleanupMaterialsPods
  
  # Define resource types to clean up
  resourceTypes=(deployment route service secret configmap pod)
  
  # Add PVC to cleanup only if not in quick mode
  if [[ "$quickMode" != true ]]; then
    resourceTypes+=(pvc build buildconfig imagestream)
    log_info "Full cleanup mode - including ${resourceTypes[*]}"
  else
    log_info "Quick mode - preserving PVCs for faster restart"
  fi
  
  cleanupResourcesByType "${resourceTypes[@]}"
  log_success "Cleanup completed"
}

function cleanupMaterialsPods() {
  log_debug "Cleaning up materials loader/checker pods"
  
  oc delete pod \
    -l app="$LABEL_APP",component=materials-loader \
    -n "$NAMESPACE" --ignore-not-found=true
    
  oc delete pod \
    -l app="$LABEL_APP",component=materials-checker \
    -n "$NAMESPACE" --ignore-not-found=true
}

function cleanupResourcesByType() {
  local resourceTypes=("$@")
  local globalParams=(-n "$NAMESPACE" "--selector=$LABEL")
  local resourceType
  
  for resourceType in "${resourceTypes[@]}"; do
    log_debug "Checking for $resourceType resources to cleanup"
    if oc get "$resourceType" "${globalParams[@]}" &>/dev/null; then
      log_info "Deleting $resourceType resources"
      oc delete "$resourceType" "${globalParams[@]}"
    else
      log_debug "No $resourceType resources found to cleanup"
    fi
  done
}