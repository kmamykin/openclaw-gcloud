#!/bin/bash
set -e

# Configuration (can be overridden via environment)
PROJECT_ID="${GCP_PROJECT_ID:-your-project-id}"
REGION="${GCP_REGION:-us-central1}"
REPO_NAME="${GCP_REPO_NAME:-openclaw-repo}"
SERVICE_NAME="${CLOUD_RUN_SERVICE:-openclaw}"
BUCKET_NAME="${GCS_BUCKET_NAME:-${PROJECT_ID}-openclaw-data}"
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
    --port=3000 \
    --memory=2Gi \
    --cpu=2 \
    --min-instances=0 \
    --max-instances=1 \
    --timeout=3600 \
    --allow-unauthenticated \
    --set-env-vars="NODE_OPTIONS=--max-old-space-size=1536" \
    --set-env-vars="OPENCLAW_STATE_DIR=/data" \
    --set-env-vars="OPENCLAW_WORKSPACE_DIR=/data/workspace" \
    --set-env-vars="OPENCLAW_GATEWAY_BIND=lan" \
    --add-volume=name=openclaw-data,type=cloud-storage,bucket=${BUCKET_NAME} \
    --add-volume-mount=volume=openclaw-data,mount-path=/data \
    --command="node" \
    --args="dist/index.js,gateway,--allow-unconfigured,--port,3000,--bind,lan"

echo ""
echo "=== Deployment Complete ==="
gcloud run services describe ${SERVICE_NAME} --region=${REGION} --project=${PROJECT_ID} --format="value(status.url)"
