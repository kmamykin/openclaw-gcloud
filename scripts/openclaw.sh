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
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && docker compose run --rm openclaw-gateway $@"
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

    gog-auth-credentials)
        if [ $# -lt 2 ]; then
            echo "ERROR: Missing required arguments"
            echo "Usage: $0 gog-auth-credentials <client-name> <path-to-credentials.json> [--domain example.com]"
            echo ""
            echo "Examples:"
            echo "  $0 gog-auth-credentials default ~/Downloads/client_secret_xxx.json"
            echo "  $0 gog-auth-credentials work ~/Downloads/work.json --domain company.com"
            echo ""
            echo "Named clients allow managing separate OAuth credentials for different projects."
            exit 1
        fi

        CLIENT_NAME="$1"
        CREDS_FILE="$2"
        shift 2  # Remove client name and creds file, keep rest for optional flags

        if [ ! -f "$CREDS_FILE" ]; then
            echo "ERROR: File not found: $CREDS_FILE"
            exit 1
        fi

        echo "Securely uploading OAuth credentials for client: $CLIENT_NAME"
        echo ""

        # Generate random temp filename
        TEMP_NAME="gog_creds_$(date +%s)_$RANDOM.json"
        VM_TEMP_PATH="/tmp/${TEMP_NAME}"
        CONTAINER_TEMP_PATH="/tmp/${TEMP_NAME}"

        # Cleanup function
        cleanup() {
            echo ""
            echo "Cleaning up temporary files..."
            gcloud compute ssh "$VM_NAME" \
                --zone="$GCP_ZONE" \
                --tunnel-through-iap \
                --project="$GCP_PROJECT_ID" \
                --command="rm -f ${VM_TEMP_PATH} 2>/dev/null || true" 2>/dev/null || true
        }

        # Set trap to cleanup on exit
        trap cleanup EXIT

        # Copy to VM
        echo "→ Copying credentials to VM..."
        gcloud compute scp "$CREDS_FILE" "${VM_NAME}:${VM_TEMP_PATH}" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID"

        # Build gog command with optional flags
        GOG_CMD="gog --client ${CLIENT_NAME} auth credentials ${CONTAINER_TEMP_PATH}"
        if [ $# -gt 0 ]; then
            GOG_CMD="${GOG_CMD} $@"
        fi

        # Copy to container, run gog command, delete from container, all in one SSH session
        echo "→ Configuring gogcli in container for client: $CLIENT_NAME"
        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="cd /home/${GCP_VM_USER}/openclaw && \
                docker compose cp ${VM_TEMP_PATH} openclaw-gateway:${CONTAINER_TEMP_PATH} && \
                docker compose exec -T openclaw-gateway ${GOG_CMD} && \
                docker compose exec -T -u root openclaw-gateway rm -f ${CONTAINER_TEMP_PATH}"

        echo ""
        echo "✓ OAuth credentials configured successfully for client: $CLIENT_NAME"
        echo ""
        echo "Next steps:"
        echo "1. Authorize your account:"
        echo "   $0 gog-auth-add $CLIENT_NAME your-email@gmail.com"
        echo ""
        echo "2. Test access:"
        echo "   $0 cli gog --client $CLIENT_NAME gmail labels list"
        ;;

    gog-auth-add)
        if [ $# -lt 2 ]; then
            echo "ERROR: Missing required arguments"
            echo "Usage: $0 gog-auth-add <client-name> <email@gmail.com> [--port <callback-port>]"
            echo ""
            echo "Examples:"
            echo "  $0 gog-auth-add default you@gmail.com"
            echo "  $0 gog-auth-add work you@company.com"
            echo ""
            echo "Note: Gogcli uses a random callback port. To authorize successfully:"
            echo "1. Run the command once to get the authorization URL and callback port"
            echo "2. In a separate terminal, run: gcloud compute ssh $VM_NAME --zone=$GCP_ZONE --tunnel-through-iap --project=$GCP_PROJECT_ID -- -N -L <port>:localhost:<port>"
            echo "3. Visit the authorization URL in your browser"
            echo "4. Complete the OAuth flow"
            exit 1
        fi

        CLIENT_NAME="$1"
        EMAIL="$2"
        shift 2

        # Check if user specified a port to forward
        CALLBACK_PORT=""
        if [ "$1" = "--port" ] && [ -n "$2" ]; then
            CALLBACK_PORT="$2"
            shift 2
        fi

        if [ -n "$CALLBACK_PORT" ]; then
            echo "Authorizing Google account: $EMAIL (client: $CLIENT_NAME)"
            echo "Port forwarding: localhost:$CALLBACK_PORT -> VM:$CALLBACK_PORT"
            echo ""
            echo "The authorization URL will open in your browser..."
            echo ""

            gcloud compute ssh "$VM_NAME" \
                --zone="$GCP_ZONE" \
                --tunnel-through-iap \
                --project="$GCP_PROJECT_ID" \
                --command="cd /home/${GCP_VM_USER}/openclaw && docker compose exec openclaw-gateway gog --client ${CLIENT_NAME} auth add ${EMAIL}" \
                -- -t -L "${CALLBACK_PORT}:localhost:${CALLBACK_PORT}"
        else
            echo "=========================================="
            echo "Google OAuth Authorization Setup"
            echo "=========================================="
            echo ""
            echo "Client: $CLIENT_NAME"
            echo "Email: $EMAIL"
            echo ""
            echo "STEP 1: Run this command first to see the callback port:"
            echo "----------------------------------------"
            echo "gcloud compute ssh $VM_NAME --zone=$GCP_ZONE --tunnel-through-iap --project=$GCP_PROJECT_ID --command='cd /home/${GCP_VM_USER}/openclaw && docker compose exec openclaw-gateway gog --client ${CLIENT_NAME} auth add ${EMAIL}'"
            echo ""
            echo "STEP 2: Look for the port in the URL (e.g., http://127.0.0.1:XXXXX/oauth2/callback)"
            echo ""
            echo "STEP 3: Cancel that command (Ctrl+C) and run this with the port:"
            echo "----------------------------------------"
            echo "$0 gog-auth-add $CLIENT_NAME $EMAIL --port <PORT_NUMBER>"
            echo ""
            echo "Example: $0 gog-auth-add $CLIENT_NAME $EMAIL --port 42313"
            echo ""
            exit 0
        fi

        echo ""
        echo "✓ Authorization complete for client: $CLIENT_NAME"
        echo ""
        echo "Test with:"
        echo "  $0 cli gog --client $CLIENT_NAME gmail labels list"
        ;;

    *)
        echo "Usage: $0 [mode] [args...]"
        echo ""
        echo "Modes:"
        echo "  vm-shell              - Open interactive SSH shell to VM with port forwarding (default)"
        echo "  port-forward          - Start port forwarding for gateway (keeps tunnel open)"
        echo "  shell                 - Open bash shell in openclaw-gateway container"
        echo "  status                - Check systemd service status"
        echo "  logs                  - Stream container logs"
        echo "  cli                   - Run OpenClaw CLI commands"
        echo "  ps                    - Show running containers"
        echo "  restart               - Restart gateway container"
        echo "  stop                  - Stop gateway container"
        echo "  start                 - Start gateway container"
        echo "  gog-auth-credentials  - Securely configure gogcli OAuth credentials"
        echo "  gog-auth-add          - Authorize Google account for gogcli"
        echo ""
        echo "Examples:"
        echo "  $0                                                            # Open SSH shell to VM"
        echo "  $0 port-forward                                               # Forward gateway port"
        echo "  $0 shell                                                      # Open bash in container"
        echo "  $0 status                                                     # Check service status"
        echo "  $0 logs                                                       # Watch logs"
        echo "  $0 cli gateway status                                         # Run CLI command"
        echo "  $0 gog-auth-credentials default ~/Downloads/client_secret.json      # Configure gogcli"
        echo "  $0 gog-auth-credentials work ~/Downloads/work.json --domain company.com"
        echo "  $0 gog-auth-add default you@gmail.com                               # Show OAuth setup instructions"
        echo "  $0 gog-auth-add default you@gmail.com --port 42313                  # Authorize with port forward"
        echo "  $0 cli gog --client default gmail labels list                       # Test gogcli access"
        echo ""
        exit 1
        ;;
esac
