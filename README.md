# OpenClaw Google Cloud Deployment

Automated deployment of OpenClaw Gateway on Google Cloud Platform using GCP Compute Engine and Artifact Registry. Supports both VM deployment and local Docker execution with git-based sync.

**Target Cost**: ~$24/month for e2-medium VM
**Documentation**: Based on [Official OpenClaw GCP Guide](https://docs.openclaw.ai/platforms/gcp)

## Project Structure

```
openclaw-gcloud/
├── .env                        # GCP infrastructure config (gitignored)
├── .env.example                # Infrastructure config template
├── .envrc                      # direnv configuration
├── .gitignore                  # Git ignore rules
├── README.md                   # This file
├── Dockerfile                  # Cloud-extended image (adds tools to base openclaw)
├── docker-compose.yml.tpl      # Template for VM docker-compose.yml
├── docker-compose.local.yml    # Local Docker execution config
├── .openclaw/                  # Separate git repo (synced to VM, gitignored by parent)
│   ├── .env                    # OpenClaw secrets (gateway token, API keys, gogcli)
│   ├── .env.example            # Secrets template
│   ├── .config/gogcli/         # OAuth tokens (moved from .config/gogcli/)
│   ├── openclaw.json           # OpenClaw config
│   ├── credentials/            # Model credentials
│   ├── workspace/              # Separate git repo (GitHub remote)
│   ├── sessions/               # Ephemeral (gitignored)
│   └── .gitignore
├── openclaw/                   # Official OpenClaw repository (gitignored)
└── scripts/
    ├── setup.sh                # One-time GCP infrastructure setup
    ├── init-vm.sh              # One-time VM initialization
    ├── build.sh                # Build Docker images (--local for native arch)
    ├── deploy.sh               # Deploy/update container on VM
    ├── openclaw.sh             # VM management (shell, forward, logs, cli, sync)
    ├── local.sh                # Local Docker execution (start, stop, logs, build)
    ├── backup.sh               # Backup/restore OpenClaw data
    ├── gog-auth-local.sh       # Local gogcli OAuth authentication
    ├── vm-git-init.sh          # One-time VM restructure to git-based sync
    └── lib/
        ├── env.sh              # Environment loading (sources both .env files)
        ├── path.sh             # Path resolution utilities
        ├── validation.sh       # Variable validation utilities
        └── ssh-setup.sh        # SSH config for git-over-IAP
```

## Architecture Overview

### Two Execution Modes

**VM Mode** (production): Container runs on GCP VM, accessed via IAP tunnel port forwarding.
**Local Mode** (development): Container runs locally in Docker, accessed at localhost:18789.

Both modes use identical Docker images and mount `.openclaw/` the same way.

### Configuration Split

| File | Contains | Tracked by |
|------|----------|------------|
| `.env` | GCP infrastructure vars (project, region, VM, registry) | `.gitignore` (not in git) |
| `.openclaw/.env` | OpenClaw secrets (token, API keys, gogcli password) | `.openclaw` git repo |

### Sync Architecture

```
┌──────────────────┐                          ┌──────────────────┐
│ Local Machine    │                          │ GCP VM           │
│                  │      git push/pull       │                  │
│ .openclaw/       │ ◄──────────────────────► │ .openclaw/       │
│  (git clone)     │    (via IAP SSH)         │  (working copy)  │
│                  │                          │                  │
│ .openclaw.git    │                          │ .openclaw.git    │
│  (not present)   │                          │  (bare repo)     │
└──────────────────┘                          └──────────────────┘
        │                                             │
        │                                             │
        ▼                                             ▼
┌──────────────────┐                          ┌──────────────────┐
│ workspace/       │      git push/pull       │ workspace/       │
│  (git repo)      │ ◄──────────────────────► │  (git repo)      │
└──────────────────┘    (via GitHub)          └──────────────────┘
```

- `.openclaw/` syncs directly between local and VM via git (never touches GitHub)
- `workspace/` syncs via GitHub as a backup and sharing mechanism

### Docker Image Strategy

**Two-Image Build Process**:

1. **openclaw:latest** (Base Image) - Built from official OpenClaw repository at `./openclaw`
2. **openclaw-cloud:latest** (Cloud-Extended Image) - Extends base with gog CLI, gh CLI, uv, ffmpeg, vim, Gemini CLI

**Multi-arch support**:
- `./scripts/build.sh` - Builds for linux/amd64 (VM) and pushes to registry
- `./scripts/build.sh --local` - Builds for native platform (arm64 on Mac), no push

### Infrastructure Components

| Component | Specification | Purpose |
|-----------|--------------|---------|
| **Compute** | GCP Compute Engine e2-medium | 2 vCPU, 4GB RAM for Docker containers |
| **Boot Disk** | 30GB Debian 12 persistent disk | OS, Docker images, and layers |
| **Storage** | Docker volumes -> local disk | Persistent OpenClaw data |
| **Registry** | GCP Artifact Registry | Store versioned Docker images |
| **Networking** | IAP tunnel (no external IP) | Secure SSH and port forwarding |
| **NAT** | Cloud NAT | Outbound internet without public IP |
| **Backup** | GCS bucket (optional) | Disaster recovery |

## Quick Start

### Initial Setup (One-Time)

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your GCP project details

# Create .openclaw/.env from template
cp .openclaw/.env.example .openclaw/.env
# Edit with gateway token (openssl rand -hex 32) and API keys

# 2. Create GCP infrastructure and initialize VM
./scripts/setup.sh

# 3. Build and push images
./scripts/build.sh

# 4. Deploy to VM
./scripts/deploy.sh

# 5. Access the gateway
./scripts/openclaw.sh forward
# Visit http://localhost:18789
```

### Local Development

```bash
# Build image for local architecture
./scripts/build.sh --local

# Start locally
./scripts/local.sh start

# Visit http://localhost:18789
# View logs
./scripts/local.sh logs
```

### Syncing Between Local and VM

```bash
# Push local .openclaw changes to VM
./scripts/openclaw.sh sync push

# Pull VM .openclaw changes locally
./scripts/openclaw.sh sync pull

# Sync workspace via GitHub
./scripts/openclaw.sh sync workspace
```

### gogcli Authentication

```bash
# 1. Set keyring password in .openclaw/.env
echo "export GOG_KEYRING_PASSWORD=$(openssl rand -hex 32)" >> .openclaw/.env

# 2. Authenticate locally (opens browser)
./scripts/gog-auth-local.sh ~/Downloads/client_secret.json default you@gmail.com

# 3. Sync to VM
./scripts/openclaw.sh sync push

# 4. Restart to pick up new credentials
./scripts/openclaw.sh restart
```

## Scripts Reference

### `./scripts/setup.sh` - Infrastructure Setup
One-time GCP setup: APIs, Artifact Registry, VM, Cloud NAT, IAP firewall, init-vm.

### `./scripts/init-vm.sh` - VM Initialization
Runs on VM: installs Docker + git, creates directories, initializes .openclaw git repo + bare repo, sets up systemd service.

### `./scripts/build.sh` - Build Images
- Default: builds for linux/amd64 + pushes to Artifact Registry
- `--local`: builds for native platform (arm64 on Mac), no push

### `./scripts/deploy.sh` - Deploy to VM
- `--build`: build images first
- `--no-sync`: skip auto-syncing .openclaw
- Auto-syncs .openclaw to VM before deploy (if git repo exists)

### `./scripts/openclaw.sh` - VM Management
```bash
./scripts/openclaw.sh vm-shell      # SSH shell with port forwarding
./scripts/openclaw.sh forward       # Port forwarding only
./scripts/openclaw.sh shell         # Bash in container
./scripts/openclaw.sh logs          # Stream logs
./scripts/openclaw.sh cli CMD       # Run CLI commands
./scripts/openclaw.sh status        # Systemd status
./scripts/openclaw.sh ps            # Container status
./scripts/openclaw.sh restart       # Restart container
./scripts/openclaw.sh sync push     # Push .openclaw to VM
./scripts/openclaw.sh sync pull     # Pull .openclaw from VM
./scripts/openclaw.sh sync workspace # Sync workspace via GitHub
```

### `./scripts/local.sh` - Local Docker Execution
```bash
./scripts/local.sh start    # Start local gateway
./scripts/local.sh stop     # Stop
./scripts/local.sh logs     # Stream logs
./scripts/local.sh shell    # Bash in container
./scripts/local.sh cli CMD  # Run CLI commands
./scripts/local.sh build    # Build local image
./scripts/local.sh status   # Container status
```

### `./scripts/backup.sh` - Backup/Restore
```bash
./scripts/backup.sh backup   # Backup .openclaw to GCS
./scripts/backup.sh restore  # Restore from GCS
./scripts/backup.sh list     # List backups
```

### `./scripts/vm-git-init.sh` - VM Git Migration
One-time script to migrate existing VM from old layout (`.openclaw` in home dir) to new git-based layout (`.openclaw` in `~/openclaw/`). Run `backup.sh backup` first!

### `./scripts/gog-auth-local.sh` - gogcli Authentication
Runs OAuth flow locally, saves credentials to `.openclaw/.config/gogcli/`.

## Data Persistence

| Data | Location | Sync Method |
|------|----------|-------------|
| OpenClaw config | `.openclaw/openclaw.json` | git (local <-> VM) |
| Model credentials | `.openclaw/credentials/` | git (local <-> VM) |
| gogcli OAuth tokens | `.openclaw/.config/gogcli/` | git (local <-> VM) |
| Secrets (.env) | `.openclaw/.env` | git (local <-> VM) |
| Agent workspace | `.openclaw/workspace/` | git via GitHub |
| Channel sessions | `.openclaw/sessions/` | ephemeral (gitignored) |
| Docker images | VM boot disk / local | Artifact Registry |

## VM Directory Layout

```
/home/${GCP_VM_USER}/openclaw/
├── .openclaw.git/              # Bare repo (receives pushes from local)
├── .openclaw/                  # Working copy (cloned from bare)
│   ├── .env                    # OpenClaw secrets
│   ├── .config/gogcli/         # OAuth tokens
│   ├── openclaw.json           # Config
│   ├── credentials/            # Model creds
│   ├── workspace/              # Separate git repo (GitHub remote)
│   ├── sessions/               # Ephemeral (gitignored)
│   └── .gitignore
├── docker-compose.yml          # Generated from template
└── .env                        # GCP infrastructure vars
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

## Security

- No external IP on VM (IAP tunnel only)
- Gateway binds to localhost on VM
- Token-based authentication
- Non-root container user (`node`)
- Systemd hardening (NoNewPrivileges, ProtectSystem)
- Secrets in private git repo (never pushed to GitHub)
- .openclaw/.env contains sensitive data, synced only via SSH/IAP

## Troubleshooting

### VM won't start
```bash
./scripts/openclaw.sh logs
./scripts/openclaw.sh status
```

### Local container won't start
```bash
./scripts/local.sh logs
docker image inspect openclaw-cloud:latest  # Check image exists
```

### Sync fails
```bash
# Verify SSH config
cat ~/.ssh/config | grep openclaw-vm
# Re-run sync (will auto-setup SSH config)
./scripts/openclaw.sh sync push
```

### Can't connect to UI
```bash
./scripts/openclaw.sh forward    # VM access
# OR
./scripts/local.sh start         # Local access at localhost:18789
```

## References

- [OpenClaw Official GCP Documentation](https://docs.openclaw.ai/platforms/gcp)
- [OpenClaw GitHub Repository](https://github.com/openclaw/openclaw)
- [GCP Compute Engine Documentation](https://cloud.google.com/compute/docs)
- [GCP Artifact Registry Documentation](https://cloud.google.com/artifact-registry/docs)
- [GCP IAP Documentation](https://cloud.google.com/iap/docs)
