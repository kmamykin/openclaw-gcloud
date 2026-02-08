#!/bin/bash
set -e

# SSH helper script for OpenClaw Compute Engine instance
# Supports multiple modes: vm-shell, port-forward, shell, logs, cli, status, ps, restart, stop, start

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/path.sh"
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/validation.sh"

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

    port-forward)
        echo "Starting port forwarding for OpenClaw gateway..."
        echo ""
        echo "Gateway available at:"
        echo "  http://localhost:${OPENCLAW_GATEWAY_PORT}"
        echo "  ws://localhost:${OPENCLAW_GATEWAY_PORT}"
        echo ""
        echo "Authenticate with token from .env file"
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
            --command="sudo systemctl status openclaw-gateway"
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
            # Escape quotes and wrap in quotes
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
        echo "✓ Gateway restarted"
        ;;

    stop)
        echo "Stopping OpenClaw gateway..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose stop openclaw-gateway"
        echo "✓ Gateway stopped"
        ;;

    start)
        echo "Starting OpenClaw gateway..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose start openclaw-gateway"
        echo "✓ Gateway started"
        ;;

    gog-sync)
        echo "Syncing local gogcli credentials to VM..."
        echo ""

        # Check local credentials exist
        if [ ! -d "${PROJECT_ROOT}/.config/gogcli" ]; then
            echo "ERROR: Local credentials not found"
            echo ""
            echo "Run local authentication first:"
            echo "  ./scripts/gog-auth-local.sh ~/Downloads/client_secret.json default you@gmail.com"
            echo ""
            exit 1
        fi

        if [ -z "$(ls -A "${PROJECT_ROOT}/.config/gogcli")" ]; then
            echo "ERROR: Credentials directory is empty"
            echo ""
            echo "Run local authentication first:"
            echo "  ./scripts/gog-auth-local.sh ~/Downloads/client_secret.json default you@gmail.com"
            echo ""
            exit 1
        fi

        # Create VM directory
        echo "→ Creating directory on VM..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="mkdir -p ~/.config/gogcli"

        # Copy recursively
        echo "→ Copying credentials to VM..."
        gcloud compute scp --recurse \
            "${PROJECT_ROOT}/.config/gogcli" \
            "${VM_NAME}:~/.config/" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID"

        # Fix ownership and permissions (files come from Mac with Mac UID, need to be readable in container)
        echo "→ Fixing file ownership and permissions..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="chown -R ${GCP_VM_USER}:${GCP_VM_USER} ~/.config/gogcli && chmod -R u+rw,go+r ~/.config/gogcli && chmod -R go+rx ~/.config/gogcli/*/"

        # Verify
        echo "→ Verifying sync..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="ls -la ~/.config/gogcli/"

        echo ""
        echo "✓ Credentials synced successfully"
        echo ""
        echo "Next steps:"
        echo ""
        echo "1. Restart containers to mount credentials:"
        echo "   $0 restart"
        echo ""
        echo "2. Test access:"
        echo "   $0 cli gog auth status"
        echo "   $0 cli gog gmail labels list"
        echo ""
        ;;

    *)
        echo "Usage: $0 [mode] [args...]"
        echo ""
        echo "Modes:"
        echo "  vm-shell      - Open interactive SSH shell to VM with port forwarding (default)"
        echo "  port-forward  - Start port forwarding for gateway (keeps tunnel open)"
        echo "  shell         - Open bash shell in openclaw-gateway container"
        echo "  status        - Check systemd service status"
        echo "  logs          - Stream container logs"
        echo "  cli           - Run OpenClaw CLI commands"
        echo "  ps            - Show running containers"
        echo "  restart       - Restart gateway container"
        echo "  stop          - Stop gateway container"
        echo "  start         - Start gateway container"
        echo "  gog-sync      - Sync local gogcli credentials to VM"
        echo ""
        echo "Examples:"
        echo "  $0                                           # Open SSH shell to VM"
        echo "  $0 port-forward                              # Forward gateway port"
        echo "  $0 shell                                     # Open bash in container"
        echo "  $0 status                                    # Check service status"
        echo "  $0 logs                                      # Watch logs"
        echo "  $0 cli gateway status                        # Run CLI command"
        echo "  $0 gog-sync                                  # Sync gogcli credentials to VM"
        echo "  $0 cli gog --client default gmail labels list    # Test gogcli access"
        echo ""
        exit 1
        ;;
esac
