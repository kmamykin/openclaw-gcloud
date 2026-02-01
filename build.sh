#!/bin/bash
set -e

# Build the base openclaw:latest image from the openclaw subfolder
echo "Building openclaw:latest base image..."
docker build -t openclaw:latest ./openclaw

# Build the custom image with gog and wacli
echo "Building openclaw-cloud:latest with additional binaries..."
docker build -t openclaw-cloud:latest .

echo "Build complete! Images available:"
echo "  - openclaw:latest (base)"
echo "  - openclaw-cloud:latest (with gog + wacli)"
