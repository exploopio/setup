#!/usr/bin/env bash
# =============================================================================
# OpenCTEM Database Backup Script
# =============================================================================
# Performs pg_dump backups with configurable retention and rotation.
#
# Usage:
#   ./backup.sh                    # Full backup with defaults
#   ./backup.sh --type full        # Explicit full backup
#   ./backup.sh --type schema      # Schema-only backup
#   BACKUP_DIR=/mnt/backups ./backup.sh  # Custom backup directory
#
# Environment variables (with defaults):
#   DB_HOST       - Database host (default: localhost)
#   DB_PORT       - Database port (default: 5432)
#   DB_USER       - Database user (default: openctem)
#   DB_NAME       - Database name (default: openctem)
#   DB_PASSWORD   - Database password (reads from .pgpass if not set)
#   BACKUP_DIR    - Backup storage directory (default: /var/backups/openctem)
#   RETENTION_DAYS - Days to keep daily backups (default: 30)
#   RETENTION_WEEKLY - Weeks to keep weekly backups (default: 12)
#   RETENTION_MONTHLY - Months to keep monthly backups (default: 12)
#   COMPRESSION   - Compression method: gzip|lz4|zstd (default: gzip)
#
# Off-site backup (optional):
#   OFFSITE_ENABLED  - Enable off-site upload: true|false (default: false)
#   OFFSITE_PROVIDER - Cloud provider: s3|gcs|azure (default: s3)
#   OFFSITE_BUCKET   - Bucket/container name (required if enabled)
#   OFFSITE_PREFIX   - Object key prefix (default: openctem/backups)
#   OFFSITE_RETENTION_DAYS - Days to keep off-site backups (default: 90)
#
# Provider-specific configuration:
#   S3:    AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION, S3_ENDPOINT
#   GCS:   GOOGLE_APPLICATION_CREDENTIALS (service account JSON path)
#   Azure: AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_KEY
# =============================================================================

set -euo pipefail

# --- Configuration ---
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-openctem}"
DB_NAME="${DB_NAME:-openctem}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/openctem}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
RETENTION_WEEKLY="${RETENTION_WEEKLY:-12}"
RETENTION_MONTHLY="${RETENTION_MONTHLY:-12}"
COMPRESSION="${COMPRESSION:-gzip}"
OFFSITE_ENABLED="${OFFSITE_ENABLED:-false}"
OFFSITE_PROVIDER="${OFFSITE_PROVIDER:-s3}"
OFFSITE_BUCKET="${OFFSITE_BUCKET:-}"
OFFSITE_PREFIX="${OFFSITE_PREFIX:-openctem/backups}"
OFFSITE_RETENTION_DAYS="${OFFSITE_RETENTION_DAYS:-90}"
BACKUP_TYPE="${1:-full}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) BACKUP_TYPE="$2"; shift 2 ;;
        --dir)  BACKUP_DIR="$2"; shift 2 ;;
        *)      shift ;;
    esac
done

# --- Setup ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATE=$(date +%Y%m%d)
DAY_OF_WEEK=$(date +%u)  # 1=Monday, 7=Sunday
DAY_OF_MONTH=$(date +%d)
DAILY_DIR="${BACKUP_DIR}/daily"
WEEKLY_DIR="${BACKUP_DIR}/weekly"
MONTHLY_DIR="${BACKUP_DIR}/monthly"
LOG_FILE="${BACKUP_DIR}/backup.log"

mkdir -p "$DAILY_DIR" "$WEEKLY_DIR" "$MONTHLY_DIR"

# --- Logging ---
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE" >&2
}

# --- Compression extension ---
case "$COMPRESSION" in
    gzip) COMP_EXT="gz" ;;
    lz4)  COMP_EXT="lz4" ;;
    zstd) COMP_EXT="zst" ;;
    *)    log_error "Unknown compression: $COMPRESSION"; exit 1 ;;
esac

