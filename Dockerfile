FROM alpine/openclaw:latest

USER root

# Install dev tools, Flutter deps + Tailscale CLI
RUN apt-get update && apt-get install -y \
    jq \
    procps \
    file \
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
    && mkdir -p /usr/share/keyrings \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null \
    && curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list \
    && apt-get update \
    && apt-get install -y tailscale \
    && rm -rf /var/lib/apt/lists/*

# Install obsidian-cli
RUN curl -L https://github.com/Yakitrak/obsidian-cli/releases/download/v0.2.3/obsidian-cli_0.2.3_linux_amd64.tar.gz -o obsidian-cli.tar.gz \
    && tar -xzf obsidian-cli.tar.gz obsidian-cli \
    && mv obsidian-cli /usr/local/bin/obsidian-cli \
    && chmod +x /usr/local/bin/obsidian-cli \
    && rm obsidian-cli.tar.gz

# Install gog (Google Workspace CLI: Gmail, Calendar, Drive, Tasks, etc.)
RUN curl -L https://github.com/steipete/gogcli/releases/download/v0.11.0/gogcli_0.11.0_linux_amd64.tar.gz -o gog.tar.gz \
    && tar -xzf gog.tar.gz gog \
    && mv gog /usr/local/bin/gog \
    && chmod +x /usr/local/bin/gog \
    && rm gog.tar.gz

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Flutter SDK
RUN git clone --branch stable https://github.com/flutter/flutter.git /opt/flutter \
    && chown -R node:node /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"

# Create dev workspace & ensure home is owned by node
RUN mkdir -p /home/node/projects \
    && chown -R node:node /home/node

USER node
ENV PATH="/home/node/.local/bin:${PATH}"

# Pre-cache Flutter artifacts
RUN flutter precache

# Claude Code CLI (installed as node user)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Claude Code default settings
RUN mkdir -p /home/node/.claude \
    && echo '{"plugins":{"allow":["acpx"]}}' > /home/node/.claude/settings.json
