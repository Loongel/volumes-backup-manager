#!/bin/bash

# 备份操作模块
# 提供备份、恢复、清空等核心操作功能

# 依赖库
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/kopia-ops.sh"
source "$(dirname "${BASH_SOURCE[0]}")/interactive.sh"

# 手动备份操作 - 直接交互模式
perform_manual_backup() {
    local volume="$1"

    log_info "开始手动备份操作" "备份"

    # 如果已经指定了卷，直接执行
    if [ -n "$volume" ]; then
        if ui_confirm_operation "确认开始备份卷 [$volume]?" "确认备份"; then
            execute_backup "$volume"
            return $?
        else
            return 1
        fi
    fi

    # 选择卷
    local selected_volume
    selected_volume=$(ui_select_volume)
    local exit_code=$?

    # 处理不同的退出情况
    case $exit_code in
        0)
            # 用户正常选择，继续处理
            ;;
        1)
            # 用户点击Cancel按钮，静默返回
            return 1
            ;;
        255)
            # 用户按ESC键，静默返回
            return 255
            ;;
        *)
            # 其他错误
            return $exit_code
            ;;
    esac

    # 确认并执行备份
    if ui_confirm_operation "确认开始备份卷 [$selected_volume]?" "确认备份"; then
        execute_backup "$selected_volume"
        return $?
    else
        return 1
    fi
}

# 备份步骤1：选择卷
backup_select_volume() {
    ui_select_volume
}

# 备份步骤2：确认并执行
backup_confirm_and_execute() {
    local volume="$1"

    if ui_confirm_operation "确认开始备份卷 [$volume]?" "确认备份"; then
        execute_backup "$volume"
        return $?
    else
        return 1  # 返回上一步
    fi
}

# 显示操作进度
show_operation_progress() {
    local operation="$1"
    local target="$2"
    local start_time="$3"

    log_info "开始${operation}: ${target}" "${operation}"
    log_info "开始时间: $(date '+%H:%M:%S')" "${operation}"
}

# 显示操作完成状态
show_operation_complete() {
    local operation="$1"
    local target="$2"
    local start_time="$3"
    local success="$4"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ "$success" = "true" ]; then
        log_success "${operation}完成: ${target} 耗时${duration}s" "${operation}"
    else
        log_error "${operation}失败: ${target} 耗时${duration}s" "${operation}"
    fi
}

# 执行备份的核心函数
execute_backup() {
    local volume="$1"

    local start_time=$(date +%s)
    show_operation_progress "备份" "$volume" "$start_time"

    local description="Manual backup of $volume"
    local tags="volume:$volume,manual:true"

    if create_snapshot_with_progress "$volume" "$description" "$tags"; then
        show_operation_complete "备份" "$volume" "$start_time" "true"
        return 0
    else
        show_operation_complete "备份" "$volume" "$start_time" "false"
        return 2  # 致命错误
    fi
}

# 手动恢复操作 - 直接交互模式
perform_manual_restore() {
    local volume="$1"
    local snapshot_id="$2"
    local target_path="$3"

    log_info "开始手动恢复操作" "恢复"

    # 如果所有参数都已指定，直接执行
    if [ -n "$volume" ] && [ -n "$snapshot_id" ] && [ -n "$target_path" ]; then
        execute_restore "$volume" "$snapshot_id" "$target_path"
        return $?
    fi

    # 步骤1：选择卷
    if [ -z "$volume" ]; then
        volume=$(ui_select_volume)
        local exit_code=$?

        # 处理不同的退出情况
        case $exit_code in
            0)
                # 用户正常选择，继续处理
                ;;
            1|255)
                # 用户取消操作（Cancel按钮或ESC键），静默返回
                return $exit_code
                ;;
            *)
                # 其他错误
                return $exit_code
                ;;
        esac
    fi

    # 步骤2：选择快照
    if [ -z "$snapshot_id" ]; then
        snapshot_id=$(ui_select_snapshot "$volume" true)
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            return $exit_code
        fi
    fi

    # 步骤3：选择目标路径
    if [ -z "$target_path" ]; then
        target_path=$(ui_select_target_path "$volume")
        local exit_code=$?
        if [ $exit_code -ne 0 ]; then
            return $exit_code
        fi
    fi

    # 步骤4：确认并执行
    restore_confirm_and_execute "$volume" "$snapshot_id" "$target_path"
    return $?
}

