#!/bin/bash

# 统一交互库 - 简洁清晰的用户交互框架
# 核心设计原则：
# 1. 统一的返回值约定：0=成功继续，1=用户取消返回上级，2=致命错误退出
# 2. 自动处理多级菜单导航
# 3. 统一的whiptail封装
# 4. 简化的API接口

# 依赖基础工具库
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/kopia-ops.sh"

# ============================================================================
# 核心交互原语 - 所有交互的基础
# ============================================================================

# 检查whiptail可用性，如果未安装则尝试自动安装
check_whiptail() {
    if ! command -v whiptail >/dev/null 2>&1; then
        log_warn "whiptail未安装，尝试自动安装..." "交互"

        # 尝试自动安装whiptail
        if install_whiptail; then
            log_success "whiptail安装成功" "交互"
            return 0
        else
            log_error "whiptail自动安装失败，请手动安装whiptail包" "交互"
            return 2
        fi
    fi
    return 0
}

# 自动安装whiptail
install_whiptail() {
    log_info "检测系统类型并安装whiptail..." "安装"

    # 检测包管理器并安装
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu系统
        log_info "检测到apt包管理器，安装whiptail..." "安装"
        if apt-get update >/dev/null 2>&1 && apt-get install -y whiptail >/dev/null 2>&1; then
            return 0
        fi
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL系统
        log_info "检测到yum包管理器，安装newt..." "安装"
        if yum install -y newt >/dev/null 2>&1; then
            return 0
        fi
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora系统
        log_info "检测到dnf包管理器，安装newt..." "安装"
        if dnf install -y newt >/dev/null 2>&1; then
            return 0
        fi
    elif command -v apk >/dev/null 2>&1; then
        # Alpine Linux系统
        log_info "检测到apk包管理器，安装newt..." "安装"
        if apk add --no-cache newt >/dev/null 2>&1; then
            return 0
        fi
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux系统
        log_info "检测到pacman包管理器，安装libnewt..." "安装"
        if pacman -S --noconfirm libnewt >/dev/null 2>&1; then
            return 0
        fi
    else
        log_error "未检测到支持的包管理器" "安装"
        return 1
    fi

    log_error "whiptail安装失败" "安装"
    return 1
}

# 统一的whiptail调用封装
# 返回值：0=用户选择，1=用户取消，2=系统错误
ui_call() {
    if ! check_whiptail; then
        return 2
    fi

    local result
    local exit_code

    result=$(whiptail "$@" 3>&1 1>&2 2>&3)
    exit_code=$?

    # 调试输出 (可选)
    # echo "[DEBUG] ui_call: whiptail exit_code=$exit_code, result='$result'" >&2

    case $exit_code in
        0)
            # 用户正常选择，输出结果（即使为空）
            echo "$result"
            return 0
            ;;
        1)
            # 用户点击Cancel按钮
            return 1
            ;;
        255)
            # 用户按ESC键
            return 255
            ;;
        *)
            # 系统错误
            return 2
            ;;
    esac
}

# 菜单选择
ui_menu() {
    local title="$1"
    local prompt="$2"
    local height="$3"
    local width="$4"
    local list_height="$5"
    shift 5

    # 调试输出 (可选)
    # echo "[DEBUG] ui_menu: title='$title', prompt='$prompt'" >&2
    # echo "[DEBUG] ui_menu: menu_options=($*)" >&2

    local result
    result=$(ui_call --title "$title" \
        --menu "$prompt" \
        "$height" "$width" "$list_height" \
        --ok-button "选择" \
        --cancel-button "返回" \
        "$@")
    local exit_code=$?

    # echo "[DEBUG] ui_menu: result='$result', exit_code=$exit_code" >&2

    if [ $exit_code -eq 0 ]; then
        echo "$result"
    fi
    return $exit_code
}

# 确认对话框
ui_confirm() {
    local title="$1"
    local message="$2"
    local height="${3:-8}"
    local width="${4:-50}"

    ui_call --title "$title" \
        --yesno "$message" \
        "$height" "$width" \
        --yes-button "确定" \
        --no-button "取消"
}

# 输入框
ui_input() {
    local title="$1"
    local prompt="$2"
    local height="${3:-10}"
    local width="${4:-50}"
    local default="${5:-}"

    ui_call --title "$title" \
        --inputbox "$prompt" \
        "$height" "$width" "$default" \
        --ok-button "确定" \
        --cancel-button "取消"
}

# 信息显示
ui_info() {
    local title="$1"
    local message="$2"
    local height="${3:-8}"
    local width="${4:-50}"

    ui_call --title "$title" \
        --msgbox "$message" \
        "$height" "$width" \
        --ok-button "确定"
}

