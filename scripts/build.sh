#!/bin/bash
set -e

# Build and push OpenClaw Docker images
# Builds both base openclaw and cloud-extended images

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Load environment variables
if [ ! -f .env ]; then
    echo "ERROR: .env file not found"
    exit 1
fi

# Source .env
set -a
source .env
set +a

# Validate required variables
if [ -z "$GCP_PROJECT_ID" ] || [ -z "$REGISTRY" ]; then
    echo "ERROR: GCP_PROJECT_ID and REGISTRY must be set in .env"
    exit 1
fi

# Check if openclaw directory exists
if [ ! -d "openclaw" ]; then
    echo "ERROR: openclaw directory not found"
    echo "Please clone the OpenClaw repository:"
    echo "  git clone https://github.com/openclaw/openclaw.git"
    exit 1
fi

# Optional: Update openclaw repository
read -p "Update openclaw repository? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Updating openclaw repository..."
    cd openclaw
    git pull
    cd ..
fi

# Generate image tag
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)

echo ""
echo "=========================================="
echo "Building OpenClaw Docker Images"
echo "=========================================="
echo "Base image:  openclaw:latest"
echo "Cloud image: openclaw-cloud:latest"
echo "Registry:    $REGISTRY"
echo "Tag:         $IMAGE_TAG"
echo "=========================================="
echo ""

# Build base image for linux/amd64 (GCP VM platform)
echo "Building base image: openclaw:latest (for linux/amd64)..."
cd openclaw
docker buildx build --platform linux/amd64 --load -t openclaw:latest .
cd ..
echo "✓ Base image built"

# Build cloud-extended image
echo ""
echo "Building cloud image: openclaw-cloud:latest (for linux/amd64)..."
docker buildx build --platform linux/amd64 --load -f Dockerfile.cloud -t openclaw-cloud:latest .
echo "✓ Cloud image built"

# Tag images
echo ""
echo "Tagging images..."

# Tag base image
docker tag openclaw:latest "${REGISTRY}/${IMAGE_NAME_BASE}:${IMAGE_TAG}"
docker tag openclaw:latest "${REGISTRY}/${IMAGE_NAME_BASE}:latest"
echo "✓ Tagged: ${REGISTRY}/${IMAGE_NAME_BASE}:${IMAGE_TAG}"
echo "✓ Tagged: ${REGISTRY}/${IMAGE_NAME_BASE}:latest"

# Tag cloud image
docker tag openclaw-cloud:latest "${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
docker tag openclaw-cloud:latest "${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"
echo "✓ Tagged: ${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
echo "✓ Tagged: ${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"

# Push images
echo ""
echo "Pushing images to Artifact Registry..."
echo "This may take a few minutes..."
echo ""

# Push base image
echo "Pushing base image..."
docker push "${REGISTRY}/${IMAGE_NAME_BASE}:${IMAGE_TAG}"
docker push "${REGISTRY}/${IMAGE_NAME_BASE}:latest"
echo "✓ Pushed base image"

# Push cloud image
echo ""
echo "Pushing cloud image..."
docker push "${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
docker push "${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"
echo "✓ Pushed cloud image"

echo ""
echo "=========================================="
echo "Build complete!"
echo "=========================================="
echo ""
echo "Images pushed:"
echo "  ${REGISTRY}/${IMAGE_NAME_BASE}:${IMAGE_TAG}"
echo "  ${REGISTRY}/${IMAGE_NAME_BASE}:latest"
echo "  ${REGISTRY}/${IMAGE_NAME_CLOUD}:${IMAGE_TAG}"
echo "  ${REGISTRY}/${IMAGE_NAME_CLOUD}:latest"
echo ""
echo "Next steps:"
echo "  Deploy to VM: ./scripts/deploy.sh"
echo ""