# 恢复步骤1：选择卷
restore_select_volume() {
    ui_select_volume
}

# 恢复步骤2：选择快照
restore_select_snapshot() {
    local volume="$1"
    ui_select_snapshot "$volume" true
}

# 恢复步骤3：选择目标路径
restore_select_path() {
    local volume="$1"
    local snapshot_id="$2"
    ui_select_target_path "$volume"
}

# 恢复步骤4：确认并执行
restore_confirm_and_execute() {
    local volume="$1"
    local snapshot_id="$2"
    local target_path="$3"

    # 显示恢复信息
    echo
    highlight "恢复操作确认"
    printf "${CYAN}源卷: %s${NC}\n" "$volume"
    printf "${CYAN}快照ID: %s${NC}\n" "$snapshot_id"
    printf "${CYAN}目标路径: %s${NC}\n" "$target_path"
    echo

    # 检查是否为危险操作
    local is_destructive=false
    if [ "$target_path" = "$VOLUMES_DIR/$volume" ]; then
        is_destructive=true
        danger "⚠️  警告: 此操作将替换卷中的所有现有数据！"
        danger "⚠️  当前数据将被备份到临时位置"
        echo
    fi

    # 确认操作
    if [ "$is_destructive" = "true" ]; then
        if ui_confirm_dangerous "恢复快照并替换所有数据" "$volume" "$volume"; then
            # 先备份当前数据
            if ! backup_current_data "$volume"; then
                log_error "备份当前数据失败，恢复操作取消" "恢复"
                return 2
            fi
        else
            return 1  # 返回上一步
        fi
    else
        if ! ui_confirm_operation "确认开始恢复操作?" "确认恢复"; then
            return 1  # 返回上一步
        fi
    fi

    # 执行恢复
    execute_restore "$volume" "$snapshot_id" "$target_path"
    return $?
}

# 执行恢复的核心函数
execute_restore() {
    local volume="$1"
    local snapshot_id="$2"
    local target_path="$3"

    local start_time=$(date +%s)
    show_operation_progress "恢复" "$target_path" "$start_time"

    if restore_snapshot_with_progress "$snapshot_id" "$target_path" "$volume"; then
        show_operation_complete "恢复" "$target_path" "$start_time" "true"
        return 0
    else
        show_operation_complete "恢复" "$target_path" "$start_time" "false"
        return 2  # 致命错误
    fi
}

# 检查备份完整性
check_backup_integrity() {
    local volume="$1"
    local check_all="${2:-false}"

    log_info "开始备份完整性检查" "完整性"

    if [ "$check_all" = "true" ]; then
        # 检查所有卷
        local volumes
        volumes=$(get_available_volumes)

        if [ $? -ne 0 ] || [ -z "$volumes" ]; then
            log_warn "未找到可用卷" "完整性"
            return 1
        fi

        local failed_count=0
        local total_count=0

        while IFS= read -r vol; do
            if [ -n "$vol" ]; then
                total_count=$((total_count + 1))
                log_info "检查卷: $vol" "完整性"

                if ! verify_volume_snapshots "$vol"; then
                    failed_count=$((failed_count + 1))
                    log_error "卷 [$vol] 完整性检查失败" "完整性"
                fi
            fi
        done <<< "$volumes"

        if [ $failed_count -eq 0 ]; then
            log_success "所有 $total_count 个卷的备份完整性检查通过" "完整性"
            return 0
        else
            log_error "$failed_count/$total_count 个卷的备份完整性检查失败" "完整性"
            return 1
        fi
    else
        # 检查单个卷
        if [ -z "$volume" ]; then
            log_error "卷名不能为空" "完整性"
            return 2
        fi

        log_info "检查卷: $volume" "完整性"
        if verify_volume_snapshots "$volume"; then
            log_success "卷 [$volume] 备份完整性检查通过" "完整性"
            return 0
        else
            log_error "卷 [$volume] 备份完整性检查失败" "完整性"
            return 1
        fi
    fi
}

# 验证单个快照
verify_single_snapshot() {
    local snapshot_id="$1"
    local volume="$2"
    local context="${3:-验证}"

    if [ -z "$snapshot_id" ]; then
        log_error "快照ID不能为空" "$context"
        return 1
    fi

    # 验证快照完整性
    if /bin/kopia snapshot verify "$snapshot_id" >/dev/null 2>&1; then
        log_info "快照 [${snapshot_id:0:8}] 验证通过" "$context"
        return 0
    else
        log_warn "快照 [${snapshot_id:0:8}] 验证失败" "$context"
        return 1
    fi
}

