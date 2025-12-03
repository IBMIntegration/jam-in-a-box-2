#!/bin/bash

# Test script to deploy and run integration-jam-in-a-box on workload server

set -e  # Exit on any error

# Configuration
LOCAL_PATH="$(dirname "$(readlink -f "$0")")"  # Current directory

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

uploadOnly=false
remoteHost="${REMOTE_HOST:-workload}"
remoteUser="${REMOTE_USER:-$(whoami)}"
# shellcheck disable=SC2088
remotePath="${REMOTE_PATH:-~/integration-jam-in-a-box}"
mainParams=()

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if server is reachable
check_connectivity() {
    log_info "Checking connectivity to ${remoteUser}@${remoteHost}..."
    if ssh -o ConnectTimeout=10 -o BatchMode=yes \
           "${remoteUser}@${remoteHost}" exit 2>/dev/null; then
        log_success "Successfully connected to ${remoteUser}@${remoteHost}"
        return 0
    else
        log_error "Cannot connect to ${remoteUser}@${remoteHost}"
        log_error "Please ensure:"
        log_error "  1. The server 'workload' is reachable"
        log_error "  2. SSH keys are properly configured"
        log_error "  3. The user '${remoteUser}' exists on the remote server"
        return 1
    fi
}

# Function to sync files to remote server
sync_files() {
    log_info "Syncing files from ${LOCAL_PATH} to " \
             "${remoteUser}@${remoteHost}:${remotePath}..."
    
    # Create rsync command with common options
    rsync_opts=(
        -avz                    # archive mode, verbose, compress
        --delete                # delete files on remote that don't exist locally
        --exclude='.git'        # exclude git directory
        --exclude='*.log'       # exclude log files
        --exclude='.DS_Store'   # exclude macOS metadata files
        --exclude='build'       # exclude build directory
        --progress              # show progress
    )
    
    if rsync "${rsync_opts[@]}" "${LOCAL_PATH}/" \
             "${remoteUser}@${remoteHost}:${remotePath}/"; then
        log_success "Files synced successfully"
        return 0
    else
        log_error "Failed to sync files"
        return 1
    fi
}

# Function to make main.sh executable and run it remotely
run_remote_script() {
    log_info "Making main.sh executable and running it on ${remoteHost}..."
    
    # SSH command to make script executable and run it
    ssh_command='chmod +x '"${remotePath}/main.sh"' && 
        cd '"${remotePath}"' &&
        ./main.sh '"${mainParams[*]}"
    
    log_info "Executing remote command..."
    log_info "Command: ${ssh_command}"
    
    if ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
           "${remoteUser}@${remoteHost}" "${ssh_command}" < /dev/null; then
        log_success "Remote script executed successfully"
        return 0
    else
        local exit_code=$?
        log_error "Failed to execute remote script (exit code: $exit_code)"
        return 1
    fi
}

# Function to show remote script output
show_remote_logs() {
    log_info "Checking for any output files on remote server..."
    
    # Check if there are any log files or output files
    ssh "${remoteUser}@${remoteHost}" \
        "cd ${remotePath} && find . -name '*.log' -o -name 'output.*' \
         -o -name 'secret.*' 2>/dev/null | head -10" || true
    
    # Also check if main.sh is still running (suppress command not found errors)
    log_info "Checking if any processes are still running..."
    ssh "${remoteUser}@${remoteHost}" \
        "command -v pgrep >/dev/null 2>&1 && pgrep -f 'main.sh' || echo 'No main.sh processes found'" 2>/dev/null || true
}

# Function to kill any hanging processes (optional)
kill_remote_processes() {
    log_info "Killing any hanging main.sh processes on remote server..."
    ssh "${remoteUser}@${remoteHost}" \
        "command -v pkill >/dev/null 2>&1 && pkill -f 'main.sh' || echo 'No processes to kill'" 2>/dev/null || true
}

# Main execution
main() {
    log_info "Starting deployment test to ${remoteHost}"
    log_info "Local path: ${LOCAL_PATH}"
    log_info "Remote user: ${remoteUser}"
    log_info "Remote path: ${remotePath}"
    echo
    
    # Check connectivity first
    if ! check_connectivity; then
        exit 1
    fi
    echo
    
    # Sync files
    if ! sync_files; then
        exit 1
    fi
    echo
    
    if [ "$uploadOnly" = true ]; then
        log_info "--upload-only flag set; skipping remote script execution"
        log_success "File upload completed successfully!"
        exit 0
    fi

    # Run the script remotely
    if ! run_remote_script; then
        log_error "Remote script execution failed or timed out"
        show_remote_logs
        echo
        
        # Ask if user wants to kill any hanging processes
        read -p "Do you want to kill any hanging processes on remote server? (y/N): " \
             -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            kill_remote_processes
        fi
        exit 1
    fi
    echo
    
    # Show any logs or output
    show_remote_logs
    echo
    
    log_success "Test deployment completed successfully!"    
}

# Help function
show_help() {
    echo "Usage: $0 [remote_user] [remotePath]"
    echo
    echo "This script will:"
    echo "  1. Check connectivity to the 'workload' server"
    echo "  2. Rsync the entire integration-jam-in-a-box folder to the remote server"
    echo "  3. Make main.sh executable and run it remotely"
    echo "  4. Display any output or logs"
    echo
    echo "Parameters:"
    echo "  remote_user   - Username on remote server (default: current user)"
    echo "  remotePath   - Remote directory path " \
         "(default: ~/integration-jam-in-a-box)"
    echo
    echo "Examples:"
    echo "  $0                           # Use current user and default path"
    echo "  $0 ubuntu                    # Use 'ubuntu' user and default path"
    echo "  $0 admin /opt/jam-in-a-box   # Use 'admin' user and custom path"
}

for arg in "$@"; do
    case $arg in
        --quick)
            mainParams+=("$arg")
            shift
            ;;
        --remote-host=*)
            remoteHost="${arg#*=}"
            shift
            ;;
        --remote-path=*)
            remotePath="${arg#*=}"
            shift
            ;;
        --remote-user=*)
            remoteUser="${arg#*=}"
            shift
            ;;
        --navigator-password=*)
            mainParams+=("$arg")
            shift
            ;;
        --start-here-app-password=*)
            echo "Warning: --start-here-app-password is deprecated, use --navigator-password instead" >&2
            mainParams+=("$arg")
            shift
            ;;
        --upload-only)
            uploadOnly=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
    esac
done

main
