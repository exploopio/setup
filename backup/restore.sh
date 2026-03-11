#!/usr/bin/env bash
# =============================================================================
# OpenCTEM Database Restore Script
# =============================================================================
# Restores a database backup created by backup.sh.
#
# Usage:
#   ./restore.sh <backup_file>              # Restore to existing database
#   ./restore.sh <backup_file> --verify     # Verify backup integrity only
#   ./restore.sh <backup_file> --target newdb  # Restore to different database
#   ./restore.sh --list                     # List available backups
#
# Environment variables:
#   DB_HOST, DB_PORT, DB_USER, DB_NAME, DB_PASSWORD (same as backup.sh)
#   BACKUP_DIR - Where backups are stored (default: /var/backups/openctem)
# =============================================================================

set -euo pipefail

# --- Configuration ---
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-openctem}"
DB_NAME="${DB_NAME:-openctem}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/openctem}"

VERIFY_ONLY=false
TARGET_DB=""
BACKUP_FILE=""

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)  VERIFY_ONLY=true; shift ;;
        --target)  TARGET_DB="$2"; shift 2 ;;
        --list)
            echo "Available backups:"
            echo ""
            echo "=== Daily ==="
            ls -lhtr "${BACKUP_DIR}/daily"/openctem_* 2>/dev/null | grep -v '.sha256' || echo "  (none)"
            echo ""
            echo "=== Weekly ==="
            ls -lhtr "${BACKUP_DIR}/weekly"/openctem_* 2>/dev/null | grep -v '.sha256' || echo "  (none)"
            echo ""
            echo "=== Monthly ==="
            ls -lhtr "${BACKUP_DIR}/monthly"/openctem_* 2>/dev/null | grep -v '.sha256' || echo "  (none)"
            exit 0
            ;;
        -*) echo "Unknown option: $1"; exit 1 ;;
        *)  BACKUP_FILE="$1"; shift ;;
    esac
done

if [[ -z "$BACKUP_FILE" ]]; then
    echo "Usage: $0 <backup_file> [--verify] [--target <dbname>]"
    echo "       $0 --list"
    exit 1
fi

# Resolve backup file path
if [[ ! -f "$BACKUP_FILE" ]]; then
    # Try looking in backup directories
    for dir in "$BACKUP_DIR/daily" "$BACKUP_DIR/weekly" "$BACKUP_DIR/monthly"; do
        if [[ -f "${dir}/${BACKUP_FILE}" ]]; then
            BACKUP_FILE="${dir}/${BACKUP_FILE}"
            break
        fi
    done
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "ERROR: Backup file not found: $BACKUP_FILE"
    exit 1
fi

RESTORE_DB="${TARGET_DB:-$DB_NAME}"
export PGPASSWORD="${DB_PASSWORD:-}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# --- Verify checksum ---
CHECKSUM_FILE="${BACKUP_FILE}.sha256"
if [[ -f "$CHECKSUM_FILE" ]]; then
    log "Verifying backup checksum..."
    if sha256sum --check "$CHECKSUM_FILE" --quiet 2>/dev/null; then
        log "Checksum verified: OK"
    else
        log_error "Checksum verification FAILED"
        exit 1
    fi
else
    log "WARNING: No checksum file found, skipping integrity check"
fi

# --- Verify backup contents ---
log "Verifying backup contents..."
if [[ "$BACKUP_FILE" == *.dump ]]; then
    # Custom format - use pg_restore to verify
    if pg_restore --list "$BACKUP_FILE" > /dev/null 2>&1; then
        TABLE_COUNT=$(pg_restore --list "$BACKUP_FILE" 2>/dev/null | grep -c "TABLE " || true)
        log "Backup contains ${TABLE_COUNT} table entries"
    else
        log_error "Backup file appears to be corrupt"
        exit 1
    fi
else
    # SQL format - check for basic markers
    DECOMPRESSED=$(mktemp)
    trap "rm -f '$DECOMPRESSED'" EXIT

    case "$BACKUP_FILE" in
        *.gz)  gunzip -c "$BACKUP_FILE" > "$DECOMPRESSED" ;;
        *.lz4) lz4 -dc "$BACKUP_FILE" > "$DECOMPRESSED" ;;
        *.zst) zstd -dc "$BACKUP_FILE" > "$DECOMPRESSED" ;;
        *)     cp "$BACKUP_FILE" "$DECOMPRESSED" ;;
    esac

    if head -50 "$DECOMPRESSED" | grep -q "PostgreSQL database dump"; then
        log "Backup format verified: PostgreSQL dump"
    else
        log_error "File does not appear to be a PostgreSQL dump"
        exit 1
    fi
fi

if $VERIFY_ONLY; then
    log "Verification complete. Backup is valid."
    exit 0
fi

# --- Safety confirmation ---
echo ""
echo "WARNING: This will restore the backup to database '${RESTORE_DB}'."
echo "  Backup file: $(basename "$BACKUP_FILE")"
echo "  Backup size: $(du -h "$BACKUP_FILE" | cut -f1)"
echo "  Target host: ${DB_HOST}:${DB_PORT}"
echo "  Target database: ${RESTORE_DB}"
echo ""
read -r -p "Are you sure you want to proceed? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    log "Restore cancelled by user"
    exit 0
fi

# --- Create target database if needed ---
if [[ -n "$TARGET_DB" ]]; then
    log "Creating target database: ${TARGET_DB}"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres \
        -c "CREATE DATABASE \"${TARGET_DB}\" OWNER \"${DB_USER}\";" 2>/dev/null || \
        log "Database ${TARGET_DB} already exists"
fi

# --- Perform restore ---
log "Starting restore to ${RESTORE_DB}..."

if [[ "$BACKUP_FILE" == *.dump ]]; then
    # Custom format restore
    pg_restore \
        -h "$DB_HOST" \
        -p "$DB_PORT" \
        -U "$DB_USER" \
        -d "$RESTORE_DB" \
        --clean \
        --if-exists \
        --no-owner \
        --no-acl \
        --verbose \
        "$BACKUP_FILE" 2>&1 | tail -20
else
    # SQL format restore
    case "$BACKUP_FILE" in
        *.gz)  gunzip -c "$BACKUP_FILE" ;;
        *.lz4) lz4 -dc "$BACKUP_FILE" ;;
        *.zst) zstd -dc "$BACKUP_FILE" ;;
        *)     cat "$BACKUP_FILE" ;;
    esac | psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$RESTORE_DB" \
        --single-transaction \
        --set ON_ERROR_STOP=1 2>&1 | tail -20
fi

RESTORE_STATUS=$?

if [[ $RESTORE_STATUS -eq 0 ]]; then
    log "Restore completed successfully"

    # Verify restored database
    log "Verifying restored database..."
    TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$RESTORE_DB" \
        -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
    log "Restored database has ${TABLE_COUNT} tables"
else
    log_error "Restore failed with exit code: $RESTORE_STATUS"
    exit 1
fi

unset PGPASSWORD