# 验证卷的快照完整性 - 高性能版本：从最新快照开始，找到第一个通过的快照
verify_volume_snapshots() {
    local volume="$1"

    # 一次性获取所有快照ID（高性能，按时间降序，最新在前）
    local snapshot_ids
    snapshot_ids=$(/bin/kopia snapshot list "$VOLUMES_DIR/$volume" --json 2>/dev/null | \
        grep -o '"id":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$snapshot_ids" ]; then
        log_warn "卷 [$volume] 没有快照" "完整性"
        return 0  # 没有快照不算错误
    fi

    local failed_snapshots=()
    local total_count=0
    local found_good_snapshot=false

    # 直接遍历快照ID，从最新开始验证（最高性能）
    while IFS= read -r snapshot_id; do
        if [ -n "$snapshot_id" ]; then
            total_count=$((total_count + 1))

            if verify_single_snapshot "$snapshot_id" "$volume" "完整性"; then
                # 找到第一个通过的快照，停止检查
                found_good_snapshot=true
                log_info "卷 [$volume] 找到有效快照: [${snapshot_id:0:8}]" "完整性"
                break
            else
                # 记录失败的快照
                failed_snapshots+=("$snapshot_id")
            fi
        fi
    done <<< "$snapshot_ids"

    # 输出结果
    local failed_count=${#failed_snapshots[@]}
    if [ $total_count -eq 0 ]; then
        log_warn "卷 [$volume] 没有快照可验证" "完整性"
        return 0
    elif [ "$found_good_snapshot" = true ]; then
        if [ $failed_count -eq 0 ]; then
            log_info "卷 [$volume] 最新快照验证通过" "完整性"
        else
            log_warn "卷 [$volume] 有 $failed_count 个损坏快照需要清理" "完整性"
        fi
        return 0
    else
        log_error "卷 [$volume] 所有 $total_count 个快照都验证失败" "完整性"
        return 1
    fi
}

# 清理损坏的快照 - 正确逻辑：基于完整性检查，删除验证失败的快照
cleanup_corrupted_snapshots() {
    log_info "开始清理损坏的快照" "清理"

    # 获取所有可用卷
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        log_warn "未找到可用卷" "清理"
        return 1
    fi

    local total_corrupted=0
    local total_checked=0

    # 逐个检查每个卷的快照
    while IFS= read -r volume; do
        if [ -n "$volume" ]; then
            log_info "检查卷 [$volume] 的快照..." "清理"

            # 一次性获取所有快照ID（高性能，按时间降序，最新在前）
            # 使用--all参数确保获取所有快照，包括相同内容的快照
            local snapshot_ids
            snapshot_ids=$(/bin/kopia snapshot list "$VOLUMES_DIR/$volume" --json --all 2>/dev/null | \
                grep -o '"id":"[^"]*"' | cut -d'"' -f4)

            if [ -z "$snapshot_ids" ]; then
                log_info "卷 [$volume] 没有快照" "清理"
                continue
            fi

            # 从最新快照开始验证，找到第一个通过的快照，删除之前的损坏快照
            local found_good_snapshot=false
            local corrupted_snapshots=()

            while IFS= read -r snapshot_id; do
                if [ -n "$snapshot_id" ]; then
                    total_checked=$((total_checked + 1))

                    if verify_single_snapshot "$snapshot_id" "$volume" "清理"; then
                        # 找到第一个通过的快照，停止检查
                        found_good_snapshot=true
                        log_info "卷 [$volume] 找到有效快照: [${snapshot_id:0:8}]，停止检查" "清理"
                        break
                    else
                        # 记录损坏的快照
                        corrupted_snapshots+=("$snapshot_id")
                    fi
                fi
            done <<< "$snapshot_ids"

            # 删除损坏的快照
            for snapshot_id in "${corrupted_snapshots[@]}"; do
                log_warn "删除损坏快照: [${snapshot_id:0:8}] 卷[$volume]" "清理"

                if /bin/kopia snapshot delete "$snapshot_id" --delete >/dev/null 2>&1; then
                    total_corrupted=$((total_corrupted + 1))
                    log_info "成功删除损坏快照: [${snapshot_id:0:8}]" "清理"
                else
                    log_error "删除损坏快照失败: [${snapshot_id:0:8}]" "清理"
                fi
            done

            if [ "$found_good_snapshot" = false ] && [ ${#corrupted_snapshots[@]} -gt 0 ]; then
                log_error "卷 [$volume] 所有快照都损坏" "清理"
            fi
        fi
    done <<< "$volumes"

    # 运行repository维护清理
    log_info "运行repository维护清理..." "清理"
    if /bin/kopia maintenance run --full >/dev/null 2>&1; then
        log_success "Repository维护清理完成" "清理"
    else
        log_warn "Repository维护清理可能有问题" "清理"
    fi

    # 输出清理结果
    if [ $total_corrupted -eq 0 ]; then
        log_success "检查了 $total_checked 个快照，未发现损坏快照" "清理"
        return 0
    else
        log_success "检查了 $total_checked 个快照，清理了 $total_corrupted 个损坏快照" "清理"
        return 0
    fi
}

# 清空卷数据 - 删除NFS卷中的文件
flush_volume_data() {
    log_info "开始清空卷数据操作" "清空"

    # 选择要清空的卷
    local selected_volume
    selected_volume=$(ui_select_volume)
    local exit_code=$?

    # 处理不同的退出情况
    case $exit_code in
        0)
            # 用户正常选择，继续处理
            ;;
        1|255)
            # 用户取消操作（Cancel按钮或ESC键），静默返回
            return $exit_code
            ;;
        *)
            # 其他错误
            return $exit_code
            ;;
    esac

    # 多重确认
    if ! ui_confirm_dangerous "⚠️ 危险操作确认" \
        "您即将删除卷 [$selected_volume] 中的所有数据！\n\n此操作不可恢复！\n\n确定要继续吗？"; then
        log_info "用户取消清空卷数据操作" "清空"
        return 1
    fi

    # 第二次确认 - 需要手动输入卷名
    if ! ui_confirm_dangerous "删除卷数据" "卷 [$selected_volume] 的所有数据" "$selected_volume"; then
        log_info "用户取消清空卷数据操作" "清空"
        return 1
    fi

    # 执行清空
    local volume_path="$VOLUMES_DIR/$selected_volume"

    if [ ! -d "$volume_path" ]; then
        log_error "卷目录不存在: $volume_path" "清空"
        return 2
    fi

    log_warn "开始清空卷数据: $selected_volume" "清空"

    # 使用应急备份目录，避免干扰卷识别
    local backup_base="$VOLUMES_DIR/.backups"
    local backup_dir="$backup_base/$selected_volume.deleted.$(date +%Y%m%d_%H%M%S)"

    # 确保备份目录存在
    mkdir -p "$backup_base"

    # 移动数据到应急备份目录而不是直接删除
    if mv "$volume_path" "$backup_dir"; then
        # 重新创建空目录
        mkdir -p "$volume_path"
        log_success "卷数据已清空: $selected_volume" "清空"
        log_info "原数据已备份到: $backup_dir" "清空"
        log_info "如需恢复，请手动移动文件" "清空"
        return 0
    else
        log_error "清空卷数据失败: $selected_volume" "清空"
        return 2
    fi
}

# 清空卷备份 - 删除备份快照
flush_volume_backups() {
    log_info "开始清空卷备份操作" "清空"

    # 选择要清空备份的卷
    local selected_volume
    selected_volume=$(ui_select_volume)
    local exit_code=$?

    # 处理不同的退出情况
    case $exit_code in
        0)
            # 用户正常选择，继续处理
            ;;
        1|255)
            # 用户取消操作（Cancel按钮或ESC键），静默返回
            return $exit_code
            ;;
        *)
            # 其他错误
            return $exit_code
            ;;
    esac

    # 第一重确认 - 危险操作警告
    if ! ui_confirm_dangerous "⚠️ 危险操作确认" \
        "您即将删除卷 [$selected_volume] 的所有备份快照！\n\n此操作将永久删除该卷的备份历史！\n虽然会先备份到应急目录，但仍然存在风险！\n\n确定要继续吗？"; then
        log_info "用户取消清空备份操作" "清空"
        return 1
    fi

    # 获取卷的快照
    local snapshots
    snapshots=$(get_volume_snapshots "$selected_volume")

    if [ $? -ne 0 ] || [ -z "$snapshots" ]; then
        log_info "卷 [$selected_volume] 没有备份快照" "清空"
        return 0
    fi

    # 显示快照信息
    local snapshot_count
    snapshot_count=$(echo "$snapshots" | wc -l)

    # 第二重确认 - 需要手动输入卷名
    if ! ui_confirm_dangerous "删除备份快照" "卷 [$selected_volume] 的所有 $snapshot_count 个备份快照" "$selected_volume"; then
        log_info "用户取消清空备份操作" "清空"
        return 1
    fi

    # 调用内部函数执行备份和删除
    _flush_volume_backups_internal "$selected_volume"
    local result=$?

    # 返回内部函数的结果
    return $result


}

