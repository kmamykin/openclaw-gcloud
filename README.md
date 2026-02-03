# OpenClaw Google Cloud Deployment

Deploy OpenClaw gateway to Google Cloud Platform:

## 📁 Project Structure

```
openclaw-gcloud/
├── .env                    # Configuration (gitignored)
├── .envrc                  # direnv configuration
├── .gitignore              # Git ignore rules
├── README.md               # This file
├── openclaw                # Repository of openclaw checked out for reference (gitignored)
├── cloud-run/              # Cloud Run deployment (abandoned approach using Cloud Run GCP service. The setup and deployment approach using gcloud cli is what we'd want now. Cloud run itself did not work out)
└── terraform/              # Terraform deployment (abandoned approach using Terraform and GCP Compute Engine)
```

Use `./cloud-run` and `./terraform` folders for reference, some ideas worked, some didn't.

Re-implement openclaw deployment using the following approach:

## Approach

Important vars are setup in .env

This is the approach to follow: https://docs.openclaw.ai/platforms/gcp , but we need to automate it and make it maintainable, replicatable, easy to push new releases of openclow.

Setup a VM (name: openclaw-gateway, machine type: e2-medium, 2CPU, 4GB mem, install vim, gcloud, gcloud storage fuse driver). Install docker on the VM. User GCP_VM_USER env var (set in .env) to use as a user on the VM that has sudo permissions. 

Setup an artifactory repository to store docker images (it may already exist).

Create a `docker-compose.yml` on the VM to simplify starting docker with all the vars and mounts.

Setup VM to start a container (using docker compose) at startup (this can be enabled later after the kinks are worked out).

Deploy should pull the latest image from the repository to the VM, restart the container to pick up the latest image.

OpenClaw persistent storage. Options (TBD the best): 

* Store files in blob storage. Create a bucket with name $GCS_BUCKET_NAME. The bucket will be mounted (using FUSE) inside the container at `/home/node/.openclaw` inside the container (because the container will run as `node` user). 
* Alternatively mount the bucket $GCS_BUCKET_NAME as `/home/$GCP_VM_USER/.openclaw` and expose it to the container as a volume.
* Use the local disk as openclaw storage, with a backup to the bucket.

Networking:
When container starts on the VM it should bind to $OPENCLAW_GATEWAY_PORT on the VM. When port forwarding is used from a local machine to gcp VM, requests for http://localhost:$OPENCLAW_GATEWAY_PORT should be handled by the container with openclaw.

* Scripts:
  - ./scripts/setup.sh    # One-time setup of all resources in GCP, using `gcloud` cli, idempotent
  - ./scripts/build.sh    # Build a latest image of opwnclaw, push to atrifact repository
  - ./scripts/deploy.sh   # Deploy a latest image of opwnclaw, pull the image from artifact directory and update VM to run that image. The first deploy should also run openclaw onboard to setup minimal config in non-interactive mode (e.g. token)
  - ./scripts/ssh.sh      # args: (shell|forward|logs|cli) shell:open up a ssh shell to the Vm instance. forward: setup port forwarding for openclaw port. logs: output latest logs from openclaw running on VM inside a docker container. cli: open ssh connection and then exec to the container.

