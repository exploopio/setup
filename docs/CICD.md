# CI/CD Documentation

**Last Updated:** 2026-01-14

This document describes the CI/CD pipelines for building and publishing Docker images.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [GitHub Actions Workflows](#github-actions-workflows)
- [Manual Triggering](#manual-triggering)
- [Tag-based Triggering](#tag-based-triggering)
- [Docker Hub Setup](#docker-hub-setup)
- [Environment Configuration](#environment-configuration)
- [Versioning Strategy](#versioning-strategy)
- [Troubleshooting](#troubleshooting)

---

## Overview

The project uses GitHub Actions to automatically build and publish Docker images to Docker Hub. There are two main workflows:

| Repository | Image | Workflow |
|------------|-------|----------|
| `ui` | `rediverio/ui` | `.github/workflows/docker-publish.yml` |
| `api` | `rediverio/api` | `.github/workflows/docker-publish.yml` |

### Build Features

- **Multi-platform builds**: `linux/amd64` and `linux/arm64`
- **GitHub Actions cache**: Faster builds using layer caching
- **Automatic tagging**: Based on git tags or manual input
- **Environment support**: Staging and Production

---

## Prerequisites

### 1. Docker Hub Account

Create an account at [Docker Hub](https://hub.docker.com/).

### 2. Docker Hub Access Token

1. Go to [Docker Hub Security Settings](https://hub.docker.com/settings/security)
2. Click **New Access Token**
3. Name: `github-actions` (or any descriptive name)
4. Permissions: **Read & Write**
5. Copy the token (you won't see it again)

### 3. GitHub Repository Secrets

Add secrets to each repository:

1. Go to **Settings → Secrets and variables → Actions**
2. Click **New repository secret**
3. Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username |
| `DOCKERHUB_TOKEN` | Access token from step 2 |

---

## GitHub Actions Workflows

### Workflow File Location

```
ui/.github/workflows/docker-publish.yml
api/.github/workflows/docker-publish.yml
```

### Workflow Triggers

| Trigger | Description |
|---------|-------------|
| `push tags: v*` | Automatically when pushing version tags |
| `workflow_dispatch` | Manual trigger from GitHub UI |

### Build Stages

1. **Checkout**: Clone repository
2. **Set variables**: Determine version and environment
3. **Setup QEMU**: Enable multi-platform builds
4. **Setup Buildx**: Configure Docker Buildx
5. **Login**: Authenticate with Docker Hub
6. **Build & Push**: Build image and push to registry
7. **Summary**: Generate build report

---

## Manual Triggering

### From GitHub UI

1. Go to repository **Actions** tab
2. Select **Docker Publish** workflow
3. Click **Run workflow**
4. Fill in parameters:
   - **Version tag**: e.g., `v0.1.1` or `v0.1.1-staging`
   - **Environment**: `staging` or `production`
5. Click **Run workflow**

### Example Scenarios

**Staging build:**
```
Version: v0.1.1
Environment: staging
→ Tags: rediverio/ui:v0.1.1-staging, rediverio/ui:staging-latest
```

**Production build:**
```
Version: v0.1.1
Environment: production
→ Tags: rediverio/ui:v0.1.1, rediverio/ui:latest
```

---

## Tag-based Triggering

### Creating Tags

```bash
# Staging release
git tag v0.1.1-staging
git push origin v0.1.1-staging

# Production release
git tag v0.1.1
git push origin v0.1.1
```

### Tag Naming Convention

| Tag Format | Environment | Example |
|------------|-------------|---------|
| `v*.*.*-staging` | Staging | `v0.1.1-staging` |
| `v*.*.*` | Production | `v0.1.1` |

### Automatic Environment Detection

The workflow automatically detects the environment from the tag:

- Tags containing `-staging` → Staging environment
- Tags without `-staging` → Production environment

---

## Docker Hub Setup

### Repository Structure

```
rediverio/
├── api
│   ├── v0.1.0-staging
│   ├── v0.1.1-staging
│   ├── staging-latest
│   ├── v0.1.0
│   ├── v0.1.1
│   └── latest
│
└── ui
    ├── v0.1.0-staging
    ├── v0.1.1-staging
    ├── staging-latest
    ├── v0.1.0
    ├── v0.1.1
    └── latest
```

### Pulling Images

```bash
# Staging
docker pull rediverio/ui:v0.1.1-staging
docker pull rediverio/api:v0.1.1-staging

# Production
docker pull rediverio/ui:v0.1.1
docker pull rediverio/api:v0.1.1

# Latest
docker pull rediverio/ui:latest
docker pull rediverio/api:latest
```

---

## Environment Configuration

### GitHub Repository Variables

You can configure build-time variables in GitHub:

1. Go to **Settings → Secrets and variables → Actions → Variables**
2. Add these variables:

**For ui:**

| Variable | Description | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_APP_URL` | Public app URL | `https://app.rediver.io` |
| `NEXT_PUBLIC_AUTH_PROVIDER` | Auth provider | `local` |

### Using with docker-compose

Update version in your `.env` files:

```env
# .env.ui.staging
VERSION=v0.1.1-staging

# .env.api.staging
VERSION=v0.1.1-staging
```

Then deploy:

```bash
make staging-pull
make staging-restart
```

---

## Versioning Strategy

### Semantic Versioning

We follow [Semantic Versioning](https://semver.org/):

```
v{MAJOR}.{MINOR}.{PATCH}[-{PRERELEASE}]
```

| Part | When to increment |
|------|-------------------|
| MAJOR | Breaking changes |
| MINOR | New features (backward compatible) |
| PATCH | Bug fixes |
| PRERELEASE | Staging releases (`-staging`) |

### Release Process

1. **Development**: Work on `develop` branch
2. **Staging Release**:
   ```bash
   git checkout develop
   git pull origin develop
   git tag v0.1.1-staging
   git push origin v0.1.1-staging
   # → Triggers staging build
   ```
3. **Production Release**:
   ```bash
   git checkout main
   git merge develop
   git tag v0.1.1
   git push origin main --tags
   # → Triggers production build
   ```

---

## Troubleshooting

### Common Issues

#### 1. "Denied: requested access to the resource is denied"

**Cause**: Docker Hub credentials are incorrect or missing.

**Solution**:
1. Verify `DOCKERHUB_USERNAME` secret is correct
2. Verify `DOCKERHUB_TOKEN` is valid and has write permissions
3. Regenerate token if needed

#### 2. Build takes too long / runs out of memory

**Cause**: Building for multiple platforms is resource-intensive.

**Solution**:
- GitHub Actions runners have 7GB RAM (should be sufficient)
- If still failing, try building one platform at a time in workflow

#### 3. Cache not working

**Cause**: Cache might be invalidated.

**Solution**:
```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```
Make sure these options are in the workflow.

#### 4. "Resource not accessible by integration"

**Cause**: Workflow doesn't have required permissions.

**Solution**: Add permissions to workflow:
```yaml
permissions:
  contents: read
  packages: write
```

### Viewing Build Logs

1. Go to **Actions** tab in repository
2. Click on the workflow run
3. Click on **Build and Push** job
4. Expand steps to see detailed logs

### Re-running Failed Builds

1. Go to failed workflow run
2. Click **Re-run all jobs** or **Re-run failed jobs**

---

## Local Development

### Building Locally (if needed)

```bash
# Single platform (faster)
docker buildx build \
  --platform linux/amd64 \
  --target production \
  -t rediverio/ui:local \
  -f Dockerfile \
  .

# Multi-platform (slower, for testing)
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --target production \
  -t rediverio/ui:local \
  -f Dockerfile \
  .
```

### Testing Image Locally

```bash
# Run the image
docker run -p 3000:3000 rediverio/ui:local

# Check health
curl http://localhost:3000/api/health
```

---

## Quick Reference

### Commands Cheat Sheet

```bash
# Create staging release
git tag v0.1.1-staging && git push origin v0.1.1-staging

# Create production release
git tag v0.1.1 && git push origin v0.1.1

# Pull latest staging
docker pull rediverio/ui:staging-latest
docker pull rediverio/api:staging-latest

# Pull specific version
docker pull rediverio/ui:v0.1.1-staging
docker pull rediverio/api:v0.1.1-staging

# Deploy staging
VERSION=v0.1.1-staging make staging-pull && make staging-restart
```

### Useful Links

- [Docker Hub - rediverio](https://hub.docker.com/u/rediverio)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Docker Build Push Action](https://github.com/docker/build-push-action)

---

## Support

For issues with CI/CD:
1. Check workflow logs in GitHub Actions
2. Review this documentation
3. Open an issue in the respective repository
