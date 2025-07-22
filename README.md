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
│  ┌─────▼────┐  │    │        │        │    │        │        │
│  │NFS Server │  │    │        │        │    │        │        │
│  │  Service  │  │    │        │        │    │        │        │
│  └───────────┘  │    │        │        │    │        │        │
│        │        │    │        │        │    │        │        │
│  ┌─────▼────┐  │    │        │        │    │        │        │
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

### 使用备份管理工具

```bash
# 给脚本执行权限
chmod +x backup-manager.sh

# 查看帮助
./backup-manager.sh help

# 列出所有卷和快照
./backup-manager.sh list

# 手动触发备份
./backup-manager.sh backup

# 从备份还原 (谨慎操作)
./backup-manager.sh restore

# 清空卷数据 (危险操作)
./backup-manager.sh flush
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
docker exec $(docker ps --filter "label=com.docker.swarm.service.name=storage_backup_manager" --format "{{.ID}}" | head -1) \
  sh -c 'export KOPIA_CONFIG_PATH=/app/config/kopia.config && /bin/kopia repository status'

# 手动测试备份
./backup-manager.sh backup
```

## 📝 注意事项

 **数据安全**: 在执行flush或restore操作前，请确保了解操作后果

## 🤝 贡献

欢迎提交Issue和Pull Request来改进这个项目。

## 📄 许可证

本项目采用MIT许可证。
