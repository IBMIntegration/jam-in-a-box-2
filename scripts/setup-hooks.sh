#!/bin/bash

# Setup script for git hooks
# Installs pre-commit hook to archive materials folder when it changes
# Follows coding standards from ai-agent.yaml

set -euo pipefail

# Configuration
readonly HOOKS_DIR=".git/hooks"
readonly PRE_COMMIT_HOOK="${HOOKS_DIR}/pre-commit"
declare SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
declare REPO_ROOT
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT

main() {
    local force=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force|-f)
                force=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                exit 1
                ;;
        esac
    done

    # Change to repository root
    cd "${REPO_ROOT}"

    # Verify we're in a git repository
    if [[ ! -d ".git" ]]; then
        echo "Error: Not in a git repository root" >&2
        exit 1
    fi

    # Check if pre-commit hook already exists
    if [[ -f "${PRE_COMMIT_HOOK}" && "${force}" == "false" ]]; then
        echo "Pre-commit hook already exists at ${PRE_COMMIT_HOOK}"
        echo "Use --force to overwrite, or remove it manually first."
        exit 1
    fi

    install_pre_commit_hook

    echo "Git hooks setup complete!"
    echo "The pre-commit hook will now archive the materials folder when it changes."
}

install_pre_commit_hook() {
    echo "Installing pre-commit hook..."

    # Create hooks directory if it doesn't exist
    mkdir -p "${HOOKS_DIR}"

    # Create the pre-commit hook
    cat > "${PRE_COMMIT_HOOK}" << 'EOF'
#!/bin/bash

# Pre-commit hook to archive materials folder when it changes
# Follows coding standards from ai-agent.yaml

set -euo pipefail

# Configuration
readonly MATERIALS_DIR="materials"

main() {
    local hasChanges=false
    local stagedFiles

    # Check if materials directory exists
    if [[ ! -d "${MATERIALS_DIR}" ]]; then
        exit 0
    fi

    # Get list of staged files
    stagedFiles=$(git diff --cached --name-only)

    # Check if any staged files are in the materials directory
    while IFS= read -r file; do
        if [[ "${file}" =~ ^${MATERIALS_DIR}/ ]]; then
            hasChanges=true
            break
        fi
    done <<< "${stagedFiles}"

    # If no changes to materials, exit early
    if [[ "${hasChanges}" == "false" ]]; then
        exit 0
    fi

    echo "Materials directory changes detected, updating archive..."

    # Run the archive script with git integration
    if ! scripts/archive-materials.sh --add-to-git --quiet; then
        echo "Error: Failed to create materials archive" >&2
        exit 1
    fi

    echo "Archive updated and staged for commit"
}

main "$@"
EOF

    # Make the hook executable
    chmod +x "${PRE_COMMIT_HOOK}"

    # Create archives directory
    mkdir -p "archives"

    echo "Pre-commit hook installed successfully"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install git hooks for the integration-jam-in-a-box project.

OPTIONS:
    --force, -f     Overwrite existing hooks
    --help, -h      Show this help message

DESCRIPTION:
    This script installs a pre-commit hook that automatically creates/updates
    an archive of the materials folder whenever changes to that folder are
    committed. The archive is saved as archives/materials.tar.gz and is
    automatically included in the commit.

EXAMPLES:
    $0              Install hooks (fails if hooks already exist)
    $0 --force      Install hooks, overwriting any existing ones

EOF
}

main "$@"