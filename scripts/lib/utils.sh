#!/bin/bash

# 基础工具函数库
# 提供日志、显示、输入验证等通用功能

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 日志函数 - 统一格式，支持标签分类，修复与进度条的冲突
log_info() {
    local message="$1"
    local tag="${2:-通用}"
    # 先换行以避免与进度条冲突
    printf "\n[${BLUE}INFO${NC}] [${CYAN}%-6s${NC}] [${CYAN}%s${NC}] %s\n" "$tag" "$(date '+%H:%M:%S')" "$message"
}

log_warn() {
    local message="$1"
    local tag="${2:-通用}"
    printf "\n[${YELLOW}WARN${NC}] [${CYAN}%-6s${NC}] [${CYAN}%s${NC}] %s\n" "$tag" "$(date '+%H:%M:%S')" "$message"
}

log_error() {
    local message="$1"
    local tag="${2:-通用}"
    printf "\n[${RED}ERRO${NC}] [${CYAN}%-6s${NC}] [${CYAN}%s${NC}] %s\n" "$tag" "$(date '+%H:%M:%S')" "$message"
}

log_success() {
    local message="$1"
    local tag="${2:-通用}"
    printf "\n[${GREEN}SUCC${NC}] [${CYAN}%-6s${NC}] [${CYAN}%s${NC}] %s\n" "$tag" "$(date '+%H:%M:%S')" "$message"
}

# 高亮显示函数
highlight() { 
    printf "${BOLD}${YELLOW}%s${NC}\n" "$1"
}

danger() { 
    printf "${BOLD}${RED}%s${NC}\n" "$1"
}

# 进度显示函数
show_progress() {
    local current=$1
    local total=$2
    local message="$3"
    local percent=$((current * 100 / total))
    local bar_length=50
    local filled_length=$((percent * bar_length / 100))
    
    printf "\r${CYAN}[%-${bar_length}s] %d%% %s${NC}" \
        "$(printf "%*s" $filled_length | tr ' ' '=')" \
        "$percent" "$message"
    
    if [ $current -eq $total ]; then
        echo
    fi
}

# 输入验证函数
validate_number_input() {
    local input="$1"
    local min="$2"
    local max="$3"
    
    # 检查是否为数字
    if ! [[ "$input" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # 检查范围
    if [ "$input" -lt "$min" ] || [ "$input" -gt "$max" ]; then
        return 1
    fi
    
    return 0
}

# 确认操作函数 - 支持特定输入要求
confirm_operation() {
    local prompt="$1"
    local required_input="$2"  # 如果指定，用户必须输入这个确切值
    
    printf "%s" "$prompt"
    read -r user_input
    
    if [ -n "$required_input" ]; then
        # 需要特定输入
        if [ "$user_input" = "$required_input" ]; then
            return 0
        else
            return 1
        fi
    else
        # 标准 y/N 确认
        if [ "$user_input" = "y" ] || [ "$user_input" = "Y" ]; then
            return 0
        else
            return 1
        fi
    fi
}

# 获取用户选择 - 支持默认值
get_user_choice() {
    local prompt="$1"
    local default="$2"
    
    if [ -n "$default" ]; then
        printf "%s (default: %s): " "$prompt" "$default"
    else
        printf "%s: " "$prompt"
    fi
    
    read -r user_input
    
    # 如果输入为空且有默认值，返回默认值
    if [ -z "$user_input" ] && [ -n "$default" ]; then
        echo "$default"
    else
        echo "$user_input"
    fi
}

# 等待用户按键继续
wait_for_enter() {
    local message="${1:-Press Enter to continue...}"
    echo
    printf "%s" "$message"
    read -r
}

# 清屏并显示标题
show_screen_title() {
    local title="$1"
    clear
    echo
    highlight "=== $title ==="
    echo
}

# 时间计算工具
calculate_duration() {
    local start_time="$1"
    local end_time="$2"
    echo $((end_time - start_time))
}

format_duration() {
    local seconds="$1"
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# 下次备份时间计算（支持小数小时）
calculate_next_backup_time() {
    local hours_offset="${1:-6}"

    # 将小数小时转换为秒数（纯bash实现）
    local seconds_offset
    if [[ "$hours_offset" == *"."* ]]; then
        # 处理小数：分离整数和小数部分
        local integer_part="${hours_offset%.*}"
        local decimal_part="${hours_offset#*.}"

        # 计算整数部分的秒数
        local integer_seconds=$((integer_part * 3600))

        # 计算小数部分的秒数（假设最多2位小数）
        local decimal_seconds=0
        if [ ${#decimal_part} -eq 1 ]; then
            # 一位小数：0.1 = 360秒
            decimal_seconds=$((decimal_part * 360))
        elif [ ${#decimal_part} -eq 2 ]; then
            # 两位小数：0.01 = 36秒
            decimal_seconds=$((decimal_part * 36))
        fi

        seconds_offset=$((integer_seconds + decimal_seconds))
    else
        # 整数小时
        seconds_offset=$((hours_offset * 3600))
    fi

    # 使用秒数计算下次备份时间
    date -d "+${seconds_offset} seconds" "+%Y-%m-%d %H:%M:%S"
}

# 检查必需的环境变量
check_required_env() {
    local var_name="$1"
    local var_value="${!var_name}"
    
    if [ -z "$var_value" ]; then
        log_error "Required environment variable not set: $var_name" "环境"
        return 1
    fi
    return 0
}

# 检查目录是否存在，不存在则创建
ensure_directory() {
    local dir_path="$1"
    
    if [ ! -d "$dir_path" ]; then
        log_info "Creating directory: $dir_path" "文件"
        mkdir -p "$dir_path"
        return $?
    fi
    return 0
}

# 安全的文件操作 - 带备份
safe_file_operation() {
    local operation="$1"  # "copy", "move", "delete"
    local source="$2"
    local target="$3"
    
    case "$operation" in
        "copy")
            if [ -f "$target" ]; then
                cp "$target" "${target}.backup.$(date +%s)"
            fi
            cp "$source" "$target"
            ;;
        "move")
            if [ -f "$target" ]; then
                cp "$target" "${target}.backup.$(date +%s)"
            fi
            mv "$source" "$target"
            ;;
        "delete")
            if [ -f "$source" ]; then
                cp "$source" "${source}.backup.$(date +%s)"
                rm "$source"
            fi
            ;;
        *)
            log_error "Unknown file operation: $operation" "文件"
            return 1
            ;;
    esac
}

# 统一的卷识别函数 - 跳过特殊目录
get_valid_volumes() {
    ls -1 "$VOLUMES_DIR" 2>/dev/null | \
    grep -v "^\\." | \
    grep -v "\\.deleted\\." | \
    grep -v "lost+found" | \
    grep -v "\\.tmp$" | \
    sort || true
}
