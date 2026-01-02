#!/bin/bash

if [ "${__debug_loaded:-false}" == true ]; then
  return
fi
__debug_loaded=true

function fault {
  echo "[ FAULT# ] $*" >&2
  exit 1
}

function error {
  echo "[ ERROR* ] $*" >&2
}

function warn {
  echo "[  WARN  ] $*" >&2
}

function info {
  echo "[   info ] $*"
}

function debug {
  # shellcheck disable=SC2154
  if [ "${isDebugL1}" == true ]; then
    echo "[    dbg ] $*" >&2
  fi
}

function debugVerbose {
  # shellcheck disable=SC2154
  if [ "${isDebugL2}" == true ]; then
    echo "[     dv ] $*" >&2
  fi
}
