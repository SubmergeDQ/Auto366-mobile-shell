#!/system/bin/sh

#   Auto366 答案提取工具 
#   功能: 从 up366 加密数据中解密并提取答案
#   环境: MT管理器 | root权限 | 扩展包环境Shell

#  全局配置 
SCRIPT_VERSION="2.0.0"
FLIPBOOK_BASE="/data/data/com.up366.mobile/files/flipbook"
AES_KEY_B64="QJBNiBmV55PDrewyne3GsA=="
TEMP_DIR=""
ANSWER_FILE=""

#  颜色定义 
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_MAGENTA='\033[0;35m'
COLOR_CYAN='\033[0;36m'
COLOR_WHITE='\033[0;37m'
COLOR_BOLD='\033[1m'
COLOR_RESET='\033[0m'

#  日志函数 
log_info() {
    echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $1"
}

log_success() {
    echo -e "${COLOR_GREEN}[OK]${COLOR_RESET} $1"
}

log_warn() {
    echo -e "${COLOR_YELLOW}[WARN]${COLOR_RESET} $1"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $1"
}

log_debug() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo -e "${COLOR_MAGENTA}[DEBUG]${COLOR_RESET} $1"
    fi
}

log_step() {
    echo ""
    echo -e "${COLOR_BLUE}${COLOR_BOLD}========================================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}${COLOR_BOLD}  $1${COLOR_RESET}"
    echo -e "${COLOR_BLUE}${COLOR_BOLD}========================================${COLOR_RESET}"
    echo ""
}

#  清理函数 
cleanup() {
    local exit_code=$?
    log_info "执行清理操作..."
    
    # 删除临时目录
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR" 2>/dev/null
        log_success "已清理临时目录: $TEMP_DIR"
    fi
    
    exit $exit_code
}

# 注册清理钩子
trap cleanup EXIT INT TERM

#  显示Banner 
show_banner() {
    echo ""
    echo -e "${COLOR_BOLD}${COLOR_CYAN}"
    echo "══════════════════════════════════════"
    echo "     Auto366 答案提取工具 v${SCRIPT_VERSION}      "
    echo "     Shell 命令版本                     "
    echo "══════════════════════════════════════"
    echo -e "${COLOR_RESET}"
    echo ""
}

#  Root权限检查 
check_root() {
    log_step "权限检查"
    
    if [ "$(id -u)" -ne 0 ]; then
        log_error "需要 root 权限才能运行此脚本!"
        echo ""
        echo "解决方法:"
        echo "  1. 在 MT管理器 中运行脚本时，勾选 '以root身份执行'"
        echo "  2. 或在终端中先输入 'su' 切换到 root 用户"
        echo "  3. 确保 Magisk/KernelSU 等 root 方案已正确安装"
        echo ""
        return 1
    fi
    
    log_success "Root 权限验证通过"
    return 0
}

