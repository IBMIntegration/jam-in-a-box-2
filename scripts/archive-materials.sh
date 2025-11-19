#!/bin/bash

# Archive materials folder script
# Creates/updates archives/materials.tar.gz with current materials content
# Follows coding standards from ai-agent.yaml

set -euo pipefail

# Configuration
readonly MATERIALS_DIR="materials"
readonly ARCHIVE_FILE="materials.tar.gz"
readonly ARCHIVE_DIR="archives"

main() {
    local addToGit=false
    local quiet=false

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --add-to-git|-a)
                addToGit=true
                shift
                ;;
            --quiet|-q)
                quiet=true
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

    # Check if materials directory exists
    if [[ ! -d "${MATERIALS_DIR}" ]]; then
        if [[ "${quiet}" == "false" ]]; then
            echo "Error: ${MATERIALS_DIR} directory not found" >&2
        fi
        exit 1
    fi

    # Always (re)create the archive
    create_archive "${quiet}"

    # Add to git if requested
    if [[ "${addToGit}" == "true" && -d ".git" ]]; then
        git add "${ARCHIVE_DIR}/${ARCHIVE_FILE}"
        if [[ "${quiet}" == "false" ]]; then
            echo "Archive staged for git commit"
        fi
    fi
}

create_archive() {
    local quiet="$1"

    # Create archive directory if it doesn't exist
    if [[ ! -d "${ARCHIVE_DIR}" ]]; then
        mkdir -p "${ARCHIVE_DIR}"
    fi

    if [[ "${quiet}" == "false" ]]; then
        echo "Creating archive: ${ARCHIVE_DIR}/${ARCHIVE_FILE}"
    fi

    # Create the archive (overwriting existing one)
    tar -czf "${ARCHIVE_DIR}/${ARCHIVE_FILE}" "${MATERIALS_DIR}"

    if [[ "${quiet}" == "false" ]]; then
        echo "Archive created successfully"
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Archive the materials folder into archives/materials.tar.gz

OPTIONS:
    --add-to-git, -a    Stage the archive file for git commit
    --quiet, -q         Suppress output messages
    --help, -h          Show this help message

DESCRIPTION:
    This script creates a compressed archive of the materials folder.
    The archive is saved as archives/materials.tar.gz and can optionally
    be staged for git commit.

EXAMPLES:
    $0                  Create archive (always overwrites)
    $0 --add-to-git     Create archive and stage for git commit
    $0 -a -q            Create archive, stage it, be quiet

EOF
}

main "$@"