# OpenClaw Cloud Deployment

Deploy OpenClaw gateway to Google Cloud Platform with two deployment options:

1. **Terraform + Compute Engine** (Recommended) - ~$1.20/month
2. **Cloud Run** (Legacy) - ~$21/month

## 🚀 Quick Start

### Option 1: Terraform + Compute Engine (Recommended)

**96% cost savings** compared to Cloud Run!

```bash
cd terraform/
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars  # Set project_id and token

./scripts/setup.sh    # One-time setup
./scripts/deploy.sh   # Deploy infrastructure
./scripts/ssh.sh forward  # Access gateway
```

See [terraform/README.md](terraform/README.md) for complete documentation.

**Benefits:**
- Always Free tier eligible (e2-micro instance)
- Native Node.js installation (no container overhead)
- Local disk storage (no GCS FUSE)
- Infrastructure as code with Terraform
- Enhanced security (no external IP)

### Option 2: Cloud Run (Legacy)

Traditional containerized deployment:

```bash
cd cloud-run/
./build.sh            # Build Docker images
./gcloud-setup.sh     # One-time GCP setup
./gcloud-deploy.sh    # Deploy to Cloud Run
./gcloud-proxy.sh     # Access gateway
```

See [cloud-run/README.md](cloud-run/README.md) for complete documentation.

## 📁 Project Structure

```
openclaw-cloud-run/
├── .env                    # Configuration (gitignored)
├── .envrc                  # direnv configuration
├── .gitignore              # Git ignore rules
├── README.md               # This file
├── cloud-run/              # Cloud Run deployment (legacy)
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── docker-entrypoint-gcsfuse.sh
│   ├── build.sh
│   ├── gcloud-setup.sh
│   ├── gcloud-deploy.sh
│   ├── gcloud-proxy.sh
│   ├── gcloud-undeploy.sh
│   ├── test-local.sh
│   └── README.md
└── terraform/              # Terraform deployment (recommended)
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── versions.tf
    ├── backend.tf
    ├── terraform.tfvars.example
    ├── .gitignore
    ├── README.md
    ├── templates/
    │   └── startup-script.sh.tpl
    └── scripts/
        ├── setup.sh
        ├── deploy.sh
        ├── destroy.sh
        ├── ssh.sh
        ├── update-version.sh
        └── migrate-data.sh
```

## 💰 Cost Comparison

| Component | Cloud Run | Compute Engine (Terraform) |
|-----------|-----------|----------------------------|
| Compute | $17.28/month | **FREE** (Always Free e2-micro) |
| Memory | $3.60/month | **Included** |
| Storage | $0.002/month (GCS) | $1.20/month (30GB local disk) |
| Network | Included | **FREE** (no external IP) |
| **Total** | **~$21/month** | **~$1.20/month** |

**Savings: 96% ($20/month)**

## 🔧 Prerequisites

### Both Deployments

1. **Google Cloud account** with billing enabled
2. **gcloud CLI** installed and authenticated
   ```bash
   gcloud auth login
   gcloud config set project YOUR_PROJECT_ID
   ```

### Additional for Cloud Run

- **Docker** installed and running

### Additional for Terraform

- **Terraform** >= 1.9
  ```bash
  # macOS
  brew install terraform

  # Linux
  wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
  unzip terraform_1.9.0_linux_amd64.zip
  sudo mv terraform /usr/local/bin/
  ```

## ⚙️ Configuration

Edit `.env` in the project root:

```bash
# Required
export GCP_PROJECT_ID="your-project-id"
export OPENCLAW_GATEWAY_TOKEN="your-secure-token"  # Generate: openssl rand -hex 32

# Optional
export GCP_REGION="us-east1"
export GCP_ZONE="us-east1-b"           # For Terraform deployment
export OPENCLAW_GATEWAY_PORT="18789"
export OPENCLAW_GATEWAY_BIND="loopback"  # For Terraform (use "lan" for Cloud Run)
```

## 🔄 Migration from Cloud Run to Terraform

If you're currently using Cloud Run:

```bash
# 1. Deploy new Terraform infrastructure
cd terraform/
./scripts/deploy.sh

# 2. Wait for startup (5-10 minutes)
./scripts/ssh.sh status

# 3. Migrate data from GCS to local disk
./scripts/migrate-data.sh

# 4. Test the new deployment
./scripts/ssh.sh forward
# In another terminal:
curl http://localhost:18789/health

# 5. After successful testing, undeploy Cloud Run
cd ../cloud-run/
./gcloud-undeploy.sh
```

## 📖 Documentation

- [Terraform Deployment Guide](terraform/README.md) - Complete guide for Compute Engine deployment
- [Cloud Run Deployment Guide](cloud-run/README.md) - Legacy containerized deployment

## 🔒 Security

### Terraform Deployment

- No external IP address
- SSH access via Identity-Aware Proxy only
- Gateway binds to loopback (127.0.0.1)
- Access via SSH port forwarding
- Minimal service account permissions
- systemd security hardening

### Cloud Run Deployment

- Requires authentication by default
- Token-based gateway access
- GCS FUSE for persistent storage
- Cloud Run automatic HTTPS

## 🛠️ Common Operations

### Access Gateway

**Terraform:**
```bash
cd terraform/
./scripts/ssh.sh forward
# Access at: ws://localhost:18789
```

**Cloud Run:**
```bash
cd cloud-run/
./gcloud-proxy.sh
# Access at: ws://localhost:18789
```

### Check Service Status

**Terraform:**
```bash
cd terraform/
./scripts/ssh.sh status
./scripts/ssh.sh logs
```

**Cloud Run:**
```bash
gcloud run services describe openclaw-gateway --region=us-east1
gcloud logging read "resource.type=cloud_run_revision"
```

### Update OpenClaw Version

**Terraform:**
```bash
cd terraform/
./scripts/update-version.sh 2026.2.1
```

**Cloud Run:**
```bash
cd cloud-run/
# Update openclaw version in Dockerfile
./build.sh
./gcloud-deploy.sh
```

## 🐛 Troubleshooting

### Terraform Issues

See [terraform/README.md#troubleshooting](terraform/README.md#troubleshooting)

### Cloud Run Issues

See [cloud-run/README.md#troubleshooting](cloud-run/README.md#troubleshooting)

## 📝 License

See the OpenClaw package for licensing information.

## 🤝 Contributing

Contributions welcome! Please ensure:
- Terraform configurations are validated
- Scripts are tested
- Documentation is updated
- Security best practices are followed
