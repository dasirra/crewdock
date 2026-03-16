ARG OPENCLAW_VERSION=latest
FROM alpine/openclaw:${OPENCLAW_VERSION}

USER root

# Core tools
RUN apt-get update && apt-get install -y \
    cron \
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
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /usr/share/keyrings/githubcli-archive-keyring.gpg >/dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      | tee /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# xurl CLI (X/Twitter API v2)
RUN XURL_TAG=$(curl -sf https://api.github.com/repos/xdevplatform/xurl/releases/latest | jq -r '.tag_name') \
    && [ "$XURL_TAG" != "null" ] && [ -n "$XURL_TAG" ] \
    && curl -fsSL "https://github.com/xdevplatform/xurl/releases/download/${XURL_TAG}/xurl_Linux_x86_64.tar.gz" \
      | tar -xz -C /usr/local/bin xurl \
    && chmod +x /usr/local/bin/xurl

# Google Workspace CLI (gws) + agent skills
RUN npm install -g @googleworkspace/cli

# Agent templates (read-only source for entrypoint to copy into workspace)
COPY --chown=node:node agents/ /opt/openclaw-agents/

# Claude CLI commands (read-only source for entrypoint to copy into ~/.claude)
COPY --chown=node:node claude/ /opt/claude/

# Entrypoint and init scripts
COPY --chown=node:node docker-entrypoint.sh /usr/local/bin/
COPY --chown=node:node init.d/ /usr/local/lib/openclaw-init.d/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && chmod +x /usr/local/lib/openclaw-init.d/*.sh

# Ensure home is owned by node
RUN mkdir -p /home/node/projects \
    && chown -R node:node /home/node

USER node
ENV PATH="/home/node/.local/bin:${PATH}"

# Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash

# Google Workspace agent skills
RUN npx -y skills add https://github.com/googleworkspace/cli -y

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]
