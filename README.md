# Docker Swarm NFS 存储架构

一个完整的Docker Swarm分布式NFS存储解决方案，支持跨节点访问、自动备份和数据恢复。

## 🏗️ 架构概览

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Docker Node   │    │   Docker Node   │    │   Docker Node   │
│     (vir02)     │    │     (ora01)     │    │     (ora02)     │
│                 │    │                 │    │                 │
│  ┌───────────┐  │    │  ┌───────────┐  │    │  ┌───────────┐  │
│  │    App    │  │    │  │    App    │  │    │  │    App    │  │
│  │ Services  │  │    │  │ Services  │  │    │  │ Services  │  │
│  └─────┬─────┘  │    │  └─────┬─────┘  │    │  └─────┬─────┘  │
│        │        │    │        │        │    │        │        │
│        │ NFS    │    │        │ NFS    │    │        │ NFS    │
│        │        │    │        │        │    │        │        │
│  ┌─────▼────┐   │    │        │        │    │        │        │
│  │NFS Server │  │    │        │        │    │        │        │
│  │  Service  │  │    │        │        │    │        │        │
│  └───────────┘  │    │        │        │    │        │        │
│        │        │    │        │        │    │        │        │
│  ┌─────▼────┐   │    │        │        │    │        │        │
│  │  Backup   │  │    │        │        │    │        │        │
│  │ Manager   │  │    │        │        │    │        │        │
│  └───────────┘  │    │        │        │    │        │        │
└─────────┬───────┘    └────────┼────────┘    └────────┼────────┘
          │                     │                      │
          └─────────────────────┼──────────────────────┘
                                │
                    ┌───────────▼──────────┐
                    │     WebDAV Backup     │
                    └───────────────────────┘
```

## 📁 项目结构

```
dockerSwarm_syncNFSvolumes/
├── scripts/
│   ├── backup-manager.sh           # 备份管理工具
│   └── lib                         # 库文件
├── 
└── README.md                       # 本文档
```

## 🚀 快速开始

## 🛠️ 备份管理

```bash
### 使用备份管理工具

=== NFS Backup Manager ===

这个脚本运行在备份管理容器内，支持两种模式:

自动模式 (Auto Mode):
  - 运行自动备份周期 (默认每6小时，可通过BACKUP_CYCLE_HOURS配置)
  - 启动时执行快照完整性检查
  - 只检查每个卷的最新快照 (除非损坏)
  - 自动清理损坏的快照
  - 使用方法: BACKUP_MODE=auto ./backup-manager.sh

手动模式 (Manual Mode):
  - 交互式菜单进行手动操作
  - 手动备份、恢复、清空操作
  - 进度显示和时间估算
  - 多重安全确认机制
  - 启动超时自动切换到自动模式 (默认30秒，可通过MANUAL_MODE_TIMEOUT配置)
  - 使用方法: BACKUP_MODE=manual ./backup-manager.sh

使用示例:
  BACKUP_MODE=auto ./backup-manager.sh                    # 启动自动模式
  BACKUP_MODE=manual ./backup-manager.sh                  # 启动交互模式
  BACKUP_CYCLE_HOURS=1 BACKUP_MODE=auto ./backup-manager.sh    # 1小时备份周期
  MANUAL_MODE_TIMEOUT=60 BACKUP_MODE=manual ./backup-manager.sh # 60秒超时

环境变量:
  VOLUMES_DIR           - NFS卷目录 (默认: /nfs_volumes)
  KOPIA_CONFIG_PATH     - Kopia配置文件路径
  KOPIA_CACHE_DIRECTORY - Kopia缓存目录
  BACKUP_CYCLE_HOURS    - 自动备份周期小时数 (默认: 6)
  MANUAL_MODE_TIMEOUT   - 手动模式超时秒数 (默认: 30)

WebDAV仓库配置 (可选):
  WEBDAV_URL            - WebDAV服务器URL
  WEBDAV_VOL_PATH       - WebDAV卷路径
  KOPIA_REPOSITORY_NAME - 仓库名称 (默认: kopia-repo)
  KOPIA_REPOSITORY_USER - WebDAV用户名
  KOPIA_REPOSITORY_PASS - WebDAV密码
  KOPIA_PASSWORD        - 仓库加密密码

自动仓库管理:
  • 如果配置了WebDAV环境变量，脚本会自动:
    - 动态识别WebDAV重定向URL
    - 创建必要的WebDAV目录
    - 连接现有仓库或创建新仓库
    - 在连接丢失时自动重连
  • 如果未配置，需要手动设置Kopia仓库

注意: 此脚本应在备份管理容器内运行。
```

### 备份功能特性

- ✅ **自动备份**: 每6小时自动备份所有卷
- ✅ **增量备份**: 使用Kopia实现高效增量备份
- ✅ **WebDAV存储**: 备份到远程WebDAV服务器
- ✅ **版本管理**: 保留多个备份版本
- ✅ **手动操作**: 支持手动备份和还原
- ✅ **安全确认**: 危险操作需要多重确认

## 📊 NFS卷说明

| 卷名 | 用途 | 权限 | 说明 |
|------|------|------|------|
| `shared_data` | 共享数据 | 读写 | 所有应用共享的数据 |
| `app_data` | Web应用数据 | 读写 | Web应用专用数据 |
| `app_api` | API应用数据 | 读写 | API应用专用数据 |
| `app_db` | 数据库数据 | 读写 | 数据库应用专用数据 |
| `app_configs` | 应用配置 | 只读 | 应用配置文件 |


### 备份配置
- **备份间隔**: 6小时
- **备份工具**: Kopia
- **存储后端**: WebDAV
- **加密**: AES-256加密
- **保留策略**: 自动清理旧备份


# 检查备份仓库状态
```bash
docker exec $(docker ps --filter "label=com.docker.swarm.service.name=storage_backup_manager" --format "{{.ID}}" | head -1) \
  sh -c 'export KOPIA_CONFIG_PATH=/app/config/kopia.config && /bin/kopia repository status'
```

## 📝 注意事项

 **数据安全**: 在执行flush或restore操作前，请确保了解操作后果

## 🤝 贡献

欢迎提交Issue和Pull Request来改进这个项目。

## 📄 许可证

本项目采用MIT许可证。
