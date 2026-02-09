#!/bin/bash
# SSH config helper for git-over-IAP access to VM
# Ensures ~/.ssh/config has an entry for openclaw-vm

# Ensure SSH config entry exists for openclaw-vm
# Uses gcloud IAP tunnel as ProxyCommand for secure git access
# Usage: ensure_ssh_config
ensure_ssh_config() {
    local ssh_config="$HOME/.ssh/config"
    local host_entry="openclaw-vm"

    # Check required vars
    if [ -z "$VM_NAME" ] || [ -z "$GCP_ZONE" ] || [ -z "$GCP_PROJECT_ID" ] || [ -z "$GCP_VM_USER" ]; then
        echo "ERROR: VM_NAME, GCP_ZONE, GCP_PROJECT_ID, and GCP_VM_USER must be set" >&2
        return 1
    fi

    # Create .ssh dir if needed
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    # Check if entry already exists
    if [ -f "$ssh_config" ] && grep -q "^Host ${host_entry}$" "$ssh_config"; then
        return 0
    fi

    # Append entry
    cat >> "$ssh_config" <<EOF

Host ${host_entry}
    User ${GCP_VM_USER}
    IdentityFile ~/.ssh/google_compute_engine
    ProxyCommand gcloud compute start-iap-tunnel ${VM_NAME} 22 --zone=${GCP_ZONE} --listen-on-stdin --project=${GCP_PROJECT_ID} 2>/dev/null
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF

    chmod 600 "$ssh_config"
    echo "Added '${host_entry}' entry to ${ssh_config}"
}

VM_HOST="openclaw-vm"
VM_DIR="/home/${GCP_VM_USER}/openclaw"
BARE_REPO_PATH="$VM_DIR/.openclaw.git"
