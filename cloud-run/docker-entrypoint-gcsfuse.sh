#!/bin/bash
set -e

# Validate environment
BUCKET_NAME="${GCS_BUCKET_NAME:?GCS_BUCKET_NAME must be set}"
PROJECT_ID="${GCP_PROJECT_ID:?GCP_PROJECT_ID must be set}"
REGION="${GCP_REGION:?GCP_REGION must be set}"
SERVICE_NAME="${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE must be set}"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
MOUNT_PATH="/home/node/.openclaw"

# Create mount point
mkdir -p "$MOUNT_PATH"

# Cleanup function for graceful shutdown
cleanup() {
    echo "Cleaning up..."
    # Kill gcloud proxy
    if [ -n "$GCLOUD_PROXY_PID" ] && kill -0 "$GCLOUD_PROXY_PID" 2>/dev/null; then
        echo "Stopping gcloud proxy..."
        kill "$GCLOUD_PROXY_PID" || true
        wait "$GCLOUD_PROXY_PID" 2>/dev/null || true
    fi
    # Unmount GCS bucket
    if mountpoint -q "$MOUNT_PATH"; then
        echo "Unmounting GCS bucket..."
        fusermount -u "$MOUNT_PATH" || true
    fi
    exit 0
}

# Setup signal handlers
trap cleanup SIGTERM SIGINT

# Mount GCS bucket with gcsfuse
echo "Mounting GCS bucket: $BUCKET_NAME at $MOUNT_PATH"
gcsfuse --implicit-dirs --file-mode=0666 --dir-mode=0777 "$BUCKET_NAME" "$MOUNT_PATH" &
GCSFUSE_PID=$!

# Wait for mount to be ready
echo "Waiting for GCS mount to be ready..."
sleep 2

# Verify mount is successful
if ! mountpoint -q "$MOUNT_PATH"; then
    echo "ERROR: Failed to mount GCS bucket"
    exit 1
fi

echo "GCS bucket mounted successfully"

# Start gcloud proxy in background
echo "Starting gcloud run proxy to $SERVICE_NAME (port $GATEWAY_PORT)..."
gcloud run services proxy "$SERVICE_NAME" \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --port="$GATEWAY_PORT" &
GCLOUD_PROXY_PID=$!

# Wait for proxy to be ready
echo "Waiting for gcloud proxy to be ready..."
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$GATEWAY_PORT/" > /dev/null 2>&1; then
        echo "gcloud proxy is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: gcloud proxy failed to start after 30 seconds"
        exit 1
    fi
    sleep 1
done

echo "Container initialization complete"
echo "  - GCS bucket mounted at: $MOUNT_PATH"
echo "  - gcloud proxy running at: ws://localhost:$GATEWAY_PORT"

# Execute the main command passed as arguments
echo "Starting application: $@"
exec "$@"
