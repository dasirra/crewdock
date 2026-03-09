.PHONY: setup up down restart logs status version shell cli onboard update clean help

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

version:           ## Show running and image versions
	@echo "Running:   $$(docker compose exec openclaw-gateway node dist/index.js --version 2>/dev/null || echo 'not running')"
	@echo "Image:     $$(docker run --rm alpine/openclaw:latest node dist/index.js --version 2>/dev/null || echo 'not pulled')"

# --- CLI tools ---

shell:             ## Open bash shell in the gateway container
	docker compose exec openclaw-gateway bash

cli:               ## Open interactive CLI
	docker compose run --rm openclaw-cli

onboard:           ## Run onboarding (for auth setup)
	docker compose run --rm openclaw-cli onboard

# --- Updates ---

update:            ## Pull latest image, rebuild, and restart
	docker compose down
	docker rmi alpine/openclaw:latest 2>/dev/null || true
	docker pull alpine/openclaw:latest
	DOCKER_BUILDKIT=0 docker compose build --no-cache --pull
	docker compose up -d
	@echo ""
	@echo "Waiting for gateway to start..."
	@sleep 5
	@docker compose logs --tail 5 openclaw-gateway

# --- Maintenance ---

clean:             ## Remove old/dangling Docker images
	docker image prune -f
	@echo "Cleaned up unused images"

help:              ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
