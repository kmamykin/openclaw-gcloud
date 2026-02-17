#!/bin/bash
set -e

# SSH helper script for OpenClaw Compute Engine instance
# Supports: vm-shell, port-forward, shell, tui, logs, cli, status, ps, restart, stop, start, push, pull

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/path.sh"
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/ssh-setup.sh"

# Get project root and change to it
PROJECT_ROOT="$(get_project_root)"
cd "$PROJECT_ROOT"

# Load environment
load_env || exit 1

# Validate required variables
require_vars VM_NAME GCP_ZONE || exit 1

ensure_ssh_config

MODE="${1:-vm-shell}"
shift || true  # Remove first argument, keep rest for cli commands

case "$MODE" in
    vm-shell)
        echo "Opening SSH shell to $VM_NAME..."
        echo "Port forwarding: localhost:${OPENCLAW_GATEWAY_PORT} -> VM:${OPENCLAW_GATEWAY_PORT}"
        echo ""
        ssh -L "${OPENCLAW_GATEWAY_PORT}:localhost:${OPENCLAW_GATEWAY_PORT}" "$VM_HOST"
        ;;

    port-forward|forward)
        echo "Starting port forwarding for OpenClaw gateway..."
        echo ""
        echo "Gateway available at:"
        echo "  http://localhost:${OPENCLAW_GATEWAY_PORT}"
        echo "  ws://localhost:${OPENCLAW_GATEWAY_PORT}"
        echo ""
        echo "Authenticate with token from .openclaw/.env"
        echo ""
        echo "Press Ctrl+C to stop port forwarding"
        echo ""
        ssh -L "${OPENCLAW_GATEWAY_PORT}:localhost:${OPENCLAW_GATEWAY_PORT}" -N "$VM_HOST"
        ;;

    status)
        ssh "$VM_HOST" "cd $VM_DIR && docker compose ps"
        ;;

    logs)
        echo "Press Ctrl+C to stop"
        echo ""
        ssh "$VM_HOST" "cd $VM_DIR && docker compose logs -f openclaw-gateway"
        ;;

    cli)
        if [ $# -eq 0 ]; then
            echo "ERROR: No CLI command provided"
            echo "Usage: $0 cli <command> [args...]"
            echo ""
            echo "Examples:"
            echo "  $0 cli gateway status"
            echo "  $0 cli gateway info"
            echo "  $0 cli gateway list-channels"
            exit 1
        fi

        echo "Running OpenClaw CLI command: $@"
        echo ""
        # Build command with proper quoting for arguments
        CLI_ARGS=""
        for arg in "$@"; do
            CLI_ARGS="${CLI_ARGS} \"${arg}\""
        done
        ssh "$VM_HOST" "cd $VM_DIR && docker compose run --rm openclaw-gateway ${CLI_ARGS}"
        ;;

    shell)
        echo "Opening bash shell in openclaw-gateway container..."
        echo ""
        ssh -t "$VM_HOST" "cd $VM_DIR && docker compose exec -it openclaw-gateway bash"
        ;;

    tui)
        echo "Opening OpenClaw TUI..."
        echo ""
        ssh -t "$VM_HOST" "cd $VM_DIR && docker compose exec -it openclaw-gateway openclaw tui"
        ;;

    ps)
        ssh "$VM_HOST" "cd $VM_DIR && docker compose ps"
        ;;

    restart)
        echo "Restarting OpenClaw gateway..."
        ssh "$VM_HOST" "cd $VM_DIR && docker compose restart openclaw-gateway"
        echo "Gateway restarted"
        ;;

    stop)
        echo "Stopping OpenClaw gateway..."
        ssh "$VM_HOST" "cd $VM_DIR && docker compose stop openclaw-gateway"
        echo "Gateway stopped"
        ;;

    start)
        echo "Starting OpenClaw gateway..."
        ssh "$VM_HOST" "cd $VM_DIR && docker compose start openclaw-gateway"
        echo "Gateway started"
        ;;

    push)
        echo "=== .openclaw ==="

        # Check if .openclaw is a git repo
        if [ ! -d .openclaw/.git ]; then
            echo "ERROR: .openclaw is not a git repository"
            echo "Clone it first: git clone ${VM_HOST}:${BARE_REPO_PATH} .openclaw"
            exit 1
        fi

        # Push existing local commits to VM bare repo
        cd .openclaw
        git push origin HEAD
        cd "$PROJECT_ROOT"
        echo "Pushed to VM"

        # Update working copy on VM
        echo "Updating VM working copy..."
        ssh "$VM_HOST" "cd $VM_DIR/.openclaw && git pull"

        # Workspaces (now siblings of .openclaw at project root)
        # Workspaces managed by the container itself (cloned via GH_TOKEN at runtime)
        SKIP_WORKSPACES="workspace-layuplab"
        for ws_dir in workspace-*/; do
            [ -d "$ws_dir/.git" ] || continue
            ws_name="$(basename "$ws_dir")"
            echo "$SKIP_WORKSPACES" | grep -qw "$ws_name" && { echo ""; echo "=== $ws_name (skipped - container-managed) ==="; continue; }
            echo ""
            echo "=== $ws_name ==="

            # Get GitHub URL for cloning on VM if needed
            github_url="$(cd "$ws_dir" && git remote get-url origin 2>/dev/null)"

            cd "$ws_dir"
            git push origin HEAD 2>/dev/null || echo "No GitHub remote or nothing to push"
            cd "$PROJECT_ROOT"
            echo "Pushed to GitHub"

            echo "Syncing $ws_name on VM..."
            ssh "$VM_HOST" "
                WS_DIR=$VM_DIR/$ws_name
                if [ -d \$WS_DIR/.git ]; then
                    cd \$WS_DIR && git pull origin HEAD
                elif [ -n '$github_url' ]; then
                    echo 'Cloning $ws_name on VM from GitHub...'
                    git clone $github_url \$WS_DIR
                else
                    echo 'ERROR: No GitHub URL for $ws_name'
                fi
            "
        done

        echo ""
        echo "Push complete"
        ;;

    pull)
        echo "=== .openclaw ==="

        # Commit and push on VM
        echo "Committing VM changes..."
        ssh "$VM_HOST" "cd $VM_DIR/.openclaw && git add -A && (git diff --cached --quiet || git commit -m 'VM changes $(date +%Y%m%d-%H%M%S)') && git push origin HEAD"

        # Pull locally
        if [ ! -d .openclaw/.git ]; then
            echo "ERROR: .openclaw is not a git repository"
            echo "Clone it first: git clone ${VM_HOST}:${BARE_REPO_PATH} .openclaw"
            exit 1
        fi

        cd .openclaw
        git pull origin
        cd "$PROJECT_ROOT"

        # Workspaces (now siblings of .openclaw at project root)
        # Workspaces managed by the container itself (cloned via GH_TOKEN at runtime)
        SKIP_WORKSPACES="workspace-layuplab"
        for ws_dir in workspace-*/; do
            [ -d "$ws_dir/.git" ] || continue
            ws_name="$(basename "$ws_dir")"
            echo "$SKIP_WORKSPACES" | grep -qw "$ws_name" && { echo ""; echo "=== $ws_name (skipped - container-managed) ==="; continue; }
            echo ""
            echo "=== $ws_name ==="

            echo "Committing VM $ws_name changes..."
            ssh "$VM_HOST" "cd $VM_DIR/$ws_name && git add -A && (git diff --cached --quiet || git commit -m 'VM $ws_name changes $(date +%Y%m%d-%H%M%S)') && git push origin HEAD 2>/dev/null || echo 'No $ws_name repo on VM'"

            cd "$ws_dir"
            git pull origin 2>/dev/null || echo "No GitHub remote or nothing to pull"
            cd "$PROJECT_ROOT"
        done

        echo ""
        echo "Pull complete"
        ;;

    *)
        echo "Usage: $0 [mode] [args...]"
        echo ""
        echo "Modes:"
        echo "  vm-shell      - Open interactive SSH shell to VM with port forwarding (default)"
        echo "  port-forward  - Start port forwarding for gateway (keeps tunnel open)"
        echo "  shell         - Open bash shell in openclaw-gateway container"
        echo "  tui           - Open OpenClaw TUI in container"
        echo "  status        - Show container status"
        echo "  logs          - Stream container logs"
        echo "  cli           - Run OpenClaw CLI commands"
        echo "  ps            - Show running containers"
        echo "  restart       - Restart gateway container"
        echo "  stop          - Stop gateway container"
        echo "  start         - Start gateway container"
        echo "  push          - Push .openclaw and workspaces to VM"
        echo "  pull          - Pull .openclaw and workspaces from VM"
        echo ""
        echo "Examples:"
        echo "  $0                                           # Open SSH shell to VM"
        echo "  $0 port-forward                              # Forward gateway port"
        echo "  $0 shell                                     # Open bash in container"
        echo "  $0 tui                                       # Open OpenClaw TUI"
        echo "  $0 status                                    # Check service status"
        echo "  $0 logs                                      # Watch logs"
        echo "  $0 cli gateway status                        # Run CLI command"
        echo "  $0 push                                      # Push local changes to VM"
        echo "  $0 pull                                      # Pull VM changes locally"
        echo ""
        exit 1
        ;;
esac