# 清空所有数据 - 卷数据 + 备份快照
flush_all_data() {
    log_info "开始清空所有数据操作" "清空"

    # 选择要清空的卷
    local selected_volume
    selected_volume=$(ui_select_volume)
    local exit_code=$?

    # 处理不同的退出情况
    case $exit_code in
        0)
            # 用户正常选择，继续处理
            ;;
        1|255)
            # 用户取消操作（Cancel按钮或ESC键），静默返回
            return $exit_code
            ;;
        *)
            # 其他错误
            return $exit_code
            ;;
    esac

    # 最严格的确认
    if ! ui_confirm_dangerous "⚠️ 极度危险操作确认" \
        "您即将删除卷 [$selected_volume] 的：\n• 所有卷数据文件\n• 所有备份快照\n\n这将完全清空该卷的所有内容！\n此操作不可恢复！\n\n确定要继续吗？"; then
        log_info "用户取消清空所有数据操作" "清空"
        return 1
    fi

    # 第二次确认 - 需要手动输入 'DELETE ALL'
    if ! ui_confirm_dangerous "完全清空卷" "卷 [$selected_volume] 的所有数据和备份" "DELETE ALL"; then
        log_info "用户取消清空所有数据操作" "清空"
        return 1
    fi

    log_warn "开始执行完全清空操作: $selected_volume" "清空"

    # 第1步：备份并删除快照 - 调用内部函数
    log_info "第1步: 备份并删除快照..." "清空"
    _flush_volume_backups_internal "$selected_volume"

    # 第2步：备份并删除卷数据 - 调用内部函数
    log_info "第2步: 备份并删除卷数据..." "清空"
    _flush_volume_data_internal "$selected_volume"

    log_success "完全清空操作完成: $selected_volume" "清空"
    return 0
}

