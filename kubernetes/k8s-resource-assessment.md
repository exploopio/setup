# OpenCTEM - Kubernetes Resource Assessment

> **Target**: ~100 concurrent users | Production + UAT
> **Date**: 2026-03-19
> **Architecture**: K8s (API + UI) | PostgreSQL + Redis server rieng
> **Environments**: Production (PG + Redis tach server) | UAT (PG + Redis chung 1 server)

---

## 1. Architecture Overview

```
                        ┌───────────────────────────────────────────────┐
                        │           Kubernetes Cluster                  │
                        │                                               │
  Users ──► Ingress ──► │  ┌──────────────┐     ┌──────────────┐        │
            (NGINX)     │  │  API (Go)    │     │  UI (Next.js)│        │
                        │  │  2-5 pods    │     │  2 pods      │        │
                        │  │  (HPA)       │     │              │        │
                        │  └──────┬───────┘     └──────────────┘        │
                        │         │                                     │
                        │  ┌──────┴───────┐                             │
                        │  │  Monitoring  │                             │
                        │  │  Prometheus  │                             │
                        │  │  Grafana     │                             │
                        │  └──────────────┘                             │
                        └─────────┬──────────────────────┬──────────────┘
                                  │ TCP/5432             │ TCP/6379
                                  ▼                      ▼
                        ┌─────────────────┐    ┌─────────────────┐
                        │  PostgreSQL 17  │    │   Redis 7       │
                        │  Server rieng   │    │   Server rieng  │
                        │                 │    │                 │
                        │  4 vCPU, 8GB    │    │  2 vCPU, 4GB    │
                        │  SSD 100GB      │    │  SSD 10GB       │
                        └─────────────────┘    └─────────────────┘
```

---

## 2. System Profile Summary

| Metric                        | Value                                       |
| ----------------------------- | ------------------------------------------- |
| API Endpoints                 | 100+ REST, 3 gRPC services                  |
| Database Tables               | 128                                         |
| Database Indexes              | 851+                                        |
| Background Controllers        | 10 (reconciliation loops, 1s-24h intervals) |
| Asynq Workers                 | 5 queues, concurrency=5                     |
| WebSocket Connections         | Up to 100 persistent                        |
| Max Concurrent HTTP Requests  | 1000 (configurable)                         |
| DB Connection Pool per pod    | 25 max open, 5 idle                         |
| Redis Connection Pool per pod | 10 (configurable up to 500)                 |

---

## 3. Workload Analysis

### 3.1 API Server (Go)

**CPU Profile:**

- HTTP request handling: ~100 users x 2-5 req/s peak = **200-500 RPS**
- 10 background controllers consuming CPU periodically (1s to 24h intervals)
- Asynq job processing: email, notifications, AI triage (concurrency=5)
- WebSocket hub: broadcasting events to ~100 connections
- JWT validation + RBAC permission checks on every request
- gRPC server for scanner agent communication

**Memory Profile:**

| Component                            | Memory        |
| ------------------------------------ | ------------- |
| Go runtime base                      | 30-50MB       |
| HTTP router + middleware stack       | ~20MB         |
| 10 controller goroutines             | ~10MB         |
| Asynq worker pool (5 queues)         | ~20MB         |
| WebSocket connections (100 users)    | ~50MB         |
| DB connection pool (25 conns x ~1MB) | ~25MB         |
| Redis connection pool (10 conns)     | ~5MB          |
| Permission cache (in-memory)         | ~10MB         |
| Request processing buffers           | 50-100MB      |
| **Estimated working set per pod**    | **250-400MB** |

**Concurrency Model:**

- `MaxConcurrentRequests`: 1000 (semaphore-limited)
- Rate limit: 100 RPS burst 200 (per-user token bucket)
- Read/Write timeout: 15s each
- Graceful shutdown supported

### 3.2 UI Server (Next.js 16)

**CPU Profile:**

- Server-side rendering (React 19 + React Compiler)
- Static asset serving (CSS, JS bundles, cached by browser)
- API proxy pass-through to backend
- 100 users = ~50-100 SSR requests/s (page navigations)

**Memory Profile:**

| Component                         | Memory         |
| --------------------------------- | -------------- |
| Node.js runtime                   | 80-120MB       |
| Next.js SSR cache                 | 50-100MB       |
| 929 TSX files compiled bundle     | included above |
| **Estimated working set per pod** | **150-250MB**  |

### 3.3 PostgreSQL (Server rieng)

**CPU Profile:**

- Multi-tenant queries always filter by `tenant_id` (index scans)
- 851+ indexes = heavy index maintenance on writes
- JSONB property queries require CPU for parsing
- Background controller queries (audit retention, data expiration) chay periodic
- 3 audit protection triggers fire on every write
- 13 CHECK constraints validation on every row insert/update

**Memory Profile:**

| Component                                      | Memory    |
| ---------------------------------------------- | --------- |
| `shared_buffers` (25% RAM)                     | 2GB       |
| `effective_cache_size` (75% RAM)               | 6GB       |
| 128 tables x index metadata                    | ~200MB    |
| Connection overhead (50-75 conns x ~10MB)      | 500-750MB |
| Sort/hash operations (`work_mem` x concurrent) | ~256MB    |
| `maintenance_work_mem` (VACUUM, INDEX)         | 512MB     |
| WAL buffers                                    | 64MB      |
| **Minimum recommended RAM**                    | **8GB**   |

**Storage Profile:**

| Data                                    | Size                              |
| --------------------------------------- | --------------------------------- |
| Schema + 851 indexes baseline           | ~500MB                            |
| Assets (~10K records)                   | ~100MB                            |
| Findings/vulnerabilities (~50K records) | ~500MB                            |
| Audit logs (~100K records/month)        | ~200MB/month                      |
| Scan results + commands                 | ~200MB                            |
| WAL files rotation                      | 1-2GB                             |
| **Year 1 estimate**                     | **~5-8GB data + indexes**         |
| **Recommended disk**                    | **100GB SSD (room for 3+ years)** |

**Tai sao PostgreSQL la bottleneck chinh:**

1. 128 tables + 851 indexes: moi INSERT/UPDATE phai cap nhat nhieu indexes
2. Multi-tenant queries: moi query deu filter `tenant_id` → extra index lookups
3. JSONB columns: cac bang findings, assets dung JSONB properties → CPU-intensive
4. Audit triggers: 3 triggers fire on every write
5. 13 CHECK constraints: validation tren moi row
6. Background controllers: audit_retention, data_expiration chay heavy DELETE
7. Concurrent connections: 2-5 API pods x 25 conns = 50-125 connections dong thoi

### 3.4 Redis (Server rieng)

**Memory Breakdown:**

