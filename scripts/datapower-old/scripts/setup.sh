#!/bin/bash

mpgw=''
namespace='default'

function readParams {
  # shellcheck disable=SC2154
  for arg in "${scriptArgs[@]}"; do
    case "$arg" in
      --mpgw=*) mpgw="${arg#*=}" ;;
      --namespace=*) namespace="${arg#*=}" ;;
      *) echo "Unknown parameter: $arg" 1>&2
         return 1 ;;
    esac
  done
  if [ -z "${mpgw}" ]; then
    echo "Error: --mpgw parameter is required" 1>&2
    return 1
  fi
  return 0
}

##
# Function that gets called to create a DataPower script for a host. Accepts
# one parameter: the host name.
function dataPowerScript {
  cat - <<EOF
top;co;
switch ${namespace}
logging target ibm-log
  admin-state enabled
  type file
  format text
  timestamp zulu
  rotate 5
  size 50000
  ssl-client-type client
  upload-method ftp
  local-file logtemp:///ibm-log
  event all debug
exit
switch default
top;co;
packet-capture-advanced all temporary:///capture.pcap -1 15000 9000 "port 9090" on
write mem
y
top;co;save error
EOF
}

function afterEachHost {
  local host="$1"
  local logObjects

  #
  # This adds the object filter to the log target. There are three cases:
  # 1. No LogObjects at all (null or empty) - create new array with one object
  # 2. LogObjects is an array - append to it
  # 3. LogObjects is a single object - convert to array with existing and new
  #

  # The object to add
  local add='{
    "Class":"MultiProtocolGateway",
    "Object":"'${mpgw}'",
    "FollowReferences":"on"
  }'
  # what to send to the server
  local payload
  local method=POST
  logObjects=$(rest "${host}" "${namespace}"/LogTarget/ibm-log)
  # shellcheck disable=SC2154
  $isDebug && echo "LogTarget response: ${logObjects}"
  logObjects="$(jq -r '.LogTarget.LogObjects' <<< "${logObjects}")"

  # shellcheck disable=SC2154
  $isDebug && echo "Current LogObjects: ${logObjects}"

  if [ "${logObjects}" == "null" ] || [ -z "${logObjects}" ]; then
    payload='{"LogObjects": ['"${add}"']}'
    method=POST
    # shellcheck disable=SC2154
  $isDebug && echo "**** CASE 1: ${method}ing ${payload}"
  elif [ $(jq 'type == "array"' <<< "${logObjects}") == "true" ]; then
    payload='{"LogObjects": '$(jq '. + ['"${add}"']' <<< "${logObjects}")'}'
    # shellcheck disable=SC2154
    $isDebug && echo "**** CASE 2: ${method}ing ${payload}"
  else
    payload='{"LogObjects": ['"${logObjects}"','"${add}"']}'
    # shellcheck disable=SC2154
    $isDebug && echo "**** CASE 3: ${method}ing ${payload}"
  fi

  rest "${host}" "${namespace}"/LogTarget/ibm-log/LogObjects -X ${method} \
    -H "Content-Type: application/json" \
    -d "${payload}"

  restSave "${host}" "${namespace}"

  # shellcheck disable=SC2154
  $isDebug && (rest "${host}" "${namespace}"/LogTarget/ibm-log | jq)
}