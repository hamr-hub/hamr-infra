#!/bin/bash

# HamR 基础设施快速检查脚本

echo "=== HamR Infrastructure Health Check ==="
echo ""

# 检查 DNS 解析
echo "[1] DNS Check"
for domain in hamr.store hamr.top app.hamr.store account.hamr.store; do
    echo -n "  $domain: "
    if host $domain > /dev/null 2>&1; then
        echo "✓ OK"
    else
        echo "✗ FAIL"
    fi
done
echo ""

# 检查 HTTP 服务（示例）
echo "[2] HTTP Check (when deployed)"
echo "  (暂未部署，跳过)"
echo ""

echo "=== Check Complete ==="
