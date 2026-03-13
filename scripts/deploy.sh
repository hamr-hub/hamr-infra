#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILDS_DIR="/opt/hamr/builds"
BACKUP_DIR="/opt/hamr/backups"

ALI_HOST="ali.hamr.top"
TX_HOST="tx.hamr.store"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}>>>${NC} $*"; }
log_warn()  { echo -e "${YELLOW}>>>${NC} $*"; }
log_error() { echo -e "${RED}>>>${NC} $*"; }

DEPLOY_FAILURES=()

deploy_guard() {
    local service=$1
    local server; server="$(get_server "$service")"
    local image; image="$(get_image "$service")"

    log_info "Pre-deploy: backing up $image on $server ..."
    ssh "$server" "
        if docker image inspect ${image}:latest >/dev/null 2>&1; then
            docker tag ${image}:latest ${image}:rollback 2>/dev/null || true
        fi
        mkdir -p $BACKUP_DIR
    " 2>/dev/null || true
}

rollback_service() {
    local service=$1
    local server; server="$(get_server "$service")"
    local image; image="$(get_image "$service")"
    local compose_dir; compose_dir="$(get_compose_dir "$server")"

    log_warn "Rolling back $image on $server ..."
    ssh "$server" "
        if docker image inspect ${image}:rollback >/dev/null 2>&1; then
            docker tag ${image}:rollback ${image}:latest
            cd $compose_dir && docker compose up -d --no-deps $image 2>&1
            echo 'Rollback complete'
        else
            echo 'No rollback image available'
        fi
    " 2>/dev/null || log_error "Rollback failed for $image"
}

# 服务 → Docker镜像名
declare -A SERVICE_MAP=(
    [website]="hamr-website"
    [help]="hamr-help"
    [developer]="hamr-developer"
    [docs]="hamr-docs"
    [account]="hamr-account"
    [account-api]="hamr-account-api"
    [app]="hamr-app"
    [app-api]="hamr-app-api"
    [jiabu]="hamr-jiabu"
    [jiabu-api]="hamr-jiabu-api"
    [status]="hamr-status"
    [api-gateway]="hamr-api-gateway"
    [deploy]="hamr-deploy"
    [demo]="hamr-demo"
    [demo-api]="hamr-demo-api"
)

# 服务 → 源码相对路径（相对 repos/）
declare -A SOURCE_MAP=(
    [website]="hamr-website"
    [help]="hamr-help"
    [developer]="hamr-developer"
    [docs]="hamr-docs"
    [account]="hamr-account/frontend"
    [account-api]="hamr-account/backend"
    [app]="hamr-app/frontend"
    [app-api]="hamr-app/backend"
    [jiabu]="hamr-jiabu/frontend"
    [jiabu-api]="hamr-jiabu/backend"
    [status]="hamr-status"
    [api-gateway]="hamr-api"
    [deploy]="hamr-deploy"
    [demo]="hamr-demo/frontend"
    [demo-api]="hamr-demo/backend"
)

ALI_SERVICES=(website help account account-api app app-api jiabu jiabu-api status api-gateway deploy demo demo-api)
TX_SERVICES=(developer docs)

usage() {
    echo "Usage: $0 <command> [service]"
    echo ""
    echo "Commands:"
    echo "  deploy [service]   - Backup + build + restart (all or specific)"
    echo "  build [service]    - Sync + build image only"
    echo "  restart <service>  - Restart a service (no rebuild)"
    echo "  rollback <service> - Rollback to previous version"
    echo "  status             - Show running containers"
    echo "  logs <service>     - Follow service logs"
    echo "  sync <service>     - Force upload source to server"
    echo ""
    echo "Services (ali): website, help, account, account-api, app, app-api, jiabu, jiabu-api, status, api-gateway, deploy, demo, demo-api"
    echo "Services (tx):  developer, docs"
    exit 1
}

get_server() {
    case "$1" in
        website|help|account|account-api|app|app-api|jiabu|jiabu-api|status|api-gateway|deploy) echo "$ALI_HOST" ;;
        developer|docs) echo "$TX_HOST" ;;
        *) echo "" ;;
    esac
}

get_image() { echo "${SERVICE_MAP[$1]:-$1}"; }
get_source() { echo "${SOURCE_MAP[$1]:-$1}"; }

get_compose_dir() {
    if [ "$1" = "$ALI_HOST" ]; then echo "/opt/hamr/ali"
    else echo "/opt/hamr/tx"; fi
}

