# HamR 基础设施运维

> HamR 底层支撑系统 - DNS/CDN/监控/备份/安全

[![Status](https://img.shields.io/badge/status-进行中-green)](https://github.com/hamr-hub/hamr-infra)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## 📋 项目概述

**项目编号**: PROJ-013  
**优先级**: ⭐⭐⭐ 高  
**状态**: 进行中

HamR 基础设施运维项目负责平台底层支撑，包括 DNS 管理、网络安全、证书管理、服务器运维、内部监控、日志管理、数据备份和应急响应。

## 🎯 核心职责

### 1. DNS 管理
- **DNS 服务商**: 阿里云 DNS
- **域名注册**: hamr.store / hamr.top
- **全域名解析配置**:
  ```
  hamr.store               → 43.133.224.11（官网服务器）
  account.hamr.store       → 账号服务器
  app.hamr.store           → 应用服务器
  help.hamr.store          → 帮助中心
  hamr.top                 → 开发者门户
  docs.hamr.top            → 文档站
  api.hamr.top             → API 网关
  deploy.hamr.top          → 部署指南
  demo.hamr.top            → 演示环境
  status.hamr.top          → 状态页面
  jiabu.hamr.store         → JiaBu 决策
  ```
- **DNSSEC**: 防止 DNS 劫持
- **DNS 劫持检测**: 定期检查解析结果
- **DNS 配置工具**: hamr-dns 仓库（阿里云 DNS API）

### 2. 网络安全
- **阿里云 CDN**: 全球加速
- **WAF 防护**: Web 应用防火墙
- **DDoS 防御**: 流量清洗
- **Brotli 压缩**: 带宽优化
- **HTTP/3**: QUIC 协议支持

### 3. 证书管理
- **Let's Encrypt**: 通配符证书自动续期
  - `*.hamr.store`
  - `*.hamr.top`
- **证书过期预警**: 提前 7 天提醒
- **自动续期脚本**: certbot + cron

### 4. 服务器运维
- **操作系统**: Ubuntu 22.04 LTS
- **SSH 密钥认证**: 禁用密码登录
- **fail2ban**: 防暴力破解
- **最小权限原则**: sudo 分级授权
- **自动安全更新**: unattended-upgrades

### 5. 内部监控告警
- **Prometheus**: 指标采集
  - CPU/内存/磁盘/网络
  - HTTP 请求/响应时间/错误率
  - 数据库连接数/查询延迟
  - 缓存命中率
- **Grafana**: 可视化面板
  - 系统资源监控
  - 应用性能监控
  - 数据库性能监控
- **多级别告警**:
  - **P0 (紧急)**: 服务完全中断，立即处理
  - **P1 (高)**: 性能严重下降，1 小时内处理
  - **P2 (中)**: 部分功能异常，4 小时内处理
  - **P3 (低)**: 非关键问题，24 小时内处理
- **通知渠道**: 邮件 + 钉钉/Slack

### 6. 日志管理
- **ELK Stack**: Elasticsearch + Logstash + Kibana
- **日志分层保留**:
  - **热数据** (7 天): 快速查询
  - **温数据** (30 天): 归档存储
  - **冷数据** (90 天): 压缩备份
- **日志分类**:
  - 应用日志 (app.log)
  - 访问日志 (access.log)
  - 错误日志 (error.log)
  - 审计日志 (audit.log)

### 7. 数据安全
- **PostgreSQL 备份**:
  - 每日全量备份 (pg_dump)
  - WAL 持续归档 (PITR)
  - 异地加密备份
  - 每月恢复演练
- **备份目标**:
  - **RTO** (恢复时间目标): < 1 小时
  - **RPO** (恢复点目标): < 24 小时
- **备份存储**:
  - 本地: 保留 7 天
  - 异地: 保留 90 天
  - 冷备: 保留 1 年

### 8. 应急响应
- **7x24 值班制度**: 轮班表
- **应急预案**:
  - 故障处理流程
  - 数据泄露响应
  - DDoS 攻击应对
  - 域名劫持恢复
- **目标可用性**: **99.9%**

## 🏗️ 基础设施架构

```
┌─────────────────────────────────┐
│      Cloudflare CDN + WAF       │
│     (DDoS 防护 + 全球加速)       │
└────────────┬────────────────────┘
             │
    ┌────────┴────────┬────────────┐
    │                 │            │
┌───▼───┐      ┌─────▼─────┐  ┌──▼───┐
│ Nginx │      │  HAProxy  │  │Static│
│Reverse│      │Load Balance│  │Files │
│ Proxy │      └─────┬─────┘  └──────┘
└───┬───┘            │
    │         ┌──────┴──────┬────────┐
    │         │             │        │
┌───▼───┐ ┌──▼───┐  ┌─────▼─────┐ ┌▼────┐
│Account│ │ App  │  │   JiaBu   │ │ API │
│Service│ │Service  │   Service │ │ GW  │
└───┬───┘ └──┬───┘  └─────┬─────┘ └─────┘
    │        │            │
┌───▼────────▼────────────▼───┐
│   PostgreSQL Cluster        │
│   (Primary + Replica)       │
└─────────────────────────────┘
```

## 🛠️ 技术栈

| 技术 | 用途 | 备注 |
|-----|------|------|
| **阿里云 DNS** | DNS 解析管理 | 阿里云服务 |
| **阿里云 CDN** | CDN 加速 | 全球分发 |
| **Nginx** | 反向代理 | SSL 终结 |
| **HAProxy** | 负载均衡 | L4/L7 负载 |
| **Prometheus** | 监控采集 | 时序数据 |
| **Grafana** | 可视化 | 监控面板 |
| **ELK Stack** | 日志管理 | 集中式日志 |
| **PostgreSQL** | 数据库 | 主从复制 |
| **Redis** | 缓存 | 集群模式 |
| **Certbot** | SSL 证书 | Let's Encrypt |

## 🚀 快速开始

### DNS 配置

```bash
# 使用阿里云 DNS API（hamr-dns 仓库）
cd repos/hamr-dns
./configure-dns.sh
```

**脚本说明**（`scripts/dns/`）：

| 文件 | 用途 |
|------|------|
| `dns-records.conf` | DNS 记录声明文件，维护所有域名解析配置 |
| `update-dns.sh` | 读取配置文件，调用阿里云 API 批量更新记录 |

**前置依赖**：
- [阿里云 CLI](https://help.aliyun.com/document_detail/110244.html)
- `jq`（`brew install jq` 或 `apt install jq`）

**环境变量**：
```bash
export ALIBABA_CLOUD_ACCESS_KEY_ID=your_key_id
export ALIBABA_CLOUD_ACCESS_KEY_SECRET=your_key_secret
```

**批量更新所有记录**：
```bash
cd scripts/dns
./update-dns.sh
```

**更新单条记录**：
```bash
./update-dns.sh --domain hamr.store --type A --value 43.133.224.11
```

**验证模式（不实际修改）**：
```bash
./update-dns.sh --dry-run
```

**修改解析 IP**：编辑 `dns-records.conf`，更新对应 IP 后执行 `update-dns.sh`。

### 证书自动续期

```bash
# 安装 certbot
sudo apt install certbot python3-certbot-nginx

# 自动续期
sudo certbot certonly --nginx \
  -d "*.hamr.store" \
  -d "*.hamr.top"

# 添加 cron 任务
0 3 * * * /usr/bin/certbot renew --quiet
```

### 监控部署

```bash
# 部署 Prometheus + Grafana
cd monitoring
docker-compose up -d

# 访问
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000
```

### 备份配置

```bash
# PostgreSQL 全量备份
cd scripts/backup
./pg-backup.sh

# 恢复数据
./pg-restore.sh backup-2026-03-05.sql.gz
```

## 📦 项目结构

```
hamr-infra/
├── dns/                      # DNS 配置
│   ├── cloudflare.tf         # Terraform 配置
│   └── configure-dns.sh      # DNS 配置脚本
├── ssl/                      # SSL 证书
│   ├── certbot-renew.sh      # 续期脚本
│   └── certs/                # 证书存储
├── monitoring/               # 监控系统
│   ├── prometheus/
│   │   └── prometheus.yml
│   ├── grafana/
│   │   └── dashboards/
│   └── docker-compose.yml
├── logging/                  # 日志系统
│   ├── logstash/
│   ├── elasticsearch/
│   └── kibana/
├── backup/                   # 备份脚本
│   ├── pg-backup.sh          # PostgreSQL 备份
│   ├── pg-restore.sh         # 数据恢复
│   ├── redis-backup.sh       # Redis 备份
│   └── file-backup.sh        # 文件备份
├── scripts/                  # 运维脚本
│   ├── deploy.sh             # 部署脚本
│   ├── healthcheck.sh        # 健康检查
│   ├── upgrade.sh            # 升级脚本
│   └── rollback.sh           # 回滚脚本
├── ansible/                  # 自动化运维
│   ├── playbooks/
│   └── inventory/
└── README.md
```

## 📊 监控指标

### 系统指标
- CPU 使用率
- 内存使用率
- 磁盘 I/O
- 网络流量

### 应用指标
- HTTP 请求数/秒
- 响应时间 (P50/P90/P99)
- 错误率 (4xx/5xx)
- 并发连接数

### 数据库指标
- 连接数
- 查询延迟
- 慢查询数量
- 复制延迟

## 🚨 告警规则

```yaml
# Prometheus 告警规则
groups:
  - name: system
    rules:
      - alert: HighCPU
        expr: cpu_usage > 80
        for: 5m
        labels:
          severity: P1
        annotations:
          summary: "CPU 使用率超过 80%"
      
      - alert: HighMemory
        expr: memory_usage > 90
        for: 5m
        labels:
          severity: P1
        annotations:
          summary: "内存使用率超过 90%"
      
      - alert: DiskFull
        expr: disk_usage > 85
        for: 10m
        labels:
          severity: P0
        annotations:
          summary: "磁盘使用率超过 85%"
```

## 📊 里程碑

- [x] **2026-03-05**: 项目初始化
- [ ] **2026-03-15**: DNS 配置完成
- [ ] **2026-03-30**: 监控体系搭建
- [ ] **2026-04-10**: 备份机制建立
- [ ] **2026-04-20**: 应急预案制定
- [ ] **2026-06-30**: Phase 1 运维就绪

## 🔗 相关链接

- [服务状态](https://status.hamr.top) - 面向用户的状态页面
- [部署指南](https://deploy.hamr.top) - 私有部署文档

## 📄 许可证

MIT License

---

**最后更新**: 2026-03-06  
**项目状态**: 进行中  
**目标可用性**: 99.9%
