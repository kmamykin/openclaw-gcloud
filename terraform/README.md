# OpenClaw Compute Engine Deployment with Terraform

This directory contains Terraform infrastructure-as-code for deploying OpenClaw gateway on Google Cloud Compute Engine.

## Overview

**Why Compute Engine?**
- 96% cost savings vs Cloud Run (~$1.20/month vs ~$21/month)
- Eligible for Google Cloud Always Free tier
- Native Node.js installation (no container overhead)
- Local disk storage (no GCS FUSE needed)

**Why Terraform?**
- Industry standard with massive community support
- Excellent state management and remote backend
- Active development (Deployment Manager reaches EOL March 2026)
- Rich validation and testing ecosystem

## Architecture

### Infrastructure Components

- **Compute Instance**: e2-micro (1 vCPU, 2GB RAM) - Always Free eligible
- **Boot Disk**: 10GB standard persistent disk
- **Data Disk**: 20GB standard persistent disk mounted at `/home`
- **Service Account**: Minimal permissions (logging, monitoring)
- **Firewall**: IAP SSH access only (no external IP)
- **Backend**: GCS bucket for Terraform state with versioning

### Software Stack

- **OS**: Debian 12
- **Runtime**: Node.js 22+
- **Package**: openclaw (pinned version from npm)
- **CLI Tool**: gog v0.9.0
- **Service**: systemd unit with auto-restart
- **Access**: SSH via Identity-Aware Proxy + port forwarding

### Security Features

- No external IP address
- SSH only via IAP tunnel
- Gateway binds to loopback (127.0.0.1) only
- Token-based authentication
- systemd security hardening
- Minimal service account permissions
- Encrypted state storage in GCS

## Prerequisites

### Required Tools

1. **Terraform** >= 1.9
   ```bash
   # macOS
   brew install terraform

   # Linux
   wget https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
   unzip terraform_1.9.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

2. **gcloud CLI**
   ```bash
   # macOS
   brew install google-cloud-sdk

   # Linux
   curl https://sdk.cloud.google.com | bash
   ```

3. **Authentication**
   ```bash
   gcloud auth login
   gcloud auth application-default login
   ```

### Required Permissions

Your GCP account needs:
- `compute.admin` or equivalent compute permissions
- `iam.serviceAccountAdmin` for service account creation
- `storage.admin` for state bucket
- `iap.tunnelResourceAccessor` for SSH access

## Quick Start

### 1. Configure

```bash
cd terraform/

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit configuration
vim terraform.tfvars
```

Required settings in `terraform.tfvars`:
```hcl
project_id               = "your-project-id"
openclaw_gateway_token   = "your-secure-token"  # Generate: openssl rand -hex 32
```

Optional overrides:
```hcl
openclaw_version = "2026.1.30"
zone             = "us-east1-b"  # For Always Free eligibility
```

### 2. Initialize

Run one-time setup to create state bucket and enable APIs:

```bash
./scripts/setup.sh
```

This will:
- Verify prerequisites
- Enable required GCP APIs
- Create GCS bucket for Terraform state
- Update backend configuration

### 3. Deploy

```bash
./scripts/deploy.sh
```

This will:
- Initialize Terraform
- Validate configuration
- Create deployment plan
- Prompt for confirmation
- Apply infrastructure changes
- Display outputs

### 4. Wait for Startup

The startup script takes 5-10 minutes to:
- Format and mount data disk
- Install Node.js and dependencies
- Install openclaw and gog
- Configure systemd service

Monitor progress:
```bash
INSTANCE=$(terraform output -raw instance_name)
ZONE=$(terraform output -raw instance_zone)
gcloud compute instances get-serial-port-output $INSTANCE --zone=$ZONE
```

### 5. Verify

```bash
# Check service status
./scripts/ssh.sh status

# View startup log
./scripts/ssh.sh startup

# View service logs
./scripts/ssh.sh logs
```

### 6. Connect

```bash
# Start port forwarding
./scripts/ssh.sh forward

# In another terminal, test gateway
curl http://localhost:18789/health

