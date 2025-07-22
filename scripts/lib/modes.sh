#!/bin/bash

# 模式控制模块
# 提供手动模式和自动模式的主要逻辑

# 依赖库
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"
source "$(dirname "${BASH_SOURCE[0]}")/kopia-ops.sh"
source "$(dirname "${BASH_SOURCE[0]}")/interactive.sh"
source "$(dirname "${BASH_SOURCE[0]}")/backup-operations.sh"

# 显示主菜单 - 修复交互问题，支持ESC和数字键
show_main_menu() {
    if command -v whiptail >/dev/null 2>&1; then
        # 构建标题和提示信息
        local title="NFS Backup Manager (手动模式)"
        local prompt="选择操作:\n\n⌨️  ESC键: 退出管理UI"

        # 使用统一的ui_menu函数
        local choice
        choice=$(ui_menu "$title" "$prompt" 18 70 8 \
            "1" "列出卷和快照" \
            "2" "手动备份" \
            "3" "从备份恢复" \
            "4" "清空数据 (危险操作)" \
            "5" "检查备份完整性" \
            "6" "Repository状态" \
            "7" "清理损坏快照" \
            "0" "回到自动模式")

        local exit_status=$?

        # 返回选择和退出状态
        if [ $exit_status -ne 0 ]; then
            # 用户按了ESC或取消，返回非0退出码
            return $exit_status
        else
            echo "$choice"
            return 0
        fi
    else
        # 降级到传统菜单
        local title="NFS Backup Manager (手动模式)"

        show_screen_title "$title"

        printf "${CYAN}1)${NC} 列出卷和快照\n"
        printf "${CYAN}2)${NC} 手动备份\n"
        printf "${CYAN}3)${NC} 从备份恢复\n"
        printf "${CYAN}4)${NC} ${RED}清空卷数据 (危险操作)${NC}\n"
        printf "${CYAN}5)${NC} 检查备份完整性\n"
        printf "${CYAN}6)${NC} Repository状态\n"
        printf "${CYAN}7)${NC} 清理损坏快照\n"
        printf "${CYAN}0)${NC} 回到自动模式\n"
        echo
        printf "${YELLOW}⌨️  ESC键: 退出管理UI${NC}\n"
        echo
        printf "请选择操作 (输入数字): "

        read -r choice
        echo "$choice"
        return 0
    fi
}


# 处理菜单选择
handle_menu_choice() {
    local choice="$1"

    log_info "处理菜单选择: $choice" "调试"

    case "$choice" in
        1)
            log_info "执行选项1: 列出卷和快照" "调试"
            list_volumes_and_snapshots
            ;;
        2)
            log_info "执行选项2: 手动备份" "调试"
            perform_manual_backup
            local backup_result=$?
            if [ $backup_result -eq 0 ]; then
                log_info "手动备份完成，等待用户按键" "调试"
                wait_for_enter
            elif [ $backup_result -eq 255 ]; then
                log_info "用户取消备份操作" "调试"
            fi
            ;;
        3)
            log_info "执行选项3: 从备份恢复" "调试"
            perform_manual_restore
            local restore_result=$?
            if [ $restore_result -eq 0 ]; then
                wait_for_enter
            elif [ $restore_result -eq 255 ]; then
                log_info "用户取消恢复操作" "调试"
            fi
            ;;
        4)
            log_info "执行选项4: 清空数据" "调试"
            flush_data_menu
            local flush_result=$?
            if [ $flush_result -eq 255 ]; then
                log_info "用户取消清空数据操作" "调试"
            fi
            ;;
        5)
            log_info "执行选项5: 检查备份完整性" "调试"
            backup_integrity_menu
            local integrity_result=$?
            if [ $integrity_result -eq 255 ]; then
                log_info "用户取消完整性检查操作" "调试"
            fi
            ;;
        6)
            log_info "执行选项6: Repository状态" "调试"
            show_repository_status
            wait_for_enter
            ;;
        7)
            log_info "执行选项7: 清理损坏快照" "调试"
            cleanup_corrupted_snapshots
            local cleanup_result=$?
            if [ $cleanup_result -eq 0 ]; then
                wait_for_enter
            elif [ $cleanup_result -eq 255 ]; then
                log_info "用户取消清理操作" "调试"
            fi
            ;;
        0)
            log_info "退出备份管理器..." "系统"
            exit 0
            ;;
        *)
            log_error "无效选项: $choice" "菜单"
            wait_for_enter "按回车键继续..."
            ;;
    esac

    log_info "菜单选择处理完成" "调试"
}

