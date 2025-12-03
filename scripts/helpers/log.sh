#!/bin/bash

# =============================================================================
# ASCII-Only Logging Functions
# No ANSI colors, pure 7-bit ASCII characters only
# =============================================================================

# Get current timestamp in readable format
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Helper function to handle piped input and format multiline output
_log_with_pipe() {
    local prefix="$1"
    local message="$*"
    local timestamp
    local piped_input=""
    local indent="        "  # 8 spaces for indentation
    
    timestamp="$(get_timestamp)"
    
    # Read piped input if available
    if [ ! -t 0 ]; then
        piped_input="$(cat)"
    fi
    
    # Handle message and piped input combination
    if [[ -n "$message" ]]; then
        # Print the main message first
        printf "[%s] [%s] %s\n" "$prefix" "$timestamp" "$message" 1>&2
        
        # If there's piped input, print it indented on following lines
        if [[ -n "$piped_input" ]]; then
            echo "$piped_input" | while IFS= read -r line; do
                printf "%s%s\n" "$indent" "$line" 1>&2
            done
        fi
    else
        # No message provided, start piped input on first line
        if [[ -n "$piped_input" ]]; then
            local first_line=true
            echo "$piped_input" | while IFS= read -r line; do
                if [[ "$first_line" == true ]]; then
                    printf "[%s] [%s] %s\n" "$prefix" "$timestamp" "$line" 1>&2
                    first_line=false
                else
                    printf "%s%s\n" "$indent" "$line" 1>&2
                fi
            done
        else
            # No message and no piped input, just print empty log
            printf "[%s] [%s]\n" "$prefix" "$timestamp" 1>&2
        fi
    fi
}

# Error logging - for critical issues
log_error() {
    _log_with_pipe "ERROR" "$@" >&2
}

# Info logging - for general information
log_info() {
    _log_with_pipe "INFO " "$@"
}

# Debug logging - for detailed troubleshooting (only shown if DEBUG=1)
log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        _log_with_pipe "DEBUG" "$@"
    fi
}

# Warning logging - for non-critical issues
log_warn() {
    _log_with_pipe "WARN " "$@" >&2
}

# Success logging - for positive outcomes
log_success() {
    _log_with_pipe "OK   " "$@"
}

# Progress logging - for step-by-step progress
log_step() {
    local step="$1"
    local total="$2"
    shift 2  # Remove first two arguments, rest becomes message
    local message="$*"
    local timestamp
    local piped_input=""
    local indent="        "
    
    timestamp="$(get_timestamp)"
    
    # Read piped input if available
    if [ ! -t 0 ]; then
        piped_input="$(cat)"
    fi
    
    # Handle message and piped input combination
    if [[ -n "$message" ]]; then
        printf "[%s/%s] [%s] %s\n" "$step" "$total" "$timestamp" "$message"
        if [[ -n "$piped_input" ]]; then
            echo "$piped_input" | while IFS= read -r line; do
                printf "%s%s\n" "$indent" "$line"
            done
        fi
    else
        if [[ -n "$piped_input" ]]; then
            local first_line=true
            echo "$piped_input" | while IFS= read -r line; do
                if [[ "$first_line" == true ]]; then
                    printf "[%s/%s] [%s] %s\n" "$step" "$total" "$timestamp" "$line"
                    first_line=false
                else
                    printf "%s%s\n" "$indent" "$line"
                fi
            done
        else
            printf "[%s/%s] [%s]\n" "$step" "$total" "$timestamp"
        fi
    fi
}

