#!/bin/bash
set -e

# Build OpenClaw cloud-extended Docker image (always linux/amd64)
# Mac runs amd64 images via Rosetta — no need for separate arch builds
#
# Usage:
#   ./scripts/build.sh          # Build image locally
#   ./scripts/build.sh --push   # Build + push to Artifact Registry

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/path.sh"
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/validation.sh"

# Get project root and change to it
PROJECT_ROOT="$(get_project_root)"
cd "$PROJECT_ROOT"

# Load environment
load_env || exit 1

# Parse arguments
PUSH=0
if [ "$1" = "--push" ] || [ "$1" = "-p" ]; then
    PUSH=1
fi

# For push builds, compute registry path and validate
if [ $PUSH -eq 1 ]; then
    require_vars GCP_PROJECT_ID GCP_REGION GCP_REPO_NAME || exit 1
    REGISTRY_HOST="${GCP_REGION}-docker.pkg.dev"
    REGISTRY="${REGISTRY_HOST}/${GCP_PROJECT_ID}/${GCP_REPO_NAME}"
    IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
fi

# Compute base image from OPENCLAW_VERSION
OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
BASE_IMAGE="ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}"

echo ""
echo "=========================================="
echo "Building OpenClaw Cloud Image"
echo "=========================================="
echo "Base image:  ${BASE_IMAGE}"
echo "Platform:    linux/amd64"
if [ $PUSH -eq 1 ]; then
echo "Registry:    $REGISTRY"
echo "Tag:         $IMAGE_TAG"
fi
echo "=========================================="
echo ""

# Pull base image (ensures latest for :latest tag)
echo "Pulling base image: ${BASE_IMAGE}..."
docker pull --platform linux/amd64 "${BASE_IMAGE}"
echo ""

# Build cloud-extended image
echo "Building cloud image: openclaw-cloud:latest..."
docker buildx build --platform linux/amd64 --load \
    --build-arg BASE_IMAGE="${BASE_IMAGE}" \
    -f docker/Dockerfile -t openclaw-cloud:latest docker/
echo "Cloud image built"

if [ $PUSH -eq 1 ]; then
    # Tag cloud image
    echo ""
    docker tag openclaw-cloud:latest "${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
    docker tag openclaw-cloud:latest "${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"
    echo "Tagged: ${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
    echo "Tagged: ${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"

    # Push cloud image
    echo ""
    echo "Pushing image to Artifact Registry..."
    echo ""
    docker push "${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
    docker push "${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"
    echo "Pushed cloud image"

    echo ""
    echo "=========================================="
    echo "Build complete!"
    echo "=========================================="
    echo ""
    echo "Images pushed:"
    echo "  ${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
    echo "  ${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"
    echo ""
    echo "Next steps:"
    echo "  Deploy to VM: ./scripts/deploy.sh"
    echo ""
else
    echo ""
    echo "=========================================="
    echo "Build complete!"
    echo "=========================================="
    echo ""
    echo "Image: openclaw-cloud:latest"
    echo ""
    echo "Next steps:"
    echo "  Run locally:       ./scripts/local.sh start"
    echo "  Push to registry:  ./scripts/build.sh --push"
    echo ""
fi
