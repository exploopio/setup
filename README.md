# Rediver Platform

[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://docs.docker.com/compose/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Rediver is a multi-tenant security platform with a Go backend API and Next.js frontend.

## 📚 Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](https://docs.rediver.io/docs/getting-started) | Quick start guide |
| [Architecture](https://docs.rediver.io/docs/architecture/overview) | System design |
| [Authentication](https://docs.rediver.io/docs/guides/authentication) | JWT & OIDC auth flow |
| [Multi-tenancy](https://docs.rediver.io/docs/guides/multi-tenancy) | Teams & tenant switching |
| [Permissions](https://docs.rediver.io/docs/guides/permissions) | Role-based access control |
| [Configuration](https://docs.rediver.io/docs/operations/configuration) | Environment variables |
| [Troubleshooting](https://docs.rediver.io/docs/operations/troubleshooting) | Common issues |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Docker Network                           │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐      │
│  │   rediver-ui │    │  rediver-api │    │   postgres   │      │
│  │   (Next.js)  │───▶│    (Go)      │───▶│  (Database)  │      │
│  │   Port 3000  │    │   Internal   │    │   Internal   │      │
│  └──────────────┘    └──────────────┘    └──────────────┘      │
│         │                   │                                   │
│         │                   ▼                                   │
│         │            ┌──────────────┐                          │
│         │            │    redis     │                          │
│         └───────────▶│   (Cache)    │                          │
│                      │   Internal   │                          │
│                      └──────────────┘                          │
└─────────────────────────────────────────────────────────────────┘
         ▲
         │ Only port 3000 exposed
         │
    [Internet]
```

## Environment Files

Environment example files are located in `environments/` folder:

| Environment | DB Config | API Config | UI Config | Nginx Config |
|-------------|-----------|------------|-----------|--------------|
| Staging | `.env.db.staging` | `.env.api.staging` | `.env.ui.staging` | `.env.nginx.staging` |
| Production | `.env.db.prod` | `.env.api.prod` | `.env.ui.prod` | `.env.nginx.prod` |

**Note:**
- Database credentials are separated into `.env.db.*` for security
- Nginx config (`.env.nginx.*`) is only needed when using SSL profile
- Example files are in `environments/` folder, copy to root directory for use

## Docker Images

Images are pulled from Docker Hub (`rediverio`):

| Image | Description | Staging Tag | Production Tag |
|-------|-------------|-------------|----------------|
| `rediverio/rediver-api` | Backend API | `staging-latest` | `latest` |
| `rediverio/rediver-ui` | Frontend UI | `staging-latest` | `latest` |
| `rediverio/rediver-migrations` | DB migrations | `staging-latest` | `latest` |
| `rediverio/rediver-seed` | DB seed data | `staging-latest` | `latest` |

See [docs/DOCKER_IMAGES.md](./docs/DOCKER_IMAGES.md) for detailed documentation.

---

## Quick Start (Staging)

### Prerequisites

- Docker & Docker Compose v2+
- ~4GB RAM available

### 1. Setup Environment Files

```bash
cd rediver-setup

# Copy environment templates from environments folder
cp environments/.env.db.staging.example .env.db.staging
cp environments/.env.api.staging.example .env.api.staging
cp environments/.env.ui.staging.example .env.ui.staging

# Generate secrets
make generate-secrets
```

### 2. Configure Environment

Edit `.env.db.staging` and update:

```env
# Database credentials
DB_PASSWORD=<generated_password>
```

Edit `.env.api.staging` and update:

```env
# Authentication (REQUIRED - min 64 chars)
AUTH_JWT_SECRET=<generated_jwt_secret>
```

Edit `.env.ui.staging` and update:

```env
# Security (REQUIRED - min 32 chars)
CSRF_SECRET=<generated_csrf_secret>
```

### 3. Start Everything

```bash
# Start all services
make staging-up

# Or with test data
make staging-up-seed
```

### 4. Access Application

- **Frontend**: http://localhost:3000
- **API Health**: http://localhost:3000/api/health

**Test credentials** (when using `staging-up-seed`):
- Email: `admin@rediver.io`
- Password: `Password123`

### 5. Database Migration & Seeding

Migrations run automatically on startup. For manual seeding:

```bash
# Seed required data (permissions, roles)
make db-migrate-staging

# Seed test data (users, teams)
make staging-seed

# Seed VNSecurity sample assets (optional)
make staging-seed-vnsecurity

# List available seed files
make staging-seed-list
```

**Seed options:**
| Command | Description |
|---------|-------------|
| `make staging-up-seed` | Start + auto-seed test data |
| `make staging-seed` | Seed test data to running DB |
| `make staging-seed-vnsecurity` | Add VNSecurity sample assets |
| `make staging-seed-custom FILE=name.sql` | Custom seed file |

### 6. HTTPS/SSL Mode (Optional)

To run staging with HTTPS (useful for testing OAuth, secure cookies):

```bash
# Generate self-signed certificate
make init-ssl

# Start with nginx/SSL
make staging-up-ssl

# Access via HTTPS
open https://localhost
# Note: Browser will show certificate warning (expected for self-signed)
```

### 7. Debug Mode (Optional)

To expose database and Redis ports for debugging:

```bash
# Start with debug profile
docker compose -f docker-compose.staging.yml --env-file .env.db.staging --profile debug up -d

# Access database
psql -h localhost -p 5432 -U rediver -d rediver

# Access Redis
redis-cli -h localhost -p 6379
```

---

## Quick Start (Production)

### Docker Compose Options

| File | Nginx | SSL | Use Case |
|------|-------|-----|----------|
| `docker-compose.prod.yml` | Yes | Yes | Full production with built-in SSL |
| `docker-compose.prod-simple.yml` | No | No | External proxy (AWS ALB, Traefik, etc.) |

### Option A: Production with Nginx/SSL (Recommended)

#### 1. Setup Environment Files

```bash
cd rediver-setup

# Copy environment templates from environments folder
cp environments/.env.db.prod.example .env.db.prod
cp environments/.env.api.prod.example .env.api.prod
cp environments/.env.ui.prod.example .env.ui.prod

# Generate secrets
make generate-secrets
```

#### 2. Configure Environment

Edit `.env.db.prod`:
```env
DB_PASSWORD=<CHANGE_ME_STRONG_PASSWORD>
REDIS_PASSWORD=<CHANGE_ME_STRONG_PASSWORD>
```

Edit `.env.api.prod`:
```env
AUTH_JWT_SECRET=<CHANGE_ME_GENERATE_WITH_OPENSSL>
CORS_ALLOWED_ORIGINS=https://your-domain.com
```

Edit `.env.ui.prod`:
```env
NEXT_PUBLIC_APP_URL=https://your-domain.com
CSRF_SECRET=<CHANGE_ME>
SECURE_COOKIES=true
```

#### 3. Setup SSL Certificates

See [nginx/README.md](nginx/README.md) for detailed SSL setup.

```bash
# Option A: Let's Encrypt (recommended)
sudo certbot certonly --standalone -d your-domain.com
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem nginx/ssl/key.pem

# Option B: Self-signed (testing only)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem -out nginx/ssl/cert.pem \
  -subj "/CN=localhost"
```

#### 4. Update Nginx Config

```bash
# Replace domain in nginx config
sed -i 's/your-domain.com/yourdomain.com/g' nginx/nginx.conf
```

#### 5. Start Production

```bash
docker compose -f docker-compose.prod.yml up -d

# With specific version
VERSION=v0.2.0 docker compose -f docker-compose.prod.yml up -d
```

### Option B: Production without Nginx (External Proxy)

Use this when you have an external reverse proxy (AWS ALB, GCP Load Balancer, Traefik, Kubernetes Ingress).

```bash
# Setup environment (same as above steps 1-2)

# Start without nginx
docker compose -f docker-compose.prod-simple.yml up -d
```

This exposes port 3000 for your external reverse proxy to handle SSL termination.

---

## Makefile Commands

### Staging

| Command | Description |
|---------|-------------|
| `make staging-up` | Start staging (HTTP) |
| `make staging-up-seed` | Start with test data (HTTP) |
| `make staging-up-ssl` | Start with nginx/HTTPS |
| `make staging-up-ssl-seed` | Start with nginx/HTTPS + test data |
| `make staging-seed` | Seed test data to running database |
| `make staging-down` | Stop services (HTTP mode) |
| `make staging-down-ssl` | Stop services including nginx (SSL mode) |
| `make staging-logs` | View all logs |
| `make staging-ps` | Show running containers |
| `make staging-restart` | Restart all services |
| `make staging-pull` | Pull latest images |
| `make staging-clean` | Stop and remove volumes (reset DB) |

### Production

| Command | Description |
|---------|-------------|
| `make prod-up` | Start production environment |
| `make prod-down` | Stop all services |
| `make prod-logs` | View all logs |
| `make prod-ps` | Show running containers |
| `make prod-restart` | Restart all services |
| `make prod-pull` | Pull latest images |

### Database

| Command | Description |
|---------|-------------|
| `make db-shell` | Open PostgreSQL shell |
| `make db-seed` | Seed test data |
| `make db-reset` | Reset database (WARNING: deletes all data) |
| `make db-migrate` | Run migrations manually |

### SSL/HTTPS

| Command | Description |
|---------|-------------|
| `make init-ssl` | Generate self-signed certificate (staging/testing) |
| `make init-ssl-letsencrypt` | Show Let's Encrypt setup instructions |
| `make ssl-renew` | Reload nginx after certificate renewal |
| `make staging-up-ssl` | Start staging with nginx/SSL |

### Utility

| Command | Description |
|---------|-------------|
| `make generate-secrets` | Generate secure secrets |
| `make status-staging` | Show staging status and URLs |
| `make status-prod` | Show production status |
| `make help` | Show all commands |

---

## Project Structure

```
rediver-setup/
├── docker-compose.staging.yml     # Staging deployment
├── docker-compose.prod.yml        # Production with Nginx/SSL
├── docker-compose.prod-simple.yml # Production without Nginx (external proxy)
├── environments/                  # Environment example files
│   ├── .env.db.staging.example    # DB credentials (staging)
│   ├── .env.db.prod.example       # DB credentials (production)
│   ├── .env.api.staging.example   # API config (staging)
│   ├── .env.api.prod.example      # API config (production)
│   ├── .env.ui.staging.example    # UI config (staging)
│   ├── .env.ui.prod.example       # UI config (production)
│   ├── .env.nginx.staging.example # Nginx config (staging)
│   └── .env.nginx.prod.example    # Nginx config (production)
├── nginx/                         # Nginx configuration
│   ├── nginx.conf                 # Main nginx config
│   ├── templates/                 # Server block templates
│   │   └── default.conf.template  # Uses ${NGINX_HOST} variable
│   ├── ssl/                       # SSL certificates (gitignored)
│   └── README.md                  # Nginx setup guide
├── Makefile                       # Convenience commands
├── README.md                      # This file
└── docs/
    └── STAGING_DEPLOYMENT.md      # Detailed staging guide
```

---

## Environment Variables

### Database Configuration (.env.db.*)

| Variable | Required | Description |
|----------|----------|-------------|
| `DB_USER` | Yes | Database username |
| `DB_PASSWORD` | Yes | Database password |
| `DB_NAME` | Yes | Database name |
| `REDIS_PASSWORD` | Prod only | Redis password |

### API Configuration (.env.api.*)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_HOST` | Yes | postgres | Database host |
| `DB_PORT` | Yes | 5432 | Database port |
| `REDIS_HOST` | Yes | redis | Redis host |
| `AUTH_JWT_SECRET` | Yes | - | JWT signing secret (min 64 chars) |
| `AUTH_PROVIDER` | No | local | Auth mode: local, oidc |
| `CORS_ALLOWED_ORIGINS` | Yes | - | Allowed CORS origins |
| `LOG_LEVEL` | No | info | Log level: debug, info, warn, error |

### UI Configuration (.env.ui.*)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NEXT_PUBLIC_APP_URL` | Yes | http://localhost:3000 | Public app URL |
| `BACKEND_API_URL` | Yes | http://api:8080 | Internal API URL |
| `CSRF_SECRET` | Yes | - | CSRF token secret (min 32 chars) |
| `SECURE_COOKIES` | Prod only | false | Set true for HTTPS |

---

## Versioning

Specify version when starting:

```bash
# Staging
VERSION=v0.2.0 make staging-up

# Production
VERSION=v0.2.0 make prod-up
```

Default version: `v0.1.0`

---

## Troubleshooting

### Services won't start

```bash
# Check logs
make staging-logs
# or
make prod-logs

# Check specific service
docker compose -f docker-compose.staging.yml logs api
docker compose -f docker-compose.staging.yml logs ui
```

### Database issues

```bash
# Check if postgres is healthy
docker compose -f docker-compose.staging.yml ps postgres

# Access database shell (requires debug profile in staging)
docker compose -f docker-compose.staging.yml --profile debug up -d
make db-shell

# Reset database
make db-reset
make staging-restart
```

### Port conflicts

Change ports in env files:
```env
# .env.ui.staging
UI_PORT=3001
```

---

## CI/CD

Docker images are automatically built and published to Docker Hub using GitHub Actions.

### Triggering Builds

**Option 1: Push a tag (automatic)**
```bash
# Staging release
git tag v0.1.1-staging
git push origin v0.1.1-staging

# Production release
git tag v0.1.1
git push origin v0.1.1
```

**Option 2: Manual trigger**
1. Go to **Actions** tab in GitHub
2. Select **Docker Publish** workflow
3. Click **Run workflow**
4. Enter version and environment

### Image Tags

| Environment | Image Tag Format | Example |
|-------------|------------------|---------|
| Staging | `v*.*.*-staging` | `rediverio/rediver-ui:v0.1.1-staging` |
| Production | `v*.*.*` | `rediverio/rediver-ui:v0.1.1` |

### Setup Requirements

Add these secrets to GitHub repository:
- `DOCKERHUB_USERNAME`: Docker Hub username
- `DOCKERHUB_TOKEN`: Docker Hub access token

See [docs/CICD.md](docs/CICD.md) for detailed documentation.

---

## Security Notes

### Staging

- Database and Redis NOT exposed by default
- Use `--profile debug` to expose ports for debugging
- Debug logging enabled
- Test credentials available

### Production

- Database and Redis NOT exposed externally
- Only UI service accessible from outside (port 3000)
- All API traffic goes through UI's BFF proxy
- Security hardening enabled:
  - `no-new-privileges` on all containers
  - `read_only` filesystem for API container
  - Resource limits enforced
- HTTPS and secure cookies required
- Strong passwords required

---

## License

Copyright 2024 Rediver. All rights reserved.