# 清空数据菜单 - 重新设计交互逻辑：先选卷，再选操作类型
flush_data_menu() {
    # 第1步：选择要操作的卷（包括"所有卷"选项）
    local selected_volume
    selected_volume=$(ui_select_volume_with_all)
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

    # 第2步：选择flush操作类型
    local flush_type
    if command -v whiptail >/dev/null 2>&1; then
        flush_type=$(ui_menu "⚠️ 清空数据选项 ⚠️" "选择要清空的数据类型 (目标: $selected_volume):" 14 70 4 \
            "1" "清空卷数据 (删除NFS卷中的文件)" \
            "2" "清空卷备份 (删除备份快照)" \
            "3" "清空所有 (卷数据 + 备份快照)" \
            "0" "返回上级菜单")
        local menu_exit_code=$?

        if [ $menu_exit_code -ne 0 ]; then
            # 用户取消，静默返回
            return $menu_exit_code
        fi
    else
        # 降级到传统菜单
        echo
        highlight "清空数据选项 (目标: $selected_volume)"
        printf "${CYAN}1)${NC} 清空卷数据 (删除NFS卷中的文件)\n"
        printf "${CYAN}2)${NC} 清空卷备份 (删除备份快照)\n"
        printf "${CYAN}3)${NC} 清空所有 (卷数据 + 备份快照)\n"
        printf "${CYAN}0)${NC} 返回\n"
        echo
        printf "请选择操作: "
        read -r flush_type
    fi

    # 第3步：执行选定的flush操作
    case "$flush_type" in
        1)
            log_info "执行清空卷数据操作: $selected_volume" "清空"
            if [ "$selected_volume" = "ALL_VOLUMES" ]; then
                flush_all_volumes_data
            else
                flush_volume_data_for_volume "$selected_volume"
            fi
            local result=$?
            if [ $result -eq 0 ]; then
                wait_for_enter
            fi
            return $result
            ;;
        2)
            log_info "执行清空卷备份操作: $selected_volume" "清空"
            if [ "$selected_volume" = "ALL_VOLUMES" ]; then
                flush_all_volumes_backups
            else
                flush_volume_backups_for_volume "$selected_volume"
            fi
            local result=$?
            if [ $result -eq 0 ]; then
                wait_for_enter
            fi
            return $result
            ;;
        3)
            log_info "执行清空所有数据操作: $selected_volume" "清空"
            if [ "$selected_volume" = "ALL_VOLUMES" ]; then
                flush_all_volumes_all_data
            else
                flush_all_data_for_volume "$selected_volume"
            fi
            local result=$?
            if [ $result -eq 0 ]; then
                wait_for_enter
            fi
            return $result
            ;;
        0)
            return 0
            ;;
        *)
            log_error "无效选项: $flush_type" "菜单"
            return 1
            ;;
    esac
}

# 列出卷和快照 - 带加载提示的表格显示
list_volumes_and_snapshots() {
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        if command -v whiptail >/dev/null 2>&1; then
            whiptail --title "错误" --msgbox "未找到可用卷" 8 40
        else
            log_error "未找到可用卷" "列表"
        fi
        return 1
    fi

    # 在一个页面内显示多级list
    show_volumes_and_snapshots_tree "$volumes"
}

