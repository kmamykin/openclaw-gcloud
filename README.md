# OpenClaw Google Cloud Deployment

Automated deployment of OpenClaw Gateway on Google Cloud Platform using GCP Compute Engine and Artifact Registry.

**Target Cost**: ~$24/month for e2-medium VM
**Documentation**: Based on [Official OpenClaw GCP Guide](https://docs.openclaw.ai/platforms/gcp)

## 📁 Project Structure

```
openclaw-gcloud/
├── .env                    # Configuration (gitignored, copy from .env.example)
├── .env.example            # Configuration template
├── .envrc                  # direnv configuration (optional)
├── .gitignore              # Git ignore rules
├── README.md               # This file
├── Dockerfile              # Cloud-extended image (adds tools to base openclaw)
├── docker-compose.yml.tpl  # Template for VM docker-compose.yml
├── openclaw/               # Official OpenClaw repository (already checked out, gitignored)
└── scripts/                # Deployment automation scripts
    ├── setup.sh            # One-time GCP infrastructure setup
    ├── init-vm.sh          # One-time VM initialization
    ├── build.sh            # Build Docker images, push to registry
    ├── deploy.sh           # Deploy/update container on VM
    ├── openclaw.sh              # SSH management (shell, forward, logs, cli)
    └── backup.sh           # Backup/restore OpenClaw data (optional)
```

## Architecture Overview

### Infrastructure Components

| Component | Specification | Purpose |
|-----------|--------------|---------|
| **Compute** | GCP Compute Engine e2-medium | 2 vCPU, 4GB RAM for Docker containers |
| **Boot Disk** | 30GB Debian 12 persistent disk | OS, Docker images, and layers |
| **Storage** | Docker volumes → local disk | Persistent OpenClaw data |
| **Registry** | GCP Artifact Registry | Store versioned Docker images |
| **Networking** | IAP tunnel (no external IP) | Secure SSH and port forwarding |
| **NAT** | Cloud NAT | Outbound internet without public IP |
| **Backup** | GCS bucket (optional) | Disaster recovery |

### Docker Image Strategy

**Two-Image Build Process**:

1. **openclaw:latest** (Base Image)
   - Built from official OpenClaw repository at `./openclaw`
   - Contains core OpenClaw Gateway functionality
   - Node.js 22, TypeScript, built UI

2. **openclaw-cloud:latest** (Cloud-Extended Image)
   - Extends `openclaw:latest` via `Dockerfile`
   - Adds cloud-specific tools:
     - gog CLI (Gmail access)
     - vim, curl (utilities)
     - Additional tools as needed
   - Pattern from `cloud-run/Dockerfile`

**Why Two Images?**
- Separation of concerns: core OpenClaw vs cloud extensions
- Base image stays clean and portable
- Cloud-specific tools only in deployment image
- Easier to maintain and update separately

### Deployment Flow

```
┌──────────────────┐
│ Local Machine    │
│                  │
│ ./openclaw/      │ ─────┐
│ (official repo)  │      │
└──────────────────┘      │ docker build
                          │
                          ↓
                   ┌──────────────────┐
                   │ openclaw:latest  │
                   │ (base image)     │
                   └──────────────────┘
                          │
                          │ Dockerfile
                          ↓
                   ┌──────────────────┐     docker push      ┌──────────────────┐
                   │ openclaw-cloud   │ ──────────────────> │ Artifact Registry│
                   │ (cloud image)    │                      │ (GCP)            │
                   └──────────────────┘                      └──────────────────┘
                                                                     │
                                                                     │ docker pull
                                                                     ↓
┌──────────────┐     gcloud ssh      ┌─────────────────┐    ┌──────────────────┐
│ Local Dev    │ ───────────────────>│ IAP Tunnel      │───>│ GCP VM           │
│ Browser      │  port forward 18789 │ (no ext IP)     │    │ (e2-medium)      │
└──────────────┘                     └─────────────────┘    └──────────────────┘
                                                                     │
                                                                     │ docker run
                                                                     ↓
                                                              ┌──────────────────┐
                                                              │ openclaw-gateway │
                                                              │ container        │
                                                              └──────────────────┘
                                                                     │
                                                                     │ volume mount
                                                                     ↓
                                                              ┌──────────────────┐
                                                              │ ~/.openclaw/     │
                                                              │ (persistent)     │
                                                              └──────────────────┘
```

## Core Design Decisions

### 1. Local Disk Storage
**Approach**: VM persistent disk with Docker volume mounts

**Implementation**:
- Persistent directories: `~/.openclaw/` and `~/.openclaw/workspace/`
- Mounted into container at `/home/node/.openclaw`
- Survives container restarts and rebuilds
- Optional backup to GCS for disaster recovery

**Why?**
- Fast local I/O
- Simple configuration
- No runtime mounting complexity
- Proven reliable

### 2. Artifact Registry for Images
**Approach**: Build locally, push to registry, VM pulls from registry

**Implementation**:
- Build both images on local development machine
- Tag with timestamps for versioning
- Push to GCP Artifact Registry
- VM authenticates and pulls latest
- Always deploy from registry (reproducible)

**Why?**
- Reproducible deployments
- Version control
- Faster VM deployments (pull vs rebuild)
- Better development workflow

### 3. e2-medium with Resource Limits
**Specs**: 2 vCPU, 4GB RAM

**Docker Configuration**:
- Memory limit: 3GB (leave 1GB for OS)
- CPU limit: 1.5 cores (leave 0.5 for OS)
- Node.js heap: 2.5GB (`--max-old-space-size=2560`)

**Why?**
- Sufficient headroom for gateway operations
- Room for multiple agents and skills
- Prevents OOM errors
- Cost-effective at ~$24/month

### 4. IAP Tunnel Access
**Approach**: No external IP, Identity-Aware Proxy for SSH

**Implementation**:
- VM has no public IP address
- Access via: `gcloud compute ssh --tunnel-through-iap`
- Port forwarding: `-- -L 18789:127.0.0.1:18789`
- Gateway binds to localhost only

**Why?**
- More secure (no public exposure)
- No firewall management needed
- Free (no external IP costs)
- Integrated with GCP IAM

### 5. Official OpenClaw Repository
**Approach**: Use openclaw directory already checked out locally

**Implementation**:
- OpenClaw repo at `./openclaw` (gitignored)
- Build base image from this directory
- Can be updated with `git pull` when needed
- No fork maintenance required

**Why?**
- Get official updates easily
- No custom fork to maintain
- Clean separation from deployment code

## Configuration

See `.env.example` for full configuration template with comments.

### Key Environment Variables

```bash
# GCP Project
GCP_PROJECT_ID=my-openclaw-project
GCP_REGION=us-east1
GCP_ZONE=us-east1-b

# Docker Registry
GCP_REPO_NAME=openclaw-images
REGISTRY=${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${GCP_REPO_NAME}

# VM Configuration
VM_NAME=openclaw-gateway
MACHINE_TYPE=e2-medium
GCP_VM_USER=openclaw

# Docker Resource Limits
DOCKER_MEMORY_LIMIT=3g
DOCKER_CPU_LIMIT=1.5

# OpenClaw Configuration
OPENCLAW_GATEWAY_TOKEN=<generate-with-openssl-rand-hex-32>
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_GATEWAY_BIND=loopback

# Optional: AI Model API Keys
ANTHROPIC_API_KEY=
OPENAI_API_KEY=
```

## Scripts Overview

### `./scripts/setup.sh` - One-Time Infrastructure Setup
**Runs on**: Local machine
**Idempotent**: Yes

**What it does**:
1. Enable GCP APIs (Compute, Artifact Registry, IAP)
2. Create Artifact Registry repository
3. Configure local Docker authentication
4. Create VM (e2-medium, 30GB disk, no external IP)
5. Configure Cloud NAT
6. Create GCS backup bucket (optional)
7. Call `init-vm.sh` to initialize VM

### `./scripts/init-vm.sh` - One-Time VM Initialization
**Runs on**: VM (via SSH from setup.sh)
**Idempotent**: Yes

**What it does**:
1. Install Docker and Docker Compose
2. Configure Docker daemon
3. Authenticate Docker to Artifact Registry
4. Create openclaw user and directories
5. Copy `.env` and `docker-compose.yml` to VM
6. Create systemd service for auto-start
7. Pull initial image and start service

### `./scripts/build.sh` - Build and Push Images
**Runs on**: Local machine
**Requires**: Docker installed locally

**What it does**:
1. Verify `./openclaw` directory exists
2. Optional: `git pull` to update openclaw
3. Build base image: `cd openclaw && docker build -t openclaw:latest .`
4. Build cloud image: `docker build -f Dockerfile -t openclaw-cloud:latest .`
5. Tag both images with timestamp and `:latest`
6. Push both images to Artifact Registry
7. Display pushed image info

### `./scripts/deploy.sh` - Deploy/Update Container
**Runs on**: Local machine (SSHs to VM)
**Options**: Can call build.sh first

**What it does**:
1. Optional: Build new images (`--build` flag)
2. SSH to VM
3. Pull latest image: `docker-compose pull`
4. Stop container: `docker-compose down`
5. Start container: `docker-compose up -d`
6. Wait for health check
7. Display logs and connection instructions

**First deploy**:
- Run `openclaw gateway onboard` with token
- Create initial configuration

### `./scripts/openclaw.sh [command]` - SSH Management
**Runs on**: Local machine

**Commands**:
- `shell` - Interactive SSH shell on VM
- `forward` - Port forwarding (18789) with tunnel kept open
- `logs` - Stream container logs
- `cli` - Exec into container for OpenClaw CLI
- `status` - Show systemd service status

**Usage**:
```bash
./scripts/openclaw.sh forward          # Access UI at http://localhost:18789
./scripts/openclaw.sh logs             # Watch logs
./scripts/openclaw.sh cli gateway status
```

### `./scripts/backup.sh [action]` - Backup Management
**Runs on**: Local machine (SSHs to VM)
**Optional**: For disaster recovery

**Actions**:
- `backup` - Sync `~/.openclaw` to GCS
- `restore` - Sync from GCS to `~/.openclaw`

### `./scripts/gog-auth-local.sh` - Local gogcli Authentication
**Runs on**: Local machine (Docker container)
**Requires**: Docker, openclaw-cloud:latest built

**Usage**:
```bash
./scripts/gog-auth-local.sh ~/Downloads/client_secret.json default you@gmail.com
./scripts/gog-auth-local.sh ~/Downloads/work.json work you@company.com --domain company.com
```

Authenticates gogcli locally via browser OAuth flow with named client support, saves credentials to `.config/gogcli/`.

## gogcli Authentication

### Strategy: Authenticate Locally → Sync to VM → Mount as Volume

**Why?**
- ✅ Easy local OAuth (no port forwarding)
- ✅ Credentials NOT in image (safe for registries)
- ✅ Update without rebuilding
- ✅ Standard volume mount pattern
- ✅ Multiple client support (personal, work, etc.)

**Setup:**

```bash
# 1. Create OAuth credentials in Google Cloud Console
#    - APIs & Services > Credentials
#    - Create OAuth 2.0 Client ID (Desktop app)
#    - Download JSON file

# 2. Set keyring password (if not set)
echo "GOG_KEYRING_PASSWORD=$(openssl rand -hex 32)" >> .env

# 3. Authenticate locally with named client
./scripts/gog-auth-local.sh ~/Downloads/client_secret.json default you@gmail.com

# 4. Sync to VM
./scripts/openclaw.sh gog-sync

# 5. Deploy or restart
./scripts/deploy.sh
# OR
./scripts/openclaw.sh restart

# 6. Test
./scripts/openclaw.sh cli gog --client default gmail labels list
```

**Multiple clients:**
```bash
# Personal Gmail
./scripts/gog-auth-local.sh ~/Downloads/personal.json personal you@gmail.com
./scripts/openclaw.sh gog-sync

# Work Workspace
./scripts/gog-auth-local.sh ~/Downloads/work.json work you@company.com --domain company.com
./scripts/openclaw.sh gog-sync

# Test both
./scripts/openclaw.sh cli gog --client personal gmail labels list
./scripts/openclaw.sh cli gog --client work gmail labels list
```

**Update credentials:**
```bash
./scripts/gog-auth-local.sh ~/Downloads/new_creds.json default new@gmail.com
./scripts/openclaw.sh gog-sync
./scripts/openclaw.sh restart
```

**Credential storage:**
- Local: `.config/gogcli/` (gitignored)
- VM: `/home/openclaw/.config/gogcli/`
- Container: `/home/node/.config/gogcli/` (volume mount)
- Image: Does NOT contain credentials ✓

## Deployment Workflow

### Initial Setup (One-Time)

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your GCP project details

# Generate secure token
openssl rand -hex 32

# 2. Create GCP infrastructure and initialize VM
./scripts/setup.sh

# 2.5. (Optional) Authenticate gogcli for Gmail/Calendar/Drive
./scripts/gog-auth-local.sh ~/Downloads/client_secret.json default you@gmail.com
./scripts/openclaw.sh gog-sync

# 3. Build and push initial images
./scripts/build.sh

# 4. Deploy to VM (includes onboarding)
./scripts/deploy.sh
```

### Regular Updates

```bash
# Build new images and deploy
./scripts/deploy.sh --build

# Or separately:
./scripts/build.sh      # Build and push new images
./scripts/deploy.sh     # Deploy to VM
```

### Access OpenClaw UI

```bash
# Set up port forwarding (keeps tunnel open)
./scripts/openclaw.sh forward

# In browser, visit: http://localhost:18789
# Use token from .env to authenticate
```

### View Logs

```bash
./scripts/openclaw.sh logs
```

### Run CLI Commands

```bash
./scripts/openclaw.sh cli gateway status
./scripts/openclaw.sh cli gateway info
```

## Data Persistence

### What's Persisted

| Data | Location | Mechanism |
|------|----------|-----------|
| OpenClaw config | `~/.openclaw/openclaw.json` | Docker volume |
| Model credentials | `~/.openclaw/credentials/` | Docker volume |
| Channel sessions | `~/.openclaw/sessions/` | Docker volume |
| Agent workspace | `~/.openclaw/workspace/` | Docker volume |
| Docker images | VM boot disk (30GB) | Persistent disk |
| External binaries | Docker image | Baked at build time |

### Critical: External Binaries

**From OpenClaw documentation**:
> "Installing binaries inside a running container is a trap. Anything installed at runtime will be lost on restart."

**Solution**: All external tools (gog, goplaces, wacli) are baked into the Docker image at build time in `Dockerfile`.

### Optional Backup

```bash
# Backup before major changes
./scripts/backup.sh backup

# Restore if needed
./scripts/backup.sh restore
```

## Networking

### Access Model

- **VM**: No external IP, IAP tunnel only
- **Gateway**: Binds to `127.0.0.1:18789` (localhost)
- **Access**: SSH port forwarding via gcloud CLI
- **Security**: Token-based authentication

### Port Forwarding

```bash
# Using script (recommended)
./scripts/openclaw.sh forward

# Manual command
gcloud compute ssh ${VM_NAME} \
  --zone=${GCP_ZONE} \
  --tunnel-through-iap \
  -- -L 18789:127.0.0.1:18789 -N
```

### Firewall

- **IAP**: Allowed from `35.235.240.0/20` (Google IAP range)
- **Public**: No ports exposed externally

## Docker Configuration

### Resource Allocation (e2-medium)

- **Total**: 2 vCPU, 4GB RAM
- **Docker**: 1.5 CPU, 3GB RAM
- **OS**: 0.5 CPU, 1GB RAM
- **Node.js**: 2.5GB heap

### docker-compose.yml (on VM)

```yaml
services:
  openclaw-gateway:
    image: ${REGISTRY}/openclaw-cloud:latest
    restart: unless-stopped
    environment:
      HOME: /home/node
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN}
      NODE_OPTIONS: --max-old-space-size=2560
    volumes:
      - ~/.openclaw:/home/node/.openclaw
      - ~/.openclaw/workspace:/home/node/.openclaw/workspace
    ports:
      - "127.0.0.1:18789:18789"
    deploy:
      resources:
        limits:
          cpus: '1.5'
          memory: 3g
    command: ["node", "dist/index.js", "gateway", "--bind", "loopback", "--port", "18789"]