# ============================================================================
# 新的Flush函数 - 支持指定卷的操作
# ============================================================================

# 清空指定卷的数据（无UI交互）
flush_volume_data_for_volume() {
    local volume="$1"

    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "清空"
        return 2
    fi

    log_info "开始清空卷数据操作: $volume" "清空"

    # 多重确认
    if ! ui_confirm_dangerous "⚠️ 危险操作确认" \
        "您即将删除卷 [$volume] 中的所有数据！\n\n此操作不可恢复！\n\n确定要继续吗？"; then
        log_info "用户取消清空卷数据操作" "清空"
        return 1
    fi

    # 第二次确认 - 需要手动输入卷名
    if ! ui_confirm_dangerous "删除卷数据" "卷 [$volume] 的所有数据" "$volume"; then
        log_info "用户取消清空卷数据操作" "清空"
        return 1
    fi

    # 调用内部函数执行
    _flush_volume_data_internal "$volume"
    return $?
}

# 清空指定卷的备份（无UI交互）
flush_volume_backups_for_volume() {
    local volume="$1"

    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "清空"
        return 2
    fi

    log_info "开始清空卷备份操作: $volume" "清空"

    # 第一重确认 - 危险操作警告
    if ! ui_confirm_dangerous "⚠️ 危险操作确认" \
        "您即将删除卷 [$volume] 的所有备份快照！\n\n此操作将永久删除该卷的备份历史！\n虽然会先备份到应急目录，但仍然存在风险！\n\n确定要继续吗？"; then
        log_info "用户取消清空备份操作" "清空"
        return 1
    fi

    # 获取卷的快照
    local snapshots
    snapshots=$(get_volume_snapshots "$volume")

    if [ $? -ne 0 ] || [ -z "$snapshots" ]; then
        log_info "卷 [$volume] 没有备份快照" "清空"
        return 0
    fi

    # 显示快照信息
    local snapshot_count
    snapshot_count=$(echo "$snapshots" | wc -l)

    # 第二重确认 - 需要手动输入卷名
    if ! ui_confirm_dangerous "删除备份快照" "卷 [$volume] 的所有 $snapshot_count 个备份快照" "$volume"; then
        log_info "用户取消清空备份操作" "清空"
        return 1
    fi

    # 调用内部函数执行备份和删除
    _flush_volume_backups_internal "$volume"
    return $?
}