# 在一个页面内显示卷和快照的树形结构
show_volumes_and_snapshots_tree() {
    local volumes="$1"

    # 显示加载提示
    whiptail --title "加载中" --infobox "正在获取所有卷和快照信息..." 6 60

    # 构建树形结构内容
    local tree_content=""
    tree_content="NFS 卷备份快照\n"
    tree_content="${tree_content}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"

    local total_volumes=0
    local total_snapshots=0

    for vol in $volumes; do
        total_volumes=$((total_volumes + 1))

        # 获取快照信息
        local snapshots
        snapshots=$(get_volume_snapshots "$vol")
        local snapshot_count=0

        if [ $? -eq 0 ] && [ -n "$snapshots" ]; then
            snapshot_count=$(echo "$snapshots" | wc -l)
        fi

        # 显示卷信息
        tree_content="${tree_content}📁 $vol ($snapshot_count 个快照)\n"

        if [ $snapshot_count -gt 0 ]; then
            local current_snapshot=0
            while IFS= read -r line; do
                if [ -n "$line" ]; then
                    local clean_line
                    clean_line=$(echo "$line" | sed 's/^[[:space:]]*//')

                    if echo "$clean_line" | grep -q "^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}"; then
                        current_snapshot=$((current_snapshot + 1))
                        total_snapshots=$((total_snapshots + 1))

                        local date_part time_part snapshot_id
                        date_part=$(echo "$clean_line" | awk '{print $1}')
                        time_part=$(echo "$clean_line" | awk '{print $2}')
                        snapshot_id=$(echo "$clean_line" | awk '{print $4}' | cut -c1-8)

                        # 树形结构符号
                        local tree_symbol="├──"
                        if [ $current_snapshot -eq $snapshot_count ]; then
                            tree_symbol="└──"
                        fi

                        # 标记最新快照
                        local status_mark=""
                        if [ $current_snapshot -eq 1 ]; then
                            status_mark=" (最新)"
                        fi

                        tree_content="${tree_content}  $tree_symbol 📸 $date_part $time_part [$snapshot_id]$status_mark\n"
                    fi
                fi
            done <<< "$snapshots"
        else
            tree_content="${tree_content}  └── (暂无快照)\n"
        fi

        tree_content="${tree_content}\n"
    done

    # 添加统计信息
    tree_content="${tree_content}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
    tree_content="${tree_content}📊 统计信息:\n"
    tree_content="${tree_content}   • 总卷数: $total_volumes 个\n"
    tree_content="${tree_content}   • 总快照数: $total_snapshots 个\n"
    tree_content="${tree_content}💡 操作提示:\n"
    tree_content="${tree_content}   • 使用方向键上下滚动查看\n"
    tree_content="${tree_content}   • 按 ESC 返回\n"

    # 使用scrolltext显示树形结构
    local temp_file=$(mktemp)
    echo -e "$tree_content" > "$temp_file"

    # 正确处理whiptail的返回值，ESC时返回主菜单而不是退出程序
    whiptail --title "NFS 卷备份快照" \
        --scrolltext \
        --textbox "$temp_file" \
        22 100 \
        --ok-button "返回" \
        --nocancel || true  # 忽略ESC的非0退出码

    rm -f "$temp_file"
}

# 备份完整性检查 - 简化为只检查所有卷
backup_integrity_menu() {
    log_info "开始检查所有卷的备份完整性" "完整性"

    # 直接执行所有卷的完整性检查
    check_backup_integrity "" true
    local result=$?

    if [ $result -eq 0 ]; then
        wait_for_enter
    elif [ $result -eq 255 ]; then
        log_info "用户取消完整性检查" "调试"
    fi

    return $result
}

# 显示Repository状态
show_repository_status() {
    show_screen_title "Kopia Repository 状态"
    
    log_info "获取repository状态信息..." "状态"
    echo
    
    get_repository_status
    
    echo
}



# 启动UI前的超时检测 - Press any key to continue
prompt_continue_or_auto_mode() {
    # 从环境变量获取超时时间，默认30秒
    local timeout_seconds="${MANUAL_MODE_TIMEOUT:-30}"

    echo
    log_info "手动模式已准备就绪" "启动"
    echo -e "${YELLOW}按任意键进入交互界面，或等待 ${timeout_seconds} 秒自动切换到自动模式...${NC}"
    echo -n "Press any key to continue ... "

    # 使用read命令的超时功能
    if read -t "$timeout_seconds" -n 1 -s; then
        echo
        log_success "用户响应，进入手动交互模式" "启动"
        return 0  # 用户按键，继续手动模式
    else
        echo
        log_info "超时 ${timeout_seconds} 秒，自动切换到自动模式" "启动"
        return 1  # 超时，切换到自动模式
    fi
}