| Component                              | Memory        | TTL             |
| -------------------------------------- | ------------- | --------------- |
| User sessions (100 x 2KB)              | ~200KB        | 30 min          |
| Permission cache (100 x 5KB)           | ~500KB        | 5 min           |
| Permission versions (100 x 1KB)        | ~100KB        | 30 days         |
| Rate limit buckets                     | ~1MB          | Rolling window  |
| Asynq queues (5 queues + task state)   | 10-50MB       | Until processed |
| Pub/Sub channels (WebSocket broadcast) | ~5MB          | Transient       |
| AOF buffer                             | 20-50MB       | Rotating        |
| **Total estimated working set**        | **~80-150MB** | -               |

> Redis workload rat nhe. 4GB RAM la du thua rat nhieu, nhung cho headroom
> khi scale users len va Asynq queue depth tang.

---

## 4. Resource Allocation Plan

### 4.1 Kubernetes Cluster (chi chay API + UI + Monitoring)

```
+─────────────────────────────────────────────────────────────────────────+
│                    Kubernetes Cluster                                   │
│                                                                         │
│  Node Pool: 2x t3.xlarge (4 vCPU, 16GB) across 2 AZs                  │
│  Usable (sau khi tru system): ~6.4 vCPU, 26GB RAM                     │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  API Deployment (2-5 pods via HPA)                                │  │
│  │  Per pod: Request 500m/512Mi | Limit 2/1Gi                       │  │
│  │  Steady state (2 pods): 1 CPU, 1Gi                               │  │
│  │  Peak (5 pods): 2.5 CPU, 2.5Gi                                  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  UI Deployment (2 pods)                                           │  │
│  │  Per pod: Request 200m/256Mi | Limit 1/512Mi                     │  │
│  │  Total: 400m CPU, 512Mi                                          │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Ingress Controller (NGINX, 2 pods)                               │  │
│  │  Total: 200m CPU, 256Mi                                           │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  Monitoring (Prometheus + Grafana)                                │  │
│  │  Total: 300m CPU, 768Mi, PVC 20Gi                                │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │  System (kube-system, CoreDNS, metrics-server, cert-manager)     │  │
│  │  Reserved: ~500m CPU, 512Mi                                       │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│  Total Requests: ~2.4 vCPU, ~3Gi RAM (steady state)                    │
│  Headroom: ~4 vCPU, ~23Gi (cho HPA burst + system spikes)             │
+─────────────────────────────────────────────────────────────────────────+
```

### 4.2 PostgreSQL Server (rieng)

```
+─────────────────────────────────────────────────────────────────────────+
│  PostgreSQL 17 - Dedicated Server                                       │
│                                                                         │
│  Hardware:                                                              │
│  ├── CPU: 4 vCPU (minimum) | 8 vCPU (recommended)                     │
│  ├── RAM: 8GB (minimum) | 16GB (recommended, cho buffer cache)         │
│  ├── Disk: 100GB NVMe SSD (IOPS: 3000+)                               │
│  └── Network: 1Gbps+ (low latency to K8s cluster, < 1ms)              │
│                                                                         │
│  Equivalent cloud instances:                                            │
│  ├── AWS: db.m6i.xlarge (4 vCPU, 16GB) hoac r6i.large (2 vCPU, 16GB) │
│  ├── GCP: db-custom-4-16384                                            │
│  ├── Azure: Standard_E4ds_v5                                           │
│  └── Bare metal: Xeon E-2374G + 16GB ECC + NVMe                       │
│                                                                         │
│  Storage layout:                                                        │
│  ├── /var/lib/postgresql/data: 100GB NVMe (data + indexes)             │
│  ├── /var/lib/postgresql/wal: 20GB NVMe (WAL, separate disk if possible)│
│  └── /backup: 200GB HDD/S3 (daily pg_dump + WAL archive)              │
+─────────────────────────────────────────────────────────────────────────+
```

### 4.3 Redis Server (rieng)

```
+─────────────────────────────────────────────────────────────────────────+
│  Redis 7 - Dedicated Server                                             │
│                                                                         │
│  Hardware:                                                              │
│  ├── CPU: 2 vCPU (du cho workload hien tai)                           │
│  ├── RAM: 4GB (working set ~150MB, con lai cho OS + AOF rewrite)       │
│  ├── Disk: 10GB SSD (AOF persistence)                                  │
│  └── Network: 1Gbps (low latency to K8s cluster, < 1ms)               │
│                                                                         │
│  Equivalent cloud instances:                                            │
│  ├── AWS: cache.m6g.large (2 vCPU, 6.38GB) hoac t3.medium (2 vCPU, 4GB)│
│  ├── GCP: M1 (4GB)                                                     │
│  ├── Azure: Standard C2                                                 │
│  └── Bare metal: Any 2-core + 4GB RAM + SSD                            │
+─────────────────────────────────────────────────────────────────────────+
```

### 4.4 Resource Summary Table

| Component      | vCPU      | RAM         | Disk                  | Network |
| -------------- | --------- | ----------- | --------------------- | ------- |
| **K8s Node 1** | 4         | 16GB        | 50GB (OS+images)      | 1Gbps   |
| **K8s Node 2** | 4         | 16GB        | 50GB (OS+images)      | 1Gbps   |
| **PostgreSQL** | 4-8       | 8-16GB      | 100GB NVMe + 20GB WAL | 1Gbps   |
| **Redis**      | 2         | 4GB         | 10GB SSD              | 1Gbps   |
| **Total**      | **14-18** | **44-52GB** | **280GB**             | -       |

---

## 5. K8s Resource Specifications

### 5.1 Pod Resources

| Service        | Replicas   | CPU Request | CPU Limit | Mem Request | Mem Limit | Priority |
| -------------- | ---------- | ----------- | --------- | ----------- | --------- | -------- |
| **API**        | 2-5 (HPA)  | 500m        | 2         | 512Mi       | 1Gi       | Critical |
| **UI**         | 2          | 200m        | 1         | 256Mi       | 512Mi     | High     |
| **Migrations** | Job (init) | 100m        | 500m      | 64Mi        | 256Mi     | Low      |
| **Ingress**    | 2          | 100m        | 500m      | 128Mi       | 256Mi     | Critical |
| **Prometheus** | 1          | 200m        | 1         | 512Mi       | 1Gi       | Medium   |
| **Grafana**    | 1          | 100m        | 500m      | 256Mi       | 512Mi     | Medium   |

### 5.2 K8s Cluster Totals (steady state, API = 2 pods)

| Resource        | Requests (Guaranteed) | Limits (Burstable) |
| --------------- | --------------------- | ------------------ |
| **CPU**         | ~1.7 vCPU             | ~6.5 vCPU          |
| **Memory**      | ~1.7Gi                | ~4Gi               |
| **PVC Storage** | 20Gi (Prometheus)     | -                  |

