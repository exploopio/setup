# =============================================================================
# Rediver Platform - Maintenance & Setup
# =============================================================================
#
# Quick Start (Staging):
#   1. make init-staging         # Create env files
#   2. make staging-up           # Start everything (auto-generates SSL)
#
# Quick Start (Production):
#   1. make init-prod            # Create env files
#   2. make prod-up              # Start production
#
# Options:
#   seed=true                    # Run with test data (e.g., make staging-up seed=true)
#   s=<service>                  # Target specific service (e.g., make staging-logs s=api)
#
# =============================================================================

# Configuration
STAGING_COMPOSE := docker-compose.staging.yml
PROD_COMPOSE := docker-compose.prod.yml

# Check for required tools
EXECUTABLES = docker openssl
K := $(foreach exec,$(EXECUTABLES),\
        $(if $(shell which $(exec)),some string,$(error "No $(exec) in PATH")))

# Environment Files Loading
STAGING_ENV_FILES := --env-file .env.db.staging --env-file .env.api.staging --env-file .env.ui.staging --env-file .env.nginx.staging --env-file .env.versions.staging
PROD_ENV_FILES    := --env-file .env.db.prod --env-file .env.api.prod --env-file .env.ui.prod --env-file .env.nginx.prod --env-file .env.versions.prod

.PHONY: help init-staging init-prod generate-secrets auto-ssl \
        staging-up staging-down staging-logs staging-restart \
        prod-up prod-down prod-logs prod-restart \
        db-shell-staging db-shell-prod redis-shell-staging redis-shell-prod \
        clean prune check-staging-env check-prod-env

help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# =============================================================================
# Initialization & Setup
# =============================================================================

init-staging: ## Initialize staging environment files
	@echo "Creating staging env files..."
	@cp -n environments/.env.db.staging.example .env.db.staging 2>/dev/null || true
	@cp -n environments/.env.api.staging.example .env.api.staging 2>/dev/null || true
	@cp -n environments/.env.ui.staging.example .env.ui.staging 2>/dev/null || true
	@cp -n environments/.env.nginx.staging.example .env.nginx.staging 2>/dev/null || true
	@cp -n environments/.env.versions.staging.example .env.versions.staging 2>/dev/null || true
	@echo "Done. Run 'make generate-secrets' and 'make staging-up'."

init-prod: ## Initialize production environment files
	@echo "Creating production env files..."
	@cp -n environments/.env.db.prod.example .env.db.prod 2>/dev/null || true
	@cp -n environments/.env.api.prod.example .env.api.prod 2>/dev/null || true
	@cp -n environments/.env.ui.prod.example .env.ui.prod 2>/dev/null || true
	@cp -n environments/.env.nginx.prod.example .env.nginx.prod 2>/dev/null || true
	@cp -n environments/.env.versions.prod.example .env.versions.prod 2>/dev/null || true
	@echo "Done. Update <CHANGE_ME> in .env files before starting."

generate-secrets: ## Generate secure random secrets for env files
	@echo "Generating secrets..."
	@# In a real script we would use sed to replace values, but simply outputting for now is safer
	@echo "AUTH_JWT_SECRET: $$(openssl rand -base64 48)"
	@echo "CSRF_SECRET:     $$(openssl rand -hex 32)"
	@echo "DB/REDIS PASS:   $$(openssl rand -hex 24)"

auto-ssl: ## Auto-generate dev SSL certificates if missing
	@if [ ! -f nginx/ssl/cert.pem ]; then \
		echo "Generating self-signed SSL certificates..."; \
		mkdir -p nginx/ssl; \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
			-keyout nginx/ssl/key.pem \
			-out nginx/ssl/cert.pem \
			-subj "/CN=localhost" 2>/dev/null; \
		echo "✓ SSL certificates generated."; \
	fi

