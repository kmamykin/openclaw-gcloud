#!/bin/bash
set -e

# SSH helper script for OpenClaw Compute Engine instance
# Supports multiple modes: shell, forward, logs, cli, status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Load environment variables
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

# Source .env
set -a
source .env
set +a

# Validate required variables
if [ -z "$VM_NAME" ] || [ -z "$GCP_ZONE" ]; then
    echo "ERROR: VM_NAME and GCP_ZONE not set in .env"
    exit 1
fi

MODE="${1:-shell}"
shift || true  # Remove first argument, keep rest for cli commands

case "$MODE" in
    shell)
        echo "Opening SSH shell to $VM_NAME..."
        echo "Port forwarding: localhost:${OPENCLAW_GATEWAY_PORT} -> VM:${OPENCLAW_GATEWAY_PORT}"
        echo ""
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            -- -L "${OPENCLAW_GATEWAY_PORT}:localhost:${OPENCLAW_GATEWAY_PORT}"
        ;;

    forward)
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
        echo "Checking OpenClaw gateway service status..."
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="sudo systemctl status openclaw-gateway"
        ;;

    logs)
        echo "Streaming OpenClaw gateway logs..."
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
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose run --rm openclaw-cli $@"
        ;;

    ps)
        echo "Showing running containers..."
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

    *)
        echo "Usage: $0 [mode] [args...]"
        echo ""
        echo "Modes:"
        echo "  shell    - Open interactive SSH shell with port forwarding (default)"
        echo "  forward  - Start port forwarding for gateway (keeps tunnel open)"
        echo "  status   - Check systemd service status"
        echo "  logs     - Stream container logs"
        echo "  cli      - Run OpenClaw CLI commands"
        echo "  ps       - Show running containers"
        echo "  restart  - Restart gateway container"
        echo "  stop     - Stop gateway container"
        echo "  start    - Start gateway container"
        echo ""
        echo "Examples:"
        echo "  $0                          # Open SSH shell"
        echo "  $0 forward                  # Forward gateway port"
        echo "  $0 status                   # Check service status"
        echo "  $0 logs                     # Watch logs"
        echo "  $0 cli gateway status       # Run CLI command"
        echo "  $0 cli gateway info         # Get gateway info"
        echo ""
        exit 1
        ;;
esac