#  环境检测与配置 
detect_environment() {
    log_step "环境检测"
    
    local has_openssl="no"
    local has_python="no"
    local has_xxd="no"
    local has_base64_cmd="no"
    
    # 检测 OpenSSL
    if command -v openssl >/dev/null 2>&1; then
        local openssl_ver=$(openssl version 2>/dev/null | head -1)
        log_success "OpenSSL 可用: ${openssl_ver:-已找到}"
        has_openssl="yes"
        
        # 检查是否支持 AES
        if openssl enc -aes-128-cbc -help 2>&1 | grep -q "aes-128-cbc"; then
            log_success "OpenSSL 支持 AES-128-CBC 解密"
        else
            log_warn "OpenSSL 可能不支持 AES-128-CBC"
        fi
    else
        log_error "未找到 OpenSSL 命令"
    fi
    
    # 检测 Python (Termux)
    local termux_py="/data/data/com.termux/files/usr/bin/python3"
    if [ -x "$termux_py" ]; then
        if "$termux_py" -c "from Crypto.Cipher import AES" 2>/dev/null; then
            log_success "Termux Python 可用 (带 pycryptodome)"
            has_python="yes"
        elif "$termux_py" --version >/dev/null 2>&1; then
            log_warn "Termux Python 存在但缺少 pycryptodome 库"
        fi
    fi
    
    # 检测系统 PATH 中的 python3
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "from Crypto.Cipher import AES" 2>/dev/null; then
            log_success "系统 Python3 可用 (带 pycryptodome)"
            has_python="yes"
        fi
    fi
    
    # 检测 xxd
    if command -v xxd >/dev/null 2>&1; then
        log_success "xxd 命令可用"
        has_xxd="yes"
    else
        log_warn "未找到 xxd 命令 (用于十六进制转换)"
    fi
    
    # 检测 base64
    if command -v base64 >/dev/null 2>&1; then
        log_success "base64 命令可用"
        has_base64_cmd="yes"
    else
        log_error "未找到 base64 命令"
    fi
    
    # 设置环境变量
    export PATH="/system/bin:/vendor/bin:/sbin:$PATH"
    
    # 尝试加载 Termux 工具链
    if [ -d "/data/data/com.termux/files/usr/bin" ]; then
        export PATH="/data/data/com.termux/files/usr/bin:$PATH"
        export LD_LIBRARY_PATH=/data/data/com.termux/files/usr/lib
        log_info "已添加 Termux 路径到 PATH"
    fi
    
    # 返回检测结果
    if [ "$has_openssl" = "yes" ] && [ "$has_base64_cmd" = "yes" ] && [ "$has_xxd" = "yes" ]; then
        DECRYPT_METHOD="openssl"
        log_success "将使用 OpenSSL 进行解密"
        return 0
    elif [ "$has_python" = "yes" ]; then
        DECRYPT_METHOD="python"
        log_success "将使用 Python 进行解密"
        return 0
    else
        log_error "缺少必要的解密工具!"
        echo ""
        echo "请安装以下工具之一:"
        echo ""
        echo "方法一: 使用 Termux 安装 (推荐)"
        echo "  pkg install openssl xxd coreutils"
        echo ""
        echo "方法二: 使用 Termux 安装 Python"
        echo "  pkg install python && pip install pycryptodome"
        echo ""
        echo "方法三: 手动下载依赖 (脚本会自动尝试)"
        echo ""
        return 1
    fi
}

