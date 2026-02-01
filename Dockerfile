# Start from the openclaw base image (built locally)
FROM openclaw:latest

# Switch to root to install binaries
USER root

# Download and install gog (gogcli) and wacli from GitHub releases
ARG GOG_VERSION=v0.9.0
ARG WACLI_VERSION=v0.2.0

RUN apt-get update && apt-get install -y curl \
    && curl -fsSL "https://github.com/steipete/gogcli/releases/download/${GOG_VERSION}/gogcli-linux-amd64" -o /usr/local/bin/gog \
    && curl -fsSL "https://github.com/steipete/wacli/releases/download/${WACLI_VERSION}/wacli-linux-amd64" -o /usr/local/bin/wacli \
    && chmod +x /usr/local/bin/gog /usr/local/bin/wacli \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Switch back to non-root user
USER node

# Inherit CMD from base image: node dist/index.js
