#!/bin/bash

set -e

# =============================================================================
# Registry Management Functions
# =============================================================================

function checkRegistryOperator() {
  local registryAvailable managementState storageConfigured
  
  log_debug "Checking if registry operator exists"
  if ! oc get clusteroperator image-registry >/dev/null 2>&1; then
    log_error "Registry operator not found"
    return 1
  fi
  
  log_debug "Checking registry operator availability status"
  registryAvailable=$(oc get clusteroperator image-registry -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
  
  log_debug "Checking registry management state"
  managementState=$(oc get config.imageregistry cluster -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "")
  
  log_debug "Checking registry storage configuration"
  storageConfigured=$(oc get config.imageregistry cluster -o jsonpath='{.spec.storage}' 2>/dev/null || echo "{}")

  if [[ "$registryAvailable" != "True" ]]; then
    log_error "Registry operator found but not available (status: $registryAvailable)"
    return 1
  fi

  if [[ "$managementState" != "Managed" ]]; then
    log_error "Registry management state is not 'Managed' (current: $managementState)"
    return 1
  fi

  if [[ "$storageConfigured" == "{}" ]]; then
    log_error "Registry storage is not configured"
    return 1
  fi

  # Check for persistent storage (PVC)
  if ! echo "$storageConfigured" | grep -q 'pvc'; then
    log_error "Registry storage is not set to PVC (persistent storage)"
    return 1
  fi

  log_debug "Registry operator is available and properly configured for persistent storage (PVC)"
  log_debug "Management state: $managementState"
  log_debug "Storage config: $storageConfigured"
  return 0
}

function enableInternalRegistry() {
  log_subheader "Enabling internal registry with persistent storage (PVC)"

  log_debug "Patching registry config to Managed state with PVC storage (default StorageClass)"
  if ! oc patch config.imageregistry cluster --type merge --patch='{"spec":{"managementState":"Managed","storage":{"pvc":{}}}}'; then
    log_error "Failed to patch registry configuration for PVC storage"
    return 1
  fi

  # Wait for PVC to be created and bound
  log_info "Waiting for PVC to be created (up to 3 minutes)..."
  local pvc_created=false
  for i in {1..36}; do
    if oc get pvc -n openshift-image-registry 2>/dev/null | grep -q "image-registry-storage"; then
      pvc_created=true
      log_debug "PVC created, waiting for it to be bound..."
      break
    fi
    sleep 5
  done

  if [[ "$pvc_created" == "false" ]]; then
    log_error "PVC was not created within timeout"
    return 1
  fi

  # Wait for PVC to be bound
  log_info "Waiting for PVC to be bound (up to 5 minutes)..."
  if ! oc wait --for=jsonpath='{.status.phase}'=Bound pvc/image-registry-storage -n openshift-image-registry --timeout=300s 2>/dev/null; then
    log_error "PVC failed to bind within timeout"
    log_debug "PVC status:"
    oc describe pvc image-registry-storage -n openshift-image-registry 2>/dev/null || true
    return 1
  fi

  log_success "PVC is bound and ready"

  # Wait for registry deployment to be created
  log_info "Waiting for registry deployment to be created (up to 2 minutes)..."
  local deploy_created=false
  for i in {1..24}; do
    if oc get deployment image-registry -n openshift-image-registry >/dev/null 2>&1; then
      deploy_created=true
      log_debug "Registry deployment created"
      break
    fi
    sleep 5
  done

  if [[ "$deploy_created" == "false" ]]; then
    log_error "Registry deployment was not created within timeout"
    return 1
  fi

  # Wait for registry pod to be ready
  log_info "Waiting for registry pod to be ready (up to 5 minutes)..."
  if ! oc rollout status deployment/image-registry -n openshift-image-registry --timeout=300s; then
    log_error "Registry deployment failed to become ready"
    log_debug "Pod status:"
    oc get pods -n openshift-image-registry -l docker-registry=default 2>/dev/null || true
    log_debug "Pod events:"
    oc get events -n openshift-image-registry --sort-by=.metadata.creationTimestamp | tail -20 || true
    return 1
  fi

  log_success "Registry pod is ready"

  # Wait for cluster operator to report Available
  log_info "Waiting for registry operator to report Available (up to 3 minutes)..."
  if ! oc wait --for=condition=Available clusteroperator/image-registry --timeout=180s; then
    log_error "Registry operator failed to report Available within timeout"
    return 1
  fi

  # Additional stabilization wait
  log_info "Waiting for registry to fully stabilize..."
  sleep 20

  log_success "Registry is now available with persistent storage (PVC)"
  return 0
}

function ensureInternalRegistry() {
  log_header "Ensuring OpenShift Internal Registry"
  
  if checkRegistryOperator; then
    log_success "Registry is already available"
  else
    if ! enableInternalRegistry; then
      return 1
    fi
  fi
  
  if ! ensureRegistryRoute; then
    return 1
  fi
  
  if ! verifyRegistryDeployment; then
    return 1
  fi
  
  if ! validateImageStreamConfiguration; then
    return 1
  fi
  
  # Force build controller to refresh its registry configuration
  if ! forceRegistryRefresh; then
    return 1
  fi
  
  # Verify build controller can process builds
  if ! verifyBuildControllerReady; then
    return 1
  fi
  
  log_success "Internal registry is fully configured and ready for ImageStreams"
  return 0
}

function verifyBuildControllerReady() {
  log_subheader "Verifying build controller can process builds"
  
  # Check if openshift-controller-manager namespace exists
  if ! oc get namespace openshift-controller-manager >/dev/null 2>&1; then
    log_warning "openshift-controller-manager namespace not found"
    log_info "This may be OKD, CRC, or a different OpenShift variant"
    log_info "Build controller may be in a different location - will attempt builds anyway"
    return 0
  fi
  
  # Check if build controller pods are running (simplified check)
  local controllerReady
  controllerReady=$(oc get pods -n openshift-controller-manager \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l || echo "0")
  
  if [[ "$controllerReady" -eq 0 ]]; then
    log_warning "No running controller manager pods found"
    log_info "Checking what exists in the namespace:"
    oc get pods -n openshift-controller-manager 2>/dev/null || true
    log_info "Will attempt builds anyway - if they fail, the build diagnostics will show why"
    return 0
  fi
  
  log_debug "Controller manager pods running: $controllerReady"
  log_debug "Build controller appears ready"
  return 0
}

function ensureRegistryRoute() {
  local i
  
  log_debug "Checking if default route exists for registry"
  if oc get route default-route -n openshift-image-registry >/dev/null 2>&1; then
    log_debug "Registry route already exists"
    return 0
  fi
  
  log_subheader "Creating default route for registry"
  
  log_debug "Enabling defaultRoute in registry config"
  if ! oc patch config.imageregistry cluster --type merge --patch='{"spec":{"defaultRoute":true}}'; then
    log_error "Failed to enable default route for registry"
    return 1
  fi
  
  log_info "Waiting for registry route to be created..."
  for i in {1..30}; do
    if oc get route default-route -n openshift-image-registry >/dev/null 2>&1; then
      log_success "Registry route created"
      return 0
    fi
    log_debug "Waiting for registry route... (attempt $i/30)"
    sleep 5
  done
  
  log_error "Failed to create registry route within timeout"
  return 1
}

function forceRegistryRefresh() {
  log_subheader "Forcing build controller to refresh registry configuration"
  
  # Delete any stuck builds first
  log_debug "Cleaning up any stuck builds in 'New' state"
  oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | \
    awk '$3=="New" {print $1}' | \
    xargs -r oc delete build -n "$NAMESPACE" 2>/dev/null || true
  
  # Force restart of openshift-controller-manager pods to refresh registry state
  log_info "Restarting openshift-controller-manager to refresh registry configuration"
  if oc get pods -n openshift-controller-manager >/dev/null 2>&1; then
    oc delete pods -n openshift-controller-manager --all --wait=false >/dev/null 2>&1 || true
    log_info "Waiting for controller manager to restart (up to 2 minutes)..."
    
    # Wait for pods to be recreated
    sleep 5
    for i in {1..24}; do
      READY_COUNT=$(oc get pods -n openshift-controller-manager \
        -l app=openshift-controller-manager \
        -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready" && @.status=="True")])].metadata.name}' \
        2>/dev/null | wc -w || echo "0")
      
      if [[ "$READY_COUNT" -gt 0 ]]; then
        log_success "Controller manager restarted ($READY_COUNT pod(s) ready)"
        break
      fi
      log_debug "Waiting for controller manager pods to be ready... (attempt $i/24)"
      sleep 5
    done
    
    # Additional stabilization time for build controller to reconnect to registry
    log_info "Allowing build controller to reconnect to registry..."
    sleep 15
  else
    log_warning "Could not find openshift-controller-manager pods"
  fi
  
  log_success "Registry refresh completed"
  return 0
}

function validateImageStreamConfiguration() {
  local registryService registryHost
  
  log_debug "Validating ImageStream configuration for namespace: $NAMESPACE"
  
  # Check if the internal registry service exists
  if ! oc get service image-registry -n openshift-image-registry >/dev/null 2>&1; then
    log_error "Registry service not found in openshift-image-registry namespace"
    return 1
  fi
  
  # Get the registry service cluster IP
  registryService=$(oc get service image-registry -n openshift-image-registry -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
  if [[ -z "$registryService" ]]; then
    log_error "Could not determine registry service cluster IP"
    return 1
  fi
  
  # Check if we can resolve the internal registry hostname
  registryHost="image-registry.openshift-image-registry.svc:5000"
  log_debug "Internal registry should be accessible at: $registryHost"
  
  # Verify namespace exists and we have access to it
  if ! oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
    log_error "Target namespace '$NAMESPACE' does not exist or is not accessible"
    return 1
  fi
  
  # Check if we have permissions to create ImageStreams in the target namespace
  if ! oc auth can-i create imagestreams -n "$NAMESPACE" >/dev/null 2>&1; then
    log_error "No permission to create ImageStreams in namespace '$NAMESPACE'"
    return 1
  fi
  
  # Test if registry is actually accepting ImageStream outputs by checking config
  local registryConfig
  registryConfig=$(oc get config.imageregistry cluster -o json 2>/dev/null || echo "{}")
  if echo "$registryConfig" | jq -r '.spec.managementState' | grep -q "Managed"; then
    log_debug "Registry management state confirmed as Managed"
  else
    log_error "Registry management state is not Managed"
    return 1
  fi
  
  # Wait a bit more and check if any builds are stuck in New state
  if oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | grep -q "New"; then
    log_info "Detected existing builds in 'New' state, waiting for registry to settle..."
    sleep 30
  fi
  
  log_debug "ImageStream configuration validation passed"
  log_debug "Registry service IP: $registryService"
  log_debug "Registry internal host: $registryHost"
  return 0
}

function verifyRegistryDeployment() {
  local registryReplicas
  
  log_debug "Checking if registry deployment exists"
  if ! oc get deployment image-registry -n openshift-image-registry >/dev/null 2>&1; then
    log_error "Registry deployment not found"
    return 1
  fi
  
  log_debug "Checking registry deployment readiness"
  registryReplicas=$(oc get deployment image-registry -n openshift-image-registry -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
  
  if [[ "$registryReplicas" == "0" ]] || [[ -z "$registryReplicas" ]]; then
    log_info "Waiting for registry deployment to be ready..."
    if ! oc rollout status deployment/image-registry -n openshift-image-registry --timeout=180s; then
      log_error "Registry deployment failed to become ready"
      return 1
  fi
  fi
  
  log_debug "Registry deployment is ready with $registryReplicas replica(s)"
  return 0
}
