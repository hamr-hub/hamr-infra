#!/bin/bash

set -e

SERVER_IP="39.103.188.33"
SERVER_USER="root"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SERVICES=("hamr-website" "hamr-help" "hamr-developer" "hamr-docs")

usage() {
    echo "Usage: $0 [service|all|proxy]"
    echo ""
    echo "  all      - Build and deploy all services"
    echo "  proxy    - Deploy/reload nginx proxy only"
    echo "  website  - Build and deploy hamr-website"
    echo "  help     - Build and deploy hamr-help"
    echo "  developer - Build and deploy hamr-developer"
    echo "  docs     - Build and deploy hamr-docs"
    exit 1
}

build_and_push() {
    local service=$1
    local repo_path="$REPO_ROOT/$service"

    echo ">>> Building $service..."
    docker build -t "$service:latest" "$repo_path"

    echo ">>> Saving and transferring $service image..."
    docker save "$service:latest" | ssh "$SERVER_USER@$SERVER_IP" "docker load"

    echo ">>> Restarting $service on server..."
    ssh "$SERVER_USER@$SERVER_IP" "docker rm -f $service 2>/dev/null || true"
}

deploy_proxy() {
    echo ">>> Deploying nginx proxy config..."
    local proxy_dir="$REPO_ROOT/hamr-infra/services/proxy"

    scp "$proxy_dir/nginx.conf" "$SERVER_USER@$SERVER_IP:/opt/hamr/proxy/nginx.conf"
    scp "$proxy_dir/docker-compose.yml" "$SERVER_USER@$SERVER_IP:/opt/hamr/proxy/docker-compose.yml"

    ssh "$SERVER_USER@$SERVER_IP" "cd /opt/hamr/proxy && docker compose up -d nginx-proxy"
    echo ">>> Proxy deployed."
}

TARGET="${1:-all}"

case "$TARGET" in
    all)
        for svc in "${SERVICES[@]}"; do
            build_and_push "$svc"
        done
        deploy_proxy
        ;;
    proxy)
        deploy_proxy
        ;;
    website|help|developer|docs)
        build_and_push "hamr-$TARGET"
        ssh "$SERVER_USER@$SERVER_IP" "cd /opt/hamr/proxy && docker compose up -d hamr-$TARGET"
        ;;
    *)
        usage
        ;;
esac

echo ""
echo "=== Deploy complete ==="