# --- Backup filename ---
BACKUP_FILE="openctem_${BACKUP_TYPE}_${TIMESTAMP}.sql.${COMP_EXT}"
BACKUP_PATH="${DAILY_DIR}/${BACKUP_FILE}"

# --- Pre-flight checks ---
if ! command -v pg_dump &>/dev/null; then
    log_error "pg_dump not found. Install postgresql-client."
    exit 1
fi

# Export password for pg_dump
export PGPASSWORD="${DB_PASSWORD:-}"

# Test connection
if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -q 2>/dev/null; then
    log_error "Cannot connect to database at ${DB_HOST}:${DB_PORT}"
    exit 1
fi

# --- Perform backup ---
log "Starting ${BACKUP_TYPE} backup of ${DB_NAME}@${DB_HOST}:${DB_PORT}"

PG_DUMP_OPTS=(
    -h "$DB_HOST"
    -p "$DB_PORT"
    -U "$DB_USER"
    -d "$DB_NAME"
    --no-owner
    --no-acl
    --verbose
)

case "$BACKUP_TYPE" in
    full)
        PG_DUMP_OPTS+=(--format=custom)
        BACKUP_FILE="openctem_${BACKUP_TYPE}_${TIMESTAMP}.dump"
        BACKUP_PATH="${DAILY_DIR}/${BACKUP_FILE}"
        pg_dump "${PG_DUMP_OPTS[@]}" -f "$BACKUP_PATH" 2>> "$LOG_FILE"
        ;;
    schema)
        PG_DUMP_OPTS+=(--schema-only)
        pg_dump "${PG_DUMP_OPTS[@]}" 2>> "$LOG_FILE" | \
            case "$COMPRESSION" in
                gzip) gzip -9 ;;
                lz4)  lz4 -9 ;;
                zstd) zstd -19 ;;
            esac > "$BACKUP_PATH"
        ;;
    *)
        log_error "Unknown backup type: $BACKUP_TYPE (use: full, schema)"
        exit 1
        ;;
esac

# Verify backup file exists and is non-empty
if [[ ! -s "$BACKUP_PATH" ]]; then
    log_error "Backup file is empty or missing: $BACKUP_PATH"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log "Backup completed: ${BACKUP_FILE} (${BACKUP_SIZE})"

# --- Generate checksum ---
sha256sum "$BACKUP_PATH" > "${BACKUP_PATH}.sha256"
log "Checksum saved: ${BACKUP_FILE}.sha256"

# --- Copy to weekly/monthly as needed ---
if [[ "$DAY_OF_WEEK" == "7" ]]; then
    cp "$BACKUP_PATH" "$WEEKLY_DIR/"
    [[ -f "${BACKUP_PATH}.sha256" ]] && cp "${BACKUP_PATH}.sha256" "$WEEKLY_DIR/"
    log "Weekly backup copied"
fi

if [[ "$DAY_OF_MONTH" == "01" ]]; then
    cp "$BACKUP_PATH" "$MONTHLY_DIR/"
    [[ -f "${BACKUP_PATH}.sha256" ]] && cp "${BACKUP_PATH}.sha256" "$MONTHLY_DIR/"
    log "Monthly backup copied"
fi

# --- Retention cleanup ---
log "Applying retention policy: daily=${RETENTION_DAYS}d, weekly=${RETENTION_WEEKLY}w, monthly=${RETENTION_MONTHLY}m"

find "$DAILY_DIR" -name "openctem_*" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null
WEEKLY_RETENTION_DAYS=$((RETENTION_WEEKLY * 7))
find "$WEEKLY_DIR" -name "openctem_*" -type f -mtime +"$WEEKLY_RETENTION_DAYS" -delete 2>/dev/null
MONTHLY_RETENTION_DAYS=$((RETENTION_MONTHLY * 31))
find "$MONTHLY_DIR" -name "openctem_*" -type f -mtime +"$MONTHLY_RETENTION_DAYS" -delete 2>/dev/null

log "Retention cleanup completed"