> K8s cluster rat nhe khi DB va Redis o ngoai. 2 nodes t3.xlarge thua suc,
> tham chi co the dung 2x t3.large (2 vCPU, 8GB) neu khong can monitoring stack nang.

### 5.3 So sanh voi Helm Chart hien tai

| Setting             | Hien tai (values.yaml) | Khuyen nghi (100 users) | Thay doi      |
| ------------------- | ---------------------- | ----------------------- | ------------- |
| API CPU request     | 250m                   | **500m**                | +100%         |
| API Memory request  | 256Mi                  | **512Mi**               | +100%         |
| API CPU limit       | 2                      | 2                       | Giu nguyen    |
| API Memory limit    | 1Gi                    | 1Gi                     | Giu nguyen    |
| API HPA maxReplicas | 10                     | **5**                   | -50%          |
| UI CPU request      | 100m                   | **200m**                | +100%         |
| UI Memory request   | 128Mi                  | **256Mi**               | +100%         |
| `postgres.enabled`  | true                   | **false**               | DB o ngoai    |
| `redis.enabled`     | true                   | **false**               | Redis o ngoai |

---

## 6. values.yaml Khuyen Nghi

```yaml
# === OpenCTEM Production values (100 users) ===
# === PostgreSQL + Redis = external servers ===

api:
  replicaCount: 2
  image:
    repository: openctemio/api
    tag: "latest" # Thay bang version tag cu the
    pullPolicy: IfNotPresent
  service:
    type: ClusterIP
    port: 8080
    grpcPort: 9090
  resources:
    requests:
      cpu: 500m # was: 250m → dam bao scheduling on dich
      memory: 512Mi # was: 256Mi → phu hop working set 250-400MB
    limits:
      cpu: "2" # unchanged → burst cho scan/report heavy
      memory: 1Gi # unchanged → OOM protection
  env:
    APP_ENV: production
    LOG_LEVEL: info
    LOG_FORMAT: json
    SERVER_PORT: "8080"
    GRPC_PORT: "9090"

    # Rate limiting (tang cho 100 users)
    RATE_LIMIT_ENABLED: "true"
    RATE_LIMIT_RPS: "200" # was: 100
    RATE_LIMIT_BURST: "400" # was: 200

    # Auth
    AUTH_PROVIDER: local
    AUTH_REQUIRE_EMAIL_VERIFICATION: "false"
    AUTH_ALLOW_REGISTRATION: "true"

    # DB connection pool (tuned for multi-pod)
    DB_MAX_OPEN_CONNS: "20" # was: 25 (giam per pod, vi co 2-5 pods)
    DB_MAX_IDLE_CONNS: "10" # was: 5 (giam connection churn)
    DB_CONN_MAX_LIFETIME: "300s" # 5min - unchanged

    # External DB connection
    DB_HOST: "pg-server.internal" # ← IP/hostname PostgreSQL server
    DB_PORT: "5432"
    DB_NAME: "openctem"
    DB_SSLMODE: "require" # ← BAT BUOC cho production

    # Redis connection pool
    REDIS_POOL_SIZE: "20" # was: 10 (nhieu concurrent cache ops hon)
    REDIS_HOST: "redis-server.internal" # ← IP/hostname Redis server
    REDIS_PORT: "6379"

    # Concurrency
    MAX_CONCURRENT_REQUESTS: "500" # was: 1000 (per pod, 2 pods = 1000 total)

  envFromSecret:
    openctem-api-secrets # JWT_SECRET, DB_PASSWORD, REDIS_PASSWORD,
    # APP_ENCRYPTION_KEY

  readinessProbe:
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 10
    periodSeconds: 10
  livenessProbe:
    httpGet:
      path: /health
      port: 8080
    initialDelaySeconds: 30
    periodSeconds: 30

  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5 # was: 10 (100 users khong can 10)
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80

ui:
  replicaCount: 2
  image:
    repository: openctemio/ui
    tag: "latest"
    pullPolicy: IfNotPresent
  service:
    type: ClusterIP
    port: 3000
  resources:
    requests:
      cpu: 200m # was: 100m
      memory: 256Mi # was: 128Mi
    limits:
      cpu: "1"
      memory: 512Mi
  env:
    NEXT_PUBLIC_API_URL: "" # Set via ingress
  readinessProbe:
    httpGet:
      path: /api/health
      port: 3000
    initialDelaySeconds: 10
    periodSeconds: 10
  livenessProbe:
    httpGet:
      path: /api/health
      port: 3000
    initialDelaySeconds: 30
    periodSeconds: 30

# === EXTERNAL SERVICES - Disable in-cluster ===
postgres:
  enabled: false # ← PostgreSQL chay tren server rieng

redis:
  enabled: false # ← Redis chay tren server rieng

# Ingress
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "100"
    nginx.ingress.kubernetes.io/rate-limit-window: "1m"
    nginx.ingress.kubernetes.io/proxy-body-size: "10m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "10"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "30"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "30"
    # WebSocket support
    nginx.ingress.kubernetes.io/proxy-http-version: "1.1"
    nginx.ingress.kubernetes.io/upstream-hash-by: "$remote_addr"
    nginx.ingress.kubernetes.io/enable-gzip: "true"
  hosts:
    - host: openctem.example.com
      paths:
        - path: /
          pathType: Prefix
          service: ui
        - path: /api
          pathType: Prefix
          service: api
        - path: /metrics
          pathType: Prefix
          service: api
  tls:
    - secretName: openctem-tls
      hosts:
        - openctem.example.com

# Migrations (chay nhu init container cua API)
migrations:
  image:
    repository: migrate/migrate
    tag: "v4.17.0"
  resources:
    requests:
      cpu: 100m
      memory: 64Mi
    limits:
      cpu: 500m
      memory: 256Mi

# Service Account
serviceAccount:
  create: true
  name: ""
  annotations: {}

# Pod Disruption Budget
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# Network Policy
networkPolicy:
  enabled: true # ← BAT nen enable cho production
```

---

## 7. PostgreSQL Server Configuration

### 7.1 postgresql.conf (cho 8-16GB RAM server)