#  自动安装依赖 
auto_install_dependencies() {
    log_step "自动安装依赖"
    
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    local temp_python_dir="$script_dir/temp/Python"
    
    log_info "尝试自动配置解密环境..."
    
    # 方法1: 再次检查是否有可用的工具（可能之前PATH问题）
    export PATH="/system/bin:/vendor/bin:/sbin:/data/data/com.termux/files/usr/bin:$PATH"
    
    if command -v openssl >/dev/null 2>&1 && command -v xxd >/dev/null 2>&1; then
        log_success "重新检测: OpenSSL 和 xxd 已可用"
        DECRYPT_METHOD="openssl"
        return 0
    fi
    
    # 方法2: 尝试使用 busybox 的等效命令
    if command -v busybox >/dev/null 2>&1; then
        log_info "检测到 busybox，尝试使用其内置工具..."
        # busybox 通常包含 base64, dd 等基础工具
    fi
    
    # 方法3: 创建内联Python解密脚本（如果系统有python但没有库）
    if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
        local py_cmd="python3"
        ! command -v python3 >/dev/null 2>&1 && py_cmd="python"
        
        log_info "发现 Python ($py_cmd)，创建内联解密模块..."
        
        # 创建便携式Python解密脚本
        cat > "$script_dir/temp/_decrypt.py" << 'PYEOF'
#!/usr/bin/env python3
import sys, os, base64, struct

KEY = base64.b64decode("QJBNiBmV55PDrewyne3GsA==")

def decrypt_file(input_path, output_path):
    try:
        with open(input_path, 'rb') as f:
            data = f.read()
        if len(data) < 16:
            print(f"[ERROR] 文件太小: {len(data)}字节", file=sys.stderr)
            return False
        
        iv = data[:16]
        ciphertext = data[16:]
        
        # 使用纯Python实现AES解密（简化版，仅支持特定场景）
        # 如果有pycryptodome则使用它
        try:
            from Crypto.Cipher import AES
            cipher = AES.new(KEY, AES.MODE_CBC, iv)
            plaintext = cipher.decrypt(ciphertext)
            
            pad_len = plaintext[-1]
            if 1 <= pad_len <= 16 and all(b == pad_len for b in plaintext[-pad_len:]):
                plaintext = plaintext[:-pad_len]
            
            with open(output_path, 'wb') as f:
                f.write(plaintext)
            print(f"[OK] 解密成功: {input_path}")
            return True
        except ImportError:
            pass
        
        # 回退：使用openssl子进程
        import subprocess
        key_hex = KEY.hex()
        iv_hex = iv.hex()
        
        with open(input_path, 'rb') as fin:
            fin.read(16)
            cipher_data = fin.read()
        
        result = subprocess.run(
            ['openssl', 'enc', '-aes-128-cbc', '-d',
             '-K', key_hex, '-iv', iv_hex, '-nosalt'],
            input=cipher_data,
            capture_output=True
        )
        
        if result.returncode == 0 and result.stdout:
            data = result.stdout
            pad_len = data[-1]
            if 1 <= pad_len <= 16 and all(b == pad_len for b in data[-pad_len:]):
                data = data[:-pad_len]
            with open(output_path, 'wb') as f:
                f.write(data)
            print(f"[OK] 解密成功(通过openssl): {input_path}")
            return True
        else:
            print(f"[ERROR] 解密失败", file=sys.stderr)
            return False
            
    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        return False

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("用法: _decrypt.py <输入文件> <输出文件>")
        sys.exit(1)
    sys.exit(0 if decrypt_file(sys.argv[1], sys.argv[2]) else 1)
PYEOF
        
        chmod +x "$script_dir/temp/_decrypt.py"
        DECRYPT_METHOD="python_inline"
        log_success "已创建内联Python解密脚本"
        return 0
    fi
    
    log_error "无法自动安装所需依赖"
    log_error "请手动安装后重试"
    return 1
}

