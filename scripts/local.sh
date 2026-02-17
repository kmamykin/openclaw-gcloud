#!/bin/bash
set -e

# Local Docker execution for OpenClaw
# Uses docker/docker-compose.local.yml to run OpenClaw locally
#
# Usage:
#   ./scripts/local.sh start    # Start gateway
#   ./scripts/local.sh stop     # Stop gateway
#   ./scripts/local.sh logs     # Stream logs
#   ./scripts/local.sh shell    # Open bash in container
#   ./scripts/local.sh cli      # Run CLI commands
#   ./scripts/local.sh restart  # Restart gateway
#   ./scripts/local.sh status   # Show container status
#   ./scripts/local.sh build    # Build local image

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/path.sh"
source "${SCRIPT_DIR}/lib/env.sh"

# Get project root and change to it
PROJECT_ROOT="$(get_project_root)"
cd "$PROJECT_ROOT"

# Load environment (only .openclaw/.env needed for local, but load both for consistency)
load_env || exit 1

# Generate compose file from template
envsubst < docker/docker-compose.local.yml.tpl > /tmp/docker-compose.local.yml

COMPOSE_CMD="docker compose --project-directory . -f /tmp/docker-compose.local.yml"

ACTION="${1:-status}"
shift || true

case "$ACTION" in
    start)
        echo "Starting local OpenClaw gateway..."
        echo ""

        # Check if image exists
        if ! docker image inspect openclaw-cloud:latest &>/dev/null; then
            echo "Image openclaw-cloud:latest not found."
            echo "Build it first: ./scripts/local.sh build"
            exit 1
        fi

        # Check if .openclaw/.env exists
        if [ ! -f .openclaw/.env ]; then
            echo "ERROR: .openclaw/.env not found"
            echo "Create it from the example: cp .openclaw/.env.example .openclaw/.env"
            exit 1
        fi

        $COMPOSE_CMD up -d openclaw-gateway

        echo ""
        echo "Gateway starting at:"
        echo "  http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}"
        echo ""
        echo "View logs: ./scripts/local.sh logs"
        echo ""
        ;;

    stop)
        echo "Stopping local OpenClaw gateway..."
        $COMPOSE_CMD down
        echo "Stopped"
        ;;

    logs)
        echo "Press Ctrl+C to stop"
        echo ""
        $COMPOSE_CMD logs -f openclaw-gateway
        ;;

    shell)
        echo "Opening bash shell in local container..."
        echo ""
        $COMPOSE_CMD exec -it openclaw-gateway bash
        ;;

    cli)
        if [ $# -eq 0 ]; then
            echo "ERROR: No CLI command provided"
            echo "Usage: $0 cli <command> [args...]"
            echo ""
            echo "Examples:"
            echo "  $0 cli gateway status"
            echo "  $0 cli gateway info"
            exit 1
        fi
        $COMPOSE_CMD run --rm openclaw-cli "$@"
        ;;

    restart)
        echo "Restarting local OpenClaw gateway..."
        $COMPOSE_CMD restart openclaw-gateway
        echo "Restarted"
        ;;

    status)
        $COMPOSE_CMD ps
        ;;

    build)
        echo "Building local OpenClaw image..."
        "${SCRIPT_DIR}/build.sh"
        ;;

    *)
        echo "Usage: $0 [action] [args...]"
        echo ""
        echo "Actions:"
        echo "  start    - Start local gateway container"
        echo "  stop     - Stop local gateway container"
        echo "  logs     - Stream container logs"
        echo "  shell    - Open bash shell in container"
        echo "  cli      - Run OpenClaw CLI commands"
        echo "  restart  - Restart gateway container"
        echo "  status   - Show container status (default)"
        echo "  build    - Build Docker image (amd64, runs via Rosetta on Mac)"
        echo ""
        echo "Examples:"
        echo "  $0 start                      # Start gateway"
        echo "  $0 logs                        # Watch logs"
        echo "  $0 cli gateway status          # Run CLI command"
        echo "  $0 build                       # Build image"
        echo ""
        exit 1
        ;;
esac