# Access via WebSocket
# ws://localhost:18789
```

## Daily Operations

### Accessing the Gateway

**Port Forwarding (Recommended)**
```bash
./scripts/ssh.sh forward
# Gateway available at: ws://localhost:18789
```

**Interactive SSH**
```bash
./scripts/ssh.sh shell
```

### Checking Status

```bash
# Service status
./scripts/ssh.sh status

# Stream logs
./scripts/ssh.sh logs

# Startup script log
./scripts/ssh.sh startup
```

### Updating OpenClaw Version

```bash
./scripts/update-version.sh 2026.2.1
```

This will:
1. Update `terraform.tfvars`
2. Install new version on instance
3. Restart service
4. Verify installation

### Manual Service Management

```bash
./scripts/ssh.sh shell

# Restart service
sudo systemctl restart openclaw-gateway

# Stop service
sudo systemctl stop openclaw-gateway

# View service details
sudo systemctl status openclaw-gateway

# View logs
sudo journalctl -u openclaw-gateway -f
```

### Data Management

**View data**
```bash
./scripts/ssh.sh shell
ls -la /home/node/.openclaw/
```

**Backup data**
```bash
# From your local machine
INSTANCE=$(cd terraform && terraform output -raw instance_name)
ZONE=$(cd terraform && terraform output -raw instance_zone)
gcloud compute scp --recurse --tunnel-through-iap \
  --zone=$ZONE \
  $INSTANCE:/home/node/.openclaw \
  ./backup/
```

**Restore data**
```bash
# Stop service first
./scripts/ssh.sh shell
sudo systemctl stop openclaw-gateway
exit

