# OpenCTEM - Resource Request Diagram

> Tai lieu mo hinh ket noi giua cac thanh phan he thong de xin cap tai nguyen.
> Date: 2026-03-19

---

## 1. Tong Quan He Thong (Full System Topology)

```
┌───────────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                               │
│                                    INTERNET / USERS                                           │
│                                                                                               │
│                        Browser (100 users)          Scanner Agents                            │
│                             │                        (N instances)                            │
│                             │ HTTPS/WSS              │ gRPC + HTTPS                           │
│                             │ Port 443               │ Port 443                               │
│                             ▼                        ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────────────┐              │
│  │                         LOAD BALANCER / DNS                                 │              │
│  │                    openctem.example.com                                     │              │
│  │                    TLS Termination (Let's Encrypt)                          │              │
│  └──────────────────────────────┬──────────────────────────────────────────────┘              │
│                                 │                                                             │
│  ═══════════════════════════════╪═════════════════════════════════════════════════════════    │
│  ║          KUBERNETES CLUSTER  ║                                                        ║    │
│  ║                              ▼                                                        ║    │
│  ║  ┌──────────────────────────────────────────────────────────────┐                     ║    │
│  ║  │                   INGRESS NGINX (2 pods)                     │                     ║    │
│  ║  │                   100m CPU / 128Mi RAM x2                    │                     ║    │
│  ║  │                                                              │                     ║    │
│  ║  │   Route: /          → UI Service :3000                       │                     ║    │
│  ║  │   Route: /api/*     → API Service :8080                      │                     ║    │
│  ║  │   Route: /metrics   → API Service :8080                      │                     ║    │
│  ║  └──────────┬──────────────────────────────────┬────────────────┘                     ║    │
│  ║             │                                  │                                      ║    │
│  ║             ▼                                  ▼                                      ║    │
│  ║  ┌─────────────────────────┐    ┌─────────────────────────────────┐                   ║    │
│  ║  │                         │    │                                 │                   ║    │
│  ║  │   UI SERVICE (Next.js)  │    │     API SERVICE (Go)            │                   ║    │
│  ║  │                         │    │                                 │                   ║    │
│  ║  │   Pods: 2 (static)      │    │     Pods: 2-5 (HPA)             │                   ║    │
│  ║  │   Port: 3000            │    │     Port HTTP: 8080             │                   ║    │
│  ║  │                         │    │     Port gRPC: 9090             │                   ║    │
│  ║  │   Per pod:              │    │     Port Metrics: 8080/metrics  │                   ║    │
│  ║  │   CPU: 200m / 1         │    │                                 │                   ║    │
│  ║  │   RAM: 256Mi / 512Mi    │    │     Per pod:                    │                   ║    │
│  ║  │                         │    │     CPU: 500m / 2               │                   ║    │
│  ║  │   Features:             │    │     RAM: 512Mi / 1Gi            │                   ║    │
│  ║  │   - SSR (React 19)      │    │                                 │                   ║    │
│  ║  │   - Static assets       │    │     Features:                   │                   ║    │
│  ║  │   - API proxy           │    │     - REST API (100+ endpoints) │                   ║    │
│  ║  │   - 3 locales           │    │     - gRPC (agent comm)         │                   ║    │
│  ║  │   - WebSocket client    │    │     - WebSocket hub             │                   ║    │
│  ║  │                         │    │     - 10 background controllers │                   ║    │
│  ║  │                         │    │     - Asynq workers (5 queues)  │                   ║    │
│  ║  │                         │    │     - Rate limiting             │                   ║    │
│  ║  │                         │    │     - JWT/RBAC auth             │                   ║    │
│  ║  └─────────────────────────┘    └────────┬────────────┬───────────┘                   ║    │
│  ║                                          │            │                               ║    │
│  ║  ┌──────────────────────────────────────┐│            │                               ║    │
│  ║  │   MONITORING (optional)              ││            │                               ║    │
│  ║  │                                      ││            │                               ║    │
│  ║  │   Prometheus: 200m/512Mi, PVC 20Gi   ││            │                               ║    │
│  ║  │   Grafana:    100m/256Mi, PVC 5Gi    ││            │                               ║    │
│  ║  │                                      ││            │                               ║    │
│  ║  │   Scrape: API :8080/metrics          ││            │                               ║    │
│  ║  │   Scrape: PG exporter :9187          ││            │                               ║    │
│  ║  │   Scrape: Redis exporter :9121       ││            │                               ║    │
│  ║  └──────────────────────────────────────┘│            │                               ║    │
│  ║                                          │            │                               ║    │
│  ═══════════════════════════════════════════╪════════════╪════════════════════════════════    │
│                                             │            │                                    │
│                          TCP/5432           │            │  TCP/6379                          │
│                      ┌──────────────────────┘            └──────────────┐                     │
│                      │              PRIVATE NETWORK                     │                     │
│                      │              (same VPC / datacenter)             │                     │
│                      │              Latency < 1ms                       │                     │
│                      ▼                                                  ▼                     │
│  ┌───────────────────────────────────────┐    ┌──────────────────────────────────────┐        │
│  │                                       │    │                                      │        │
│  │   POSTGRESQL 17 SERVER                │    │   REDIS 7 SERVER                     │        │
│  │                                       │    │                                      │        │
│  │   ┌─────────────────────────────┐     │    │   ┌──────────────────────────────┐   │        │
│  │   │ PRODUCTION (dedicated)      │     │    │   │ PRODUCTION (dedicated)       │   │        │
│  │   │ CPU: 4-8 vCPU               │     │    │   │ CPU: 2 vCPU                  │   │        │
│  │   │ RAM: 8-16GB                 │     │    │   │ RAM: 4GB                     │   │        │
│  │   │ Disk: 100GB NVMe + 20GB WAL │     │    │   │ Disk: 10GB SSD               │   │        │
│  │   └─────────────────────────────┘     │    │   └──────────────────────────────┘   │        │
│  │                                       │    │                                      │        │
│  │   ┌─────────────────────────────┐     │    │   Data stored:                       │        │
│  │   │ UAT (shared with Redis)     │     │    │   - User sessions (30min TTL)        │        │
│  │   │ CPU: 4 vCPU (shared)        │     │    │   - Permission cache (5min TTL)      │        │
│  │   │ RAM: 8GB (shared)           │     │    │   - Asynq job queues (5 queues)      │        │
│  │   │ Disk: 50GB SSD (shared)     │     │    │   - Rate limit counters              │        │
│  │   └─────────────────────────────┘     │    │   - Pub/Sub (WebSocket broadcast)    │        │
│  │                                       │    │   - Agent state + heartbeats         │        │
│  │   Data stored:                        │    │                                      │        │
│  │   - 128 tables, 851+ indexes          │    │   Connections from:                  │        │
│  │   - Assets, Findings, Scans           │    │   - API pods: 20 pool + 5 asynq each │        │
│  │   - Users, Tenants, Roles, Perms      │    │   - Total peak: 127 connections      │        │
│  │   - Audit logs, Workflows             │    │                                      │        │
│  │   - Encrypted credentials (AES-256)   │    │   Protocol: RESP (Redis Protocol)    │        │
│  │                                       │    │   Auth: requirepass                  │        │
│  │   Connections from:                   │    │   Persistence: AOF (everysec)        │        │
│  │   - API pods: 20 conns each           │    │                                      │        │
│  │   - Total peak: 106 connections       │    └──────────────────────────────────────┘        │
│  │                                       │                                                    │
│  │   Protocol: PostgreSQL wire protocol  │                                                    │
│  │   Auth: scram-sha-256 + SSL           │                                                    │
│  │   Backup: daily pg_dump + WAL archive │                                                    │
│  │                                       │                                                    │
│  └───────────────────────────────────────┘                                                    │
│                                                                                               │
│                                                                                               │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐    │
│  │                          SCANNER AGENTS (external)                                    │    │
│  │                                                                                       │    │
│  │   Deployed on: target networks / customer infrastructure / cloud VMs                  │    │
│  │                                                                                       │    │
│  │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │    │
│  │   │  Agent #1   │  │  Agent #2   │  │  Agent #3   │  │  Agent #N   │                  │    │
│  │   │             │  │             │  │             │  │             │                  │    │
│  │   │  Scanners:  │  │  Scanners:  │  │  Scanners:  │  │  Scanners:  │                  │    │
│  │   │  - Semgrep  │  │  - Trivy    │  │  - Nuclei   │  │  - GitLeaks │                  │    │
│  │   │  - Trivy    │  │  - Nuclei   │  │  - Semgrep  │  │  - Trivy    │                  │    │
│  │   │             │  │             │  │             │  │             │                  │    │
│  │   │  Per agent: │  │             │  │             │  │             │                  │    │
│  │   │  2 vCPU     │  │             │  │             │  │             │                  │    │
│  │   │  2-4GB RAM  │  │             │  │             │  │             │                  │    │
│  │   │  10GB disk  │  │             │  │             │  │             │                  │    │
│  │   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                  │    │
│  │          │                │                │                │                         │    │
│  │          └────────────────┴────────────────┴────────────────┘                         │    │
│  │                                    │                                                  │    │
│  │                                    │ gRPC :9090 (job polling, result submission)      │    │
│  │                                    │ HTTPS :443/api (REST fallback)                   │    │
│  │                                    │ Auth: Bootstrap Token → API Key                  │    │
│  │                                    │                                                  │    │
│  │                                    ▼                                                  │    │
│  │                          API SERVICE (K8s)                                            │    │
│  └───────────────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                               │
│                                                                                               │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐    │
│  │                        EXTERNAL SERVICES (optional)                                   │    │
│  │                                                                                       │    │
│  │   ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐             │    │
│  │   │  SMTP Server │  │  Keycloak    │  │  OpenAI API   │  │  OAuth       │             │    │
│  │   │  (Email)     │  │  (OIDC SSO)  │  │  (AI Triage)  │  │  (GitHub/    │             │    │
│  │   │              │  │              │  │               │  │   GitLab)    │             │    │
│  │   │  Port: 587   │  │  Port: 443   │  │  Port: 443    │  │  Port: 443   │             │    │
│  │   │  Protocol:   │  │  Protocol:   │  │  Protocol:    │  │  Protocol:   │             │    │
│  │   │  SMTP/TLS    │  │  HTTPS/OIDC  │  │  HTTPS/REST   │  │  HTTPS/OAuth │             │    │
│  │   └──────┬───────┘  └──────┬───────┘  └───────┬───────┘  └──────┬───────┘             │    │
│  │          │                 │                  │                 │                     │    │
│  │          └─────────────────┴──────────────────┴─────────────────┘                     │    │
│  │                                    │                                                  │    │
│  │                            Outbound from API pods                                     │    │
│  │                            (requires egress network access)                           │    │
│  └───────────────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                               │
│  ┌───────────────────────────────────────────────────────────────────────────────────────┐    │
│  │                        NOTIFICATION TARGETS (outbound)                                │    │
│  │                                                                                       │    │
│  │   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐                │    │
│  │   │  Slack   │  │  Teams   │  │ Telegram │  │ Webhooks │  │  Email   │                │    │
│  │   │  API     │  │  API     │  │  Bot API │  │ (custom) │  │  (SMTP)  │                │    │
│  │   │  :443    │  │  :443    │  │  :443    │  │  :443    │  │  :587    │                │    │
│  │   └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘                │    │
│  │                                                                                       │    │
│  │   Direction: API pods → External (outbound only)                                      │    │
│  │   Triggered by: Transactional Outbox pattern (async, fan-out-on-read)                 │    │
│  └───────────────────────────────────────────────────────────────────────────────────────┘    │
│                                                                                               │
└───────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Connection Matrix (Port / Protocol / Direction)

### 2.1 Inbound Connections (tu ngoai vao)

| #   | Source          | Destination   | Port   | Protocol | Direction | Auth     | Muc dich             |
| --- | --------------- | ------------- | ------ | -------- | --------- | -------- | -------------------- |
| 1   | Users (Browser) | Load Balancer | 443    | HTTPS    | Inbound   | TLS cert | Web access           |
| 2   | Users (Browser) | Load Balancer | 443    | WSS      | Inbound   | JWT      | Real-time updates    |
| 3   | Scanner Agents  | Load Balancer | 443    | HTTPS    | Inbound   | API Key  | REST fallback        |
| 4   | Scanner Agents  | API Service   | 9090   | gRPC/TLS | Inbound   | API Key  | Job polling, results |
| 5   | Load Balancer   | Ingress NGINX | 80/443 | HTTP(S)  | Inbound   | -        | Reverse proxy        |

### 2.2 Internal Connections (trong he thong)

| #   | Source     | Destination    | Port | Protocol       | Direction | Auth          | Muc dich              |
| --- | ---------- | -------------- | ---- | -------------- | --------- | ------------- | --------------------- |
| 6   | Ingress    | UI pods        | 3000 | HTTP           | Internal  | -             | SSR pages, static     |
| 7   | Ingress    | API pods       | 8080 | HTTP           | Internal  | -             | REST API              |
| 8   | API pods   | PostgreSQL     | 5432 | PostgreSQL/SSL | Internal  | scram-sha-256 | Data read/write       |
| 9   | API pods   | Redis          | 6379 | RESP           | Internal  | requirepass   | Cache, queue, pub/sub |
| 10  | Prometheus | API pods       | 8080 | HTTP           | Internal  | -             | Scrape /metrics       |
| 11  | Prometheus | PG exporter    | 9187 | HTTP           | Internal  | -             | DB metrics            |
| 12  | Prometheus | Redis exporter | 9121 | HTTP           | Internal  | -             | Redis metrics         |

### 2.3 Outbound Connections (tu trong ra ngoai)

| #   | Source   | Destination     | Port | Protocol    | Direction | Auth        | Muc dich              |
| --- | -------- | --------------- | ---- | ----------- | --------- | ----------- | --------------------- |
| 13  | API pods | SMTP Server     | 587  | SMTP/TLS    | Outbound  | User/Pass   | Email (invite, alert) |
| 14  | API pods | Keycloak        | 443  | HTTPS       | Outbound  | OIDC        | SSO authentication    |
| 15  | API pods | OpenAI API      | 443  | HTTPS       | Outbound  | API Key     | AI Triage scoring     |
| 16  | API pods | GitHub/GitLab   | 443  | HTTPS/OAuth | Outbound  | OAuth token | SCM integration       |
| 17  | API pods | Slack API       | 443  | HTTPS       | Outbound  | Webhook URL | Notifications         |
| 18  | API pods | Teams API       | 443  | HTTPS       | Outbound  | Webhook URL | Notifications         |
| 19  | API pods | Telegram API    | 443  | HTTPS       | Outbound  | Bot token   | Notifications         |
| 20  | API pods | Custom Webhooks | 443  | HTTPS       | Outbound  | Custom      | Event webhooks        |

---

## 3. Firewall Rules Summary

### 3.1 K8s Cluster Nodes

```
INBOUND:
  ┌────────────────────────────────────────────────────────────────┐
  │  Port 443   ← Load Balancer (any)          │ HTTPS/WSS/gRPC    │
  │  Port 6443  ← Admin IP only                │ K8s API server    │
  │  Port 22    ← Admin IP only                │ SSH management    │
  └────────────────────────────────────────────────────────────────┘

