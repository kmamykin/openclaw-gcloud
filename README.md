# Deploy OpenClaw to Google Cloud Run

Deploy the OpenClaw application (from the `openclaw` subfolder) to Google Cloud Run using a custom Docker image that includes the `gog` CLI.

## Directory Structure

```
openclaw-cloud-run/
├── Dockerfile              # Custom image (FROM openclaw:latest + gog)
├── docker-compose.yml      # Local development compose file
├── build.sh                # Build both images locally
├── deploy-gcloud.sh        # Deploy to Google Cloud Run
├── test-local.sh           # Convenience wrapper for docker compose up
├── data/                   # Local persistent data (gitignored)
└── openclaw/               # Existing openclaw repository (separately cloned, gitignored)
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
gcloud services enable places.googleapis.com
```

### Authenticate with Google Cloud

```bash
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

## Usage

### 0. Configure Environment Variables

Edit `.env` to set the necessary env vars. See the file for descriptions.

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
docker compose run openclaw-cli # Run CLI commands
```

### 3. Deploy to Cloud Run

```bash
source .env && ./deploy-gcloud.sh
```

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

Additional environment variables (API keys, tokens) can be added to the `deploy-gcloud.sh` script or set via Cloud Run console.

#### Option 1: Environment Variables (less secure)

Add to the `gcloud run deploy` command in `deploy-gcloud.sh`:

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

# Add to deployment (modify deploy-gcloud.sh)
--set-secrets="ANTHROPIC_API_KEY=ANTHROPIC_API_KEY:latest"
```

Common secrets you might need:
- `ANTHROPIC_API_KEY` - For Claude models
- `OPENCLAW_GATEWAY_TOKEN` - For secure gateway access (auto-generated if not set)

## Verification Steps

1. After deployment, the script outputs the Cloud Run service URL
2. Access `<service-url>/health` to verify the gateway is running
3. Check logs in Cloud Console: **Cloud Run > openclaw > Logs**

### Verify Binaries Are Installed

To verify `gog` is correctly installed:

```bash
# Check during local testing
docker run --rm openclaw-cloud:latest gog --version
```

## Troubleshooting

### Build Fails

- Ensure Docker is running: `docker info`
- Ensure the `openclaw` subfolder contains a valid Dockerfile
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

- **Cloud Run**: Container is running all the time. Pay (~$0.00002400/vCPU-second, ~$0.00000250/GiB-second)
- **Artifact Registry**: ~$0.10/GB/month for stored images
- **Cloud Storage**: ~$0.020/GB/month for standard storage + operation costs
- **Network egress**: Varies by destination

To minimize costs:
- Use a smaller machine type if memory allows
- Clean up old container images periodically

## License

See the `openclaw` subfolder for the OpenClaw license.
