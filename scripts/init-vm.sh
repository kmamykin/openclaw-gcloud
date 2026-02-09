#!/bin/bash
set -e

# OpenClaw VM Initialization Script
# Runs on the VM to set up Docker, OpenClaw directories, and systemd service

echo "Starting VM initialization..."

# Load environment from copied .env file
if [ ! -f /tmp/.env ]; then
    echo "ERROR: /tmp/.env not found"
    exit 1
fi

# Source .env
set -a
source /tmp/.env
set +a

# Check if Docker is already installed
if command -v docker &> /dev/null; then
    echo "Docker already installed, skipping..."
else
    echo "Installing Docker..."

    # Install prerequisites
    sudo apt-get update
    sudo apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release

    # Add Docker's official GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    # Set up repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    echo "Docker installed successfully"
fi

# Install git if not present
if ! command -v git &> /dev/null; then
    echo "Installing git..."
    sudo apt-get update
    sudo apt-get install -y git
    echo "Git installed"
fi

# Check if Docker Compose is installed
if ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose plugin not installed"
    exit 1
fi

# Configure Docker daemon
echo "Configuring Docker daemon..."
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "live-restore": true,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# Restart Docker to apply config
sudo systemctl restart docker
sudo systemctl enable docker

# Create OpenClaw user if doesn't exist
if id "$GCP_VM_USER" &>/dev/null; then
    echo "User $GCP_VM_USER already exists"
else
    echo "Creating user: $GCP_VM_USER"
    sudo useradd -m -s /bin/bash "$GCP_VM_USER"
fi

# Add user to docker group
sudo usermod -aG docker "$GCP_VM_USER"

# Create OpenClaw directories (new layout)
echo "Creating OpenClaw directories..."
sudo -u "$GCP_VM_USER" mkdir -p "/home/$GCP_VM_USER/openclaw"
sudo -u "$GCP_VM_USER" mkdir -p "/home/$GCP_VM_USER/openclaw/.openclaw"
sudo -u "$GCP_VM_USER" mkdir -p "/home/$GCP_VM_USER/openclaw/.openclaw/workspace"
sudo -u "$GCP_VM_USER" mkdir -p "/home/$GCP_VM_USER/openclaw/.openclaw/sessions"
sudo -u "$GCP_VM_USER" mkdir -p "/home/$GCP_VM_USER/openclaw/.openclaw/.config/gogcli"

# Copy .env to user directory
echo "Copying .env to OpenClaw directory..."
sudo cp /tmp/.env "/home/$GCP_VM_USER/openclaw/.env"
sudo chown "$GCP_VM_USER:$GCP_VM_USER" "/home/$GCP_VM_USER/openclaw/.env"
sudo chmod 600 "/home/$GCP_VM_USER/openclaw/.env"

# Initialize .openclaw as a git repo
echo "Initializing .openclaw git repo..."
sudo -u "$GCP_VM_USER" bash -c "
    cd /home/$GCP_VM_USER/openclaw/.openclaw
    if [ ! -d .git ]; then
        # Create .gitignore
        cat > .gitignore <<'GITEOF'
workspace/
sessions/
GITEOF
        # Create placeholder .env
        touch .env
        git init
        git add -A
        git commit -m 'Initial commit'
    fi
"

# Create bare repo for sync
echo "Creating bare repo..."
sudo -u "$GCP_VM_USER" bash -c "
    if [ ! -d /home/$GCP_VM_USER/openclaw/.openclaw.git ]; then
        git clone --bare /home/$GCP_VM_USER/openclaw/.openclaw /home/$GCP_VM_USER/openclaw/.openclaw.git
    fi
"

# Set up post-receive hook
echo "Setting up post-receive hook..."
sudo -u "$GCP_VM_USER" bash -c "
    mkdir -p /home/$GCP_VM_USER/openclaw/.openclaw.git/hooks
    cat > /home/$GCP_VM_USER/openclaw/.openclaw.git/hooks/post-receive <<'HOOKEOF'
#!/bin/bash
GIT_WORK_TREE=/home/${GCP_VM_USER}/openclaw/.openclaw git checkout -f
HOOKEOF
    chmod +x /home/$GCP_VM_USER/openclaw/.openclaw.git/hooks/post-receive
"

# Configure Docker authentication to Artifact Registry
echo "Configuring Docker authentication to Artifact Registry..."
gcloud auth configure-docker "${REGISTRY_HOST}" --quiet

# Allow openclaw user to use Docker auth
sudo -u "$GCP_VM_USER" gcloud auth configure-docker "${REGISTRY_HOST}" --quiet

# Create docker-compose.yml from template
echo "Creating initial docker-compose.yml..."
cat <<'EOF' | sudo -u "$GCP_VM_USER" tee "/home/$GCP_VM_USER/openclaw/docker-compose.yml" > /dev/null
# Placeholder - will be updated by deploy.sh
services:
  openclaw-gateway:
    image: placeholder
    restart: "no"
EOF

# Create systemd service
echo "Creating systemd service..."
cat <<EOF | sudo tee /etc/systemd/system/openclaw-gateway.service
[Unit]
Description=OpenClaw Gateway
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=$GCP_VM_USER
WorkingDirectory=/home/$GCP_VM_USER/openclaw
ExecStart=/usr/bin/docker compose up
ExecStop=/usr/bin/docker compose down
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/$GCP_VM_USER/openclaw/.openclaw
ReadWritePaths=/home/$GCP_VM_USER/openclaw/.openclaw.git

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
sudo systemctl daemon-reload

# Enable service (but don't start yet - will be started by deploy.sh)
sudo systemctl enable openclaw-gateway

echo ""
echo "=========================================="
echo "VM initialization complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "- Docker and git installed"
echo "- User '$GCP_VM_USER' created"
echo "- OpenClaw directories created (new layout)"
echo "- .openclaw git repo initialized"
echo "- Bare repo + post-receive hook set up"
echo "- Systemd service configured"
echo "- Docker authenticated to Artifact Registry"
echo ""
echo "Next steps:"
echo "1. Build and push Docker images (from local machine):"
echo "   ./scripts/build.sh"
echo ""
echo "2. Deploy OpenClaw (from local machine):"
echo "   ./scripts/deploy.sh"
echo ""
echo "3. Clone .openclaw locally:"
echo "   git clone openclaw-vm:/home/$GCP_VM_USER/openclaw/.openclaw.git .openclaw"
echo ""
