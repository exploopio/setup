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
- [Management Commands](#management-commands)
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
- Ports: 3000 (UI), 5432 (DB - optional), 6379 (Redis - optional)
```

---

## Quick Start

### 5-Minute Deployment

```bash
# 1. Clone repository
git clone <your-repo-url>
cd rediver-setup

# 2. Create environment files
cp .env.api.staging.example .env.api.staging
cp .env.ui.staging.example .env.ui.staging

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
cd rediver-setup

# Verify structure
ls -la
# Should see: docker-compose.staging.yml, Makefile, .env.*.example files
```

### Step 2: Create Environment Files

```bash
# Copy API configuration
cp .env.api.staging.example .env.api.staging

# Copy UI configuration
cp .env.ui.staging.example .env.ui.staging

# Generate secure secrets
make generate-secrets
```

Output example:
```
JWT Secret (copy to AUTH_JWT_SECRET in .env.api.staging):
abc123def456ghi789...

CSRF Secret (copy to CSRF_SECRET in .env.ui.staging):
xyz789abc123...

DB Password (copy to DB_PASSWORD in .env.api.staging):
secure_password_here...
```

### Step 3: Configure .env.api.staging

Edit `.env.api.staging`:

```bash
nano .env.api.staging
```

**Critical values to update:**

```env
# Database (REQUIRED)
DB_PASSWORD=<generated_password>

# Authentication (REQUIRED - min 64 chars)
AUTH_JWT_SECRET=<generated_jwt_secret>

# CORS (update for your server)
CORS_ALLOWED_ORIGINS=http://localhost:3000
```

### Step 4: Configure .env.ui.staging

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

### Step 5: Start Services

```bash
# Option 1: Start without test data
make staging-up

# Option 2: Start with test data (RECOMMENDED for staging)
make staging-up-seed
```

### Step 6: Verify Deployment

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
| `.env.api.staging` | API configuration (database, auth, CORS, etc.) |
| `.env.ui.staging` | UI configuration (URLs, cookies, security) |

### API Configuration (.env.api.staging)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_USER` | Yes | rediver | Database username |
| `DB_PASSWORD` | Yes | - | Database password |
| `DB_NAME` | Yes | rediver | Database name |
| `DB_EXTERNAL_PORT` | No | 5432 | External DB port for debugging |
| `REDIS_PASSWORD` | No | - | Redis password (optional for staging) |
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
  image: rediverio/rediver-api:${VERSION:-v0.1.0}-staging

ui:
  image: rediverio/rediver-ui:${VERSION:-v0.1.0}-staging
```

### Port Configuration

| Service | Internal Port | External Port | Configurable |
|---------|---------------|---------------|--------------|
| UI (Next.js) | 3000 | 3000 | `UI_PORT` |
| API (Go) | 8080 | Not exposed | Internal only |
| PostgreSQL | 5432 | 5432 | `DB_EXTERNAL_PORT` |
| Redis | 6379 | 6379 | `REDIS_EXTERNAL_PORT` |

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
    │   :5432   │  │   :6379   │  │  (one-off)│
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

# Or manually after startup
make db-seed
```

### Test Credentials

| Role | Email | Password |
|------|-------|----------|
| Admin | admin@rediver.io | Password123 |
| User | nguyen.an@techviet.vn | Password123 |

---

## Management Commands

### Service Management

```bash
# Start
make staging-up          # Without test data
make staging-up-seed     # With test data

# Stop
make staging-down

# Restart
make staging-restart

# Status
make staging-ps
make status

# Pull latest images
make staging-pull
```

### Logs

```bash
# All logs
make staging-logs

# Docker compose directly
docker compose -f docker-compose.staging.yml logs -f api
docker compose -f docker-compose.staging.yml logs -f ui --tail=100
```

### Database

```bash
# Open psql shell
make db-shell

# Run migrations
make db-migrate

# Seed test data
make db-seed

# Reset database (WARNING: deletes all data)
make db-reset
```

### Cleanup

```bash
# Stop and remove containers + volumes
make staging-clean

# Prune unused Docker resources
make staging-prune
```

---

## Troubleshooting

### Common Issues

#### 1. "Environment file not found"

```bash
# Solution: Create environment files
cp .env.api.staging.example .env.api.staging
cp .env.ui.staging.example .env.ui.staging
# Then update secrets
```

#### 2. "Database connection refused"

```bash
# Check PostgreSQL is running
docker compose -f docker-compose.staging.yml ps postgres

# Check logs
docker compose -f docker-compose.staging.yml logs postgres

# Verify credentials in .env.api.staging match
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
lsof -i :5432

# Change port in env files
# .env.ui.staging
UI_PORT=3001

# .env.api.staging
DB_EXTERNAL_PORT=5433
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
# rediver-postgres   healthy
# rediver-redis      healthy
# rediver-api        healthy
# rediver-ui         healthy

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
cd rediver-setup

# Option 2: rsync from local
rsync -avz --exclude '.git' \
  /path/to/rediver-setup/ user@server:/home/user/rediver-setup/
```

### Step 3: Configure for Server

```bash
# Create env files
cp .env.api.staging.example .env.api.staging
cp .env.ui.staging.example .env.ui.staging

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
- [ ] `.env.api.staging` created from example
- [ ] `.env.ui.staging` created from example
- [ ] `AUTH_JWT_SECRET` updated (min 64 chars)
- [ ] `CSRF_SECRET` updated (min 32 chars)
- [ ] `DB_PASSWORD` updated
- [ ] `NEXT_PUBLIC_APP_URL` set correctly
- [ ] `CORS_ALLOWED_ORIGINS` set correctly

### Post-Deployment

- [ ] All services healthy (`make staging-ps`)
- [ ] UI accessible at configured URL
- [ ] Can login with test credentials
- [ ] API health check passes

### For Remote Server

- [ ] Firewall configured
- [ ] (Optional) Nginx reverse proxy setup
- [ ] (Optional) SSL certificate installed
- [ ] `SECURE_COOKIES=true` if using HTTPS

---

## Support

- **Issues:** https://github.com/your-org/rediver/issues
- **Documentation:** Check `docs/` folder