OUTBOUND:
  ┌────────────────────────────────────────────────────────────────┐
  │  Port 5432  → PostgreSQL server IP          │ Database         │
  │  Port 6379  → Redis server IP               │ Cache/Queue      │
  │  Port 443   → 0.0.0.0/0                     │ External APIs    │
  │  Port 587   → SMTP server IP                │ Email            │
  └────────────────────────────────────────────────────────────────┘
```

### 3.2 PostgreSQL Server

```
INBOUND:
  ┌────────────────────────────────────────────────────────────────┐
  │  Port 5432  ← K8s cluster subnet            │ PostgreSQL       │
  │  Port 9187  ← K8s cluster subnet (optional) │ PG exporter      │
  │  Port 22    ← Admin IP only                 │ SSH management   │
  └────────────────────────────────────────────────────────────────┘

OUTBOUND:
  ┌────────────────────────────────────────────────────────────────┐
  │  DENY ALL (khong can outbound)                                 │
  └────────────────────────────────────────────────────────────────┘
```

### 3.3 Redis Server

```
INBOUND:
  ┌────────────────────────────────────────────────────────────────┐
  │  Port 6379  ← K8s cluster subnet            │ Redis            │
  │  Port 9121  ← K8s cluster subnet (optional) │ Redis exporter   │
  │  Port 22    ← Admin IP only                 │ SSH management   │
  └────────────────────────────────────────────────────────────────┘

