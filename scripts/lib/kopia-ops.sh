#!/bin/bash

# Kopia操作封装库
# 提供所有Kopia相关的操作接口

# 依赖基础工具库
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# 配置变量 - 确保这些是环境变量
export VOLUMES_DIR="${VOLUMES_DIR:-/nfs_volumes}"
export KOPIA_CONFIG_PATH="${KOPIA_CONFIG_PATH:-/app/config/kopia.config}"
export KOPIA_CACHE_DIRECTORY="${KOPIA_CACHE_DIRECTORY:-/app/cache}"

# 初始化Kopia环境
init_kopia_environment() {
    export KOPIA_CONFIG_PATH="$KOPIA_CONFIG_PATH"
    export KOPIA_CACHE_DIRECTORY="$KOPIA_CACHE_DIRECTORY"

    log_info "初始化Kopia环境" "Kopia"
    log_info "配置路径: $KOPIA_CONFIG_PATH" "Kopia"
    log_info "缓存目录: $KOPIA_CACHE_DIRECTORY" "Kopia"
}

# 动态获取真实WebDAV URL - 借鉴compose脚本，修复输出污染问题
get_real_webdav_url() {
    local original_url="$1"

    if [ -z "$original_url" ]; then
        log_error "WebDAV URL不能为空" "WebDAV"
        return 1
    fi

    # 使用curl检查重定向，重定向到stderr避免污染输出
    local real_url
    real_url=$(curl -s -I "$original_url" 2>/dev/null | grep -i "location:" | cut -d' ' -f2 | tr -d '\r')

    if [ -n "$real_url" ]; then
        # 输出到stderr避免污染函数返回值
        log_info "检测到URL重定向: $original_url -> $real_url" "WebDAV" >&2
        echo "$real_url"
    else
        log_info "使用原始URL (无重定向): $original_url" "WebDAV" >&2
        echo "$original_url"
    fi

    return 0
}

# 检查WebDAV目录 - 使用标准PROPFIND方法
check_webdav_directory() {
    local webdav_url="$1"
    local username="$2"
    local password="$3"

    if [ -z "$webdav_url" ] || [ -z "$username" ] || [ -z "$password" ]; then
        log_error "WebDAV URL、用户名和密码不能为空" "WebDAV"
        return 1
    fi

    log_info "检查WebDAV目录连接性: $webdav_url" "WebDAV"

    # 使用PROPFIND方法测试WebDAV连接（推荐方法）
    local response_code
    response_code=$(curl -X PROPFIND \
        --user "$username:$password" \
        -H "Depth: 0" \
        -s -o /dev/null \
        -w "%{http_code}" \
        "$webdav_url" 2>/dev/null)

    log_info "WebDAV PROPFIND测试返回状态码: $response_code" "WebDAV"

    case "$response_code" in
        207)
            log_success "WebDAV连接成功 (207 Multi-Status)" "WebDAV"
            return 0
            ;;
        301|302|307|308)
            log_info "WebDAV URL重定向 ($response_code)，这是正常的" "WebDAV"
            log_info "Kopia会自动处理重定向" "WebDAV"
            return 0
            ;;
        401)
            log_error "WebDAV认证失败 (401 Unauthorized)" "WebDAV"
            log_error "请检查用户名和密码" "WebDAV"
            return 1
            ;;
        403)
            log_error "WebDAV访问被拒绝 (403 Forbidden)" "WebDAV"
            log_error "请检查用户权限设置" "WebDAV"
            return 1
            ;;
        404)
            log_warn "WebDAV目录不存在 (404 Not Found)" "WebDAV"
            log_info "尝试创建目录..." "WebDAV"
            create_webdav_directory "$webdav_url" "$username" "$password"
            return $?
            ;;
        *)
            log_warn "WebDAV连接测试返回状态码: $response_code" "WebDAV"
            log_info "继续执行，Kopia会进行更详细的检查" "WebDAV"
            return 0  # 继续执行，让Kopia进行更准确的检查
            ;;
    esac
}

