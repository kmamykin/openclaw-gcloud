#!/bin/bash
set -e

# Backup and restore OpenClaw data to/from GCS
# Optional disaster recovery tool

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
if [ -z "$VM_NAME" ] || [ -z "$GCP_ZONE" ] || [ -z "$GCS_BUCKET_NAME" ]; then
    echo "ERROR: VM_NAME, GCP_ZONE, and GCS_BUCKET_NAME must be set in .env"
    exit 1
fi

ACTION="${1:-backup}"

case "$ACTION" in
    backup)
        echo "=========================================="
        echo "Backing up OpenClaw data to GCS"
        echo "=========================================="
        echo ""
        echo "Source: VM:~/.openclaw"
        echo "Destination: gs://$GCS_BUCKET_NAME/openclaw-backup/"
        echo ""

        BACKUP_SCRIPT=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -e

# Source .env
cd /home/${GCP_VM_USER}/openclaw
set -a
source .env
set +a

echo "Creating backup timestamp..."
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="gs://${GCS_BUCKET_NAME}/openclaw-backup/${BACKUP_DATE}"

echo "Backing up to: $BACKUP_PATH"

# Create a compressed archive
cd /home/${GCP_VM_USER}
tar czf /tmp/openclaw-backup.tar.gz .openclaw/

echo "Uploading to GCS..."
gsutil cp /tmp/openclaw-backup.tar.gz "$BACKUP_PATH/openclaw-data.tar.gz"

# Also create a "latest" symlink
gsutil cp /tmp/openclaw-backup.tar.gz "gs://${GCS_BUCKET_NAME}/openclaw-backup/latest.tar.gz"

# Cleanup
rm /tmp/openclaw-backup.tar.gz

echo "✓ Backup complete"
echo ""
echo "Backup location:"
echo "  $BACKUP_PATH/openclaw-data.tar.gz"
echo "  gs://${GCS_BUCKET_NAME}/openclaw-backup/latest.tar.gz"
EOFSCRIPT
)

        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="$BACKUP_SCRIPT"

        echo ""
        echo "=========================================="
        echo "Backup complete!"
        echo "=========================================="
        echo ""
        ;;

    restore)
        echo "=========================================="
        echo "Restoring OpenClaw data from GCS"
        echo "=========================================="
        echo ""
        echo "Source: gs://$GCS_BUCKET_NAME/openclaw-backup/latest.tar.gz"
        echo "Destination: VM:~/.openclaw"
        echo ""

        # Confirm restoration
        read -p "This will OVERWRITE existing data on the VM. Continue? (yes/NO) " -r
        echo
        if [[ ! $REPLY =~ ^yes$ ]]; then
            echo "Restore cancelled"
            exit 1
        fi

        RESTORE_SCRIPT=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -e

# Source .env
cd /home/${GCP_VM_USER}/openclaw
set -a
source .env
set +a

echo "Stopping OpenClaw gateway..."
docker compose stop openclaw-gateway || true

echo "Downloading backup from GCS..."
gsutil cp "gs://${GCS_BUCKET_NAME}/openclaw-backup/latest.tar.gz" /tmp/openclaw-backup.tar.gz

echo "Backing up current data (just in case)..."
if [ -d "/home/${GCP_VM_USER}/.openclaw" ]; then
    mv "/home/${GCP_VM_USER}/.openclaw" "/home/${GCP_VM_USER}/.openclaw.pre-restore-$(date +%Y%m%d-%H%M%S)"
fi

echo "Extracting backup..."
cd /home/${GCP_VM_USER}
tar xzf /tmp/openclaw-backup.tar.gz

# Cleanup
rm /tmp/openclaw-backup.tar.gz

echo "Starting OpenClaw gateway..."
cd /home/${GCP_VM_USER}/openclaw
docker compose start openclaw-gateway

echo "✓ Restore complete"
EOFSCRIPT
)

        gcloud compute ssh "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --tunnel-through-iap \
            --project="$GCP_PROJECT_ID" \
            --command="$RESTORE_SCRIPT"

        echo ""
        echo "=========================================="
        echo "Restore complete!"
        echo "=========================================="
        echo ""
        echo "Previous data backed up to: ~/.openclaw.pre-restore-*"
        echo ""
        ;;

    list)
        echo "Listing available backups..."
        echo ""
        gsutil ls "gs://$GCS_BUCKET_NAME/openclaw-backup/"
        ;;

    *)
        echo "Usage: $0 [action]"
        echo ""
        echo "Actions:"
        echo "  backup   - Backup OpenClaw data to GCS (default)"
        echo "  restore  - Restore OpenClaw data from GCS (latest backup)"
        echo "  list     - List available backups"
        echo ""
        echo "Examples:"
        echo "  $0 backup     # Create a backup"
        echo "  $0 restore    # Restore from latest backup"
        echo "  $0 list       # List all backups"
        echo ""
        exit 1
        ;;
esac
