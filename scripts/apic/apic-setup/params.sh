#!/bin/bash

# defaults

DEFAULT_CLOUD_UI_BASE="$(apicHost mgmt-admin)"
DEFAULT_KEYCLOAK_BASE="https://keycloak-ibm-common-services"
DEFAULT_KEYCLOAK_REALM="cloudpak"
DEFAULT_MANAGEMENT_BASE="$(apicHost mgmt-platform-api)"

__param_errors=()
__param_info=()

# required parameters

function printHelp {
  # AI Info: Generate this function based on the comments in the parseParams
  # function. Start with the usage line, then for each parameter, include its
  # description. Keep the line lengths under 80 characters unless it creates an
  # orphaned word.
  cat <<EOF
Usage: apic-setup.sh [OPTIONS]

OPTIONS:
  --admin-username=[username]   (required) username for the keycloak admin user
  --admin-password=[password]   (required) password for the keycloak admin user
  --cloud-server=[URL]          URL for the API Connect Cloud UI server
  --keycloak-server=[URL]       URL for the Keycloak server
  --keycloak-realm=[REALM]      Keycloak realm to use
  --techzone-domain=[DOMAIN]    Techzone domain to use for building other URLs
  --use-portal-service=[NAME]   (required if multiple portal services) name of
                                the portal service to use
  --debug                       Increase debug level (can be used multiple
                                times, max level 2)
  --debug=[LEVEL]               Set debug level (0=off, 1=basic, 2=detailed)
  --help                        Print this help text
EOF
}

function __validateRequiredParams {
  if [ -z "${adminUsername}" ]; then
    __param_errors+=(
      "ERROR: Missing required parameter: --admin-username=[username]"
    )
  fi
  if [ -z "${adminPassword}" ]; then
    __param_errors+=(
      "ERROR: Missing required parameter: --admin-password=[password]"
    )
  fi
}

# normalize parameters

function __buildDomain {
  local name=$1
  local domainVar=$2
  local domainPart="${!domainVar}"
  local defaultDomain=$3
  local secure="${4:-true}"
  local result=""
  local useDefaultDomain=false
  if [ -n "${domainPart}" ]; then
    if [[ "${domainPart}" == *"."* ]]; then
      result="${domainPart}"
    else
      if [ -n "${tzDomain}" ]; then
        result="${domainPart}.${tzDomain}"
      else
        __param_errors+=(
          "ERROR: cannot build ${name} base URL without techzone domain"
          )
      fi
    fi
  else
    useDefaultDomain=true    
    result="${defaultDomain}.${tzDomain}"
    if [ -n "${tzDomain}" ]; then
      result="${defaultDomain}.${tzDomain}"
    else
      __param_errors+=(
        "ERROR: cannot build ${name} default URL without techzone domain"
        )
    fi
  fi
  if [[ "${result}" == http://* ]] || [[ "${result}" == https://* ]]; then
    true # do nothing
  elif [ "${secure}" == true ]; then
    result="https://${result}"
  else
    result="http://${result}"
  fi
  if [ "${useDefaultDomain}" == true ]; then
    __param_info+=("Using default ${name} base URL: ${result}")
  fi

  eval "${domainVar}=\"\${result}\""
}

function __normalizeParams {
  __buildDomain "Cloud UI" "cloudUIBaseURL" "${DEFAULT_CLOUD_UI_BASE}"
  __buildDomain "Keycloak" "keycloakBaseURL" "${DEFAULT_KEYCLOAK_BASE}"
  if [ -z "${keycloakRealm}" ]; then
    keycloakRealm="${DEFAULT_KEYCLOAK_REALM}"
    __param_info+=("Using default Keycloak realm: ${keycloakRealm}")
  fi
  __buildDomain "Management" "managementBaseURL" "${DEFAULT_MANAGEMENT_BASE}"
}

function setParam {
  local varName="$1"
  local param="$2"
  local paramName="${param%=*}"
  local paramValue="${param#*=}"
  if [ -n "${!varName}" ]; then
    __param_errors+=(
      "ERROR: Duplicate parameter for ${paramName}: ${paramValue} (already set to: ${!varName})"
    )
  else
    eval "${varName}=\"\${paramValue}\""
  fi
}

function parseParams {
  for arg in "$@"; do
    case $arg in
      --admin-username=*)
        # required always
        # username for the keycloak admin user
        setParam "adminUsername" "${arg}"
        ;;
      --admin-password=*)      
        # required always
        # password for the keycloak admin user
        setParam "adminPassword" "${arg}"
        ;;
      --cloud-server=*)
        # URL for the API Connect Cloud UI server
        setParam "cloudUIBaseURL" "${arg}"
        ;;
      --debug)
        # Increase the debug level by 1 -- can be specified multiple times for
        # a maximum debug level of 2
        if [ "${isDebugL1}" == false ]; then
          isDebugL1=true
        else
          if [ "${isDebugL2}" == false ]; then
            __param_info+=("Enabling level 2 debug output")
          fi
          isDebugL2=true
        fi
        ;;        
      --debug=*)
        # Set debug level. Valid levels are 0, 1 or 2. Level 0 disables debug,
        # level 1 enables basic debug, level 2 enables more detailed debug.
        debugLevel="${arg#*=}"
        if [ "${debugLevel}" == "0" ]; then
          isDebugL1=false
          isDebugL2=false
        elif [ "${debugLevel}" == "1" ]; then
          isDebugL1=true
          isDebugL2=false
        elif [ "${debugLevel}" == "2" ]; then
          isDebugL1=true
          isDebugL2=true
        else
          __param_errors+=(
            "ERROR: Invalid debug level: ${debugLevel} (valid levels are 1 or 2)"
          )
        fi
        ;;
      --help)
        # prints this help text
        printHelp
        exit 0
        ;;
      --keycloak-realm=*)
        # Keycloak realm to use
        setParam "keycloakRealm" "${arg}"
        ;;
      --keycloak-server=*)
        # URL for the Keycloak server
        setParam "keycloakBaseURL" "${arg}"
        ;;
      --management-server=*)
        # URL for the API Connect Management server
        setParam "managementBaseURL" "${arg}"
        ;;
      --techzone-domain=*)
        # Techzone domain to use for building other URLs
        setParam "tzDomain" "${arg}"
        ;;
      --use-portal-service=*)
        # required if there are multiple portal services. This is the name of
        # the portal service to use.
        setParam "portalServiceName" "${arg}"
    esac
  done

  __validateRequiredParams
  __normalizeParams

  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/apic-setup/debug.sh"

  # output errors and exit if there are any errors
  local hasParamErrors=false
  for err in "${__param_errors[@]}"; do
    error "$err" >&2
    hasParamErrors=true
  done
  if [ "$hasParamErrors" == true ]; then
    return 1
  fi
  # output info messages
  if [ "${isDebugL1}" == true ]; then
    for info in "${__param_info[@]}"; do
      debug "$info"
    done
  fi

  # output final parameters if debug is enabled
  debugVerbose "Final parameters:"
  debugVerbose "  cloudUIBaseURL: $cloudUIBaseURL"
  debugVerbose "  managementBaseURL: $managementBaseURL"
  debugVerbose "  keycloakBaseURL: $keycloakBaseURL"
  debugVerbose "  keycloakRealm: ${keycloakRealm}"
  debugVerbose "  tzDomain: $tzDomain"
}