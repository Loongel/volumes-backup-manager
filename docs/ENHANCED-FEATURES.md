# Backup Manager 增强功能说明

## 概述

基于Docker Compose脚本的经验，对backup-manager脚本进行了增强，主要借鉴了以下功能：

1. **动态配置文件生成**：根据环境变量自动生成Kopia配置
2. **WebDAV URL动态识别**：处理重定向URL，确保连接稳定
3. **仓库自动管理**：自动连接或创建仓库，无需手动配置
4. **连接重连机制**：在连接丢失时自动重连
5. **工作目录初始化**：确保必要的目录和环境存在

## 新增功能

### 1. 动态仓库配置

脚本现在支持通过环境变量自动配置WebDAV仓库：

```bash
export WEBDAV_URL="https://dav.domain.name"
export WEBDAV_VOL_PATH="/path/to/nfs_srv_vol"
export KOPIA_REPOSITORY_NAME="kopia-repo"
export KOPIA_REPOSITORY_USER="username"
export KOPIA_REPOSITORY_PASS="password"
export KOPIA_PASSWORD="crypt-key"
export MANUAL_MODE_TIMEOUT=60
export VOLUMES_DIR="/nfs_volumes"
export BACKUP_MODE="auto /manual"

```

### 2. WebDAV URL重定向处理

自动检测和处理WebDAV服务器的重定向：

```bash
# 函数: get_real_webdav_url()
# 功能: 检测URL重定向，返回真实地址
# 用途: 处理动态跳转的WebDAV服务
```

### 3. 仓库自动管理

- **自动连接**：尝试连接现有仓库
- **自动创建**：如果仓库不存在，自动创建新仓库
- **目录创建**：确保WebDAV目录存在

### 4. 连接监控和重连

在自动模式中：
- 每个备份周期前检查仓库连接
- 连接丢失时自动重连
- 重连失败时等待5分钟后重试

### 5. 增强的错误处理

- 跳过特殊目录（如lost+found）
- 连接问题时中断当前周期
- 详细的错误日志和统计信息

## 使用方法

### 环境变量配置

参考 `example-env-config.sh` 文件：

```bash
source example-env-config.sh
./backup-manager.sh auto
```

### Docker Compose集成

可以直接使用compose中的环境变量：

```yaml
environment:
  - WEBDAV_URL=https://dav.domain.name
  - WEBDAV_VOL_PATH=/path/to/nfs_srv_vol
  - KOPIA_REPOSITORY_USER=username
  - KOPIA_REPOSITORY_PASS=passme
  - KOPIA_PASSWORD=nfs-backup-encryption-2025
  - export VOLUMES_DIR="/nfs_volumes"
  - export BACKUP_MODE="auto /manual"
```

### 手动配置兼容性

如果不设置WebDAV环境变量，脚本仍然支持手动配置的Kopia仓库。


## 与原功能的兼容性

- 保持所有原有功能不变
- 新功能为可选，不影响现有使用方式
- 向后兼容，无需修改现有配置

## 主要改进点

1. **奥卡姆剃刀原则**：复用现有函数，避免重复代码
2. **抽象优化**：统一的配置管理和错误处理
3. **简洁设计**：最小化新增代码，最大化功能增强
4. **环境适应**：自动适应不同的部署环境

## 注意事项

1. WebDAV配置为可选，未配置时需要手动设置仓库
2. 自动重连机制仅在自动模式中生效
3. 建议在生产环境中设置所有必要的环境变量
4. 密码等敏感信息应通过安全的方式传递