# 创建WebDAV目录 - 仅在目录不存在时使用
create_webdav_directory() {
    local webdav_url="$1"
    local username="$2"
    local password="$3"

    log_info "尝试创建WebDAV目录: $webdav_url" "WebDAV"

    # 提取直接父目录
    local parent_url="${webdav_url%/*}"
    
    # 基准情况：到达协议头或无法再分割
    if [[ "$parent_url" == *://*/* ]]; then
        # 递归创建上级目录
        create_webdav_directory "$parent_url" "$username" "$password" || return $?
    fi

    # 使用MKCOL方法创建目录
    local create_response
    create_response=$(curl -s -u "$username:$password" -X MKCOL "$webdav_url" -w "%{http_code}" -o /dev/null 2>/dev/null)

    case "$create_response" in
        201)
            log_success "WebDAV目录创建成功" "WebDAV"
            return 0
            ;;
        409)
            log_info "WebDAV目录已存在" "WebDAV"
            return 0
            ;;
        401)
            log_error "WebDAV认证失败 (401 Unauthorized)" "WebDAV"
            return 1
            ;;
        403)
            log_error "WebDAV创建目录被拒绝 (403 Forbidden)" "WebDAV"
            return 1
            ;;
        *)
            log_warn "WebDAV目录创建返回状态码: $create_response" "WebDAV"
            return 0  # 继续执行，可能是权限问题但目录存在
            ;;
    esac
}

# 动态初始化Kopia配置 - 借鉴compose脚本的配置生成逻辑
init_kopia_dynamic_config() {
    log_info "初始化Kopia动态配置" "配置"

    # 确保配置和缓存目录存在
    ensure_directory "$(dirname "$KOPIA_CONFIG_PATH")"
    ensure_directory "$KOPIA_CACHE_DIRECTORY"

    # 设置Kopia环境变量
    export KOPIA_CONFIG_PATH="$KOPIA_CONFIG_PATH"
    export KOPIA_CACHE_DIRECTORY="$KOPIA_CACHE_DIRECTORY"

    log_info "Kopia配置路径: $KOPIA_CONFIG_PATH" "配置"
    log_info "Kopia缓存目录: $KOPIA_CACHE_DIRECTORY" "配置"

    # 如果配置了WebDAV仓库信息，设置仓库URL
    if [ -n "$KOPIA_REPOSITORY_URL" ]; then
        log_info "仓库URL: $KOPIA_REPOSITORY_URL" "配置"
    fi

    return 0
}

# 检查Kopia连接状态
check_kopia_connection() {
    if ! /bin/kopia repository status >/dev/null 2>&1; then
        log_error "Kopia repository未连接" "Kopia"
        return 1
    fi
    log_info "Kopia repository连接正常" "Kopia"
    return 0
}

