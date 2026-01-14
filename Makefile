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
# Quick Start (Production with Nginx/SSL):
#   1. make init-prod
#   2. Edit .env files (update ALL <CHANGE_ME> values)
#   3. make init-ssl (setup SSL certificates)
#   4. make prod-up
#
# Quick Start (Production without Nginx):
#   1. make init-prod
#   2. Edit .env files
#   3. make prod-simple-up
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
PROD_SIMPLE_COMPOSE := docker-compose.prod-simple.yml

# Export VERSION for docker-compose
export VERSION

.PHONY: help init-staging init-prod init-ssl init-ssl-letsencrypt ssl-renew \
        staging-up staging-up-seed staging-up-ssl staging-up-ssl-seed staging-seed staging-down staging-logs staging-ps staging-restart \
        prod-up prod-down prod-logs prod-ps prod-restart prod-simple-up prod-simple-down \
        nginx-reload nginx-logs nginx-test \
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
	@echo "Quick Start (Staging with HTTPS):"
	@echo "  1. make init-staging     # Copy example env files"
	@echo "  2. make generate-secrets # Generate secure secrets"
	@echo "  3. Edit .env.*.staging files"
	@echo "  4. make init-ssl         # Generate self-signed certificate"
	@echo "  5. make staging-up-ssl   # Start with nginx/SSL"
	@echo ""
	@echo "Quick Start (Production with Nginx/SSL):"
	@echo "  1. make init-prod        # Copy example env files"
	@echo "  2. make generate-secrets # Generate secure secrets"
	@echo "  3. Edit .env.*.prod files (update ALL <CHANGE_ME>)"
	@echo "  4. make init-ssl-letsencrypt # Show Let's Encrypt instructions"
	@echo "  5. make prod-up          # Pull & start services"
	@echo ""
	@echo "Quick Start (Production without Nginx):"
	@echo "  1. make init-prod        # Copy example env files"
	@echo "  2. Edit .env.*.prod files"
	@echo "  3. make prod-simple-up   # For external proxy (AWS ALB, etc.)"
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
	@cp -n environments/.env.db.staging.example .env.db.staging 2>/dev/null || echo "  .env.db.staging already exists"
	@cp -n environments/.env.api.staging.example .env.api.staging 2>/dev/null || echo "  .env.api.staging already exists"
	@cp -n environments/.env.ui.staging.example .env.ui.staging 2>/dev/null || echo "  .env.ui.staging already exists"
	@cp -n environments/.env.nginx.staging.example .env.nginx.staging 2>/dev/null || echo "  .env.nginx.staging already exists"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run: make generate-secrets"
	@echo "  2. Update secrets in .env.*.staging files"
	@echo "  3. Run: make staging-up"
	@echo "  4. (Optional) For HTTPS: make init-ssl && make staging-up-ssl"

init-prod: ## Copy production env example files
	@echo "Creating production environment files..."
	@cp -n environments/.env.db.prod.example .env.db.prod 2>/dev/null || echo "  .env.db.prod already exists"
	@cp -n environments/.env.api.prod.example .env.api.prod 2>/dev/null || echo "  .env.api.prod already exists"
	@cp -n environments/.env.ui.prod.example .env.ui.prod 2>/dev/null || echo "  .env.ui.prod already exists"
	@cp -n environments/.env.nginx.prod.example .env.nginx.prod 2>/dev/null || echo "  .env.nginx.prod already exists"
	@echo ""
	@echo "IMPORTANT: Update ALL <CHANGE_ME> values before starting!"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run: make generate-secrets"
	@echo "  2. Update ALL values in .env.*.prod files"
	@echo "  3. Update NGINX_HOST in .env.nginx.prod"
	@echo "  4. Run: make init-ssl-letsencrypt (for SSL setup instructions)"
	@echo "  4. Run: make prod-up"
	@echo ""
	@echo "Or for external proxy (AWS ALB, Traefik, etc.):"
	@echo "  3. Run: make prod-simple-up"

init-ssl: ## Generate self-signed SSL certificate (for staging/testing)
	@echo "=== Generating Self-Signed SSL Certificate ==="
	@mkdir -p nginx/ssl
	@if [ -f nginx/ssl/cert.pem ]; then \
		echo "SSL certificate already exists. Remove nginx/ssl/*.pem to regenerate."; \
	else \
		openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
			-keyout nginx/ssl/key.pem \
			-out nginx/ssl/cert.pem \
			-subj "/CN=localhost" 2>/dev/null; \
		echo "✓ Generated nginx/ssl/cert.pem"; \
		echo "✓ Generated nginx/ssl/key.pem"; \
		echo ""; \
		echo "Certificate valid for 365 days."; \
		echo "WARNING: Self-signed certificates will show browser warnings."; \
		echo ""; \
		echo "Now run: make staging-up-ssl"; \
	fi

