# Cloud-extended OpenClaw image
# Extends the base openclaw image with cloud-specific tools

# Base image passed from build.sh (version controlled there)
ARG BASE_IMAGE=ghcr.io/openclaw/openclaw:latest
FROM ${BASE_IMAGE}

# Switch to root to install binaries
USER root

ARG TARGETARCH

# Install basic utilities, ffmpeg, CLI tools, GitHub CLI, and uv
RUN apt-get update && apt-get install -y curl vim ffmpeg gnupg \
    jq ripgrep fd-find tree bat sqlite3 xmlstarlet pandoc wget jo httpie unzip \
    # Install GitHub CLI (gh)
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y gh \
    # Install uv (fast Python package installer)
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && cp /root/.local/bin/uv /usr/local/bin/ \
    && cp /root/.local/bin/uvx /usr/local/bin/ \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    # Symlink Debian-named binaries to their common names
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# Add openclaw command wrapper
COPY openclaw-wrapper.sh /usr/local/bin/openclaw
RUN chmod +x /usr/local/bin/openclaw

# Install Google Gemini CLI, Google Workspace CLI, Playwright, and Playwright CLI globally (as root)
RUN npm install -g @google/gemini-cli @googleworkspace/cli @steipete/summarize pdfkit playwright @playwright/cli

# Install Playwright Chromium browser and its system dependencies (baked into image)
RUN npx playwright install --with-deps chromium

# Install Playwright CLI skills (for Claude Code skill discovery)
RUN playwright-cli install --skills

# Install Google Workspace CLI agent skills
RUN mkdir -p /opt/skills/gws-skills && \
    npx skills add https://github.com/googleworkspace/cli --dir /opt/skills/gws-skills -y

# Install CLI tools from GitHub releases (yq, gron, xsv, pup)
ARG GRON_VERSION=0.7.1
RUN ARCH=$([ "$TARGETARCH" = "arm64" ] && echo "arm64" || echo "amd64") \
    # yq - YAML/TOML/XML/CSV processor
    && curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    # gron - make JSON greppable
    && curl -fsSL "https://github.com/tomnomnom/gron/releases/download/v${GRON_VERSION}/gron-linux-${ARCH}-${GRON_VERSION}.tgz" \
       | tar -xzf - -C /usr/local/bin \
    && chmod +x /usr/local/bin/gron \
    # xsv - fast CSV toolkit (amd64 only)
    && if [ "$ARCH" = "amd64" ]; then \
         curl -fsSL "https://github.com/BurntSushi/xsv/releases/download/0.13.0/xsv-0.13.0-x86_64-unknown-linux-musl.tar.gz" \
           | tar -xzf - -C /usr/local/bin; \
         chmod +x /usr/local/bin/xsv; \
       fi \
    # pup - HTML parsing (like jq for HTML)
    && curl -fsSL "https://github.com/ericchiang/pup/releases/download/v0.4.0/pup_v0.4.0_linux_${ARCH}.zip" -o /tmp/pup.zip \
    && unzip -o /tmp/pup.zip -d /usr/local/bin \
    && chmod +x /usr/local/bin/pup \
    && rm /tmp/pup.zip

# Switch back to non-root user
USER node

# Symlink gws config so gws CLI finds creds at its expected ~/.config/gws path
# Actual creds live in ~/.openclaw/.config/gws (mounted as volume)
RUN mkdir -p ~/.config && \
    ln -sf /home/node/.openclaw/.config/gws /home/node/.config/gws

# Copy bash configuration
COPY .bashrc /home/node/.bashrc

# Inherit CMD from base image: node dist/index.js
