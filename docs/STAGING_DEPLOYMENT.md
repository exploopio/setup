# Staging Deployment Guide

**Last Updated:** 2026-01-14

Comprehensive guide for deploying Rediver Platform to staging environment.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step-by-Step Deployment](#step-by-step-deployment)
- [Configuration](#configuration)
- [Seeding Data](#seeding-data)
- [HTTPS/SSL Mode](#httpsssl-mode)
- [Debug Mode](#debug-mode)
- [Management Commands](#management-commands)
- [CI/CD - Building Docker Images](#cicd---building-docker-images)
- [Troubleshooting](#troubleshooting)
- [Remote Server Deployment](#remote-server-deployment)

---

## Prerequisites

### Local Machine (Development)

```bash
# Required
- Docker >= 24.0
- Docker Compose >= 2.20
- Make (optional, for convenience commands)
- Git

# Check versions
docker --version
docker compose version
```

### Remote Server (Staging)

```bash
# Minimum requirements
- Ubuntu 22.04 LTS (or equivalent)
- 4 CPU cores
- 8GB RAM
- 50GB SSD
- Docker & Docker Compose installed
- Port 3000 (UI) - only port exposed externally
```

---

## Quick Start

### 5-Minute Deployment

```bash
# 1. Clone repository
git clone <your-repo-url>
cd setup

# 2. Create environment files from templates
cp environments/.env.db.staging.example .env.db.staging
cp environments/.env.api.staging.example .env.api.staging
cp environments/.env.ui.staging.example .env.ui.staging

# 3. Generate secure secrets
make generate-secrets
# Copy the generated values to env files

# 4. Start all services with test data
make staging-up-seed

# 5. Access application
open http://localhost:3000

# Login credentials:
# Email: admin@rediver.io
# Password: Password123
```

---

## Step-by-Step Deployment

### Step 1: Clone Repository

```bash
# Clone the project
git clone <your-repo-url>
cd setup

# Verify structure
ls -la
# Should see: docker-compose.staging.yml, Makefile, environments/ folder
```

### Step 2: Create Environment Files

```bash
# Copy DB configuration (credentials)
cp environments/.env.db.staging.example .env.db.staging

# Copy API configuration
cp environments/.env.api.staging.example .env.api.staging

# Copy UI configuration
cp environments/.env.ui.staging.example .env.ui.staging

# Generate secure secrets
make generate-secrets
```

Output example:
```
JWT Secret (copy to AUTH_JWT_SECRET in .env.api.staging):
abc123def456ghi789...

CSRF Secret (copy to CSRF_SECRET in .env.ui.staging):
xyz789abc123...

DB Password (copy to DB_PASSWORD in .env.db.staging):
secure_password_here...
```

### Step 3: Configure .env.db.staging

Edit `.env.db.staging`:

```bash
nano .env.db.staging
```

**Critical values to update:**

```env
# Database (REQUIRED)
DB_PASSWORD=<generated_password>

# Redis (optional for staging)
REDIS_PASSWORD=
```

### Step 4: Configure .env.api.staging

Edit `.env.api.staging`:

```bash
nano .env.api.staging
```

**Critical values to update:**

```env
# Authentication (REQUIRED - min 64 chars)
AUTH_JWT_SECRET=<generated_jwt_secret>

# CORS (update for your server)
CORS_ALLOWED_ORIGINS=http://localhost:3000
```

### Step 5: Configure .env.ui.staging

Edit `.env.ui.staging`:

```bash
nano .env.ui.staging
```

**Critical values to update:**

```env
# Security (REQUIRED - min 32 chars)
CSRF_SECRET=<generated_csrf_secret>

# URLs (update for your server)
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

### Step 6: Start Services

```bash
# Option 1: Start without test data
make staging-up

# Option 2: Start with test data (RECOMMENDED for staging)
make staging-up-seed
```

### Step 7: Verify Deployment

```bash
# Check running services
make staging-ps

# View logs
make staging-logs

# Check health
curl http://localhost:3000/api/health
```

---

## Configuration

### Environment Files Structure

| File | Description |
|------|-------------|
| `.env.db.staging` | Database credentials (DB_PASSWORD, REDIS_PASSWORD) |
| `.env.api.staging` | API configuration (auth, CORS, app settings) |
| `.env.ui.staging` | UI configuration (URLs, cookies, security) |
| `.env.nginx.staging` | Nginx configuration (NGINX_HOST) - only for SSL mode |

### Database Configuration (.env.db.staging)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_USER` | Yes | rediver | Database username |
| `DB_PASSWORD` | Yes | - | Database password |
| `DB_NAME` | Yes | rediver | Database name |
| `REDIS_PASSWORD` | No | - | Redis password (optional for staging) |

### API Configuration (.env.api.staging)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_HOST` | Yes | postgres | Database host (Docker service name) |
| `DB_PORT` | Yes | 5432 | Database port |
| `REDIS_HOST` | Yes | redis | Redis host (Docker service name) |
| `AUTH_JWT_SECRET` | Yes | - | JWT signing secret (min 64 chars) |
| `AUTH_PROVIDER` | No | local | Auth mode: local, oidc |
| `AUTH_ALLOW_REGISTRATION` | No | true | Allow user registration |
| `CORS_ALLOWED_ORIGINS` | Yes | http://localhost:3000 | Allowed CORS origins |
| `LOG_LEVEL` | No | info | Log level: debug, info, warn, error |

### UI Configuration (.env.ui.staging)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NEXT_PUBLIC_APP_URL` | Yes | http://localhost:3000 | Public app URL |
| `NEXT_PUBLIC_AUTH_PROVIDER` | No | local | Auth provider |
| `BACKEND_API_URL` | Yes | http://api:8080 | Internal API URL |
| `CSRF_SECRET` | Yes | - | CSRF token secret (min 32 chars) |
| `UI_PORT` | No | 3000 | UI external port |

### Docker Images

Staging uses images with `-staging` suffix:

```yaml
api:
  image: rediverio/api:${VERSION:-v0.1.0}-staging

ui:
  image: rediverio/ui:${VERSION:-v0.1.0}-staging
```

### Port Configuration

| Service | Internal Port | External Port | Notes |
|---------|---------------|---------------|-------|
| UI (Next.js) | 3000 | 3000 | Configurable via `UI_PORT` |
| API (Go) | 8080 | Not exposed | Internal only |
| PostgreSQL | 5432 | Not exposed | Use debug profile to expose |
| Redis | 6379 | Not exposed | Use debug profile to expose |

### Architecture

```
                    Internet/Browser
                          │
                          ▼
                 ┌─────────────────┐
                 │   UI (Next.js)  │ :3000 (public)
                 │   BFF Proxy     │
                 └────────┬────────┘
                          │
            Docker Network (internal)
                          │
                          ▼
                 ┌─────────────────┐
                 │   API (Go)      │ :8080 (internal)
                 └────────┬────────┘
                          │
           ┌──────────────┼──────────────┐
           ▼              ▼              ▼
    ┌───────────┐  ┌───────────┐  ┌───────────┐
    │ PostgreSQL│  │   Redis   │  │  Migrate  │
    │ (internal)│  │ (internal)│  │  (one-off)│
    └───────────┘  └───────────┘  └───────────┘
```

---

## Seeding Data

### Available Seed Options

| Seed File | Description | Command |
|-----------|-------------|---------|
| `seed_required.sql` | Required system data | Auto on startup |
| `seed_test.sql` | Test users & sample data | `--profile seed` |

### Seed Test Data

```bash
# During startup
make staging-up-seed

# Or seed to running database
make staging-seed

# Or manually via docker compose
make db-seed
```

### Test Credentials

| Role | Email | Password |
|------|-------|----------|
| Admin | admin@rediver.io | Password123 |
| User | nguyen.an@techviet.vn | Password123 |

---

## HTTPS/SSL Mode

For staging environments that require HTTPS (e.g., testing OAuth, secure cookies), you can enable the built-in Nginx reverse proxy with SSL.

### Option 1: Quick Start with Self-Signed Certificate

```bash
# 1. Generate self-signed certificate (for testing only)
make init-ssl

# 2. Start staging with SSL
make staging-up-ssl

# Or start with SSL + test data
make staging-up-ssl-seed

# 3. Access via HTTPS
open https://localhost
# Note: Browser will show certificate warning (expected for self-signed)
```

### Option 2: With Let's Encrypt Certificate

```bash
# Show setup instructions
make init-ssl-letsencrypt

# Or manually:

# 1. Obtain certificate (run on server with domain pointing to it)
sudo certbot certonly --standalone -d staging.yourdomain.com

# 2. Copy certificates
sudo cp /etc/letsencrypt/live/staging.yourdomain.com/fullchain.pem nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/staging.yourdomain.com/privkey.pem nginx/ssl/key.pem

# 3. Configure nginx hostname
cp environments/.env.nginx.staging.example .env.nginx.staging
# Edit .env.nginx.staging and set:
# NGINX_HOST=staging.yourdomain.com

# 4. Start staging with SSL
make staging-up-ssl

# 5. Update environment for HTTPS
# .env.api.staging
CORS_ALLOWED_ORIGINS=https://staging.yourdomain.com

# .env.ui.staging
NEXT_PUBLIC_APP_URL=https://staging.yourdomain.com
SECURE_COOKIES=true

# 6. Restart to apply changes
make staging-restart
```

### SSL Architecture

```
                    Internet/Browser
                          │
                          ▼
                 ┌─────────────────┐
                 │   Nginx Proxy   │ :80, :443 (public)
                 │   SSL/TLS       │
                 └────────┬────────┘
                          │
            Docker Network (internal)
                          │
                          ▼
                 ┌─────────────────┐
                 │   UI (Next.js)  │ :3000 (internal)
                 │   BFF Proxy     │
                 └────────┬────────┘
                          │
                          ▼
                 ┌─────────────────┐
                 │   API (Go)      │ :8080 (internal)
                 └────────┬────────┘
                          │
           ┌──────────────┴──────────────┐
           ▼                             ▼
    ┌───────────┐                 ┌───────────┐
    │ PostgreSQL│                 │   Redis   │
    └───────────┘                 └───────────┘
```

### SSL Port Configuration

| Service | Internal Port | External Port | Notes |
|---------|---------------|---------------|-------|
| Nginx | 80, 443 | 80, 443 | Only with `--profile ssl` |
| UI (Next.js) | 3000 | Not exposed | Via nginx when SSL enabled |
| API (Go) | 8080 | Not exposed | Internal only |

### Nginx Management Commands

```bash
# Test nginx configuration
make nginx-test-staging

# Reload nginx (after config changes)
make nginx-reload-staging

# View nginx logs
make nginx-logs-staging
```

### Stop SSL Mode

```bash
# IMPORTANT: Use staging-down-ssl to properly remove nginx container
make staging-down-ssl

# Start without SSL (direct UI access)
make staging-up
```

**Note:** Using `make staging-down` instead of `make staging-down-ssl` may cause "network not found" errors on next SSL startup. See Troubleshooting section for details.

---

## Debug Mode

By default, database and Redis ports are NOT exposed externally for security. Use debug mode when you need direct access.

### Start with Debug Profile

```bash
# Start with debug profile (exposes DB/Redis ports)
docker compose -f docker-compose.staging.yml --profile debug up -d

# Or combine with seed profile
docker compose -f docker-compose.staging.yml --profile debug --profile seed up -d
```

### Access Database

```bash
# Connect via psql
psql -h localhost -p 5432 -U rediver -d rediver

# Or use any database client (DBeaver, pgAdmin, etc.)
# Host: localhost
# Port: 5432
# Database: rediver
# Username: rediver
# Password: (from .env.db.staging)
```

### Access Redis

```bash
# Connect via redis-cli
redis-cli -h localhost -p 6379

# If password is set
redis-cli -h localhost -p 6379 -a <password>
```

### Stop Debug Mode

```bash
# Stop all services
make staging-down

# Start without debug profile
make staging-up
```

---

## Management Commands

### Service Management

```bash
# Start
make staging-up              # Without test data (HTTP)
make staging-up-seed         # With test data (HTTP)
make staging-up-ssl          # With Nginx/SSL (HTTPS)
make staging-up-ssl-seed     # With Nginx/SSL + test data (HTTPS)

# Seed data to running database
make staging-seed

# Stop (use the correct one for your mode)
make staging-down       # For HTTP mode
make staging-down-ssl   # For SSL mode (IMPORTANT: prevents network errors)

# Restart
make staging-restart
make staging-restart-api # Restart API only
make staging-restart-ui  # Restart UI only

# Status
make staging-ps
make status-staging

# Pull latest images
make staging-pull

# Upgrade to new version
VERSION=v0.2.0 make staging-upgrade
```

### Logs

```bash
# All logs
make staging-logs

# Service-specific logs
make staging-logs-api    # API logs only
make staging-logs-ui     # UI logs only

# Nginx logs (when using SSL profile)
make nginx-logs-staging

# Docker compose directly
docker compose -f docker-compose.staging.yml --env-file .env.db.staging logs -f api
docker compose -f docker-compose.staging.yml --env-file .env.db.staging logs -f ui --tail=100
```

### Database

```bash
# Open psql shell
make db-shell-staging

# Run migrations
make db-migrate-staging

# Seed test data
make db-seed-staging

# Redis CLI
make redis-shell-staging
```

### Cleanup

```bash
# Stop and remove containers + volumes (resets database!)
make staging-clean

# Prune unused Docker resources
make prune
```

---

## CI/CD - Building Docker Images

Docker images are built and published using GitHub Actions.

### Building Staging Images

**Option 1: Push a tag (recommended)**

```bash
# Make sure you're on develop branch with latest code
git checkout develop
git pull origin develop

# Create and push staging tag
git tag v0.1.1-staging
git push origin v0.1.1-staging

# GitHub Actions will automatically:
# - Build for linux/amd64 and linux/arm64
# - Push to Docker Hub as rediverio/ui:v0.1.1-staging
```

**Option 2: Manual trigger**

1. Go to GitHub repository → **Actions** tab
2. Select **Docker Publish** workflow
3. Click **Run workflow**
4. Enter:
   - Version: `v0.1.1`
   - Environment: `staging`
5. Click **Run workflow**

### Deploying New Version

After image is built:

```bash
# Update version in .env files
# .env.ui.staging
VERSION=v0.1.1-staging

# .env.api.staging
VERSION=v0.1.1-staging

# Pull and restart
make staging-pull
make staging-restart
```

Or with VERSION variable:

```bash
VERSION=v0.1.1-staging make staging-pull
VERSION=v0.1.1-staging make staging-restart
```

### Setting Up CI/CD

1. **Add GitHub Secrets** (one-time setup):
   - Go to repo **Settings → Secrets and variables → Actions**
   - Add `DOCKERHUB_USERNAME`: Your Docker Hub username
   - Add `DOCKERHUB_TOKEN`: Docker Hub access token

2. **Get Docker Hub Token**:
   - Go to https://hub.docker.com/settings/security
   - Click **New Access Token**
   - Name: `github-actions`
   - Copy token and add to GitHub secrets

See [CICD.md](CICD.md) for complete documentation.

---

## Troubleshooting

### Common Issues

#### 1. "Environment file not found"

```bash
# Solution: Create environment files
cp environments/.env.db.staging.example .env.db.staging
cp environments/.env.api.staging.example .env.api.staging
cp environments/.env.ui.staging.example .env.ui.staging
# Then update secrets
```

#### 2. "Database connection refused"

```bash
# Check PostgreSQL is running
docker compose -f docker-compose.staging.yml ps postgres

# Check logs
docker compose -f docker-compose.staging.yml logs postgres

# Verify credentials in .env.db.staging match
```

#### 3. "Migration failed"

```bash
# Check migration logs
docker compose -f docker-compose.staging.yml logs migrate

# Reset and try again
make staging-clean
make staging-up-seed
```

#### 4. "UI shows blank page / API errors"

```bash
# Check via UI proxy
curl http://localhost:3000/api/health

# Check API logs
docker compose -f docker-compose.staging.yml logs api
```

#### 5. "Port already in use"

```bash
# Find what's using the port
lsof -i :3000

# Change port in env files
# .env.ui.staging
UI_PORT=3001
```

#### 6. "Cannot connect to database externally"

```bash
# Database is NOT exposed by default
# Use debug profile to expose:
docker compose -f docker-compose.staging.yml --env-file .env.db.staging --profile debug up -d
```

#### 7. "Network not found" error

```bash
# Docker network state can get corrupted. Clean up and restart:
make staging-down
docker network prune -f
make staging-up-seed
```

#### 8. "Network not found" error when starting nginx/SSL

This error occurs when Docker caches a stale network ID for the nginx container:

```
Error response from daemon: failed to set up container networking: network xxx not found
```

**Solution:** You must stop services with the same profile that was used to start nginx:

```bash
# IMPORTANT: Use --profile ssl to properly remove nginx container
docker compose -f docker-compose.staging.yml --env-file .env.db.staging --profile ssl down

# Remove nginx container if it still exists
docker rm -f nginx 2>/dev/null || true

# Clean up Docker networks
docker network prune -f

# Start again
make staging-up-ssl
```

**Why this happens:**
- When nginx is started with `--profile ssl`, it gets associated with a specific network ID
- If services are stopped without `--profile ssl`, the nginx container is not properly removed
- Docker caches the old network ID, causing "network not found" error on next start

**Prevention:** Use the correct stop command for your mode:
```bash
# If you started with HTTP mode (make staging-up):
make staging-down

# If you started with SSL mode (make staging-up-ssl):
make staging-down-ssl
```

### Debug Mode

```bash
# Enable debug logging in .env.api.staging:
APP_DEBUG=true
LOG_LEVEL=debug

# Restart
make staging-restart
```

### Health Checks

```bash
# Check all services
docker compose -f docker-compose.staging.yml ps

# Expected output:
# postgres   healthy
# redis      healthy
# api        healthy
# ui         healthy

# UI Health
curl http://localhost:3000/api/health
```

---

## Remote Server Deployment

### Step 1: Prepare Server

```bash
# SSH to server
ssh user@your-server-ip

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Logout and login again
exit
ssh user@your-server-ip

# Verify Docker
docker --version
docker compose version
```

### Step 2: Transfer Code

```bash
# Option 1: Git clone
git clone <your-repo-url>
cd setup

# Option 2: rsync from local
rsync -avz --exclude '.git' \
  /path/to/setup/ user@server:/home/user/setup/
```

### Step 3: Configure for Server

```bash
# Create env files
cp environments/.env.db.staging.example .env.db.staging
cp environments/.env.api.staging.example .env.api.staging
cp environments/.env.ui.staging.example .env.ui.staging

# Generate secrets
make generate-secrets

# Update .env.api.staging
nano .env.api.staging
# Set: CORS_ALLOWED_ORIGINS=http://your-server-ip:3000

# Update .env.ui.staging
nano .env.ui.staging
# Set: NEXT_PUBLIC_APP_URL=http://your-server-ip:3000
```

### Step 4: Start on Server

```bash
# Start with test data
make staging-up-seed

# Verify
make status
curl http://localhost:3000/api/health
```

### Step 5: Configure Firewall

```bash
# Ubuntu UFW
sudo ufw allow 3000/tcp    # UI
sudo ufw allow 22/tcp      # SSH
sudo ufw enable
```

### Step 6: (Optional) Setup Nginx Reverse Proxy

```bash
# Install Nginx
sudo apt install nginx

# Create config
sudo nano /etc/nginx/sites-available/rediver

# Add:
server {
    listen 80;
    server_name staging.yourdomain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }
}

# Enable site
sudo ln -s /etc/nginx/sites-available/rediver /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

### Step 7: (Optional) Setup SSL with Let's Encrypt

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Get certificate
sudo certbot --nginx -d staging.yourdomain.com

# Update env files for HTTPS
# .env.api.staging
CORS_ALLOWED_ORIGINS=https://staging.yourdomain.com

# .env.ui.staging
NEXT_PUBLIC_APP_URL=https://staging.yourdomain.com
SECURE_COOKIES=true

# Restart
make staging-restart
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Docker & Docker Compose installed
- [ ] `.env.db.staging` created from example (`cp environments/.env.db.staging.example .env.db.staging`)
- [ ] `.env.api.staging` created from example (`cp environments/.env.api.staging.example .env.api.staging`)
- [ ] `.env.ui.staging` created from example (`cp environments/.env.ui.staging.example .env.ui.staging`)
- [ ] `DB_PASSWORD` updated in `.env.db.staging`
- [ ] `AUTH_JWT_SECRET` updated (min 64 chars)
- [ ] `CSRF_SECRET` updated (min 32 chars)
- [ ] `NEXT_PUBLIC_APP_URL` set correctly
- [ ] `CORS_ALLOWED_ORIGINS` set correctly

### Post-Deployment

- [ ] All services healthy (`make staging-ps`)
- [ ] UI accessible at configured URL
- [ ] Can login with test credentials
- [ ] API health check passes (`curl http://localhost:3000/api/health`)

### For HTTPS/SSL Mode (Optional)

- [ ] SSL certificates generated (`make init-ssl` for self-signed, or Let's Encrypt for production)
- [ ] `.env.nginx.staging` created (`cp environments/.env.nginx.staging.example .env.nginx.staging`)
- [ ] `NGINX_HOST` set in `.env.nginx.staging` (e.g., localhost or your domain)
- [ ] `CORS_ALLOWED_ORIGINS` updated for HTTPS
- [ ] `NEXT_PUBLIC_APP_URL` updated for HTTPS
- [ ] `SECURE_COOKIES=true` in `.env.ui.staging`
- [ ] Start with `make staging-up-ssl` or `make staging-up-ssl-seed`

### For Remote Server

- [ ] Firewall configured (port 3000, or 80/443 for SSL mode)
- [ ] (Optional) Use built-in nginx (`make staging-up-ssl`)
- [ ] SSL certificate installed
- [ ] `SECURE_COOKIES=true` if using HTTPS

---

## Support

- **Issues:** https://github.com/your-org/rediver/issues
- **Documentation:** Check `docs/` folder
