#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "  HamR 一键部署 - Phase 1 全部服务"
echo "========================================="
echo ""

check_env() {
    local envfile="$1"
    if [ ! -f "$envfile" ]; then
        echo -e "${RED}错误: 缺少环境变量文件 $envfile${NC}"
        echo "请创建该文件并填写以下必填变量:"
        echo "  POSTGRES_PASSWORD=<数据库密码>"
        echo "  JWT_SECRET=<JWT密钥>"
        exit 1
    fi

    source "$envfile"
    for var in POSTGRES_PASSWORD JWT_SECRET; do
        if [ -z "${!var}" ]; then
            echo -e "${RED}错误: $envfile 中缺少 $var${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}✓${NC} 环境变量检查通过"
}

echo "[Step 1/6] 检查环境变量 ..."
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/../services/proxy/.env}"
if [ -f "$ENV_FILE" ]; then
    check_env "$ENV_FILE"
else
    echo -e "${YELLOW}⚠ 未找到 $ENV_FILE，跳过环境变量检查${NC}"
    echo "  在服务器上部署时请确保 /opt/hamr/ali/.env 已配置"
fi
echo ""

echo "[Step 2/6] 构建基础设施镜像 ..."
echo -e "${GREEN}>>>${NC} 部署顺序: 数据库 → 后端服务 → 前端 → 网关 → 监控"
echo ""

echo "[Step 3/6] 部署阿里云服务器 (hamr.store 核心服务) ..."
echo "  按依赖顺序部署:"
echo "  1. 静态前端: website, help"
echo "  2. 数据库启动 (通过 docker compose)"
echo "  3. 后端 API: account-api, app-api, jiabu-api"
echo "  4. 前端应用: account, app, jiabu"
echo "  5. API 网关: api-gateway"
echo "  6. 监控: status"
echo "  7. 演示: demo, demo-api"
echo "  8. 部署指南: deploy"

DEPLOY_ORDER="website help account-api app-api jiabu-api account app jiabu api-gateway status demo demo-api deploy"
for svc in $DEPLOY_ORDER; do
    echo ""
    echo -e "${GREEN}>>> 部署 $svc ...${NC}"
    "$SCRIPT_DIR/deploy.sh" deploy "$svc" || {
        echo -e "${RED}>>> $svc 部署失败，继续其他服务 ...${NC}"
    }
done
echo ""

echo "[Step 4/6] 部署腾讯云服务器 (hamr.top 开发者生态) ..."
for svc in developer docs; do
    echo ""
    echo -e "${GREEN}>>> 部署 $svc ...${NC}"
    "$SCRIPT_DIR/deploy.sh" deploy "$svc" || {
        echo -e "${RED}>>> $svc 部署失败，继续其他服务 ...${NC}"
    }
done
echo ""

echo "[Step 5/6] 同步 Nginx 配置 ..."
"$SCRIPT_DIR/deploy.sh" restart website 2>/dev/null || true
echo ""

echo "[Step 6/6] 健康检查 ..."
echo ""
"$SCRIPT_DIR/health-check.sh" || true

echo ""
echo "========================================="
echo "  部署完成！"
echo "========================================="
echo ""
echo "已部署的站点:"
echo "  hamr.store         - 官网"
echo "  help.hamr.store    - 帮助中心"
echo "  account.hamr.store - 账号中心"
echo "  app.hamr.store     - 管家应用"
echo "  jiabu.hamr.store   - JiaBu 决策"
echo "  hamr.top           - 开发者门户"
echo "  docs.hamr.top      - 技术文档"
echo "  api.hamr.top       - API 网关"
echo "  status.hamr.top    - 服务监控"
echo "  deploy.hamr.top    - 部署指南"
echo "  demo.hamr.top      - 在线演示"
echo ""
echo "运维命令:"
echo "  $SCRIPT_DIR/deploy.sh status   - 查看容器状态"
echo "  $SCRIPT_DIR/deploy.sh logs <svc> - 查看日志"
echo "  $SCRIPT_DIR/deploy.sh rollback <svc> - 回滚服务"
echo "  $SCRIPT_DIR/health-check.sh    - 健康检查"