```

## Cost Breakdown

| Component | Monthly Cost |
|-----------|--------------|
| e2-medium VM (730 hrs) | ~$24.27 |
| 30GB persistent disk | ~$1.20 |
| Artifact Registry (~5GB) | ~$0.50 |
| Cloud NAT | ~$1-2 |
| GCS backup (minimal) | ~$0.10 |
| **Total** | **~$27/month** |

**With sustained use discounts**: ~$20-22/month

## Security

### Network Security
- ✅ No external IP on VM
- ✅ IAP tunnel for SSH only
- ✅ Gateway binds to localhost
- ✅ Token-based authentication

### Container Security
- ✅ Runs as non-root user (`node`)
- ✅ Systemd hardening (NoNewPrivileges, ProtectSystem)
- ✅ Resource limits prevent DoS
- ✅ Read-only protections

### Access Control
- ✅ Service account with minimal permissions
- ✅ IAP authentication for SSH
- ✅ No public storage access

## Prerequisites

### Local Development Machine
- `gcloud` CLI installed and authenticated
- Docker installed and running
- Git installed
- Bash shell

### GCP Requirements
- GCP project with billing enabled
- IAM permissions:
  - Compute Admin
  - Artifact Registry Admin
  - Storage Admin (for backups)
  - Service Account User

## Troubleshooting

### VM won't start after deploy
```bash
./scripts/openclaw.sh logs              # Check logs
./scripts/openclaw.sh status            # Check systemd status
```

### Can't connect to UI
```bash
./scripts/openclaw.sh forward           # Verify port forwarding
# Check token matches .env
./scripts/openclaw.sh shell             # SSH to VM
docker ps                          # Verify container running
```

### Out of memory
```bash
# Check Docker logs
./scripts/openclaw.sh logs