# Upload data
gcloud compute scp --recurse --tunnel-through-iap \
  --zone=$ZONE \
  ./backup/.openclaw/* \
  $INSTANCE:/tmp/restore/

# Move and fix permissions
./scripts/ssh.sh shell
sudo mv /tmp/restore/* /home/node/.openclaw/
sudo chown -R node:node /home/node/.openclaw
sudo systemctl start openclaw-gateway
```

## Migration from Cloud Run

If migrating from existing Cloud Run deployment:

```bash
# 1. Deploy new infrastructure
./scripts/deploy.sh

# 2. Wait for startup to complete (5-10 minutes)

# 3. Migrate data from GCS
./scripts/migrate-data.sh

# 4. Test gateway
./scripts/ssh.sh forward
curl http://localhost:18789/health

# 5. After successful testing, undeploy Cloud Run
cd ..
./gcloud-undeploy.sh
```

The migration script:
- Downloads data from GCS bucket
- Stops OpenClaw service
- Uploads data to Compute Engine instance
- Restarts service
- Verifies migration

## Cost Breakdown

### Always Free Tier (within limits)

| Resource | Quantity | Monthly Cost |
|----------|----------|--------------|
| e2-micro instance | 1 | **FREE** |
| 30GB Standard Disk | 30GB | **FREE** |
| Egress (Internet) | 1GB | **FREE** |
| **Total** | | **~$1.20/month** |

The ~$1.20/month is for minimal network egress beyond free tier.

### Comparison with Cloud Run

| Component | Cloud Run | Compute Engine |
|-----------|-----------|----------------|
| Compute | $17.28/mo | FREE |
| Memory | $3.60/mo | Included |
| Storage | $0.002/mo | $1.20/mo |
| Network | Included | FREE |
| **Total** | **~$21/mo** | **~$1.20/mo** |

**Savings: 96% ($20/month)**

### Free Tier Eligibility

Requirements for Always Free:
- Use `e2-micro` machine type
- Deploy in us-east1, us-central1, or us-west1
- One instance per billing account
- 30GB standard persistent disk included
- 1GB network egress per month

## Configuration Reference

### Variables

All variables in `terraform.tfvars`:

**Required:**
- `project_id` - GCP project ID
- `openclaw_gateway_token` - Auth token (min 32 chars)

**Optional:**
- `region` - GCP region (default: us-east1)
- `zone` - GCP zone (default: us-east1-b)
- `instance_name` - VM name (default: openclaw-gateway)
- `machine_type` - Instance type (default: e2-micro)
- `boot_disk_size_gb` - Boot disk size (default: 10)
- `data_disk_size_gb` - Data disk size (default: 20)
- `openclaw_version` - npm version (default: 2026.1.30)
- `gog_version` - gog CLI version (default: 0.9.0)
- `openclaw_gateway_port` - Listen port (default: 18789)
- `openclaw_gateway_bind` - Bind mode (default: loopback)
- `enable_os_login` - Use OS Login (default: true)
- `labels` - Resource labels

### Outputs

After deployment, `terraform output` shows:
- `instance_name` - VM name
- `instance_zone` - VM zone
- `internal_ip` - Private IP address
- `ssh_command` - SSH via IAP command
- `ssh_with_port_forward` - Port forwarding command
- `gateway_url` - Local HTTP URL
- `gateway_websocket_url` - Local WebSocket URL

## Troubleshooting

### Deployment Issues

**Error: Backend not initialized**
```bash
./scripts/setup.sh  # Re-run setup
terraform init -reconfigure
```

**Error: State locked**
```bash
# Get lock ID from error message
terraform force-unlock LOCK_ID
```

**Error: APIs not enabled**
```bash
gcloud services enable compute.googleapis.com
gcloud services enable iap.googleapis.com
```

### Instance Issues

**Startup script failed**
```bash
# View startup log
./scripts/ssh.sh startup

# Or via gcloud
gcloud compute instances get-serial-port-output \
  $(terraform output -raw instance_name) \
  --zone=$(terraform output -raw instance_zone)
```

**Service won't start**
```bash
./scripts/ssh.sh shell
sudo journalctl -u openclaw-gateway -n 100
sudo systemctl status openclaw-gateway

# Check installation
openclaw --version
node --version
```

**Can't SSH to instance**
```bash
# Verify IAP permissions
gcloud projects get-iam-policy $(terraform output -json | grep project_id | cut -d'"' -f4) \
  --flatten="bindings[].members" \
  --filter="bindings.role:roles/iap.tunnelResourceAccessor"

# Try with verbose output
gcloud compute ssh $(terraform output -raw instance_name) \
  --zone=$(terraform output -raw instance_zone) \
  --tunnel-through-iap \
  --verbosity=debug
```

### Gateway Issues

**Gateway not responding**
```bash
# Check if service is listening
./scripts/ssh.sh shell
sudo netstat -tulpn | grep 18789

# Restart service
sudo systemctl restart openclaw-gateway
```

**Port forwarding not working**
```bash
# Try different local port
gcloud compute ssh $(terraform output -raw instance_name) \
  --zone=$(terraform output -raw instance_zone) \
  --tunnel-through-iap \
  -- -L 19999:localhost:18789 -N

# Then access at localhost:19999
```

**Authentication fails**
```bash
# Verify token matches
./scripts/ssh.sh shell
sudo systemctl show openclaw-gateway -p Environment | grep TOKEN

# Compare with terraform.tfvars
grep gateway_token terraform.tfvars
```

### Disk Issues

**Data disk not mounted**
```bash
./scripts/ssh.sh shell

# Check disk status
lsblk
df -h

# Check fstab
cat /etc/fstab

# Try mounting manually
sudo mount -a
```

**Disk full**
```bash
./scripts/ssh.sh shell

# Check usage
df -h
du -sh /home/node/.openclaw/*

# Clean up old data
cd /home/node/.openclaw
ls -lah
# Remove old files as needed
```

## Maintenance

### Updating Infrastructure

After changing `terraform.tfvars` or `.tf` files:

```bash
terraform plan
terraform apply
```

**Note:** Changes to `openclaw_version` in tfvars won't automatically update the instance due to `ignore_changes` lifecycle rule. Use `./scripts/update-version.sh` instead.

### Disk Snapshots

**Create snapshot**
```bash
gcloud compute disks snapshot \
  $(terraform output -raw data_disk_name) \
  --zone=$(terraform output -raw instance_zone) \
  --snapshot-names=openclaw-data-$(date +%Y%m%d)
```

**Restore from snapshot**
```bash
# Create new disk from snapshot
gcloud compute disks create openclaw-gateway-data-restored \
  --source-snapshot=openclaw-data-20260201 \
  --zone=us-east1-b

# Attach to instance (requires instance stop)
./scripts/ssh.sh shell
sudo systemctl stop openclaw-gateway
exit

gcloud compute instances detach-disk $(terraform output -raw instance_name) \
  --disk=$(terraform output -raw data_disk_name) \
  --zone=$(terraform output -raw instance_zone)

gcloud compute instances attach-disk $(terraform output -raw instance_name) \
  --disk=openclaw-gateway-data-restored \
  --zone=$(terraform output -raw instance_zone)
```

### Scaling Up

To use a larger instance:

```bash
# Edit terraform.tfvars
vim terraform.tfvars
# Change: machine_type = "e2-small"

# Apply change (requires instance stop)
terraform apply

# Note: This exits Always Free tier!
```

### Complete Teardown

```bash
./scripts/destroy.sh
```

This destroys all resources except disks (protected by `prevent_destroy`).

To also delete disks:
```bash
# Create final snapshots (recommended)
gcloud compute disks snapshot $(terraform output -raw boot_disk_name) \
  --zone=$(terraform output -raw instance_zone) \
  --snapshot-names=$(terraform output -raw boot_disk_name)-final

gcloud compute disks snapshot $(terraform output -raw data_disk_name) \
  --zone=$(terraform output -raw instance_zone) \
  --snapshot-names=$(terraform output -raw data_disk_name)-final

# Delete disks (THIS DELETES ALL DATA)
gcloud compute disks delete \
  $(terraform output -raw boot_disk_name) \
  $(terraform output -raw data_disk_name) \
  --zone=$(terraform output -raw instance_zone)
```

## Security Best Practices

1. **Never commit terraform.tfvars** - Contains secrets (gitignored)
2. **Rotate tokens regularly** - Update `openclaw_gateway_token`
3. **Use OS Login** - Better than SSH keys
4. **No external IP** - Access only via IAP
5. **Minimal SA permissions** - Only logging/monitoring
6. **Regular updates** - Keep openclaw and Node.js current
7. **Enable audit logs** - Monitor access
8. **Use strong tokens** - Minimum 32 characters
9. **Backup regularly** - Snapshot data disk
10. **Review IAM** - Least privilege access

## Project Structure

```
terraform/
├── main.tf                         # Core infrastructure
├── variables.tf                    # Input variables
├── outputs.tf                      # Output definitions
├── versions.tf                     # Provider versions
├── backend.tf                      # State backend config
├── terraform.tfvars.example       # Example config
├── terraform.tfvars               # Actual config (gitignored)
├── .gitignore                     # Git ignore rules
├── README.md                      # This file
├── templates/
│   └── startup-script.sh.tpl     # VM initialization
└── scripts/
    ├── setup.sh                   # One-time initialization
    ├── deploy.sh                  # Main deployment
    ├── destroy.sh                 # Teardown
    ├── ssh.sh                     # SSH helper (multi-mode)
    ├── update-version.sh          # Version updates
    └── migrate-data.sh            # Data migration
```

## Additional Resources

- [Terraform GCP Provider Docs](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GCP Always Free Tier](https://cloud.google.com/free/docs/free-cloud-features#free-tier-usage-limits)
- [Identity-Aware Proxy](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [OpenClaw Documentation](https://www.npmjs.com/package/openclaw)
- [systemd Service Management](https://www.freedesktop.org/software/systemd/man/systemd.service.html)

## Support

For issues:
1. Check this README's troubleshooting section
2. Review `./scripts/ssh.sh startup` for startup errors
3. Check service logs: `./scripts/ssh.sh logs`
4. Verify configuration: `terraform validate`
5. Review Terraform state: `terraform state list`
