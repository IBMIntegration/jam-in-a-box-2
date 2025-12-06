#!/bin/bash
# Diagnose why builds are stuck or not starting
# Usage: ./scripts/diagnose-build-stuck.sh [namespace] [build-name]

set -e

NAMESPACE="${1:-jam-in-a-box}"
BUILD_NAME="${2:-}"

# Color output
info() { echo "ℹ️  $*"; }
success() { echo "✓ $*"; }
warning() { echo "⚠️  $*"; }
error() { echo "❌ $*" >&2; }

echo "=== Build Diagnostics for namespace: $NAMESPACE ==="
echo

# 1. Check registry operator status
info "Checking registry operator status..."
REGISTRY_STATE=$(oc get config.imageregistry cluster \
  -o jsonpath='{.spec.managementState}' 2>/dev/null || echo "Unknown")
REGISTRY_AVAILABLE=$(oc get clusteroperator image-registry \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "Unknown")

echo "  Management State: $REGISTRY_STATE"
echo "  Operator Available: $REGISTRY_AVAILABLE"

if [[ "$REGISTRY_STATE" != "Managed" ]]; then
  error "Registry is not in Managed state"
elif [[ "$REGISTRY_AVAILABLE" != "True" ]]; then
  error "Registry operator is not Available"
else
  success "Registry operator is healthy"
fi
echo

