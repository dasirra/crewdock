FROM alpine/openclaw:latest

USER root

# Install dev tools + Tailscale CLI (daemon runs natively on host)
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

# Create dev workspace
RUN mkdir -p /home/node/projects && chown -R node:node /home/node/projects

USER node
