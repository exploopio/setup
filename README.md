# Rediver Platform

Rediver is a multi-tenant security platform with a Go backend API and Next.js frontend.

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

| Environment | DB Config | API Config | UI Config |
|-------------|-----------|------------|-----------|
| Staging | `.env.db.staging` | `.env.api.staging` | `.env.ui.staging` |
| Production | `.env.db.prod` | `.env.api.prod` | `.env.ui.prod` |

**Note:** Database credentials are separated into `.env.db.*` for security.

## Docker Images

Images are pulled from Docker Hub (`rediverio`):

| Environment | API Image | UI Image |
|-------------|-----------|----------|
| Staging | `rediverio/rediver-api:<version>-staging` | `rediverio/rediver-ui:<version>-staging` |
| Production | `rediverio/rediver-api:<version>` | `rediverio/rediver-ui:<version>` |

---

## Quick Start (Staging)

### Prerequisites

- Docker & Docker Compose v2+
- ~4GB RAM available

### 1. Setup Environment Files

```bash
cd rediver-setup

# Copy environment templates
cp .env.db.staging.example .env.db.staging
cp .env.api.staging.example .env.api.staging
cp .env.ui.staging.example .env.ui.staging

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

### 5. Debug Mode (Optional)

To expose database and Redis ports for debugging:

```bash
# Start with debug profile
docker compose -f docker-compose.staging.yml --profile debug up -d

# Access database
psql -h localhost -p 5432 -U rediver -d rediver

# Access Redis
redis-cli -h localhost -p 6379
```

---

## Quick Start (Production)

### 1. Setup Environment Files

```bash
cd rediver-setup

# Copy environment templates
cp .env.db.prod.example .env.db.prod
cp .env.api.prod.example .env.api.prod
cp .env.ui.prod.example .env.ui.prod

# Generate secrets
make generate-secrets
```

### 2. Configure Environment

Edit `.env.db.prod` and update:

```env
# Database
DB_PASSWORD=<CHANGE_ME_STRONG_PASSWORD>

# Redis
REDIS_PASSWORD=<CHANGE_ME_STRONG_PASSWORD>
```

Edit `.env.api.prod` and update ALL `<CHANGE_ME>` values:

```env
# Authentication
AUTH_JWT_SECRET=<CHANGE_ME_GENERATE_WITH_OPENSSL>

# CORS
CORS_ALLOWED_ORIGINS=https://your-domain.com

# SMTP
SMTP_HOST=<CHANGE_ME_SMTP_HOST>
SMTP_USER=<CHANGE_ME>
SMTP_PASSWORD=<CHANGE_ME>
```

Edit `.env.ui.prod` and update:

```env
# URLs
NEXT_PUBLIC_APP_URL=https://your-domain.com

# Security
CSRF_SECRET=<CHANGE_ME>
SECURE_COOKIES=true
```

### 3. Start Production

```bash
# Pull and start
make prod-up

# With specific version
VERSION=v0.2.0 make prod-up
```

---

## Makefile Commands

### Staging

| Command | Description |
|---------|-------------|
| `make staging-up` | Start staging environment |
| `make staging-up-seed` | Start with test data |
| `make staging-down` | Stop all services |
| `make staging-logs` | View all logs |
| `make staging-ps` | Show running containers |
| `make staging-restart` | Restart all services |
| `make staging-pull` | Pull latest images |

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

### Utility

| Command | Description |
|---------|-------------|
| `make generate-secrets` | Generate secure secrets |
| `make status` | Show service status and URLs |
| `make help` | Show all commands |

---

## Project Structure

```
rediver-setup/
├── docker-compose.staging.yml     # Staging deployment
├── docker-compose.prod.yml        # Production deployment
├── .env.db.staging.example        # DB credentials (staging)
├── .env.db.prod.example           # DB credentials (production)
├── .env.api.staging.example       # API config (staging)
├── .env.api.prod.example          # API config (production)
├── .env.ui.staging.example        # UI config (staging)
├── .env.ui.prod.example           # UI config (production)
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
