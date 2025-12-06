#!/bin/bash
# Reset Jam-in-a-Box Environment
# This script:
# 1. Deletes the jam-in-a-box namespace
# 2. Removes the image registry configuration and PVC
# 3. Returns the registry to the default "Removed" state

set -e

# Color output functions
error() {
  echo "ERROR: $*" >&2
}

info() {
  echo "$*"
}

success() {
  echo "✓ $*"
}

warning() {
  echo "⚠️  WARNING: $*"
}

# Retry function for resilient operations
retry_command() {
  local max_attempts=2
  local delay=5
  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    if "$@"; then
      return 0
    else
      echo "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
      sleep $delay
      attempt=$((attempt + 1))
    fi
  done
  echo "All $max_attempts attempts failed"
  return 1
}

info "=== Jam-in-a-Box Environment Reset Script ==="
echo

# Step 0: Delete jam-in-a-box namespace
info "Step 0: Deleting jam-in-a-box namespace..."
if kubectl get namespace jam-in-a-box >/dev/null 2>&1; then
  info "Namespace exists, deleting..."
  if kubectl delete namespace jam-in-a-box --timeout=120s; then
    success "Namespace deleted"
    
    # Wait for namespace to be fully removed
    info "Waiting for namespace to be fully removed..."
    for i in {1..30}; do
      if ! kubectl get namespace jam-in-a-box >/dev/null 2>&1; then
        success "Namespace fully removed"
        break
      fi
      info "Waiting for namespace deletion (attempt $i/30)..."
      sleep 2
    done
    
    if kubectl get namespace jam-in-a-box >/dev/null 2>&1; then
      error "Namespace still exists after 60 seconds - cannot proceed safely"
      info "Checking for stuck resources..."
      kubectl get all -n jam-in-a-box 2>/dev/null || true
      info ""
      info "Try manually removing finalizers:"
      info "  kubectl patch namespace jam-in-a-box -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"
      exit 1
    fi
  else
    error "Failed to delete namespace"
    exit 1
  fi
else
  success "Namespace does not exist (already clean)"
fi
echo

# Step 1: Check current registry state
info "Step 1: Checking current image registry configuration..."
REGISTRY_STATE=$(retry_command kubectl get \
  config.imageregistry.operator.openshift.io/cluster \
  -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "Unknown")
STORAGE_CONFIG=$(retry_command kubectl get \
  config.imageregistry.operator.openshift.io/cluster \
  -o jsonpath='{.spec.storage}' 2>/dev/null || echo "{}")

info "Current registry state: $REGISTRY_STATE"
info "Current storage config: $STORAGE_CONFIG"
echo

# Step 2: Set registry to Removed state
info "Step 2: Setting image registry to Removed state..."
if retry_command kubectl patch \
  config.imageregistry.operator.openshift.io/cluster \
  --type merge -p '{"spec":{"managementState":"Removed","storage":{}}}'; then
  success "Registry set to Removed state"
else
  error "Failed to set registry to Removed state"
  exit 1
fi
echo

# Step 3: Wait for registry deployment to be deleted
info "Step 3: Waiting for registry deployment to be removed..."
DEPLOYMENT_REMOVED=false
for i in {1..30}; do
  if kubectl get deployment image-registry -n openshift-image-registry >/dev/null 2>&1; then
    info "Waiting for deployment deletion (attempt $i/30)..."
    sleep 2
  else
    success "Registry deployment removed"
    DEPLOYMENT_REMOVED=true
    break
  fi
done

if [ "$DEPLOYMENT_REMOVED" = "false" ]; then
  warning "Registry deployment still exists after 60 seconds"
  kubectl get deployment image-registry -n openshift-image-registry 2>&1 || true
fi
echo

# Step 4: Delete any existing PVCs
info "Step 4: Removing image registry PVCs..."
PVC_COUNT=$(retry_command kubectl get pvc -n openshift-image-registry \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w || echo "0")

if [ "$PVC_COUNT" -gt 0 ]; then
  info "Found $PVC_COUNT PVC(s) to delete"
  retry_command kubectl get pvc -n openshift-image-registry
  
  # Delete all PVCs in the namespace
  if retry_command kubectl delete pvc --all -n openshift-image-registry; then
    success "PVCs deleted"
    
    # Wait for PVCs to be fully removed
    info "Waiting for PVCs to be fully removed..."
    for i in {1..30}; do
      REMAINING=$(retry_command kubectl get pvc -n openshift-image-registry \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w || echo "0")
      if [ "$REMAINING" -eq 0 ]; then
        success "All PVCs removed"
        break
      fi
      info "Waiting for PVC deletion (attempt $i/30)..."
      sleep 2
    done
  else
    warning "Failed to delete PVCs, they may need manual cleanup"
  fi
else
  success "No PVCs found to delete"
fi
echo

# Step 5: Verify final state
info "Step 5: Verifying final state..."
echo

info "Registry configuration:"
FINAL_STATE=$(retry_command kubectl get \
  config.imageregistry.operator.openshift.io/cluster \
  -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "Unknown")