# 连接或创建仓库 - 借鉴compose脚本的仓库管理逻辑，增强调试信息
setup_kopia_repository() {
    log_info "设置Kopia仓库连接" "仓库"

    # 检查是否已配置仓库信息
    if [ -z "$KOPIA_REPOSITORY_URL" ] || [ -z "$KOPIA_REPOSITORY_USER" ] || [ -z "$KOPIA_REPOSITORY_PASS" ]; then
        log_warn "仓库配置信息不完整，跳过自动仓库设置" "仓库"
        log_info "请手动配置Kopia仓库或设置环境变量:" "仓库"
        log_info "  KOPIA_REPOSITORY_URL, KOPIA_REPOSITORY_USER, KOPIA_REPOSITORY_PASS" "仓库"
        return 0
    fi

    log_info "仓库配置信息:" "仓库"
    log_info "  URL: $KOPIA_REPOSITORY_URL" "仓库"
    log_info "  用户: $KOPIA_REPOSITORY_USER" "仓库"
    log_info "  密码: [已设置]" "仓库"

    # 获取真实的WebDAV URL
    local real_url
    real_url=$(get_real_webdav_url "$KOPIA_REPOSITORY_URL")
    if [ $? -ne 0 ]; then
        log_error "无法获取真实WebDAV URL" "仓库"
        return 1
    fi

    # 检查WebDAV目录连接性
    if ! check_webdav_directory "$real_url" "$KOPIA_REPOSITORY_USER" "$KOPIA_REPOSITORY_PASS"; then
        log_warn "WebDAV目录检查失败，但继续尝试连接仓库" "仓库"
    fi

    # 尝试连接现有仓库
    log_info "尝试连接现有仓库: $real_url" "仓库"
    local connect_output
    connect_output=$(/bin/kopia repository connect webdav \
        --url="$real_url" \
        --webdav-username="$KOPIA_REPOSITORY_USER" \
        --webdav-password="$KOPIA_REPOSITORY_PASS" 2>&1)

    if [ $? -eq 0 ]; then
        log_success "连接到现有仓库成功" "仓库"
        return 0
    else
        log_warn "连接现有仓库失败: $connect_output" "仓库"
    fi

    # 如果连接失败，尝试创建新仓库
    if [ -n "$KOPIA_PASSWORD" ]; then
        log_info "创建新仓库" "仓库"
        local create_output
        create_output=$(printf "%s\n%s\n" "$KOPIA_PASSWORD" "$KOPIA_PASSWORD" | /bin/kopia repository create webdav \
            --url="$real_url" \
            --webdav-username="$KOPIA_REPOSITORY_USER" \
            --webdav-password="$KOPIA_REPOSITORY_PASS" 2>&1)

        if [ $? -eq 0 ]; then
            log_success "仓库创建成功" "仓库"
            return 0
        else
            log_error "仓库创建失败: $create_output" "仓库"
            return 1
        fi
    else
        log_error "未设置KOPIA_PASSWORD，无法创建新仓库" "仓库"
        return 1
    fi
}

# 重连仓库 - 处理动态URL变化，借鉴compose脚本
reconnect_kopia_repository() {
    log_info "尝试重新连接仓库" "重连"

    # 断开当前连接
    /bin/kopia repository disconnect >/dev/null 2>&1 || true

    # 重新设置仓库连接
    if setup_kopia_repository; then
        log_success "仓库重连成功" "重连"
        return 0
    else
        log_error "仓库重连失败" "重连"
        return 1
    fi
}

# 获取可用卷列表 - 使用统一的卷识别函数
get_available_volumes() {
    local volumes
    volumes=$(get_valid_volumes)

    if [ -z "$volumes" ]; then
        log_warn "未找到可用卷" "卷管理"
        return 1
    fi

    echo "$volumes"
    return 0
}

# 获取卷的快照列表 - 按时间降序排列（最新的在前），显示所有快照
get_volume_snapshots() {
    local volume="$1"
    local limit="${2:-10}"

    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "快照"
        return 1
    fi

    local snapshots
    # 使用--all参数确保显示所有快照，包括相同内容的快照
    if [ "$limit" -eq 0 ]; then
        # limit为0表示获取所有快照，不使用head限制
        snapshots=$(/bin/kopia snapshot list "$VOLUMES_DIR/$volume" 2>/dev/null | \
            grep -E "^  [0-9]" | tac || true)
    else
        snapshots=$(/bin/kopia snapshot list "$VOLUMES_DIR/$volume" 2>/dev/null | \
            grep -E "^  [0-9]" | tac | head -"$limit" || true)
    fi

    if [ -z "$snapshots" ]; then
        # 不输出错误，只是返回空结果
        return 1
    fi

    echo "$snapshots"
    return 0
}