# 清空指定卷的所有数据（无UI交互）
flush_all_data_for_volume() {
    local volume="$1"

    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "清空"
        return 2
    fi

    log_info "开始清空所有数据操作: $volume" "清空"

    # 最严格的确认
    if ! ui_confirm_dangerous "⚠️ 极度危险操作确认" \
        "您即将删除卷 [$volume] 的：\n• 所有卷数据文件\n• 所有备份快照\n\n这将完全清空该卷的所有内容！\n此操作不可恢复！\n\n确定要继续吗？"; then
        log_info "用户取消清空所有数据操作" "清空"
        return 1
    fi

    # 第二次确认 - 需要手动输入 'DELETE ALL'
    if ! ui_confirm_dangerous "完全清空卷" "卷 [$volume] 的所有数据和备份" "DELETE ALL"; then
        log_info "用户取消清空所有数据操作" "清空"
        return 1
    fi

    log_warn "开始执行完全清空操作: $volume" "清空"

    # 第1步：备份并删除快照 - 调用内部函数
    log_info "第1步: 备份并删除快照..." "清空"
    _flush_volume_backups_internal "$volume"

    # 第2步：备份并删除卷数据 - 调用内部函数
    log_info "第2步: 备份并删除卷数据..." "清空"
    _flush_volume_data_internal "$volume"

    log_success "完全清空操作完成: $volume" "清空"
    return 0
}

# ============================================================================
# 处理所有卷的Flush函数
# ============================================================================

