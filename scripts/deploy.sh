#!/bin/bash
set -e

# Deploy OpenClaw to GCP VM
# Optionally builds new images first

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
require_vars VM_NAME GCP_ZONE GCP_REGION GCP_PROJECT_ID GCP_REPO_NAME || exit 1

ensure_ssh_config

# Compute registry path (derived from base vars)
export REGISTRY_HOST="${GCP_REGION}-docker.pkg.dev"
export REGISTRY="${REGISTRY_HOST}/${GCP_PROJECT_ID}/${GCP_REPO_NAME}"

# Parse arguments
BUILD_FIRST=0
SKIP_SYNC=0
for arg in "$@"; do
    case "$arg" in
        --build|-b) BUILD_FIRST=1 ;;
        --no-sync) SKIP_SYNC=1 ;;
    esac
done

# Optionally build new images
if [ $BUILD_FIRST -eq 1 ]; then
    echo "Building new images first..."
    "${SCRIPT_DIR}/build.sh" --push
    echo ""
fi

# Sync .openclaw changes to VM before deploy
if [ $SKIP_SYNC -eq 0 ] && [ -d .openclaw/.git ]; then
    echo "Syncing .openclaw to VM..."
    "${SCRIPT_DIR}/openclaw.sh" push
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
envsubst < docker/docker-compose.yml.tpl > /tmp/docker-compose.yml

# Copy files to VM
scp /tmp/docker-compose.yml "$VM_HOST:$VM_DIR/docker-compose.yml"

echo "Files copied"

# Deploy on VM
echo ""
echo "Deploying container on VM..."

DEPLOY_SCRIPT=$(cat <<EOFSCRIPT
#!/bin/bash
set -e

cd /home/${GCP_VM_USER}/openclaw

# Source openclaw env for docker compose
set -a
[ -f .openclaw/.env ] && source .openclaw/.env
set +a

# Ensure tmp dirs exist with correct ownership before docker compose creates them as root
sudo install -d -o ${GCP_VM_USER} -g ${GCP_VM_USER} tmp tmp/gateway tmp/cli

docker compose pull openclaw-gateway

docker compose down || true

docker compose up -d openclaw-gateway

sleep 5

# Check if container is running
if ! docker compose ps | grep openclaw-gateway | grep -q Up; then
    echo "ERROR: Container failed to start"
    echo "Logs:"
    docker compose logs openclaw-gateway
    exit 1
fi

echo ""
echo "Container started successfully"
EOFSCRIPT
)

ssh "$VM_HOST" "$DEPLOY_SCRIPT"

# Show logs
echo ""
ssh "$VM_HOST" "cd $VM_DIR && docker compose logs --tail=50 openclaw-gateway"

echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo ""
echo "Access the gateway:"
echo "  1. Start port forwarding:"
echo "     ./scripts/openclaw.sh forward"
echo ""
echo "  2. Visit in browser:"
echo "     http://localhost:${OPENCLAW_GATEWAY_PORT}"
echo ""
echo "  3. Authenticate with token from .openclaw/.env"
echo ""
echo "View logs:"
echo "  ./scripts/openclaw.sh logs"
echo ""
