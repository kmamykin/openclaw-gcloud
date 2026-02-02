#!/bin/bash
set -e

# Validate environment
BUCKET_NAME="${GCS_BUCKET_NAME:?GCS_BUCKET_NAME must be set}"
MOUNT_PATH="/home/node/.openclaw"

# Create mount point
mkdir -p "$MOUNT_PATH"

# Cleanup function for graceful shutdown
cleanup() {
    echo "Cleaning up..."
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
echo "Waiting for mount to be ready..."
sleep 2

# Verify mount is successful
if ! mountpoint -q "$MOUNT_PATH"; then
    echo "ERROR: Failed to mount GCS bucket"
    exit 1
fi

echo "GCS bucket mounted successfully"

# Execute the main command passed as arguments
echo "Starting application: $@"
exec "$@"
