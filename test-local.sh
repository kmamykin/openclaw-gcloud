#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

echo "Running openclaw-cloud locally..."
echo "Gateway: http://localhost:${OPENCLAW_GATEWAY_PORT}"
echo "Bridge:  http://localhost:${OPENCLAW_BRIDGE_PORT}"
echo ""

docker run -it --rm \
    -p "${OPENCLAW_GATEWAY_PORT}:${OPENCLAW_GATEWAY_PORT}" \
    -p "${OPENCLAW_BRIDGE_PORT}:${OPENCLAW_BRIDGE_PORT}" \
    -v "$(pwd)/data:/home/node/.openclaw" \
    -v "$(pwd)/data/workspace:/home/node/.openclaw/workspace" \
    -e HOME=/home/node \
    -e TERM=xterm-256color \
    -e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
    -e OPENCLAW_GATEWAY_BIND="$OPENCLAW_GATEWAY_BIND" \
    openclaw-cloud:latest \
    node dist/index.js gateway --allow-unconfigured --port "$OPENCLAW_GATEWAY_PORT" --bind "$OPENCLAW_GATEWAY_BIND"