# --- Summary ---
DAILY_COUNT=$(find "$DAILY_DIR" -name "openctem_*" -not -name "*.sha256" | wc -l)
WEEKLY_COUNT=$(find "$WEEKLY_DIR" -name "openctem_*" -not -name "*.sha256" | wc -l)
MONTHLY_COUNT=$(find "$MONTHLY_DIR" -name "openctem_*" -not -name "*.sha256" | wc -l)
log "Backup inventory: daily=${DAILY_COUNT}, weekly=${WEEKLY_COUNT}, monthly=${MONTHLY_COUNT}"

# --- Off-site upload ---
retry() {
    local max_attempts="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        if "$@"; then
            return 0
        fi
        log "Attempt ${attempt}/${max_attempts} failed: $*"
        if [[ $attempt -lt $max_attempts ]]; then
            log "Retrying in ${delay}s..."
            sleep "$delay"
        fi
        ((attempt++))
    done
    log_error "All ${max_attempts} attempts failed: $*"
    return 1
}

offsite_upload() {
    local file="$1"
    local filename
    filename=$(basename "$file")
    local tier="$2"  # daily, weekly, monthly
    local remote_path="${OFFSITE_PREFIX}/${tier}/${filename}"

    case "$OFFSITE_PROVIDER" in
        s3)
            local s3_opts=()
            if [[ -n "${S3_ENDPOINT:-}" ]]; then
                s3_opts+=(--endpoint-url "$S3_ENDPOINT")
            fi
            retry 3 5 aws s3 cp "${s3_opts[@]}" "$file" "s3://${OFFSITE_BUCKET}/${remote_path}" --quiet
            ;;
        gcs)
            retry 3 5 gsutil -q cp "$file" "gs://${OFFSITE_BUCKET}/${remote_path}"
            ;;
        azure)
            retry 3 5 az storage blob upload \
                --account-name "${AZURE_STORAGE_ACCOUNT}" \
                --account-key "${AZURE_STORAGE_KEY}" \
                --container-name "${OFFSITE_BUCKET}" \
                --name "${remote_path}" \
                --file "$file" \
                --overwrite --only-show-errors
            ;;
        *)
            log_error "Unknown off-site provider: $OFFSITE_PROVIDER"
            return 1
            ;;
    esac
}

offsite_cleanup() {
    local cutoff_date
    cutoff_date=$(date -d "-${OFFSITE_RETENTION_DAYS} days" +%Y-%m-%d 2>/dev/null || \
                  date -v-${OFFSITE_RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null)

    case "$OFFSITE_PROVIDER" in
        s3)
            local s3_opts=()
            if [[ -n "${S3_ENDPOINT:-}" ]]; then
                s3_opts+=(--endpoint-url "$S3_ENDPOINT")
            fi
            # List and delete objects older than retention period
            aws s3api list-objects-v2 "${s3_opts[@]}" \
                --bucket "$OFFSITE_BUCKET" \
                --prefix "${OFFSITE_PREFIX}/daily/" \
                --query "Contents[?LastModified<='${cutoff_date}'].Key" \
                --output text 2>/dev/null | tr '\t' '\n' | while read -r key; do
                    [[ -n "$key" && "$key" != "None" ]] && \
                        aws s3 rm "${s3_opts[@]}" "s3://${OFFSITE_BUCKET}/${key}" --quiet
                done
            ;;
        gcs)
            gsutil ls -l "gs://${OFFSITE_BUCKET}/${OFFSITE_PREFIX}/daily/" 2>/dev/null | \
                awk -v cutoff="$cutoff_date" '$2 < cutoff {print $3}' | while read -r uri; do
                    [[ -n "$uri" ]] && gsutil -q rm "$uri"
                done
            ;;
        azure)
            az storage blob list \
                --account-name "${AZURE_STORAGE_ACCOUNT}" \
                --account-key "${AZURE_STORAGE_KEY}" \
                --container-name "${OFFSITE_BUCKET}" \
                --prefix "${OFFSITE_PREFIX}/daily/" \
                --query "[?properties.lastModified<='${cutoff_date}'].name" \
                --output tsv 2>/dev/null | while read -r blob; do
                    [[ -n "$blob" ]] && az storage blob delete \
                        --account-name "${AZURE_STORAGE_ACCOUNT}" \
                        --account-key "${AZURE_STORAGE_KEY}" \
                        --container-name "${OFFSITE_BUCKET}" \
                        --name "$blob" --only-show-errors
                done
            ;;
    esac
}

