#!/bin/bash
set -e

# SSH helper script for OpenClaw Compute Engine instance
# Supports multiple modes: shell, forward, status, logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

# Get instance info from Terraform outputs
INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null)
INSTANCE_ZONE=$(terraform output -raw instance_zone 2>/dev/null)
PROJECT_ID=$(grep '^project_id' terraform.tfvars 2>/dev/null | cut -d'"' -f2)
GATEWAY_PORT=$(grep '^openclaw_gateway_port' terraform.tfvars 2>/dev/null | sed 's/.*=\s*\([0-9]*\).*/\1/' || echo "18789")

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ]; then
    echo "ERROR: Could not get instance information from Terraform"
    echo "Make sure the instance is deployed: ./scripts/deploy.sh"
    exit 1
fi

MODE="${1:-shell}"

case "$MODE" in
    shell)
        echo "Opening SSH shell to $INSTANCE_NAME..."
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$INSTANCE_ZONE" \
            --tunnel-through-iap \
            --project="$PROJECT_ID"
        ;;

    forward)
        echo "Starting port forwarding for OpenClaw gateway..."
        echo "Gateway will be available at: http://localhost:$GATEWAY_PORT"
        echo "WebSocket: ws://localhost:$GATEWAY_PORT"
        echo ""
        echo "Press Ctrl+C to stop port forwarding"
        echo ""
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$INSTANCE_ZONE" \
            --tunnel-through-iap \
            --project="$PROJECT_ID" \
            -- -L "${GATEWAY_PORT}:localhost:${GATEWAY_PORT}" -N
        ;;

    status)
        echo "Checking OpenClaw gateway service status..."
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$INSTANCE_ZONE" \
            --tunnel-through-iap \
            --project="$PROJECT_ID" \
            --command="sudo systemctl status openclaw-gateway"
        ;;

    logs)
        echo "Streaming OpenClaw gateway logs..."
        echo "Press Ctrl+C to stop"
        echo ""
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$INSTANCE_ZONE" \
            --tunnel-through-iap \
            --project="$PROJECT_ID" \
            --command="sudo journalctl -u openclaw-gateway -f"
        ;;

    startup)
        echo "Showing startup script log..."
        gcloud compute ssh "$INSTANCE_NAME" \
            --zone="$INSTANCE_ZONE" \
            --tunnel-through-iap \
            --project="$PROJECT_ID" \
            --command="sudo cat /var/log/startup-script.log"
        ;;

    *)
        echo "Usage: $0 [mode]"
        echo ""
        echo "Modes:"
        echo "  shell    - Open interactive SSH shell (default)"
        echo "  forward  - Start port forwarding for gateway"
        echo "  status   - Check service status"
        echo "  logs     - Stream service logs"
        echo "  startup  - Show startup script log"
        echo ""
        echo "Examples:"
        echo "  $0              # Open SSH shell"
        echo "  $0 forward      # Forward gateway port"
        echo "  $0 status       # Check if service is running"
        echo "  $0 logs         # Watch service logs"
        exit 1
        ;;
esac