# 获取快照详细信息 - 返回ID和显示信息的映射，高性能版本
get_snapshot_details() {
    local volume="$1"
    local limit="${2:-10}"  # 默认限制10个快照

    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "快照"
        return 1
    fi

    # 使用临时文件避免多次调用kopia
    local temp_json=$(mktemp)
    local temp_list=$(mktemp)

    # 并行获取JSON和列表格式的快照信息，使用--all显示所有快照
    {
        /bin/kopia snapshot list "$VOLUMES_DIR/$volume" --json --all 2>/dev/null > "$temp_json" &
        /bin/kopia snapshot list "$VOLUMES_DIR/$volume" --all 2>/dev/null > "$temp_list" &
        wait
    }

    # 检查是否获取成功
    if [ ! -s "$temp_json" ] || [ ! -s "$temp_list" ]; then
        rm -f "$temp_json" "$temp_list"
        log_warn "卷[$volume]快照信息获取失败" "快照"
        return 1
    fi

    # 从JSON中提取快照ID
    local snapshot_ids
    snapshot_ids=$(grep -o '"id":"[^"]*"' "$temp_json" | cut -d'"' -f4 | head -"$limit")

    # 从列表中提取显示信息
    local snapshot_lines
    snapshot_lines=$(grep -E "^  [0-9]" "$temp_list" | head -"$limit")

    # 清理临时文件
    rm -f "$temp_json" "$temp_list"

    if [ -z "$snapshot_ids" ] || [ -z "$snapshot_lines" ]; then
        log_warn "卷[$volume]未找到快照" "快照"
        return 1
    fi

    # 输出格式: snapshot_id|display_info
    local line_num=1
    for snapshot_id in $snapshot_ids; do
        local display_info
        display_info=$(echo "$snapshot_lines" | sed -n "${line_num}p")
        if [ -n "$display_info" ]; then
            echo "${snapshot_id}|${display_info}"
        fi
        line_num=$((line_num + 1))
    done

    return 0
}

# 创建快照 - 带进度显示
create_snapshot_with_progress() {
    local volume="$1"
    local description="$2"
    local tags="$3"

    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "备份"
        return 1
    fi

    local volume_path="$VOLUMES_DIR/$volume"
    if [ ! -d "$volume_path" ]; then
        log_error "卷目录不存在: $volume_path" "备份"
        return 1
    fi

    log_info "开始创建快照: 卷[$volume]" "备份"
    local start_time=$(date +%s)

    # 构建命令参数
    local cmd_args=("$volume_path")

    if [ -n "$description" ]; then
        cmd_args+=("--description=$description")
    fi

    if [ -n "$tags" ]; then
        cmd_args+=("--tags=$tags")
    fi

    # 显示进度状态
    printf "${CYAN}正在创建快照...${NC}\n"
    printf "${CYAN}卷: %s${NC}\n" "$volume"
    printf "${CYAN}开始时间: %s${NC}\n" "$(date '+%H:%M:%S')"
    echo

    # 执行备份并捕获输出
    local temp_log="/tmp/kopia_backup_$$.log"
    if /bin/kopia snapshot create "${cmd_args[@]}" 2>&1 | tee "$temp_log" | while IFS= read -r line; do
        # 解析Kopia输出，显示进度信息
        if echo "$line" | grep -q "Processed\|Uploaded\|Compressed"; then
            printf "\r${CYAN}状态: %s${NC}" "$line"
        elif echo "$line" | grep -q "Snapshot created"; then
            echo
            printf "${GREEN}✓ %s${NC}\n" "$line"
        fi
    done; then
        local end_time=$(date +%s)
        local duration=$(calculate_duration "$start_time" "$end_time")
        echo
        log_success "快照创建成功: 卷[$volume] 耗时$(format_duration $duration)" "备份"

        # 清理临时日志
        rm -f "$temp_log"
        return 0
    else
        echo
        log_error "快照创建失败: 卷[$volume]" "备份"

        # 显示错误详情
        if [ -f "$temp_log" ]; then
            log_error "错误详情:" "备份"
            tail -5 "$temp_log" | while IFS= read -r line; do
                printf "  ${RED}%s${NC}\n" "$line"
            done
            rm -f "$temp_log"
        fi
        return 1
    fi
}

# 验证快照完整性
verify_snapshot() {
    local snapshot_id="$1"
    local volume_name="$2"
    local snapshot_info="$3"
    
    if [ -z "$snapshot_id" ]; then
        log_error "快照ID不能为空" "校验"
        return 1
    fi
    
    local display_name="${volume_name:+卷[$volume_name] }快照"
    if [ -n "$snapshot_info" ]; then
        display_name="$display_name: $snapshot_info"
    else
        display_name="$display_name: $snapshot_id"
    fi
    
    log_info "检查$display_name" "校验"
    
    if /bin/kopia snapshot verify "$snapshot_id" >/dev/null 2>&1; then
        log_success "${display_name}完整性正常" "校验"
        return 0
    else
        log_warn "${display_name}完整性失败" "校验"
        return 1
    fi
}

