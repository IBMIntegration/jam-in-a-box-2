#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JAM_NAMESPACE="jam-in-a-box"

startHereParams=();
quickMode=false;
for arg in "$@"; do
  case $arg in
    --canary*)
      startHereParams+=("${arg}")
      shift
      ;;
    --clean*)
      startHereParams+=("${arg}")
      shift
      ;;
    --fork=*)
      startHereParams+=("${arg}")
      shift
      ;;
    --navigator-password=*)
      startHereParams+=("--password=${arg#*=}")
      shift
      ;;
    --start-here-app-password=*)
      echo "Warning: --start-here-app-password is deprecated, use --navigator-password instead" >&2
      startHereParams+=("--password=${arg#*=}")
      shift
      ;;
    --quick)
      startHereParams+=("--quick")
      # shellcheck disable=SC2034
      quickMode=true
      shift
      ;;

  esac
done

# Source logging helper functions
# shellcheck source=scripts/helpers/log.sh
source "${SCRIPT_DIR}/scripts/helpers/log.sh"

# Main script starts here
output_file="$(mktemp /tmp/output.XXXXXX)"

log_info "Integration Jam-in-a-Box main script started"
log_info "Output file created: $output_file"

# Your main application logic goes here...
secret_file="$(mktemp /tmp/secret.XXXXXX)"

hasAllNecessaryTools=true

function checkTool {
  for i in "$@"; do
    if ! command -v "$i" &> /dev/null; then
        echo "$i is required but not installed. Please install $i and try again."
        hasAllNecessaryTools=false
    fi
  done
}
log_info "Starting tool check..."
checkTool jq oc

log_info "Checking OpenShift login status..."
if ! kubectl auth can-i get pods &> /dev/null; then
  log_error "Not logged in to OpenShift. Please run 'oc login' first."
  exit 1
fi
log_info "OpenShift login verified"

# Ensure jam-in-a-box namespace exists
log_info "Ensuring jam-in-a-box namespace exists..."
if ! oc get namespace "${JAM_NAMESPACE}" &> /dev/null; then
  log_info "Creating jam-in-a-box namespace..."
  oc create namespace "${JAM_NAMESPACE}"
  log_success "Created namespace: ${JAM_NAMESPACE}"
else
  log_info "Namespace ${JAM_NAMESPACE} already exists"
fi

if ! $hasAllNecessaryTools; then
  log_error "Cannot continue without all necessary tools."
  exit 1
fi
log_info "Tool check completed successfully"

log_info "Cleaning up previous output files if they exist..."
oc -n "${JAM_NAMESPACE}" delete configmap setup-output --ignore-not-found
oc -n "${JAM_NAMESPACE}" delete secret setup-secrets --ignore-not-found

##
# Reduce the size of the oc output by filtering out information that is
# not useful for the jam helper.
function filterUselessInfo {
  local uselessInfo=(
    .metadata.annotations
    .metadata.creationTimestamp
    .metadata.generation
    .metadata.resourceVersion
    .metadata.selfLink
    .metadata.uid
    .status
  )
  # join uselessInfo with ,
  local uselessInfoJoined
  uselessInfoJoined=$(IFS=,; echo "${uselessInfo[*]}")

  local filtered
  filtered="$(jq 'del('"${uselessInfoJoined}"')')"

  # if its kind is Route, also empty spec.tls
  local kind
  kind="$(jq -r '.kind' <<< "$filtered" | tr '[:upper:]' '[:lower:]')"
  if [ "$kind" == "route" ]; then
    filtered="$(jq 'del(.spec.tls)' <<< "$filtered")"
  fi

  echo "$filtered"
}

function delimitFile {
  local file="$1"
  # check if the file is either empty or does not exist
  if [ ! -s "$file" ]; then
    echo '[' > "$file"
  else
    echo ',' >> "$file"
  fi  
}

function endFile {
  local file="$1"
  local content='';
  # check if the file is either empty or does not exist
  if [ -s "$file" ]; then
    content="$(<"$file")]"
    jq -c <<< "$content" > "$file"
  fi
}

function delistInfo {
  if [ -z "$1" ]; then
    echo "Error: Could not delist info" >&2
    return 1
  elif [ "$(jq -r .kind <<< "$1")" == "List" ]; then
    local out line
    while IFS= read -r line; do
      if [ -n "$line" ]; then
        out+="$(filterUselessInfo <<< "$line"),"
      fi
    done <<< "$(jq -c '.items[]' <<< "$1")"
    echo "${out%,}"
  else
    echo "$1"
  fi
}

