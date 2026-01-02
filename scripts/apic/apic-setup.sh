#!/bin/bash

# Set up API Connect to have a catalog with a portal server. This is intended
# to be run after the Tech Jam environment is set up.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

function apicHost {
  local service=$1
  echo "https://apim-demo-${service}-tools"
}

# set by parameters
adminUsername=''
adminPassword=''
cloudUIBaseURL=''
isDebugL1=false
isDebugL2=false
keycloakBaseURL=''
keycloakRealm=''
managementBaseURL=''
portalServiceName=''
tzDomain=''

__lastCloudTokenExpiry=0
__lastCloudCredsHash=''
cloudToken=''
__lastMgmtTokenExpiry=0
__lastMgmtCredsHash=''
mgmtToken=''

source "${SCRIPT_DIR}/apic-setup/params.sh"
if ! parseParams "$@"; then
  printHelp
  exit 1
fi
source "${SCRIPT_DIR}/apic-setup/debug.sh"

function getApicIdentityProvider {
  local identityProvider
  identityProvider=$(curl -s -k \
    "${cloudUIBaseURL}/api/cloud/provider/identity-providers" | \
    jq -r '.results[] | select(.registry_type=="oidc") | .realm')
  if [ -z "$identityProvider" ]; then
    echo "ERROR: Unable to determine identity provider" >&2
    return 1
  fi
  echo "$identityProvider"
}

function getApimIdentityProvider {
  local identityProvider
  identityProvider=$(curl -s -k \
    "${managementBaseURL}/api/cloud/provider/identity-providers" | \
    jq -r '.results[] | select(.registry_type=="oidc") | .realm')
  if [ -z "$identityProvider" ]; then
    echo "ERROR: Unable to determine identity provider" >&2
    return 1
  fi
  echo "$identityProvider"
}

##
# Get info about portal services
#
function getPortalService {
  local queryResult onePortalService
  queryResult="$(
    curl -s -k \
      -H "Authorization: $(getTokenInfo "$adminUsername" "$adminPassword")" \
      -H "Accept: application/json" \
      -H 'x-ibm-realm: provider/common-services' \
      "${cloudUIBaseURL}/api/cloud/portal/services")"

  case "$(jq -r .total_results <<< "$queryResult")" in
    0)
      fault "No portal services found. Cannot establish API Connect portal."
      ;;
    1) 
      if [ -n "$portalServiceName" ]; then
        if [ "$(jq -r '.results[0].name' <<< "$queryResult")" != "$portalServiceName" ]; then
          error "Only one portal service found, but it does not match the specified name \"$portalServiceName\"."
          info "Available portal service:"
          jq -r '.results[] | .name' <<< "$queryResult" | while read -r name; do
            info "  - $name"
          done
          fault "Cannot continue with an invalid portal service name."
        fi
      fi
      jq -r '.results[0]' <<< "$queryResult"
      ;;
    *)
      onePortalService="$(jq -r --arg name "$portalServiceName" \
        '.results[] | select(.name==$name)' <<< "$queryResult")"
      if [ -n "$onePortalService" ]; then
        echo "$onePortalService"
        return 0
      else
        error "Portal server \"$portalServiceName\" not found among multiple services."
        info "Available portal services:"
        jq -r '.results[] | .name' <<< "$queryResult" | while read -r name; do
          info "  - $name"
        done
        fault "Cannot continue without a valid portal service name."
      return 1
      fi
      ;;
  esac
}