# Consider upgrading to e2-standard-2 (8GB RAM)
# Edit .env: MACHINE_TYPE=e2-standard-2
# Redeploy VM (requires recreating)
```

### Image build fails
```bash
# Verify openclaw directory exists
ls -la ./openclaw

# Update openclaw
cd openclaw && git pull && cd ..

# Check Docker daemon
docker ps
```

### Can't pull image on VM
```bash
./scripts/openclaw.sh shell
gcloud auth configure-docker ${REGISTRY_HOST}
docker-compose pull
```

## File Checklist

Files to create/configure:

- [ ] `.env` - Copy from `.env.example` and configure
- [ ] `Dockerfile` - Cloud-extended image definition
- [ ] `docker-compose.yml.tpl` - Template for VM
- [ ] `scripts/setup.sh`
- [ ] `scripts/init-vm.sh`
- [ ] `scripts/build.sh`
- [ ] `scripts/deploy.sh`
- [ ] `scripts/openclaw.sh`
- [ ] `scripts/backup.sh`

## References

- [OpenClaw Official GCP Documentation](https://docs.openclaw.ai/platforms/gcp)
- [OpenClaw GitHub Repository](https://github.com/openclaw/openclaw)
- [GCP Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [GCP Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [GCP IAP Documentation](https://cloud.google.com/iap/docs)
