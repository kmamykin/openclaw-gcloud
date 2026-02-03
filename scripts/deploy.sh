#!/bin/bash
set -e

# Deploy OpenClaw to GCP VM
# Optionally builds new images first

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
    echo "ERROR: VM_NAME and GCP_ZONE must be set in .env"
    exit 1
fi

# Parse arguments
BUILD_FIRST=0
if [ "$1" = "--build" ] || [ "$1" = "-b" ]; then
    BUILD_FIRST=1
fi

# Optionally build new images
if [ $BUILD_FIRST -eq 1 ]; then
    echo "Building new images first..."
    "${SCRIPT_DIR}/build.sh"
    echo ""
fi

echo "=========================================="
echo "Deploying OpenClaw to VM: $VM_NAME"
echo "=========================================="
echo ""

# Check if VM exists
if ! gcloud compute instances describe "$VM_NAME" --zone="$GCP_ZONE" &>/dev/null; then
    echo "ERROR: VM $VM_NAME not found in zone $GCP_ZONE"
    echo "Run ./scripts/setup.sh first"
    exit 1
fi

# Create docker-compose.yml from template
echo "Creating docker-compose.yml from template..."
envsubst < docker-compose.yml.tpl > /tmp/docker-compose.yml

# Copy files to VM
echo "Copying files to VM..."
gcloud compute scp /tmp/docker-compose.yml "${VM_NAME}:/home/${GCP_VM_USER}/openclaw/docker-compose.yml" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap

gcloud compute scp .env "${VM_NAME}:/home/${GCP_VM_USER}/openclaw/.env" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap

echo "✓ Files copied"

# Deploy on VM
echo ""
echo "Deploying container on VM..."

DEPLOY_SCRIPT=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -e

cd /home/${GCP_VM_USER}/openclaw

# Source .env
set -a
source .env
set +a

echo "Pulling latest image..."
docker compose pull openclaw-gateway

echo "Stopping current container..."
docker compose down || true

echo "Starting new container..."
docker compose up -d openclaw-gateway

echo "Waiting for container to be ready..."
sleep 5

# Check if container is running
if ! docker compose ps | grep openclaw-gateway | grep -q Up; then
    echo "ERROR: Container failed to start"
    echo "Logs:"
    docker compose logs openclaw-gateway
    exit 1
fi

# Check for first-time setup
OPENCLAW_CONFIG="/home/${GCP_VM_USER}/.openclaw/openclaw.json"
if [ ! -f "$OPENCLAW_CONFIG" ]; then
    echo ""
    echo "First-time setup detected - running onboarding..."

    # Wait a bit more for gateway to be fully ready
    sleep 10

    # Run onboarding non-interactively
    docker compose run --rm openclaw-cli gateway onboard --token "${OPENCLAW_GATEWAY_TOKEN}"

    echo "✓ Onboarding complete"
fi

echo ""
echo "Container started successfully"
EOFSCRIPT
)

gcloud compute ssh "$VM_NAME" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap \
    --command="$DEPLOY_SCRIPT"

# Show logs
echo ""
echo "Showing recent logs..."
gcloud compute ssh "$VM_NAME" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap \
    --command="cd /home/${GCP_VM_USER}/openclaw && docker compose logs --tail=50 openclaw-gateway"

echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo ""
echo "Access the gateway:"
echo "  1. Start port forwarding:"
echo "     ./scripts/ssh.sh forward"
echo ""
echo "  2. Visit in browser:"
echo "     http://localhost:${OPENCLAW_GATEWAY_PORT}"
echo ""
echo "  3. Authenticate with token from .env"
echo ""
echo "View logs:"
echo "  ./scripts/ssh.sh logs"
echo ""
echo "Run CLI commands:"
echo "  ./scripts/ssh.sh cli gateway status"
echo ""
