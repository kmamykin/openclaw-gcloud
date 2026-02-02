#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
REGION="${GCP_REGION:?GCP_REGION must be set}"
SERVICE_NAME="${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE must be set}"

echo "=== Removing OpenClaw from Cloud Run ==="
echo "Service: ${SERVICE_NAME}"
echo "Region: ${REGION}"
echo "Project: ${PROJECT_ID}"
echo ""

read -p "Are you sure you want to delete the service? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

gcloud run services delete ${SERVICE_NAME} \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --quiet

echo ""
echo "=== Service Removed ==="
