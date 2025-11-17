#!/bin/bash

envName=''
isDebug=false

function printUsageAndExit {
  shift
  if [ -n "$*" ]; then
    echo "$*" 1>&2
    echo "" 1>&2
  fi
  cat 1>&2 << EOF
Usage: $0 <command> --env=<env-name> [--debug] [--help] [options]
  --env=<env-name> -- specify the environment to use (required)
  --debug          -- enable debug output for this script
  --help, -h       -- display this help message
Commands:
  add-debug --mpgw=<mpgw> -- build a log target on the specified mpgw for debug
                             logging and enable packet capture
  enable-rest [--ip=<ip-address>] -- enable REST management interface
  no-debug -- disable the log target and packet capture
EOF
  if [ -n "$1" ]; then
    exit $1
  else
    exit 0
  fi
}

function _doDataPowerScriptInner {
  if ! ssh -o "StrictHostKeyChecking=no" -T $host -p $port <<< "$1"; then
    echo "Error: failed to execute script on host ${host}" 1>&2
    exit 1
  fi
}

function doDataPowerScript {
  local host s
  host="$(normalizeHost ssh "$1")"
  port="${host##*:}"
  host="${host%%:*}"
  s="$(cat - << EOF
${ADMIN_USER}
${ADMIN_PASS}
$(dataPowerScript "$host")
top
exit
EOF
  )"

  $isDebug && echo "$s"

  if [ "$isDebug" == true ]; then
    echo "=== Executing script on host ${host} ==="
    _doDataPowerScriptInner "$s"
  else
    _doDataPowerScriptInner "$s" >/dev/null 2>&1
  fi
}

function normalizeHost {
  local part="$1" # ssh or rest
  # if there's a slash, it's ssh/rest, if not, ssh and rest are the same
  local host="$2"
  local port=5554
  if [ "$part" == "ssh" ]; then
    port=22
  fi

  if [[ "$host" == *"/"* ]]; then
    case "$part" in
      ssh) host="${host%%/*}" ;;
      rest) host="${host##*/}" ;;
    esac
  fi

  if [[ "$host" == *:* ]]; then
    port="${host##*:}"
    host="${host%%:*}"
  fi

  echo "${host}.${BASE_DOMAIN}:${port}"
}

function rest {
  local host="$1"
  local path="$2"
  local normalHost out
  normalHost=$(normalizeHost rest "$host")
  shift 2
  if ! out="$(curl -sku "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://$normalHost/mgmt/config/$path" "$@")" || $isDebug; then
    echo "$out"
  fi
}

function restSave {
  local host="$1"
  local domain="$2"
  local normalHost out
  local payload='{"SaveConfig":"1"}'
  normalHost=$(normalizeHost rest "$host")
  shift 2
  if ! out="$(curl -sku "${ADMIN_USER}:${ADMIN_PASS}" \
    "https://$normalHost/mgmt/actionqueue/$domain" -d "$payload")" || \
    $isDebug
  then
    echo "$out"
  fi
}

scriptArgs=()

afterDashDash=false
for arg in "$@"; do
  if [ "$afterDashDash" == true ]; then
    scriptArgs+=("$arg")
    continue
  else
    case "$arg" in
      --env=*) envName="${arg#*=}" ;;
      --debug) isDebug=true ;;
      --help|-h) printUsageAndExit 0 ;;
      --) afterDashDash=true ;;
      *) if [ -z "${command}" ]
         then command="$arg"
         else scriptArgs+=("$arg")
         fi ;;
    esac
  fi
done

if [ -z "$command" ]; then
  printUsageAndExit 1 "Error: command argument is required"
fi

if [ -n "$envName" ]; then
  if [ -e "$(dirname "$0")/env/$envName" ]; then
    # shellcheck source=./env/windmill
    source "$(dirname "$0")/env/$envName"
  else
    printUsageAndExit 1 "Error: environment \"$envName\" does not exist"
  fi
else
  printUsageAndExit 1 "Error: --env argument is required"
fi

scriptDir="$(dirname "$0")/scripts"
scriptFile="${scriptDir}/${command}.sh"
# find that gets overridden by script file

# override script function by sourcing the command script
if [ -e "${scriptFile}"  ]; then
  # shellcheck source=/dev/null
  source "${scriptDir}/abstract-script.sh"
  # shellcheck source=/dev/null
  source "${scriptFile}"
else
  printUsageAndExit 1 "Unknown command \"$command\""
fi

readParams "${scriptArgs[@]}" || printUsageAndExit 1
echo "=== Starting script \"$command\" for environment \"$envName\" ==="
beforeAllHosts
for host in "${HOSTS[@]}"; do
  beforeEachHost "$host"
  doDataPowerScript "$host"
  echo "=== DataPower script for host ${host} ==="
  afterEachHost "$host"
done
afterAllHosts
echo "=== Completed script \"$command\" for environment \"$envName\" ==="