check-staging-env: ## Verify staging env files exist
	@missing=""; \
	for f in .env.db.staging .env.api.staging .env.ui.staging .env.nginx.staging .env.versions.staging; do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "❌ Missing env files:$$missing"; \
		echo "   Run 'make init-staging' first."; \
		exit 1; \
	fi; \
	echo "✓ All staging env files present."

check-prod-env: ## Verify production env files exist and have no CHANGE_ME
	@missing=""; \
	for f in .env.db.prod .env.api.prod .env.ui.prod .env.nginx.prod .env.versions.prod; do \
		if [ ! -f "$$f" ]; then missing="$$missing $$f"; fi; \
	done; \
	if [ -n "$$missing" ]; then \
		echo "❌ Missing env files:$$missing"; \
		echo "   Run 'make init-prod' first."; \
		exit 1; \
	fi; \
	echo "✓ All production env files present."; \
	if grep -rq "CHANGE_ME\|<CHANGE_ME" .env.*.prod 2>/dev/null; then \
		echo "⚠️  Warning: Found CHANGE_ME values in production env files!"; \
		echo "   Please update all placeholders before deploying."; \
		grep -l "CHANGE_ME\|<CHANGE_ME" .env.*.prod 2>/dev/null | sed 's/^/   - /'; \
	fi

# =============================================================================
# Staging Environment
# =============================================================================
# Staging now ALWAYS runs with Nginx/SSL enabled for parity with Production.

staging-up: check-staging-env auto-ssl ## Start staging (Default: SSL enabled). Use seed=true to seed DB.
	@echo "Starting Staging Environment..."
	@PROFILES="--profile ssl"; \
	if [ "$(seed)" = "true" ]; then \
		PROFILES="$$PROFILES --profile seed"; \
	fi; \
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) $$PROFILES pull; \
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) $$PROFILES up -d
	@echo "\n✅ Staging is running!"
	@echo "   UI:  https://localhost (or configured NGINX_HOST)"
	@echo "   API: https://api.localhost (or configured API_HOST)"

staging-down: ## Stop staging and remove resources
	@echo "Stopping Staging..."
	@# Down with all profiles to ensure full cleanup
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) --profile ssl --profile seed down

staging-logs: ## View staging logs. Use s=<service> for specific service.
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) logs -f $(s)

staging-restart: ## Restart staging services. Use s=<service> to limit.
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) restart $(s)

staging-status: ## Show staging containers status
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) ps

staging-seed: ## Seed test data into running staging database
	@echo "Seeding test data..."
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) --profile seed up seed
	@echo "✅ Seeding complete!"

# =============================================================================
# Production Environment
# =============================================================================

prod-up: check-prod-env ## Start production environment
	@echo "Starting Production Environment..."
	docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) pull
	docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) up -d

prod-down: ## Stop production environment
	docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) down

prod-logs: ## View production logs. Use s=<service> for specific logs.
	docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) logs -f $(s)

prod-restart: ## Restart production services. Use s=<service> to limit.
	docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) restart $(s)

# =============================================================================
# Admin Bootstrap
# =============================================================================

bootstrap-admin-staging: ## Create initial admin user for staging. Use email=<email> role=<role>
	@if [ -z "$(email)" ]; then \
		echo "Usage: make bootstrap-admin-staging email=admin@example.com [role=super_admin]"; \
		exit 1; \
	fi
	@ROLE=$${role:-super_admin}; \
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) \
		exec api /app/bootstrap-admin -email "$(email)" -role "$$ROLE"

bootstrap-admin-prod: ## Create initial admin user for production. Use email=<email> role=<role>
	@if [ -z "$(email)" ]; then \
		echo "Usage: make bootstrap-admin-prod email=admin@example.com [role=super_admin]"; \
		exit 1; \
	fi
	@ROLE=$${role:-super_admin}; \
	docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) \
		exec api /app/bootstrap-admin -email "$(email)" -role "$$ROLE"

# =============================================================================
# Database & Utilities
# =============================================================================