```ini
# ============================================================
# OpenCTEM PostgreSQL 17 - Production Config (100 users)
# Server: 4-8 vCPU, 8-16GB RAM, NVMe SSD
# ============================================================

# --- Connection ---
listen_addresses = '*'
port = 5432
max_connections = 150
# Budget: API pods (20 x 5 = 100) + Monitoring (10) + Admin (10) + Buffer (30)

# --- Memory (assuming 16GB RAM) ---
shared_buffers = 4GB                    # 25% of RAM
effective_cache_size = 12GB             # 75% of RAM
work_mem = 32MB                         # Per-sort/hash op (128 tables, complex JOINs)
maintenance_work_mem = 512MB            # VACUUM, CREATE INDEX
wal_buffers = 64MB                      # WAL write buffer
huge_pages = try                        # Neu OS support

# --- Memory (if 8GB RAM, use these instead) ---
# shared_buffers = 2GB
# effective_cache_size = 6GB
# work_mem = 16MB
# maintenance_work_mem = 256MB

# --- WAL & Write Performance ---
wal_level = replica                     # Cho future streaming replication
max_wal_size = 2GB
min_wal_size = 512MB
checkpoint_completion_target = 0.9
checkpoint_timeout = 10min

# --- Query Optimizer (SSD optimized) ---
random_page_cost = 1.1                  # SSD: gần sequential cost
effective_io_concurrency = 200          # NVMe SSD concurrent I/O
seq_page_cost = 1.0
default_statistics_target = 100         # Better query plans cho 128 tables

# --- Parallel Query (tan dung multi-core) ---
max_parallel_workers_per_gather = 2     # 2 workers per query
max_parallel_workers = 4                # Total parallel workers
max_parallel_maintenance_workers = 2    # Parallel VACUUM/INDEX
parallel_tuple_cost = 0.01
parallel_setup_cost = 100

# --- Multi-tenant Optimization ---
enable_partitionwise_join = on
enable_partitionwise_aggregate = on
jit = on                                # JIT cho complex queries

# --- Autovacuum (128 tables can tuning) ---
autovacuum = on
autovacuum_max_workers = 4              # was 3 (128 tables can nhieu hon)
autovacuum_naptime = 30s                # was 1min (check more frequently)
autovacuum_vacuum_threshold = 50
autovacuum_vacuum_scale_factor = 0.05   # was 0.2 (vacuum som hon)
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.02  # was 0.1 (analyze som hon)
autovacuum_vacuum_cost_delay = 2ms      # was 20ms (vacuum nhanh hon)

# --- Logging ---
log_destination = 'stderr'
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_rotation_age = 1d
log_rotation_size = 100MB
log_min_duration_statement = 500        # Log queries > 500ms
log_line_prefix = '%t [%p] %u@%d '
log_statement = 'ddl'                   # Log DDL statements
log_checkpoints = on
log_connections = off                   # Too noisy with connection pooling
log_disconnections = off
log_lock_waits = on
log_temp_files = 10MB

# --- Security ---
ssl = on
ssl_cert_file = '/etc/postgresql/server.crt'
ssl_key_file = '/etc/postgresql/server.key'
password_encryption = scram-sha-256

# --- Replication (prepared for future replica) ---
max_wal_senders = 5
max_replication_slots = 5
hot_standby = on
```

### 7.2 pg_hba.conf

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     scram-sha-256

# K8s cluster subnet (thay bang subnet that)
host    openctem        openctem        10.0.0.0/16             scram-sha-256

# Monitoring
host    openctem        monitoring      10.0.0.0/16             scram-sha-256

# Replication (future)
host    replication     replicator      10.0.0.0/16             scram-sha-256

# Deny all others
host    all             all             0.0.0.0/0               reject
```

### 7.3 Connection Pool Strategy

```
                     K8s Cluster
┌──────────────────────────────────────────────┐
│                                              │
│  API Pod 1 ──[20 conns]──┐                   │
│  API Pod 2 ──[20 conns]──┤                   │
│  API Pod 3 ──[20 conns]──┤  (HPA burst)     │
│  API Pod 4 ──[20 conns]──┤                   │
│  API Pod 5 ──[20 conns]──┤                   │
│                           │                  │
│  Prometheus ──[5 conns]───┤                  │
│  Migration job ──[1 conn]─┤                  │
│                           │                  │
└───────────────────────────┤──────────────────┘
                            │
                            ▼
                  PostgreSQL Server
                  max_connections = 150

Scenario Analysis:
─────────────────────────────────────────────────
  2 API pods (steady):  2×20 + 5 + 1 = 46/150  (31% utilization) ✓
  3 API pods (normal):  3×20 + 5 + 1 = 66/150  (44% utilization) ✓
  5 API pods (peak):    5×20 + 5 + 1 = 106/150 (71% utilization) ✓
  Buffer remaining:     44 connections           (cho admin, backup, etc.)
```

> **Luu y**: Neu API scale > 5 pods trong tuong lai, can giam `DB_MAX_OPEN_CONNS`
> hoac deploy PgBouncer giua K8s va PostgreSQL server.

### 7.4 Backup Strategy

```bash
# Daily full backup (chay bang cron 2:00 AM)
pg_dump -Fc -Z 6 openctem > /backup/openctem_$(date +%Y%m%d).dump

# WAL archiving (continuous, cho Point-in-Time Recovery)
archive_mode = on
archive_command = 'cp %p /backup/wal/%f'

# Retention: 7 daily + 4 weekly + 3 monthly
# Test restore monthly!
```

---

## 8. Redis Server Configuration

### 8.1 redis.conf

```conf
# ============================================================
# OpenCTEM Redis 7 - Production Config (100 users)
# Server: 2 vCPU, 4GB RAM, SSD
# ============================================================

# --- Network ---
bind 0.0.0.0
port 6379
protected-mode yes
requirepass <REDIS_PASSWORD>        # Set strong password

# TLS (khuyen nghi cho production)
# tls-port 6380
# tls-cert-file /etc/redis/redis.crt
# tls-key-file /etc/redis/redis.key

# --- Memory ---
maxmemory 2gb                       # 50% of 4GB (con lai cho OS + AOF rewrite)
maxmemory-policy allkeys-lru        # Evict LRU keys khi full

# --- Persistence (Asynq can durability) ---
appendonly yes
appendfsync everysec                # Fsync moi giay (max 1s data loss)
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 128mb
aof-use-rdb-preamble yes            # Faster AOF rewrite

# RDB snapshots (backup supplement)
save 900 1                          # Save if 1 key changed in 15min
save 300 10                         # Save if 10 keys changed in 5min
save 60 10000                       # Save if 10000 keys changed in 1min
dbfilename dump.rdb
dir /var/lib/redis

# --- Connection ---
timeout 300                         # Close idle after 5min
tcp-keepalive 60
maxclients 256                      # API(20×5) + Asynq + Monitoring + buffer

# --- Performance ---
hz 10
dynamic-hz yes
lazyfree-lazy-eviction yes          # Non-blocking eviction
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
lazyfree-lazy-user-del yes

# --- Slow Log ---
slowlog-log-slower-than 10000       # Log commands > 10ms
slowlog-max-len 128

