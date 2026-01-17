# Docker Images Architecture

This document describes the Docker images used in the Rediver platform and how they work together.

## Overview

The Rediver platform uses 4 Docker images published to Docker Hub:

| Image | Description | Repository |
|-------|-------------|------------|
| `rediverio/api` | Backend API (Go) | api |
| `rediverio/ui` | Frontend UI (Next.js) | ui |
| `rediverio/migrations` | Database migrations | api |
| `rediverio/seed` | Database seed data | api |

## Image Details

### 1. API Image (`rediverio/api`)

The main backend API built with Go.

```bash
# Pull latest
docker pull rediverio/api:latest

# Pull staging
docker pull rediverio/api:staging-latest

# Pull specific version
docker pull rediverio/api:v0.1.0
```

**Tags:**
- `latest` - Latest production release
- `staging-latest` - Latest staging build
- `v0.1.0` - Specific version

### 2. UI Image (`rediverio/ui`)

The frontend application built with Next.js.

```bash
docker pull rediverio/ui:latest
docker pull rediverio/ui:staging-latest
```

### 3. Migrations Image (`rediverio/migrations`)

Contains database migration files and the migrate tool.

```bash
docker pull rediverio/migrations:latest
docker pull rediverio/migrations:staging-latest
```

**Usage:**
```bash
# Apply all migrations
docker run --rm \
  rediverio/migrations:staging-latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  up

# Rollback last migration
docker run --rm \
  rediverio/migrations:staging-latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  down 1

# Show current version
docker run --rm \
  rediverio/migrations:staging-latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  version
```

### 4. Seed Image (`rediverio/seed`)

Contains SQL seed files for initializing database data.

```bash
docker pull rediverio/seed:latest
docker pull rediverio/seed:staging-latest
```

**Available seed files:**
- `seed_required.sql` - Required data (roles, permissions, default settings)
- `seed_test.sql` - Test/demo data (test users, sample assets)
- `seed_vnsecurity_assets.sql` - VNSecurity specific assets

**Usage:**
```bash
# List available seed files
docker run --rm rediverio/seed:staging-latest ls -la /seed/

# Run specific seed file
docker run --rm \
  -e PGHOST=postgres \
  -e PGUSER=rediver \
  -e PGPASSWORD=secret \
  -e PGDATABASE=rediver \
  rediverio/seed:staging-latest \
  psql -f /seed/seed_required.sql
```

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
# Seed with required + test data
make staging-seed

# Seed with VNSecurity assets
make staging-seed-vnsecurity

# Seed with custom file
make staging-seed-custom FILE=seed_vnsecurity_assets.sql

# List available seed files
make staging-seed-list
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

# Seed VNSecurity assets (after services are running)
docker compose -f docker-compose.staging.yml --profile seed-vnsecurity up seed-vnsecurity
```

### Available Profiles

| Profile | Description |
|---------|-------------|
| `seed` | Run seed_required.sql + seed_test.sql |
| `seed-vnsecurity` | Run seed_vnsecurity_assets.sql |
| `ssl` | Enable nginx reverse proxy with SSL |
| `debug` | Expose database and Redis ports |

## Building Images Locally

If you need to build images locally for development:

```bash
cd api

# Build API image
docker build -t rediverio/api:local -f Dockerfile --target production .

# Build migrations image
docker build -t rediverio/migrations:local -f Dockerfile.migrations .

# Build seed image
docker build -t rediverio/seed:local -f Dockerfile.seed .
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
docker manifest inspect rediverio/api:staging-latest
```
