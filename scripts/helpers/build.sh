#!/bin/bash

set -e

# =============================================================================
# Configuration and Global Variables
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL_APP="navigator"
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

source "$SCRIPT_DIR/build/logging.sh"

doClean=false
navigatorPassword=''
quickMode=false
export quickMode
fork=''
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
    --fork=*)
      fork="${1#*=}"
      shift
      ;;
    --namespace=*)
      NAMESPACE="${1#*=}"
      shift
      ;;
    --password=*)
      navigatorPassword="${1#*=}"
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

# Update repo-config.json template_vars if fork is specified
if [ -n "$fork" ]; then
  log_info "Using fork: $fork"
  REPO_CONFIG_FILE="$SCRIPT_DIR/../../repo-config.json"
  log_debug "Repo config file path: $REPO_CONFIG_FILE"
  if [ -f "$REPO_CONFIG_FILE" ]; then
    log_debug "Before fork update: $(jq -r '.template_vars.NAVIGATOR_GIT_URL' "$REPO_CONFIG_FILE")"
    # Extract fork-specific URLs and update template_vars
    FORK_VARS=$(jq -r ".forks[\"$fork\"].template_vars" "$REPO_CONFIG_FILE")
    if [ "$FORK_VARS" != "null" ]; then
      # Create a temporary config with fork values in template_vars
      jq ".template_vars = .forks[\"$fork\"].template_vars" "$REPO_CONFIG_FILE" > "${REPO_CONFIG_FILE}.tmp"
      mv "${REPO_CONFIG_FILE}.tmp" "$REPO_CONFIG_FILE"
      log_info "Updated repo-config.json to use fork: $fork"
      log_debug "After fork update: $(jq -r '.template_vars.NAVIGATOR_GIT_URL' "$REPO_CONFIG_FILE")"
    else
      log_error "Fork '$fork' not found in repo-config.json"
      exit 1
    fi
  else
    log_error "Repo config file not found: $REPO_CONFIG_FILE"
    exit 1
  fi
fi

source "$SCRIPT_DIR/build/registry-management.sh"
source "$SCRIPT_DIR/build/build-management.sh"
source "$SCRIPT_DIR/build/cleanup.sh"
source "$SCRIPT_DIR/build/utility.sh"
source "$SCRIPT_DIR/build/app-deployment.sh"

function setupNavigatorApp() {
  log_header "Starting Setup of Navigator Application"
  
  log_debug "Configuration - Password set: ${navigatorPassword:+yes}"
  
  # Step 1: Build navigator image (nginx + htdocs)
  if ! setupNavigator; then
    log_error "Failed to setup navigator"
    return 1
  fi
  
  # Step 2: Build materials-handler (S2I image with materials baked in)
  if ! setupMdHandler; then
    log_error "Failed to setup materials-handler"
    return 1
  fi
  
  # Step 3: Deploy and apply main deployment
  if ! setupNginxAndDeploy; then
    log_error "Failed to deploy application"
    return 1
  fi
  
  for i in "${__build_management___builds[@]}"; do
    buildName="${i%%:*}"
    appName="${i##*:}"
    
    log_info "Waiting for build completion: $buildName (app: $appName)"
    if ! waitForBuildCompletion "$buildName" "$appName"; then
      log_error "Build $buildName for app $appName failed to complete"
      return 1
    fi
  done

  log_success "Navigator Application setup completed successfully"
}

# =============================================================================
# Main Execution
# =============================================================================

cleanup
setupNavigatorApp

# =============================================================================
# Final Error Reporting
# =============================================================================

if [[ $errorCount -eq 0 ]]; then
  log_success "Script completed successfully with no errors"
else
  log_error "Script completed with $errorCount error(s)"
fi

exit $errorCount
