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
