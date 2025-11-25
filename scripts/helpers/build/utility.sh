#!/bin/bash

set -e

# =============================================================================
# Utility Functions
# =============================================================================

function generate_password() {
  local chars password i
  
  chars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  password=""
  
  for _ in {1..20}; do
    password+="${chars:$((RANDOM % ${#chars})):1}"
  done
  
  log_debug "Generated password with length: ${#password}"
  echo "$password"
}