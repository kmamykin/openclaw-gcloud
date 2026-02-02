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

BASE_IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/openclaw:latest"
IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/openclaw-cloud:latest"

echo "=== Deploying OpenClaw to Cloud Run ==="
echo "Service: ${SERVICE_NAME}"
echo "Image: ${IMAGE_PATH}"

# Build multi-arch images (arm64 for local, amd64 for Cloud Run)
# First, push base image to registry so buildx can access both architectures
echo "Building and pushing base image for linux/amd64,linux/arm64..."
docker buildx build --platform linux/amd64,linux/arm64 -t ${BASE_IMAGE_PATH} --push ./openclaw

echo "Building and pushing openclaw-cloud for linux/amd64,linux/arm64..."
docker buildx build --platform linux/amd64,linux/arm64 \
    --build-arg BASE_IMAGE=${BASE_IMAGE_PATH} \
    -t ${IMAGE_PATH} --push .

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
    --no-allow-unauthenticated \
    --set-env-vars="NODE_OPTIONS=--max-old-space-size=1536" \
    --set-env-vars="HOME=/home/node" \
    --set-env-vars="TERM=xterm-256color" \
    --set-env-vars="OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}" \
    --set-env-vars="OPENCLAW_GATEWAY_BIND=${GATEWAY_BIND}" \
    --add-volume=name=openclaw-data,type=cloud-storage,bucket=${BUCKET_NAME} \
    --add-volume-mount=volume=openclaw-data,mount-path=/home/node/.openclaw \
    --command="/bin/sh" \
    --args="-c,node /app/dist/index.js gateway --allow-unconfigured --port ${GATEWAY_PORT} --bind ${GATEWAY_BIND} --verbose"

echo ""
echo "=== Deployment Complete ==="
gcloud run services describe ${SERVICE_NAME} --region=${REGION} --project=${PROJECT_ID} --format="value(status.url)"
