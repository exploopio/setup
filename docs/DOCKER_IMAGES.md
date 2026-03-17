# Docker Images Architecture

This document describes the Docker images used in the OpenCTEM platform and how they work together.

## Overview

The OpenCTEM platform publishes Docker images to **two registries**:

| Registry | Domain | Availability |
|----------|--------|-------------|
| **GitHub Container Registry (GHCR)** | `ghcr.io/openctemio/*` | Always available (default) |
| **Docker Hub** | `openctemio/*` | Optional mirror (requires secrets) |

**GHCR is the primary registry** — images are always pushed there via `GITHUB_TOKEN`. Docker Hub is an optional mirror that only works if `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` secrets are configured in the GitHub repo.

### Images

| Image | Description | Source Repo | Architectures |
|-------|-------------|------------|----------------|
| `api` | Backend API (Go) | api | amd64, arm64 |
| `ui` | Frontend UI (Next.js) | ui | amd64, arm64 |
| `migrations` | Database migrations | api | amd64, arm64 |
| `seed` | Database seed data | api | amd64, arm64 |
| `admin-cli` | Admin CLI tool | api | amd64, arm64 |
| `agent` | Security scanning agent (5 variants) | agent | amd64, arm64 |

> **Note:** `admin-ui` is an optional component (use `--profile admin` in compose). It requires a separate admin-ui image to be available.

## Registry Configuration

The `IMAGE_REGISTRY` variable controls which registry to pull from:

```bash
# Default: GitHub Container Registry (always available)
IMAGE_REGISTRY=ghcr.io/openctemio

# Alternative: Docker Hub (if images are mirrored)
IMAGE_REGISTRY=openctemio
```

Set this in `.env.versions.prod` or `.env.versions.staging`.

## Pulling Images

```bash
# From GHCR (default, always available)
docker pull ghcr.io/openctemio/api:latest
docker pull ghcr.io/openctemio/api:v0.2.0
docker pull ghcr.io/openctemio/api:staging-latest

# From Docker Hub (if mirrored)
docker pull openctemio/api:latest
docker pull openctemio/api:v0.2.0
```

## Image Details

### API Image (`api`)

The main backend API built with Go.

**Tags:**
- `latest` - Latest production release
- `staging-latest` - Latest staging build
- `v0.1.0` - Specific version

### UI Image (`ui`)

The frontend application built with Next.js.

### Migrations Image (`migrations`)

Contains database migration files and the migrate tool.

```bash
# Apply all migrations
docker run --rm \
  ghcr.io/openctemio/migrations:latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  up

# Rollback last migration
docker run --rm \
  ghcr.io/openctemio/migrations:latest \
  -path=/migrations \
  -database "postgres://user:pass@host:5432/db?sslmode=disable" \
  down 1
```

### Seed Image (`seed`)

Contains SQL seed files for initializing database data.

**Available seed files:**
- `seed_required.sql` - Required data (roles, permissions, default settings)
- `seed_comprehensive.sql` - Comprehensive test data (users, teams, assets, findings)

### Agent Image (`agent`)

Security scanning agent with multiple variants:

| Variant | Tag Pattern | Description |
|---------|------------|-------------|
| `default` | `:v1.0.0-default`, `:latest-default` | Base agent |
| `semgrep` | `:v1.0.0-semgrep`, `:latest-semgrep` | With Semgrep |
| `trivy` | `:v1.0.0-trivy`, `:latest-trivy` | With Trivy |
| `nuclei` | `:v1.0.0-nuclei`, `:latest-nuclei` | With Nuclei |
| `gitleaks` | `:v1.0.0-gitleaks`, `:latest-gitleaks` | With Gitleaks |

## Version Configuration

Versions are configured in `.env.versions.staging` or `.env.versions.prod`:

```bash
# .env.versions.prod
IMAGE_REGISTRY=ghcr.io/openctemio
API_VERSION=v0.2.0
UI_VERSION=v0.2.0
ADMIN_UI_VERSION=v0.2.0
MIGRATIONS_VERSION=v0.2.0
```

**Important:** Keep `MIGRATIONS_VERSION` and `SEED_VERSION` in sync with `API_VERSION` to ensure schema compatibility.

## CI/CD Pipeline

Images are automatically built and pushed when a version tag is created:

1. **Tag push** (`v*`) → Production build → Push to GHCR → Mirror to Docker Hub (if configured)
2. **Tag push** (`v*-staging`) → Staging build → Push to GHCR → Mirror to Docker Hub (if configured)
3. **Manual dispatch** → Can be triggered from GitHub Actions

### Pipeline Flow

```
PREPARE → BUILD (amd64 + arm64 native) → MERGE (multi-arch manifest) → MIRROR to Docker Hub (optional)
```

Each repo has its own `docker-publish.yml` workflow:
- `api` repo: builds `api`, `migrations`, `seed`, `admin-cli` (4 images)
- `ui` repo: builds `ui` (1 image)
- `agent` repo: builds `agent` x 5 variants (5 images)

### Environment Detection

- Tag contains `-staging` → staging environment (`:v1.0.0-staging`, `:staging-latest`)
- Tag without `-staging` → production environment (`:v1.0.0`, `:latest`)

## Docker Compose Profiles

### Staging Environment

```bash
# Basic (no seed)
docker compose -f docker-compose.staging.yml up -d

# With test data seed
docker compose -f docker-compose.staging.yml --profile seed up -d

# With SSL/nginx
docker compose -f docker-compose.staging.yml --profile ssl up -d
```

### Available Profiles

| Profile | Description |
|---------|-------------|
| `seed` | Run seed_required.sql + seed_comprehensive.sql |
| `ssl` | Enable nginx reverse proxy with SSL |
| `debug` | Expose database and Redis ports |

## Troubleshooting

### Image not found

GHCR images require authentication for private repos:
```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Then pull
docker compose -f docker-compose.staging.yml pull
```

### Migration fails with "file does not exist"

Ensure `MIGRATIONS_VERSION` matches `API_VERSION`:
```bash
grep VERSION .env.versions.staging
```

### Password contains special characters

Database passwords must be URL-safe (no `/`, `+`, `=`). Generate safe passwords:
```bash
make generate-secrets
```
