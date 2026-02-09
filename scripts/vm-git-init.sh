#!/bin/bash
set -e

# One-time VM directory restructure + git initialization
# Converts existing VM layout to git-based sync:
#   ~/.openclaw -> ~/openclaw/.openclaw (git repo, cloned from bare)
#   ~/openclaw/.openclaw.git (bare repo, receives pushes)
#   ~/.openclaw/workspace -> separate git repo with GitHub remote
#
# Run from local machine: it SSHes to the VM and executes the restructure.
# Prerequisites: existing VM with ~/.openclaw data, run backup first!
#
# Rollback: mv ~/.openclaw.bak ~/.openclaw

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
require_vars VM_NAME GCP_ZONE GCP_VM_USER GCP_PROJECT_ID || exit 1

echo "=========================================="
echo "VM Git Init: Restructure + Git Setup"
echo "=========================================="
echo ""
echo "VM: $VM_NAME"
echo "User: $GCP_VM_USER"
echo ""
echo "This will:"
echo "  1. Stop the container"
echo "  2. Move gogcli creds into ~/.openclaw/.config/gogcli"
echo "  3. Create .openclaw/.env from existing secrets"
echo "  4. Initialize git in ~/.openclaw"
echo "  5. Create bare repo at ~/openclaw/.openclaw.git"
echo "  6. Clone working copy to ~/openclaw/.openclaw"
echo "  7. Set up post-receive hook"
echo "  8. Update systemd service"
echo "  9. Restart container"
echo ""
echo "IMPORTANT: Run ./scripts/backup.sh backup FIRST!"
echo ""
read -p "Continue? (yes/NO) " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "Aborted"
    exit 1
fi

