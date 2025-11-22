#!/bin/bash

# =============================================================================
# Configuration and Global Variables
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL_APP="jb-start-here"
LABEL="app=${LABEL_APP}"
NAMESPACE="jam-in-a-box"
GIT_BRANCH="main"
LAST_BUILD_NAME=""
ROUTE_BASENAME="integration"

DEBUG=true

## 
# This is a one-touch deployment script for a jam-in-a-box educational
# environment. These scripts assume OpenShift and Cloud Pak for integration are
# installed and configured, with the Cloud Pak in the `tools` namespace. It also
# sets up an app to guide students through course materials and provide the
# basic URLs and credentials of the installed things.
#
# The basic installation steps are:
# 1. Clean up any existing resources
# 2. Build and deploy the Markdown Handler application
# 3. Deploy the Start Here App with nginx frontend
# 4. Configure authentication and routing
# 5. Display access URLs and credentials
#

# =============================================================================
# Logging Functions
# =============================================================================

errorCount=0

# Main header for major sections
log_header() {
  echo ""
  echo "=============================================================="
  echo "🚀 $1"
  echo "=============================================================="
}

# Sub-header for minor steps within a section
log_subheader() {
  echo ""
  echo "--- $1 ---"
}

# Success messages
log_success() {
  echo "✅ $1"
}

# Error messages
log_error() {
  ((errorCount++))
  echo "❌ ERROR: $1" >&2
}

# Info messages
log_info() {
  echo "ℹ️ $1"
}

# Debug messages (only shown if DEBUG=true)
log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🐛 DEBUG: $1" >&2
  fi
}

doClean=false
startHereAppPassword=''
quickMode=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --canary)
      GIT_BRANCH="canary"
      shift
      ;;
    --canary=*)
      GIT_BRANCH="${1#*=}"
      shift
      ;;
    --clean)
      doClean=true
      shift
      ;;
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift
      ;;
    --password=*)
      startHereAppPassword="${1#*=}"
      shift
      ;;
    --quick)
      quickMode=true
      shift
      ;;
    *)
      echo "Unknown parameter: $1"
      exit 1
      ;;
  esac
done

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
  
  log_debug "Registry operator is available and properly configured"
  log_debug "Management state: $managementState"
  log_debug "Storage config: $storageConfigured"
  return 0
}