# --- Security ---
rename-command FLUSHDB ""           # Disable dangerous commands
rename-command FLUSHALL ""
rename-command DEBUG ""
```

### 8.2 Redis Connection Budget

```
API Pod 1 ──[20 pool + 5 asynq]──┐
API Pod 2 ──[20 pool + 5 asynq]──┤
API Pod 3 ──[20 pool + 5 asynq]──┤  (HPA burst)
API Pod 4 ──[20 pool + 5 asynq]──┤
API Pod 5 ──[20 pool + 5 asynq]──┤
                                   │
Prometheus ──[2 conns]─────────────┤
                                   │
                                   ▼
                          Redis Server
                          maxclients = 256

Peak: 5×25 + 2 = 127/256 (50% utilization) ✓
```

---

## 9. Network Architecture

### 9.1 Traffic Flow & Latency Requirements

```
                    Internet
                       │
                       ▼
              ┌────────────────┐
              │  Load Balancer │  (Cloud LB hoac bare-metal HAProxy)
              │  Public IP     │
              └────────┬───────┘
                       │ TLS termination
                       ▼
              ┌────────────────┐
              │ Ingress NGINX  │  K8s Cluster
              │ (2 replicas)   │
              └───┬────────┬───┘
                  │        │
            /api  │        │ /
                  ▼        ▼
           ┌──────────┐ ┌──────────┐
           │ API pods │ │ UI pods  │
           │ (2-5)    │ │ (2)      │
           └────┬─┬───┘ └──────────┘
                │ │
    ┌───────────┘ └───────────┐
    │ < 1ms RTT               │ < 1ms RTT
    ▼                         ▼
┌──────────┐           ┌──────────┐
│ PG Server│           │ Redis    │
│ (private │           │ Server   │
│  network)│           │ (private │
└──────────┘           │  network)│
                       └──────────┘
```

### 9.2 Bandwidth Estimation

```
100 users x 2-5 req/s (peak) = 200-500 RPS

Traffic breakdown:
─────────────────────────────────────────────────
External (user-facing):
  API responses:     avg 5KB  x 500 RPS  = 2.5 MB/s
  SSR pages:         avg 50KB x 50 RPS   = 2.5 MB/s
  Static assets:     avg 200KB x 10 RPS  = 2.0 MB/s (cached)
  WebSocket frames:  avg 100B x 10/s x 100 = 0.1 MB/s
  Total external:    ~7 MB/s peak (~60 Mbps)

Internal (K8s ↔ DB/Redis):
  DB queries:        avg 2KB  x 1000 qps = 2.0 MB/s
  DB responses:      avg 10KB x 1000 qps = 10.0 MB/s
  Redis commands:    avg 500B x 2000 cps = 1.0 MB/s
  Total internal:    ~13 MB/s peak (~110 Mbps)

Network requirement:
  K8s nodes:     1Gbps (du thua)
  PG Server:     1Gbps (du thua)
  Redis Server:  1Gbps (du thua)
```

### 9.3 Network Latency yeu cau

| Path             | Max Latency | Ly do                                        |
| ---------------- | ----------- | -------------------------------------------- |
| K8s ↔ PostgreSQL | **< 1ms**   | Moi API request = 2-5 DB queries, latency x5 |
| K8s ↔ Redis      | **< 0.5ms** | Permission check + session trên moi request  |
| User ↔ Ingress   | < 100ms     | UX acceptable threshold                      |

> **QUAN TRONG**: PostgreSQL va Redis server PHAI cung datacenter/VPC voi K8s cluster.
> Cross-region latency (5-50ms) se khien API response time tang gap 10-50x.

---

## 10. HPA Configuration

### 10.1 API Server HPA

```yaml
# Da co trong hpa.yaml - chi can dieu chinh maxReplicas
autoscaling:
  enabled: true
  minReplicas: 2 # HA: luon co it nhat 2 pods
  maxReplicas: 5 # 100 users khong can 10
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 80

# Scale behavior (giu nguyen)
# Scale up:   +2 pods / 60s  (phan ung nhanh voi traffic spike)
# Scale down: -1 pod / 60s   (stabilization 300s, tranh flapping)
```

**Giai thich nguong:**

- CPU 70%: Request=500m → trigger khi pod dung 350m → ~150-200 RPS/pod
- Memory 80%: Request=512Mi → trigger khi dung ~410Mi → phat hien memory pressure som
- Max 5 pods: moi pod xu ly 20-30 users concurrent, 5 pods = 100-150 users

### 10.2 UI HPA

```yaml
# Khong can HPA cho 100 users
# 2 static replicas du cho SSR load
# Enable khi: UI response time > 500ms sustained
autoscaling:
  enabled: false
```

---

## 11. Monitoring & Alerts

### 11.1 Critical Alerts

| Alert                | Condition             | Severity | Action                                |
| -------------------- | --------------------- | -------- | ------------------------------------- |
| API High Latency     | p99 > 2s for 5min     | Critical | Check DB connections, slow queries    |
| API Error Rate       | 5xx > 1% for 5min     | Critical | Check logs, DB/Redis health           |
| API Pod OOMKilled    | Any occurrence        | Critical | Tang memory limit                     |
| API CrashLoop        | > 3 restarts/5min     | Critical | Check logs immediately                |
| DB CPU > 80%         | Sustained 10min       | Warning  | Review slow queries, consider upgrade |
| DB Connections > 80% | > 120 of 150          | Warning  | Giam pool size hoac add PgBouncer     |
| DB Storage > 80%     | > 80GB of 100GB       | Warning  | Expand disk                           |
| DB Replication Lag   | > 1s (khi co replica) | Warning  | Check network, write load             |
| Redis Memory > 70%   | > 1.4GB of 2GB        | Warning  | Check key distribution                |
| Redis Latency > 10ms | p99 sustained         | Warning  | Check slow commands (`SLOWLOG`)       |
| Node CPU > 85%       | Sustained 10min       | Warning  | Scale node pool                       |
| Node Memory > 90%    | Sustained 5min        | Critical | Scale node pool hoac evict pods       |
| PVC > 85%            | Storage nearly full   | Warning  | Expand PVC                            |
| SSL Cert Expiry      | < 14 days             | Warning  | Check cert-manager                    |

### 11.2 Capacity Planning Queries (Prometheus)

```promql
# API pods can thiet (uoc tinh)
ceil(sum(rate(http_requests_total[5m])) / 200)

# DB connection utilization
sum(pg_stat_activity_count) / pg_settings_max_connections * 100

# Redis memory usage percentage
redis_memory_used_bytes / redis_memory_max_bytes * 100

# API memory working set (kiem tra OOM risk)
container_memory_working_set_bytes{container="api"} / container_spec_memory_limit_bytes * 100

