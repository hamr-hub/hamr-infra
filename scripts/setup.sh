#!/bin/bash
# HamR 服务器初始化脚本
# 在阿里云服务器（43.133.224.11）首次执行
# 用法: bash setup.sh

set -e

HAMR_DIR="/opt/hamr"
ALI_DIR="$HAMR_DIR/ali"
BUILDS_DIR="$HAMR_DIR/builds"
MONITORING_DIR="$HAMR_DIR/monitoring"

echo "=========================================="
echo " HamR 服务器初始化"
echo "=========================================="

# 1. 安装依赖
echo ""
echo "[1/6] 安装系统依赖..."
apt-get update -qq
apt-get install -y -qq curl git ufw fail2ban

# 2. 安装 Docker
if ! command -v docker &>/dev/null; then
    echo "[2/6] 安装 Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
else
    echo "[2/6] Docker 已安装，跳过"
fi

# 3. 创建目录结构
echo ""
echo "[3/6] 创建目录结构..."
mkdir -p "$ALI_DIR"
mkdir -p "$BUILDS_DIR"
mkdir -p "$MONITORING_DIR/grafana/provisioning/dashboards"
mkdir -p "$MONITORING_DIR/grafana/provisioning/datasources"

# 4. 创建 Docker 网络
echo ""
echo "[4/6] 创建 Docker 网络..."
docker network create hamr-net 2>/dev/null || echo "网络已存在，跳过"

# 5. 配置防火墙
echo ""
echo "[5/6] 配置防火墙..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS
echo "防火墙规则已设置"

# 6. 检查环境文件
echo ""
echo "[6/6] 检查配置..."
if [ ! -f "$ALI_DIR/.env" ]; then
    echo "警告: $ALI_DIR/.env 不存在！"
    echo "请创建 $ALI_DIR/.env 并填写以下变量："
    cat <<'EOF'
POSTGRES_USER=hamr
POSTGRES_PASSWORD=<强密码>
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<强密码>
JWT_SECRET=<至少32位随机字符串>
RATE_LIMIT_PER_MINUTE=60
EOF
else
    echo "配置文件已存在 ✓"
fi

echo ""
echo "=========================================="
echo " 初始化完成！"
echo ""
echo " 下一步："
echo " 1. 确保 $ALI_DIR/.env 已配置"
echo " 2. 将 services/ali/docker-compose.yml 上传到 $ALI_DIR/"
echo " 3. 将 monitoring/ 配置上传到 $MONITORING_DIR/"
echo " 4. 执行: cd $ALI_DIR && docker compose up -d"
echo "=========================================="
