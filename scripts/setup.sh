#!/bin/bash
set -e

# OpenClaw GCP Infrastructure Setup
# One-time script to create all GCP resources

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

# Compute registry host (derived from base vars)
REGISTRY_HOST="${GCP_REGION}-docker.pkg.dev"

# Validate required variables
if ! require_vars GCP_PROJECT_ID; then
    exit 1
fi

if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
    echo "ERROR: OPENCLAW_GATEWAY_TOKEN not set in .openclaw/.env"
    echo "Generate one with: openssl rand -hex 32"
    exit 1
fi

# Set gcloud project
echo "Setting gcloud project to: $GCP_PROJECT_ID"
gcloud config set project "$GCP_PROJECT_ID"

# Enable required APIs
echo ""
echo "Enabling required GCP APIs..."
gcloud services enable compute.googleapis.com --quiet
gcloud services enable artifactregistry.googleapis.com --quiet
gcloud services enable iap.googleapis.com --quiet

# Enable Google Workspace APIs for gogcli
echo "Enabling Google Workspace APIs for gogcli..."
gcloud services enable gmail.googleapis.com --quiet
gcloud services enable calendar-json.googleapis.com --quiet
gcloud services enable chat.googleapis.com --quiet
gcloud services enable drive.googleapis.com --quiet
gcloud services enable classroom.googleapis.com --quiet
gcloud services enable people.googleapis.com --quiet
gcloud services enable tasks.googleapis.com --quiet
gcloud services enable sheets.googleapis.com --quiet
gcloud services enable cloudidentity.googleapis.com --quiet
gcloud services enable docs.googleapis.com --quiet
gcloud services enable slides.googleapis.com --quiet

# Create Artifact Registry repository
echo ""
echo "Creating Artifact Registry repository..."
if gcloud artifacts repositories describe "$GCP_REPO_NAME" \
    --location="$GCP_REGION" &>/dev/null; then
    echo "Repository $GCP_REPO_NAME already exists, skipping..."
else
    gcloud artifacts repositories create "$GCP_REPO_NAME" \
        --repository-format=docker \
        --location="$GCP_REGION" \
        --description="OpenClaw Docker images"
    echo "Repository created successfully"
fi

# Configure Docker authentication
echo ""
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet

# Create VM
echo ""
echo "Creating VM instance: $VM_NAME..."
if gcloud compute instances describe "$VM_NAME" \
    --zone="$GCP_ZONE" &>/dev/null; then
    echo "VM $VM_NAME already exists, skipping..."
    VM_EXISTS=1
else
    # Create Cloud Router for NAT (if not exists)
    ROUTER_NAME="${CLOUD_ROUTER_NAME:-openclaw-router}"
    if ! gcloud compute routers describe "$ROUTER_NAME" \
        --region="$GCP_REGION" &>/dev/null; then
        echo "Creating Cloud Router: $ROUTER_NAME..."
        gcloud compute routers create "$ROUTER_NAME" \
            --network=default \
            --region="$GCP_REGION"
    fi

    # Create Cloud NAT (if not exists)
    NAT_NAME="${CLOUD_NAT_NAME:-openclaw-nat}"
    if ! gcloud compute routers nats describe "$NAT_NAME" \
        --router="$ROUTER_NAME" \
        --region="$GCP_REGION" &>/dev/null; then
        echo "Creating Cloud NAT: $NAT_NAME..."
        gcloud compute routers nats create "$NAT_NAME" \
            --router="$ROUTER_NAME" \
            --region="$GCP_REGION" \
            --auto-allocate-nat-external-ips \
            --nat-all-subnet-ip-ranges
    fi

    # Create VM
    echo "Creating VM: $VM_NAME..."
    gcloud compute instances create "$VM_NAME" \
        --zone="$GCP_ZONE" \
        --machine-type="$MACHINE_TYPE" \
        --boot-disk-size="${BOOT_DISK_SIZE_GB}GB" \
        --boot-disk-type=pd-standard \
        --image-family=debian-12 \
        --image-project=debian-cloud \
        --no-address \
        --network-interface=network-tier=PREMIUM,stack-type=IPV4_ONLY,subnet=default \
        --metadata=enable-oslogin="${ENABLE_OS_LOGIN:-true}" \
        --tags="$NETWORK_TAGS" \
        --scopes=https://www.googleapis.com/auth/cloud-platform

    echo "VM created successfully"
    VM_EXISTS=0
fi

# Create snapshot schedule for automated daily backups
SNAPSHOT_POLICY="openclaw-daily-snapshot"
echo ""
echo "Creating snapshot schedule policy..."
if gcloud compute resource-policies describe "$SNAPSHOT_POLICY" \
    --region="$GCP_REGION" &>/dev/null; then
    echo "Snapshot policy $SNAPSHOT_POLICY already exists, skipping..."
else
    gcloud compute resource-policies create snapshot-schedule "$SNAPSHOT_POLICY" \
        --region="$GCP_REGION" \
        --max-retention-days=7 \
        --daily-schedule \
        --start-time=03:00
    echo "Snapshot policy created"
fi

# Attach snapshot policy to VM boot disk
echo "Attaching snapshot policy to VM disk..."
ATTACHED_POLICIES=$(gcloud compute disks describe "$VM_NAME" \
    --zone="$GCP_ZONE" \
    --format="value(resourcePolicies)" 2>/dev/null || true)
if echo "$ATTACHED_POLICIES" | grep -q "$SNAPSHOT_POLICY"; then
    echo "Snapshot policy already attached, skipping..."
else
    gcloud compute disks add-resource-policies "$VM_NAME" \
        --zone="$GCP_ZONE" \
        --resource-policies="$SNAPSHOT_POLICY"
    echo "Snapshot policy attached"
fi

# Create firewall rule for IAP
echo ""
echo "Creating firewall rule for IAP access..."
if gcloud compute firewall-rules describe allow-iap-ssh &>/dev/null; then
    echo "Firewall rule already exists, skipping..."
else
    gcloud compute firewall-rules create allow-iap-ssh \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=tcp:22 \
        --source-ranges=35.235.240.0/20 \
        --target-tags="$NETWORK_TAGS"
    echo "Firewall rule created"
fi

# Wait for VM to be ready
if [ "$VM_EXISTS" -eq 0 ]; then
    echo ""
    echo "Waiting for VM to be ready..."
    sleep 30
fi

# Initialize VM
echo ""
echo "Initializing VM..."
echo "This will install Docker, configure the system, and set up OpenClaw"
echo ""

# Copy .env to VM
echo "Copying .env to VM..."
gcloud compute scp .env "${VM_NAME}:/tmp/.env" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap

# Copy init-vm.sh to VM and run it
echo "Running VM initialization script..."
gcloud compute scp "${SCRIPT_DIR}/init-vm.sh" "${VM_NAME}:/tmp/init-vm.sh" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap

gcloud compute ssh "$VM_NAME" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap \
    --command="chmod +x /tmp/init-vm.sh && /tmp/init-vm.sh"

echo ""
echo "=========================================="
echo "Setup complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Build and push Docker images:"
echo "   ./scripts/build.sh"
echo ""
echo "2. Deploy OpenClaw:"
echo "   ./scripts/deploy.sh"
echo ""
echo "3. Access the gateway:"
echo "   ./scripts/openclaw.sh forward"
echo "   Then visit: http://localhost:${OPENCLAW_GATEWAY_PORT}"
echo ""
echo "4. View logs:"
echo "   ./scripts/openclaw.sh logs"
echo ""