# Khi nao can scale len tier tiep theo
# Trigger: bat ky dieu nao sau day keo dai 1 tuan
# - API HPA consistently at max replicas (5/5)
# - DB CPU > 70% average
# - API p99 latency > 1s
# - User count approaching 150
```

---

## 12. Security Considerations

### 12.1 Network Security

```
┌─────────────────────────────────────────────────────┐
│                  Private Network / VPC               │
│                                                      │
│  ┌──────────────────┐  Firewall rules:              │
│  │ K8s Cluster      │                                │
│  │ Subnet: 10.0.1.0 │──► PG:5432 (only from K8s)   │
│  │                   │──► Redis:6379 (only from K8s) │
│  └──────────────────┘                                │
│                                                      │
│  ┌──────────────────┐  Firewall rules:              │
│  │ PG Server        │                                │
│  │ Subnet: 10.0.2.0 │──► Inbound: 5432 from 10.0.1.0│
│  │                   │──► Outbound: deny all         │
│  └──────────────────┘                                │
│                                                      │
│  ┌──────────────────┐  Firewall rules:              │
│  │ Redis Server     │                                │
│  │ Subnet: 10.0.3.0 │──► Inbound: 6379 from 10.0.1.0│
│  │                   │──► Outbound: deny all         │
│  └──────────────────┘                                │
└─────────────────────────────────────────────────────┘
```

### 12.2 Checklist bao mat

- [ ] PostgreSQL: SSL enabled (`DB_SSLMODE=require`)
- [ ] PostgreSQL: `scram-sha-256` authentication (not `md5`)
- [ ] PostgreSQL: `pg_hba.conf` chi cho phep K8s subnet
- [ ] Redis: `requirepass` set strong password
- [ ] Redis: Disable dangerous commands (FLUSHDB, FLUSHALL, DEBUG)
- [ ] Redis: Bind chi K8s subnet (khong bind 0.0.0.0 tren public)
- [ ] K8s: NetworkPolicy enabled (chi API pods truy cap DB/Redis)
- [ ] K8s: Secrets encrypted at rest (EncryptionConfiguration)
- [ ] K8s: Pod SecurityContext (runAsNonRoot, readOnlyRootFilesystem)
- [ ] K8s: RBAC - ServiceAccount toi thieu quyen
- [ ] Ingress: TLS 1.2+ only
- [ ] Ingress: Rate limiting enabled
- [ ] All: Private network, khong expose DB/Redis ra internet

---

## 13. Growth Path

| Users              | API Pods       | PG Server                   | Redis Server    | K8s Nodes        | Est. Cost/mo  |
| ------------------ | -------------- | --------------------------- | --------------- | ---------------- | ------------- |
| **50**             | 2              | 4 vCPU, 8GB, 50GB           | 2 vCPU, 2GB     | 2x t3.large      | ~$300         |
| **100** (hien tai) | 2-5            | **4-8 vCPU, 8-16GB, 100GB** | **2 vCPU, 4GB** | **2x t3.xlarge** | **~$400-500** |
| **250**            | 3-6            | 8 vCPU, 32GB, 200GB         | 4 vCPU, 8GB     | 3x t3.xlarge     | ~$800         |
| **500**            | 4-8            | 16 vCPU, 64GB + replica     | 4 vCPU, 8GB     | 4x m6i.xlarge    | ~$1,500       |
| **1000+**          | 5-10 + workers | 32 vCPU, 128GB + replica    | Redis Sentinel  | 6x m6i.xlarge    | ~$3,000+      |

### Milestone Actions

| Milestone  | Action                                                      |
| ---------- | ----------------------------------------------------------- |
| 150 users  | Tang maxReplicas len 7, review DB slow queries              |
| 250 users  | Deploy PgBouncer, tang PG RAM len 32GB                      |
| 500 users  | Tach api-web va api-worker, add PG read replica             |
| 1000 users | Redis Sentinel, dedicated node pools, CDN cho static assets |

---

## 14. Deployment Checklist

### Pre-deployment

- [ ] Setup PostgreSQL server theo Section 7
- [ ] Setup Redis server theo Section 8
- [ ] Verify network connectivity: K8s ↔ PG (< 1ms), K8s ↔ Redis (< 0.5ms)
- [ ] Tao K8s cluster voi 2 nodes t3.xlarge
- [ ] Setup container registry, build production images
- [ ] Tao K8s Secrets: `openctem-api-secrets` (JWT, DB password, encryption key, Redis password)
- [ ] Setup DNS + cert-manager + Let's Encrypt
- [ ] Apply NetworkPolicy (chi API pods → DB/Redis)

### Deployment

- [ ] Apply values.yaml theo Section 6
- [ ] `helm install openctem ./setup/kubernetes/helm/openctem -f values-production.yaml`
- [ ] Verify migrations thanh cong: `kubectl logs <api-pod> -c migrate`
- [ ] Run bootstrap-admin job
- [ ] Test: `curl https://openctem.example.com/api/health`
- [ ] Test WebSocket connectivity
- [ ] Test RBAC: Owner, Admin, Member, Viewer roles
- [ ] Verify HPA: `kubectl get hpa`

### Post-deployment

- [ ] Deploy Prometheus + Grafana (monitoring stack)
- [ ] Import dashboards (API latency, PG stats, Redis stats)
- [ ] Configure alerts theo Section 11.1
- [ ] Setup PG backup: daily pg_dump + WAL archiving
- [ ] Load test: 100 concurrent users, verify p99 < 2s
- [ ] Setup log aggregation (Loki/ELK)
- [ ] Document runbook cho on-call team
- [ ] Schedule monthly: backup restore test, security audit

---

## 15. Summary

| Component          | Spec                             | Note                                           |
| ------------------ | -------------------------------- | ---------------------------------------------- |
| **K8s Cluster**    | 2x t3.xlarge (4 vCPU, 16GB)      | Chi chay API + UI + Monitoring                 |
| **API Pods**       | 2-5 (HPA), 500m/1Gi per pod      | Background controllers + Asynq workers inclued |
| **UI Pods**        | 2 static, 200m/512Mi per pod     | SSR + static serving                           |
| **PostgreSQL**     | 4-8 vCPU, 8-16GB RAM, 100GB NVMe | Server rieng, bottleneck chinh                 |
| **Redis**          | 2 vCPU, 4GB RAM, 10GB SSD        | Server rieng, workload nhe                     |
| **Network**        | 1Gbps, < 1ms latency K8s↔DB      | Cung datacenter/VPC BAT BUOC                   |
| **Cost**           | ~$400-500/month                  | Cloud VMs, khong tinh managed services         |
| **Key bottleneck** | PostgreSQL                       | 128 tables, 851 indexes, multi-tenant          |

