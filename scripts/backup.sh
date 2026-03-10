#!/bin/bash

set -euo pipefail

BACKUP_DIR="/opt/hamr/backups"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=30
LOG_FILE="/var/log/hamr-backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $*"
    exit 1
}

backup_postgres() {
    log "Starting PostgreSQL backup..."
    local backup_file="$BACKUP_DIR/postgres/hamr_db_${DATE}.sql.gz"
    mkdir -p "$BACKUP_DIR/postgres"

    if docker ps --format '{{.Names}}' | grep -q "^hamr-postgres$"; then
        docker exec hamr-postgres pg_dumpall -U postgres | gzip > "$backup_file" \
            || error_exit "PostgreSQL backup failed"
        log "PostgreSQL backup saved: $backup_file ($(du -sh "$backup_file" | cut -f1))"
    else
        log "WARN: hamr-postgres container not running, skipping"
    fi
}

backup_redis() {
    log "Starting Redis backup..."
    local backup_file="$BACKUP_DIR/redis/hamr_redis_${DATE}.rdb"
    mkdir -p "$BACKUP_DIR/redis"

    if docker ps --format '{{.Names}}' | grep -q "^hamr-redis$"; then
        docker exec hamr-redis redis-cli BGSAVE
        sleep 3
        docker cp hamr-redis:/data/dump.rdb "$backup_file" \
            || error_exit "Redis backup failed"
        gzip "$backup_file"
        log "Redis backup saved: ${backup_file}.gz ($(du -sh "${backup_file}.gz" | cut -f1))"
    else
        log "WARN: hamr-redis container not running, skipping"
    fi
}

backup_configs() {
    log "Starting config files backup..."
    local backup_file="$BACKUP_DIR/configs/hamr_configs_${DATE}.tar.gz"
    mkdir -p "$BACKUP_DIR/configs"

    tar -czf "$backup_file" \
        /opt/hamr/proxy/nginx.conf \
        /opt/hamr/proxy/docker-compose.yml \
        /opt/monitoring/ \
        2>/dev/null || log "WARN: Some config files may be missing"

    log "Config backup saved: $backup_file ($(du -sh "$backup_file" | cut -f1))"
}

cleanup_old_backups() {
    log "Cleaning up backups older than ${RETENTION_DAYS} days..."
    find "$BACKUP_DIR" -type f \( -name "*.gz" -o -name "*.tar.gz" \) \
        -mtime +"$RETENTION_DAYS" -delete
    log "Cleanup done"
}

verify_backup() {
    local file=$1
    if [ -f "$file" ] && [ -s "$file" ]; then
        log "Verification OK: $file"
        return 0
    else
        log "ERROR: Backup file missing or empty: $file"
        return 1
    fi
}

main() {
    log "========== HamR Backup Started =========="
    mkdir -p "$BACKUP_DIR"/{postgres,redis,configs}

    backup_postgres
    backup_redis
    backup_configs
    cleanup_old_backups

    log "========== HamR Backup Completed =========="
    log "Backup directory size: $(du -sh "$BACKUP_DIR" | cut -f1)"
}

main "$@"