FINAL_STORAGE=$(retry_command kubectl get \
  config.imageregistry.operator.openshift.io/cluster \
  -o jsonpath='{.spec.storage}' 2>/dev/null || echo "{}")

info "  Management State: $FINAL_STATE"
info "  Storage Config: $FINAL_STORAGE"

if [ "$FINAL_STATE" == "Removed" ] && [ "$FINAL_STORAGE" == "{}" ]; then
  success "Registry is in Removed state with no storage configured"
else
  if [ "$FINAL_STORAGE" != "{}" ]; then
    warning "Storage config is not empty, attempting to clear it..."
    if retry_command kubectl patch \
      config.imageregistry.operator.openshift.io/cluster \
      --type merge -p '{"spec":{"storage":{}}}'; then
      success "Storage config cleared"
      FINAL_STORAGE="{}"
    else
      error "Failed to clear storage config"
    fi
  fi
  if [ "$FINAL_STATE" != "Removed" ] || [ "$FINAL_STORAGE" != "{}" ]; then
    warning "Registry state may not be fully reset"
  fi
fi
echo

info "Registry operator status:"
retry_command kubectl get \
  config.imageregistry.operator.openshift.io/cluster \
  -o jsonpath='{.status.conditions[?(@.type=="Available")]}' 2>/dev/null | \
  grep -q '"status":"False"' && \
  success "  Available: False (expected for Removed state)" || \
  info "  Available status check inconclusive"
echo

info "Pods in openshift-image-registry namespace:"
POD_COUNT=$(retry_command kubectl get pods -n openshift-image-registry \
  -l docker-registry=default \
  --field-selector=status.phase=Running 2>/dev/null | tail -n +2 | wc -l || echo "0")
if [ "$POD_COUNT" -eq 0 ]; then
  success "  No running image-registry pods (expected)"
else
  warning "  Found $POD_COUNT running image-registry pod(s)"
  retry_command kubectl get pods -n openshift-image-registry -l docker-registry=default
fi
echo

info "PVCs in openshift-image-registry namespace:"
FINAL_PVC_COUNT=$(retry_command kubectl get pvc -n openshift-image-registry \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | wc -w || echo "0")
if [ "$FINAL_PVC_COUNT" -eq 0 ]; then
  success "  No PVCs remaining (expected)"
else
  warning "  Found $FINAL_PVC_COUNT PVC(s) remaining"
  retry_command kubectl get pvc -n openshift-image-registry
fi
echo

# Step 6: Restart controller-manager to clear registry state cache
info "Step 6: Restarting openshift-controller-manager to clear cached state..."
if kubectl get namespace openshift-controller-manager >/dev/null 2>&1; then
  info "Deleting controller-manager pods..."
  kubectl delete pods -n openshift-controller-manager --all --wait=false >/dev/null 2>&1 || true
  
  info "Waiting for controller-manager to restart (up to 2 minutes)..."
  sleep 5
  for i in {1..24}; do
    CONTROLLER_READY=$(kubectl get pods -n openshift-controller-manager \
      --field-selector=status.phase=Running \
      --no-headers 2>/dev/null | wc -l || echo "0")
    
    if [ "$CONTROLLER_READY" -gt 0 ]; then
      success "Controller-manager restarted ($CONTROLLER_READY pod(s) running)"
      break
    fi
    info "Waiting for controller-manager pods (attempt $i/24)..."
    sleep 5
  done
  
  if [ "$CONTROLLER_READY" -eq 0 ]; then
    warning "Controller-manager pods not running after 2 minutes"
    kubectl get pods -n openshift-controller-manager 2>/dev/null || true
  else
    # Give it time to fully initialize and connect to services
    info "Allowing controller-manager to stabilize..."
    sleep 10
    success "Controller-manager ready with fresh state"
  fi
else
  info "openshift-controller-manager namespace not found (may be OKD/CRC)"
fi
echo

info "=== Reset Complete ==="
NAMESPACE_EXISTS=$(kubectl get namespace jam-in-a-box >/dev/null 2>&1 && echo "true" || echo "false")

if [ "$NAMESPACE_EXISTS" == "false" ] && \
   [ "$FINAL_STATE" == "Removed" ] && [ "$FINAL_STORAGE" == "{}" ] && \
   [ "$POD_COUNT" -eq 0 ] && [ "$FINAL_PVC_COUNT" -eq 0 ]; then
  success "Environment successfully reset to clean state"
  echo
  info "You can now re-run setup.yaml to deploy from scratch:"
  info "  oc apply -f https://raw.githubusercontent.com/IBMIntegration/jam-in-a-box-2/main/setup.yaml"
  exit 0
else
  warning "Reset completed but some components may need manual verification:"
  [ "$NAMESPACE_EXISTS" == "true" ] && warning "  - jam-in-a-box namespace still exists"
  [ "$FINAL_STATE" != "Removed" ] && warning "  - Registry state is not 'Removed'"
  [ "$FINAL_STORAGE" != "{}" ] && warning "  - Registry storage config is not empty"
  [ "$POD_COUNT" -ne 0 ] && warning "  - Registry pods still running"
  [ "$FINAL_PVC_COUNT" -ne 0 ] && warning "  - Registry PVCs still exist"
  exit 1
fi