# Build the script to run on VM
VM_SCRIPT=$(cat <<'EOFSCRIPT'
#!/bin/bash
set -e

GCP_VM_USER="__GCP_VM_USER__"
HOME_DIR="/home/${GCP_VM_USER}"
OPENCLAW_DIR="${HOME_DIR}/openclaw"
OLD_OPENCLAW="${HOME_DIR}/.openclaw"
NEW_OPENCLAW="${OPENCLAW_DIR}/.openclaw"
BARE_REPO="${OPENCLAW_DIR}/.openclaw.git"

echo "==> Step 1: Stop container"
cd "${OPENCLAW_DIR}"
if [ -f docker-compose.yml ]; then
    docker compose stop openclaw-gateway 2>/dev/null || true
fi

echo "==> Step 2: Move gogcli creds into .openclaw"
if [ -d "${HOME_DIR}/.config/gogcli" ] && [ -n "$(ls -A "${HOME_DIR}/.config/gogcli" 2>/dev/null)" ]; then
    mkdir -p "${OLD_OPENCLAW}/.config/gogcli"
    cp -r "${HOME_DIR}/.config/gogcli"/* "${OLD_OPENCLAW}/.config/gogcli/"
    echo "   Copied gogcli creds to ${OLD_OPENCLAW}/.config/gogcli/"
else
    mkdir -p "${OLD_OPENCLAW}/.config/gogcli"
    echo "   No gogcli creds found, created empty directory"
fi

echo "==> Step 3: Create .openclaw/.env from existing secrets"
# Extract openclaw-specific vars from the project .env
if [ -f "${OPENCLAW_DIR}/.env" ]; then
    {
        echo "# OpenClaw Application Secrets"
        echo "# Managed by git-based sync"
        echo ""
        # Extract each known openclaw var
        for VAR in OPENCLAW_GATEWAY_TOKEN OPENCLAW_GATEWAY_PORT OPENCLAW_GATEWAY_BIND \
                   OPENCLAW_ALLOW_UNCONFIGURED ANTHROPIC_API_KEY OPENAI_API_KEY \
                   GOG_KEYRING_BACKEND GOG_KEYRING_PASSWORD NODE_MAX_OLD_SPACE_SIZE; do
            VAL=$(grep "^export ${VAR}=" "${OPENCLAW_DIR}/.env" 2>/dev/null | head -1 || true)
            if [ -n "$VAL" ]; then
                echo "$VAL"
            fi
        done
    } > "${OLD_OPENCLAW}/.env"
    echo "   Created ${OLD_OPENCLAW}/.env"
else
    echo "   WARNING: No ${OPENCLAW_DIR}/.env found, creating empty .openclaw/.env"
    touch "${OLD_OPENCLAW}/.env"
fi

echo "==> Step 4: Create .gitignore"
cat > "${OLD_OPENCLAW}/.gitignore" <<'EOF'
# Workspace is a separate git repo (synced via GitHub)
workspace/

# Sessions are ephemeral
sessions/
EOF
echo "   Created .gitignore"

echo "==> Step 5: Initialize git in ~/.openclaw"
cd "${OLD_OPENCLAW}"
git init
git config user.email "openclaw@vm"
git config user.name "OpenClaw VM"
git add -A
git commit -m "Initial commit from VM restructure"
echo "   Git initialized with initial commit"

echo "==> Step 6: Create bare repo at ~/openclaw/.openclaw.git"
git clone --bare "${OLD_OPENCLAW}" "${BARE_REPO}"
echo "   Bare repo created"

echo "==> Step 7: Backup original and clone working copy"
# Save workspace and sessions before moving
WORKSPACE_EXISTS=0
SESSIONS_EXISTS=0
if [ -d "${OLD_OPENCLAW}/workspace" ]; then
    WORKSPACE_EXISTS=1
fi
if [ -d "${OLD_OPENCLAW}/sessions" ]; then
    SESSIONS_EXISTS=1
fi

# Move original to backup
mv "${OLD_OPENCLAW}" "${OLD_OPENCLAW}.bak"
echo "   Original moved to ${OLD_OPENCLAW}.bak"

# Clone from bare repo
git clone "${BARE_REPO}" "${NEW_OPENCLAW}"
echo "   Working copy cloned to ${NEW_OPENCLAW}"

# Copy back workspace and sessions from backup
if [ $WORKSPACE_EXISTS -eq 1 ]; then
    cp -r "${OLD_OPENCLAW}.bak/workspace" "${NEW_OPENCLAW}/workspace"
    echo "   Restored workspace/"
fi
if [ $SESSIONS_EXISTS -eq 1 ]; then
    cp -r "${OLD_OPENCLAW}.bak/sessions" "${NEW_OPENCLAW}/sessions"
    echo "   Restored sessions/"
fi

echo "==> Step 8: Set up post-receive hook"
mkdir -p "${BARE_REPO}/hooks"
cat > "${BARE_REPO}/hooks/post-receive" <<HOOKEOF
#!/bin/bash
GIT_WORK_TREE="${NEW_OPENCLAW}" git checkout -f
HOOKEOF
chmod +x "${BARE_REPO}/hooks/post-receive"
echo "   Post-receive hook installed"

echo "==> Step 9: Set up workspace as git repo (if it exists)"
if [ -d "${NEW_OPENCLAW}/workspace" ] && [ ! -d "${NEW_OPENCLAW}/workspace/.git" ]; then
    cd "${NEW_OPENCLAW}/workspace"
    git init
    git config user.email "openclaw@vm"
    git config user.name "OpenClaw VM"
    git add -A 2>/dev/null || true
    git commit -m "Initial workspace commit" 2>/dev/null || true
    echo "   Workspace git initialized (add GitHub remote manually)"
fi

echo "==> Step 10: Update project .env on VM (remove openclaw secrets)"
if [ -f "${OPENCLAW_DIR}/.env" ]; then
    # Remove openclaw-specific vars from project .env
    cp "${OPENCLAW_DIR}/.env" "${OPENCLAW_DIR}/.env.pre-refactor"
    for VAR in OPENCLAW_GATEWAY_TOKEN OPENCLAW_GATEWAY_PORT OPENCLAW_GATEWAY_BIND \
               OPENCLAW_ALLOW_UNCONFIGURED ANTHROPIC_API_KEY OPENAI_API_KEY \
               GOG_KEYRING_BACKEND GOG_KEYRING_PASSWORD NODE_MAX_OLD_SPACE_SIZE; do
        sed -i "/^export ${VAR}=/d" "${OPENCLAW_DIR}/.env"
    done
    # Also remove any blank sections that are now empty
    echo "   Updated project .env (backup at .env.pre-refactor)"
fi

echo "==> Step 11: Update systemd service"
sudo tee /etc/systemd/system/openclaw-gateway.service > /dev/null <<SVCEOF
[Unit]
Description=OpenClaw Gateway
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=${GCP_VM_USER}
WorkingDirectory=/home/${GCP_VM_USER}/openclaw
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/${GCP_VM_USER}/openclaw/.openclaw
ReadWritePaths=/home/${GCP_VM_USER}/openclaw/.openclaw.git

[Install]
WantedBy=multi-user.target
SVCEOF
sudo systemctl daemon-reload
echo "   Systemd service updated"

echo "==> Step 12: Restart container"
cd "${OPENCLAW_DIR}"
if [ -f docker-compose.yml ]; then
    docker compose up -d openclaw-gateway 2>/dev/null || echo "   Note: Container start failed (may need new docker-compose.yml)"
fi

echo ""
echo "=========================================="
echo "VM Git Init Complete!"
echo "=========================================="
echo ""
echo "New layout:"
echo "  ${OPENCLAW_DIR}/.openclaw.git/  (bare repo)"
echo "  ${NEW_OPENCLAW}/               (working copy)"
echo "  ${NEW_OPENCLAW}/.env           (secrets)"
echo "  ${NEW_OPENCLAW}/.config/gogcli/ (OAuth tokens)"
echo ""
echo "Rollback:"
echo "  mv ${OLD_OPENCLAW}.bak ${OLD_OPENCLAW}"
echo ""
echo "Next: Clone locally with:"
echo "  git clone openclaw-vm:${BARE_REPO} .openclaw"
EOFSCRIPT
)

# Replace placeholder with actual value
VM_SCRIPT="${VM_SCRIPT//__GCP_VM_USER__/$GCP_VM_USER}"

# Run on VM
gcloud compute ssh "$VM_NAME" \
    --zone="$GCP_ZONE" \
    --tunnel-through-iap \
    --project="$GCP_PROJECT_ID" \
    --command="$VM_SCRIPT"