# ============================================================================
# 多级菜单导航框架
# ============================================================================

# 多步骤向导 - 自动处理前进/后退导航
# 用法：ui_wizard step1_func step2_func step3_func ...
# 每个步骤函数接收前面所有步骤的结果作为参数
ui_wizard() {
    local steps=("$@")
    local step_count=${#steps[@]}
    local current_step=0
    local results=()

    while [ $current_step -lt $step_count ]; do
        local step_func="${steps[$current_step]}"

        # 调用步骤函数，传递之前的结果
        local result
        result=$($step_func "${results[@]}")
        local exit_code=$?

        case $exit_code in
            0)
                # 成功，保存结果并前进
                results[$current_step]="$result"
                current_step=$((current_step + 1))
                ;;
            1)
                # 用户取消，后退
                if [ $current_step -eq 0 ]; then
                    return 1  # 第一步取消，退出向导
                else
                    current_step=$((current_step - 1))
                    # 清空当前及后续步骤的结果
                    for ((i=current_step; i<step_count; i++)); do
                        results[$i]=""
                    done
                fi
                ;;
            2)
                # 致命错误，退出
                return 2
                ;;
        esac
    done

    # 所有步骤完成，输出结果
    echo "${results[@]}"
    return 0
}

# ============================================================================
# 业务逻辑选择器 - 基于核心原语构建的高级接口
# ============================================================================

# 从列表中选择项目
ui_select_from_list() {
    local items="$1"
    local title="$2"
    local prompt="${3:-请选择一个选项:}"

    if [ -z "$items" ]; then
        ui_info "错误" "选择列表为空"
        return 2
    fi

    # 构建菜单选项
    local menu_options=()
    local i=1
    while IFS= read -r item; do
        if [ -n "$item" ]; then
            menu_options+=("$i" "$item")
            i=$((i + 1))
        fi
    done <<< "$items"

    if [ ${#menu_options[@]} -eq 0 ]; then
        ui_info "错误" "没有可选择的项目"
        return 2
    fi

    local choice
    choice=$(ui_menu "$title" "$prompt" 15 70 8 "${menu_options[@]}")
    local exit_code=$?

    # 调试输出 (可选)
    # echo "[DEBUG] ui_select_from_list: choice='$choice', exit_code=$exit_code" >&2

    # 处理不同的退出码
    case $exit_code in
        0)
            # 用户正常选择
            local selected_item
            selected_item=$(echo "$items" | sed -n "${choice}p")
            echo "$selected_item"
            return 0
            ;;
        1)
            # 用户点击Cancel按钮
            return 1
            ;;
        255)
            # 用户按ESC键
            return 255
            ;;
        *)
            # 其他错误
            return $exit_code
            ;;
    esac
}

# 选择NFS卷
ui_select_volume() {
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        ui_info "错误" "未找到可用卷"
        return 2
    fi

    ui_select_from_list "$volumes" "选择NFS卷"
}

# 选择NFS卷（包括"所有卷"选项）
ui_select_volume_with_all() {
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        ui_info "错误" "未找到可用卷"
        return 2
    fi

    # 将"所有卷"选项添加到列表末尾（更安全）
    local volumes_with_all="$volumes"$'\n'"所有卷"

    local selected
    selected=$(ui_select_from_list "$volumes_with_all" "选择NFS卷")
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        if [ "$selected" = "所有卷" ]; then
            echo "ALL_VOLUMES"
        else
            echo "$selected"
        fi
    fi

    return $exit_code
}

