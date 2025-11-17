#!/bin/bash

##
# Abstract script functions to be overridden by specific command scripts
#
# Assumes the following global variables are defined:
#   scriptArgs - array of extra arguments passed to the script
#   command   - the command being executed
##

##
# Read parameters from scriptArgs array and return them appropriately.
# This function should return false if there was an error reading parameters.
# and true otherwise. The default behaviour is to not expect any parameters.
function readParams {
  if [ -n "${scriptArgs[*]}" ]; then
    return 1
  else
    return 0
  fi
}

##
# Function that gets called before the DataPower script is generated for any
# hosts.
function beforeAllHosts {
  true
}

##
# Function that gets called before the DataPower script is generated for each
# host. Accepts one parameter: the host name.
function beforeEachHost {
  true
}

##
# Function that gets called to create a DataPower script for a host. Accepts
# one parameter: the host name.
function dataPowerScript {
  local host="$1"
  shift
  local p=''
  if [ "${#scriptArgs[@]}" -gt 0 ]; then
    p=" params ${scriptArgs[*]}"
  fi
  echo "Placeholder script for host ${host}${p}".
  # shellcheck disable=SC2154
  echo Implement in scripts/${command}.sh.
}

##
# Function that gets called before the DataPower script is generated for each
# host. Accepts one parameter: the host name.
function afterEachHost {
  true
}

##
# Function that gets called before the DataPower script is generated for any
# hosts.
function afterAllHosts {
  true
}