# 2. Check registry deployment
info "Checking registry deployment..."
REGISTRY_REPLICAS=$(oc get deployment image-registry -n openshift-image-registry \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
REGISTRY_DESIRED=$(oc get deployment image-registry -n openshift-image-registry \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

echo "  Ready replicas: $REGISTRY_REPLICAS/$REGISTRY_DESIRED"

if [[ "$REGISTRY_REPLICAS" != "$REGISTRY_DESIRED" ]]; then
  error "Registry deployment not fully ready"
  oc get pods -n openshift-image-registry -l docker-registry=default
else
  success "Registry deployment is ready"
fi
echo

# 3. Check registry PVC
info "Checking registry storage..."
PVC_STATUS=$(oc get pvc -n openshift-image-registry \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

echo "  PVC Status: $PVC_STATUS"

if [[ "$PVC_STATUS" != "Bound" ]]; then
  error "Registry PVC is not bound"
  oc get pvc -n openshift-image-registry
else
  success "Registry PVC is bound"
fi
echo

# 4. Check openshift-controller-manager
info "Checking openshift-controller-manager..."
CONTROLLER_READY=$(oc get pods -n openshift-controller-manager \
  -l app=openshift-controller-manager \
  -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready" && @.status=="True")])].metadata.name}' \
  2>/dev/null | wc -w || echo "0")

echo "  Ready controller pods: $CONTROLLER_READY"

if [[ "$CONTROLLER_READY" -eq 0 ]]; then
  error "No ready controller manager pods"
  oc get pods -n openshift-controller-manager -l app=openshift-controller-manager
else
  success "Controller manager is ready"
fi
echo

# 5. Check for stuck builds in the namespace
info "Checking for builds in $NAMESPACE..."
if oc get builds -n "$NAMESPACE" >/dev/null 2>&1; then
  BUILD_COUNT=$(oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
  echo "  Total builds: $BUILD_COUNT"
  
  if [[ "$BUILD_COUNT" -gt 0 ]]; then
    echo
    info "Build status summary:"
    oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | \
      awk '{print $3}' | sort | uniq -c | \
      awk '{printf "  %-15s: %d\n", $2, $1}'
    
    # Check for stuck builds in "New" state
    NEW_BUILDS=$(oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | \
      awk '$3=="New" {print $1}')
    
    if [[ -n "$NEW_BUILDS" ]]; then
      warning "Found builds stuck in 'New' state:"
      echo "$NEW_BUILDS" | while read -r build; do
        echo "    - $build"
        
        # Show creation time
        CREATED=$(oc get build "$build" -n "$NAMESPACE" \
          -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null || echo "Unknown")
        echo "      Created: $CREATED"
        
        # Check for status message
        STATUS_MSG=$(oc get build "$build" -n "$NAMESPACE" \
          -o jsonpath='{.status.message}' 2>/dev/null || echo "")
        if [[ -n "$STATUS_MSG" ]]; then
          echo "      Message: $STATUS_MSG"
        fi
      done
    fi
  fi
else
  info "No builds found in namespace"
fi
echo

# 6. If specific build name provided, show detailed info
if [[ -n "$BUILD_NAME" ]]; then
  info "Detailed diagnostics for build: $BUILD_NAME"
  
  if ! oc get build "$BUILD_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    error "Build $BUILD_NAME not found in namespace $NAMESPACE"
  else
    echo
    info "Build phase:"
    oc get build "$BUILD_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.status.phase}' && echo
    
    echo
    info "Build conditions:"
    oc get build "$BUILD_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.status.conditions}' | jq '.' 2>/dev/null || echo "  None"
    
    echo
    info "Build output reference:"
    oc get build "$BUILD_NAME" -n "$NAMESPACE" \
      -o jsonpath='{.spec.output.to}' | jq '.' 2>/dev/null || echo "  None"
    
    echo
    info "Recent events for build:"
    oc get events -n "$NAMESPACE" \
      --field-selector involvedObject.name="$BUILD_NAME" \
      --sort-by=.lastTimestamp \
      -o custom-columns=TIME:.lastTimestamp,TYPE:.type,REASON:.reason,MESSAGE:.message \
      --no-headers 2>/dev/null | tail -10 || echo "  No events found"
    
    echo
    info "Build logs (last 30 lines):"
    oc logs "build/$BUILD_NAME" -n "$NAMESPACE" --tail=30 2>/dev/null || \
      echo "  No logs available (build may not have started)"
  fi
  echo
fi

# 7. Check ImageStreams
info "Checking ImageStreams in $NAMESPACE..."
if oc get imagestreams -n "$NAMESPACE" >/dev/null 2>&1; then
  IS_COUNT=$(oc get imagestreams -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
  echo "  ImageStreams: $IS_COUNT"
  
  if [[ "$IS_COUNT" -gt 0 ]]; then
    oc get imagestreams -n "$NAMESPACE" \
      -o custom-columns=NAME:.metadata.name,DOCKER-REPO:.status.dockerImageRepository,TAGS:.status.tags[*].tag \
      --no-headers 2>/dev/null | while read -r line; do
      echo "    $line"
    done
  fi
else
  info "No ImageStreams found"
fi
echo

# 8. Check BuildConfigs
info "Checking BuildConfigs in $NAMESPACE..."
if oc get buildconfigs -n "$NAMESPACE" >/dev/null 2>&1; then
  BC_COUNT=$(oc get buildconfigs -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
  echo "  BuildConfigs: $BC_COUNT"
  
  if [[ "$BC_COUNT" -gt 0 ]]; then
    oc get buildconfigs -n "$NAMESPACE" \
      -o custom-columns=NAME:.metadata.name,TYPE:.spec.strategy.type,FROM:.spec.source.git.uri \
      --no-headers 2>/dev/null | while read -r line; do
      echo "    $line"
    done
  fi
else
  info "No BuildConfigs found"
fi
echo

# 9. Summary and recommendations
echo "=== Recommendations ==="
echo

if [[ "$REGISTRY_STATE" != "Managed" ]] || [[ "$REGISTRY_AVAILABLE" != "True" ]]; then
  error "Fix registry configuration first:"
  echo "  ./scripts/reset-registry.sh"
  echo "  Then re-run setup to configure registry properly"
elif [[ "$REGISTRY_REPLICAS" != "$REGISTRY_DESIRED" ]]; then
  error "Wait for registry deployment to be ready:"
  echo "  oc rollout status deployment/image-registry -n openshift-image-registry"
elif [[ "$CONTROLLER_READY" -eq 0 ]]; then
  error "Restart controller manager:"
  echo "  oc delete pods -n openshift-controller-manager --all"
  echo "  oc wait --for=condition=Ready pods -l app=openshift-controller-manager -n openshift-controller-manager --timeout=120s"
elif [[ -n "$NEW_BUILDS" ]]; then
  warning "Stuck builds detected. Try these steps:"
  echo "  1. Delete stuck builds:"
  echo "     oc delete builds -l buildconfig=<name> -n $NAMESPACE"
  echo
  echo "  2. Restart controller manager to refresh registry connection:"
  echo "     oc delete pods -n openshift-controller-manager --all"
  echo
  echo "  3. Start a new build:"
  echo "     oc start-build <buildconfig-name> -n $NAMESPACE"
else
  success "No obvious issues detected"
  info "If builds still don't start, check:"
  echo "  - Network connectivity between controller and registry"
  echo "  - Storage class availability and bindings"
  echo "  - OpenShift cluster node resources (CPU, memory, disk)"
fi