# 删除快照
delete_snapshot() {
    local snapshot_id="$1"
    local volume_name="$2"
    local snapshot_info="$3"
    
    if [ -z "$snapshot_id" ]; then
        log_error "快照ID不能为空" "删除"
        return 1
    fi
    
    local display_name="${volume_name:+卷[$volume_name] }快照"
    if [ -n "$snapshot_info" ]; then
        display_name="$display_name: $snapshot_info"
    else
        display_name="$display_name: $snapshot_id"
    fi
    
    log_warn "删除$display_name" "删除"
    
    if /bin/kopia snapshot delete "$snapshot_id" --delete >/dev/null 2>&1; then
        log_success "${display_name}删除成功" "删除"
        return 0
    else
        log_error "${display_name}删除失败" "删除"
        return 1
    fi
}

# 恢复快照到指定路径 - 带进度显示
restore_snapshot_with_progress() {
    local snapshot_id="$1"
    local target_path="$2"
    local volume_name="$3"

    if [ -z "$snapshot_id" ] || [ -z "$target_path" ]; then
        log_error "快照ID和目标路径不能为空" "恢复"
        return 1
    fi

    # 确保目标目录存在
    ensure_directory "$(dirname "$target_path")"

    local display_name="${volume_name:+卷[$volume_name] }快照恢复"
    log_info "开始$display_name到: $target_path" "恢复"
    local start_time=$(date +%s)

    # 显示恢复状态
    printf "${CYAN}正在恢复快照...${NC}\n"
    printf "${CYAN}快照ID: %s${NC}\n" "$snapshot_id"
    printf "${CYAN}目标路径: %s${NC}\n" "$target_path"
    printf "${CYAN}开始时间: %s${NC}\n" "$(date '+%H:%M:%S')"
    echo

    # 执行恢复并显示进度
    local temp_log="/tmp/kopia_restore_$$.log"
    if /bin/kopia snapshot restore "$snapshot_id" "$target_path" 2>&1 | tee "$temp_log" | while IFS= read -r line; do
        # 解析恢复输出，显示进度
        if echo "$line" | grep -q "Restored\|Processing\|files"; then
            printf "\r${CYAN}状态: %s${NC}" "$line"
        elif echo "$line" | grep -q "Restore completed"; then
            echo
            printf "${GREEN}✓ %s${NC}\n" "$line"
        fi
    done; then
        local end_time=$(date +%s)
        local duration=$(calculate_duration "$start_time" "$end_time")
        echo
        log_success "${display_name}成功 耗时$(format_duration $duration)" "恢复"

        # 清理临时日志
        rm -f "$temp_log"
        return 0
    else
        echo
        log_error "${display_name}失败" "恢复"

        # 显示错误详情
        if [ -f "$temp_log" ]; then
            log_error "错误详情:" "恢复"
            tail -5 "$temp_log" | while IFS= read -r line; do
                printf "  ${RED}%s${NC}\n" "$line"
            done
            rm -f "$temp_log"
        fi
        return 1
    fi
}

# 获取repository状态信息
get_repository_status() {
    log_info "获取repository状态" "状态"
    /bin/kopia repository status
}

# 检查快照是否存在
snapshot_exists() {
    local snapshot_id="$1"
    
    if [ -z "$snapshot_id" ]; then
        return 1
    fi
    
    /bin/kopia snapshot list --json 2>/dev/null | grep -q "\"id\":\"$snapshot_id\"" 
}

# 获取最新快照ID
get_latest_snapshot_id() {
    local volume="$1"
    
    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "快照"
        return 1
    fi
    
    local latest_id
    latest_id=$(/bin/kopia snapshot list "$VOLUMES_DIR/$volume" --json --all 2>/dev/null | \
        grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -n "$latest_id" ]; then
        echo "$latest_id"
        return 0
    else
        log_warn "卷[$volume]未找到快照" "快照"
        return 1
    fi
}