Thay doi chinh so voi Helm chart hien tai:

1. `postgres.enabled: false` va `redis.enabled: false` (external servers)
2. API resource requests tang x2 (500m/512Mi)
3. HPA maxReplicas giam 10 → 5
4. DB/Redis connection strings tro den external servers
5. NetworkPolicy enabled

---

## APPENDIX A: UAT Environment (PG + Redis chung 1 server)

### A.1 Architecture Overview

```
                   ┌──────────────────────────────────────┐
                   │       K8s Cluster (UAT)              │
                   │                                      │
  QA/Dev ──────►   │  ┌───────────┐    ┌───────────┐     │
  (10-20 users)    │  │ API (1-2) │    │ UI (1)    │     │
                   │  └─────┬─────┘    └───────────┘     │
                   └────────┼─────────────────────────────┘
                            │
                            │ Private network (< 1ms)
                            ▼
                   ┌──────────────────────────────────────┐
                   │     1 Server (UAT DB+Cache)          │
                   │                                      │
                   │  ┌──────────────┐ ┌──────────────┐  │
                   │  │ PostgreSQL 17│ │ Redis 7      │  │
                   │  │ Port: 5432   │ │ Port: 6379   │  │
                   │  │              │ │              │  │
                   │  │ ~2GB RAM     │ │ ~512MB RAM   │  │
                   │  │ ~60% CPU     │ │ ~5% CPU      │  │
                   │  └──────────────┘ └──────────────┘  │
                   │                                      │
                   │  4 vCPU | 8GB RAM | 50GB SSD        │
                   └──────────────────────────────────────┘
```

### A.2 UAT Server Spec (1 server cho PG + Redis)

| Resource    | Spec                     | Ghi chu                                           |
| ----------- | ------------------------ | ------------------------------------------------- |
| **CPU**     | 4 vCPU                   | PG dung ~60%, Redis dung ~5%, OS ~10%, buffer 25% |
| **RAM**     | 8GB                      | PG: 4GB (shared_buffers 1GB), Redis: 1GB, OS: 3GB |
| **Disk**    | 50GB SSD                 | PG data: ~5-10GB, Redis AOF: ~1GB, OS: ~5GB       |
| **Network** | 1Gbps                    | Cung VPC voi K8s cluster                          |
| **OS**      | Ubuntu 22.04 / Debian 12 |                                                   |

**Cloud instance tuong duong:**

- AWS: `t3.xlarge` (4 vCPU, 16GB, ~$120/mo) hoac `t3.large` (2 vCPU, 8GB, ~$60/mo)
- GCP: `e2-standard-4` hoac `e2-standard-2`
- Bare metal: Any 4-core + 8GB + SSD

> **Khuyen nghi UAT**: `t3.large` (2 vCPU, 8GB) la du cho 10-20 QA users.
> Chi can `t3.xlarge` neu UAT chay load test hoac data lon.

### A.3 UAT K8s Cluster

| Service        | Replicas | CPU Request | CPU Limit | Mem Request | Mem Limit |
| -------------- | -------- | ----------- | --------- | ----------- | --------- |
| **API**        | 1-2      | 250m        | 1         | 256Mi       | 512Mi     |
| **UI**         | 1        | 100m        | 500m      | 128Mi       | 256Mi     |
| **Migrations** | Job      | 100m        | 500m      | 64Mi        | 256Mi     |

**K8s node**: 1x `t3.medium` (2 vCPU, 4GB) hoac `t3.large` (2 vCPU, 8GB)

> UAT khong can HPA, PDB, monitoring stack. 1 node du.

### A.4 UAT PostgreSQL Config (chia se server voi Redis)

```ini
# ============================================================
# OpenCTEM PostgreSQL 17 - UAT Config
# Shared server: 4 vCPU, 8GB RAM (PG duoc ~4-5GB)
# ============================================================

listen_addresses = '*'
port = 5432
max_connections = 50                # API(10×2) + Admin(5) + Buffer(25)

# --- Memory (budget: ~4GB cho PG) ---
shared_buffers = 1GB                # 25% cua 4GB PG budget
effective_cache_size = 3GB          # OS cache + shared_buffers
work_mem = 8MB                      # Thap hon production (it user)
maintenance_work_mem = 128MB
wal_buffers = 16MB

# --- WAL (giam IO cho shared server) ---
wal_level = minimal                 # Khong can replica cho UAT
max_wal_size = 1GB
min_wal_size = 256MB
checkpoint_completion_target = 0.9

# --- Query Optimizer ---
random_page_cost = 1.1
effective_io_concurrency = 200
default_statistics_target = 100

# --- Parallel (giam de nhuong CPU cho Redis) ---
max_parallel_workers_per_gather = 1
max_parallel_workers = 2
max_parallel_maintenance_workers = 1

# --- Autovacuum ---
autovacuum = on
autovacuum_max_workers = 2          # Giam tu 4 (shared CPU)
autovacuum_naptime = 1min
autovacuum_vacuum_scale_factor = 0.1
autovacuum_analyze_scale_factor = 0.05

# --- Logging ---
log_min_duration_statement = 1000   # Chi log queries > 1s (UAT it care)
log_statement = 'ddl'

# --- JIT ---
jit = off                           # Tat de tiet kiem CPU tren shared server
```

### A.5 UAT Redis Config (chia se server voi PostgreSQL)

```conf
# ============================================================
# OpenCTEM Redis 7 - UAT Config
# Shared server: budget ~1GB RAM cho Redis
# ============================================================

bind 0.0.0.0
port 6379
protected-mode yes
requirepass <REDIS_PASSWORD>

# --- Memory (gioi han de khong anh huong PG) ---
maxmemory 512mb                     # Chi 512MB (UAT data rat it)
maxmemory-policy allkeys-lru

# --- Persistence ---
appendonly yes
appendfsync everysec
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 32mb      # Nho hon production

# RDB snapshots
save 900 1
save 300 10
dbfilename dump.rdb
dir /var/lib/redis

# --- Connection ---
timeout 300
tcp-keepalive 60
maxclients 64                       # API(10×2) + Asynq + buffer

# --- Performance ---
hz 10
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
```

### A.6 UAT Resource Budget tren Shared Server

