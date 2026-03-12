.PHONY: setup up down restart logs status version shell cli onboard update clean help

OPENCLAW_VERSION := $(shell cat .openclaw-version 2>/dev/null || echo latest)
export OPENCLAW_VERSION

# --- Setup ---

setup:             ## First-time setup: create .env, install agents
	bash setup.sh

# --- Daily operations ---

up:                ## Start all services
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
	@echo "Running:   $$(docker compose exec openclaw-gateway node dist/index.js --version 2>/dev/null || echo 'not running')"
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
	@CURRENT=$$(cat .openclaw-version 2>/dev/null || echo "0.0.0"); \
	LATEST=$$(curl -sf "https://hub.docker.com/v2/repositories/alpine/openclaw/tags/?page_size=50&ordering=last_updated" \
	  | jq -r '[.results[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$$"))] | first'); \
	if [ -z "$$LATEST" ]; then \
	  echo "ERROR: Could not fetch latest version from Docker Hub"; exit 1; \
	fi; \
	echo "Current: $$CURRENT"; \
	echo "Latest:  $$LATEST"; \
	CUR_NUM=$$(echo "$$CURRENT" | awk -F. '{printf "%d%02d%02d", $$1, $$2, $$3}'); \
	LAT_NUM=$$(echo "$$LATEST" | awk -F. '{printf "%d%02d%02d", $$1, $$2, $$3}'); \
	if [ "$$LAT_NUM" -le "$$CUR_NUM" ]; then \
	  echo "Already up to date."; exit 0; \
	fi; \
	echo "Updating to $$LATEST..."; \
	echo "$$LATEST" > .openclaw-version; \
	export OPENCLAW_VERSION=$$LATEST; \
	docker compose down; \
	docker pull alpine/openclaw:$$LATEST; \
	docker compose build --no-cache; \
	docker compose up -d; \
	echo ""; \
	echo "Updated to $$LATEST. Waiting for gateway to start..."; \
	sleep 5; \
	docker compose logs --tail 5 openclaw-gateway

# --- Maintenance ---

clean:             ## Remove old/dangling Docker images
	docker image prune -f
	@echo "Cleaned up unused images"

help:              ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
