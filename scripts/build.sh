#!/bin/bash
set -e

# Build and push OpenClaw cloud-extended Docker image
# Uses pre-built base image from ghcr.io/openclaw/openclaw
#
# Usage:
#   ./scripts/build.sh          # Build for amd64 (VM) + push to registry
#   ./scripts/build.sh --local  # Build for native platform (arm64 on Mac), no push

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
LOCAL_BUILD=0
if [ "$1" = "--local" ] || [ "$1" = "-l" ]; then
    LOCAL_BUILD=1
fi

# For remote builds, compute registry path and validate
if [ $LOCAL_BUILD -eq 0 ]; then
    require_vars GCP_PROJECT_ID GCP_REGION GCP_REPO_NAME || exit 1
    REGISTRY_HOST="${GCP_REGION}-docker.pkg.dev"
    REGISTRY="${REGISTRY_HOST}/${GCP_PROJECT_ID}/${GCP_REPO_NAME}"
fi

# Compute base image from OPENCLAW_VERSION
OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
BASE_IMAGE="ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}"

if [ $LOCAL_BUILD -eq 1 ]; then
    echo ""
    echo "=========================================="
    echo "Building OpenClaw Cloud Image (local)"
    echo "=========================================="
    echo "Base image:  ${BASE_IMAGE}"
    echo "Platform:    native ($(uname -m))"
    echo "=========================================="
    echo ""

    # Pull base image (ensures latest for :latest tag)
    echo "Pulling base image: ${BASE_IMAGE}..."
    docker pull "${BASE_IMAGE}"
    echo ""

    # Build cloud-extended image
    echo "Building cloud image: openclaw-cloud:latest..."
    docker buildx build --load \
        --build-arg BASE_IMAGE="${BASE_IMAGE}" \
        -f docker/Dockerfile -t openclaw-cloud:latest docker/
    echo "Cloud image built"

    echo ""
    echo "=========================================="
    echo "Local build complete!"
    echo "=========================================="
    echo ""
    echo "Image: openclaw-cloud:latest"
    echo ""
    echo "Next steps:"
    echo "  Run locally: ./scripts/local.sh start"
    echo ""
else
    # Generate image tag
    IMAGE_TAG=$(date +%Y%m%d-%H%M%S)

    echo ""
    echo "=========================================="
    echo "Building OpenClaw Cloud Image"
    echo "=========================================="
    echo "Base image:  ${BASE_IMAGE}"
    echo "Cloud image: openclaw-cloud:latest"
    echo "Registry:    $REGISTRY"
    echo "Tag:         $IMAGE_TAG"
    echo "=========================================="
    echo ""

    # Pull base image (ensures latest for :latest tag)
    echo "Pulling base image: ${BASE_IMAGE}..."
    docker pull --platform linux/amd64 "${BASE_IMAGE}"
    echo ""

    # Build cloud-extended image
    echo "Building cloud image: openclaw-cloud:latest (for linux/amd64)..."
    docker buildx build --platform linux/amd64 --load \
        --build-arg BASE_IMAGE="${BASE_IMAGE}" \
        -f docker/Dockerfile -t openclaw-cloud:latest docker/
    echo "Cloud image built"

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
fi