```
Server: 4 vCPU, 8GB RAM, 50GB SSD
──────────────────────────────────────────────────

CPU Budget:
┌─────────────────────────────────────────────────┐
│  PostgreSQL    │████████████████████░░░░│ ~60%   │
│  Redis         │██░░░░░░░░░░░░░░░░░░░░░│ ~5%    │
│  OS + System   │████░░░░░░░░░░░░░░░░░░░│ ~10%   │
│  Buffer        │██████░░░░░░░░░░░░░░░░░│ ~25%   │
└─────────────────────────────────────────────────┘

RAM Budget:
┌─────────────────────────────────────────────────┐
│  PG shared_buffers    │ 1GB                      │
│  PG connections (20)  │ 200MB                    │
│  PG work_mem + misc   │ 300MB                    │
│  PG effective_cache   │ (uses OS cache ~2GB)     │
│  ─────────────────────┼─────────────────────────-│
│  PG subtotal          │ ~1.5GB (+ 2GB OS cache)  │
│                       │                          │
│  Redis maxmemory      │ 512MB                    │
│  Redis AOF buffer     │ ~100MB                   │
│  ─────────────────────┼─────────────────────────-│
│  Redis subtotal       │ ~612MB                   │
│                       │                          │
│  OS + system          │ ~1GB                     │
│  ─────────────────────┼─────────────────────────-│
│  Total used           │ ~3.1GB                   │
│  OS file cache        │ ~4.9GB (cho PG reads)    │
│  Total                │ 8GB                      │
└─────────────────────────────────────────────────┘

Disk Budget:
┌─────────────────────────────────────────────────┐
│  PG data + indexes    │ 5-10GB                   │
│  PG WAL               │ 1GB                      │
│  Redis AOF + RDB      │ 1GB                      │
│  OS + logs            │ 5GB                      │
│  Buffer               │ 33-38GB                  │
│  Total                │ 50GB                     │
└─────────────────────────────────────────────────┘
```

### A.7 UAT values.yaml

```yaml
# === OpenCTEM UAT values ===
# === PG + Redis = 1 shared external server ===

api:
  replicaCount: 1 # 1 pod du cho UAT
  resources:
    requests:
      cpu: 250m
      memory: 256Mi
    limits:
      cpu: "1"
      memory: 512Mi
  env:
    APP_ENV: staging
    LOG_LEVEL: debug # Debug cho UAT
    LOG_FORMAT: json
    SERVER_PORT: "8080"
    GRPC_PORT: "9090"
    RATE_LIMIT_ENABLED: "true"
    RATE_LIMIT_RPS: "50" # Thap hon production
    RATE_LIMIT_BURST: "100"
    AUTH_PROVIDER: local
    AUTH_REQUIRE_EMAIL_VERIFICATION: "false"
    AUTH_ALLOW_REGISTRATION: "true"

    # DB (tro den shared server)
    DB_HOST: "uat-db.internal"
    DB_PORT: "5432"
    DB_NAME: "openctem"
    DB_SSLMODE: "require"
    DB_MAX_OPEN_CONNS: "10" # Giam vi chi 1-2 pods
    DB_MAX_IDLE_CONNS: "5"
    DB_CONN_MAX_LIFETIME: "300s"

    # Redis (tro den cung shared server)
    REDIS_HOST: "uat-db.internal" # Cung server voi PG
    REDIS_PORT: "6379"
    REDIS_POOL_SIZE: "10"

    MAX_CONCURRENT_REQUESTS: "200"

  envFromSecret: openctem-api-secrets
  autoscaling:
    enabled: false # Khong can HPA cho UAT

ui:
  replicaCount: 1 # 1 pod du cho UAT
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 500m
      memory: 256Mi
  env:
    NEXT_PUBLIC_API_URL: ""

# External services
postgres:
  enabled: false
redis:
  enabled: false

# Ingress
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: uat.openctem.example.com
      paths:
        - path: /
          pathType: Prefix
          service: ui
        - path: /api
          pathType: Prefix
          service: api
  tls:
    - secretName: openctem-uat-tls
      hosts:
        - uat.openctem.example.com

migrations:
  image:
    repository: migrate/migrate
    tag: "v4.17.0"
  resources:
    requests:
      cpu: 100m
      memory: 64Mi
    limits:
      cpu: 500m
      memory: 256Mi

serviceAccount:
  create: true
podDisruptionBudget:
  enabled: false # Khong can PDB cho UAT
networkPolicy:
  enabled: false # Optional cho UAT
```

### A.8 UAT Shared Server Setup Script

```bash
#!/bin/bash
# Setup PostgreSQL 17 + Redis 7 tren 1 server Ubuntu 22.04

set -euo pipefail

# === PostgreSQL 17 ===
sudo apt-get update
sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y postgresql-17

# Config
sudo cp /etc/postgresql/17/main/postgresql.conf /etc/postgresql/17/main/postgresql.conf.bak
# Apply config tu Section A.4
sudo systemctl restart postgresql

# Create database + user
sudo -u postgres psql <<SQL
CREATE USER openctem WITH PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
CREATE DATABASE openctem OWNER openctem;
GRANT ALL PRIVILEGES ON DATABASE openctem TO openctem;
SQL

# === Redis 7 ===
sudo apt-get install -y redis-server

# Config
sudo cp /etc/redis/redis.conf /etc/redis/redis.conf.bak
# Apply config tu Section A.5
sudo systemctl restart redis-server

# === Firewall (chi cho phep K8s subnet) ===
sudo ufw allow from 10.0.1.0/24 to any port 5432  # PG
sudo ufw allow from 10.0.1.0/24 to any port 6379  # Redis
sudo ufw allow from 10.0.0.0/16 to any port 22    # SSH
sudo ufw enable

echo "Done! PG:5432 + Redis:6379 ready."
```

### A.9 So sanh UAT vs Production

| Aspect                 | UAT                  | Production                     |
| ---------------------- | -------------------- | ------------------------------ |
| **Users**              | 10-20 (QA/Dev)       | ~100                           |
| **K8s nodes**          | 1x t3.medium         | 2x t3.xlarge                   |
| **API pods**           | 1 (no HPA)           | 2-5 (HPA)                      |
| **UI pods**            | 1                    | 2                              |
| **PG server**          | Shared (4 vCPU, 8GB) | Dedicated (4-8 vCPU, 8-16GB)   |
| **Redis server**       | Shared (cung PG)     | Dedicated (2 vCPU, 4GB)        |
| **PG shared_buffers**  | 1GB                  | 2-4GB                          |
| **PG max_connections** | 50                   | 150                            |
| **Redis maxmemory**    | 512MB                | 2GB                            |
| **HPA**                | Disabled             | Enabled                        |
| **PDB**                | Disabled             | Enabled                        |
| **Monitoring**         | Optional             | Required                       |
| **Backup**             | Daily pg_dump        | pg_dump + WAL archiving        |
| **Est. cost/mo**       | **~$80-120**         | **~$400-500**                  |
| **Total servers**      | **2** (1 K8s + 1 DB) | **4** (2 K8s + 1 PG + 1 Redis) |
