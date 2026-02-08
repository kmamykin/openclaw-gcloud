#!/bin/bash
set -e

# Local gogcli authentication script
# Runs OAuth flow in local container with browser, saves to .config/gogcli/

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

# Parse arguments
if [ $# -lt 3 ]; then
    echo "ERROR: Missing required arguments"
    echo ""
    echo "Usage: $0 <credentials-file> <client-name> <email> [--domain example.com]"
    echo ""
    echo "Arguments:"
    echo "  credentials-file  - Path to OAuth credentials JSON file (from Google Cloud Console)"
    echo "  client-name      - Named client identifier (e.g., default, work, personal)"
    echo "  email            - Google account email to authorize"
    echo "  --domain         - (Optional) Workspace domain for organization accounts"
    echo ""
    echo "Examples:"
    echo "  $0 ~/Downloads/client_secret.json default you@gmail.com"
    echo "  $0 ~/Downloads/work.json work you@company.com --domain company.com"
    echo "  $0 ~/Downloads/personal.json personal you@gmail.com"
    echo ""
    echo "Named clients allow managing separate OAuth credentials for different projects."
    echo ""
    exit 1
fi

CREDS_FILE="$1"
CLIENT_NAME="$2"
EMAIL="$3"
shift 3  # Remaining args for optional --domain flag

# Validate credentials file exists
if [ ! -f "$CREDS_FILE" ]; then
    echo "ERROR: Credentials file not found: $CREDS_FILE"
    exit 1
fi

# Validate GOG_KEYRING_PASSWORD is set
if [ -z "$GOG_KEYRING_PASSWORD" ]; then
    echo "ERROR: GOG_KEYRING_PASSWORD not set in .env"
    echo ""
    echo "Generate and add to .env:"
    echo "  echo \"GOG_KEYRING_PASSWORD=\$(openssl rand -hex 32)\" >> .env"
    echo ""
    exit 1
fi

# Check if gog is installed locally
if ! command -v gog &> /dev/null; then
    echo "ERROR: 'gog' command not found"
    echo ""
    echo "Install gogcli locally:"
    echo "  brew install steipete/tap/gogcli"
    echo ""
    echo "Or download from: https://github.com/steipete/gogcli/releases"
    echo ""
    exit 1
fi

# Create .config/gogcli directory
CONFIG_DIR="${PROJECT_ROOT}/.config/gogcli"
mkdir -p "$CONFIG_DIR"

echo "=========================================="
echo "Local gogcli Authentication"
echo "=========================================="
echo ""
echo "Client name: $CLIENT_NAME"
echo "Email: $EMAIL"
echo "Credentials: $(basename "$CREDS_FILE")"
echo ""
echo "Starting OAuth flow on local machine..."
echo "Your browser will open for authorization."
echo ""

# Set up environment for gog
export GOG_KEYRING_PASSWORD
export GOG_KEYRING_BACKEND=file
export HOME="${PROJECT_ROOT}"  # Make gog use .config/gogcli in project root

# Step 1: Set up OAuth credentials
echo "→ Configuring OAuth credentials..."
GOG_CREDS_CMD="gog --client ${CLIENT_NAME} auth credentials \"${CREDS_FILE}\""
if [ $# -gt 0 ]; then
    GOG_CREDS_CMD="${GOG_CREDS_CMD} $@"
fi
eval "$GOG_CREDS_CMD"

echo ""
echo "→ Starting OAuth authorization flow..."
echo "   (Your browser will open shortly)"
echo ""

# Step 2: Run OAuth flow
gog --client "${CLIENT_NAME}" auth add "${EMAIL}"

echo ""
echo "✓ Authentication successful!"
echo ""
echo "Credentials saved to: .config/gogcli/"
echo "  (This directory is gitignored - credentials stay local)"
echo ""
echo "Next steps:"
echo ""
echo "1. Sync credentials to VM:"
echo "   ./scripts/openclaw.sh gog-sync"
echo ""
echo "2. Deploy or restart:"
echo "   ./scripts/deploy.sh"
echo "   # OR"
echo "   ./scripts/openclaw.sh restart"
echo ""
echo "3. Test access:"
echo "   ./scripts/openclaw.sh cli gog --client $CLIENT_NAME gmail labels list"
echo ""
