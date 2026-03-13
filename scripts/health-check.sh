#!/bin/bash

SERVER_IP="43.133.224.11"
SSH_USER="root"
SSH_OPTS="-o ConnectTimeout=5 -o BatchMode=yes"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }

ERRORS=0

echo "=== HamR Infrastructure Health Check ==="
echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

echo "[1] DNS Check"
HAMR_STORE_DOMAINS="hamr.store www.hamr.store help.hamr.store app.hamr.store account.hamr.store jiabu.hamr.store"
HAMR_TOP_DOMAINS="hamr.top www.hamr.top docs.hamr.top api.hamr.top status.hamr.top deploy.hamr.top demo.hamr.top"

for domain in $HAMR_STORE_DOMAINS $HAMR_TOP_DOMAINS; do
    resolved=$(dig +short "$domain" 2>/dev/null | head -1)
    if [ -n "$resolved" ]; then
        ok "$domain -> $resolved"
    else
        fail "$domain not resolved"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

echo "[2] HTTP Check"
ENDPOINTS="hamr.store hamr.top help.hamr.store docs.hamr.top account.hamr.store app.hamr.store api.hamr.top/health status.hamr.top deploy.hamr.top demo.hamr.top"

for endpoint in $ENDPOINTS; do
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$endpoint" 2>/dev/null)
    if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
        ok "http://$endpoint -> HTTP $status"
    elif [ "$status" = "503" ]; then
        warn "http://$endpoint -> HTTP $status (service unavailable)"
    else
        fail "http://$endpoint -> HTTP $status"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

echo "[3] Docker Services (via SSH)"
if ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" "docker ps --format '  {{.Names}}: {{.Status}}'" 2>/dev/null; then
    echo ""
else
    warn "SSH not available or no Docker containers running"
    echo ""
fi

echo "[4] Database Check (via SSH)"
if ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" "
    for db in hamr_account hamr_app hamr_jiabu; do
        if docker exec hamr-postgres-account pg_isready -U hamr -d \$db -q 2>/dev/null || \
           docker exec hamr-postgres-app pg_isready -U hamr -d \$db -q 2>/dev/null || \
           docker exec hamr-postgres-jiabu pg_isready -U hamr -d \$db -q 2>/dev/null; then
            echo \"  ✓ \$db: ready\"
        else
            echo \"  ✗ \$db: not ready\"
        fi
    done
" 2>/dev/null; then
    echo ""
else
    warn "Database check skipped (SSH not available)"
    echo ""
fi

echo "[5] API Health Endpoints"
API_ENDPOINTS="account.hamr.store/api/health app.hamr.store/api/health api.hamr.top/health"

for ep in $API_ENDPOINTS; do
    body=$(curl -s --connect-timeout 5 "http://$ep" 2>/dev/null)
    status=$(echo "$body" | grep -o '"status"[[:space:]]*:[[:space:]]*"ok"' 2>/dev/null)
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$ep" 2>/dev/null)
    if [ -n "$status" ] || [ "$http_code" = "200" ]; then
        ok "http://$ep -> healthy"
    else
        fail "http://$ep -> HTTP $http_code"
        ERRORS=$((ERRORS + 1))
    fi
done
echo ""

echo "[6] Disk & Memory (via SSH)"
if ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" "
    echo '  Disk Usage:'
    df -h / | tail -1 | awk '{print \"    / : \" \$5 \" used (\" \$3 \" / \" \$2 \")\"}'
    echo '  Memory:'
    free -h | grep Mem | awk '{print \"    RAM: \" \$3 \" used / \" \$2 \" total\"}'
    echo '  Docker Volumes:'
    docker system df --format '    Images: {{.Size}} | Containers: {{.Size}} | Volumes: {{.Size}}' 2>/dev/null || echo '    (docker df unavailable)'
" 2>/dev/null; then
    echo ""
else
    warn "System resource check skipped (SSH not available)"
    echo ""
fi

echo "=== Check Complete ==="
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
else
    echo -e "${RED}$ERRORS check(s) failed!${NC}"
    exit 1
fi
