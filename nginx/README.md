# Nginx Configuration

Nginx reverse proxy configuration for OpenCTEM Platform with multi-domain and SSL/TLS support.

## Architecture

```
                    ┌─────────────────────────────────────────────────────────────────┐
                    │                            Nginx                                 │
                    │                                                                  │
    Internet ──────►│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
                    │  │ openctem.io      │  │ api.openctem.io  │  │admin.openctem.io │  │
                    │  │ (NGINX_HOST)    │  │ (API_HOST)      │  │ (ADMIN_HOST)    │  │
                    │  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  │
                    │           │                    │                    │           │
                    └───────────┼────────────────────┼────────────────────┼───────────┘
                                │                    │                    │
                                ▼                    ▼                    ▼
                         ┌──────────┐         ┌──────────┐         ┌──────────┐
                         │    UI    │         │   API    │         │ Admin UI │
                         │  :3000   │         │  :8080   │         │  :3000   │
                         └──────────┘         └──────────┘         └──────────┘
```

## Quick Start

### Staging

```bash
# 1. Copy env file
cp environments/.env.nginx.staging.example .env.nginx.staging

# 2. Generate self-signed certificates
make init-ssl

# 3. Start with SSL
make staging-up-ssl
```

### Production

```bash
# 1. Copy env file
cp environments/.env.nginx.prod.example .env.nginx.prod

# 2. Update domains in .env.nginx.prod
NGINX_HOST=openctem.io
API_HOST=api.openctem.io
ADMIN_HOST=admin.openctem.io

# 3. Setup SSL certificates (see SSL section below)

# 4. Start production
make prod-up
```

## Configuration

### Environment Variables

| Variable | Staging Default | Production | Description |
|----------|-----------------|------------|-------------|
| `NGINX_HOST` | `localhost` | Required | UI domain (e.g., `openctem.io`) |
| `API_HOST` | `api.localhost` | Required | API domain (e.g., `api.openctem.io`) |
| `ADMIN_HOST` | `admin.localhost` | Required | Admin UI domain (e.g., `admin.openctem.io`) |

### Example Configurations

**Local Development:**
```bash
NGINX_HOST=localhost
API_HOST=api.localhost
ADMIN_HOST=admin.localhost
```

**Staging:**
```bash
NGINX_HOST=staging.openctem.io
API_HOST=api.staging.openctem.io
ADMIN_HOST=admin.staging.openctem.io
```

**Production:**
```bash
NGINX_HOST=openctem.io
API_HOST=api.openctem.io
ADMIN_HOST=admin.openctem.io
```

## Multi-Domain Setup

Nginx serves three domains with separate configurations:

### UI Domain (NGINX_HOST)
- Serves the Next.js tenant frontend
- Static asset caching
- WebSocket support for HMR

### API Domain (API_HOST)
- Serves the Go API backend
- CORS headers for cross-origin requests
- Different rate limits per endpoint:
  - `/api/v1/auth/*`: 5 req/s (authentication)
  - `/api/v1/agent/*`: 100 req/s (agent data ingest)
  - `/api/*`: 30 req/s (general API)
- WebSocket support for real-time updates
- Large payload support for agent data (50MB max)

### Admin UI Domain (ADMIN_HOST)
- Serves the Next.js admin panel
- Stricter security headers (CSP, robots deny)
- Stricter rate limiting (5 req/s vs 10 for tenant UI)
- Static asset caching
- Robots.txt returns "Disallow: /" (admin should NOT be indexed)

## SSL Certificates

### Option 1: Self-Signed (Staging/Development)

```bash
# Generate self-signed certificate for all domains
make init-ssl

# Or manually:
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem \
  -out nginx/ssl/cert.pem \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost,DNS:api.localhost,DNS:admin.localhost,DNS:*.openctem.io"
```

### Option 2: Let's Encrypt (Production)

```bash
# 1. Install Certbot
sudo apt install certbot

# 2. Stop any service on port 80
docker compose down

# 3. Obtain certificates for all domains
sudo certbot certonly --standalone \
  -d openctem.io \
  -d api.openctem.io \
  -d admin.openctem.io

# 4. Copy certificates
sudo cp /etc/letsencrypt/live/openctem.io/fullchain.pem nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/openctem.io/privkey.pem nginx/ssl/key.pem
sudo chmod 644 nginx/ssl/cert.pem
sudo chmod 600 nginx/ssl/key.pem

# 5. Start production
make prod-up
```