# Banner logging - for section headers
log_banner() {
    local message="$*"
    local length=${#message}
    local border=""
    
    # Create border of equal signs
    for ((i=0; i<length+4; i++)); do
        border="${border}="
    done
    
    printf "\n%s\n= %s =\n%s\n\n" "$border" "$message" "$border"
}

# Separator logging - for visual breaks
log_separator() {
    printf "%s\n" "----------------------------------------"
}

# Additional helper: Log with custom prefix
log_custom() {
    local prefix="$1"
    shift
    local message="$*"
    local timestamp
    local piped_input=""
    local indent="        "
    
    timestamp="$(get_timestamp)"
    
    # Read piped input if available
    if [ ! -t 0 ]; then
        piped_input="$(cat)"
    fi
    
    # Handle message and piped input combination
    if [[ -n "$message" ]]; then
        printf "[%-5s] [%s] %s\n" "$prefix" "$timestamp" "$message"
        if [[ -n "$piped_input" ]]; then
            echo "$piped_input" | while IFS= read -r line; do
                printf "%s%s\n" "$indent" "$line"
            done
        fi
    else
        if [[ -n "$piped_input" ]]; then
            local first_line=true
            echo "$piped_input" | while IFS= read -r line; do
                if [[ "$first_line" == true ]]; then
                    printf "[%-5s] [%s] %s\n" "$prefix" "$timestamp" "$line"
                    first_line=false
                else
                    printf "%s%s\n" "$indent" "$line"
                fi
            done
        else
            printf "[%-5s] [%s]\n" "$prefix" "$timestamp"
        fi
    fi
}

# Additional helper: Log without timestamp (for continuation lines)
log_continue() {
    local message="$*"
    printf "        %s\n" "$message"
}

# =============================================================================
# Usage Examples (commented out):
#
# # Basic usage with single message
# log_info "Application starting"
# log_error "Failed to connect to database"
# log_warn "Configuration file not found, using defaults"
# 
# # Multiple arguments (all become part of message)
# log_info "Processing file:" "$filename" "with size:" "$filesize"
# 
# # Piped input examples
# echo "Line 1\nLine 2\nLine 3" | log_info "Received data:"
# cat /var/log/app.log | log_error "Application errors:"
# ps aux | grep myapp | log_debug
# 
# # Step logging with multiple args
# log_step "3" "10" "Processing user data for" "$username"
# 
# # Custom logging
# log_custom "TRACE" "Custom log level with" "multiple" "arguments"
# 
# To enable debug logging: DEBUG=1 ./script.sh
# =============================================================================

# Example function to demonstrate all logging functions
# Uncomment the function call at the bottom to run examples
show_logging_examples() {
    log_banner "Integration Jam-in-a-Box Setup Examples"
    
    log_info "Starting setup process with multiple arguments:" "arg1" "arg2"
    log_debug "Debug mode is enabled"
    
    # Example with piped input
    echo -e "Dependency 1: OK\nDependency 2: MISSING\nDependency 3: OK" | log_step "1" "5" "Checking dependencies:"
    
    log_step "2" "5" "Creating configuration files"
    
    # Example with multiline piped input
    echo -e "export PATH=/usr/local/bin:$PATH\nexport NODE_ENV=production\nexport DEBUG=1" | log_step "3" "5" "Setting environment variables:"
    
    log_step "4" "5" "Installing components"
    log_step "5" "5" "Finalizing setup"
    
    log_separator
    
    log_success "Setup completed successfully"
    log_warn "This is just an example warning with" "multiple" "parts"
    
    # Example with piped error
    echo -e "Connection timeout\nRetry failed\nGiving up" | log_error "Database connection failed:"
    
    # Example with no message, just piped input
    echo -e "TRACE: Function called\nTRACE: Processing data\nTRACE: Function exit" | log_custom "TRACE"
    
    log_continue "Additional details for the above operation"
    log_continue "Even more details..."
    
    log_separator
    log_info "Examples completed"
}

# Uncomment the line below to run examples when this script is executed directly
# show_logging_examples

# Auto-run examples when script is executed directly (not sourced)
# This checks if the script name matches the currently executing script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Running logging examples (script executed directly)..."
    echo "To disable this, comment out the auto-run section at the bottom of log.sh"
    echo
    show_logging_examples
fi