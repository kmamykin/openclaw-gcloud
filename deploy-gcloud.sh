#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

# Configuration (required environment variables)
PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
REGION="${GCP_REGION:?GCP_REGION must be set}"
REPO_NAME="${GCP_REPO_NAME:?GCP_REPO_NAME must be set}"
SERVICE_NAME="${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE must be set}"
BUCKET_NAME="${GCS_BUCKET_NAME:?GCS_BUCKET_NAME must be set}"
GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN must be set}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:?OPENCLAW_GATEWAY_PORT must be set}"
GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:?OPENCLAW_GATEWAY_BIND must be set}"
IMAGE_NAME="openclaw-cloud"

# Full image path
IMAGE_PATH="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}/${IMAGE_NAME}:latest"

echo "=== Google Cloud Run Deployment ==="
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Repository: ${REPO_NAME}"
echo "Service: ${SERVICE_NAME}"
echo "Bucket: ${BUCKET_NAME}"
echo "Image: ${IMAGE_PATH}"
echo ""

# Step 1: Authenticate (if not already)
echo "Ensuring gcloud authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Step 2: Create Artifact Registry repository (if it doesn't exist)
echo "Creating Artifact Registry repository (if needed)..."
gcloud artifacts repositories create ${REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --project=${PROJECT_ID} \
    --description="OpenClaw container images" \
    2>/dev/null || echo "Repository already exists"

# Step 3: Create GCS bucket for persistent storage (if it doesn't exist)
echo "Creating GCS bucket for persistent storage (if needed)..."
gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project=${PROJECT_ID} \
    --location=${REGION} \
    --uniform-bucket-level-access \
    2>/dev/null || echo "Bucket already exists"

# Step 4: Build and push the image
echo "Building and pushing image to Artifact Registry..."
docker tag openclaw-cloud:latest ${IMAGE_PATH}
docker push ${IMAGE_PATH}

# Step 5: Deploy to Cloud Run with GCS FUSE volume mount
echo "Deploying to Cloud Run with GCS volume mount..."
gcloud run deploy ${SERVICE_NAME} \
    --image=${IMAGE_PATH} \
    --platform=managed \
    --region=${REGION} \
    --project=${PROJECT_ID} \
    --execution-environment=gen2 \
    --port=${GATEWAY_PORT} \
    --memory=2Gi \
    --cpu=2 \
    --min-instances=0 \
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
