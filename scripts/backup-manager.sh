#!/bin/bash

# NFS备份管理器 - 重构优化版本
# 运行在备份管理服务容器内，支持手动和自动模式
#
# 特性:
# - DRY原则重构，最大化代码复用
# - 修复交互式操作bug（ESC/Cancel/数字键）
# - 优化异步加载和进度显示
# - 完善flush操作（卷/备份/both）
# - 简洁抽象设计，遵循奥卡姆剃刀原则

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# 检查库文件是否存在
check_lib_files() {
    local required_libs=(
        "utils.sh"
        "kopia-ops.sh" 
        "interactive.sh"
        "backup-operations.sh"
        "modes.sh"
    )
    
    for lib in "${required_libs[@]}"; do
        if [ ! -f "$LIB_DIR/$lib" ]; then
            echo "错误: 缺少库文件 $LIB_DIR/$lib"
            echo "请确保所有库文件都已正确安装"
            exit 1
        fi
    done
}

# 加载库文件
load_libraries() {
    check_lib_files
    
    # 按依赖顺序加载
    source "$LIB_DIR/utils.sh"
    source "$LIB_DIR/kopia-ops.sh"
    source "$LIB_DIR/interactive.sh"
    source "$LIB_DIR/backup-operations.sh"
    source "$LIB_DIR/modes.sh"
}

# 配置环境变量
setup_environment() {
    # 从环境变量获取配置，设置默认值
    export VOLUMES_DIR="${VOLUMES_DIR:-/nfs_volumes}"
    export KOPIA_CONFIG_PATH="${KOPIA_CONFIG_PATH:-/app/config/kopia.config}"
    export KOPIA_CACHE_DIRECTORY="${KOPIA_CACHE_DIRECTORY:-/app/cache}"
    export BACKUP_MODE="${BACKUP_MODE:-}"

    # WebDAV仓库配置 - 借鉴compose脚本的动态配置
    export WEBDAV_URL="${WEBDAV_URL:-}"
    export WEBDAV_VOL_PATH="${WEBDAV_VOL_PATH:-}"
    export KOPIA_REPOSITORY_NAME="${KOPIA_REPOSITORY_NAME:-kopia-repo}"
    export KOPIA_REPOSITORY_TYPE="${KOPIA_REPOSITORY_TYPE:-webdav}"
    export KOPIA_REPOSITORY_USER="${KOPIA_REPOSITORY_USER:-}"
    export KOPIA_REPOSITORY_PASS="${KOPIA_REPOSITORY_PASS:-}"
    export KOPIA_PASSWORD="${KOPIA_PASSWORD:-}"

    # 动态生成仓库URL
    if [ -n "$WEBDAV_URL" ] && [ -n "$WEBDAV_VOL_PATH" ]; then
        export KOPIA_REPOSITORY_URL="${WEBDAV_URL}${WEBDAV_VOL_PATH}/${KOPIA_REPOSITORY_NAME}"
        log_info "动态生成仓库URL: $KOPIA_REPOSITORY_URL" "环境"
    fi

    # 验证必需的环境变量
    if ! check_required_env "VOLUMES_DIR"; then
        exit 1
    fi

    # 确保目录存在
    if ! ensure_directory "$VOLUMES_DIR"; then
        log_error "无法创建或访问卷目录: $VOLUMES_DIR" "环境"
        exit 1
    fi

    if ! ensure_directory "$(dirname "$KOPIA_CONFIG_PATH")"; then
        log_error "无法创建Kopia配置目录: $(dirname "$KOPIA_CONFIG_PATH")" "环境"
        exit 1
    fi

    if ! ensure_directory "$KOPIA_CACHE_DIRECTORY"; then
        log_error "无法创建Kopia缓存目录: $KOPIA_CACHE_DIRECTORY" "环境"
        exit 1
    fi

    # 初始化Kopia环境配置
    init_kopia_dynamic_config
}

