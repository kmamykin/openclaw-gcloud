#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../.env"

PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
REGION="${GCP_REGION:?GCP_REGION must be set}"
REPO_NAME="${GCP_REPO_NAME:?GCP_REPO_NAME must be set}"
BUCKET_NAME="${GCS_BUCKET_NAME:?GCS_BUCKET_NAME must be set}"

echo "=== GCP Setup for OpenClaw ==="
echo "Project: ${PROJECT_ID}"
echo "Region: ${REGION}"

# Enable required APIs
echo "Enabling required GCP APIs..."
gcloud services enable \
    artifactregistry.googleapis.com \
    run.googleapis.com \
    storage.googleapis.com \
    places.googleapis.com \
    --project=${PROJECT_ID}

# Configure Docker auth
echo "Configuring Docker authentication..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Create Artifact Registry repository
echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create ${REPO_NAME} \
    --repository-format=docker \
    --location=${REGION} \
    --project=${PROJECT_ID} \
    --description="OpenClaw container images" \
    2>/dev/null || echo "Repository already exists"

# Create GCS bucket
echo "Creating GCS bucket..."
gcloud storage buckets create "gs://${BUCKET_NAME}" \
    --project=${PROJECT_ID} \
    --location=${REGION} \
    --uniform-bucket-level-access \
    2>/dev/null || echo "Bucket already exists"

echo ""
echo "=== Setup Complete ==="
