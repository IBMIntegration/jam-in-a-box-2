#!/bin/bash

ip='0.0.0.0'

function readParams {
  # shellcheck disable=SC2154
  for arg in "${scriptArgs[@]}"; do
    case "$arg" in
      --ip=*) ip="${arg#*=}" ;;
      *) echo "Unknown parameter: $arg" 1>&2
         return 1 ;;
    esac
  done
  return 0
}

##
# Function that gets called to create a DataPower script for a host. Accepts
# one parameter: the host name.
function dataPowerScript {

  # TODO related objects, but we need to suss out the correct names
  # object stylepolicy default
  # object user-agent default
  # object xmlmgr default
  # object sslproxy system-wsgw-management-loopback
  # object profile system-default

  cat - <<EOF
top;co;
switch default
rest-mgmt
  admin-state enabled
  ip-address ${ip}
exit
write mem
EOF
}