# 验证运行环境
validate_environment() {
    # 检查是否在测试模式
    if [ "$BACKUP_MODE" = "help" ] || [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        log_info "帮助模式，跳过环境验证" "环境"
        return 0
    fi

    # 设置正确的终端模式，确保交互式输入正常工作
    if [ -t 0 ] && [ -t 1 ]; then
        # 确保终端处于正确的模式
        stty sane 2>/dev/null || true
        # 设置终端为立即模式，不需要等待换行
        stty -icanon min 1 time 0 2>/dev/null || true
        # 恢复标准模式
        stty icanon 2>/dev/null || true
    fi

    # 检查是否在容器内运行
    if [ -f "/.dockerenv" ] || ([ -f "/proc/1/cgroup" ] && grep -q docker /proc/1/cgroup 2>/dev/null); then
        log_info "运行在Docker容器内" "环境"
    else
        log_warn "似乎不在Docker容器内运行" "环境"
        log_warn "此脚本设计为在备份管理容器内运行" "环境"
    fi

    # 检查Kopia二进制文件
    if [ ! -x "/bin/kopia" ]; then
        log_error "Kopia二进制文件不存在或不可执行: /bin/kopia" "环境"
        log_error "如需测试，请在容器内运行或使用测试脚本" "环境"
        exit 1
    fi

    # 检查卷目录访问权限
    if [ ! -r "$VOLUMES_DIR" ] || [ ! -w "$VOLUMES_DIR" ]; then
        log_error "卷目录权限不足: $VOLUMES_DIR" "环境"
        exit 1
    fi

    log_info "环境验证通过" "环境"
}

# 显示启动信息
show_startup_info() {
    echo
    highlight "=== NFS Backup Manager - 重构版本 ==="
    echo
    log_info "脚本目录: $SCRIPT_DIR" "启动"
    log_info "库目录: $LIB_DIR" "启动"
    log_info "卷目录: $VOLUMES_DIR" "启动"
    log_info "Kopia配置: $KOPIA_CONFIG_PATH" "启动"
    log_info "Kopia缓存: $KOPIA_CACHE_DIRECTORY" "启动"
    
    if [ -n "$BACKUP_MODE" ]; then
        log_info "运行模式: $BACKUP_MODE" "启动"
    else
        log_info "运行模式: 未指定 (将显示帮助)" "启动"
    fi
    echo
}

# 主函数
main() {
    # 初始化
    load_libraries
    setup_environment
    show_startup_info
    validate_environment "$@"
    
    # 处理命令行参数和环境变量
    local mode="$BACKUP_MODE"
    
    # 命令行参数优先于环境变量
    if [ $# -gt 0 ]; then
        case "$1" in
            manual|auto|help|--help|-h)
                mode="$1"
                ;;
            *)
                log_error "未知参数: $1" "参数"
                mode="help"
                ;;
        esac
    fi
    
    # 如果没有设置模式或模式为空，显示帮助
    if [ -z "$mode" ] || [ "$mode" = "help" ] || [ "$mode" = "--help" ] || [ "$mode" = "-h" ]; then
        show_help_info
        exit 0
    fi
    
    # 根据模式执行相应逻辑
    case "$mode" in
        manual)
            run_manual_mode
            ;;
        auto)
            run_auto_mode
            ;;
        *)
            log_error "未知模式: $mode" "模式"
            echo
            show_help_info
            exit 1
            ;;
    esac
}

# 移除set -e，让whiptail的ESC/Cancel正常工作
# 在需要的地方单独检查错误状态

# 信号处理
cleanup() {
    log_info "收到退出信号，正在清理..." "系统"
    
    # 清理临时文件
    rm -f /tmp/kopia_backup_$$.log 2>/dev/null || true
    rm -f /tmp/kopia_restore_$$.log 2>/dev/null || true
    
    log_info "清理完成，退出" "系统"
    exit 0
}

trap cleanup SIGTERM SIGINT

# 如果直接执行脚本
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
