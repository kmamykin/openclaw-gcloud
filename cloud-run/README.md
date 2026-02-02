# OpenClaw Cloud Run Deployment

Deploy the OpenClaw application to Google Cloud Run using a custom Docker image that includes the `gog` CLI.

> **Note**: This is the legacy Cloud Run deployment. For a more cost-effective solution (~96% savings), see the [Terraform Compute Engine deployment](../terraform/) which costs ~$1.20/month vs ~$21/month for Cloud Run.

## Directory Structure

```
cloud-run/
├── Dockerfile                    # Custom image (FROM openclaw:latest + gog)
├── docker-compose.yml            # Local development compose file
├── docker-entrypoint-gcsfuse.sh  # GCS FUSE mount entrypoint
├── build.sh                      # Build both images locally
├── gcloud-setup.sh               # One-time GCP infrastructure setup
├── gcloud-deploy.sh              # Deploy to Google Cloud Run (idempotent)
├── gcloud-proxy.sh               # Access deployed service via proxy
├── gcloud-undeploy.sh            # Remove Cloud Run service
└── test-local.sh                 # Convenience wrapper for docker compose up
```

## Prerequisites

### Required Software

- **Docker** installed and running
- **Google Cloud SDK** (`gcloud`) installed and authenticated
- A **Google Cloud project** with billing enabled

### Enable Required GCP APIs

```bash
gcloud services enable artifactregistry.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable storage.googleapis.com
```

### Authenticate with Google Cloud

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

## Usage

### 0. Configure Environment Variables

Edit `../.env` (in project root) to set the necessary env vars. See the file for descriptions.

Required variables:
- `GCP_PROJECT_ID` - Your Google Cloud project ID
- `OPENCLAW_GATEWAY_TOKEN` - Gateway authentication token
- `OPENCLAW_GATEWAY_BIND` - Set to "lan" for Cloud Run

### 1. Build Images Locally

```bash
./build.sh
```

This builds:
- `openclaw:latest` - Base image from the `openclaw` subfolder
- `openclaw-cloud:latest` - Extended image with `gog` CLI

### 2. Test Locally

```bash
./test-local.sh
# Or directly:
docker compose up
```

Access the gateway at http://localhost:18789/health

Other useful commands:
```bash
docker compose logs -f          # Follow logs
docker compose down             # Stop and remove containers
```

### 3. One-Time GCP Setup

Run once to set up GCP infrastructure (APIs, Artifact Registry, GCS bucket):

```bash
./gcloud-setup.sh
```

### 4. Deploy to Cloud Run

Deploy or update the Cloud Run service (idempotent):

```bash
./gcloud-deploy.sh
```

### 5. Access Deployed Service

Use the proxy script to access the deployed service:

```bash
./gcloud-proxy.sh
```

### 6. Undeploy (Optional)

To remove the Cloud Run service:

```bash
./gcloud-undeploy.sh
```

**Note**: This does NOT delete the GCS bucket or Artifact Registry images.

## Important Notes

### Cloud Storage FUSE Mount

- **Persistent storage**: State is stored in a GCS bucket mounted at `/home/node/.openclaw` via Cloud Storage FUSE
- **Performance**: GCS FUSE adds some latency compared to local disk, but persists state across container restarts
- **Costs**: GCS storage costs apply (~$0.020/GB/month for standard storage)
- **Requires Gen2 execution environment**: The deployment uses `--execution-environment=gen2` for volume mount support

### Cloud Run Considerations

- **WebSocket support**: Cloud Run supports WebSockets, but connections may be interrupted during scale-down
- **Cold starts**: With `min-instances=0`, there may be cold start latency. Set `min-instances=1` if needed (incurs additional cost)
- **Timeout**: Set to 3600s (1 hour) for long-running WebSocket connections
- **Resources**: Configured with 1 vCPU and 2GB memory

### Environment Variables Set at Runtime

The deployment automatically sets these environment variables:

| Variable | Value | Description |
|----------|-------|-------------|
| `NODE_OPTIONS` | `--max-old-space-size=1536` | Node.js memory limit |
| `HOME` | `/home/node` | Home directory for openclaw config |
| `TERM` | `xterm-256color` | Terminal type |
| `OPENCLAW_GATEWAY_TOKEN` | from `.env` | Gateway authentication token |
| `OPENCLAW_GATEWAY_BIND` | from `.env` | Network binding mode |

### Adding API Keys and Secrets

Additional environment variables (API keys, tokens) can be added to the `gcloud-deploy.sh` script or set via Cloud Run console.

#### Option 1: Environment Variables (less secure)

Add to the `gcloud run deploy` command in `gcloud-deploy.sh`:

```bash
--set-env-vars="ANTHROPIC_API_KEY=your-key-here"
```

#### Option 2: Cloud Run Secrets (recommended)

```bash
# Create the secret
echo -n "your-api-key" | gcloud secrets create ANTHROPIC_API_KEY --data-file=-

# Grant Cloud Run access to the secret
gcloud secrets add-iam-policy-binding ANTHROPIC_API_KEY \
    --member="serviceAccount:YOUR_PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# Add to deployment (modify gcloud-deploy.sh)
--set-secrets="ANTHROPIC_API_KEY=ANTHROPIC_API_KEY:latest"
```

Common secrets you might need:
- `ANTHROPIC_API_KEY` - For Claude models
- `OPENCLAW_GATEWAY_TOKEN` - For secure gateway access

## Verification Steps

1. After deployment, the script outputs the Cloud Run service URL
2. Use `./gcloud-proxy.sh` to access the gateway
3. Check logs in Cloud Console: **Cloud Run > openclaw-gateway > Logs**

### Verify Binaries Are Installed

To verify `gog` is correctly installed:

```bash
# Check during local testing
docker run --rm openclaw-cloud:latest gog --version
```

## Troubleshooting

### Build Fails

- Ensure Docker is running: `docker info`
- Check network connectivity for downloading binaries from GitHub

### Deployment Fails

- Verify GCP authentication: `gcloud auth list`
- Ensure billing is enabled on the project
- Check that required APIs are enabled
- Verify you have sufficient IAM permissions (Cloud Run Admin, Artifact Registry Admin, Storage Admin)

### Container Won't Start

- Check Cloud Run logs for errors
- Verify the base `openclaw:latest` image works locally
- Ensure port 18789 is correctly exposed

### GCS Mount Issues

- Verify the bucket exists and is accessible
- Check Cloud Run service account has Storage Object Admin role on the bucket
- Ensure Gen2 execution environment is being used

## Cost Considerations

With the default configuration (`min-instances=1`, `max-instances=1`):

- **Cloud Run**: ~$17.28/month (container running continuously)
- **Artifact Registry**: ~$0.10/GB/month for stored images
- **Cloud Storage**: ~$0.020/GB/month for standard storage
- **Network egress**: Varies by destination

**Total: ~$21/month**

To minimize costs:
- Consider migrating to [Terraform Compute Engine deployment](../terraform/) for 96% savings (~$1.20/month)
- Use a smaller machine type if memory allows
- Clean up old container images periodically

## Migration to Compute Engine

For significant cost savings, migrate to the Terraform-based Compute Engine deployment:

```bash
# 1. Deploy new infrastructure
cd ../terraform
./scripts/deploy.sh

# 2. Migrate data from Cloud Run
./scripts/migrate-data.sh

# 3. After successful testing, undeploy Cloud Run
cd ../cloud-run
./gcloud-undeploy.sh
```

See [../terraform/README.md](../terraform/README.md) for details.
