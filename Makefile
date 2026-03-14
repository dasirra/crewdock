.PHONY: init up down restart restart-gateway logs logs-all status version shell cli onboard update clean help

OPENCLAW_VERSION := $(shell cat .openclaw-version 2>/dev/null || echo latest)
export OPENCLAW_VERSION

# --- Setup ---

init:              ## Create runtime directories (run once before first 'make up')
	mkdir -p config/openclaw config/claude workspace projects

# --- Daily operations ---

up:                ## Build and start all services
	docker compose up -d

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
	@LATEST=$$(curl -sf "https://hub.docker.com/v2/repositories/alpine/openclaw/tags/?page_size=50&ordering=last_updated" \
	  | jq -r '[.results[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$$"))] | first' 2>/dev/null || echo 'unknown'); \
	echo "Latest:    $$LATEST"

# --- CLI tools ---

shell:             ## Open bash shell in the gateway container
	docker compose exec openclaw-gateway bash

cli:               ## Open interactive CLI
	docker compose exec openclaw-gateway node dist/index.js

onboard:           ## Run onboarding (for auth setup)
	docker compose exec openclaw-gateway node dist/index.js onboard

# --- Updates ---

update:            ## Check for new OpenClaw version, update and rebuild if newer
	@LATEST=$$(curl -sf "https://hub.docker.com/v2/repositories/alpine/openclaw/tags/?page_size=50&ordering=last_updated" \
	  | jq -r '[.results[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$$"))] | first'); \
	if [ -z "$$LATEST" ]; then \
	  echo "ERROR: Could not fetch latest version from Docker Hub"; exit 1; \
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
	echo "Pulling alpine/openclaw:$$LATEST..." && \
	docker pull alpine/openclaw:$$LATEST && \
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