function getInfo {
  local kind namespace name out
  kind="$(tr '[:upper:]' '[:lower:]' <<< "$1")"
  namespace="$2"
  name="$3"

  # get the data but filter out status and metadata that changes often
  out="$(oc get "$kind" -n "$namespace" "$name" -o json | filterUselessInfo)"
  if [ -z "$out" ]; then
    echo "Error: Could not get $kind $namespace/$name" >&2
    return 1
  fi

  out="$(delistInfo "$out")"

  if [ "$kind" == "secret" ] || [ "$kind" == 'secrets' ]; then
    # decode all data fields and put them in the secret file
    delimitFile "$secret_file"
    jq '.data |= with_entries(.value |= @base64d)' <<< "$out" >> "$secret_file"
  else
    delimitFile "$output_file"
    # put the output in the output file
    echo "$out" >> "$output_file"
  fi
}

function getInfoByLabel {
  local kind namespace name out
  kind="$(tr '[:upper:]' '[:lower:]' <<< "$1")"
  namespace="$2"
  label="$3"

  # get the data but filter out status and metadata that changes often
  out="$(oc get "$kind" -n "$namespace" -l "$label" -o json)"
  if [ -z "$out" ]; then
    echo "Error: Could not get $kind in $namespace with label $label" >&2
    return 1
  fi

  out="$(delistInfo "$out")"

  if [ "$kind" == "secret" ] || [ "$kind" == 'secrets' ]; then
    # decode all data fields and put them in the secret file
    delimitFile "$secret_file"
    jq '.data |= with_entries(.value |= @base64d)' <<< "$out" >> "$secret_file"
  else
    delimitFile "$output_file"
    # put the output in the output file
    echo "$out" >> "$output_file"
  fi
}

log_info "Creating missing objects..."

if which node &> /dev/null; then
  log_info "Node.js is installed and ready"
else
  log_info "Node.js not ready. Attempting nvm. $HOME/.nvm/nvm.sh"
  if [ -e "$HOME/.nvm/nvm.sh" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.nvm/nvm.sh"
    nvm install --lts
  else
    log_error "nvm is not installed. Please install nvm to proceed."
    exit 1
  fi
  if ! nvm use --lts; then
    log_error "nvm failed to set Node.js version"
    exit 1
  fi
fi

"${SCRIPT_DIR}/scripts/datapower/datapower.sh" --namespace="${JAM_NAMESPACE}"
getInfoByLabel route "${JAM_NAMESPACE}" jb-purpose=datapower-console

# log_info "Creating Gatsby app resources..."
# "${SCRIPT_DIR}/scripts/helpers/gatsby-site.sh" \
#   --namespace="$NAMESPACE"

log_info "Creating Start Here app resources..."
if ! "${SCRIPT_DIR}/scripts/helpers/build.sh" \
  --namespace="$JAM_NAMESPACE" \
  "${startHereParams[@]}"
then
  log_error "Start Here app setup failed"
  exit 1
fi

log_info "Gathering OpenShift resource information..."

getInfo route openshift-console console

getInfo route ibm-common-services keycloak
getInfo secret ibm-common-services cs-keycloak-initial-admin
getInfo secret ibm-common-services integration-admin-initial-temporary-credentials

getInfo route openshift-console console

getInfo route tools cp4i-navigator-pn
getInfo secret tools apim-demo-gw-admin
getInfo secret tools apim-demo-mgmt-admin-pass

getInfo route tools apim-demo-mgmt-api-manager
getInfo secret tools apim-demo-mgmt-admin-pass

getInfo route "${JAM_NAMESPACE}" integration
getInfo secret "${JAM_NAMESPACE}" navigator-credentials

log_info "Finalizing output files..."
endFile "$output_file"
endFile "$secret_file"

log_info "Integration Jam-in-a-Box main script completed"
log_info "Output file created: $output_file"
log_info "Secret file created: $secret_file"

# Show the contents of the files - simplified approach to avoid hanging
log_info "Output file contents:"
if [ -s "$output_file" ]; then
    cat "$output_file"
else
    log_info "Output file is empty"
fi

log_info "Secret file contents:"
if [ -s "$secret_file" ]; then
    cat "$secret_file"
else
    log_info "Secret file is empty"
fi

log_info "Creating ConfigMap and Secret for output files..."

oc -n "${JAM_NAMESPACE}" create configmap setup-output \
  --from-file=setup.json="$output_file"
oc -n "${JAM_NAMESPACE}" create secret generic setup-secrets \
  --from-file=secret.json="$secret_file"

log_info "Creating report..."

# Call the reporting script with the output and secret files
if ! node scripts/helpers/get-server-detail.js "$output_file" "$secret_file"; then
    log_error "Report generation failed"
    exit 1
fi

log_info "Script execution completed successfully"
