#!/bin/bash

# Check if the repos for the Jam-in-a-Box components are in sync. Checks these
# Things:
# 1. That all the repos in the `repo-config.json` under `.template_vars` have
#    any pending pull requests
# 2. That all the repos in the `repo-config.json` under
#    `.forks[<fork name>].template_vars` are at the same commit level as the
#    main repo.

# In conditions (1) and (2), check that the URL is a repo, ie that it ends with
# `.git`. This avoids checking non-repo URLs such as documentation links.
# In condition (1), produce a yellow "pending PRs" message if any repos have
# pending pull requests, and a green "no pending PRs" message if none do.
# In condition (2), produce a green "in sync" message if all repos are in sync,
# a blue "ahead" message if the fork is ahead of the main repo, and a red
# "behind" message if the fork is behind the main repo.
# 
# To get the fork, check this project's github repo and see which fork it is,
# then scan the forks in `repo-config.json` to find the matching fork name.
# For priority should be:
#   --fork=<fork name> command line argument
#   FORK_NAME environment variable
#   GitHub repo fork name
# If none of these are set, skip condition (2) with a yellow "no fork specified"
# message.

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_CONFIG="$PROJECT_ROOT/repo-config.json"

# Source logging functions
source "$SCRIPT_DIR/helpers/log.sh"

# Color codes for terminal output
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# Configuration
FORK_NAME=""

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --fork=*)
        FORK_NAME="${1#*=}"
        shift
        ;;
      --help|-h)
        show_help
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
    esac
  done
}

show_help() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Check if Jam-in-a-Box component repositories are in sync.

OPTIONS:
  --fork=<name>    Specify fork name to check (overrides auto-detection)
  -h, --help       Show this help message

ENVIRONMENT VARIABLES:
  FORK_NAME        Fork name to check (lower priority than --fork)

The script checks:
  1. Pending pull requests on main repos
  2. Sync status between fork and upstream repos

EOF
}

# Extract owner/repo from git URL
extract_repo_info() {
  local url="$1"
  
  # Remove .git suffix if present
  url="${url%.git}"
  
  # Extract owner/repo from various git URL formats
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  else
    echo ""
  fi
}

# Check if URL is a git repository
is_git_repo() {
  local url="$1"
  [[ "$url" =~ \.git$ ]] && return 0
  return 1
}

# Get pending PRs for a repo
check_pending_prs() {
  local repo="$1"
  local pr_count
  
  pr_count=$(gh pr list --repo "$repo" --state open --json number \
    --jq 'length' 2>/dev/null || echo "0")
  
  echo "$pr_count"
}

# Get latest commit SHA for a branch
get_latest_commit() {
  local repo="$1"
  local branch="${2:-main}"
  
  gh api "repos/$repo/commits/$branch" --jq '.sha' 2>/dev/null || echo ""
}

# Compare commits between two repos
compare_commits() {
  local upstream_repo="$1"
  local fork_repo="$2"
  local branch="${3:-main}"
  
  local upstream_sha
  local fork_sha
  
  upstream_sha=$(get_latest_commit "$upstream_repo" "$branch")
  fork_sha=$(get_latest_commit "$fork_repo" "$branch")
  
  if [[ -z "$upstream_sha" ]] || [[ -z "$fork_sha" ]]; then
    echo "ERROR"
    return 1
  fi
  
  if [[ "$upstream_sha" == "$fork_sha" ]]; then
    echo "IN_SYNC"
    return 0
  fi
  
  # Check if fork is ahead or behind
  local comparison
  comparison=$(gh api "repos/$upstream_repo/compare/$upstream_sha...$fork_sha" \
    --jq '.status' 2>/dev/null || echo "ERROR")
  
  case "$comparison" in
    ahead)
      echo "AHEAD"
      ;;
    behind)
      echo "BEHIND"
      ;;
    diverged)
      echo "DIVERGED"
      ;;
    *)
      echo "ERROR"
      ;;
  esac
}

# Detect fork name from current git repo
detect_fork_name() {
  local origin_url
  local fork_owner
  
  origin_url=$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || echo "")
  
  if [[ -z "$origin_url" ]]; then
    return 1
  fi
  
  # Extract owner from origin URL
  if [[ "$origin_url" =~ github\.com[:/]([^/]+)/ ]]; then
    fork_owner="${BASH_REMATCH[1]}"
    
    # Check if this fork exists in repo-config.json
    if jq -e ".forks.\"$fork_owner\"" "$REPO_CONFIG" > /dev/null 2>&1; then
      echo "$fork_owner"
      return 0
    fi
  fi
  
  return 1
}