#  目录选择函数 
select_directory() {
    local target_path="$1"
    local prompt_text="$2"
    local selection_var="$3"
    
    # 检查路径是否存在
    if [ ! -d "$target_path" ]; then
        log_error "目录不存在: $target_path"
        return 1
    fi
    
    # 获取所有文件夹
    local dirs=()
    while IFS= read -r dir; do
        [ -n "$dir" ] && dirs+=("$dir")
    done < <(find "$target_path" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    
    # 检查是否有文件夹
    if [ ${#dirs[@]} -eq 0 ]; then
        log_error "目录下没有子文件夹: $target_path"
        return 1
    fi
    
    # 显示选择菜单
    echo -e "${COLOR_YELLOW}=== 选择文件夹 ===${COLOR_RESET}"
    echo -e "路径: ${COLOR_CYAN}$target_path${COLOR_RESET}"
    echo ""
    
    local i=1
    for dir in "${dirs[@]}"; do
        local dirname=$(basename "$dir")
        printf "  ${COLOR_GREEN}[%2d]${COLOR_RESET} %s\n" "$i" "$dirname"
        i=$((i + 1))
    done
    
    echo ""
    local max=${#dirs[@]}
    echo -n -e "${COLOR_BOLD}>> 选择 (1-$max): ${COLOR_RESET}"
    
    # 读取用户输入
    local choice
    read choice
    
    # 验证输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$max" ]; then
        log_error "无效的选择: $choice"
        return 1
    fi
    
    # 返回选中的路径
    local selected="${dirs[$((choice - 1))]}"
    local selected_name=$(basename "$selected")
    
    eval "$selection_var=\"$selected\""
    
    echo ""
    log_success "$selected_name"
    return 0
}

#  目标文件查找与复制 
find_and_copy_files() {
    log_step "目标文件定位与复制"
    
    local selected_dir="$1"
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    
    # 创建临时目录
    TEMP_DIR="$script_dir/temp"
    mkdir -p "$TEMP_DIR"
    log_info "已创建临时目录: $TEMP_DIR"
    
    # 扫描数字命名的文件夹
    local found_dirs=()
    local dir_num
    
    for dir_num in $(seq 1 20); do
        local target_dir="$selected_dir/$dir_num"
        if [ -d "$target_dir" ]; then
            found_dirs+=("$dir_num")
        fi
    done
    
    # 检查是否找到数字文件夹
    if [ ${#found_dirs[@]} -eq 0 ]; then
        log_error "未找到数字命名的文件夹 (1, 2, 3...)"
        log_error "期望路径格式: .../<父文件夹>/<数字文件夹>/page1.js.u3enc"
        echo ""
        echo "当前目录内容:"
        ls -la "$selected_dir/" 2>/dev/null | head -20
        return 1
    fi
    
    log_success "找到 ${#found_dirs[@]} 个目标文件夹: ${found_dirs[*]}"
    echo ""
    
    # 复制文件
    local copied_count=0
    local failed_count=0
    
    for dir_num in "${found_dirs[@]}"; do
        local source_file="$selected_dir/$dir_num/page1.js.u3enc"
        # 使用纯数字命名，避免 .js.js 重复后缀
        local dest_file="$TEMP_DIR/${dir_num}.u3enc"
        
        if [ -f "$source_file" ]; then
            if cp "$source_file" "$dest_file" 2>/dev/null; then
                local file_size=$(wc -c < "$dest_file" 2>/dev/null)
                log_success "已复制: ${dir_num}.js.u3enc (${file_size} 字节)"
                copied_count=$((copied_count + 1))
            else
                log_error "复制失败: $source_file"
                failed_count=$((failed_count + 1))
            fi
        else
            log_warn "文件不存在: $source_file"
            failed_count=$((failed_count + 1))
        fi
    done
    
    echo ""
    if [ $copied_count -gt 0 ]; then
        log_success "文件复制完成: 成功 ${copied_count} 个, 失败 ${failed_count} 个"
        log_success "目标位置: $TEMP_DIR/"
        return 0
    else
        log_error "没有成功复制任何文件"
        return 1
    fi
}

#  OpenSSL 解密函数 
decrypt_with_openssl() {
    local input_file="$1"
    local output_file="$2"
    
    # 将Base64密钥转换为Hex
    local key_hex=$(echo -n "$AES_KEY_B64" | base64 -d 2>/dev/null | xxd -p | tr -d '\n')
    
    if [ -z "$key_hex" ] || [ ${#key_hex} -ne 32 ]; then
        log_error "密钥转换失败"
        return 1
    fi
    
    # 提取IV（前16字节）并转换为Hex
    local iv_hex=$(head -c 16 "$input_file" | xxd -p | tr -d '\n')
    
    # 解密：跳过前16字节(IV)，解密剩余部分
    if tail -c +17 "$input_file" | openssl enc -aes-128-cbc -d \
        -K "$key_hex" \
        -iv "$iv_hex" \
        -nosalt \
        -out "$output_file" 2>/dev/null; then
        
        if [ -s "$output_file" ]; then
            log_success "解密成功: $(basename "$input_file") -> $(basename "$output_file")"
            return 0
        else
            log_error "解密输出为空: $(basename "$input_file")"
            rm -f "$output_file"
            return 1
        fi
    else
        log_error "OpenSSL 解密失败: $(basename "$input_file")"
        # 显示详细错误信息
        tail -c +17 "$input_file" | openssl enc -aes-128-cbc -d \
            -K "$key_hex" \
            -iv "$iv_hex" \
            -nosalt 2>&1 | head -2
        return 1
    fi
}

#  Python 解密函数 
decrypt_with_python() {
    local input_file="$1"
    local output_file="$2"
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    
    local py_cmd="python3"
    if ! command -v python3 >/dev/null 2>&1; then
        py_cmd="python"
    fi
    
    # 查找或使用内联解密脚本
    local decrypt_script="$script_dir/temp/_decrypt.py"
    
    if [ -f "$decrypt_script" ]; then
        "$py_cmd" "$decrypt_script" "$input_file" "$output_file" 2>/dev/null
        return $?
    fi
    
    # 使用内联Python代码解密
    "$py_cmd" -c "
import sys, base64

KEY = base64.b64decode('$AES_KEY_B64')

try:
    from Crypto.Cipher import AES
    with open('$input_file', 'rb') as f:
        data = f.read()
    iv = data[:16]
    ciphertext = data[16:]
    cipher = AES.new(KEY, AES.MODE_CBC, iv)
    plaintext = cipher.decrypt(ciphertext)
    pad_len = plaintext[-1]
    if 1 <= pad_len <= 16 and all(b == pad_len for b in plaintext[-pad_len:]):
        plaintext = plaintext[:-pad_len]
    with open('$output_file', 'wb') as f:
        f.write(plaintext)
    print('[OK] 解密成功')
except Exception as e:
    print(f'[ERROR] {e}', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null
    
    if [ $? -eq 0 ] && [ -s "$output_file" ]; then
        log_success "解密成功: $(basename "$input_file") -> $(basename "$output_file")"
        return 0
    else
        log_error "Python 解密失败: $(basename "$input_file")"
        return 1
    fi
}

#  批量解密函数 
decrypt_all_files() {
    log_step "解密加密文件"
    
    if [ -z "$TEMP_DIR" ] || [ ! -d "$TEMP_DIR" ]; then
        log_error "临时目录不存在"
        return 1
    fi
    
    local success_count=0
    local fail_count=0
    
    # 遍历所有 .u3enc 文件
    for u3enc_file in "$TEMP_DIR"/*.u3enc; do
        [ -f "$u3enc_file" ] || continue
        
        local basename=$(basename "$u3enc_file" .u3enc)
        local output_file="${TEMP_DIR}/${basename}.js"
        
        log_info "正在解密: ${basename}.u3enc ..."
        
        case "$DECRYPT_METHOD" in
            openssl)
                if decrypt_with_openssl "$u3enc_file" "$output_file"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
                ;;
            python|python_inline)
                if decrypt_with_python "$u3enc_file" "$output_file"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
                ;;
            *)
                log_error "未知解密方式: $DECRYPT_METHOD"
                fail_count=$((fail_count + 1))
                ;;
        esac
    done
    
    echo ""
    log_step "解密结果汇总"
    echo -e "  ${COLOR_GREEN}成功:${COLOR_RESET} $success_count 个文件"
    echo -e "  ${COLOR_RED}失败:${COLOR_RESET} $fail_count 个文件"
    echo ""
    
    if [ $success_count -eq 0 ]; then
        log_error "没有文件解密成功"
        return 1
    fi
    
    # 调试模式: 显示解密后的文件内容预览
    if [ "$DEBUG_MODE" = "true" ]; then
        log_step "调试信息 - 解密后内容预览"
        for js_file in "$TEMP_DIR"/*.js; do
            [ -f "$js_file" ] || continue
            local fname=$(basename "$js_file")
            local fsize=$(wc -c < "$js_file")
            echo -e "${COLOR_MAGENTA}--- $fname ($fsize 字节) ---${COLOR_RESET}"
            # 显示前800字符，帮助分析数据结构
            head -c 800 "$js_file"
            echo -e "\n${COLOR_MAGENTA}--- 预览结束 ---${COLOR_RESET}"
            echo ""
        done
    fi
    
    return 0
}

#  答案提取函数 (带去重合并)
extract_answers() {
    log_step "提取答案信息"
    
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    ANSWER_FILE="$script_dir/answer.txt"
    
    # 临时文件用于收集和去重
    local tmp_all="$TEMP_DIR/_all_answers.txt"
    local tmp_unique="$TEMP_DIR/_unique_answers.txt"
    > "$tmp_all"
    > "$tmp_unique"
    
    # 清空或创建答案文件
    > "$ANSWER_FILE"
    
    local total_raw=0
    local file_count=0
    
    # 遍历所有解密后的JS文件
    for js_file in "$TEMP_DIR"/*.js; do
        [ -f "$js_file" ] || continue
        
        local file_basename=$(basename "$js_file" .js)
        log_info "正在处理: ${file_basename}.js"
        
        # 提取答案并追加到总文件
        extract_answers_from_js "$js_file" >> "$tmp_all"
        file_count=$((file_count + 1))
    done
    
    # 统计原始答案数
    total_raw=$(wc -l < "$tmp_all" 2>/dev/null || echo "0")
    
    if [ "$total_raw" -eq 0 ]; then
        log_warn "未从任何文件中提取到答案"
        {
            echo "========================================"
            echo "  Auto366 答案提取结果"
            echo "  提取时间: $(date '+%Y-%m-%d %H:%M:%S')"
            echo "========================================"
            echo ""
            echo "[!] 未找到有效答案数据"
            echo ""
        } >> "$ANSWER_FILE"
        
        rm -f "$tmp_all" "$tmp_unique" 2>/dev/null
        return 1
    fi
    
    log_info "正在处理合并答案..."
    
    # 去重 + 按题号数字顺序排序
    sort -t'|' -k1,1n -u "$tmp_all" > "$tmp_unique" 2>/dev/null || sort -n "$tmp_all" > "$tmp_unique"
    
    local total_unique=$(wc -l < "$tmp_unique" 2>/dev/null || echo "0")
    
    # 写入最终答案文件（按题号排序后的格式化输出）
    {
        echo "========================================"
        echo "  答案"
        echo "========================================"
        
        # 读取排序后的数据并格式化输出
        while IFS='|' read -r num content; do
            [ -z "$num" ] && continue
            printf "第 %s 题：「%s」\n" "$num" "$content"
        done < "$tmp_unique"
        
        echo ""
        echo "========================================"
        echo "  日志"
        echo "========================================"
        echo "[INFO] 处理文件数: $file_count"
        echo "[INFO] 提取原始答案: $total_raw 个"
        echo "[OK] 合并去重后: $total_unique 个答案"
        echo ""
    } >> "$ANSWER_FILE"
    
    # 清理临时文件
    rm -f "$tmp_all" "$tmp_unique" 2>/dev/null
    
    echo ""
    log_success "答案提取完成!"
    log_success "原始答案: $total_raw 个 → 去重后: $total_unique 个"
    log_success "保存位置: $ANSWER_FILE"
    echo ""
    
    # 显示预览
    echo -e "${COLOR_YELLOW}=== 答案预览 ===${COLOR_RESET}"
    head -50 "$ANSWER_FILE"
    [ $(wc -l < "$ANSWER_FILE" 2>/dev/null || echo "0") -gt 50 ] && echo "..."
    echo ""
    
    return 0
}

#  从单个JS文件提取答案 (纯Shell版 - 简单可靠)
extract_answers_from_js() {
    local js_file="$1"
    
    if [ ! -f "$js_file" ]; then
        return 1
    fi
    
    # 临时文件
    local tmp_raw="$TEMP_DIR/_raw_answers.txt"
    > "$tmp_raw"
    
    log_debug "使用纯Shell模式提取答案..."
    
    # 步骤1: 合并所有行为一行
    local oneline
    oneline=$(tr -d '\n\r' < "$js_file" 2>/dev/null)
    
    if [ -z "$oneline" ]; then
        log_warn "文件内容为空: $js_file"
        return 1
    fi
    
    # 步骤2: 用 awk 提取每个答案块中的 answer_text 和对应 content
    echo "$oneline" | awk -v RS='"answer_text":"' '
    NR > 1 {
        # 提取答案字母 (第一个字符)
        ans = substr($0, 1, 1)
        if (ans == "" || ans == "\"") next
        
        # 在当前记录中查找 "id":"ans" 后面的 "content":"值"
        pattern = "\"id\":\"" ans "\""
        
        # 找到 id 位置后的内容
        pos = index($0, pattern)
        if (pos > 0) {
            rest = substr($0, pos + length(pattern))
            
            # 找 content 字段
            cpos = index(rest, "\"content\":\"")
            if (cpos > 0) {
                after = substr(rest, cpos + 11)
                qpos = index(after, "\"")
                if (qpos > 1) {
                    content = substr(after, 1, qpos - 1)
                    
                    # 清理HTML标签
                    gsub(/<[^>]*>/, "", content)
                    gsub(/&nbsp;/, " ", content)
                    
                    print "|" content
                    next
                }
            }
        }
        
        # 回退：只输出字母
        print "|" ans
    }
    ' >> "$tmp_raw"
    
    # 检查是否提取到数据
    if [ ! -s "$tmp_raw" ]; then
        log_warn "未提取到答案数据"
        rm -f "$tmp_raw" 2>/dev/null
        return 1
    fi
    
    # 步骤3: 输出结果（带编号，格式: 题号|答案内容）
    local num=0
    while IFS= read -r content; do
        [ -z "$content" ] && continue
        # 去除可能的前导 |
        content=$(echo "$content" | sed 's/^|//')
        [ -z "$content" ] && continue
        num=$((num + 1))
        printf "%s|%s\n" "$num" "$content"
    done < "$tmp_raw"
    
    # 清理临时文件
    rm -f "$tmp_raw" 2>/dev/null
    
    return 0
}

#  主函数 
main() {
    # 解析命令行参数
    DEBUG_MODE="false"
    for arg in "$@"; do
        case "$arg" in
            --debug|-d)
                DEBUG_MODE="true"
                log_warn "调试模式已启用!"
                ;;
            --help|-h)
                show_banner
                echo "用法: $0 [选项]"
                echo ""
                echo "选项:"
                echo "  -d, --debug   启用调试模式（显示详细日志和文件预览）"
                echo "  -h, --help    显示帮助信息"
                echo ""
                echo "示例:"
                echo "  $0              # 正常运行"
                echo "  $0 --debug      # 调试模式运行"
                exit 0
                ;;
        esac
    done
    
    show_banner
    
    # 1. 检查Root权限
    if ! check_root; then
        exit 1
    fi
    
    # 2. 环境检测
    if ! detect_environment; then
        # 尝试自动安装依赖
        if ! auto_install_dependencies; then
            exit 1
        fi
    fi
    
    # 3. 检查 flipbook 目录是否存在
    if [ ! -d "$FLIPBOOK_BASE" ]; then
        log_error "Flipbook 目录不存在: $FLIPBOOK_BASE"
        echo ""
        echo "可能的原因:"
        echo "  1. 未安装 up366 应用"
        echo "  2. 应用从未打开过（无缓存数据）"
        echo "  3. 应用数据已被清除"
        echo "  4. 设备未正确 root"
        echo ""
        echo "解决方法:"
        echo "  1. 打开 up366 应用并浏览任意课程"
        echo "  2. 确认应用有缓存数据后再运行此脚本"
        echo ""
        exit 1
    fi
    
    log_success "Flipbook 目录存在: $FLIPBOOK_BASE"
    
    # 4. 第一级目录选择
    local first_level_dir=""
    log_step "第一级目录选择"
    
    if ! select_directory "$FLIPBOOK_BASE" "选择课程/试卷文件夹" first_level_dir; then
        log_error "第一级目录选择失败"
        exit 1
    fi
    
    # 5. 第二级目录选择
    local second_level_dir=""
    log_step "第二级目录选择"
    
    if ! select_directory "$first_level_dir" "选择具体内容文件夹" second_level_dir; then
        log_error "第二级目录选择失败"
        exit 1
    fi
    
    log_success "找到目标! "
    log_success "路径: $second_level_dir"
    
    # 6. 查找并复制文件
    if ! find_and_copy_files "$second_level_dir"; then
        exit 1
    fi
    
    # 7. 解密文件
    if ! decrypt_all_files; then
        exit 1
    fi
    
    # 8. 提取答案
    if ! extract_answers; then
        exit 1
    fi
    
    # 9. 完成
    echo ""
    echo -e "${COLOR_GREEN}${COLOR_BOLD}══════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}           任务完成!                   ${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}══════════════════════════════════════${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}  答案文件: $(basename "$ANSWER_FILE")$(printf '%*s' $((28 - ${#ANSWER_FILE})) '')${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}  临时文件已自动清理                  ${COLOR_RESET}"
    echo -e "${COLOR_GREEN}${COLOR_BOLD}══════════════════════════════════════${COLOR_RESET}"
    echo ""
    
    return 0
}

#  执行入口 
main "$@"