# 手动模式主循环 - 启动UI前超时检测
run_manual_mode() {
    log_info "启动手动交互模式" "启动"

    # 初始化Kopia环境
    init_kopia_environment

    # 尝试设置仓库连接 - 借鉴compose脚本的仓库管理
    if ! setup_kopia_repository; then
        log_warn "仓库自动设置失败，请手动配置" "启动"
    fi

    if ! check_kopia_connection; then
        log_error "Kopia仓库未连接，请检查配置" "启动"
        log_error "手动模式需要有效的仓库连接才能运行" "启动"
        exit 1
    fi

    log_success "手动模式初始化完成" "启动"

    # 启动UI前的超时检测
    if ! prompt_continue_or_auto_mode; then
        log_info "超时未响应，自动切换到自动模式" "模式"
        run_auto_mode
        return 0
    fi

    # 主菜单循环
    while true; do
        log_info "显示主菜单" "调试"
        local choice
        choice=$(show_main_menu)
        local menu_exit_code=$?

        # 处理用户取消或ESC - 应该退出管理UI，不是进入自动模式
        if [ $menu_exit_code -ne 0 ]; then
            log_info "用户按ESC或取消，退出管理UI" "系统"
            exit 0
        fi

        # 处理空选择
        if [ -z "$choice" ]; then
            log_info "空选择，继续显示菜单" "调试"
            continue
        fi

        log_info "用户选择: '$choice'" "调试"

        # 处理选择
        case "$choice" in
            0)
                log_info "用户选择回到自动模式" "模式"
                echo
                log_success "正在启动自动模式..." "模式"
                run_auto_mode
                return 0
                ;;
            *)
                handle_menu_choice "$choice"
                # 更新活动时间
                last_activity=$(date +%s)
                ;;
        esac

        log_info "返回主菜单循环" "调试"
    done
}

# 自动模式 - 借鉴compose脚本的循环检查和重连机制
run_auto_mode() {
    log_info "启动自动模式" "启动"

    # 初始化Kopia环境
    init_kopia_environment

    # 尝试设置仓库连接 - 借鉴compose脚本的仓库管理
    if ! setup_kopia_repository; then
        log_error "仓库初始化失败，无法继续" "启动"
        exit 1
    fi

    if ! check_kopia_connection; then
        log_error "Kopia仓库连接失败，无法继续" "启动"
        exit 1
    fi

    log_success "自动模式初始化完成" "启动"
    
    # 执行启动时的完整性检查和清理
    log_info "执行启动完整性检查..." "启动"
    cleanup_corrupted_snapshots
    
    # 进入自动备份循环
    log_info "进入自动备份循环模式..." "备份"
    local cycle_count=0

    while true; do

        cycle_count=$((cycle_count + 1))
        log_info "开始备份周期 #$cycle_count" "调度"

        # 获取备份周期（小时），默认6小时
        local backup_cycle_hours="${BACKUP_CYCLE_HOURS:-6}"
        log_info "备份周期设置: ${backup_cycle_hours}小时" "调度"

        # 显示下次备份时间
        local next_backup_time
        next_backup_time=$(calculate_next_backup_time "$backup_cycle_hours")
        next_timestamp=$(date -d "$next_backup_time" +%s)  # 转换为时间戳
        log_info "下次自动备份: $next_backup_time (等待时间: $(( (next_timestamp - $(date +%s)) / 60 )) 分钟)" "调度"

        # 检查仓库连接状态 - 
        if ! check_kopia_connection; then
            log_warn "仓库连接丢失，尝试重新连接" "调度"
            if ! reconnect_kopia_repository; then
                log_error "仓库重连失败，等待5分钟后重试" "调度"
                sleep 300
                continue
            fi
        fi

        log_info "等待" "调度"


        while (( $(date +%s) < next_timestamp )); do
            sleep 10
        done

        # 执行所有卷的自动备份
        perform_auto_backup_cycle

        # 运行维护任务 - 借鉴compose脚本的维护逻辑
        log_info "运行仓库维护任务" "维护"
        if /bin/kopia maintenance run --full >/dev/null 2>&1; then
            log_info "仓库维护完成" "维护"
        else
            log_warn "仓库维护完成但有警告" "维护"
        fi

    done
}

# 自动备份周期 - 增强错误处理和统计
perform_auto_backup_cycle() {
    local volumes
    volumes=$(get_available_volumes)

    if [ $? -ne 0 ] || [ -z "$volumes" ]; then
        log_warn "未找到可用卷，跳过备份周期" "备份"
        return 0
    fi

    local total_volumes
    total_volumes=$(echo "$volumes" | wc -l)
    local current=0
    local success_count=0
    local failed_count=0

    log_info "开始自动备份周期，共 $total_volumes 个卷" "备份"
    local cycle_start_time=$(date +%s)

    for volume in $volumes; do
        current=$((current + 1))

        # 跳过特殊目录 - 借鉴compose脚本的过滤逻辑
        if [ "$volume" = "lost+found" ] || [ ! -d "$VOLUMES_DIR/$volume" ]; then
            log_info "跳过特殊目录: $volume" "备份"
            continue
        fi

        log_info "备份卷 ($current/$total_volumes): $volume" "备份"

        local description="Auto backup of $volume"
        local tags="volume:$volume,auto:true"

        if create_snapshot_with_progress "$volume" "$description" "$tags"; then
            success_count=$((success_count + 1))
            log_success "卷[$volume]备份成功" "备份"
        else
            failed_count=$((failed_count + 1))
            log_error "卷[$volume]备份失败" "备份"

            # 检查是否是连接问题
            if ! check_kopia_connection; then
                log_warn "检测到连接问题，中断当前周期" "备份"
                break
            fi
        fi

        # 显示总体进度
        show_progress "$current" "$total_volumes" "备份进度"
    done

    local cycle_end_time=$(date +%s)
    local cycle_duration=$(calculate_duration "$cycle_start_time" "$cycle_end_time")

    echo
    log_info "自动备份周期完成，耗时 $(format_duration $cycle_duration)" "备份"
    log_info "成功: $success_count, 失败: $failed_count, 总计: $total_volumes" "备份"

    if [ $failed_count -gt 0 ]; then
        log_warn "部分卷备份失败，请检查日志" "备份"
        return 1
    else
        log_success "所有卷备份成功" "备份"
        return 0
    fi
}