# 选择快照 - 按时间降序排列，最新快照在第一位并标记
ui_select_snapshot() {
    local volume="$1"
    local allow_latest="${2:-true}"

    if [ -z "$volume" ]; then
        ui_info "错误" "卷名不能为空"
        return 2
    fi

    # 显示加载提示
    ui_call --title "加载中" --infobox "正在获取卷 [$volume] 的快照信息..." 6 60

    # 使用修复后的get_volume_snapshots函数，确保按时间降序排列
    local snapshots
    snapshots=$(get_volume_snapshots "$volume")

    if [ $? -ne 0 ] || [ -z "$snapshots" ]; then
        ui_info "信息" "卷[$volume]暂无快照"
        return 2
    fi

    # 构建快照选项 - 移除"0 使用最新快照"选项
    local menu_options=()
    local id_mapping=()
    local i=1
    local is_first=true

    while IFS= read -r line; do
        if [ -n "$line" ]; then
            # 提取快照信息
            local clean_line
            clean_line=$(echo "$line" | sed 's/^[[:space:]]*//')

            # 提取日期时间和快照ID
            local snapshot_date=$(echo "$clean_line" | awk '{print $1, $2}')
            local snapshot_id=$(echo "$clean_line" | grep -o '[a-f0-9]\{8,\}' | head -1)

            if [ -n "$snapshot_id" ] && [ -n "$snapshot_date" ]; then
                # 第一个快照标记为"(最新)"
                if [ "$is_first" = "true" ]; then
                    menu_options+=("$i" "📸 $snapshot_date [${snapshot_id:0:8}] (最新)")
                    is_first=false
                else
                    menu_options+=("$i" "📸 $snapshot_date [${snapshot_id:0:8}]")
                fi
                id_mapping[$i]="$snapshot_id"
                i=$((i + 1))
            fi
        fi
    done <<< "$snapshots"

    if [ ${#menu_options[@]} -eq 0 ]; then
        ui_info "信息" "卷[$volume]暂无快照"
        return 2
    fi

    local choice
    choice=$(ui_menu "选择快照 - 卷[$volume]" "选择要使用的快照:" 15 70 8 "${menu_options[@]}")
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        return $exit_code
    fi

    # 返回快照ID
    echo "${id_mapping[$choice]}"
    return 0
}

# 选择恢复目标路径 - 优化设计，默认使用应急恢复目录
ui_select_target_path() {
    local volume="$1"

    if [ -z "$volume" ]; then
        ui_info "错误" "卷名不能为空"
        return 2
    fi

    local volume_path="$VOLUMES_DIR/$volume"
    local recovery_base="$VOLUMES_DIR/.recovery"

    local choice
    choice=$(ui_menu "选择恢复目标" "选择恢复方式:" 12 60 2 \
        "1" "恢复到原卷位置 (替换所有数据)" \
        "2" "恢复到应急目录 (安全恢复)")

    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        return $exit_code
    fi

    case "$choice" in
        1)
            echo "$volume_path"
            return 0
            ;;
        2)
            # 应急恢复目录 - 默认路径
            local default_recovery_path="$recovery_base/$volume/restored_$(date +%Y%m%d_%H%M%S)"

            local custom_path
            custom_path=$(ui_input "应急恢复路径" "确认或修改恢复路径:" 12 70 "$default_recovery_path")
            local input_exit_code=$?

            if [ $input_exit_code -ne 0 ]; then
                return $input_exit_code
            fi

            if [ -z "$custom_path" ]; then
                custom_path="$default_recovery_path"
            fi

            # 安全检查：如果用户指定的路径在NFS卷下，强制重定向到应急目录
            if [[ "$custom_path" == "$VOLUMES_DIR"/* ]] && [[ "$custom_path" != "$recovery_base"/* ]]; then
                ui_info "路径重定向" "检测到路径在NFS卷下，为避免干扰卷识别，已重定向到应急恢复目录"
                custom_path="$recovery_base/$volume/$(basename "$custom_path")"
            fi

            # 确保应急恢复目录存在
            mkdir -p "$(dirname "$custom_path")"

            echo "$custom_path"
            return 0
            ;;
    esac
}

# 简单确认
ui_confirm_operation() {
    local message="$1"
    local title="${2:-确认操作}"

    ui_confirm "$title" "$message"
}

# 危险操作确认（多重确认）
ui_confirm_dangerous() {
    local operation="$1"
    local target="$2"
    local required_input="$3"

    # 第一重确认
    local warning_msg="⚠️ 危险操作警告 ⚠️\n\n操作: $operation\n目标: $target\n\n此操作不可撤销！\n\n确定要继续吗？"

    if ! ui_confirm "危险操作确认" "$warning_msg" 12 60; then
        return 1
    fi

    # 第二重确认（如果需要输入验证）
    if [ -n "$required_input" ]; then
        local user_input
        user_input=$(ui_input "确认目标名称" "请输入目标名称 '$required_input' 以确认:" 10 50)
        local input_exit_code=$?

        if [ $input_exit_code -ne 0 ]; then
            return $input_exit_code
        fi

        if [ "$user_input" != "$required_input" ]; then
            ui_info "操作取消" "名称不匹配，操作已取消"
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# 兼容性接口 - 保持向后兼容
# ============================================================================

# 为了保持向后兼容，提供旧接口的映射
select_volume_interactive() { ui_select_volume "$@"; }
select_snapshot_interactive() { ui_select_snapshot "$@"; }
select_target_path_interactive() { ui_select_target_path "$@"; }
confirm_operation() { ui_confirm_operation "$@"; }
confirm_dangerous_operation() { ui_confirm_dangerous "$@"; }

