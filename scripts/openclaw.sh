#!/bin/bash
set -e

# SSH helper script for OpenClaw Compute Engine instance
# Supports: vm-shell, port-forward, shell, logs, cli, status, ps, restart, stop, start, sync

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

MODE="${1:-vm-shell}"
shift || true  # Remove first argument, keep rest for cli commands

case "$MODE" in
    vm-shell)
        echo "Opening SSH shell to $VM_NAME..."
        echo "Port forwarding: localhost:${OPENCLAW_GATEWAY_PORT} -> VM:${OPENCLAW_GATEWAY_PORT}"
        echo ""
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            -- -L "${OPENCLAW_GATEWAY_PORT}:localhost:${OPENCLAW_GATEWAY_PORT}"
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
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            -- -L "${OPENCLAW_GATEWAY_PORT}:localhost:${OPENCLAW_GATEWAY_PORT}" -N
        ;;

    status)
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose ps"
        ;;

    logs)
        echo "Press Ctrl+C to stop"
        echo ""
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose logs -f openclaw-gateway"
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
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose run --rm openclaw-gateway ${CLI_ARGS}"
        ;;

    shell)
        echo "Opening bash shell in openclaw-gateway container..."
        echo ""
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose exec -it openclaw-gateway bash" \
            -- -t
        ;;

    ps)
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose ps"
        ;;

    restart)
        echo "Restarting OpenClaw gateway..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose restart openclaw-gateway"
        echo "Gateway restarted"
        ;;

    stop)
        echo "Stopping OpenClaw gateway..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose stop openclaw-gateway"
        echo "Gateway stopped"
        ;;

    start)
        echo "Starting OpenClaw gateway..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose start openclaw-gateway"
        echo "Gateway started"
        ;;

    sync)
        SYNC_MODE="${1:-}"
        shift || true

        # Ensure SSH config is set up for git access
        ensure_ssh_config

        VM_REMOTE="openclaw-vm"
        BARE_REPO_PATH="/home/${GCP_VM_USER}/openclaw/.openclaw.git"

        case "$SYNC_MODE" in
            push)
                echo "Syncing local .openclaw -> VM..."
                echo ""

                # Check if .openclaw is a git repo
                if [ ! -d .openclaw/.git ]; then
                    echo "ERROR: .openclaw is not a git repository"
                    echo "Clone it first: git clone ${VM_REMOTE}:${BARE_REPO_PATH} .openclaw"
                    exit 1
                fi

                # Commit local changes
                cd .openclaw
                if [ -n "$(git status --porcelain)" ]; then
                    git add -A
                    git commit -m "Local changes $(date +%Y%m%d-%H%M%S)"
                    echo "Committed local changes"
                else
                    echo "No local changes to commit"
                fi

                # Push to VM bare repo
                git push origin HEAD
                echo "Pushed to VM"

                # Update working copy on VM
                echo "Updating VM working copy..."
                gcloud compute ssh "$VM_NAME" \
                    --zone="$GCP_ZONE" \
                    --tunnel-through-iap \
                    --project="$GCP_PROJECT_ID" \
                    --command="cd /home/${GCP_VM_USER}/openclaw/.openclaw && git pull"

                cd "$PROJECT_ROOT"
                echo ""
                echo "Sync push complete"
                ;;

            pull)
                echo "Syncing VM .openclaw -> local..."
                echo ""

                # Commit and push on VM
                echo "Committing VM changes..."
                gcloud compute ssh "$VM_NAME" \
                    --zone="$GCP_ZONE" \
                    --tunnel-through-iap \
                    --project="$GCP_PROJECT_ID" \
                    --command="cd /home/${GCP_VM_USER}/openclaw/.openclaw && git add -A && git diff --cached --quiet || git commit -m 'VM changes $(date +%Y%m%d-%H%M%S)' && git push origin HEAD"

                # Pull locally
                if [ ! -d .openclaw/.git ]; then
                    echo "ERROR: .openclaw is not a git repository"
                    echo "Clone it first: git clone ${VM_REMOTE}:${BARE_REPO_PATH} .openclaw"
                    exit 1
                fi

                cd .openclaw
                git pull origin
                cd "$PROJECT_ROOT"

                echo ""
                echo "Sync pull complete"
                ;;

            workspace)
                echo "Syncing workspace via GitHub..."
                echo ""

                # Push local workspace to GitHub
                if [ -d .openclaw/workspace/.git ]; then
                    cd .openclaw/workspace
                    if [ -n "$(git status --porcelain)" ]; then
                        git add -A
                        git commit -m "Workspace update $(date +%Y%m%d-%H%M%S)"
                    fi
                    git push origin main 2>/dev/null || echo "No GitHub remote or nothing to push"
                    cd "$PROJECT_ROOT"
                    echo "Local workspace pushed to GitHub"
                else
                    echo "No local workspace git repo found, skipping local push"
                fi

                # Pull on VM from GitHub
                echo "Pulling workspace on VM from GitHub..."
                gcloud compute ssh "$VM_NAME" \
                    --zone="$GCP_ZONE" \
                    --tunnel-through-iap \
                    --project="$GCP_PROJECT_ID" \
                    --command="cd /home/${GCP_VM_USER}/openclaw/.openclaw/workspace && git pull origin main 2>/dev/null || echo 'No GitHub remote configured on VM'"

                echo ""
                echo "Workspace sync complete"
                ;;

            *)
                echo "Usage: $0 sync <mode>"
                echo ""
                echo "Modes:"
                echo "  push       - Commit and push local .openclaw changes to VM"
                echo "  pull       - Commit VM .openclaw changes and pull locally"
                echo "  workspace  - Sync workspace via GitHub (push local, pull on VM)"
                echo ""
                exit 1
                ;;
        esac
        ;;

    *)
        echo "Usage: $0 [mode] [args...]"
        echo ""
        echo "Modes:"
        echo "  vm-shell      - Open interactive SSH shell to VM with port forwarding (default)"
        echo "  port-forward  - Start port forwarding for gateway (keeps tunnel open)"
        echo "  shell         - Open bash shell in openclaw-gateway container"
        echo "  status        - Show container status"
        echo "  logs          - Stream container logs"
        echo "  cli           - Run OpenClaw CLI commands"
        echo "  ps            - Show running containers"
        echo "  restart       - Restart gateway container"
        echo "  stop          - Stop gateway container"
        echo "  start         - Start gateway container"
        echo "  sync          - Git-based sync (push/pull/workspace)"
        echo ""
        echo "Examples:"
        echo "  $0                                           # Open SSH shell to VM"
        echo "  $0 port-forward                              # Forward gateway port"
        echo "  $0 shell                                     # Open bash in container"
        echo "  $0 status                                    # Check service status"
        echo "  $0 logs                                      # Watch logs"
        echo "  $0 cli gateway status                        # Run CLI command"
        echo "  $0 sync push                                 # Push local changes to VM"
        echo "  $0 sync pull                                 # Pull VM changes locally"
        echo "  $0 sync workspace                            # Sync workspace via GitHub"
        echo ""
        exit 1
        ;;
esac
