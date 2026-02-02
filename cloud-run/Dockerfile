# Start from the openclaw base image
# Use BASE_IMAGE arg for multi-arch builds (from registry), defaults to local image
ARG BASE_IMAGE=openclaw:latest
FROM ${BASE_IMAGE}

# Switch to root to install binaries
USER root

# Download and install gog (gogcli) from GitHub releases
# Note: wacli has no Linux builds, only macOS
ARG GOG_VERSION=0.9.0
ARG TARGETARCH

RUN apt-get update && apt-get install -y curl vim \
    && ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") \
    && curl -fsSL "https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_${ARCH}.tar.gz" \
       | tar -xzf - -C /usr/local/bin gog \
    && chmod +x /usr/local/bin/gog \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install gcsfuse for GCS bucket mounting
RUN apt-get update && apt-get install -y lsb-release gnupg \
    && export GCSFUSE_REPO=gcsfuse-`lsb_release -c -s` \
    && echo "deb https://packages.cloud.google.com/apt $GCSFUSE_REPO main" | tee /etc/apt/sources.list.d/gcsfuse.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && apt-get update \
    && apt-get install -y gcsfuse \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install gcloud CLI for Cloud Run proxy
RUN echo "deb https://packages.cloud.google.com/apt cloud-sdk main" | tee /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update \
    && apt-get install -y google-cloud-cli google-cloud-cli-cloud-run-proxy \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy and setup gcsfuse entrypoint script
COPY docker-entrypoint-gcsfuse.sh /docker-entrypoint-gcsfuse.sh
RUN chmod +x /docker-entrypoint-gcsfuse.sh

# Switch back to non-root user
USER node

# Inherit CMD from base image: node dist/index.js
