#!/bin/bash
# Path and directory resolution utilities

# Get the directory of the calling script
# Usage: SCRIPT_DIR="$(get_script_dir)"
get_script_dir() {
    # Use BASH_SOURCE[1] to get the caller's location, not this library file
    local source="${BASH_SOURCE[1]}"
    local dir="$(cd "$(dirname "$source")" && pwd)"
    echo "$dir"
}

# Get project root directory (parent of scripts/)
# Usage: PROJECT_ROOT="$(get_project_root)"
get_project_root() {
    # Use BASH_SOURCE[1] to get the caller's location
    local source="${BASH_SOURCE[1]}"
    local script_dir="$(cd "$(dirname "$source")" && pwd)"
    local project_root="$(dirname "$script_dir")"
    echo "$project_root"
}
