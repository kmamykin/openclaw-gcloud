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

RUN apt-get update && apt-get install -y curl \
    && ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") \
    && curl -fsSL "https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_${ARCH}.tar.gz" \
       | tar -xzf - -C /usr/local/bin gog \
    && chmod +x /usr/local/bin/gog \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch back to non-root user
USER node

# Inherit CMD from base image: node dist/index.js
