# =============================================================================
# Rediver Platform - Root Makefile
# =============================================================================
# Manage staging and production environments
# Images are pulled from Docker Hub: rediverio/rediver-api, rediverio/rediver-ui
#
# Quick Start (Staging):
#   1. make init-staging
#   2. Edit .env files (update secrets)
#   3. make staging-up
#
# Quick Start (Production):
#   1. make init-prod
#   2. Edit .env files (update ALL <CHANGE_ME> values)
#   3. make prod-up
#
# Use specific version:
#   VERSION=v0.2.0 make staging-up
#   VERSION=v0.2.0 make prod-up
# =============================================================================

# Default version (can be overridden: VERSION=v0.2.0 make staging-up)
VERSION ?= v0.1.0

# Compose files
STAGING_COMPOSE := docker-compose.staging.yml
PROD_COMPOSE := docker-compose.prod.yml

# Export VERSION for docker-compose
export VERSION

.PHONY: help init-staging init-prod \
        staging-up staging-up-seed staging-down staging-logs staging-ps staging-restart \
        prod-up prod-down prod-logs prod-ps prod-restart \
        staging-build staging-rebuild prod-build prod-rebuild \
        db-shell db-seed redis-shell generate-secrets status

# =============================================================================
# Help
# =============================================================================

help: ## Show this help
	@echo "Rediver Platform - Docker Compose Management"
	@echo "Images: rediverio/rediver-api, rediverio/rediver-ui (Docker Hub)"
	@echo "Current version: $(VERSION)"
	@echo ""
	@echo "Quick Start (Staging):"
	@echo "  1. make init-staging     # Copy example env files"
	@echo "  2. make generate-secrets # Generate secure secrets"
	@echo "  3. Edit .env.*.staging files"
	@echo "  4. make staging-up       # Pull & start services"
	@echo ""
	@echo "Quick Start (Production):"
	@echo "  1. make init-prod        # Copy example env files"
	@echo "  2. make generate-secrets # Generate secure secrets"
	@echo "  3. Edit .env.*.prod files (update ALL <CHANGE_ME>)"
	@echo "  4. make prod-up          # Pull & start services"
	@echo ""
	@echo "Use specific version:"
	@echo "  VERSION=v0.2.0 make staging-up"
	@echo "  VERSION=v0.2.0 make prod-upgrade"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# Initialization
# =============================================================================

init-staging: ## Copy staging env example files
	@echo "Creating staging environment files..."
	@cp -n .env.db.staging.example .env.db.staging 2>/dev/null || echo "  .env.db.staging already exists"
	@cp -n .env.api.staging.example .env.api.staging 2>/dev/null || echo "  .env.api.staging already exists"
	@cp -n .env.ui.staging.example .env.ui.staging 2>/dev/null || echo "  .env.ui.staging already exists"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run: make generate-secrets"
	@echo "  2. Update secrets in .env.*.staging files"
	@echo "  3. Run: make staging-up"

init-prod: ## Copy production env example files
	@echo "Creating production environment files..."
	@cp -n .env.db.prod.example .env.db.prod 2>/dev/null || echo "  .env.db.prod already exists"
	@cp -n .env.api.prod.example .env.api.prod 2>/dev/null || echo "  .env.api.prod already exists"
	@cp -n .env.ui.prod.example .env.ui.prod 2>/dev/null || echo "  .env.ui.prod already exists"
	@echo ""
	@echo "IMPORTANT: Update ALL <CHANGE_ME> values before starting!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run: make generate-secrets"
	@echo "  2. Update ALL values in .env.*.prod files"
	@echo "  3. Run: make prod-up"

# =============================================================================
# Staging Commands
# =============================================================================

staging-up: check-staging ## Start staging environment
	@echo "Starting staging environment (version: $(VERSION))..."
	@echo "Pulling images from Docker Hub..."
	docker compose -f $(STAGING_COMPOSE) pull
	docker compose -f $(STAGING_COMPOSE) up -d
	@echo ""
	@echo "Services starting... UI: http://localhost:3000"
	@echo "View logs: make staging-logs"

staging-up-seed: check-staging ## Start staging with test data
	@echo "Starting staging environment with test data (version: $(VERSION))..."
	docker compose -f $(STAGING_COMPOSE) pull
	docker compose -f $(STAGING_COMPOSE) --profile seed up -d
	@echo ""
	@echo "Test credentials: admin@rediver.io / Password123"
	@echo "UI: http://localhost:3000"

staging-down: ## Stop staging services
	docker compose -f $(STAGING_COMPOSE) down

staging-logs: ## View staging logs (follow)
	docker compose -f $(STAGING_COMPOSE) logs -f

staging-logs-api: ## View staging API logs
	docker compose -f $(STAGING_COMPOSE) logs -f api

staging-logs-ui: ## View staging UI logs
	docker compose -f $(STAGING_COMPOSE) logs -f ui

staging-ps: ## Show staging containers
	docker compose -f $(STAGING_COMPOSE) ps

staging-restart: ## Restart staging services
	docker compose -f $(STAGING_COMPOSE) restart

staging-restart-api: ## Restart staging API only
	docker compose -f $(STAGING_COMPOSE) restart api

