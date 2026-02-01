#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Running openclaw-cloud locally..."
echo "Gateway: http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}"
echo ""
echo "Commands:"
echo "  docker compose logs -f"
echo "  docker compose down"
echo ""

docker compose up
