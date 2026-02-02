#!/bin/bash
set -e

# Startup script for OpenClaw gateway on Compute Engine
# This script is idempotent and can be safely re-run

LOG_FILE="/var/log/startup-script.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================="
echo "OpenClaw Startup Script"
echo "Started at: $(date)"
echo "=================================="

# Configuration from Terraform
OPENCLAW_VERSION="${openclaw_version}"
GOG_VERSION="${gog_version}"
GATEWAY_TOKEN="${gateway_token}"
GATEWAY_PORT="${gateway_port}"
GATEWAY_BIND="${gateway_bind}"
DATA_DEVICE="/dev/disk/by-id/google-${data_device_name}"

# Check if this is the first boot (data disk not formatted)
FIRST_BOOT=false
if ! blkid "$DATA_DEVICE" > /dev/null 2>&1; then
    FIRST_BOOT=true
    echo "First boot detected - data disk not formatted"
fi

# Format and mount data disk if needed
if [ "$FIRST_BOOT" = true ]; then
    echo "Formatting data disk as ext4..."
    mkfs.ext4 -F -L openclaw-data "$DATA_DEVICE"

    echo "Adding data disk to fstab..."
    DISK_UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
    echo "UUID=$DISK_UUID /home ext4 defaults,nofail 0 2" >> /etc/fstab
fi

# Ensure /home is mounted
if ! mountpoint -q /home; then
    echo "Mounting /home..."
    mount /home
fi

echo "Data disk mounted successfully:"
df -h /home

# Create node user if it doesn't exist
if ! id -u node > /dev/null 2>&1; then
    echo "Creating node user..."
    useradd -m -s /bin/bash -d /home/node node
fi

# Update system packages (only on first boot to save time)
if [ "$FIRST_BOOT" = true ]; then
    echo "Updating system packages..."
    apt-get update
    apt-get upgrade -y
fi

# Install prerequisites
echo "Installing prerequisites..."
apt-get install -y \
    curl \
    wget \
    gnupg \
    ca-certificates \
    vim \
    git \
    htop \
    tmux

# Install Node.js 22 from NodeSource
if ! command -v node > /dev/null 2>&1; then
    echo "Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt-get install -y nodejs
fi

NODE_VERSION=$(node --version)
echo "Node.js version: $NODE_VERSION"

# Install OpenClaw at pinned version
echo "Installing openclaw@$OPENCLAW_VERSION..."
npm install -g "openclaw@$OPENCLAW_VERSION"

INSTALLED_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
echo "OpenClaw version installed: $INSTALLED_VERSION"

# Install gog CLI (optional - don't fail if unavailable)
echo "Installing gog CLI v$GOG_VERSION..."
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        GOG_ARCH="amd64"
        ;;
    aarch64|arm64)
        GOG_ARCH="arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH, skipping gog"
        GOG_ARCH=""
        ;;
esac

if [ -n "$GOG_ARCH" ] && ! command -v gog &> /dev/null; then
    GOG_URL="https://github.com/cloudfuse-io/gog/releases/download/v$GOG_VERSION/gog_$${GOG_VERSION}_linux_$GOG_ARCH.tar.gz"
    echo "Downloading gog from: $GOG_URL"

    if wget -q "$GOG_URL" -O /tmp/gog.tar.gz 2>/dev/null; then
        tar -xzf /tmp/gog.tar.gz -C /usr/local/bin gog 2>/dev/null || true
        chmod +x /usr/local/bin/gog 2>/dev/null || true
        rm /tmp/gog.tar.gz
        echo "gog installation complete"
    else
        echo "WARNING: gog download failed (optional tool, continuing)"
    fi
fi

GOG_VERSION_INSTALLED=$(gog --version 2>/dev/null || echo "not installed")
echo "gog version installed: $GOG_VERSION_INSTALLED"

# Create .openclaw directory
echo "Creating OpenClaw data directory..."
mkdir -p /home/node/.openclaw
chown -R node:node /home/node/.openclaw

# Initialize openclaw configuration
echo "Initializing openclaw configuration..."
sudo -u node bash -c "
    export HOME=/home/node
    cd /home/node

    # Create minimal openclaw config
    mkdir -p /home/node/.openclaw/workspace

    cat > /home/node/.openclaw/openclaw.json << 'CONFIGEOF'
{
  \"gateway\": {
    \"auth\": {
      \"token\": \"$GATEWAY_TOKEN\"
    },
    \"port\": $GATEWAY_PORT,
    \"bind\": \"$GATEWAY_BIND\"
  }
}
CONFIGEOF

    # Set proper permissions
    chmod 600 /home/node/.openclaw/openclaw.json
"

echo "openclaw configuration created"

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/openclaw-gateway.service <<EOF
[Unit]
Description=OpenClaw Gateway Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=node
Group=node
WorkingDirectory=/home/node
Environment="OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN"
Environment="OPENCLAW_GATEWAY_PORT=$GATEWAY_PORT"
Environment="OPENCLAW_GATEWAY_BIND=$GATEWAY_BIND"
Environment="HOME=/home/node"
Environment="NODE_ENV=production"
ExecStart=/usr/bin/openclaw gateway
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-gateway

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/node/.openclaw

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
echo "Enabling and starting OpenClaw gateway service..."
systemctl daemon-reload
systemctl enable openclaw-gateway
systemctl restart openclaw-gateway

# Wait a moment for service to start
sleep 5

# Check service status
if systemctl is-active --quiet openclaw-gateway; then
    echo "✓ OpenClaw gateway service is running"
    systemctl status openclaw-gateway --no-pager
else
    echo "✗ OpenClaw gateway service failed to start"
    journalctl -u openclaw-gateway -n 50 --no-pager
    exit 1
fi

echo "=================================="
echo "OpenClaw installation complete!"
echo "Completed at: $(date)"
echo "=================================="
