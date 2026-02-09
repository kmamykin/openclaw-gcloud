# Cloud-extended OpenClaw image
# Extends the base openclaw image with cloud-specific tools

# Use BASE_IMAGE arg for multi-arch builds (from registry), defaults to local image
ARG BASE_IMAGE=openclaw:latest
FROM ${BASE_IMAGE}

# Switch to root to install binaries
USER root

# Download and install gog (gogcli) from GitHub releases
# Note: wacli has no Linux builds, only macOS
ARG GOG_VERSION=0.9.0
ARG TARGETARCH

# Install basic utilities, ffmpeg, GitHub CLI, gog CLI, and uv
RUN apt-get update && apt-get install -y curl vim ffmpeg gnupg \
    # Install GitHub CLI (gh)
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y gh \
    # Install gog CLI
    && ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") \
    && curl -fsSL "https://github.com/steipete/gogcli/releases/download/v${GOG_VERSION}/gogcli_${GOG_VERSION}_linux_${ARCH}.tar.gz" \
       | tar -xzf - -C /usr/local/bin gog \
    && chmod +x /usr/local/bin/gog \
    # Install uv (fast Python package installer)
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && cp /root/.local/bin/uv /usr/local/bin/ \
    && cp /root/.local/bin/uvx /usr/local/bin/ \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Add openclaw command wrapper
COPY scripts/docker/openclaw-wrapper.sh /usr/local/bin/openclaw
RUN chmod +x /usr/local/bin/openclaw

# Install Google Gemini CLI globally (as root)
RUN npm install -g @google/gemini-cli

# Switch back to non-root user
USER node

# Symlink gogcli config so gog CLI finds creds at its expected ~/.config/gogcli path
# Actual creds live in ~/.openclaw/.config/gogcli (mounted as volume)
RUN mkdir -p ~/.config && \
    ln -sf /home/node/.openclaw/.config/gogcli /home/node/.config/gogcli

# Copy bash configuration
COPY scripts/docker/.bashrc /home/node/.bashrc

# Create SSH config for GitHub
RUN mkdir -p ~/.ssh && \
    echo "Host github.com" > ~/.ssh/config && \
    echo "  Hostname github.com" >> ~/.ssh/config && \
    echo "  IdentityFile ~/.openclaw/ssh/github_rsa" >> ~/.ssh/config && \
    echo "  User git" >> ~/.ssh/config && \
    chmod 600 ~/.ssh/config

# Inherit CMD from base image: node dist/index.js
