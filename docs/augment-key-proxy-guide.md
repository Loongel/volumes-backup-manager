# Augment终端按键代理操作指南


## Step 1: 开启按键转发终端
```bash
# 新开一个终端作为按键代理控制台
# （在Augment中执行 launch-process 创建新终端）
```

## Step 2: 绑定目标终端

### 🎯 TTY发现与绑定

```bash
# 定义通用TTY绑定函数
bind_target_tty() {
    local current_tty=$(tty | sed 's|^/dev/||') 
    local pattern="${1:-shellIntegration-bash.sh}"
    echo $current_tty
    # 1. 获取并显示目标进程
    echo "发现的由你开启的控制台进程:"
    local target_processes=$(ps -eo pid,ppid,lstart,tty,cmd | grep -E "$pattern" | grep -Ev "$current_tty" | grep -v grep)
    echo "$target_processes"
    
    # 2. 获取进程信息
    local target_pids=$(echo "$target_processes" | awk '{print $1}')
    local target_ttys=$(echo "$target_processes" | awk '{print $8}' | sed 's/pts/\/dev\/pts/')
    
    echo $target_pids
    echo $target_ttys

    # 3. 获取你控制台的子进程信息
    echo -e "\n相关子进程:"
    echo "PID    PPID   STARTED                 TTY    COMMAND"
    echo "---    ----   -------                 ---    -------"
    ps -eo pid,ppid,lstart,tty,cmd | grep -E "$(echo $target_pids | tr ' ' '|')" | grep -Ev "$pattern"| grep -Ev "$current_tty"
    
    # 4. 智能选择最新的TTY并设置
    local latest_tty=$(echo "$target_ttys" | tail -n1)
    if [[ -n "$latest_tty" ]] && [[ -e "$latest_tty" ]] && [[ -w "$latest_tty" ]]; then
        export TARGET_TTY="$latest_tty"
        echo -e "\n✅ 已绑定最新TTY: $TARGET_TTY"
        echo "提示: 如需更改,请手动设置TARGET_TTY变量"
        return 0
    fi
    
    echo "❌ 未找到可用TTY或无写入权限"
    return 1
}

# 获取tty进程信息并绑定tty
bind_target_tty
# 根据上述信息，手动绑定 export TARGET_TTY="你的目标TTY设备"

## Step 3: 创建按键注入函数
```bash
# 使用TIOCSTI进行真实按键注入
inject_key() {
    local target_tty="$1"
    local key_sequence="$2"

    python3 -c "
import termios
import fcntl
import time

def inject_keys(tty_path, keys):
    try:
        with open(tty_path, 'w') as tty:
            for char in keys:
                fcntl.ioctl(tty, termios.TIOCSTI, char.encode())
                time.sleep(0.01)  # 小延迟模拟真实打字
        return True
    except Exception as e:
        print(f'注入失败: {e}')
        return False

inject_keys('$target_tty', '$key_sequence')
"
}

## Step 4: 按键注入（附：常用按键注入）

### 方向键 (使用TIOCSTI)
```bash
inject_key $TARGET_TTY '\033[A'  # 上箭头
inject_key $TARGET_TTY '\033[B'  # 下箭头
inject_key $TARGET_TTY '\033[D'  # 左箭头
inject_key $TARGET_TTY '\033[C'  # 右箭头
```

### 控制键
```bash
inject_key $TARGET_TTY '\r'     # 回车
inject_key $TARGET_TTY '\033'   # ESC
inject_key $TARGET_TTY '\003'   # Ctrl+C
inject_key $TARGET_TTY '\030'   # Ctrl+X
```

### 数字和文本
```bash
inject_key $TARGET_TTY '1'      # 数字1
inject_key $TARGET_TTY 'hello'  # 文本
```

## 🚀 快速参考

### 常用组合操作
```bash
# 菜单导航 (推荐方法)
inject_key $TARGET_TTY '2'     # 选择2
sleep 0.1
inject_key $TARGET_TTY '\r'    # 确认

# 方向键导航
inject_key $TARGET_TTY '\033[B'  # 下移
sleep 0.1
inject_key $TARGET_TTY '\033[B'  # 再下移
sleep 0.1
inject_key $TARGET_TTY '\r'      # 确认

# 退出程序
inject_key $TARGET_TTY '\033'    # ESC退出
sleep 0.1
inject_key $TARGET_TTY '\030'    # Ctrl+X退出
```

### 🔧 故障排除

#### 测试TIOCSTI是否可用
```bash
# 测试TIOCSTI功能
python3 -c "
import termios
import fcntl
try:
    with open('$TARGET_TTY', 'w') as tty:
        fcntl.ioctl(tty, termios.TIOCSTI, 'test'.encode())
    print('TIOCSTI可用')
except Exception as e:
    print(f'TIOCSTI不可用: {e}')
"
```

## 📚 技术说明

### 为什么需要TIOCSTI？
1. **printf方法局限性**:
   - 只能写入输出流，无法模拟真实输入
   - 应用程序无法感知到"用户输入"
   - 只能控制显示，不能控制交互

2. **TIOCSTI优势**:
   - 直接注入到TTY输入缓冲区
   - 应用程序认为是真实的键盘输入
   - 可以触发readline历史、whiptail菜单等功能

### 兼容性说明
- **内核版本**: Linux 6.2+可能默认禁用TIOCSTI
- **权限要求**: 需要对目标TTY的写权限
- **容器环境**: Docker容器中通常可用
