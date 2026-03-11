#!/usr/bin/env bash
# =============================================================================
# OpenCTEM WAL Archiving Configuration
# =============================================================================
# Configures PostgreSQL Write-Ahead Log (WAL) archiving for point-in-time
# recovery (PITR). Run this script to set up WAL archiving on the PostgreSQL
# server.
#
# Prerequisites:
#   - PostgreSQL 14+ with superuser access
#   - Archive directory with write permissions
#
# Usage:
#   ./wal-archive.sh setup     # Configure WAL archiving
#   ./wal-archive.sh status    # Check archiving status
#   ./wal-archive.sh restore-command <target_time>  # Print restore command
# =============================================================================

set -euo pipefail

DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-openctem}"
DB_NAME="${DB_NAME:-openctem}"
WAL_ARCHIVE_DIR="${WAL_ARCHIVE_DIR:-/var/backups/openctem/wal}"

export PGPASSWORD="${DB_PASSWORD:-}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

psql_cmd() {
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null
}

case "${1:-status}" in
    setup)
        log "Setting up WAL archiving..."

        mkdir -p "$WAL_ARCHIVE_DIR"

        # Check current settings
        CURRENT_LEVEL=$(psql_cmd "SHOW wal_level;")
        CURRENT_ARCHIVE=$(psql_cmd "SHOW archive_mode;")

        log "Current wal_level: ${CURRENT_LEVEL}"
        log "Current archive_mode: ${CURRENT_ARCHIVE}"

        if [[ "$CURRENT_LEVEL" != "replica" && "$CURRENT_LEVEL" != "logical" ]]; then
            log "WARNING: wal_level must be 'replica' or 'logical' for archiving"
            log "Add to postgresql.conf:"
            echo "  wal_level = replica"
            echo "  archive_mode = on"
            echo "  archive_command = 'cp %p ${WAL_ARCHIVE_DIR}/%f'"
            echo "  archive_timeout = 300"
            log "Then restart PostgreSQL"
            exit 1
        fi

        if [[ "$CURRENT_ARCHIVE" != "on" ]]; then
            log "WARNING: archive_mode is not 'on'"
            log "Add to postgresql.conf:"
            echo "  archive_mode = on"
            echo "  archive_command = 'cp %p ${WAL_ARCHIVE_DIR}/%f'"
            echo "  archive_timeout = 300"
            log "Then restart PostgreSQL"
            exit 1
        fi

        log "WAL archiving is properly configured"
        log "Archive directory: ${WAL_ARCHIVE_DIR}"

        # Show archive stats
        WAL_COUNT=$(find "$WAL_ARCHIVE_DIR" -name "0*" -type f 2>/dev/null | wc -l)
        WAL_SIZE=$(du -sh "$WAL_ARCHIVE_DIR" 2>/dev/null | cut -f1 || echo "0")
        log "Archived WAL files: ${WAL_COUNT} (${WAL_SIZE})"

        # Cleanup old WAL files (keep 7 days by default)
        WAL_RETENTION_DAYS="${WAL_RETENTION_DAYS:-7}"
        DELETED=$(find "$WAL_ARCHIVE_DIR" -name "0*" -type f -mtime +"$WAL_RETENTION_DAYS" -delete -print 2>/dev/null | wc -l)
        if [[ "$DELETED" -gt 0 ]]; then
            log "Cleaned up ${DELETED} WAL files older than ${WAL_RETENTION_DAYS} days"
        fi
        ;;

    status)
        log "WAL Archiving Status"
        echo "---"
        echo "wal_level:       $(psql_cmd 'SHOW wal_level;')"
        echo "archive_mode:    $(psql_cmd 'SHOW archive_mode;')"
        echo "archive_command: $(psql_cmd 'SHOW archive_command;')"
        echo "archive_timeout: $(psql_cmd 'SHOW archive_timeout;')"
        echo "---"

        if [[ -d "$WAL_ARCHIVE_DIR" ]]; then
            WAL_COUNT=$(find "$WAL_ARCHIVE_DIR" -name "0*" -type f 2>/dev/null | wc -l)
            WAL_SIZE=$(du -sh "$WAL_ARCHIVE_DIR" 2>/dev/null | cut -f1 || echo "0")
            NEWEST=$(find "$WAL_ARCHIVE_DIR" -name "0*" -type f -printf '%T+ %f\n' 2>/dev/null | sort -r | head -1 || echo "none")
            echo "Archive dir:     ${WAL_ARCHIVE_DIR}"
            echo "WAL files:       ${WAL_COUNT} (${WAL_SIZE})"
            echo "Newest WAL:      ${NEWEST}"
        else
            echo "Archive dir:     ${WAL_ARCHIVE_DIR} (not created)"
        fi
        ;;

    restore-command)
        TARGET_TIME="${2:-}"
        if [[ -z "$TARGET_TIME" ]]; then
            echo "Usage: $0 restore-command '<timestamp>'"
            echo "Example: $0 restore-command '2026-03-06 14:30:00'"
            exit 1
        fi

        echo "# Point-in-Time Recovery Steps:"
        echo "#"
        echo "# 1. Stop PostgreSQL"
        echo "#    systemctl stop postgresql"
        echo ""
        echo "# 2. Back up current data directory"
        echo "#    cp -r /var/lib/postgresql/17/main /var/lib/postgresql/17/main.bak"
        echo ""
        echo "# 3. Restore base backup"
        echo "#    ./restore.sh <latest_base_backup>"
        echo ""
        echo "# 4. Create recovery.signal"
        echo "#    touch /var/lib/postgresql/17/main/recovery.signal"
        echo ""
        echo "# 5. Add to postgresql.conf:"
        echo "restore_command = 'cp ${WAL_ARCHIVE_DIR}/%f %p'"
        echo "recovery_target_time = '${TARGET_TIME}'"
        echo "recovery_target_action = 'promote'"
        echo ""
        echo "# 6. Start PostgreSQL"
        echo "#    systemctl start postgresql"
        echo ""
        echo "# 7. Verify recovery"
        echo "#    psql -c 'SELECT pg_is_in_recovery();'  -- should return 'f' after promote"
        ;;

    *)
        echo "Usage: $0 {setup|status|restore-command <timestamp>}"
        exit 1
        ;;
esac

unset PGPASSWORD
