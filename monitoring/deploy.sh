#!/usr/bin/env bash
set -euo pipefail

REMOTE_DIR="/opt/monitoring"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SSH="ssh -p 2222 root@39.103.188.33"
SCP="scp -P 2222"

$SSH "mkdir -p ${REMOTE_DIR}/grafana/provisioning/datasources ${REMOTE_DIR}/grafana/provisioning/dashboards"

$SCP "${SCRIPT_DIR}/docker-compose.yml"   root@39.103.188.33:"${REMOTE_DIR}/docker-compose.yml"
$SCP "${SCRIPT_DIR}/prometheus.yml"       root@39.103.188.33:"${REMOTE_DIR}/prometheus.yml"
$SCP "${SCRIPT_DIR}/alerts.yml"           root@39.103.188.33:"${REMOTE_DIR}/alerts.yml"
$SCP "${SCRIPT_DIR}/grafana/provisioning/datasources/prometheus.yml" \
      root@39.103.188.33:"${REMOTE_DIR}/grafana/provisioning/datasources/prometheus.yml"
$SCP "${SCRIPT_DIR}/grafana/provisioning/dashboards/provider.yml" \
      root@39.103.188.33:"${REMOTE_DIR}/grafana/provisioning/dashboards/provider.yml"

if ! $SSH "test -f ${REMOTE_DIR}/.env"; then
  $SCP "${SCRIPT_DIR}/.env.example" root@39.103.188.33:"${REMOTE_DIR}/.env"
  echo "请先在服务器上编辑 ${REMOTE_DIR}/.env 设置 Grafana 密码，然后重新运行本脚本。"
  exit 0
fi

$SSH "cd ${REMOTE_DIR} && docker compose pull && docker compose up -d"
echo "监控体系已启动，Grafana 访问地址：http://39.103.188.33:3000"
