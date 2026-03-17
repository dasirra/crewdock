.PHONY: setup up up-debug down restart restart-gateway logs logs-all status version shell cli onboard openai-codex update clean help

OPENCLAW_VERSION := $(shell cat .openclaw-version 2>/dev/null || echo latest)
export OPENCLAW_VERSION

# --- Setup ---

setup:             ## First-time setup: check Docker, create dirs, copy example files, build and start
	@command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is not installed."; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon is not running."; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "ERROR: docker compose is not available."; exit 1; }
	@echo "Docker OK."
	@mkdir -p config/openclaw config/claude config/gh config/gws workspace projects
	@echo "Runtime directories created."
	@# Copy example files (skip if target already exists)
	@for pair in \
	  ".env.example:.env" \
	  "docker-compose.override.example.yaml:docker-compose.override.yaml" \
	  "Dockerfile.local.example:Dockerfile.local"; do \
	  src=$${pair%%:*}; dst=$${pair##*:}; \
	  if [ ! -f "$$src" ]; then continue; fi; \
	  if [ -f "$$dst" ]; then \
	    echo "  $$dst already exists, skipping."; \
	  else \
	    cp "$$src" "$$dst"; \
	    echo "  $$dst created from $$src"; \
	  fi; \
	done
	@echo ""
	@echo "Edit .env with your tokens, then run: make up"

# --- Daily operations ---

up:                ## Build and start all services (pulls base image if version changed)
	@IMAGE_ID=$$(docker images -q ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION) 2>/dev/null); \
	if [ -z "$$IMAGE_ID" ]; then \
		echo "Pulling ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION)..."; \
		docker pull ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION); \
	fi
	docker compose up -d --build

up-debug:          ## Build and start in foreground (no daemon, for debugging)
	@IMAGE_ID=$$(docker images -q ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION) 2>/dev/null); \
	if [ -z "$$IMAGE_ID" ]; then \
		echo "Pulling ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION)..."; \
		docker pull ghcr.io/openclaw/openclaw:$(OPENCLAW_VERSION); \
	fi
	docker compose up --build

down:              ## Stop all services
	docker compose down

restart:           ## Restart all services
	docker compose restart

restart-gateway:   ## Restart only the gateway
	docker compose restart openclaw-gateway

logs:              ## Tail gateway logs
	docker compose logs -f --tail 50 openclaw-gateway

logs-all:          ## Tail all service logs
	docker compose logs -f --tail 50

status:            ## Show running containers
	docker compose ps

version:           ## Show pinned, running, and latest versions
	@echo "Pinned:    $(OPENCLAW_VERSION)"
	@echo "Running:   $$(docker compose exec -T openclaw-gateway node dist/index.js --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo 'not running')"
	@LATEST=$$(curl -sf "https://api.github.com/orgs/openclaw/packages/container/openclaw/versions?per_page=1" \
	  | jq -r '.[0].metadata.container.tags[0]' 2>/dev/null || echo 'unknown'); \
	echo "Latest:    $$LATEST"

# --- CLI tools ---

shell:             ## Open bash shell in the gateway container
	docker compose exec openclaw-gateway bash

cli:               ## Open interactive CLI
	docker compose exec openclaw-gateway node dist/index.js

onboard:           ## Run onboarding (for auth setup)
	docker compose exec openclaw-gateway node dist/index.js onboard

openai-codex:      ## Set up OpenAI Codex OAuth and make it the default model
	docker compose exec openclaw-gateway node dist/index.js models auth login --provider openai-codex
	docker compose exec openclaw-gateway node dist/index.js config set agents.defaults.model.primary openai-codex/gpt-5.4
	docker compose exec openclaw-gateway node dist/index.js config set agents.defaults.model.fallbacks '["anthropic/claude-sonnet-4-6"]' --json
	@echo "Default model set to openai-codex/gpt-5.4 (fallback: anthropic/claude-sonnet-4-6)"

# --- Updates ---

update:            ## Check for new OpenClaw version, update and rebuild if newer
	@LATEST=$$(curl -sf "https://api.github.com/orgs/openclaw/packages/container/openclaw/versions?per_page=1" \
	  | jq -r '.[0].metadata.container.tags[0]'); \
	if [ -z "$$LATEST" ] || [ "$$LATEST" = "null" ]; then \
	  echo "ERROR: Could not fetch latest version from GHCR"; exit 1; \
	fi; \
	RUNNING=$$(docker compose exec -T openclaw-gateway node dist/index.js --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo ""); \
	PINNED=$$(cat .openclaw-version 2>/dev/null || echo "none"); \
	if [ -n "$$RUNNING" ]; then \
	  echo "Running: $$RUNNING"; \
	  echo "Pinned:  $$PINNED"; \
	  echo "Latest:  $$LATEST"; \
	  RUN_NUM=$$(echo "$$RUNNING" | awk -F. '{printf "%d%02d%02d", $$1, $$2, $$3}'); \
	  LAT_NUM=$$(echo "$$LATEST" | awk -F. '{printf "%d%02d%02d", $$1, $$2, $$3}'); \
	  if [ "$$LAT_NUM" -le "$$RUN_NUM" ]; then \
	    echo "Already up to date."; exit 0; \
	  fi; \
	else \
	  echo "Gateway not running — cannot verify current version."; \
	  echo "Pinned:  $$PINNED"; \
	  echo "Latest:  $$LATEST"; \
	  echo "Forcing rebuild..."; \
	fi; \
	echo "Updating to $$LATEST..."; \
	echo "$$LATEST" > .openclaw-version; \
	export OPENCLAW_VERSION=$$LATEST; \
	docker compose down && \
	echo "Pulling ghcr.io/openclaw/openclaw:$$LATEST..." && \
	docker pull ghcr.io/openclaw/openclaw:$$LATEST && \
	echo "Building base image..." && \
	docker build --no-cache --build-arg OPENCLAW_VERSION=$$LATEST -t openclaw-openclaw-gateway:latest -f Dockerfile . && \
	echo "Building final image..." && \
	docker compose build --no-cache && \
	docker compose up -d --force-recreate; \
	echo ""; \
	echo "Updated to $$LATEST. Waiting for gateway to start..."; \
	sleep 10; \
	echo "Verifying..."; \
	VERIFY=$$(docker compose exec -T openclaw-gateway node dist/index.js --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "could not verify"); \
	echo "Running: $$VERIFY"; \
	if [ "$$VERIFY" = "$$LATEST" ]; then \
	  echo "Update successful!"; \
	else \
	  echo "WARNING: Expected $$LATEST but got $$VERIFY"; \
	fi

# --- Maintenance ---

clean:             ## Remove old/dangling Docker images
	docker image prune -f
	@echo "Cleaned up unused images"

help:              ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
