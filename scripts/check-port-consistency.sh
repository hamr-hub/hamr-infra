#!/usr/bin/env bash
#
# 端口一致性检查 —— 保证各部署拓扑的端口不会再次漂移。
#
# 背景（proposed-fixes-v2 #08，P0）：
#   同一个服务在不同 compose 里被写成不同的端口（hamr-jiabu-api 在 ali 栈是
#   3003、在 proxy 栈是 8082），nginx 反代写的是 8082 —— 结果线上
#   jiabu.hamr.store 的 /api/ 是 502。
#
# 本脚本校验四处是否一致：
#   1. services/ports.env            —— 唯一真源
#   2. services/*/docker-compose.yml  —— 变量默认值的 fallback
#   3. services/proxy/nginx.conf      —— 反代 upstream 的字面量
#   4. 各后端仓库的 .env.example      —— 服务自身声明的 PORT
#
# 任何一处对不上就以非零码退出，可直接挂到 CI。
#
# 用法: ./scripts/check-port-consistency.sh
#
# 兼容 bash 3.2（macOS 自带版本），不使用关联数组。
set -uo pipefail

cd "$(dirname "$0")/.."

PORTS_FILE="services/ports.env"
FAILURES=0
CHECKED=0

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }

fail() {
    red   "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

if [[ ! -f "$PORTS_FILE" ]]; then
    red "FAIL: 找不到端口契约文件 $PORTS_FILE"
    exit 1
fi

# ── 读取唯一真源 ────────────────────────────────────────
canonical() {
    # canonical HAMR_JIABU_API_PORT → 8082
    grep -E "^$1=" "$PORTS_FILE" | head -1 | cut -d= -f2- | tr -d '[:space:]'
}

# 服务名 → 真源里的变量名
port_var_for_service() {
    case "$1" in
        hamr-account-api)  echo "HAMR_ACCOUNT_API_PORT" ;;
        hamr-app-api)      echo "HAMR_APP_API_PORT" ;;
        hamr-jiabu-api)    echo "HAMR_JIABU_API_PORT" ;;
        hamr-demo-api)     echo "HAMR_DEMO_API_PORT" ;;
        hamr-api-gateway)  echo "HAMR_API_GATEWAY_PORT" ;;
        grafana)           echo "HAMR_GRAFANA_PORT" ;;
        *)                 echo "" ;;
    esac
}

ALL_SERVICES="hamr-account-api hamr-app-api hamr-jiabu-api hamr-demo-api hamr-api-gateway grafana"

echo "端口契约检查 · 真源: $PORTS_FILE"
echo "--------------------------------------------------"

# ── 1. 真源自身必须完整 ─────────────────────────────────
for var in HAMR_ACCOUNT_API_PORT HAMR_APP_API_PORT HAMR_JIABU_API_PORT \
           HAMR_DEMO_API_PORT HAMR_API_GATEWAY_PORT HAMR_GRAFANA_PORT; do
    val="$(canonical "$var")"
    if [[ -z "$val" ]]; then
        fail "$PORTS_FILE 缺少 $var"
    else
        CHECKED=$((CHECKED + 1))
    fi
done

# ── 2. compose 里的 ${VAR:-default} 默认值必须等于真源 ──
check_compose_defaults() {
    file="$1"
    [[ -f "$file" ]] || return 0
    while IFS= read -r line; do
        var="$(printf '%s' "$line" | sed -n 's/.*\${\(HAMR_[A-Z_]*\):-\([0-9]\+\)}.*/\1/p')"
        default="$(printf '%s' "$line" | sed -n 's/.*\${\(HAMR_[A-Z_]*\):-\([0-9]\+\)}.*/\2/p')"
        [[ -z "$var" ]] && continue
        want="$(canonical "$var")"
        [[ -z "$want" ]] && continue
        CHECKED=$((CHECKED + 1))
        if [[ "$default" != "$want" ]]; then
            fail "$file: $var 的默认值 $default 与真源 $want 不一致"
        fi
    done < "$file"
}

for f in services/*/docker-compose.yml monitoring/docker-compose.yml; do
    check_compose_defaults "$f"
done

# ── 3. nginx upstream 的字面量必须等于真源 ──────────────
NGINX="services/proxy/nginx.conf"
if [[ -f "$NGINX" ]]; then
    for svc in $ALL_SERVICES; do
        ports="$(grep -oE "${svc}:[0-9]+" "$NGINX" | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')"
        ports="${ports% }"
        [[ -z "$ports" ]] && continue
        var="$(port_var_for_service "$svc")"
        want="$(canonical "$var")"
        [[ -z "$want" ]] && continue
        CHECKED=$((CHECKED + 1))
        if [[ "$ports" != "$want" ]]; then
            fail "$NGINX: ${svc} 反代端口为 '$ports'，真源为 $want"
        fi
    done
fi

# ── 4. 后端仓库 .env.example 声明的 PORT 必须等于真源 ──
check_backend_env() {
    file="$1"
    svc="$2"
    [[ -f "$file" ]] || return 0
    port="$(grep -E '^PORT=' "$file" | head -1 | cut -d= -f2- | tr -d '[:space:]')"
    [[ -z "$port" ]] && return 0
    var="$(port_var_for_service "$svc")"
    want="$(canonical "$var")"
    [[ -z "$want" ]] && return 0
    CHECKED=$((CHECKED + 1))
    if [[ "$port" != "$want" ]]; then
        fail "$file: PORT=$port 与真源 $want 不一致"
    fi
}

# 各后端仓库所在目录。默认是 hamr-infra 的同级目录；在 CI 里可用
# HAMR_REPOS_ROOT 指向专门拉取子仓库的目录。
REPO_ROOT="${HAMR_REPOS_ROOT:-$(cd .. && pwd)}"
check_backend_env "$REPO_ROOT/hamr-account/backend/.env.example"   "hamr-account-api"
check_backend_env "$REPO_ROOT/hamr-app/backend/.env.example"       "hamr-app-api"
check_backend_env "$REPO_ROOT/hamr-demo/backend/.env.example"      "hamr-demo-api"
check_backend_env "$REPO_ROOT/hamr-jiabu/backend/.env.example"     "hamr-jiabu-api"
check_backend_env "$REPO_ROOT/hamr-api/.env.example"              "hamr-api-gateway"

# ── 5. 弱口令兜底值不得再出现 ──────────────────────────
CHECKED=$((CHECKED + 1))
if grep -rqE 'ADMIN_PASSWORD[^}]*:-admin' services/ monitoring/ 2>/dev/null; then
    fail "Grafana 管理密码仍存在 ':-admin' 弱口令兜底"
fi

echo "--------------------------------------------------"
if [[ "$FAILURES" -gt 0 ]]; then
    red "共 $FAILURES 处不一致（检查了 $CHECKED 项）"
    exit 1
fi

green "端口契约一致 ✓（检查了 $CHECKED 项）"
exit 0