# Main function
main() {
  local hasIssues=0
  
  parse_args "$@"
  
  # Check if required tools are installed
  if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) is not installed. Install it from" \
      "https://cli.github.com/"
    exit 1
  fi
  
  if ! command -v jq &> /dev/null; then
    log_error "jq is not installed. Install it with: brew install jq"
    exit 1
  fi
  
  if [[ ! -f "$REPO_CONFIG" ]]; then
    log_error "repo-config.json not found at $REPO_CONFIG"
    exit 1
  fi
  
  log_banner "Checking Jam-in-a-Box Repository Sync Status"
  
  # ===== Check 1: Pending Pull Requests =====
  log_info "Checking for pending pull requests on main repos..."
  
  local hasPendingPRs=false
  local repoUrls
  
  repoUrls=$(jq -r '.template_vars | to_entries[] | .value' "$REPO_CONFIG")
  
  while IFS= read -r url; do
    if ! is_git_repo "$url"; then
      continue
    fi
    
    local repoInfo
    repoInfo=$(extract_repo_info "$url")
    
    if [[ -z "$repoInfo" ]]; then
      continue
    fi
    
    local prCount
    prCount=$(check_pending_prs "$repoInfo")
    
    if [[ "$prCount" -gt 0 ]]; then
      printf "${COLOR_YELLOW}⚠ ${COLOR_RESET}%s has %d pending PR(s)\n" \
        "$repoInfo" "$prCount"
      hasPendingPRs=true
      hasIssues=1
    else
      printf "${COLOR_GREEN}✓${COLOR_RESET} %s: no pending PRs\n" "$repoInfo"
    fi
  done <<< "$repoUrls"
  
  if [[ "$hasPendingPRs" == false ]]; then
    log_success "No pending pull requests found"
  fi
  
  log_separator
  
  # ===== Check 2: Fork Sync Status =====
  
  # Determine fork name
  if [[ -z "$FORK_NAME" ]]; then
    FORK_NAME="${FORK_NAME:-$(detect_fork_name)}"
  fi
  
  if [[ -z "$FORK_NAME" ]]; then
    printf "${COLOR_YELLOW}⚠${COLOR_RESET} No fork specified. " \
      "Skipping fork sync check.\n"
    printf "  Use --fork=<name> or set FORK_NAME environment variable\n"
  else
    log_info "Checking fork sync status for: $FORK_NAME"
    
    # Check if fork exists in config
    if ! jq -e ".forks.\"$FORK_NAME\"" "$REPO_CONFIG" > /dev/null 2>&1; then
      log_error "Fork '$FORK_NAME' not found in repo-config.json"
      exit 1
    fi
    
    # Get main and fork repos - process them together to maintain pairing
    # This approach works with bash 3.2 (macOS) and bash 4.x (Linux)
    local repoKeys
    
    repoKeys=$(jq -r '.template_vars | keys[]' "$REPO_CONFIG")
    
    # Compare each repo
    while IFS= read -r key; do
      local mainUrl
      local forkUrl
      
      mainUrl=$(jq -r ".template_vars.\"$key\"" "$REPO_CONFIG")
      forkUrl=$(jq -r ".forks.\"$FORK_NAME\".template_vars.\"$key\"" \
        "$REPO_CONFIG")
      
      # Skip if not a git repo
      if ! is_git_repo "$mainUrl"; then
        continue
      fi
      
      local mainRepo
      local forkRepo
      
      mainRepo=$(extract_repo_info "$mainUrl")
      forkRepo=$(extract_repo_info "$forkUrl")
      
      if [[ -z "$mainRepo" ]] || [[ -z "$forkRepo" ]]; then
        continue
      fi
      
      local status
      status=$(compare_commits "$mainRepo" "$forkRepo")
      
      case "$status" in
        IN_SYNC)
          printf "${COLOR_GREEN}✓${COLOR_RESET} %s: in sync\n" "$key"
          ;;
        AHEAD)
          printf "${COLOR_BLUE}↑${COLOR_RESET} %s: fork is ahead\n" "$key"
          ;;
        BEHIND)
          printf "${COLOR_RED}↓${COLOR_RESET} %s: fork is BEHIND\n" "$key"
          hasIssues=1
          ;;
        DIVERGED)
          printf "${COLOR_RED}↕${COLOR_RESET} %s: fork has DIVERGED\n" "$key"
          hasIssues=1
          ;;
        ERROR)
          printf "${COLOR_YELLOW}?${COLOR_RESET} %s: could not compare\n" "$key"
          ;;
      esac
    done <<< "$repoKeys"
    
    if [[ "$hasIssues" -eq 0 ]]; then
      log_success "All fork repositories are in sync or ahead"
    fi
  fi
  
  log_separator
  
  if [[ "$hasIssues" -eq 0 ]]; then
    log_success "All checks passed"
    exit 0
  else
    log_warn "Some checks require attention"
    exit 1
  fi
}

main "$@"