init-ssl-letsencrypt: ## Instructions for Let's Encrypt SSL (production)
	@echo "=== Let's Encrypt SSL Certificate Setup ==="
	@echo ""
	@echo "1. Install Certbot:"
	@echo "   sudo apt install certbot"
	@echo ""
	@echo "2. Stop any service on port 80, then get certificate:"
	@echo "   sudo certbot certonly --standalone -d your-domain.com"
	@echo ""
	@echo "3. Copy certificates:"
	@echo "   sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/ssl/cert.pem"
	@echo "   sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/ssl/key.pem"
	@echo "   sudo chmod 644 nginx/ssl/cert.pem"
	@echo "   sudo chmod 600 nginx/ssl/key.pem"
	@echo ""
	@echo "4. Update nginx config with your domain:"
	@echo "   sed -i 's/your-domain.com/yourdomain.com/g' nginx/nginx.conf"
	@echo ""
	@echo "5. Start production:"
	@echo "   make prod-up"
	@echo ""
	@echo "See nginx/README.md for detailed instructions."

ssl-renew: ## Reload nginx after certificate renewal
	@echo "Reloading nginx after certificate renewal..."
	@if docker ps --format '{{.Names}}' | grep -q rediver-nginx; then \
		docker exec rediver-nginx nginx -s reload; \
		echo "✓ Nginx reloaded successfully"; \
	else \
		echo "Nginx container is not running"; \
	fi

# =============================================================================
# Staging Commands
# =============================================================================

staging-up: check-staging ## Start staging environment
	@echo "Starting staging environment (version: $(VERSION))..."
	@echo "Pulling images from Docker Hub..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging pull
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging up -d
	@echo ""
	@echo "Services starting... UI: http://localhost:3000"
	@echo "View logs: make staging-logs"

staging-up-seed: check-staging ## Start staging with test data
	@echo "Starting staging environment with test data (version: $(VERSION))..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging pull
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging --profile seed up -d
	@echo ""
	@echo "Test credentials: admin@rediver.io / Password123"
	@echo "UI: http://localhost:3000"

staging-up-ssl: check-staging check-nginx-staging check-ssl ## Start staging with Nginx/SSL
	@echo "Starting staging environment with Nginx/SSL (version: $(VERSION))..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging pull
	@echo "Starting all services with SSL profile..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging --profile ssl up -d
	@echo ""
	@echo "Services starting... UI: https://localhost"
	@echo "View logs: make staging-logs"

staging-up-ssl-seed: check-staging check-nginx-staging check-ssl ## Start staging with Nginx/SSL and test data
	@echo "Starting staging environment with Nginx/SSL and test data (version: $(VERSION))..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging pull
	@echo "Starting all services with SSL and seed profiles..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging --profile ssl --profile seed up -d
	@echo ""
	@echo "Test credentials: admin@rediver.io / Password123"
	@echo "UI: https://localhost"

staging-seed: check-staging ## Seed test data to running staging database
	@echo "Seeding test data..."
	@if docker ps --format '{{.Names}}' | grep -q rediver-postgres; then \
		docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging run --rm seed; \
		echo ""; \
		echo "✓ Seeding complete!"; \
		echo "Test credentials: admin@rediver.io / Password123"; \
	else \
		echo "Error: PostgreSQL is not running. Start services first with 'make staging-up'"; \
		exit 1; \
	fi

staging-down: ## Stop staging services
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging down

staging-logs: ## View staging logs (follow)
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging logs -f

staging-logs-api: ## View staging API logs
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging logs -f api

staging-logs-ui: ## View staging UI logs
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging logs -f ui

staging-ps: ## Show staging containers
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging ps

staging-restart: ## Restart staging services
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging restart

staging-restart-api: ## Restart staging API only
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging restart api

staging-restart-ui: ## Restart staging UI only
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging restart ui

staging-pull: check-staging ## Pull latest staging images
	@echo "Pulling staging images (version: $(VERSION))..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging pull

staging-upgrade: check-staging ## Upgrade to latest version
	@echo "Upgrading staging to version: $(VERSION)..."
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging pull
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging up -d --force-recreate

staging-clean: ## Stop and remove staging volumes
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging down -v
	@echo "Cleaned up. Run 'make staging-up' to start fresh."

# =============================================================================
# Production Commands
# =============================================================================

