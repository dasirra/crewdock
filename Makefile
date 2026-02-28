.PHONY: up down restart update rebuild logs status version cli onboard clean

# --- Daily operations ---

up:                ## Start all services
	sudo docker compose up -d

down:              ## Stop all services
	sudo docker compose down

restart:           ## Restart all services
	sudo docker compose restart

restart-gateway:   ## Restart only the gateway
	sudo docker compose restart openclaw-gateway

logs:              ## Tail gateway logs
	sudo docker compose logs -f --tail 50 openclaw-gateway

logs-all:          ## Tail all service logs
	sudo docker compose logs -f --tail 50

status:            ## Show running containers and versions
	sudo docker compose ps
	@echo ""
	@sudo docker compose exec openclaw-gateway node dist/index.js --version 2>/dev/null || echo "Gateway not running"

version:           ## Show running, image, and latest available versions
	@echo "Running:   $$(sudo docker compose exec openclaw-gateway node dist/index.js --version 2>/dev/null || echo 'not running')"
	@echo "Image:     $$(sudo docker run --rm alpine/openclaw:latest node dist/index.js --version 2>/dev/null || echo 'not pulled')"

# --- Updates ---

update:            ## Pull latest image, rebuild, and restart everything
	sudo docker compose down
	sudo docker rmi alpine/openclaw:latest 2>/dev/null || true
	sudo docker pull alpine/openclaw:latest
	sudo DOCKER_BUILDKIT=0 docker compose build --no-cache --pull
	sudo docker compose up -d
	@echo ""
	@echo "Waiting for gateway to start..."
	@sleep 5
	@sudo docker compose logs --tail 5 openclaw-gateway

# --- CLI tools ---

cli:               ## Open interactive CLI
	sudo docker compose run --rm openclaw-cli

onboard:           ## Run onboarding (for auth setup)
	sudo docker compose run --rm openclaw-cli onboard

auth-codex:        ## Authenticate with OpenAI Codex
	sudo docker compose run --rm openclaw-cli onboard --auth-choice openai-codex

auth-anthropic:    ## Authenticate with Anthropic
	sudo docker compose run --rm openclaw-cli models auth login --provider anthropic

# --- Maintenance ---

clean:             ## Remove old/dangling Docker images
	sudo docker image prune -f
	@echo "Cleaned up unused images"

help:              ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