OUTBOUND:
  ┌────────────────────────────────────────────────────────────────┐
  │  DENY ALL (khong can outbound)                                 │
  └────────────────────────────────────────────────────────────────┘
```

---

## 4. Resource Request Table

### 4.1 PRODUCTION Environment (~100 users)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          PRODUCTION                                      │
├──────────────────┬───────────┬────────┬──────────┬──────────┬────────────┤
│ Component        │ vCPU      │ RAM    │ Disk     │ Network  │ Qty        │
├──────────────────┼───────────┼────────┼──────────┼──────────┼────────────┤
│ K8s Worker Node  │ 4         │ 16GB   │ 50GB SSD │ 1Gbps    │ 2 nodes    │
│ PostgreSQL       │ 4-8       │ 16GB   │ 100GB    │ 1Gbps    │ 1 server   │
│                  │           │        │ NVMe SSD │          │            │
│ Redis            │ 2         │ 4GB    │ 10GB SSD │ 1Gbps    │ 1 server   │
├──────────────────┼───────────┼────────┼──────────┼──────────┼────────────┤
│ TOTAL PROD       │ 14-18     │ 52GB   │ 260GB    │          │ 4 servers  │
├──────────────────┼───────────┼────────┼──────────┼──────────┼────────────┤
│ Backup storage   │ -         │ -      │ 200GB    │          │ S3/NFS     │
│                  │           │        │ (HDD ok) │          │            │
└──────────────────┴───────────┴────────┴──────────┴──────────┴────────────┘
```