# 显示帮助信息
show_help_info() {
    echo
    highlight "=== NFS Backup Manager ==="
    echo
    echo "这个脚本运行在备份管理容器内，支持两种模式:"
    echo
    printf "${CYAN}自动模式 (Auto Mode):${NC}\n"
    echo "  - 运行自动备份周期 (默认每6小时，可通过BACKUP_CYCLE_HOURS配置)"
    echo "  - 启动时执行快照完整性检查"
    echo "  - 只检查每个卷的最新快照 (除非损坏)"
    echo "  - 自动清理损坏的快照"
    echo "  - 使用方法: BACKUP_MODE=auto ./backup-manager.sh"
    echo
    printf "${CYAN}手动模式 (Manual Mode):${NC}\n"
    echo "  - 交互式菜单进行手动操作"
    echo "  - 手动备份、恢复、清空操作"
    echo "  - 进度显示和时间估算"
    echo "  - 多重安全确认机制"
    echo "  - 启动超时自动切换到自动模式 (默认30秒，可通过MANUAL_MODE_TIMEOUT配置)"
    echo "  - 使用方法: BACKUP_MODE=manual ./backup-manager.sh"
    echo
    printf "${YELLOW}使用示例:${NC}\n"
    echo "  BACKUP_MODE=auto ./backup-manager.sh                    # 启动自动模式"
    echo "  BACKUP_MODE=manual ./backup-manager.sh                  # 启动交互模式"
    echo "  BACKUP_CYCLE_HOURS=1 BACKUP_MODE=auto ./backup-manager.sh    # 1小时备份周期"
    echo "  MANUAL_MODE_TIMEOUT=60 BACKUP_MODE=manual ./backup-manager.sh # 60秒超时"
    echo
    printf "${CYAN}环境变量:${NC}\n"
    echo "  VOLUMES_DIR           - NFS卷目录 (默认: /nfs_volumes)"
    echo "  KOPIA_CONFIG_PATH     - Kopia配置文件路径"
    echo "  KOPIA_CACHE_DIRECTORY - Kopia缓存目录"
    echo "  BACKUP_CYCLE_HOURS    - 自动备份周期小时数 (默认: 6)"
    echo "  MANUAL_MODE_TIMEOUT   - 手动模式超时秒数 (默认: 30)"
    echo
    printf "${CYAN}WebDAV仓库配置 (可选):${NC}\n"
    echo "  WEBDAV_URL            - WebDAV服务器URL"
    echo "  WEBDAV_VOL_PATH       - WebDAV卷路径"
    echo "  KOPIA_REPOSITORY_NAME - 仓库名称 (默认: kopia-repo)"
    echo "  KOPIA_REPOSITORY_USER - WebDAV用户名"
    echo "  KOPIA_REPOSITORY_PASS - WebDAV密码"
    echo "  KOPIA_PASSWORD        - 仓库加密密码"
    echo
    printf "${YELLOW}自动仓库管理:${NC}\n"
    echo "  • 如果配置了WebDAV环境变量，脚本会自动:"
    echo "    - 动态识别WebDAV重定向URL"
    echo "    - 创建必要的WebDAV目录"
    echo "    - 连接现有仓库或创建新仓库"
    echo "    - 在连接丢失时自动重连"
    echo "  • 如果未配置，需要手动设置Kopia仓库"
    echo
    printf "${RED}注意:${NC} 此脚本应在备份管理容器内运行。\n"
    echo
}
