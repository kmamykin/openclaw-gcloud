#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
REGION="${GCP_REGION:?GCP_REGION must be set}"
REPO_NAME="${GCP_REPO_NAME:?GCP_REPO_NAME must be set}"
SERVICE_NAME="${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE must be set}"
BUCKET_NAME="${GCS_BUCKET_NAME:?GCS_BUCKET_NAME must be set}"
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN must be set}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:?OPENCLAW_GATEWAY_PORT must be set}"
GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:?OPENCLAW_GATEWAY_BIND must be set}"

IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/openclaw-cloud:latest"

echo "=== Deploying OpenClaw to Cloud Run ==="
echo "Service: ${SERVICE_NAME}"
echo "Image: ${IMAGE_PATH}"

# Tag and push image
echo "Pushing image to Artifact Registry..."
docker tag openclaw-cloud:latest ${IMAGE_PATH}
docker push ${IMAGE_PATH}

# Deploy to Cloud Run (creates or updates)
echo "Deploying to Cloud Run..."
gcloud run deploy ${SERVICE_NAME} \
    --image=${IMAGE_PATH} \
    --platform=managed \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --execution-environment=gen2 \
    --port=${GATEWAY_PORT} \
    --memory=2Gi \
    --cpu=1 \
    --min-instances=1 \
    --max-instances=1 \
    --timeout=3600 \
    --allow-unauthenticated \
    --set-env-vars="NODE_OPTIONS=--max-old-space-size=1536" \
    --set-env-vars="HOME=/home/node" \
    --set-env-vars="TERM=xterm-256color" \
    --set-env-vars="OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}" \
    --set-env-vars="OPENCLAW_GATEWAY_BIND=${GATEWAY_BIND}" \
    --add-volume=name=openclaw-data,type=cloud-storage,bucket=${BUCKET_NAME} \
    --add-volume-mount=volume=openclaw-data,mount-path=/home/node/.openclaw \
    --command="node" \
    --args="dist/index.js,gateway,--allow-unconfigured,--port,${GATEWAY_PORT},--bind,${GATEWAY_BIND}"

echo ""
echo "=== Deployment Complete ==="
gcloud run services describe ${SERVICE_NAME} --region=${REGION} --project=${PROJECT_ID} --format="value(status.url)"
