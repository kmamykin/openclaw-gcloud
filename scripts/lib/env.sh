#!/bin/bash
# Environment variable loading utilities

# Load .env file from project root
# Usage: load_env || { echo "ERROR: Failed to load .env" >&2; exit 1; }
load_env() {
    if [ ! -f .env ]; then
        echo "ERROR: .env file not found" >&2
        echo "Please copy .env.example to .env and configure it" >&2
        return 1
    fi

    set -a
    source .env
    set +a

    # Also source .openclaw/.env if it exists
    if [ -f .openclaw/.env ]; then
        set -a
        source .openclaw/.env
        set +a
    fi

    return 0
}

# Load .env file with variable expansion (for setup.sh)
# This handles ${VAR} expansions in .env file
# Usage: load_env_expanded || { echo "ERROR: Failed to load .env" >&2; exit 1; }
load_env_expanded() {
    if [ ! -f .env ]; then
        echo "ERROR: .env file not found" >&2
        echo "Please copy .env.example to .env and configure it" >&2
        return 1
    fi

    # Source .env, handling variable expansion
    set -a
    eval "$(cat .env | grep -v '^#' | sed 's/\${GCP_REGION}/'$GCP_REGION'/g' | sed 's/\${GCP_PROJECT_ID}/'$GCP_PROJECT_ID'/g' | sed 's/\${GCP_REPO_NAME}/'$GCP_REPO_NAME'/g')"
    set +a

    # Also source .openclaw/.env if it exists
    if [ -f .openclaw/.env ]; then
        set -a
        source .openclaw/.env
        set +a
    fi

    return 0
}
