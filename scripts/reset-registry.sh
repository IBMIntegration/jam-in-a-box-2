#!/bin/bash
# Reset OpenShift Image Registry to Removed State
# This script removes the image registry configuration and PVC, 
# returning to the default "Removed" state.

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

info "=== OpenShift Image Registry Reset Script ==="
echo

# Check current registry state
info "Checking current image registry configuration..."
REGISTRY_STATE=$(retry_command kubectl get \
  config.imageregistry.operator.openshift.io/cluster \
  -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "Unknown")
STORAGE_CONFIG=$(retry_command kubectl get \
  config.imageregistry.operator.openshift.io/cluster \
  -o jsonpath='{.spec.storage}' 2>/dev/null || echo "{}")

info "Current registry state: $REGISTRY_STATE"
info "Current storage config: $STORAGE_CONFIG"
echo

# Step 1: Set registry to Removed state
info "Step 1: Setting image registry to Removed state..."
if retry_command kubectl patch \
  config.imageregistry.operator.openshift.io/cluster \
  --type merge -p '{"spec":{"managementState":"Removed","storage":{}}}'; then
  success "Registry set to Removed state"
else
  error "Failed to set registry to Removed state"
  exit 1
fi
echo

# Step 2: Wait for registry deployment to be deleted
info "Step 2: Waiting for registry deployment to be removed..."
for i in {1..30}; do
  DEPLOYMENT_EXISTS=$(retry_command kubectl get deployment \
    image-registry -n openshift-image-registry \
    -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
  
  if [ -z "$DEPLOYMENT_EXISTS" ]; then
    success "Registry deployment removed"
    break
  fi
  info "Waiting for deployment deletion (attempt $i/30)..."
  sleep 2
done

if [ -n "$DEPLOYMENT_EXISTS" ]; then
  warning "Registry deployment still exists after 60 seconds"
  retry_command kubectl get deployment image-registry -n openshift-image-registry
else
  success "No registry deployment found"
fi
echo

# Step 3: Delete any existing PVCs
info "Step 3: Removing image registry PVCs..."
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

# Step 4: Verify final state
info "Step 4: Verifying final state..."
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

if [ "$FINAL_STATE" = "Removed" ] && [ "$FINAL_STORAGE" = "{}" ]; then
  success "Registry is in Removed state with no storage configured"
else
  warning "Registry state may not be fully reset"
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
  --field-selector=status.phase=Running 2>/dev/null | grep -c image-registry || echo "0")
if [ "$POD_COUNT" -eq 0 ]; then
  success "  No running image-registry pods (expected)"
else
  warning "  Found $POD_COUNT running image-registry pod(s)"
  retry_command kubectl get pods -n openshift-image-registry
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

info "=== Reset Complete ==="
if [ "$FINAL_STATE" = "Removed" ] && [ "$FINAL_STORAGE" = "{}" ] && \
   [ "$POD_COUNT" -eq 0 ] && [ "$FINAL_PVC_COUNT" -eq 0 ]; then
  success "Image registry successfully reset to clean Removed state"
  echo
  info "You can now re-run setup.yaml to test the registry configuration from scratch"
  exit 0
else
  warning "Reset completed but some components may need manual verification"
  exit 1
fi
