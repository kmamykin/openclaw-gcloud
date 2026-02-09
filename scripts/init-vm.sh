#!/bin/bash
set -e

# OpenClaw VM Initialization Script
# Runs on the VM to set up Docker, OpenClaw directories, and git-based sync

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

# Configure Docker userns-remap so container's node user (UID 1000) maps to host VM user
echo "Configuring Docker userns-remap..."
HOST_UID=$(id -u "$GCP_VM_USER")
HOST_GID=$(id -g "$GCP_VM_USER")
SUBID_START=$((HOST_UID - 1000))
SUBGID_START=$((HOST_GID - 1000))

# Create dockremap user if needed
if ! id dockremap &>/dev/null; then
    sudo useradd -r -s /usr/sbin/nologin dockremap
fi

# Configure subordinate UID/GID ranges
echo "dockremap:${SUBID_START}:65536" | sudo tee /etc/subuid
echo "dockremap:${SUBGID_START}:65536" | sudo tee /etc/subgid

# Configure Docker daemon
echo "Configuring Docker daemon..."
sudo mkdir -p /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "userns-remap": "default",
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

# Configure git identity for VM commits
sudo -u "$GCP_VM_USER" git config --global user.email 'kmamykin@gmail.com'
sudo -u "$GCP_VM_USER" git config --global user.name 'Kliment Mamykin'

# Create OpenClaw directories (new layout)
echo "Creating OpenClaw directories..."
sudo -u "$GCP_VM_USER" mkdir -p "/home/$GCP_VM_USER/openclaw"
sudo -u "$GCP_VM_USER" mkdir -p "/home/$GCP_VM_USER/openclaw/.openclaw"
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
workspace-*/
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


# Configure Docker authentication to Artifact Registry
REGISTRY_HOST="${GCP_REGION}-docker.pkg.dev"
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
echo "- Bare repo set up"
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
