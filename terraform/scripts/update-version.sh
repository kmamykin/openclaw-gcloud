#!/bin/bash
set -e

# Script to update OpenClaw version on deployed instance
# Updates terraform.tfvars and runs npm install on the instance

if [ -z "$1" ]; then
    echo "Usage: $0 <new-version>"
    echo ""
    echo "Example: $0 2026.2.1"
    exit 1
fi

NEW_VERSION="$1"

# Validate version format
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$'; then
    echo "ERROR: Invalid version format. Expected: YYYY.M.D or YYYY.MM.DD"
    echo "Example: 2026.2.1 or 2026.02.01"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

# Get instance info
INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null)
INSTANCE_ZONE=$(terraform output -raw instance_zone 2>/dev/null)
PROJECT_ID=$(terraform output -json | grep -A 1 '"ssh_command"' | grep 'project=' | sed 's/.*project=\([^"]*\).*/\1/')

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ]; then
    echo "ERROR: Could not get instance information from Terraform"
    echo "Make sure the instance is deployed"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(grep '^openclaw_version' terraform.tfvars 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' || echo "unknown")

echo "=================================="
echo "OpenClaw Version Update"
echo "=================================="
echo "Current version: $CURRENT_VERSION"
echo "New version: $NEW_VERSION"
echo "Instance: $INSTANCE_NAME"
echo ""

read -p "Proceed with update? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Update cancelled"
    exit 0
fi

# Update terraform.tfvars
echo ""
echo "Step 1: Updating terraform.tfvars..."

if grep -q '^openclaw_version' terraform.tfvars; then
    # Uncomment and update if commented
    sed -i.bak "s/^#\?\s*openclaw_version\s*=.*/openclaw_version = \"$NEW_VERSION\"/" terraform.tfvars
else
    # Add if not present
    echo "" >> terraform.tfvars
    echo "openclaw_version = \"$NEW_VERSION\"" >> terraform.tfvars
fi

rm -f terraform.tfvars.bak
echo "✓ terraform.tfvars updated"

# Update openclaw on the instance
echo ""
echo "Step 2: Installing openclaw@$NEW_VERSION on instance..."

gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="sudo npm install -g openclaw@$NEW_VERSION"

# Restart service
echo ""
echo "Step 3: Restarting service..."

gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="sudo systemctl restart openclaw-gateway"

# Wait for service to start
echo "Waiting for service to restart..."
sleep 5

# Verify installation
echo ""
echo "Step 4: Verifying installation..."

INSTALLED_VERSION=$(gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="openclaw --version" 2>/dev/null | tr -d '\r\n')

SERVICE_STATUS=$(gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="sudo systemctl is-active openclaw-gateway" 2>/dev/null | tr -d '\r\n')

echo ""
echo "=================================="
echo "Update Complete!"
echo "=================================="
echo "Installed version: $INSTALLED_VERSION"
echo "Service status: $SERVICE_STATUS"
echo ""

if [ "$SERVICE_STATUS" != "active" ]; then
    echo "WARNING: Service is not active!"
    echo "Check logs with: ./scripts/ssh.sh logs"
    exit 1
fi

echo "Test the gateway:"
echo "  ./scripts/ssh.sh forward"
echo ""