### Option 3: Commercial Certificate

1. Purchase wildcard SSL certificate (recommended for `*.openctem.io`)
2. Place certificate files in `nginx/ssl/`:
   - `cert.pem` - Certificate chain
   - `key.pem` - Private key

## Directory Structure

```
nginx/
├── nginx.conf                          # Main nginx configuration
├── templates/
│   ├── 00-upstreams.conf.template      # Shared upstream definitions
│   ├── admin-ui.conf.template          # Admin UI server block (admin.openctem.io)
│   ├── api.conf.template               # API server block (api.openctem.io)
│   └── ui.conf.template                # UI server block (openctem.io)
├── ssl/                                # SSL certificates directory
│   ├── .gitignore                      # Ignore certificate files
│   ├── cert.pem                        # SSL certificate (you provide)
│   └── key.pem                         # SSL private key (you provide)
└── README.md                           # This file
```

## Rate Limiting

Different rate limits are configured for different endpoints:

| Zone | Rate | Burst | Endpoints |
|------|------|-------|-----------|
| `ui_general` | 10 req/s | 20 | UI routes |
| `admin_general` | 5 req/s | 10 | Admin UI routes (stricter) |
| `api_general` | 30 req/s | 50 | General API (`/api/*`) |
| `api_auth` | 5 req/s | 10 | Authentication (`/api/v1/auth/*`) |
| `api_ingest` | 100 req/s | 200 | Agent data ingest (`/api/v1/agent/*`) |

## CORS Configuration

The API server is configured with CORS headers to allow requests from:
- `localhost` (development)
- `127.0.0.1` (development)
- `${NGINX_HOST}` (UI domain)
- `*.openctem.io` (all OpenCTEM subdomains)

## Management Commands

```bash
# Generate self-signed certificate
make init-ssl

# Show Let's Encrypt instructions
make init-ssl-letsencrypt

# Test nginx configuration
make nginx-test-staging    # Staging
make nginx-test-prod       # Production

# Reload nginx (after config changes)
make nginx-reload-staging  # Staging
make nginx-reload-prod     # Production

# View nginx logs
make nginx-logs-staging    # Staging
make nginx-logs-prod       # Production

# Reload after certificate renewal
make ssl-renew
```

## Security Features

- **TLS 1.2/1.3 only** - Older versions disabled
- **HSTS** - 1 year max-age with includeSubDomains and preload
- **Security Headers**:
  - `X-Frame-Options: DENY`
  - `X-Content-Type-Options: nosniff`
  - `X-XSS-Protection: 1; mode=block`
  - `Referrer-Policy: strict-origin-when-cross-origin`
- **Rate Limiting** - Per-IP limits on all endpoints
- **SSL Session Tickets** - Disabled for forward secrecy

## Certificate Renewal (Let's Encrypt)

```bash
# Renew certificates
sudo certbot renew

# Copy renewed certificates
sudo cp /etc/letsencrypt/live/openctem.io/fullchain.pem nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/openctem.io/privkey.pem nginx/ssl/key.pem

# Reload nginx
make ssl-renew
```

## Troubleshooting

### Certificate not trusted
- Ensure `cert.pem` contains the full certificate chain
- Check certificate validity: `openssl x509 -in nginx/ssl/cert.pem -text -noout`
- Verify SANs include both domains: `openssl x509 -in nginx/ssl/cert.pem -noout -ext subjectAltName`

### Permission denied
```bash
sudo chmod 644 nginx/ssl/cert.pem
sudo chmod 600 nginx/ssl/key.pem
```

### Nginx won't start
```bash
# Check logs
make nginx-logs-staging
# Or
make nginx-logs-prod

# Test config
make nginx-test-staging
# Or
make nginx-test-prod
```

### CORS errors
- Verify `API_HOST` is correctly set
- Check that the Origin header matches allowed patterns
- Look at nginx logs for blocked requests

### Rate limit exceeded (429)
- Check if legitimate traffic is being blocked
- Adjust rate limits in `api.conf.template` or `ui.conf.template`

### API not responding
- Verify API container is healthy: `docker compose ps`
- Check API logs: `docker compose logs api`
- Ensure nginx depends on API service in docker-compose
