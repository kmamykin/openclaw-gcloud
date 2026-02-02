#!/bin/bash
set -e

# Deployment script for OpenClaw Terraform infrastructure
# This script runs the full terraform workflow with safety checks

echo "=================================="
echo "OpenClaw Terraform Deployment"
echo "=================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

cd "$TERRAFORM_DIR"

# Check if setup has been run
if grep -q "REPLACE_WITH_PROJECT_ID" backend.tf 2>/dev/null; then
    echo "ERROR: Setup not completed. Please run ./scripts/setup.sh first"
    exit 1
fi

# Initialize Terraform
echo ""
echo "Step 1: Initializing Terraform..."
terraform init -upgrade

# Validate configuration
echo ""
echo "Step 2: Validating configuration..."
terraform validate

if [ $? -ne 0 ]; then
    echo "ERROR: Terraform configuration is invalid"
    exit 1
fi

echo "✓ Configuration is valid"

# Check formatting
echo ""
echo "Step 3: Checking formatting..."
terraform fmt -check -recursive || {
    echo "Formatting issues found. Running terraform fmt..."
    terraform fmt -recursive
    echo "✓ Files formatted"
}

# Create plan
echo ""
echo "Step 4: Creating deployment plan..."
terraform plan -out=tfplan

# Show plan summary
echo ""
echo "=================================="
echo "Deployment Plan Summary"
echo "=================================="
terraform show -no-color tfplan | grep -E "^(Plan:|No changes)" || true

# Confirm deployment
echo ""
read -p "Do you want to apply this plan? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    rm -f tfplan
    exit 0
fi

# Apply plan
echo ""
echo "Step 5: Applying plan..."
terraform apply tfplan

# Clean up plan file
rm -f tfplan

# Show outputs
echo ""
echo "=================================="
echo "Deployment Complete!"
echo "=================================="
echo ""
terraform output

echo ""
echo "Next steps:"
echo "  1. Wait 5-10 minutes for startup script to complete"
echo "  2. Check startup progress:"
echo "     gcloud compute instances get-serial-port-output \$(terraform output -raw instance_name) --zone=\$(terraform output -raw instance_zone)"
echo "  3. Verify service status:"
echo "     ./scripts/ssh.sh status"
echo "  4. Connect to gateway:"
echo "     ./scripts/ssh.sh forward"
echo ""