# 打包并上传源码，然后构建镜像
scp_and_build() {
    local service=$1
    local image; image="$(get_image "$service")"
    local src_rel; src_rel="$(get_source "$service")"
    local server; server="$(get_server "$service")"
    local src_dir="$INFRA_ROOT/../repos/$src_rel"

    if [ ! -d "$src_dir" ]; then
        echo "ERROR: Source not found: $src_dir"
        return 1
    fi

    local parent; parent="$(dirname "$src_dir")"
    local base; base="$(basename "$src_dir")"

    echo ">>> Packing $image from repos/$src_rel ..."
    local tarfile="/tmp/${image}.tar.gz"
    tar czf "$tarfile" \
        -C "$parent" \
        --exclude="$base/node_modules" \
        --exclude="$base/dist" \
        --exclude="$base/.git" \
        --exclude="$base/target" \
        "$base"

    echo ">>> Uploading to $server:$BUILDS_DIR/$image ..."
    ssh "$server" "mkdir -p $BUILDS_DIR/$image"
    scp "$tarfile" "$server:/tmp/${image}.tar.gz"
    ssh "$server" "rm -rf $BUILDS_DIR/$image && mkdir -p $BUILDS_DIR && tar xzf /tmp/${image}.tar.gz -C $BUILDS_DIR/ && mv $BUILDS_DIR/$base $BUILDS_DIR/$image 2>/dev/null || true && rm /tmp/${image}.tar.gz"

    echo ">>> [$server] docker build $image ..."
    ssh "$server" "cd $BUILDS_DIR/$image && docker build -t ${image}:latest . 2>&1"
    echo ">>> Build done: $image"
}

# git pull 后构建（服务器上有 git repo 时使用）
git_pull_and_build() {
    local service=$1
    local image; image="$(get_image "$service")"
    local server; server="$(get_server "$service")"

    echo ">>> [$server] git pull $image ..."
    ssh "$server" "cd $BUILDS_DIR/$image && git pull origin main 2>&1 || echo 'WARN: git pull failed'"
    echo ">>> [$server] docker build $image ..."
    ssh "$server" "cd $BUILDS_DIR/$image && docker build -t ${image}:latest . 2>&1"
    echo ">>> Build done: $image"
}

compose_restart() {
    local service=$1
    local server; server="$(get_server "$service")"
    local image; image="$(get_image "$service")"
    local compose_dir; compose_dir="$(get_compose_dir "$server")"

    echo ">>> Syncing compose config to $server:$compose_dir ..."
    if [ "$server" = "$ALI_HOST" ]; then
        scp "$INFRA_ROOT/services/ali/docker-compose.yml" "$server:$compose_dir/docker-compose.yml"
    else
        scp "$INFRA_ROOT/services/tx/docker-compose.yml" "$server:$compose_dir/docker-compose.yml"
    fi

    echo ">>> Restarting $image on $server ..."
    ssh "$server" "cd $compose_dir && docker compose up -d --no-deps $image 2>&1"
    echo ">>> $image is up"
}

do_build() {
    local service=$1
    local server; server="$(get_server "$service")"

    # 检查服务器是否有 git repo
    if ssh "$server" "test -d $BUILDS_DIR/$(get_image "$service")/.git" 2>/dev/null; then
        git_pull_and_build "$service"
    else
        scp_and_build "$service"
    fi
}

do_deploy() {
    local service=$1
    deploy_guard "$service"
    if do_build "$service"; then
        compose_restart "$service"
        log_info "Deploy succeeded: $service"
    else
        log_error "Build failed: $service"
        rollback_service "$service"
        DEPLOY_FAILURES+=("$service")
        return 1
    fi
}

CMD="${1:-}"
TARGET="${2:-}"

case "$CMD" in
    deploy)
        if [ -z "$TARGET" ]; then
            for svc in "${ALI_SERVICES[@]}"; do do_deploy "$svc" || true; done
            for svc in "${TX_SERVICES[@]}"; do do_deploy "$svc" || true; done
        else
            [ -z "$(get_server "$TARGET")" ] && { echo "Unknown service: $TARGET"; usage; }
            do_deploy "$TARGET"
        fi
        ;;

    build)
        if [ -z "$TARGET" ]; then
            for svc in "${ALI_SERVICES[@]}" "${TX_SERVICES[@]}"; do do_build "$svc"; done
        else
            [ -z "$(get_server "$TARGET")" ] && { echo "Unknown service: $TARGET"; usage; }
            do_build "$TARGET"
        fi
        ;;

    sync)
        [ -z "$TARGET" ] && { echo "Usage: $0 sync <service>"; exit 1; }
        scp_and_build "$TARGET"
        ;;

    restart)
        [ -z "$TARGET" ] && { echo "Usage: $0 restart <service>"; exit 1; }
        compose_restart "$TARGET"
        ;;

    status)
        echo "=== ali ($ALI_HOST) ==="
        ssh "$ALI_HOST" "cd /opt/hamr/ali && docker compose ps 2>&1"
        echo ""
        echo "=== tx ($TX_HOST) ==="
        ssh "$TX_HOST" "cd /opt/hamr/tx && docker compose ps 2>&1"
        ;;

    logs)
        [ -z "$TARGET" ] && { echo "Usage: $0 logs <service>"; exit 1; }
        server="$(get_server "$TARGET")"
        image="$(get_image "$TARGET")"
        compose_dir="$(get_compose_dir "$server")"
        ssh "$server" "cd $compose_dir && docker compose logs -f --tail=100 $image"
        ;;

    rollback)
        [ -z "$TARGET" ] && { echo "Usage: $0 rollback <service>"; exit 1; }
        rollback_service "$TARGET"
        ;;

    *)
        usage
        ;;
esac

echo ""
echo "=== Done ==="
if [ ${#DEPLOY_FAILURES[@]} -gt 0 ]; then
    log_error "Failed services: ${DEPLOY_FAILURES[*]}"
    exit 1
fi
