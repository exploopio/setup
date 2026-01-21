# Agent Architecture

This document describes the unified agent architecture for the Rediver platform.

## Overview

The platform uses a **Single Table Inheritance (STI)** pattern with a unified `agents` table that supports four main component types through discriminator columns.

## Agent Types

| Type | Use Case | Execution Mode | Description |
|------|----------|----------------|-------------|
| **Runner** | CI/CD | `standalone` | One-shot scans, exits after completion |
| **Worker** | Production | `daemon` | Server-controlled daemon, polls for commands |
| **Collector** | Infrastructure | `daemon` | Data collection agent for cloud/infra inventory |
| **Sensor** | EASM | `daemon` | External attack surface monitoring |

### Runner

Runners are designed for CI/CD pipelines and one-shot scanning scenarios.

**Characteristics:**
- Executes scan and exits
- No persistent connection to server
- Reports results via push
- Can post PR/MR comments
- Best for: GitHub Actions, GitLab CI, Jenkins

**Example:**
```bash
# GitHub Actions
docker run --rm \
  -v "$(pwd)":/code:ro \
  -e API_URL=https://api.rediver.io \
  -e API_KEY=$REDIVER_API_KEY \
  rediverio/agent:ci \
  -tools semgrep,gitleaks,trivy-fs -target /code -push -comments
```

### Worker

Workers are long-running daemons controlled by the server.

**Characteristics:**
- Persistent WebSocket connection
- Receives scan commands from server
- Sends heartbeat for health monitoring
- Best for: Production scanning, managed infrastructure

**Example:**
```bash
# Server-controlled daemon
docker run -d \
  --name rediver-worker \
  --restart unless-stopped \
  -e API_URL=https://api.rediver.io \
  -e API_KEY=$REDIVER_API_KEY \
  -e AGENT_ID=$AGENT_ID \
  rediverio/agent:latest \
  -daemon -enable-commands -verbose
```

### Collector

Collectors are specialized agents for data gathering.

**Characteristics:**
- Collects infrastructure inventory
- Discovers cloud assets (AWS, GCP, Azure)
- Maps network topology
- Best for: Asset discovery, CSPM, CTEM

**Example:**
```bash
# Collector daemon
docker run -d \
  --name rediver-collector \
  --restart unless-stopped \
  -e API_URL=https://api.rediver.io \
  -e API_KEY=$REDIVER_API_KEY \
  -e AGENT_ID=$AGENT_ID \
  -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
  -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
  rediverio/agent:latest \
  -daemon -enable-commands -verbose
```

### Sensor

Sensors are specialized agents for external attack surface monitoring.

**Characteristics:**
- Monitors external-facing assets
- Performs reconnaissance and vulnerability detection
- Best for: EASM, attack surface management

**Example:**
```bash
# Sensor daemon
docker run -d \
  --name rediver-sensor \
  --restart unless-stopped \
  -e API_URL=https://api.rediver.io \
  -e API_KEY=$REDIVER_API_KEY \
  -e AGENT_ID=$AGENT_ID \
  rediverio/agent:latest \
  -daemon -enable-commands -verbose
```

## Database Schema

The unified `agents` table uses discriminator columns:

```sql
CREATE TABLE agents (
    id UUID PRIMARY KEY,
    tenant_id UUID NOT NULL REFERENCES tenants(id),
    name VARCHAR(255) NOT NULL,

    -- Type discriminator: runner, worker, collector, sensor
    type VARCHAR(50) NOT NULL CHECK (type IN ('runner', 'worker', 'collector', 'sensor')),

    -- Execution mode: standalone (one-shot) or daemon (long-running)
    execution_mode VARCHAR(20) DEFAULT 'standalone' CHECK (execution_mode IN ('standalone', 'daemon')),

    -- Capabilities: sast, sca, dast, secrets, iac, infra, collector, etc.
    capabilities TEXT[] DEFAULT '{}',

    -- Tools: semgrep, trivy, nuclei, gitleaks, etc.
    tools TEXT[] DEFAULT '{}',

    -- Admin-controlled status: active, disabled, revoked
    status VARCHAR(50) NOT NULL DEFAULT 'active',

    -- Automatic health (from heartbeat): unknown, online, offline, error
    health VARCHAR(20) DEFAULT 'unknown',

    -- ... other fields
);
```

## Type Mapping

| Type | Execution Mode | Description |
|------|----------------|-------------|
| `runner` | `standalone` | CI/CD one-shot scans |
| `worker` | `daemon` | Server-controlled daemon |
| `collector` | `daemon` | Data collection agent |
| `sensor` | `daemon` | External attack surface monitoring |

## API Types

```typescript
// TypeScript types
type AgentType = 'runner' | 'worker' | 'collector' | 'sensor';
type AgentStatus = 'active' | 'disabled' | 'revoked';  // Admin-controlled
type AgentHealth = 'unknown' | 'online' | 'offline' | 'error';  // Automatic
type ExecutionMode = 'standalone' | 'daemon';
```

```go
// Go types
type AgentType string
const (
    AgentTypeRunner    AgentType = "runner"
    AgentTypeWorker    AgentType = "worker"
    AgentTypeCollector AgentType = "collector"
    AgentTypeSensor    AgentType = "sensor"
)
```

## Status vs Health

The platform separates **admin-controlled status** from **automatic health**:

| Field | Control | Values | Purpose |
|-------|---------|--------|---------|
| `status` | Admin | `active`, `disabled`, `revoked` | Authentication access |
| `health` | Automatic | `unknown`, `online`, `offline`, `error` | Monitoring |

- **Status**: Determines if agent can authenticate
- **Health**: Based on heartbeat, for monitoring only

## Commands Table

The `commands` table supports different command types for each agent type:

| Command Type | Runner | Worker | Collector | Sensor |
|--------------|--------|--------|-----------|--------|
| `scan` | Yes | Yes | No | Yes |
| `collect` | No | No | Yes | No |
| `health_check` | Yes | Yes | Yes | Yes |
| `config_update` | No | Yes | Yes | Yes |
| `cancel` | Yes | Yes | Yes | Yes |

## Best Practices

### Choosing Agent Type

1. **Use Runner when:**
   - Integrating with CI/CD pipelines
   - Running one-time scans
   - Scanning PR/MR changes

2. **Use Worker when:**
   - Need server-controlled scanning
   - Running in production infrastructure
   - Require scheduled or on-demand scans

3. **Use Collector when:**
   - Discovering cloud assets
   - Building infrastructure inventory
   - Continuous exposure monitoring

4. **Use Sensor when:**
   - Monitoring external attack surface
   - Performing external reconnaissance
   - EASM and continuous external monitoring

### Deployment Recommendations

| Scenario | Type | Image | Mode |
|----------|------|-------|------|
| GitHub Actions | Runner | `rediverio/agent:ci` | One-shot |
| GitLab CI | Runner | `rediverio/agent:ci` | One-shot |
| Kubernetes | Worker | `rediverio/agent:latest` | Daemon |
| EC2 Instance | Worker | `rediverio/agent:latest` | Daemon |
| Cloud Asset Discovery | Collector | `rediverio/agent:latest` | Daemon |
| External Monitoring | Sensor | `rediverio/agent:latest` | Daemon |

## See Also

- [Agent README](https://github.com/rediverio/agent)
- [Docker Images](./DOCKER_IMAGES.md)
- [CI/CD Integration](./CICD.md)