### 4.2 UAT Environment (~10-20 users)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                             UAT                                          │
├──────────────────┬───────────┬────────┬──────────┬──────────┬────────────┤
│ Component        │ vCPU      │ RAM    │ Disk     │ Network  │ Qty        │
├──────────────────┼───────────┼────────┼──────────┼──────────┼────────────┤
│ K8s Worker Node  │ 2         │ 8GB    │ 30GB SSD │ 1Gbps    │ 1 node     │
│ PG + Redis       │ 4         │ 8GB    │ 50GB SSD │ 1Gbps    │ 1 server   │
│ (shared server)  │           │        │          │          │            │
├──────────────────┼───────────┼────────┼──────────┼──────────┼────────────┤
│ TOTAL UAT        │ 6         │ 16GB   │ 80GB     │          │ 2 servers  │
└──────────────────┴───────────┴────────┴──────────┴──────────┴────────────┘
```

### 4.3 TONG TAI NGUYEN CAN XIN CAP (PROD + UAT)

```
╔══════════════════════════════════════════════════════════════════════════╗
║                    TONG HOP TAI NGUYEN CAN CAP                           ║
╠══════════════════╦═══════════╦════════╦══════════╦══════════╦════════════╣
║                  ║   vCPU    ║  RAM   ║   Disk   ║ Network  ║ Servers    ║
╠══════════════════╬═══════════╬════════╬══════════╬══════════╬════════════╣
║ PRODUCTION       ║           ║        ║          ║          ║            ║
║  K8s nodes (x2)  ║    8      ║  32GB  ║  100GB   ║  1Gbps   ║   2        ║
║  PostgreSQL      ║    8      ║  16GB  ║  120GB   ║  1Gbps   ║   1        ║
║  Redis           ║    2      ║   4GB  ║   10GB   ║  1Gbps   ║   1        ║
╠──────────────────╬───────────╬────────╬──────────╬──────────╬════════════╣
║ UAT              ║           ║        ║          ║          ║            ║
║  K8s node  (x1)  ║    2      ║   8GB  ║   30GB   ║  1Gbps   ║   1        ║
║  PG+Redis shared ║    4      ║   8GB  ║   50GB   ║  1Gbps   ║   1        ║
╠══════════════════╬═══════════╬════════╬══════════╬══════════╬════════════╣
║ BACKUP STORAGE   ║    -      ║   -    ║  200GB   ║    -     ║  S3/NFS    ║
╠══════════════════╬═══════════╬════════╬══════════╬══════════╬════════════╣
║ SCANNER AGENTS   ║  2/agent  ║ 4GB/   ║ 10GB/    ║  1Gbps   ║ N agents   ║
║ (tuy so luong)   ║           ║ agent  ║ agent    ║          ║            ║
╠══════════════════╬═══════════╬════════╬══════════╬══════════╬════════════╣
║                  ║           ║        ║          ║          ║            ║
║ GRAND TOTAL      ║   24+     ║  68GB+ ║  510GB+  ║          ║ 6+         ║
║ (khong tinh      ║   2N      ║  4N GB ║  10N GB  ║          ║ N agents   ║
║  agents)         ║   24      ║  68GB  ║  510GB   ║          ║ 6          ║
║                  ║           ║        ║          ║          ║            ║
╚══════════════════╩═══════════╩════════╩══════════╩══════════╩════════════╝
```

---

## 5. Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                                                                  │
│  [User Browser]                                                                  │
│       │                                                                          │
│       │ 1. HTTPS Request (GET /dashboard)                                        │
│       ▼                                                                          │
│  [Load Balancer] ──443──► [Ingress NGINX]                                        │
│       │                        │                                                 │
│       │              ┌─────────┴──────────┐                                      │
│       │              ▼                    ▼                                      │
│       │    [UI Pod :3000]        [API Pod :8080]                                 │
│       │    SSR render page       │                                               │
│       │         │                │ 2. API call (GET /api/v1/dashboard/stats)     │
│       │         │                │                                               │
│       │         │                ├──► [Redis :6379]                              │
│       │         │                │    Check session + permission cache           │
│       │         │                │    ◄── Cache HIT: return cached perms         │
│       │         │                │    ◄── Cache MISS: query DB, cache result     │
│       │         │                │                                               │
│       │         │                ├──► [PostgreSQL :5432]                         │
│       │         │                │    Query: SELECT stats with tenant_id filter  │
│       │         │                │    ◄── Return results                         │
│       │         │                │                                               │
│       │         │                │ 3. Return JSON response                       │
│       │         │                ▼                                               │
│       │         │           [User Browser]                                       │
│       │         │                                                                │
│       │         │                                                                │
│  [Scanner Agent]                                                                 │
│       │                                                                          │
│       │ 4. gRPC: Poll for jobs                                                   │
│       ▼                                                                          │
│  [API Pod :9090]                                                                 │
│       │                                                                          │
│       ├──► [Redis] Check agent lease, get queued job                             │
│       ├──► [PostgreSQL] Fetch command details, update status                     │
│       │                                                                          │
│       │ 5. Return job to agent                                                   │
│       ▼                                                                          │
│  [Scanner Agent]                                                                 │
│       │                                                                          │
│       │ 6. Execute scan (Semgrep/Trivy/Nuclei/GitLeaks)                          │
│       │ 7. Submit results via gRPC                                               │
│       ▼                                                                          │
│  [API Pod :9090]                                                                 │
│       │                                                                          │
│       ├──► [PostgreSQL] Store findings, update scan status                       │
│       ├──► [Redis] Publish event (scan.completed)                                │
│       │         │                                                                │
│       │         ├──► [WebSocket Hub] Broadcast to subscribed browsers            │
│       │         └──► [Asynq Queue] Enqueue notification job                      │
│       │                    │                                                     │
│       │                    ▼                                                     │
│       │              [Asynq Worker]                                              │
│       │                    │                                                     │
│       │                    ├──► [Slack API] Send notification                    │
│       │                    ├──► [Email/SMTP] Send alert                          │
│       │                    └──► [Webhook] POST to custom URL                     │
│       │                                                                          │
└──────────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Scanner Agent Detail

```
┌──────────────────────────────────────────────────────────────────┐
│                    SCANNER AGENT                                 │
│                                                                  │
│   Resource per agent:                                            │
│   ├── CPU: 2 vCPU (scan tools are CPU-intensive)                 │
│   ├── RAM: 2-4GB (depends on scan scope)                         │
│   ├── Disk: 10GB (tool binaries + scan cache)                    │
│   └── Network: outbound to API + target networks                 │
│                                                                  │
│   Deployment options:                                            │
│   ├── Docker container on target network                         │
│   ├── K8s pod (DaemonSet or Deployment)                          │
│   ├── VM on customer infrastructure                              │
│   └── Cloud VM (EC2/GCE) for external scanning                   │
│                                                                  │
│   ┌──────────────────────────────────────────┐                   │
│   │  Agent Binary (Go)                       │                   │
│   │                                          │                   │
│   │  ┌─────────┐ ┌───────────┐ ┌───────────┐ │                   │
│   │  │ Semgrep │ │  Trivy    │ │  Nuclei   │ │                   │
│   │  │ (SAST)  │ │ (SCA/     │ │  (Vuln    │ │                   │
│   │  │         │ │  Container│ │  Scanner) │ │                   │
│   │  └─────────┘ └───────────┘ └───────────┘ │                   │
│   │  ┌─────────┐                             │                   │
│   │  │GitLeaks │                             │                   │
│   │  │(Secrets)│                             │                   │
│   │  └─────────┘                             │                   │
│   └──────────────────┬───────────────────────┘                   │
│                      │                                           │
│                      │ Outbound connections:                     │
│                      ├──► API :9090  (gRPC - job poll/results)   │
│                      ├──► API :443   (HTTPS - REST fallback)     │
│                      ├──► Target hosts (scan targets)            │
│                      └──► GitHub/GitLab (code clone for SAST)    │
│                                                                  │
│   Auth flow:                                                     │
│   1. Register with Bootstrap Token (one-time)                    │
│   2. Receive API Key                                             │
│   3. All subsequent comms use API Key                            │
│                                                                  │
│   Scaling:                                                       │
│   ├── 1-2 agents: small team, internal scanning                  │
│   ├── 5-10 agents: multiple networks/regions                     │
│   └── 10+ agents: enterprise, distributed scanning               │
│                                                                  │
│   Resource per agent does NOT affect K8s/DB sizing               │
│   (agents are stateless, results are small JSON payloads)        │
└──────────────────────────────────────────────────────────────────┘
```

---

## 7. Network Diagram (cho team Network/Infra)

```
                          INTERNET
                              │
                              │
                    ┌─────────┴─────────┐
                    │   FIREWALL / WAF  │
                    │   (optional)      │
                    └─────────┬─────────┘
                              │
                              │ Port 443 only
                              │
              ┌───────────────┴─────────────────┐
              │        PUBLIC SUBNET            │
              │                                 │
              │   ┌─────────────────────────┐   │
              │   │    LOAD BALANCER        │   │
              │   │    Public IP: x.x.x.x   │   │
              │   │    Ports: 443           │   │
              │   └───────────┬─────────────┘   │
              │               │                 │
              └───────────────┼─────────────────┘
                              │
              ┌───────────────┼────────────────────────────────────────┐
              │               │    PRIVATE SUBNET A (K8s)              │
              │               │    CIDR: 10.0.1.0/24                   │
              │               │                                        │
              │   ┌───────────┴────────────┐                           │
              │   │  K8s Node 1            │                           │
              │   │  10.0.1.10             │                           │
              │   │  4 vCPU, 16GB          │                           │
              │   │                        │                           │
              │   │  Pods:                 │                           │
              │   │  - API (10.0.1.100)    │                           │
              │   │  - UI  (10.0.1.101)    │                           │
              │   │  - Ingress             │                           │
              │   └────────────────────────┘                           │
              │                                                        │
              │   ┌────────────────────────┐                           │
              │   │  K8s Node 2            │                           │
              │   │  10.0.1.11             │                           │
              │   │  4 vCPU, 16GB          │                           │
              │   │                        │                           │
              │   │  Pods:                 │                           │
              │   │  - API (10.0.1.102)    │                           │
              │   │  - UI  (10.0.1.103)    │                           │
              │   │  - Prometheus          │                           │
              │   │  - Grafana             │                           │
              │   └────────────────────────┘                           │
              │                                                        │
              └────────────────┬───────────────┬───────────────────────┘
                               │               │
                    TCP/5432   │               │  TCP/6379
                               │               │
              ┌────────────────┴───────────────┴──────────────────────┐
              │                PRIVATE SUBNET B (Data)                │
              │                CIDR: 10.0.2.0/24                      │
              │                                                       │
              │   ┌────────────────────────┐                          │
              │   │  PostgreSQL Server     │                          │
              │   │  10.0.2.10             │                          │
              │   │  4-8 vCPU, 16GB        │                          │
              │   │  Disk: 100GB NVMe      │                          │
              │   │  Port: 5432            │                          │
              │   │                        │                          │
              │   │  Inbound: 10.0.1.0/24  │                          │
              │   │  Outbound: DENY ALL    │                          │
              │   └────────────────────────┘                          │
              │                                                       │
              │   ┌────────────────────────┐                          │
              │   │  Redis Server          │                          │
              │   │  10.0.2.20             │                          │
              │   │  2 vCPU, 4GB           │                          │
              │   │  Disk: 10GB SSD        │                          │
              │   │  Port: 6379            │                          │
              │   │                        │                          │
              │   │  Inbound: 10.0.1.0/24  │                          │
              │   │  Outbound: DENY ALL    │                          │
              │   └────────────────────────┘                          │
              │                                                       │
              └───────────────────────────────────────────────────────┘


  REMOTE / ON-PREMISE
  ┌────────────────────────────────────────────────────────────────────┐
  │                                                                    │
  │   Scanner Agent(s)                                                 │
  │   2 vCPU, 4GB, 10GB per agent                                      │
  │                                                                    │
  │   Outbound:                                                        │
  │   ──► Load Balancer :443  (HTTPS/gRPC to API)                      │
  │   ──► Target networks    (scan targets)                            │
  │   ──► GitHub/GitLab :443 (clone repos for SAST)                    │
  │                                                                    │
  └────────────────────────────────────────────────────────────────────┘
```

---

## 8. Tom Tat Xin Cap Tai Nguyen

### PRODUCTION (~100 users)

| STT | Thanh phan | Server/VM     | vCPU | RAM  | Disk                  | OS           | Ports can mo              | Ghi chu          |
| --- | ---------- | ------------- | ---- | ---- | --------------------- | ------------ | ------------------------- | ---------------- |
| 1   | K8s Node 1 | VM/Bare metal | 4    | 16GB | 50GB SSD              | Ubuntu 22.04 | 443 (LB), 6443 (K8s API)  | Private subnet A |
| 2   | K8s Node 2 | VM/Bare metal | 4    | 16GB | 50GB SSD              | Ubuntu 22.04 | 443 (LB), 6443 (K8s API)  | Private subnet A |
| 3   | PostgreSQL | VM/Bare metal | 8    | 16GB | 100GB NVMe + 20GB WAL | Ubuntu 22.04 | 5432 (from subnet A only) | Private subnet B |
| 4   | Redis      | VM/Bare metal | 2    | 4GB  | 10GB SSD              | Ubuntu 22.04 | 6379 (from subnet A only) | Private subnet B |
| 5   | Backup     | S3/NFS        | -    | -    | 200GB HDD             | -            | -                         | PG backup + WAL  |

### UAT (~10-20 users)

| STT | Thanh phan | Server/VM | vCPU | RAM | Disk     | OS           | Ports can mo | Ghi chu       |
| --- | ---------- | --------- | ---- | --- | -------- | ------------ | ------------ | ------------- |
| 1   | K8s Node   | VM        | 2    | 8GB | 30GB SSD | Ubuntu 22.04 | 443          | Single node   |
| 2   | PG + Redis | VM        | 4    | 8GB | 50GB SSD | Ubuntu 22.04 | 5432, 6379   | Shared server |

### SCANNER AGENTS (tuy nhu cau)

| STT | Thanh phan    | Server/VM    | vCPU | RAM | Disk | OS           | Ports can mo      | Ghi chu              |
| --- | ------------- | ------------ | ---- | --- | ---- | ------------ | ----------------- | -------------------- |
| N   | Scanner Agent | VM/Container | 2    | 4GB | 10GB | Ubuntu 22.04 | Outbound 443 only | 1 per network/region |

### YEU CAU NETWORK

| Yeu cau         | Chi tiet                                                         |
| --------------- | ---------------------------------------------------------------- |
| VPC/VLAN        | 2 subnets: K8s (10.0.1.0/24) + Data (10.0.2.0/24)                |
| Bandwidth       | 1Gbps giua cac server                                            |
| Latency         | < 1ms giua K8s nodes va DB/Redis servers                         |
| Public IP       | 1 (Load Balancer)                                                |
| DNS             | 2 records: openctem.example.com (prod), uat.openctem.example.com |
| TLS Certificate | Let's Encrypt (auto-renew) hoac corporate cert                   |
| Firewall        | Theo Section 3                                                   |