# 清空所有卷的数据
flush_all_volumes_data() {
    log_info "开始清空所有卷的数据操作" "清空"

    # 获取所有可用卷
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        log_error "未找到可用卷" "清空"
        return 2
    fi

    local volume_count
    volume_count=$(echo "$volumes" | wc -l)

    # 极度危险的确认
    if ! ui_confirm_dangerous "⚠️ 极度危险操作确认" \
        "您即将删除所有 $volume_count 个卷的数据文件！\n\n这将清空所有卷的内容！\n此操作不可恢复！\n\n确定要继续吗？"; then
        log_info "用户取消清空所有卷数据操作" "清空"
        return 1
    fi

    # 第二次确认 - 需要手动输入 'DELETE ALL VOLUMES'
    if ! ui_confirm_dangerous "删除所有卷数据" "所有 $volume_count 个卷的数据文件" "DELETE ALL VOLUMES"; then
        log_info "用户取消清空所有卷数据操作" "清空"
        return 1
    fi

    local success_count=0
    local failed_count=0

    # 逐个处理每个卷
    while IFS= read -r volume; do
        if [ -n "$volume" ]; then
            log_info "处理卷: $volume" "清空"
            if _flush_volume_data_internal "$volume"; then
                success_count=$((success_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
        fi
    done <<< "$volumes"

    if [ $failed_count -eq 0 ]; then
        log_success "成功清空所有 $success_count 个卷的数据" "清空"
        return 0
    else
        log_warn "清空完成，成功: $success_count 个，失败: $failed_count 个" "清空"
        return 1
    fi
}

# 清空所有卷的备份
flush_all_volumes_backups() {
    log_info "开始清空所有卷的备份操作" "清空"

    # 获取所有可用卷
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        log_error "未找到可用卷" "清空"
        return 2
    fi

    local volume_count
    volume_count=$(echo "$volumes" | wc -l)

    # 极度危险的确认
    if ! ui_confirm_dangerous "⚠️ 极度危险操作确认" \
        "您即将删除所有 $volume_count 个卷的备份快照！\n\n这将删除所有卷的备份历史！\n虽然会先备份到应急目录，但仍然存在风险！\n\n确定要继续吗？"; then
        log_info "用户取消清空所有卷备份操作" "清空"
        return 1
    fi

    # 第二次确认 - 需要手动输入 'DELETE ALL BACKUPS'
    if ! ui_confirm_dangerous "删除所有卷备份" "所有 $volume_count 个卷的备份快照" "DELETE ALL BACKUPS"; then
        log_info "用户取消清空所有卷备份操作" "清空"
        return 1
    fi

    local success_count=0
    local failed_count=0

    # 逐个处理每个卷
    while IFS= read -r volume; do
        if [ -n "$volume" ]; then
            log_info "处理卷: $volume" "清空"
            if _flush_volume_backups_internal "$volume"; then
                success_count=$((success_count + 1))
            else
                failed_count=$((failed_count + 1))
            fi
        fi
    done <<< "$volumes"

    if [ $failed_count -eq 0 ]; then
        log_success "成功清空所有 $success_count 个卷的备份" "清空"
        return 0
    else
        log_warn "清空完成，成功: $success_count 个，失败: $failed_count 个" "清空"
        return 1
    fi
}

# 清空所有卷的所有数据
flush_all_volumes_all_data() {
    log_info "开始清空所有卷的所有数据操作" "清空"

    # 获取所有可用卷
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        log_error "未找到可用卷" "清空"
        return 2
    fi

    local volume_count
    volume_count=$(echo "$volumes" | wc -l)

    # 最极度危险的确认
    if ! ui_confirm_dangerous "⚠️ 最极度危险操作确认" \
        "您即将删除所有 $volume_count 个卷的：\n• 所有卷数据文件\n• 所有备份快照\n\n这将完全清空整个系统的所有内容！\n此操作不可恢复！\n\n确定要继续吗？"; then
        log_info "用户取消清空所有数据操作" "清空"
        return 1
    fi

    # 第二次确认 - 需要手动输入 'DELETE EVERYTHING'
    if ! ui_confirm_dangerous "完全清空系统" "所有 $volume_count 个卷的所有数据和备份" "DELETE EVERYTHING"; then
        log_info "用户取消清空所有数据操作" "清空"
        return 1
    fi

    log_warn "开始执行完全清空所有卷操作" "清空"

    local success_count=0
    local failed_count=0

    # 逐个处理每个卷
    while IFS= read -r volume; do
        if [ -n "$volume" ]; then
            log_info "完全清空卷: $volume" "清空"

            # 先清空备份，再清空数据
            log_info "第1步: 清空卷 [$volume] 的备份..." "清空"
            _flush_volume_backups_internal "$volume"

            log_info "第2步: 清空卷 [$volume] 的数据..." "清空"
            if _flush_volume_data_internal "$volume"; then
                success_count=$((success_count + 1))
                log_success "卷 [$volume] 完全清空完成" "清空"
            else
                failed_count=$((failed_count + 1))
                log_error "卷 [$volume] 清空失败" "清空"
            fi
        fi
    done <<< "$volumes"

    if [ $failed_count -eq 0 ]; then
        log_success "成功完全清空所有 $success_count 个卷" "清空"
        return 0
    else
        log_warn "清空完成，成功: $success_count 个，失败: $failed_count 个" "清空"
        return 1
    fi
}

# 内部函数：备份并删除快照（无UI交互）
_flush_volume_backups_internal() {
    local volume="$1"

    # 创建应急备份目录
    local backup_base="$VOLUMES_DIR/.backups"
    local snapshot_backup_dir="$backup_base/snapshots_$volume.deleted.$(date +%Y%m%d_%H%M%S)"

    # 确保备份目录存在
    mkdir -p "$snapshot_backup_dir"

    log_info "备份快照到应急目录: $snapshot_backup_dir" "清空"

    # 获取所有快照信息（0表示获取所有快照，不限制数量）
    local snapshots
    snapshots=$(get_volume_snapshots "$volume" 0)

    if [ $? -ne 0 ] || [ -z "$snapshots" ]; then
        log_info "卷 [$volume] 没有备份快照" "清空"
        return 0
    fi

    # 预先获取所有快照ID（一次性调用，提高效率和准确性）
    # 使用--all参数确保获取所有快照，包括相同内容的快照
    local snapshot_ids
    snapshot_ids=$(/bin/kopia snapshot list "$VOLUMES_DIR/$volume" --json --all 2>/dev/null | \
        grep -o '"id":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$snapshot_ids" ]; then
        log_info "卷 [$volume] 没有备份快照" "清空"
        return 0
    fi

    local backup_count=0
    local deleted_count=0
    local failed_count=0

    # 逐个处理快照ID
    while IFS= read -r snapshot_id; do
        if [ -n "$snapshot_id" ]; then
            # 第1步：备份快照到应急目录
            local snapshot_backup_path="$snapshot_backup_dir/snapshot_${snapshot_id:0:8}"

            if /bin/kopia snapshot restore "$snapshot_id" "$snapshot_backup_path" >/dev/null 2>&1; then
                backup_count=$((backup_count + 1))

                # 第2步：删除原快照
                if /bin/kopia snapshot delete "$snapshot_id" --delete >/dev/null 2>&1; then
                    deleted_count=$((deleted_count + 1))
                else
                    failed_count=$((failed_count + 1))
                    log_warn "删除快照失败: $snapshot_id" "清空"
                fi
            else
                failed_count=$((failed_count + 1))
                log_warn "备份快照失败: $snapshot_id" "清空"
            fi
        fi
    done <<< "$snapshot_ids"

    if [ $failed_count -eq 0 ]; then
        log_success "已备份并删除卷 [$volume] 的所有 $deleted_count 个快照" "清空"
        log_info "快照备份保存在: $snapshot_backup_dir" "清空"
        return 0
    else
        log_warn "快照处理完成，但有 $failed_count 个快照处理失败" "清空"
        log_info "成功备份: $backup_count 个，成功删除: $deleted_count 个" "清空"
        return 1
    fi
}

# 内部函数：备份并删除卷数据（无UI交互）
_flush_volume_data_internal() {
    local volume="$1"
    local volume_path="$VOLUMES_DIR/$volume"

    if [ ! -d "$volume_path" ]; then
        log_warn "卷目录不存在: $volume_path" "清空"
        return 0
    fi

    # 使用应急备份目录，避免干扰卷识别
    local backup_base="$VOLUMES_DIR/.backups"
    local backup_dir="$backup_base/$volume.deleted.$(date +%Y%m%d_%H%M%S)"

    # 确保备份目录存在
    mkdir -p "$backup_base"

    # 移动数据到应急备份目录而不是直接删除
    if mv "$volume_path" "$backup_dir"; then
        # 重新创建空目录
        mkdir -p "$volume_path"
        log_success "卷数据已清空: $volume" "清空"
        log_info "原数据已备份到: $backup_dir" "清空"
        return 0
    else
        log_error "清空卷数据失败: $volume" "清空"
        return 2
    fi
}

# 备份当前数据 - 恢复前保护
backup_current_data() {
    local volume="$1"
    
    if [ -z "$volume" ]; then
        log_error "卷名不能为空" "备份"
        return 1
    fi
    
    local volume_path="$VOLUMES_DIR/$volume"
    if [ ! -d "$volume_path" ]; then
        log_warn "卷目录不存在，跳过备份: $volume_path" "备份"
        return 0
    fi
    
    # 检查目录是否为空
    if [ -z "$(ls -A "$volume_path" 2>/dev/null)" ]; then
        log_info "卷为空，跳过备份: $volume" "备份"
        return 0
    fi
    
    log_info "备份当前数据: 卷[$volume]" "备份"
    
    local backup_description="Pre-restore backup of $volume"
    local backup_tags="volume:$volume,pre-restore:true,auto:true"
    
    if create_snapshot_with_progress "$volume" "$backup_description" "$backup_tags"; then
        log_success "当前数据备份完成: 卷[$volume]" "备份"
        return 0
    else
        log_error "当前数据备份失败: 卷[$volume]" "备份"
        return 1
    fi
}





# 检查单个卷的最新快照
check_volume_latest_snapshot() {
    local volume="$1"
    
    log_info "检查卷[$volume]的最新快照..." "校验"
    
    # 获取最新快照ID
    local latest_snapshot_id
    latest_snapshot_id=$(get_latest_snapshot_id "$volume")
    
    if [ $? -ne 0 ] || [ -z "$latest_snapshot_id" ]; then
        log_warn "卷[$volume]未找到快照" "校验"
        return 1
    fi
    
    # 获取快照显示信息
    local snapshot_info
    snapshot_info=$(get_volume_snapshots "$volume" 1 | head -1)
    local snapshot_date
    snapshot_date=$(echo "$snapshot_info" | awk '{print $1, $2}')
    
    # 验证快照完整性
    if verify_snapshot "$latest_snapshot_id" "$volume" "$snapshot_date"; then
        return 0
    else
        return 1
    fi
}




