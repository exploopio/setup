# Docker Images Architecture

This document describes the Docker images used in the OpenCTEM platform and how they work together.

## Overview

The OpenCTEM platform uses 4 Docker images published to Docker Hub:

| Image | Description | Repository |
|-------|-------------|------------|
| `openctemio/api` | Backend API (Go) | api |
| `openctemio/ui` | Frontend UI (Next.js) | ui |
| `openctemio/migrations` | Database migrations | api |
| `openctemio/seed` | Database seed data | api |
| `openctemio/agent` | Security scanning agent | agent |

## Image Details

### 1. API Image (`openctemio/api`)

The main backend API built with Go.

```bash
# Pull latest
docker pull openctemio/api:latest

# Pull staging
docker pull openctemio/api:staging-latest

# Pull specific version
docker pull openctemio/api:v0.1.0
```

**Tags:**
- `latest` - Latest production release
- `staging-latest` - Latest staging build
- `v0.1.0` - Specific version

### 2. UI Image (`openctemio/ui`)

The frontend application built with Next.js.

```bash
docker pull openctemio/ui:latest
docker pull openctemio/ui:staging-latest
```

### 3. Migrations Image (`openctemio/migrations`)

Contains database migration files and the migrate tool.

```bash
docker pull openctemio/migrations:latest
docker pull openctemio/migrations:staging-latest
```

**Usage:**
```bash
# Apply all migrations
docker run --rm \
  openctemio/migrations:staging-latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  up

# Rollback last migration
docker run --rm \
  openctemio/migrations:staging-latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  down 1

# Show current version
docker run --rm \
  openctemio/migrations:staging-latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  version
```

### 4. Seed Image (`openctemio/seed`)

Contains SQL seed files for initializing database data.

```bash
docker pull openctemio/seed:latest
docker pull openctemio/seed:staging-latest
```

**Available seed files:**
- `seed_required.sql` - Required data (roles, permissions, default settings)
- `seed_comprehensive.sql` - Comprehensive test data (users, teams, assets, findings)

**Usage:**
```bash
# List available seed files
docker run --rm openctemio/seed:staging-latest ls -la /seed/

# Run specific seed file
docker run --rm \
  -e PGHOST=postgres \
  -e PGUSER=openctem \
  -e PGPASSWORD=secret \
  -e PGDATABASE=openctem \
  openctemio/seed:staging-latest \
  psql -f /seed/seed_required.sql
```

### 5. Agent Image (`openctemio/agent`)

Security scanning agent for CI/CD integration and continuous monitoring.

```bash
docker pull openctemio/agent:latest   # Full (semgrep + gitleaks + trivy)
docker pull openctemio/agent:slim     # Minimal (no tools)
docker pull openctemio/agent:ci       # CI optimized (preloaded Trivy DB)
```

**Component Types:**
| Type | Use Case | Mode | Recommended Image |
|------|----------|------|-------------------|
| `runner` | CI/CD pipelines | One-shot | `openctemio/agent:ci` |
| `worker` | Production scanning | Daemon | `openctemio/agent:latest` |
| `collector` | Infrastructure inventory | Daemon | `openctemio/agent:latest` |

**Image Variants:**
| Variant | Description | Use Case |
|---------|-------------|----------|
| `latest` | All tools included | Production scanning |
| `slim` | Agent only, no tools | Custom tool setup |
| `ci` | Full + preloaded Trivy DB | CI/CD (faster startup) |

**Usage:**
```bash
# Runner: CI/CD one-shot scan
docker run --rm \
  -v "$(pwd)":/code:ro \
  -e API_URL=https://api.openctem.io \
  -e API_KEY=your-api-key \
  openctemio/agent:ci \
  -tools semgrep,gitleaks,trivy-fs -target /code -push

# Worker: Server-controlled daemon
docker run -d \
  --name openctem-worker \
  --restart unless-stopped \
  -e API_URL=https://api.openctem.io \
  -e API_KEY=your-api-key \
  -e WORKER_ID=your-worker-id \
  openctemio/agent:latest \
  -daemon -enable-commands -verbose

# Collector: Infrastructure scanning
docker run -d \
  --name openctem-collector \
  --restart unless-stopped \
  -e API_URL=https://api.openctem.io \
  -e API_KEY=your-api-key \
  -e WORKER_ID=your-collector-id \
  -e AWS_ACCESS_KEY_ID=your-access-key \
  -e AWS_SECRET_ACCESS_KEY=your-secret-key \
  openctemio/agent:latest \
  -daemon -enable-commands -verbose
```

See [Agent README](https://github.com/openctemio/agent) and [Worker Architecture](./WORKER_ARCHITECTURE.md) for full documentation.

## Version Configuration

Versions are configured in `.env.versions.staging` or `.env.versions.prod`:

```bash
# .env.versions.staging
API_VERSION=staging-latest
UI_VERSION=staging-latest
MIGRATIONS_VERSION=staging-latest
SEED_VERSION=staging-latest
```

**Important:** Keep `MIGRATIONS_VERSION` and `SEED_VERSION` in sync with `API_VERSION` to ensure schema compatibility.

## Makefile Commands

### Seeding Commands

```bash
# Seed with required + comprehensive test data
make staging-seed
```

### Migration Commands

```bash
# Run migrations
make db-migrate-staging

# Open database shell
make db-shell-staging
```

## Docker Compose Profiles

### Staging Environment

```bash
# Basic (no seed)
docker compose -f docker-compose.staging.yml up -d

# With test data seed
docker compose -f docker-compose.staging.yml --profile seed up -d

# With SSL/nginx
docker compose -f docker-compose.staging.yml --profile ssl up -d

# With SSL + test data
docker compose -f docker-compose.staging.yml --profile ssl --profile seed up -d
```

### Available Profiles

| Profile | Description |
|---------|-------------|
| `seed` | Run seed_required.sql + seed_comprehensive.sql |
| `ssl` | Enable nginx reverse proxy with SSL |
| `debug` | Expose database and Redis ports |

## Building Images Locally

If you need to build images locally for development:

```bash
cd api

# Build API image
docker build -t openctemio/api:local -f Dockerfile --target production .

# Build migrations image
docker build -t openctemio/migrations:local -f Dockerfile.migrations .

# Build seed image
docker build -t openctemio/seed:local -f Dockerfile.seed .
```

## CI/CD Pipeline

Images are automatically built and pushed to Docker Hub when:

1. **Tag push** (`v*`) - Triggers production build
2. **Tag push** (`v*-staging`) - Triggers staging build
3. **Manual dispatch** - Can be triggered from GitHub Actions

See [CICD.md](./CICD.md) for detailed CI/CD documentation.

## Troubleshooting

### Migration fails with "file does not exist"

Ensure `MIGRATIONS_VERSION` matches `API_VERSION`:
```bash
# Check current versions
grep VERSION .env.versions.staging

# Should match
API_VERSION=staging-latest
MIGRATIONS_VERSION=staging-latest
```

### Seed fails with "relation does not exist"

Run migrations first:
```bash
make db-migrate-staging
# Then seed
make staging-seed
```

### Password contains special characters

Database passwords must be URL-safe (no `/`, `+`, `=`). Generate safe passwords:
```bash
make generate-secrets
```

### Image not found

Pull the latest images:
```bash
docker compose -f docker-compose.staging.yml pull
```

Or check if the image exists on Docker Hub:
```bash
docker manifest inspect openctemio/api:staging-latest
```
