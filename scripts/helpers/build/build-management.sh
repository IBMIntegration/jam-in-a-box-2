#!/bin/bash

set -e

# Error trap to show what command failed
trap 'echo "ERROR: Command failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# =============================================================================
# Build Management Functions
# =============================================================================

function checkImageExists() {
  local appName="$1"
  local imageSha
  
  log_debug "Checking if image already exists for $appName"
  imageSha=$(oc get imagestream "$appName" -n "$NAMESPACE" \
    -o jsonpath='{.status.tags[0].items[0].image}' 2>/dev/null || echo "")
  
  if [[ -n "$imageSha" ]]; then
    log_info "Image already exists: ${imageSha:0:12}..."
    return 0
  else
    log_debug "No existing image found for $appName"
    return 1
  fi
}

function applyBuildConfiguration() {
  local appName="$1"
  local yamlFile="$2" 
  local buildYaml
  local materialsGitUrl materialsHandlerGitUrl navigatorGitUrl repoGitUrl
  
  repoGitUrl=$(jq -r '.template_vars.REPO_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  materialsHandlerGitUrl=$(jq -r '.template_vars.MATERIALS_HANDLER_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  materialsGitUrl=$(jq -r '.template_vars.MATERIALS_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  navigatorGitUrl=$(jq -r '.template_vars.NAVIGATOR_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  
  log_subheader "Applying build configuration for $appName"
  
  log_debug "Processing template: $yamlFile"
  log_debug "Using namespace: $NAMESPACE"
  log_debug "Using Git branch: $GIT_BRANCH"
  
  # Use safe bash string replacement instead of sed to avoid delimiter conflicts
  # Note: Individual repos (jam-navigator, jam-materials, jam-materials-handler) only have 'main' branch
  # The GIT_BRANCH variable is for the integration-jam-in-a-box repo, not the individual repos
  buildYaml=$(cat "$yamlFile")
  buildYaml="${buildYaml//\{\{NAME\}\}/$appName}"
  buildYaml="${buildYaml//\{\{NAMESPACE\}\}/$NAMESPACE}"
  buildYaml="${buildYaml//\{\{GIT_BRANCH\}\}/main}"
  buildYaml="${buildYaml//\{\{REPO_GIT_URL\}\}/$repoGitUrl}"
  buildYaml="${buildYaml//\{\{MATERIALS_HANDLER_GIT_URL\}\}/$materialsHandlerGitUrl}"
  buildYaml="${buildYaml//\{\{MATERIALS_GIT_URL\}\}/$materialsGitUrl}"
  buildYaml="${buildYaml//\{\{NAVIGATOR_GIT_URL\}\}/$navigatorGitUrl}"
  
  log_info "Applying build configuration for $appName to namespace $NAMESPACE"
  log_debug "YAML template variables:"
  log_debug "  REPO_GIT_URL=$repoGitUrl"
  log_debug "  MATERIALS_HANDLER_GIT_URL=$materialsHandlerGitUrl"
  log_debug "  MATERIALS_GIT_URL=$materialsGitUrl"
  log_debug "  NAVIGATOR_GIT_URL=$navigatorGitUrl"
  log_debug "  GIT_BRANCH=$GIT_BRANCH"
  
  applyOutput=$(echo "$buildYaml" | oc apply -f - 2>&1) || {
    echo "❌ ERROR: Failed to apply build configuration for $appName" >&2
    echo "❌ ERROR: oc apply output: $applyOutput" >&2
    echo "❌ ERROR: YAML content (first 50 lines):" >&2
    echo "$buildYaml" | head -50 >&2
    return 1
  }
  log_debug "Apply output: $applyOutput"
  
  log_success "Build configuration applied"
  return 0
}

function buildMdHandlerApp() {
  local appName buildName buildYamlPath buildYamlUrl
  
  log_header "Building Markdown Handler Application"
  
  # Declare and initialize all local variables
  appName="jam-materials-handler"
  
  # Get the materials handler URL from repo-config
  local materialsHandlerGitUrl
  materialsHandlerGitUrl=$(jq -r '.template_vars.MATERIALS_HANDLER_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  
  # Convert git URL to raw GitHub URL for build.yaml
  # Always use 'main' branch for build.yaml since individual repos don't have canary branches
  buildYamlUrl=$(echo "$materialsHandlerGitUrl" | sed 's|github.com|raw.githubusercontent.com|' | sed 's|\.git$||')/main/build.yaml
  
  # Download build.yaml to temp location
  buildYamlPath="/tmp/materials-handler-build.yaml"
  log_debug "Fetching build.yaml from: $buildYamlUrl"
  if ! curl -fsSL "$buildYamlUrl" -o "$buildYamlPath"; then
    log_error "Failed to fetch build.yaml from $buildYamlUrl"
    return 1
  fi
  
  buildName=""
  
  # Ensure internal registry is available
  if ! ensureInternalRegistry; then
    log_error "Cannot proceed without internal registry"
    return 1
  fi
  
  # Apply build configuration
  if ! applyBuildConfiguration "$appName" "$buildYamlPath"; then
    return 1
  fi
  
  # Check if image already exists in quick mode
  # shellcheck disable=SC2154
  if [[ "$quickMode" == "true" ]] && checkImageExists "$appName"; then
    log_success "Quick mode: Using existing image for $appName"
    return 0
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

function buildNavigatorApp() {
  local appName buildName buildYamlPath buildYamlUrl
  
  log_header "Building Navigator Application"
  
  # Declare and initialize all local variables
  appName="jam-navigator"
  
  # Get the navigator URL from repo-config
  local navigatorGitUrl
  navigatorGitUrl=$(jq -r '.template_vars.NAVIGATOR_GIT_URL' \
    "$SCRIPT_DIR/../../repo-config.json" 2>/dev/null || echo "")
  
  # Convert git URL to raw GitHub URL for build.yaml
  # Always use 'main' branch for build.yaml since individual repos don't have canary branches
  buildYamlUrl=$(echo "$navigatorGitUrl" | sed 's|github.com|raw.githubusercontent.com|' | sed 's|\.git$||')/main/build.yaml
  
  # Download build.yaml to temp location
  buildYamlPath="/tmp/navigator-build.yaml"
  log_debug "Fetching build.yaml from: $buildYamlUrl"
  if ! curl -fsSL "$buildYamlUrl" -o "$buildYamlPath"; then
    log_error "Failed to fetch build.yaml from $buildYamlUrl"
    return 1
  fi
  
  buildName=""
  
  # Ensure internal registry is available
  if ! ensureInternalRegistry; then
    log_error "Cannot proceed without internal registry"
    return 1
  fi
  
  # Apply build configuration
  if ! applyBuildConfiguration "$appName" "$buildYamlPath"; then
    return 1
  fi
  
  # Check if image already exists in quick mode
  if [[ "$quickMode" == "true" ]] && checkImageExists "$appName"; then
    log_success "Quick mode: Using existing image for $appName"
    return 0
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
  
  log_success "Navigator application build completed"
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
  
  # Poll build status instead of using wait, so we can detect failures early
  local maxWait=600
  local elapsed=0
  local checkInterval=5
  
  while [[ $elapsed -lt $maxWait ]]; do
    buildStatus=$(oc get build "$buildName" -n "$NAMESPACE" \
      -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    case "$buildStatus" in
      Complete)
        log_success "Build completed successfully!"
        break
        ;;
      Failed|Error|Cancelled)
        log_error "Build failed with status: $buildStatus"
        showBuildDiagnostics "$buildName" "$appName"
        return 1
        ;;
      New|Pending|Running)
        log_debug "Build status: $buildStatus (elapsed: ${elapsed}s)"
        sleep $checkInterval
        ((elapsed += checkInterval))
        ;;
      *)
        log_debug "Build status: $buildStatus (elapsed: ${elapsed}s)"
        sleep $checkInterval
        ((elapsed += checkInterval))
        ;;
    esac
  done
  
  # Final status check after loop
  buildStatus=$(oc get build "$buildName" -n "$NAMESPACE" \
    -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
  
  if [[ "$buildStatus" == "Complete" ]]; then
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
    log_error "Build status: $buildStatus"
    
    showBuildDiagnostics "$buildName" "$appName"
    return 1
  fi
}