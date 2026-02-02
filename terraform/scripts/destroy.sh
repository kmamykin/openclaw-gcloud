#!/bin/bash
set -e

# Destroy script for OpenClaw Terraform infrastructure
# This script safely destroys all Terraform-managed resources

echo "=================================="
echo "OpenClaw Terraform Destroy"
echo "=================================="
echo ""
echo "WARNING: This will destroy the following resources:"
echo "  - Compute instance"
echo "  - Service account"
echo "  - Firewall rule"
echo ""
echo "NOTE: Disks are protected with prevent_destroy lifecycle rule."
echo "They must be manually deleted if you want to remove them completely."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

# Get instance info before destroying
INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null || echo "unknown")
BOOT_DISK=$(terraform output -raw boot_disk_name 2>/dev/null || echo "unknown")
DATA_DISK=$(terraform output -raw data_disk_name 2>/dev/null || echo "unknown")

# First confirmation
read -p "Type 'destroy' to confirm destruction: " CONFIRM1

if [ "$CONFIRM1" != "destroy" ]; then
    echo "Destruction cancelled"
    exit 0
fi

# Create destroy plan
echo ""
echo "Creating destroy plan..."
terraform plan -destroy -out=tfplan.destroy

# Show what will be destroyed
echo ""
terraform show -no-color tfplan.destroy | grep -E "^(Plan:|No changes)" || true

# Second confirmation
echo ""
echo "This is your last chance to abort!"
read -p "Are you absolutely sure you want to destroy? (yes/no): " CONFIRM2

if [ "$CONFIRM2" != "yes" ]; then
    echo "Destruction cancelled"
    rm -f tfplan.destroy
    exit 0
fi

# Apply destroy
echo ""
echo "Destroying infrastructure..."
terraform apply tfplan.destroy

# Clean up plan file
rm -f tfplan.destroy

echo ""
echo "=================================="
echo "Destruction Complete!"
echo "=================================="
echo ""
echo "The following disks are protected and were NOT deleted:"
echo "  - $BOOT_DISK"
echo "  - $DATA_DISK"
echo ""
echo "To manually delete disks (THIS WILL DELETE ALL DATA):"
echo "  gcloud compute disks delete $BOOT_DISK --zone=\$(terraform output -raw instance_zone 2>/dev/null || echo 'us-east1-b')"
echo "  gcloud compute disks delete $DATA_DISK --zone=\$(terraform output -raw instance_zone 2>/dev/null || echo 'us-east1-b')"
echo ""
echo "To create snapshots before deletion:"
echo "  gcloud compute disks snapshot $BOOT_DISK --zone=\$(terraform output -raw instance_zone 2>/dev/null || echo 'us-east1-b') --snapshot-names=${BOOT_DISK}-final"
echo "  gcloud compute disks snapshot $DATA_DISK --zone=\$(terraform output -raw instance_zone 2>/dev/null || echo 'us-east1-b') --snapshot-names=${DATA_DISK}-final"
echo ""
