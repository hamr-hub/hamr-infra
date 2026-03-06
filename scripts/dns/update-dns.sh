#!/bin/bash

# HamR 阿里云 DNS 记录更新脚本
# 用途: 批量读取 dns-records.conf，通过阿里云 DNS API 更新解析记录
#
# 依赖:
#   - aliyun CLI: https://help.aliyun.com/document_detail/110244.html
#   - jq: apt install jq / brew install jq
#
# 使用方法:
#   export ALIBABA_CLOUD_ACCESS_KEY_ID=your_key_id
#   export ALIBABA_CLOUD_ACCESS_KEY_SECRET=your_key_secret
#   ./update-dns.sh
#
# 单条更新:
#   ./update-dns.sh --domain hamr.store --type A --value 43.133.224.11
#
# 验证模式 (不实际更新):
#   ./update-dns.sh --dry-run

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$SCRIPT_DIR/dns-records.conf"
DRY_RUN=false
SINGLE_DOMAIN=""
SINGLE_TYPE=""
SINGLE_VALUE=""

# ============================================================
# 参数解析
# ============================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --domain)
            SINGLE_DOMAIN="$2"
            shift 2
            ;;
        --type)
            SINGLE_TYPE="$2"
            shift 2
            ;;
        --value)
            SINGLE_VALUE="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# ============================================================
# 前置检查
# ============================================================
check_dependencies() {
    if ! command -v aliyun &> /dev/null; then
        echo "[ERROR] 未找到 aliyun CLI，请先安装："
        echo "  https://help.aliyun.com/document_detail/110244.html"
        exit 1
    fi
    if ! command -v jq &> /dev/null; then
        echo "[ERROR] 未找到 jq，请先安装："
        echo "  brew install jq  或  apt install jq"
        exit 1
    fi
    if [[ -z "$ALIBABA_CLOUD_ACCESS_KEY_ID" || -z "$ALIBABA_CLOUD_ACCESS_KEY_SECRET" ]]; then
        echo "[ERROR] 请先设置阿里云访问密钥："
        echo "  export ALIBABA_CLOUD_ACCESS_KEY_ID=your_key_id"
        echo "  export ALIBABA_CLOUD_ACCESS_KEY_SECRET=your_key_secret"
        exit 1
    fi
}

# ============================================================
# 从完整域名拆分主域名和子域名 RR
# 例: app.hamr.store → domain=hamr.store, rr=app
#     hamr.store     → domain=hamr.store, rr=@
# ============================================================
split_domain() {
    local full_domain="$1"
    local known_roots=("hamr.store" "hamr.top")

    for root in "${known_roots[@]}"; do
        if [[ "$full_domain" == "$root" ]]; then
            echo "$root @"
            return
        fi
        if [[ "$full_domain" == *".$root" ]]; then
            local rr="${full_domain%.$root}"
            echo "$root $rr"
            return
        fi
    done

    echo "[ERROR] 无法识别的域名: $full_domain" >&2
    exit 1
}

# ============================================================
# 查询已有记录 ID
# ============================================================
get_record_id() {
    local domain="$1"
    local rr="$2"
    local type="$3"

    local result
    result=$(aliyun alidns DescribeDomainRecords \
        --DomainName "$domain" \
        --RRKeyWord "$rr" \
        --TypeKeyWord "$type" \
        --output json 2>/dev/null)

    echo "$result" | jq -r '.DomainRecords.Record[0].RecordId // empty'
}

# ============================================================
# 更新或新增单条 DNS 记录
# ============================================================
upsert_record() {
    local full_domain="$1"
    local type="$2"
    local value="$3"
    local ttl="$4"

    read -r domain rr <<< "$(split_domain "$full_domain")"

    echo -n "  [$type] $full_domain → $value (TTL: ${ttl}s) ... "

    if $DRY_RUN; then
        echo "[DRY-RUN 跳过]"
        return
    fi

    local record_id
    record_id=$(get_record_id "$domain" "$rr" "$type")

    if [[ -n "$record_id" ]]; then
        aliyun alidns UpdateDomainRecord \
            --RecordId "$record_id" \
            --RR "$rr" \
            --Type "$type" \
            --Value "$value" \
            --TTL "$ttl" \
            --output json > /dev/null
        echo "已更新 (ID: $record_id)"
    else
        aliyun alidns AddDomainRecord \
            --DomainName "$domain" \
            --RR "$rr" \
            --Type "$type" \
            --Value "$value" \
            --TTL "$ttl" \
            --output json > /dev/null
        echo "已新增"
    fi
}

# ============================================================
# 主逻辑
# ============================================================
check_dependencies

echo "=== HamR DNS 记录更新 ==="
$DRY_RUN && echo "[验证模式] 不会实际修改 DNS"
echo ""

if [[ -n "$SINGLE_DOMAIN" ]]; then
    if [[ -z "$SINGLE_TYPE" || -z "$SINGLE_VALUE" ]]; then
        echo "[ERROR] 单条更新需同时指定 --type 和 --value"
        exit 1
    fi
    upsert_record "$SINGLE_DOMAIN" "$SINGLE_TYPE" "$SINGLE_VALUE" 600
else
    if [[ ! -f "$CONF_FILE" ]]; then
        echo "[ERROR] 配置文件不存在: $CONF_FILE"
        exit 1
    fi

    SUCCESS=0
    FAIL=0

    while IFS='|' read -r full_domain type value ttl; do
        [[ "$full_domain" =~ ^#.*$ || -z "$full_domain" ]] && continue
        full_domain="$(echo "$full_domain" | xargs)"
        type="$(echo "$type" | xargs)"
        value="$(echo "$value" | xargs)"
        ttl="$(echo "$ttl" | xargs)"

        if upsert_record "$full_domain" "$type" "$value" "$ttl"; then
            ((SUCCESS++))
        else
            ((FAIL++))
        fi
    done < "$CONF_FILE"

    echo ""
    echo "=== 完成: 成功 $SUCCESS 条，失败 $FAIL 条 ==="
fi
