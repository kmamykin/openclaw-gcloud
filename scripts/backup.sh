#!/bin/bash
set -e

# Manual VM disk snapshot operations
# Automated daily snapshots are managed by the snapshot schedule (see setup.sh)

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

# Validate required variables
require_vars VM_NAME GCP_ZONE || exit 1

ACTION="${1:-snapshot}"

case "$ACTION" in
    snapshot)
        SNAPSHOT_NAME="openclaw-$(date +%Y%m%d-%H%M%S)"
        echo "Creating snapshot: $SNAPSHOT_NAME"
        gcloud compute disks snapshot "$VM_NAME" \
            --zone="$GCP_ZONE" \
            --snapshot-names="$SNAPSHOT_NAME"
        echo "Snapshot created: $SNAPSHOT_NAME"
        ;;

    list)
        gcloud compute snapshots list \
            --filter="sourceDisk~${VM_NAME}$"
        ;;

    delete)
        SNAPSHOT_NAME="$2"
        if [ -z "$SNAPSHOT_NAME" ]; then
            echo "Usage: $0 delete <snapshot-name>"
            exit 1
        fi
        read -p "Delete snapshot '$SNAPSHOT_NAME'? (yes/NO) " -r
        echo
        if [[ ! $REPLY =~ ^yes$ ]]; then
            echo "Cancelled"
            exit 0
        fi
        gcloud compute snapshots delete "$SNAPSHOT_NAME" --quiet
        echo "Snapshot deleted: $SNAPSHOT_NAME"
        ;;

    *)
        echo "Usage: $0 [action]"
        echo ""
        echo "Actions:"
        echo "  snapshot  - Create a disk snapshot (default)"
        echo "  list      - List snapshots for this VM"
        echo "  delete    - Delete a snapshot"
        echo ""
        echo "Examples:"
        echo "  $0              # Create a snapshot"
        echo "  $0 list         # List snapshots"
        echo "  $0 delete NAME  # Delete a snapshot"
        echo ""
        exit 1
        ;;
esac
