#!/bin/bash

set -e

# =============================================================================
# Application Deployment Functions
# =============================================================================

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

function createScriptsConfigMaps() {
  local NAME="$1"
  local scriptPath
  
  # Config generator is in the same directory as this script (scripts/helpers/build/)
  scriptPath="$SCRIPT_DIR/build/config-generator.js"
  
  log_debug "Creating scripts configmaps from $scriptPath"
  
  # Create config generator script configmap
  oc create configmap "${NAME}-scripts-init" \
    --namespace="$NAMESPACE" \
    --from-file="$scriptPath" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f -
}

function displayAccessInformation() {
  local NAME="$1"
  local USERNAME="$2" 
  local PASSWORD="$3"
  
  log_header "Deployment Complete - Access Information"
  
  echo ""
  echo "Navigator URL: https://$(oc get route "$NAME" \
    -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Not available')"
  echo "MD Handler URL: https://$(oc get route "${NAME}-md-handler" \
    -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo 'Not available')"
  echo "Username: $USERNAME"
  echo "Password: $PASSWORD"
  echo ""
}

function generateAuthCredentials() {
  local USERNAME PASSWORD USERNAME_BASE64 PASSWORD_BASE64
  
  USERNAME="jam"
  PASSWORD=$(
    if [[ -n "${navigatorPassword}" ]]; then
      echo "${navigatorPassword}"
    else
      generate_password
    fi
  )
  
  USERNAME_BASE64=$(echo -n "$USERNAME" | base64)
  PASSWORD_BASE64=$(echo -n "$PASSWORD" | base64)
  
  log_debug "Generated credentials for user: $USERNAME"
  
  echo "$USERNAME:$PASSWORD:$USERNAME_BASE64:$PASSWORD_BASE64"
}

function setupNavigator() {
  local NAME
  
  log_subheader "Setting up Navigator resources"
  
  # Declare and initialize local variables
  NAME="${LABEL_APP}"
  
  log_debug "Using app name: $NAME"
  
  # Build the navigator app
  if ! buildNavigatorApp; then
    log_error "Failed to build navigator application"
    return 1
  fi
  
  log_success "Navigator build and setup complete"
  return 0
}

function setupMdHandler() {
  local NAME
  
  log_subheader "Setting up MD Handler resources"
  
  # Declare and initialize local variables
  NAME="${LABEL_APP}"
  
  log_debug "Using app name: $NAME"
  
  # Build the md-handler app using S2I
  if ! buildMaterialsHandlerApp; then
    log_error "Failed to build md-handler application"
    return 1
  fi
  
  # The buildMaterialsHandlerApp function already creates the ImageStream and BuildConfig
  # Now we just need to create any additional resources that aren't part of the deployment
  
  log_success "MD Handler build and setup complete"
  return 0
}

function setupNginxAndDeploy() {
  local NAME yamlFile PORT
  local credentials USERNAME PASSWORD USERNAME_BASE64 PASSWORD_BASE64
  
  log_subheader "Setting up nginx and deploying application"
  
  # Declare and initialize all local variables
  NAME="${LABEL_APP}"
  yamlFile="$SCRIPT_DIR/build/deployment.yaml"
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
  
  # Create navigator-credentials secret (used by config-generator.js in init container)
  log_debug "Creating navigator-credentials secret with username: $USERNAME"
  oc create secret generic navigator-credentials \
    --namespace="$NAMESPACE" \
    --from-literal=username="$USERNAME" \
    --from-literal=password="$PASSWORD" \
    --dry-run=client -o yaml | \
    oc label --local -f - app="$LABEL_APP" -o yaml | \
    oc apply -f - || {
    log_error "Failed to create navigator-credentials secret"
    return 1
  }
  
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