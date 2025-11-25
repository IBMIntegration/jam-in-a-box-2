#!/bin/bash

# =============================================================================
# Logging Functions
# =============================================================================

errorCount=0

# Debug messages (only shown if DEBUG=true)
log_debug() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🐛 DEBUG: $1" >&2
  fi
}

# Error messages - exits immediately
log_error() {
  ((errorCount++))
  echo "❌ ERROR: $1" >&2
  exit 1
}

# Main header for major sections
log_header() {
  echo ""
  echo "=============================================================="
  echo "🚀 $1"
  echo "=============================================================="
}

# Info messages
log_info() {
  echo "ℹ️ $1"
}

# Sub-header for minor steps within a section
log_subheader() {
  echo ""
  echo "--- $1 ---"
}

# Success messages
log_success() {
  echo "✅ $1"
}