if [[ "$OFFSITE_ENABLED" == "true" ]]; then
    if [[ -z "$OFFSITE_BUCKET" ]]; then
        log_error "OFFSITE_BUCKET is required when OFFSITE_ENABLED=true"
    else
        # Pre-flight: check cloud CLI is installed
        case "$OFFSITE_PROVIDER" in
            s3)
                if ! command -v aws &>/dev/null; then
                    log_error "aws CLI not found. Install awscli to use S3 offsite backups."
                    exit 1
                fi
                ;;
            gcs)
                if ! command -v gsutil &>/dev/null; then
                    log_error "gsutil not found. Install google-cloud-sdk to use GCS offsite backups."
                    exit 1
                fi
                ;;
            azure)
                if ! command -v az &>/dev/null; then
                    log_error "az CLI not found. Install azure-cli to use Azure offsite backups."
                    exit 1
                fi
                ;;
        esac

        # Pre-flight: validate cloud credentials
        log "Validating ${OFFSITE_PROVIDER} credentials..."
        case "$OFFSITE_PROVIDER" in
            s3)
                s3_preflight_opts=()
                if [[ -n "${S3_ENDPOINT:-}" ]]; then
                    s3_preflight_opts+=(--endpoint-url "$S3_ENDPOINT")
                fi
                if ! aws sts get-caller-identity "${s3_preflight_opts[@]}" &>/dev/null; then
                    log_error "AWS credential validation failed. Check AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY."
                    exit 1
                fi
                ;;
            gcs)
                if ! gsutil ls "gs://${OFFSITE_BUCKET}" &>/dev/null; then
                    log_error "GCS credential validation failed. Check GOOGLE_APPLICATION_CREDENTIALS and bucket access."
                    exit 1
                fi
                ;;
            azure)
                if ! az account show &>/dev/null; then
                    log_error "Azure credential validation failed. Check AZURE_STORAGE_ACCOUNT and AZURE_STORAGE_KEY."
                    exit 1
                fi
                ;;
        esac
        log "Credentials validated successfully"

        log "Uploading backup to ${OFFSITE_PROVIDER}://${OFFSITE_BUCKET}/${OFFSITE_PREFIX}/"

        # Upload backup + checksum to daily tier
        if offsite_upload "$BACKUP_PATH" "daily" && \
           offsite_upload "${BACKUP_PATH}.sha256" "daily"; then
            log "Off-site daily upload completed"
        else
            log_error "Off-site daily upload failed"
        fi

        # Upload to weekly tier
        if [[ "$DAY_OF_WEEK" == "7" ]]; then
            if offsite_upload "$BACKUP_PATH" "weekly" && \
               offsite_upload "${BACKUP_PATH}.sha256" "weekly"; then
                log "Off-site weekly upload completed"
            else
                log_error "Off-site weekly upload failed"
            fi
        fi

        # Upload to monthly tier
        if [[ "$DAY_OF_MONTH" == "01" ]]; then
            if offsite_upload "$BACKUP_PATH" "monthly" && \
               offsite_upload "${BACKUP_PATH}.sha256" "monthly"; then
                log "Off-site monthly upload completed"
            else
                log_error "Off-site monthly upload failed"
            fi
        fi

        # Clean up old off-site backups
        log "Cleaning off-site backups older than ${OFFSITE_RETENTION_DAYS} days"
        offsite_cleanup 2>/dev/null || log "Off-site cleanup skipped (non-critical)"
    fi
fi

log "Backup completed successfully"

unset PGPASSWORD
