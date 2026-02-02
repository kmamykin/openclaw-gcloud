#!/bin/bash
set -e

# Script to migrate data from Cloud Run (GCS) to Compute Engine (local disk)
# Downloads data from GCS and uploads to VM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$TERRAFORM_DIR")"

cd "$TERRAFORM_DIR"

echo "=================================="
echo "OpenClaw Data Migration"
echo "=================================="

# Get instance info
INSTANCE_NAME=$(terraform output -raw instance_name 2>/dev/null)
INSTANCE_ZONE=$(terraform output -raw instance_zone 2>/dev/null)
PROJECT_ID=$(terraform output -json | grep -A 1 '"ssh_command"' | grep 'project=' | sed 's/.*project=\([^"]*\).*/\1/')

if [ -z "$INSTANCE_NAME" ] || [ -z "$INSTANCE_ZONE" ]; then
    echo "ERROR: Could not get instance information from Terraform"
    echo "Make sure the instance is deployed"
    exit 1
fi

# Read GCS bucket name from parent .env file
ENV_FILE="$PROJECT_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

# Source .env to get GCS_BUCKET_NAME
set -a
source "$ENV_FILE"
set +a

if [ -z "$GCS_BUCKET_NAME" ]; then
    echo "ERROR: GCS_BUCKET_NAME not set in .env"
    echo "Cannot determine source bucket for migration"
    exit 1
fi

GCS_BUCKET="gs://$GCS_BUCKET_NAME"

echo "Source: $GCS_BUCKET"
echo "Destination: $INSTANCE_NAME:/home/node/.openclaw/"
echo ""

# Check if bucket exists and has data
if ! gsutil ls "$GCS_BUCKET" &> /dev/null; then
    echo "ERROR: Cannot access bucket $GCS_BUCKET"
    echo "Make sure it exists and you have permissions"
    exit 1
fi

FILE_COUNT=$(gsutil ls -r "$GCS_BUCKET" | grep -v "/$" | wc -l)

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "WARNING: No files found in $GCS_BUCKET"
    echo "Nothing to migrate"
    exit 0
fi

echo "Found $FILE_COUNT files to migrate"
echo ""

read -p "Proceed with migration? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Migration cancelled"
    exit 0
fi

# Create temporary directory for download
TEMP_DIR="$PROJECT_ROOT/migration-data"
mkdir -p "$TEMP_DIR"

echo ""
echo "Step 1: Downloading data from GCS..."
gsutil -m cp -r "$GCS_BUCKET/*" "$TEMP_DIR/" || {
    echo "ERROR: Failed to download from GCS"
    exit 1
}

echo "✓ Downloaded to $TEMP_DIR"

# List what we downloaded
echo ""
echo "Downloaded files:"
ls -lah "$TEMP_DIR"

# Stop the service before migration
echo ""
echo "Step 2: Stopping OpenClaw service..."
gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="sudo systemctl stop openclaw-gateway"

echo "✓ Service stopped"

# Upload data to instance
echo ""
echo "Step 3: Uploading data to instance..."
gcloud compute scp \
    --recurse \
    --tunnel-through-iap \
    --zone="$INSTANCE_ZONE" \
    --project="$PROJECT_ID" \
    "$TEMP_DIR"/* \
    "$INSTANCE_NAME:/tmp/openclaw-migration/"

echo "✓ Data uploaded"

# Move data to correct location and fix permissions
echo ""
echo "Step 4: Installing data on instance..."
gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="sudo mv /tmp/openclaw-migration/* /home/node/.openclaw/ && \
               sudo chown -R node:node /home/node/.openclaw && \
               sudo rm -rf /tmp/openclaw-migration"

echo "✓ Data installed"

# Restart service
echo ""
echo "Step 5: Starting OpenClaw service..."
gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="sudo systemctl start openclaw-gateway"

echo "Waiting for service to start..."
sleep 5

# Check service status
SERVICE_STATUS=$(gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="sudo systemctl is-active openclaw-gateway" 2>/dev/null | tr -d '\r\n')

echo "✓ Service status: $SERVICE_STATUS"

# Verify data
echo ""
echo "Step 6: Verifying migrated data..."
gcloud compute ssh "$INSTANCE_NAME" \
    --zone="$INSTANCE_ZONE" \
    --tunnel-through-iap \
    --project="$PROJECT_ID" \
    --command="ls -lah /home/node/.openclaw"

echo ""
echo "=================================="
echo "Migration Complete!"
echo "=================================="
echo ""
echo "The temporary download directory is still at:"
echo "  $TEMP_DIR"
echo ""
echo "You can safely delete it after verifying the migration:"
echo "  rm -rf $TEMP_DIR"
echo ""
echo "Test the gateway:"
echo "  ./scripts/ssh.sh forward"
echo ""
echo "If migration was successful, you can undeploy Cloud Run:"
echo "  cd $PROJECT_ROOT"
echo "  ./gcloud-undeploy.sh"
echo ""