##
# Obtain a Keycloak token for the given realm and username/password
#
function getTokenInfo {
  local type=$1
  local username=$2
  local password=$3
  local userPassHash
  local lastTokenExpiry lastCredsHash token

  if [ "$type" == "cloud" ]; then
    token="$cloudToken"
    lastTokenExpiry="$__lastCloudTokenExpiry"
    lastCredsHash="$__lastCloudCredsHash"
  else
    token="$mgmtToken"
    lastTokenExpiry="$__lastMgmtTokenExpiry"
    lastCredsHash="$__lastMgmtCredsHash"
  fi
  
  userPassHash="$(md5sum <<< "${username}:${password}" | cut -d' ' -f1)"

  if [ "$lastCredsHash" == "$userPassHash" ] && [ -n "$token" ]; then
    # reuse the cached token if it doesn't expire in the next 10 seconds
    if [ "$(($(date +%s) - 10))" -lt "$lastTokenExpiry" ]; then
      debugVerbose "Reusing cached $type token for $username"
      return 0
    else
      debugVerbose "Cached $type token for $username is expiring soon, obtaining new token"      
    fi
  fi

  if [ "$type" == "cloud" ]; then
    __lastCloudCredsHash="$userPassHash"
    cloudToken=''
  else
    __lastMgmtCredsHash="$userPassHash"
    mgmtToken=''
  fi
  
  # obtain a new token

  token=''

  local kc_client_id=admin-cli
  local basePath="${keycloakBaseURL}/realms/${keycloakRealm}"

  debugVerbose "Logging in to realm \"$keycloakRealm\" with $username:******"
  local scopesUrl="${keycloakBaseURL}/admin/realms/${keycloakRealm}/client-scopes"
  debugVerbose "Scopes URL: $scopesUrl"

  local tokenRes
  tokenRes="$(curl -ks -d "client_id=$kc_client_id" \
        -d "username=$username" -d "password=$password" \
        -d 'grant_type=password' -d scope=openid \
        "${basePath}/protocol/openid-connect/token")"

  local error
  error="$(jq .error <<< "$tokenRes")"
  if [ -n "${error}" ] && [ "${error}" != 'null' ]; then
    error "ERROR: Unable to obtain $type token: $error" >&2
    return 1
  fi

  local tokenPayload
  token="$(jq -r .access_token <<< "${tokenRes}")"
  # token is header.base64payload.signature
  tokenPayload="$(cut -d'.' -f2 <<< "${token}" | base64 -d)"

  # cache token data
  # shellcheck disable=SC2001
  lastTokenExpiry="$(echo "$tokenPayload" | sed -e 's/.*"exp":\([0-9]*\).*/\1/')"

  local tokenType
  tokenType="$(jq -r .token_type <<< "${tokenRes}")"

  token="${tokenType} ${token}"

  debug "Obtained new $type token for $username, expires at $lastTokenExpiry"

  debugVerbose $'\x1b[32m'"Client scopes $(curl -ks \
        -H 'Authorization: '"$token" "$scopesUrl")"$'\x1b[0m'



  if [ "$type" == "cloud" ]; then
    __lastCloudTokenExpiry="$lastTokenExpiry"
    cloudToken="$token"
  else
    __lastMgmtTokenExpiry="$lastTokenExpiry"
    mgmtToken="$token"
  fi
}

##
# Get the info about the user's orgs
function getUserOrgs {
  local queryResult
  
  getTokenInfo mgmt "$adminUsername" "$adminPassword"

  # queryResult="$(    
    curl -s -k \
      -H "Authorization: $mgmtToken" \
      -H "Accept: application/json" \
      -H 'x-ibm-realm: provider/common-services' \
      "${managementBaseURL}/api/me?context=manager"
    #)"

  #echo "$queryResult"
}

function main {
  local apicIdentityProvider apimIdentityProvider token
  apicIdentityProvider="$(getApicIdentityProvider)"
  apimIdentityProvider="$(getApimIdentityProvider)"

  info "API Connect Identity Provider: $apicIdentityProvider"
  info "API Management Identity Provider: $apimIdentityProvider"

  if ! getTokenInfo cloud "$adminUsername" "$adminPassword"; then
    fault "ERROR: Unable to obtain cloud Keycloak token, cannot continue" >&2
  fi
  if ! getTokenInfo mgmt "$adminUsername" "$adminPassword"; then
    fault "ERROR: Unable to obtain mgmt Keycloak token, cannot continue" >&2
  fi

  getUserOrgs "$adminUsername" "$adminPassword"



}
main