function enableInternalRegistry() {
  log_subheader "Enabling internal registry with storage"
  
  log_debug "Patching registry config to Managed state with emptyDir storage"
  if ! oc patch config.imageregistry cluster --type merge --patch='{"spec":{"managementState":"Managed","storage":{"emptyDir":{}}}}'; then
    log_error "Failed to patch registry configuration"
    return 1
  fi
  
  log_info "Waiting for registry to become available (up to 5 minutes)..."
  if ! oc wait --for=condition=Available clusteroperator/image-registry --timeout=300s; then
    log_error "Registry failed to become available within timeout"
    return 1
  fi
  
  # Additional wait for registry to be truly ready for builds
  log_info "Waiting for registry deployment to stabilize..."
  sleep 30
  
  log_success "Registry is now available"
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

function forceRegistryRefresh() {
  log_subheader "Forcing build controller to refresh registry configuration"
  
  # Delete any stuck builds first
  log_debug "Cleaning up any stuck builds in 'New' state"
  oc get builds -n "$NAMESPACE" --no-headers 2>/dev/null | \
    awk '$3=="New" {print $1}' | \
    xargs -r oc delete build -n "$NAMESPACE"
  
  # Force restart of openshift-controller-manager pods to refresh registry state
  log_info "Restarting openshift-controller-manager to refresh registry configuration"
  if oc get pods -n openshift-controller-manager >/dev/null 2>&1; then
    oc delete pods -n openshift-controller-manager --all --wait=false >/dev/null 2>&1 || true
    sleep 10
    log_info "Waiting for controller manager to restart..."
    oc wait --for=condition=Ready pods -l app=openshift-controller-manager -n openshift-controller-manager --timeout=120s >/dev/null 2>&1 || true
  fi
  
  log_success "Registry refresh completed"
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
  
  log_success "Internal registry is fully configured and ready for ImageStreams"
  return 0
}

# =============================================================================
# Build Management Functions
# =============================================================================

function applyBuildConfiguration() {
  local appName="$1"
  local yamlFile="$2" 
  local buildYaml
  local repoGitUrl
  
  repoGitUrl=$(jq -r '.template_vars.REPO_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  
  log_subheader "Applying build configuration for $appName"
  
  log_debug "Processing template: $yamlFile"
  log_debug "Using namespace: $NAMESPACE"
  log_debug "Using Git branch: $GIT_BRANCH"
  
  # Use safe bash string replacement instead of sed to avoid delimiter conflicts
  buildYaml=$(cat "$yamlFile")
  buildYaml="${buildYaml//\{\{NAME\}\}/$appName}"
  buildYaml="${buildYaml//\{\{NAMESPACE\}\}/$NAMESPACE}"
  buildYaml="${buildYaml//\{\{GIT_BRANCH\}\}/$GIT_BRANCH}"
  buildYaml="${buildYaml//\{\{REPO_GIT_URL\}\}/$repoGitUrl}"
  
  if ! echo "$buildYaml" | oc apply -f -; then
    log_error "Failed to apply build configuration"
    return 1
  fi
  
  log_success "Build configuration applied"
  return 0
}

function cleanupExistingBuilds() {
  local appName="$1"
  
  log_subheader "Cleaning up existing builds for $appName"
  
  log_debug "Deleting builds with label buildconfig=$appName"
  if ! oc delete builds -l buildconfig="$appName" -n "$NAMESPACE" --ignore-not-found=true; then
    log_error "Failed to cleanup existing builds"
    return 1
  fi
  
  log_info "Existing builds cleaned up"
  return 0
}

function startNewBuild() {
  local appName="$1"
  local buildOutput buildName
  
  log_subheader "Starting new build for $appName"
  
  log_debug "Executing: oc start-build $appName -n $NAMESPACE"
  buildOutput=$(oc start-build "$appName" -n "$NAMESPACE" 2>&1)
  
  if [[ $? -ne 0 ]]; then
    log_error "Failed to start build:"
    echo "$buildOutput" >&2
    return 1
  fi
  
  # Extract build name from output like "build.build.openshift.io/md-handler-1 started"
  buildName=$(echo "$buildOutput" | grep -o "${appName}-[0-9]*" | head -1)
  
  if [[ -z "$buildName" ]]; then
    log_error "Could not determine build name from output: $buildOutput"
    return 1
  fi
  
  log_success "Started build: $buildName"
  # Use a variable to avoid echo mixing with function output
  LAST_BUILD_NAME="$buildName"
  return 0
}

function waitForBuildCompletion() {
  local buildName="$1"
  local appName="$2"
  local buildStatus imageSha
  
  log_subheader "Waiting for build completion: $buildName"
  
  log_info "Waiting for build to complete (timeout: 10 minutes)..."
  if oc wait --for=condition=Complete "build/$buildName" --timeout=600s -n "$NAMESPACE"; then
    log_success "Build completed successfully!"
    
    # Verify image is available
    log_debug "Checking if image is available in ImageStream"
    imageSha=$(oc get imagestream "$appName" -n "$NAMESPACE" \
      -o jsonpath='{.status.tags[0].items[0].image}' 2>/dev/null || echo "")
    if [[ -n "$imageSha" ]]; then
      log_success "Image available: ${imageSha:0:12}..."
    fi
    
    return 0
  else
    log_error "Build failed or timed out"
    
    buildStatus=$(oc get build "$buildName" -n "$NAMESPACE" \
      -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    log_error "Build status: $buildStatus"
    
    showBuildDiagnostics "$buildName" "$appName"
    return 1
  fi
}

function showBuildDiagnostics() {
  local buildName="$1"
  local appName="$2"
  local dockerRepo publicRepo registryRoute
  
  log_subheader "Build Diagnostics for $buildName"
  
  echo "  ImageStream status:"
  if oc get imagestream "$appName" -n "$NAMESPACE" >/dev/null 2>&1; then
    dockerRepo=$(oc get imagestream "$appName" -n "$NAMESPACE" \
      -o jsonpath='{.status.dockerImageRepository}' 2>/dev/null || echo "Not set")
    echo "    Docker repository: $dockerRepo"
    
    publicRepo=$(oc get imagestream "$appName" -n "$NAMESPACE" \
      -o jsonpath='{.status.publicDockerImageRepository}' 2>/dev/null || echo "Not set")
    echo "    Public repository: $publicRepo"
  else
    echo "    ImageStream not found"
  fi
  
  echo "  Registry status:"
  if oc get route default-route -n openshift-image-registry >/dev/null 2>&1; then
    registryRoute=$(oc get route default-route -n openshift-image-registry \
      -o jsonpath='{.status.ingress[0].host}' 2>/dev/null || echo "unknown")
    echo "    Registry route: $registryRoute"
  else
    echo "    Registry route: Not found"
  fi
  
  echo "  Recent events for build $buildName:"
  oc get events --field-selector involvedObject.name="$buildName" \
    --sort-by='.lastTimestamp' \
    -o custom-columns=TYPE:.type,REASON:.reason,MESSAGE:.message \
    --no-headers -n "$NAMESPACE" | tail -5
  
  echo "  Recent build logs:"
  oc logs "build/$buildName" -n "$NAMESPACE" --tail=20 || \
    echo "    Could not retrieve build logs"
}

function buildMdHandlerApp() {
  local appName buildName yamlFile
  
  log_header "Building Markdown Handler Application"
  
  # Declare and initialize all local variables
  appName="md-handler"
  yamlFile="scripts/helpers/start-here-app/build.yaml"
  buildName=""
  
  # Ensure internal registry is available
  if ! ensureInternalRegistry; then
    log_error "Cannot proceed without internal registry"
    return 1
  fi
  
  # Apply build configuration
  if ! applyBuildConfiguration "$appName" "$yamlFile"; then
    return 1
  fi
  
  # Clean up existing builds
  if ! cleanupExistingBuilds "$appName"; then
    return 1
  fi
  
  # Start new build and get build name
  if ! startNewBuild "$appName"; then
    return 1
  fi
  buildName="$LAST_BUILD_NAME"
  
  if [[ -z "$buildName" ]]; then
    log_error "Build name not available after starting build"
    return 1
  fi
  
  # Wait for build completion
  if ! waitForBuildCompletion "$buildName" "$appName"; then
    return 1
  fi
  
  log_success "Markdown Handler application build completed"
  return 0
}

# =============================================================================
# Cleanup Functions
# =============================================================================

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

# =============================================================================
# Utility Functions  
# =============================================================================

function generate_password() {
  local chars password i
  
  chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  password=""
  
  for i in {1..20}; do
    password+="${chars:$((RANDOM % ${#chars})):1}"
  done
  
  log_debug "Generated password with length: ${#password}"
  echo "$password"
}

# function retry_command() {
#   local max_attempts delay description attempt exit_code
  
#   max_attempts="$1"
#   delay="$2"
#   description="$3"
#   shift 3
  
#   attempt=1
#   exit_code=1
  
#   while [[ $attempt -le $max_attempts ]]; do
#     log_info "Attempt $attempt of $max_attempts: $description"
    
#     if "$@"; then
#       log_success "$description succeeded on attempt $attempt"
#       return 0
#     fi
    
#     exit_code=$?
#     log_error "$description failed on attempt $attempt (exit code: $exit_code)"
    
#     if [[ $attempt -lt $max_attempts ]]; then
#       log_info "Waiting ${delay}s before retry..."
#       sleep "$delay"
#     fi
    
#     attempt=$((attempt + 1))
#   done
  
#   log_error "$description failed after $max_attempts attempts"
#   return $exit_code
# }

# function create_materials_pvc() {
#   local NAME="$1"
#   local NAMESPACE="$2"
  
#   echo "Creating CephFS PVC for materials archive..."
  
#   # Create PVC with retry logic
#   retry_command 3 5 "Creating materials PVC" oc apply -f - <<EOF
# apiVersion: v1
# kind: PersistentVolumeClaim
# metadata:
#   name: ${NAME}-materials-pvc
#   namespace: $NAMESPACE
#   labels:
#     app: $LABEL_APP
# spec:
#   accessModes:
#     - ReadWriteMany
#   resources:
#     requests:
#       storage: 5Gi
#   storageClassName: ocs-external-storagecluster-cephfs
# EOF

#   # Wait for PVC to be bound with retry logic
#   if ! retry_command 3 10 "Waiting for PVC to bind" \
#     wait_for_pvc_bound "$NAME" "$NAMESPACE"; then
#     echo "ERROR: PVC failed to bind after multiple attempts. " \
#          "Showing diagnostics:"
#     oc get pvc ${NAME}-materials-pvc -n "$NAMESPACE" -o wide || \
#       echo "PVC not found"
#     echo "Available storage classes:"
#     oc get sc
#     return 1
#   fi
  
#   echo "PVC successfully created and bound"
#   return 0
# }

# function wait_for_pvc_bound() {
#   local NAME="$1"
#   local NAMESPACE="$2"
  
#   echo "Checking PVC status..."
#   local current_status
#   current_status=$(oc get pvc ${NAME}-materials-pvc -n "$NAMESPACE" \
#     -o jsonpath='{.status.phase}' 2>/dev/null || echo 'Not found')
#   echo "PVC status: $current_status"
  
#   # Check if PVC already exists and is bound
#   if [ "$current_status" = "Bound" ]; then
#     echo "PVC is already bound"
#     return 0
#   fi
  
#   # Wait for PVC to become bound
#   echo "Waiting up to 2 minutes for PVC to be bound..."
#   if oc wait --for=condition=Bound pvc/${NAME}-materials-pvc \
#     -n "$NAMESPACE" --timeout=120s; then
#     echo "PVC successfully bound"
#     return 0
#   else
#     echo "PVC failed to bind within timeout"
#     return 1
#   fi
# }

# function setupMaterialsLoader() {
#   local NAME="${LABEL_APP}"

#   echo "Setting up materials loader..."

#   # Create materials archive PVC using CephFS
#   materialsDir="$(dirname "$0")/../../materials"
#   if [[ -d "$materialsDir" ]]; then
#     # Create PVC with retry logic
#     if ! create_materials_pvc "$NAME" "$NAMESPACE"; then
#       echo "Failed to create materials PVC after multiple attempts"
#       return 1
#     fi

#     # Check if materials need to be loaded
#     shouldLoadMaterials=false
    
#     if [ "$quickMode" != true ]; then
#       echo "Non-quick mode: will refresh materials data"
#       shouldLoadMaterials=true
#     else
#       # In quick mode, check if materials directory exists in PVC
#       echo "Quick mode: checking if materials already exist in PVC..."
      
#       # Create a temporary checker pod with retry logic
#       if retry_command 3 5 "Creating materials checker pod" oc apply -f - <<EOF
# apiVersion: v1
# kind: Pod
# metadata:
#   name: ${NAME}-materials-checker
#   namespace: $NAMESPACE
#   labels:
#     app: $LABEL_APP
#     component: materials-checker
# spec:
#   restartPolicy: Never
#   containers:
#   - name: checker
#     image: registry.redhat.io/ubi8/ubi:latest
#     command: 
#     - 'sh'
#     - '-c'
#     - 'if [ -d /mnt/materials ] && [ "$(ls -A /mnt/materials)" ]; then echo "MATERIALS_EXIST"; else echo "MATERIALS_MISSING"; fi; sleep 30'
#     volumeMounts:
#     - name: materials-storage
#       mountPath: /mnt/materials
#   volumes:
#   - name: materials-storage
#     persistentVolumeClaim:
#       claimName: ${NAME}-materials-pvc
# EOF
#       then
#         # Wait for pod and check result with retry
#         if retry_command 3 10 "Waiting for materials checker pod" \
#           oc wait --for=condition=Ready pod/${NAME}-materials-checker \
#           -n "$NAMESPACE" --timeout=60s; then
#           if oc logs ${NAME}-materials-checker -n "$NAMESPACE" | \
#             grep -q "MATERIALS_MISSING"; then
#             echo "Materials missing in PVC, will load them"
#             shouldLoadMaterials=true
#           else
#             echo "Materials found in PVC, skipping load"
#             shouldLoadMaterials=false
#           fi
#         else
#           echo "Warning: Could not check materials status, " \
#                "will load them to be safe"
#           shouldLoadMaterials=true
#         fi
        
#         # Clean up checker pod
#         oc delete pod ${NAME}-materials-checker \
#           -n "$NAMESPACE" --ignore-not-found=true
#       else
#         echo "Warning: Could not create materials checker pod, " \
#              "will load materials to be safe"
#         shouldLoadMaterials=true
#       fi
#     fi
    
#     if [ "$shouldLoadMaterials" = true ]; then
#       # Clean up any leftover materials-loader pods
#       oc delete pod \
#         -l app=${LABEL_APP},component=materials-loader \
#         -n "$NAMESPACE" --ignore-not-found=true
      
#       # Create a temporary pod to copy materials data to the PVC with retry
#       echo "Copying materials data to CephFS volume..."
      
#       if retry_command 3 5 "Creating materials loader pod" \
#         oc apply -f - <<EOF
# apiVersion: v1
# kind: Pod
# metadata:
#   name: ${NAME}-materials-loader
#   namespace: $NAMESPACE
#   labels:
#     app: $LABEL_APP
#     component: materials-loader
# spec:
#   restartPolicy: Never
#   containers:
#   - name: loader
#     image: registry.redhat.io/ubi8/ubi:latest
#     command: ['sleep', '600']
#     volumeMounts:
#     - name: materials-storage
#       mountPath: /mnt/materials
#   volumes:
#   - name: materials-storage
#     persistentVolumeClaim:
#       claimName: ${NAME}-materials-pvc
# EOF
#       then
#         # Wait for pod to be ready with retry
#         if retry_command 3 10 "Waiting for materials loader pod" \
#           oc wait --for=condition=Ready pod/${NAME}-materials-loader \
#           -n "$NAMESPACE" --timeout=120s; then
#           # Copy materials directory to the mounted volume 
#           # (exclude macOS extended attributes)
#           # Set COPYFILE_DISABLE to prevent macOS extended attributes in tar
#           echo "Copying materials to PVC..."
          
#           # Use a function to avoid quote issues
#           copy_materials_to_pod() {
#             (cd "$(dirname "$materialsDir")" && \
#              COPYFILE_DISABLE=1 tar --exclude='._*' --exclude='.DS_Store' \
#              --exclude='.Spotlight*' --exclude='.Trashes' -cf - materials) | \
#             oc exec -i "${NAME}-materials-loader" -n "$NAMESPACE" -- \
#             tar xf - -C /mnt/
#           }
          
#           if retry_command 2 5 "Copying materials data" copy_materials_to_pod; then
#             echo "Materials data successfully copied to CephFS volume"
#           else
#             echo "ERROR: Failed to copy materials data after retries"
#             # Clean up the loader pod
#             oc delete pod ${NAME}-materials-loader \
#               -n "$NAMESPACE" --ignore-not-found=true
#             return 1
#           fi
#         else
#           echo "ERROR: Materials loader pod failed to become ready"
#           # Clean up the loader pod
#           oc delete pod ${NAME}-materials-loader \
#             -n "$NAMESPACE" --ignore-not-found=true
#           return 1
#         fi
        
#         # Clean up the loader pod
#         oc delete pod ${NAME}-materials-loader \
#           -n "$NAMESPACE" --ignore-not-found=true
#       else
#         echo "ERROR: Failed to create materials loader pod after retries"
#         return 1
#       fi
#     else
#       echo "Skipping materials loading"
#     fi
#   else
#     echo "Warning: materials directory not found at $materialsDir"
#   fi
# }

function setupMdHandler() {
  local NAME
  
  log_subheader "Setting up MD Handler resources"
  
  # Declare and initialize local variables
  NAME="${LABEL_APP}"
  
  log_debug "Using app name: $NAME"
  
  # Build the md-handler app using S2I
  if ! buildMdHandlerApp; then
    log_error "Failed to build md-handler application"
    return 1
  fi
  
  # The buildMdHandlerApp function already creates the ImageStream and BuildConfig
  # Now we just need to create any additional resources that aren't part of the deployment
  
  log_success "MD Handler build and setup complete"
  return 0
}

# =============================================================================
# Application Deployment Functions
# =============================================================================

function createNginxAuthSecret() {
  local NAME="$1"
  local USERNAME="$2"
  local PASSWORD="$3"
  
  log_debug "Creating nginx auth secret with username: $USERNAME"
  
  oc create secret generic "${NAME}-nginx-auth" \
    --namespace="$NAMESPACE" \
    --from-literal=.htpasswd="${USERNAME}:$(openssl passwd -apr1 "$PASSWORD")" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -
}

function createRestProxyConfigMap() {
  local NAME="$1"
  local baseDir
  
  baseDir="$(dirname "$0")/start-here-app"
  
  log_debug "Creating rest-proxy configmap from $baseDir"
  
  oc create configmap "${NAME}-rest-proxy" \
    --namespace="$NAMESPACE" \
    --from-file="$baseDir/rest-proxy.js" \
    --from-file="$baseDir/config/config.json" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -
}



function createScriptsConfigMaps() {
  local NAME="$1"
  local baseDir
  
  baseDir="$(dirname "$0")/start-here-app"
  
  log_debug "Creating scripts configmaps"
  
  # Create config generator script configmap
  oc create configmap "${NAME}-scripts-init" \
    --namespace="$NAMESPACE" \
    --from-file="$baseDir/config/config-generator.js" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -
}

function generateAuthCredentials() {
  local USERNAME PASSWORD USERNAME_BASE64 PASSWORD_BASE64
  
  USERNAME="jam"
  PASSWORD=$(
    if [[ -n "${startHereAppPassword}" ]]; then
      echo "${startHereAppPassword}"
    else
      generate_password
    fi
  )
  
  USERNAME_BASE64=$(echo -n "$USERNAME" | base64)
  PASSWORD_BASE64=$(echo -n "$PASSWORD" | base64)
  
  log_debug "Generated credentials for user: $USERNAME"
  
  echo "$USERNAME:$PASSWORD:$USERNAME_BASE64:$PASSWORD_BASE64"
}

function applyMainDeployment() {
  local NAME="$1"
  local USERNAME="$2"
  local PASSWORD="$3"
  local USERNAME_BASE64="$4"
  local PASSWORD_BASE64="$5"
  local yamlFile="$6"
  local PORT="$7"
  local output remaining
  local repoGitUrl repoRawBaseUrl

  repoGitUrl=$(jq -r '.template_vars.REPO_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  repoRawBaseUrl=$(jq -r '.template_vars.REPO_RAW_BASE_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  
  log_debug "Processing deployment template: $yamlFile"
  
  # Apply template with substitutions
  # Use safe bash string replacement instead of sed to avoid delimiter conflicts
  output=$(cat "$yamlFile")
  output="${output//\{\{NAME\}\}/$NAME}"
  output="${output//\{\{NAMESPACE\}\}/$NAMESPACE}"
  output="${output//\{\{USERNAME\}\}/$USERNAME}"
  output="${output//\{\{ROUTE_BASENAME\}\}/$ROUTE_BASENAME}"
  output="${output//\{\{USERNAME_BASE64\}\}/$USERNAME_BASE64}"
  output="${output//\{\{PASSWORD\}\}/$PASSWORD}"
  output="${output//\{\{PASSWORD_BASE64\}\}/$PASSWORD_BASE64}"
  output="${output//\{\{LABEL_APP\}\}/$LABEL_APP}"
  output="${output//\{\{APP\}\}/$NAME}"
  output="${output//\{\{PORT\}\}/$PORT}"
  output="${output//\{\{GIT_BRANCH\}\}/$GIT_BRANCH}"
  output="${output//\{\{REPO_GIT_URL\}\}/$repoGitUrl}"
  output="${output//\{\{REPO_RAW_BASE_URL\}\}/$repoRawBaseUrl}"

  # Check for any remaining {{}} variables
  remaining=$(echo "$output" | grep -o '{{[^}]*}}' || true)
  if [[ -n "$remaining" ]]; then
    log_error "Unsubstituted variables found in main deployment:"
    echo "$remaining" | sort -u >&2
    log_error "Template processing failed!"
    return 1
  fi

  # Apply the main deployment
  log_info "Applying main deployment configuration"
  echo "$output" | oc apply -f -
}

function setupNginxAndDeploy() {
  local NAME yamlFile PORT
  local credentials USERNAME PASSWORD USERNAME_BASE64 PASSWORD_BASE64
  
  log_subheader "Setting up nginx and deploying application"
  
  # Declare and initialize all local variables
  NAME="${LABEL_APP}"
  yamlFile="$(dirname "$0")/start-here-app/deployment.yaml"
  PORT=8088
  
  log_debug "Using deployment template: $yamlFile"
  
  # Generate authentication credentials
  credentials=$(generateAuthCredentials)
  IFS=':' read -r USERNAME PASSWORD USERNAME_BASE64 PASSWORD_BASE64 <<< "$credentials"
  
  # Create nginx auth secret
  if ! createNginxAuthSecret "$NAME" "$USERNAME" "$PASSWORD"; then
    log_error "Failed to create nginx auth secret"
    return 1
  fi
  
  # Create rest-proxy configmap
  if ! createRestProxyConfigMap "$NAME"; then
    log_error "Failed to create rest-proxy configmap"
    return 1
  fi
  
  # Create scripts configmaps
  if ! createScriptsConfigMaps "$NAME"; then
    log_error "Failed to create scripts configmaps"
    return 1
  fi
  
  # Apply main deployment
  if ! applyMainDeployment "$NAME" "$USERNAME" "$PASSWORD" "$USERNAME_BASE64" "$PASSWORD_BASE64" "$yamlFile" "$PORT"; then
    log_error "Failed to apply main deployment"
    return 1
  fi
  
  log_success "Nginx and application deployment completed"
  
  # Display access information
  displayAccessInformation "$NAME" "$USERNAME" "$PASSWORD"
}

function displayAccessInformation() {
  local NAME="$1"
  local USERNAME="$2" 
  local PASSWORD="$3"
  
  log_header "Deployment Complete - Access Information"
  
  echo ""
  echo "Start Here App URL: https://$(oc get route "$NAME" \
    -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Not available')"
  echo "MD Handler URL: https://$(oc get route "${NAME}-md-handler" \
    -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Not available')"
  echo "Username: $USERNAME"
  echo "Password: $PASSWORD"
  echo ""
}

function setupStartHereApp() {
  log_header "Starting Setup of Start Here Application"
  
  log_debug "Configuration - Password set: ${startHereAppPassword:+yes}"
  
  # Step 1: Setup materials loader (currently commented out)
  # if ! setupMaterialsLoader; then
  #   log_error "Failed to setup materials loader"
  #   return 1
  # fi
  
  # Step 2: Setup md-handler (build S2I image)
  if ! setupMdHandler; then
    log_error "Failed to setup md-handler"
    return 1
  fi
  
  # Step 3: Deploy nginx and apply main deployment
  if ! setupNginxAndDeploy; then
    log_error "Failed to deploy application"
    return 1
  fi
  
  log_success "Start Here Application setup completed successfully"
}

# =============================================================================
# Main Execution
# =============================================================================

cleanup
setupStartHereApp

# =============================================================================
# Final Error Reporting
# =============================================================================

if [[ $errorCount -eq 0 ]]; then
  log_success "Script completed successfully with no errors"
else
  log_error "Script completed with $errorCount error(s)"
fi

exit $errorCount
