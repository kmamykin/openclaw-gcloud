#!/bin/bash
set -e

# Setup script for OpenClaw Terraform deployment
# This script:
# 1. Verifies prerequisites
# 2. Enables required GCP APIs
# 3. Creates GCS bucket for Terraform state
# 4. Updates backend.tf with bucket name

echo "=================================="
echo "OpenClaw Terraform Setup"
echo "=================================="

# Check for required tools
echo "Checking prerequisites..."

if ! command -v terraform &> /dev/null; then
    echo "ERROR: terraform not found. Install from: https://www.terraform.io/downloads"
    exit 1
fi

if ! command -v gcloud &> /dev/null; then
    echo "ERROR: gcloud not found. Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

TERRAFORM_VERSION=$(terraform version -json | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4)
echo "✓ Terraform version: $TERRAFORM_VERSION"

GCLOUD_VERSION=$(gcloud version --format="value(version)")
echo "✓ gcloud version: $GCLOUD_VERSION"

# Check gcloud authentication
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
    echo "ERROR: Not authenticated with gcloud. Run: gcloud auth login"
    exit 1
fi

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1)
echo "✓ Authenticated as: $ACTIVE_ACCOUNT"

# Check for terraform.tfvars
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

if [ ! -f "$TERRAFORM_DIR/terraform.tfvars" ]; then
    echo "ERROR: terraform.tfvars not found"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and configure it:"
    echo "  cp $TERRAFORM_DIR/terraform.tfvars.example $TERRAFORM_DIR/terraform.tfvars"
    echo "  vim $TERRAFORM_DIR/terraform.tfvars"
    exit 1
fi

# Extract project_id from terraform.tfvars
PROJECT_ID=$(grep '^project_id' "$TERRAFORM_DIR/terraform.tfvars" | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ')

if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "your-project-id" ]; then
    echo "ERROR: project_id not set in terraform.tfvars"
    echo "Please edit terraform.tfvars and set your GCP project ID"
    exit 1
fi

echo "✓ Project ID: $PROJECT_ID"

# Set gcloud project
echo ""
echo "Setting gcloud project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# Enable required APIs
echo ""
echo "Enabling required GCP APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable iap.googleapis.com
gcloud services enable logging.googleapis.com
gcloud services enable monitoring.googleapis.com
gcloud services enable storage.googleapis.com

echo "✓ APIs enabled"

# Create GCS bucket for Terraform state
STATE_BUCKET="${PROJECT_ID}-terraform-state"
echo ""
echo "Creating GCS bucket for Terraform state: $STATE_BUCKET"

if gsutil ls -b "gs://$STATE_BUCKET" &> /dev/null; then
    echo "✓ Bucket already exists: $STATE_BUCKET"
else
    gsutil mb -p "$PROJECT_ID" -l us-east1 "gs://$STATE_BUCKET"
    echo "✓ Bucket created: $STATE_BUCKET"
fi

# Enable versioning on state bucket
echo "Enabling versioning on state bucket..."
gsutil versioning set on "gs://$STATE_BUCKET"
echo "✓ Versioning enabled"

# Update backend.tf with actual bucket name
BACKEND_FILE="$TERRAFORM_DIR/backend.tf"
echo ""
echo "Updating backend.tf with bucket name..."

sed -i.bak "s/REPLACE_WITH_PROJECT_ID-terraform-state/${STATE_BUCKET}/g" "$BACKEND_FILE"

if grep -q "REPLACE_WITH_PROJECT_ID" "$BACKEND_FILE"; then
    echo "ERROR: Failed to update backend.tf"
    exit 1
fi

echo "✓ backend.tf updated"

# Clean up backup file
rm -f "${BACKEND_FILE}.bak"

echo ""
echo "=================================="
echo "Setup complete!"
echo "=================================="
echo ""
echo "Next steps:"
echo "  1. Review your terraform.tfvars configuration"
echo "  2. Run: ./scripts/deploy.sh"
echo ""