staging-restart-ui: ## Restart staging UI only
	docker compose -f $(STAGING_COMPOSE) restart ui

staging-pull: ## Pull latest staging images
	@echo "Pulling staging images (version: $(VERSION))..."
	docker compose -f $(STAGING_COMPOSE) pull

staging-upgrade: check-staging ## Upgrade to latest version
	@echo "Upgrading staging to version: $(VERSION)..."
	docker compose -f $(STAGING_COMPOSE) pull
	docker compose -f $(STAGING_COMPOSE) up -d --force-recreate

staging-clean: ## Stop and remove staging volumes
	docker compose -f $(STAGING_COMPOSE) down -v
	@echo "Cleaned up. Run 'make staging-up' to start fresh."

# =============================================================================
# Production Commands
# =============================================================================

prod-up: check-prod ## Start production environment
	@echo "Starting production environment (version: $(VERSION))..."
	@echo "Pulling images from Docker Hub..."
	docker compose -f $(PROD_COMPOSE) pull
	docker compose -f $(PROD_COMPOSE) up -d
	@echo ""
	@echo "Services starting..."
	@echo "View logs: make prod-logs"

prod-down: ## Stop production services
	docker compose -f $(PROD_COMPOSE) down

prod-logs: ## View production logs (follow)
	docker compose -f $(PROD_COMPOSE) logs -f

prod-logs-api: ## View production API logs
	docker compose -f $(PROD_COMPOSE) logs -f api

prod-logs-ui: ## View production UI logs
	docker compose -f $(PROD_COMPOSE) logs -f ui

prod-ps: ## Show production containers
	docker compose -f $(PROD_COMPOSE) ps

prod-restart: ## Restart production services
	docker compose -f $(PROD_COMPOSE) restart

prod-restart-api: ## Restart production API only
	docker compose -f $(PROD_COMPOSE) restart api

prod-restart-ui: ## Restart production UI only
	docker compose -f $(PROD_COMPOSE) restart ui

prod-pull: ## Pull latest production images
	@echo "Pulling production images (version: $(VERSION))..."
	docker compose -f $(PROD_COMPOSE) pull

prod-upgrade: check-prod ## Upgrade to latest version
	@echo "Upgrading production to version: $(VERSION)..."
	docker compose -f $(PROD_COMPOSE) pull
	docker compose -f $(PROD_COMPOSE) up -d --force-recreate

prod-clean: ## Stop and remove production volumes (DANGER!)
	@echo "WARNING: This will delete all production data!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	docker compose -f $(PROD_COMPOSE) down -v

# =============================================================================
# Database Commands
# =============================================================================

db-shell-staging: ## Open staging PostgreSQL shell
	docker compose -f $(STAGING_COMPOSE) exec postgres psql -U rediver -d rediver

db-shell-prod: ## Open production PostgreSQL shell
	docker compose -f $(PROD_COMPOSE) exec postgres psql -U rediver -d rediver

db-migrate-staging: ## Run staging migrations
	docker compose -f $(STAGING_COMPOSE) up migrate

db-migrate-prod: ## Run production migrations
	docker compose -f $(PROD_COMPOSE) up migrate

db-seed-staging: ## Seed staging test data
	docker compose -f $(STAGING_COMPOSE) exec -T postgres psql -U rediver -d rediver < rediver-api/migrations/seed/seed_test.sql
	@echo "Seeding complete! Test login: admin@rediver.io / Password123"

redis-shell-staging: ## Open staging Redis CLI
	docker compose -f $(STAGING_COMPOSE) exec redis redis-cli

redis-shell-prod: ## Open production Redis CLI
	@echo "Note: Production Redis requires password"
	docker compose -f $(PROD_COMPOSE) exec redis redis-cli

# =============================================================================
# Utility Commands
# =============================================================================

check-staging:
	@if [ ! -f .env.db.staging ] || [ ! -f .env.api.staging ] || [ ! -f .env.ui.staging ]; then \
		echo "Error: Staging env files not found!"; \
		echo "Run: make init-staging"; \
		exit 1; \
	fi

check-prod:
	@if [ ! -f .env.db.prod ] || [ ! -f .env.api.prod ] || [ ! -f .env.ui.prod ]; then \
		echo "Error: Production env files not found!"; \
		echo "Run: make init-prod"; \
		exit 1; \
	fi

generate-secrets: ## Generate secure secrets
	@echo "=== Generated Secrets ==="
	@echo ""
	@echo "AUTH_JWT_SECRET (for .env.api.*):"
	@openssl rand -base64 48
	@echo ""
	@echo "CSRF_SECRET (for .env.ui.*):"
	@openssl rand -hex 32
	@echo ""
	@echo "DB_PASSWORD (for .env.db.*):"
	@openssl rand -base64 24
	@echo ""
	@echo "REDIS_PASSWORD (for .env.db.prod):"
	@openssl rand -base64 24

status-staging: ## Show staging status
	@echo "=== Staging Environment ==="
	@docker compose -f $(STAGING_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "UI: http://localhost:3000"

status-prod: ## Show production status
	@echo "=== Production Environment ==="
	@docker compose -f $(PROD_COMPOSE) ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

prune: ## Remove unused Docker resources
	docker system prune -f
	docker volume prune -f
