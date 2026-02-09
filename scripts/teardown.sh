#!/bin/bash
set -e

# OpenClaw GCP Infrastructure Teardown
# Removes all GCP resources created by setup.sh

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
if ! require_vars GCP_PROJECT_ID; then
    exit 1
fi

# Set gcloud project
echo "Setting gcloud project to: $GCP_PROJECT_ID"
gcloud config set project "$GCP_PROJECT_ID"

# Confirmation prompt
echo ""
echo "=========================================="
echo "WARNING: This will DELETE the following resources:"
echo "=========================================="
echo "- VM instance: $VM_NAME"
echo "- Snapshot policy: openclaw-daily-snapshot"
echo "- Snapshots for VM: $VM_NAME"
echo "- Firewall rule: allow-iap-ssh"
echo "- Cloud NAT: ${CLOUD_NAT_NAME:-openclaw-nat}"
echo "- Cloud Router: ${CLOUD_ROUTER_NAME:-openclaw-router}"
echo "- Artifact Registry: $GCP_REPO_NAME"
echo ""
echo "Project: $GCP_PROJECT_ID"
echo "Region: $GCP_REGION"
echo "Zone: $GCP_ZONE"
echo ""
read -p "Are you sure you want to proceed? (yes/no): " CONFIRMATION

if [ "$CONFIRMATION" != "yes" ]; then
    echo "Teardown cancelled"
    exit 0
fi

echo ""
echo "Starting teardown..."

# Delete VM instance
echo ""
echo "Deleting VM instance: $VM_NAME..."
if gcloud compute instances describe "$VM_NAME" \
    --zone="$GCP_ZONE" &>/dev/null; then
    gcloud compute instances delete "$VM_NAME" \
        --zone="$GCP_ZONE" \
        --quiet
    echo "VM deleted"
else
    echo "VM $VM_NAME does not exist, skipping..."
fi

# Delete snapshot policy
SNAPSHOT_POLICY="openclaw-daily-snapshot"
echo ""
echo "Deleting snapshot policy: $SNAPSHOT_POLICY..."
if gcloud compute resource-policies describe "$SNAPSHOT_POLICY" \
    --region="$GCP_REGION" &>/dev/null; then
    gcloud compute resource-policies delete "$SNAPSHOT_POLICY" \
        --region="$GCP_REGION" \
        --quiet
    echo "Snapshot policy deleted"
else
    echo "Snapshot policy does not exist, skipping..."
fi

# Delete remaining snapshots for this VM
echo ""
echo "Deleting snapshots for VM: $VM_NAME..."
SNAPSHOTS=$(gcloud compute snapshots list \
    --filter="sourceDisk~${VM_NAME}$" \
    --format="value(name)" 2>/dev/null || true)
if [ -n "$SNAPSHOTS" ]; then
    echo "$SNAPSHOTS" | while read -r SNAP; do
        echo "  Deleting snapshot: $SNAP"
        gcloud compute snapshots delete "$SNAP" --quiet
    done
    echo "Snapshots deleted"
else
    echo "No snapshots found, skipping..."
fi

# Delete firewall rule
echo ""
echo "Deleting firewall rule: allow-iap-ssh..."
if gcloud compute firewall-rules describe allow-iap-ssh &>/dev/null; then
    gcloud compute firewall-rules delete allow-iap-ssh --quiet
    echo "Firewall rule deleted"
else
    echo "Firewall rule does not exist, skipping..."
fi

# Delete Cloud NAT
NAT_NAME="${CLOUD_NAT_NAME:-openclaw-nat}"
ROUTER_NAME="${CLOUD_ROUTER_NAME:-openclaw-router}"

echo ""
echo "Deleting Cloud NAT: $NAT_NAME..."
if gcloud compute routers nats describe "$NAT_NAME" \
    --router="$ROUTER_NAME" \
    --region="$GCP_REGION" &>/dev/null; then
    gcloud compute routers nats delete "$NAT_NAME" \
        --router="$ROUTER_NAME" \
        --region="$GCP_REGION" \
        --quiet
    echo "Cloud NAT deleted"
else
    echo "Cloud NAT does not exist, skipping..."
fi

# Delete Cloud Router
echo ""
echo "Deleting Cloud Router: $ROUTER_NAME..."
if gcloud compute routers describe "$ROUTER_NAME" \
    --region="$GCP_REGION" &>/dev/null; then
    gcloud compute routers delete "$ROUTER_NAME" \
        --region="$GCP_REGION" \
        --quiet
    echo "Cloud Router deleted"
else
    echo "Cloud Router does not exist, skipping..."
fi

# Delete Artifact Registry repository
echo ""
echo "Deleting Artifact Registry repository: $GCP_REPO_NAME..."
if gcloud artifacts repositories describe "$GCP_REPO_NAME" \
    --location="$GCP_REGION" &>/dev/null; then
    gcloud artifacts repositories delete "$GCP_REPO_NAME" \
        --location="$GCP_REGION" \
        --quiet
    echo "Repository deleted"
else
    echo "Repository does not exist, skipping..."
fi

echo ""
echo "=========================================="
echo "Teardown complete!"
echo "=========================================="
echo ""
echo "All OpenClaw infrastructure has been removed."
echo ""
echo "Note: GCP APIs remain enabled and can be used by other resources."
echo "To disable them manually, run:"
echo "  gcloud services disable compute.googleapis.com"
echo "  gcloud services disable artifactregistry.googleapis.com"
echo "  gcloud services disable iap.googleapis.com"
echo ""
