#!/bin/bash
set -e

# Backup and restore OpenClaw data to/from GCS
# Optional disaster recovery tool

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
source "${SCRIPT_DIR}/lib/path.sh"
source "${SCRIPT_DIR}/lib/env.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/ssh-setup.sh"

# Get project root and change to it
PROJECT_ROOT="$(get_project_root)"
cd "$PROJECT_ROOT"

# Load environment
load_env || exit 1

# Validate required variables
require_vars VM_NAME GCP_ZONE GCS_BUCKET_NAME || exit 1

ensure_ssh_config

ACTION="${1:-backup}"

case "$ACTION" in
    backup)
        echo "=========================================="
        echo "Backing up OpenClaw data to GCS"
        echo "=========================================="
        echo ""
        echo "Source: VM:~/openclaw/.openclaw"
        echo "Destination: gs://$GCS_BUCKET_NAME/openclaw-backup/"
        echo ""

        BACKUP_SCRIPT=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -e

# Source .env
cd $HOME/openclaw
set -a
source .env
[ -f .openclaw/.env ] && source .openclaw/.env
set +a

BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="gs://${GCS_BUCKET_NAME}/openclaw-backup/${BACKUP_DATE}"

echo "Backing up to: $BACKUP_PATH"

# Create a compressed archive from the new location
cd $HOME/openclaw
tar czf /tmp/openclaw-backup.tar.gz .openclaw/

gsutil cp /tmp/openclaw-backup.tar.gz "$BACKUP_PATH/openclaw-data.tar.gz"

# Also create a "latest" symlink
gsutil cp /tmp/openclaw-backup.tar.gz "gs://${GCS_BUCKET_NAME}/openclaw-backup/latest.tar.gz"

# Cleanup
rm /tmp/openclaw-backup.tar.gz

echo "Backup complete"
echo ""
echo "Backup location:"
echo "  $BACKUP_PATH/openclaw-data.tar.gz"
echo "  gs://${GCS_BUCKET_NAME}/openclaw-backup/latest.tar.gz"
EOFSCRIPT
)

        ssh "$VM_HOST" "$BACKUP_SCRIPT"

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
        echo "Destination: VM:~/openclaw/.openclaw"
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
cd $HOME/openclaw
set -a
source .env
[ -f .openclaw/.env ] && source .openclaw/.env
set +a

echo "Stopping OpenClaw gateway..."
docker compose stop openclaw-gateway || true

echo "Downloading backup from GCS..."
gsutil cp "gs://${GCS_BUCKET_NAME}/openclaw-backup/latest.tar.gz" /tmp/openclaw-backup.tar.gz

if [ -d "$HOME/openclaw/.openclaw" ]; then
    mv "$HOME/openclaw/.openclaw" "$HOME/openclaw/.openclaw.pre-restore-$(date +%Y%m%d-%H%M%S)"
fi

echo "Extracting backup..."
cd $HOME/openclaw
tar xzf /tmp/openclaw-backup.tar.gz

# Cleanup
rm /tmp/openclaw-backup.tar.gz

echo "Starting OpenClaw gateway..."
docker compose start openclaw-gateway

echo "Restore complete"
EOFSCRIPT
)

        ssh "$VM_HOST" "$RESTORE_SCRIPT"

        echo ""
        echo "=========================================="
        echo "Restore complete!"
        echo "=========================================="
        echo ""
        echo "Previous data backed up to: ~/openclaw/.openclaw.pre-restore-*"
        echo ""
        ;;

    list)
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
