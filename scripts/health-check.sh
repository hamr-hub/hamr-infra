#!/bin/bash

SERVER_IP="39.103.188.33"

echo "=== HamR Infrastructure Health Check ==="
echo ""

echo "[1] DNS Check"
for domain in hamr.store www.hamr.store help.hamr.store app.hamr.store account.hamr.store hamr.top www.hamr.top docs.hamr.top api.hamr.top status.hamr.top deploy.hamr.top demo.hamr.top; do
    echo -n "  $domain: "
    resolved=$(dig +short "$domain" 2>/dev/null | head -1)
    if [ "$resolved" = "$SERVER_IP" ]; then
        echo "✓ -> $resolved"
    elif [ -n "$resolved" ]; then
        echo "⚠ -> $resolved (expected $SERVER_IP)"
    else
        echo "✗ not resolved"
    fi
done
echo ""

echo "[2] HTTP Check"
declare -A HTTP_TARGETS=(
    ["hamr.store"]="HamR"
    ["hamr.top"]="HamR"
    ["help.hamr.store"]=""
    ["docs.hamr.top"]=""
    ["status.hamr.top"]=""
)

for domain in "${!HTTP_TARGETS[@]}"; do
    echo -n "  http://$domain: "
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$domain" 2>/dev/null)
    if [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]; then
        echo "✓ HTTP $status"
    else
        echo "✗ HTTP $status"
    fi
done
echo ""

echo "[3] Docker Services (via SSH)"
if ssh -o ConnectTimeout=5 -o BatchMode=yes "root@$SERVER_IP" "docker ps --format '  {{.Names}}: {{.Status}}'" 2>/dev/null; then
    echo ""
else
    echo "  (SSH not available or no Docker containers running)"
    echo ""
fi

echo "=== Check Complete ==="