migrate-staging: ## Run staging database migrations manually
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) up migrate

migrate-prod: ## Run production database migrations manually
	docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) up migrate

db-shell-staging: ## Connect to Staging DB shell
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) exec postgres psql -U rediver -d rediver

redis-shell-staging: ## Connect to Staging Redis shell
	docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) exec redis redis-cli

clean: ## Remove unused Docker resources (prune)
	docker system prune -f

prune: clean

# =============================================================================
# Tenant Management
# =============================================================================

assign-plan-staging: ## Assign plan to tenant (staging). Use tenant=<uuid> plan=<slug>
	@if [ -z "$(tenant)" ]; then \
		echo "Usage: make assign-plan-staging tenant=<uuid> plan=<plan_slug>"; \
		echo ""; \
		echo "Available plans: free, team, business, enterprise"; \
		echo ""; \
		echo "Example:"; \
		echo "  make assign-plan-staging tenant=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa plan=enterprise"; \
		exit 1; \
	fi
	@if [ -z "$(plan)" ]; then \
		echo "Error: plan is required"; \
		echo "Available plans: free, team, business, enterprise"; \
		exit 1; \
	fi
	@echo "Assigning $(plan) plan to tenant $(tenant)..."
	@docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"UPDATE tenants SET plan_id = (SELECT id FROM plans WHERE slug = '$(plan)'), updated_at = NOW() WHERE id = '$(tenant)';"
	@echo ""
	@echo "Verifying assignment..."
	@docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"SELECT t.id, t.name, t.slug, p.name as plan_name, p.slug as plan_slug FROM tenants t JOIN plans p ON t.plan_id = p.id WHERE t.id = '$(tenant)';"

assign-plan-prod: ## Assign plan to tenant (production). Use tenant=<uuid> plan=<slug>
	@if [ -z "$(tenant)" ]; then \
		echo "Usage: make assign-plan-prod tenant=<uuid> plan=<plan_slug>"; \
		echo ""; \
		echo "Available plans: free, team, business, enterprise"; \
		echo ""; \
		echo "Example:"; \
		echo "  make assign-plan-prod tenant=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa plan=enterprise"; \
		exit 1; \
	fi
	@if [ -z "$(plan)" ]; then \
		echo "Error: plan is required"; \
		echo "Available plans: free, team, business, enterprise"; \
		exit 1; \
	fi
	@echo "Assigning $(plan) plan to tenant $(tenant)..."
	@docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"UPDATE tenants SET plan_id = (SELECT id FROM plans WHERE slug = '$(plan)'), updated_at = NOW() WHERE id = '$(tenant)';"
	@echo ""
	@echo "Verifying assignment..."
	@docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"SELECT t.id, t.name, t.slug, p.name as plan_name, p.slug as plan_slug FROM tenants t JOIN plans p ON t.plan_id = p.id WHERE t.id = '$(tenant)';"

list-tenants-staging: ## List all tenants with their plans (staging)
	@docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"SELECT t.id, t.name, t.slug, p.name as plan_name, p.slug as plan_slug FROM tenants t JOIN plans p ON t.plan_id = p.id ORDER BY t.name;"

list-tenants-prod: ## List all tenants with their plans (production)
	@docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"SELECT t.id, t.name, t.slug, p.name as plan_name, p.slug as plan_slug FROM tenants t JOIN plans p ON t.plan_id = p.id ORDER BY t.name;"

list-plans-staging: ## List all available plans (staging)
	@docker compose -f $(STAGING_COMPOSE) $(STAGING_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"SELECT id, name, slug, display_name FROM plans ORDER BY price_monthly;"

list-plans-prod: ## List all available plans (production)
	@docker compose -f $(PROD_COMPOSE) $(PROD_ENV_FILES) exec -T postgres psql -U rediver -d rediver -c \
		"SELECT id, name, slug, display_name FROM plans ORDER BY price_monthly;"