prod-up: check-prod check-nginx-prod check-ssl ## Start production with Nginx/SSL
	@echo "Starting production environment with Nginx/SSL (version: $(VERSION))..."
	@echo "Pulling images from Docker Hub..."
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod pull
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod up -d
	@echo ""
	@echo "Services starting... UI: https://your-domain.com"
	@echo "View logs: make prod-logs"

prod-simple-up: check-prod ## Start production without Nginx (external proxy)
	@echo "Starting production environment without Nginx (version: $(VERSION))..."
	@echo "Use this with external reverse proxy (AWS ALB, Traefik, etc.)"
	docker compose -f $(PROD_SIMPLE_COMPOSE) --env-file .env.db.prod pull
	docker compose -f $(PROD_SIMPLE_COMPOSE) --env-file .env.db.prod up -d
	@echo ""
	@echo "Services starting... UI: http://localhost:3000"
	@echo "Configure your external proxy to forward to port 3000"

prod-simple-down: ## Stop production (simple) services
	docker compose -f $(PROD_SIMPLE_COMPOSE) --env-file .env.db.prod down

prod-down: ## Stop production services
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod down

prod-logs: ## View production logs (follow)
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod logs -f

prod-logs-api: ## View production API logs
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod logs -f api

prod-logs-ui: ## View production UI logs
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod logs -f ui

prod-ps: ## Show production containers
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod ps

prod-restart: ## Restart production services
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod restart

prod-restart-api: ## Restart production API only
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod restart api

prod-restart-ui: ## Restart production UI only
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod restart ui

prod-pull: check-prod ## Pull latest production images
	@echo "Pulling production images (version: $(VERSION))..."
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod pull

prod-upgrade: check-prod check-nginx-prod check-ssl ## Upgrade to latest version
	@echo "Upgrading production to version: $(VERSION)..."
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod pull
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod up -d --force-recreate

prod-clean: ## Stop and remove production volumes (DANGER!)
	@echo "WARNING: This will delete all production data!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod down -v

# =============================================================================
# Database Commands
# =============================================================================

db-shell-staging: ## Open staging PostgreSQL shell
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging exec postgres psql -U rediver -d rediver

db-shell-prod: ## Open production PostgreSQL shell
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod exec postgres psql -U rediver -d rediver

db-migrate-staging: ## Run staging migrations
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging up migrate

db-migrate-prod: ## Run production migrations
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod up migrate

db-seed-staging: ## Seed staging test data
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging exec -T postgres psql -U rediver -d rediver < rediver-api/migrations/seed/seed_test.sql
	@echo "Seeding complete! Test login: admin@rediver.io / Password123"

redis-shell-staging: ## Open staging Redis CLI
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging exec redis redis-cli

redis-shell-prod: ## Open production Redis CLI
	@echo "Note: Production Redis requires password"
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod exec redis redis-cli

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

check-ssl:
	@if [ ! -f nginx/ssl/cert.pem ] || [ ! -f nginx/ssl/key.pem ]; then \
		echo "Warning: SSL certificates not found in nginx/ssl/"; \
		echo "Run: make init-ssl to generate self-signed certificate"; \
		echo ""; \
	fi

check-nginx-staging:
	@if [ ! -f .env.nginx.staging ]; then \
		echo "Warning: .env.nginx.staging not found!"; \
		echo "Creating from template..."; \
		cp environments/.env.nginx.staging.example .env.nginx.staging; \
		echo "Created .env.nginx.staging with NGINX_HOST=localhost"; \
		echo ""; \
	fi

check-nginx-prod:
	@if [ ! -f .env.nginx.prod ]; then \
		echo "Error: .env.nginx.prod not found!"; \
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
	@docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Not running"
	@echo ""
	@echo "UI: http://localhost:3000"

status-prod: ## Show production status
	@echo "=== Production Environment ==="
	@docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Not running"

prune: ## Remove unused Docker resources
	docker system prune -f
	docker volume prune -f

# =============================================================================
# Nginx Commands
# =============================================================================

nginx-test-staging: ## Test staging nginx configuration
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging --profile ssl exec nginx nginx -t

nginx-test-prod: ## Test production nginx configuration
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod exec nginx nginx -t

nginx-reload-staging: ## Reload staging nginx configuration
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging --profile ssl exec nginx nginx -s reload

nginx-reload-prod: ## Reload production nginx configuration
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod exec nginx nginx -s reload

nginx-logs-staging: ## View staging nginx logs
	docker compose -f $(STAGING_COMPOSE) --env-file .env.db.staging --profile ssl logs -f nginx

nginx-logs-prod: ## View production nginx logs
	docker compose -f $(PROD_COMPOSE) --env-file .env.db.prod logs -f nginx
