# HamR 基础设施运维

HamR 平台基础设施管理 - DNS、CDN、监控、备份。

**项目编号**: PROJ-013  
**技术栈**: Shell / Python / Terraform / Ansible

## 项目结构

```
hamr-infra/
├── scripts/        # 运维脚本
│   ├── backup/    # 备份脚本
│   ├── deploy/    # 部署脚本
│   └── monitor/   # 监控脚本
├── terraform/      # IaC 基础设施代码
├── ansible/        # 配置管理
└── docs/           # 运维文档
```

## 功能

- DNS 配置管理
- CDN 配置
- SSL 证书自动续期
- 监控告警（Prometheus + Grafana）
- 数据备份与恢复
- 安全防护

## 相关文档

- [项目文档](../../projects/active/基础设施运维-20260305.md)
