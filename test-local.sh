#!/bin/bash
set -e

echo "Running openclaw-cloud locally..."
docker run -it --rm \
    -p 3000:3000 \
    -v "$(pwd)/data:/data" \
    -e OPENCLAW_STATE_DIR=/data \
    -e OPENCLAW_WORKSPACE_DIR=/data/workspace \
    -e OPENCLAW_GATEWAY_BIND=lan \
    openclaw-cloud:latest \
    node dist/index.js gateway --allow-unconfigured --port 3000 --bind lan
