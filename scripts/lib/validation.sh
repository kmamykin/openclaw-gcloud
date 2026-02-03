#!/bin/bash
# Variable validation utilities

# Validate that required environment variables are set
# Usage: require_vars VAR1 VAR2 VAR3 || exit 1
require_vars() {
    local missing_vars=()

    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "ERROR: Required variables not set in .env:" >&2
        for var in "${missing_vars[@]}"; do
            echo "  - $var" >&2
        done
        return 1
    fi

    return 0
}
