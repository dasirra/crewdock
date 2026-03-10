FROM alpine/openclaw:latest

USER root

# Core tools
RUN apt-get update && apt-get install -y \
    jq \
    procps \
    curl \
    gnupg \
    git \
    build-essential \
    python3 \
    python3-pip \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    sqlite3 \
    && mkdir -p /usr/share/keyrings \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y tailscale \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Ensure home is owned by node
RUN mkdir -p /home/node/projects \
    && chown -R node:node /home/node

USER node
ENV PATH="/home/node/.local/bin:${PATH}"

# Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Claude Code default settings
RUN mkdir -p /home/node/.claude \
    && echo '{"plugins":{"allow":["acpx"]}}' > /home/node/.claude/settings.json
