#!/bin/bash

set -euo pipefail

BACKUP_DIR="/opt/hamr/backups"
LOG_FILE="/var/log/hamr-restore.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $*"
    exit 1
}

usage() {
    echo "Usage: $0 <type> <backup_file>"
    echo ""
    echo "Types:"
    echo "  postgres   - Restore PostgreSQL from .sql.gz file"
    echo "  redis      - Restore Redis from .rdb.gz file"
    echo ""
    echo "Examples:"
    echo "  $0 postgres $BACKUP_DIR/postgres/hamr_db_20260310_020000.sql.gz"
    echo "  $0 redis    $BACKUP_DIR/redis/hamr_redis_20260310_020000.rdb.gz"
    exit 1
}

restore_postgres() {
    local backup_file=$1
    [ -f "$backup_file" ] || error_exit "Backup file not found: $backup_file"

    log "Restoring PostgreSQL from: $backup_file"
    log "WARNING: This will overwrite all databases!"
    read -r -p "Continue? (yes/NO): " confirm
    [ "$confirm" = "yes" ] || { log "Aborted."; exit 0; }

    gunzip -c "$backup_file" | docker exec -i hamr-postgres psql -U postgres \
        || error_exit "PostgreSQL restore failed"
    log "PostgreSQL restore completed"
}

restore_redis() {
    local backup_file=$1
    [ -f "$backup_file" ] || error_exit "Backup file not found: $backup_file"

    log "Restoring Redis from: $backup_file"
    log "WARNING: This will overwrite current Redis data!"
    read -r -p "Continue? (yes/NO): " confirm
    [ "$confirm" = "yes" ] || { log "Aborted."; exit 0; }

    docker exec hamr-redis redis-cli SHUTDOWN NOSAVE 2>/dev/null || true
    gunzip -c "$backup_file" > /tmp/dump.rdb
    docker cp /tmp/dump.rdb hamr-redis:/data/dump.rdb
    docker start hamr-redis
    rm -f /tmp/dump.rdb
    log "Redis restore completed"
}

[ $# -lt 2 ] && usage

TYPE=$1
BACKUP_FILE=$2

case "$TYPE" in
    postgres) restore_postgres "$BACKUP_FILE" ;;
    redis)    restore_redis "$BACKUP_FILE" ;;
    *)        usage ;;
esac
