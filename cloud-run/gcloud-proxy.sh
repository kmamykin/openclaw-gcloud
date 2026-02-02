#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../.env"

PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
REGION="${GCP_REGION:?GCP_REGION must be set}"
SERVICE_NAME="${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE must be set}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:?OPENCLAW_GATEWAY_PORT must be set}"

echo "Starting proxy to ${SERVICE_NAME}..."
echo "Connect to: http://localhost:${GATEWAY_PORT}"

gcloud run services proxy ${SERVICE_NAME} \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --port=${GATEWAY_PORT}
