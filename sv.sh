#!/bin/bash

# SV - Shell Version Manager
# 统一的脚本版本和配置管理工具
# 功能：自动更新、环境变量管理、配置统一维护

# 版本号
readonly SCRIPT_VERSION="1.0.3"

# 配置常量
readonly GITLAB_HOST="${GITLAB_HOST:-gitlab.example.com}"
readonly GITLAB_PROJECT="project/project-dev"
readonly API_TIMEOUT=30
readonly MAX_RETRIES=3

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Emoji 图标
readonly SUCCESS="✅"
readonly FAILED="❌"
readonly WARNING="⚠️"
readonly INFO="ℹ️"
readonly ROCKET="🚀"
readonly GEAR="⚙️"

# 日志函数
log_info() {
    echo -e "${CYAN}${INFO} $1${NC}"
}

log_success() {
    echo -e "${GREEN}${SUCCESS} $1${NC}"
}

log_error() {
    echo -e "${RED}${FAILED} $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}${WARNING} $1${NC}"
}

# 语义化版本比较函数
# 参数：$1 - 版本1，$2 - 版本2
# 返回：0 如果版本1 >= 版本2，1 如果版本1 < 版本2
version_compare() {
    local version1="$1"
    local version2="$2"

    # 如果版本相同，返回0
    [[ "$version1" == "$version2" ]] && return 0

    # 将版本号分解为数组
    local IFS='.'
    local ver1_array=($version1)
    local ver2_array=($version2)

    # 获取最大长度
    local max_len=${#ver1_array[@]}
    [[ ${#ver2_array[@]} -gt $max_len ]] && max_len=${#ver2_array[@]}

    # 逐个比较版本号的每个部分
    for ((i=0; i<max_len; i++)); do
        local v1=${ver1_array[$i]:-0}
        local v2=${ver2_array[$i]:-0}

        # 移除非数字字符（如果有的话）
        v1=$(echo "$v1" | sed 's/[^0-9]//g')
        v2=$(echo "$v2" | sed 's/[^0-9]//g')

        # 如果为空，设为0
        [[ -z "$v1" ]] && v1=0
        [[ -z "$v2" ]] && v2=0

        if [[ $v1 -gt $v2 ]]; then
            return 0  # version1 > version2
        elif [[ $v1 -lt $v2 ]]; then
            return 1  # version1 < version2
        fi
        # 如果相等，继续比较下一个部分
    done

    # 所有部分都相等
    return 0
}

# 获取shell配置文件路径
get_shell_config_file() {
    # 首先检查用户的默认shell
    local user_shell
    user_shell=$(basename "$SHELL" 2>/dev/null)

    case "$user_shell" in
        "zsh")
            echo "$HOME/.zshrc"
            ;;
        "bash")
            if [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        "fish")
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            # 如果无法确定，按优先级检查文件是否存在
            if [[ -f "$HOME/.zshrc" ]]; then
                echo "$HOME/.zshrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            elif [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.profile"
            fi
            ;;
    esac
}

# 设置环境变量到配置文件
set_env_variable() {
    local var_name="$1"
    local var_value="$2"
    local config_file

    config_file=$(get_shell_config_file)

    # 检查是否已存在该环境变量
    if grep -q "^export ${var_name}=" "$config_file" 2>/dev/null; then
        # 更新现有的环境变量
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|" "$config_file"
        else
            # Linux
            sed -i "s|^export ${var_name}=.*|export ${var_name}=\"${var_value}\"|" "$config_file"
        fi
        log_info "已更新环境变量 $var_name 在文件: $config_file"
    else
        # 添加新的环境变量
        echo "" >> "$config_file"
        echo "# Project Scripts Configuration" >> "$config_file"
        echo "export ${var_name}=\"${var_value}\"" >> "$config_file"
        log_success "已添加环境变量 $var_name 到文件: $config_file"
    fi

    # 立即设置到当前会话
    export "${var_name}=${var_value}"
    log_info "环境变量已在当前会话中生效"
    log_warning "请重新打开终端或执行 'source $config_file' 使环境变量永久生效"
}

# 获取GitLab Token
get_gitlab_token() {
    echo "${GITLAB_TOKEN:-}"
}

# 配置管理功能
manage_config() {
    echo -e "${BOLD}${GEAR} SV 配置管理${NC}"
    echo ""

    # 显示当前配置
    echo -e "${CYAN}当前配置：${NC}"
    local current_token="${GITLAB_TOKEN:-}"
    if [[ -n "$current_token" ]]; then
        local masked_token="${current_token:0:8}***${current_token: -4}"
        echo -e "  GITLAB_TOKEN: $masked_token"
    else
        echo -e "  GITLAB_TOKEN: ${RED}未设置${NC}"
    fi
    echo -e "  GITLAB_HOST: ${GITLAB_HOST}"
    echo ""

    # 配置选项
    echo -e "${CYAN}配置选项：${NC}"
    echo -e "  1) 设置 GitLab Token"
    echo -e "  2) 设置 GitLab Host"
    echo -e "  3) 查看配置文件位置"
    echo -e "  4) 返回"
    echo ""

    read -p "请选择 (1-4): " choice
    case $choice in
        1)
            echo ""
            read -p "请输入 GitLab Personal Access Token: " token
            if [[ -n "$token" ]]; then
                set_env_variable "GITLAB_TOKEN" "$token"
                echo ""
                log_success "GitLab Token 配置完成"
            else
                log_error "Token 不能为空"
            fi
            ;;
        2)
            echo ""
            echo -e "${CYAN}当前 GitLab Host: ${GITLAB_HOST}${NC}"
            read -p "请输入新的 GitLab Host (留空保持默认): " host
            if [[ -n "$host" ]]; then
                set_env_variable "GITLAB_HOST" "$host"
                echo ""
                log_success "GitLab Host 配置完成"
                log_warning "请重新运行脚本使新配置生效"
            else
                log_info "保持默认配置"
            fi
            ;;
        3)
            echo ""
            local config_file
            config_file=$(get_shell_config_file)
            echo -e "${CYAN}配置文件位置: $config_file${NC}"
            if [[ -f "$config_file" ]]; then
                echo -e "${CYAN}项目相关配置：${NC}"
                grep -n "Project\|GITLAB" "$config_file" 2>/dev/null || echo "  未找到相关配置"
            fi
            ;;
        4)
            return 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 检查别名是否存在
check_alias_exists() {
    local alias_name="$1"
    local config_file
    config_file=$(get_shell_config_file)

    # 检查配置文件中是否有别名定义
    if [[ -f "$config_file" ]] && grep -q "alias ${alias_name}=" "$config_file" 2>/dev/null; then
        return 0
    fi

    # 检查当前会话中是否有别名
    if alias "$alias_name" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# 添加脚本别名
add_script_alias() {
    local script_name="$1"
    local alias_name="${script_name%.sh}"
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local script_path="$script_dir/$script_name"
    local config_file
    config_file=$(get_shell_config_file)

    # 检查脚本是否存在
    if [[ ! -f "$script_path" ]]; then
        log_warning "$script_name 不存在，跳过别名设置"
        return 1
    fi

    # 检查别名是否已存在
    if check_alias_exists "$alias_name"; then
        log_info "别名 '$alias_name' 已存在，跳过"
        return 0
    fi

    # 添加别名到配置文件
    # 检查是否已有Project Script Aliases注释
    if ! grep -q "# Project Script Aliases" "$config_file" 2>/dev/null; then
        echo "" >> "$config_file"
        echo "# Project Script Aliases" >> "$config_file"
    fi
    echo "alias ${alias_name}='${script_path}'" >> "$config_file"

    # 在当前会话中设置别名
    alias "${alias_name}=${script_path}"

    log_success "已添加别名: $alias_name -> $script_name"
    return 0
}

# 管理所有脚本别名
manage_aliases() {
    echo -e "${BOLD}${GEAR} 脚本别名管理${NC}"
    echo ""

    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh" "sv.sh")
    local config_file
    config_file=$(get_shell_config_file)

    # 显示当前别名状态
    echo -e "${CYAN}当前别名状态：${NC}"
    for script in "${scripts[@]}"; do
        local alias_name="${script%.sh}"
        local script_path="$script_dir/$script"

        if [[ -f "$script_path" ]]; then
            if check_alias_exists "$alias_name"; then
                echo -e "  ${GREEN}✓${NC} $alias_name -> $script"
            else
                echo -e "  ${RED}✗${NC} $alias_name -> $script (未设置)"
            fi
        else
            echo -e "  ${YELLOW}?${NC} $alias_name -> $script (脚本不存在)"
        fi
    done

    echo ""
    echo -e "${CYAN}操作选项：${NC}"
    echo -e "  1) 自动添加所有缺失的别名"
    echo -e "  2) 手动选择要添加的别名"
    echo -e "  3) 查看配置文件位置"
    echo -e "  4) 返回"
    echo ""

    read -p "请选择 (1-4): " choice
    case $choice in
        1)
            echo ""
            log_info "正在添加所有缺失的别名..."
            local added_count=0
            for script in "${scripts[@]}"; do
                local alias_name="${script%.sh}"
                local script_path="$script_dir/$script"

                if [[ -f "$script_path" ]] && ! check_alias_exists "$alias_name"; then
                    if add_script_alias "$script"; then
                        ((added_count++))
                    fi
                fi
            done

            if [[ $added_count -gt 0 ]]; then
                echo ""
                log_success "成功添加 $added_count 个别名"
                log_warning "请重新打开终端或执行 'source $config_file' 使别名生效"
            else
                log_info "没有需要添加的别名"
            fi
            ;;
        2)
            echo ""
            log_info "请选择要添加别名的脚本："
            local i=1
            local available_scripts=()

            for script in "${scripts[@]}"; do
                local alias_name="${script%.sh}"
                local script_path="$script_dir/$script"

                if [[ -f "$script_path" ]] && ! check_alias_exists "$alias_name"; then
                    echo -e "  $i) $alias_name -> $script"
                    available_scripts+=("$script")
                    ((i++))
                fi
            done

            if [[ ${#available_scripts[@]} -eq 0 ]]; then
                log_info "没有可添加的别名"
            else
                echo ""
                read -p "请输入序号 (多个用空格分隔): " selections
                for selection in $selections; do
                    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#available_scripts[@]} ]]; then
                        local script="${available_scripts[$((selection-1))]}"
                        add_script_alias "$script"
                    fi
                done

                echo ""
                log_warning "请重新打开终端或执行 'source $config_file' 使别名生效"
            fi
            ;;
        3)
            echo ""
            echo -e "${CYAN}配置文件位置: $config_file${NC}"
            if [[ -f "$config_file" ]]; then
                echo -e "${CYAN}项目相关别名：${NC}"
                grep -n "alias.*=" "$config_file" | grep -E "(ma|bc|br|mb|ci|gs|bu|vpn|sv)" 2>/dev/null || echo "  未找到相关别名"
            fi
            ;;
        4)
            return 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 检查脚本更新
# 参数：$1 - 脚本文件名（如 "ci.sh"）
check_script_update() {
    local script_name="$1"
    local token
    
    # 获取token
    token=$(get_gitlab_token)
    
    # 如果没有token，跳过更新检查
    if [[ -z "$token" ]]; then
        return 0
    fi
    
    # 获取当前脚本的绝对路径
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)
    local current_script="$script_dir/$script_name"
    
    # 检查脚本是否存在
    if [[ ! -f "$current_script" ]]; then
        log_error "脚本文件不存在: $current_script"
        return 1
    fi
    
    # 构建API URL
    local script_file_path="sh/$script_name"
    local encoded_project
    encoded_project=$(echo "$GITLAB_PROJECT" | sed 's|/|%2F|g')
    local encoded_file_path
    encoded_file_path=$(echo "$script_file_path" | sed 's|/|%2F|g')
    local api_url="http://${GITLAB_HOST}/api/v4/projects/${encoded_project}/repository/files/${encoded_file_path}?ref=main"
    
    log_info "检查 $script_name 更新..."
    
    # 获取远程文件信息
    local response
    response=$(curl -s --max-time "$API_TIMEOUT" \
        -H "PRIVATE-TOKEN: $token" \
        "$api_url" 2>/dev/null)
    
    if [[ $? -ne 0 || -z "$response" ]]; then
        log_warning "无法获取远程脚本信息，跳过更新检查"
        return 0
    fi
    
    # 检查API响应是否包含错误
    if echo "$response" | grep -q '"message"'; then
        local error_msg
        if command -v jq >/dev/null 2>&1; then
            error_msg=$(echo "$response" | jq -r '.message // "未知错误"')
        else
            error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        fi
        log_warning "API返回错误: $error_msg，跳过更新检查"
        return 0
    fi
    
    # 解析远程文件内容
    local remote_content
    if command -v jq >/dev/null 2>&1; then
        local base64_content
        base64_content=$(echo "$response" | jq -r '.content // empty')
        if [[ -n "$base64_content" && "$base64_content" != "null" && "$base64_content" != "empty" ]]; then
            remote_content=$(echo "$base64_content" | base64 -d 2>/dev/null)
        fi
    else
        local base64_content
        base64_content=$(echo "$response" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$base64_content" ]]; then
            remote_content=$(echo "$base64_content" | base64 -d 2>/dev/null)
        fi
    fi
    
    if [[ -z "$remote_content" ]]; then
        log_warning "无法解析远程脚本内容，跳过更新检查"
        return 0
    fi
    
    # 提取本地脚本版本号
    local local_version=""
    local local_version_line
    local_version_line=$(grep 'readonly.*SCRIPT_VERSION=' "$current_script" | head -1) || true
    if [[ -n "$local_version_line" ]]; then
        local_version=$(echo "$local_version_line" | grep -o '"[^"]*"' | tr -d '"') || true
    fi
    
    # 提取远程脚本版本号
    local remote_version=""
    local remote_version_line
    remote_version_line=$(echo "$remote_content" | grep 'readonly.*SCRIPT_VERSION=' | head -1) || true
    if [[ -n "$remote_version_line" ]]; then
        remote_version=$(echo "$remote_version_line" | grep -o '"[^"]*"' | tr -d '"') || true
    fi
    
    # 如果没有版本号，跳过更新
    if [[ -z "$local_version" || -z "$remote_version" ]]; then
        log_info "$script_name 没有版本号，跳过更新检查"
        return 0
    fi
    
    # 比较版本号
    if [[ "$remote_version" == "$local_version" ]]; then
        log_success "$script_name 已是最新版本 ($local_version)"
        return 0
    fi
    
    # 语义化版本比较
    if version_compare "$local_version" "$remote_version"; then
        log_info "$script_name 本地版本 ($local_version) 比远程版本 ($remote_version) 更新，无需更新"
        return 0
    fi
    
    # 发现新版本，进行更新
    log_info "发现 $script_name 新版本: $remote_version (当前版本: $local_version)"
    log_info "正在自动更新 $script_name..."
    
    # 执行更新
    update_script_file "$current_script" "$remote_content" "$remote_version"
}

# 更新脚本文件
# 参数：$1 - 脚本路径，$2 - 新内容，$3 - 新版本号
update_script_file() {
    local script_path="$1"
    local new_content="$2"
    local new_version="$3"
    
    # 写入新版本到临时文件
    local temp_file="${script_path}.tmp"
    echo "$new_content" > "$temp_file" || {
        log_error "无法创建临时文件"
        return 1
    }
    
    # 验证新脚本的语法
    if ! bash -n "$temp_file" 2>/dev/null; then
        log_error "新脚本语法检查失败，取消更新"
        rm -f "$temp_file"
        return 1
    fi
    
    # 保存原脚本的权限
    local original_permissions
    if command -v stat >/dev/null 2>&1; then
        original_permissions=$(stat -c "%a" "$script_path" 2>/dev/null || stat -f "%A" "$script_path" 2>/dev/null)
    fi
    [[ -z "$original_permissions" ]] && original_permissions="755"
    
    # 替换当前脚本
    if mv "$temp_file" "$script_path"; then
        chmod "$original_permissions" "$script_path" 2>/dev/null || chmod +x "$script_path"
        log_success "$(basename "$script_path") 已更新到版本 $new_version"
        return 0
    else
        log_error "脚本更新失败"
        rm -f "$temp_file"
        return 1
    fi
}

# 下载单个脚本
download_script() {
    local script_name="$1"
    local token

    token=$(get_gitlab_token)
    if [[ -z "$token" ]]; then
        log_error "需要 GitLab Token 才能下载脚本"
        return 1
    fi

    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local script_path="$script_dir/$script_name"

    # 构建API URL
    local script_file_path="sh/$script_name"
    local encoded_project
    encoded_project=$(echo "$GITLAB_PROJECT" | sed 's|/|%2F|g')
    local encoded_file_path
    encoded_file_path=$(echo "$script_file_path" | sed 's|/|%2F|g')
    local api_url="http://${GITLAB_HOST}/api/v4/projects/${encoded_project}/repository/files/${encoded_file_path}?ref=main"

    log_info "正在下载 $script_name..."

    # 获取远程文件信息
    local response
    response=$(curl -s --max-time "$API_TIMEOUT" \
        -H "PRIVATE-TOKEN: $token" \
        "$api_url" 2>/dev/null)

    if [[ $? -ne 0 || -z "$response" ]]; then
        log_error "无法获取远程脚本: $script_name"
        return 1
    fi

    # 检查API响应是否包含错误
    if echo "$response" | grep -q '"message"'; then
        local error_msg
        if command -v jq >/dev/null 2>&1; then
            error_msg=$(echo "$response" | jq -r '.message // "未知错误"')
        else
            error_msg=$(echo "$response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
        fi
        log_error "API返回错误: $error_msg"
        return 1
    fi

    # 解析远程文件内容
    local remote_content
    if command -v jq >/dev/null 2>&1; then
        local base64_content
        base64_content=$(echo "$response" | jq -r '.content // empty')
        if [[ -n "$base64_content" && "$base64_content" != "null" && "$base64_content" != "empty" ]]; then
            remote_content=$(echo "$base64_content" | base64 -d 2>/dev/null)
        fi
    else
        local base64_content
        base64_content=$(echo "$response" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$base64_content" ]]; then
            remote_content=$(echo "$base64_content" | base64 -d 2>/dev/null)
        fi
    fi

    if [[ -z "$remote_content" ]]; then
        log_error "无法解析远程脚本内容: $script_name"
        return 1
    fi

    # 写入文件
    echo "$remote_content" > "$script_path" || {
        log_error "无法写入文件: $script_path"
        return 1
    }

    # 设置可执行权限
    chmod +x "$script_path" 2>/dev/null || {
        log_warning "无法设置可执行权限，请手动执行: chmod +x $script_path"
    }

    log_success "已下载: $script_name"
    return 0
}

# 批量下载所有脚本
download_all_scripts() {
    local token
    token=$(get_gitlab_token)

    if [[ -z "$token" ]]; then
        log_error "需要 GitLab Token 才能下载脚本"
        log_info "请先运行 'sv.sh -c' 配置 GitLab Token"
        return 1
    fi

    log_info "开始下载所有脚本..."

    local scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh")
    local downloaded_count=0
    local new_scripts=()

    for script in "${scripts[@]}"; do
        local script_dir
        script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
        local script_path="$script_dir/$script"

        if [[ ! -f "$script_path" ]]; then
            if download_script "$script"; then
                ((downloaded_count++))
                new_scripts+=("$script")
            fi
        else
            log_info "$script 已存在，跳过下载"
        fi
    done

    if [[ $downloaded_count -gt 0 ]]; then
        log_success "成功下载 $downloaded_count 个新脚本"

        # 显示新脚本信息
        if [[ ${#new_scripts[@]} -gt 0 ]]; then
            echo ""
            log_info "新下载的脚本："
            for script in "${new_scripts[@]}"; do
                local script_name="${script%.sh}"
                case "$script" in
                    "ma.sh") echo -e "  ${GREEN}ma.sh${NC}  - Merge Approvals (合并请求自动处理)" ;;
                    "bc.sh") echo -e "  ${GREEN}bc.sh${NC}  - Branch Clean (Git分支清理)" ;;
                    "br.sh") echo -e "  ${GREEN}br.sh${NC}  - Branch merge Request (分支合并请求管理)" ;;
                    "mb.sh") echo -e "  ${GREEN}mb.sh${NC}  - Maven Batch (项目批量构建)" ;;
                    "ci.sh") echo -e "  ${GREEN}ci.sh${NC}  - CI/CD (流水线管理)" ;;
                    "gs.sh") echo -e "  ${GREEN}gs.sh${NC}  - Git Search (Git提交记录查询)" ;;
                    "bu.sh") echo -e "  ${GREEN}bu.sh${NC}  - Branch Update (Git分支批量更新)" ;;
                    "vpn.sh") echo -e "  ${GREEN}vpn.sh${NC} - VPN (VPN连接管理)" ;;
                esac
            done
        fi

        # 提示设置别名
        echo ""
        log_info "建议运行 'sv.sh -a' 设置脚本别名以便快捷使用"
    else
        log_info "所有脚本都已存在"
    fi
}

# 批量更新所有脚本
update_all_scripts() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

    log_info "开始批量更新所有脚本..."

    local scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh")
    local updated_count=0

    for script in "${scripts[@]}"; do
        if [[ -f "$script_dir/$script" ]]; then
            if check_script_update "$script"; then
                ((updated_count++))
            fi
        else
            log_warning "$script 不存在，可运行 'sv.sh -d' 下载所有脚本"
        fi
    done

    log_success "批量更新完成，共处理 ${#scripts[@]} 个脚本"
}

# 删除单个脚本
delete_script() {
    local script_name="$1"
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local script_path="$script_dir/$script_name"

    if [[ ! -f "$script_path" ]]; then
        log_warning "$script_name 不存在，跳过删除"
        return 1
    fi

    if rm "$script_path" 2>/dev/null; then
        log_success "已删除: $script_name"
        return 0
    else
        log_error "删除失败: $script_name"
        return 1
    fi
}

# 批量删除脚本
delete_scripts() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh")
    local existing_scripts=()

    # 找出存在的脚本
    for script in "${scripts[@]}"; do
        if [[ -f "$script_dir/$script" ]]; then
            existing_scripts+=("$script")
        fi
    done

    if [[ ${#existing_scripts[@]} -eq 0 ]]; then
        log_info "没有可删除的脚本"
        return 0
    fi

    echo -e "${BOLD}${GEAR} 脚本删除管理${NC}"
    echo ""
    echo -e "${CYAN}现有脚本：${NC}"
    for i in "${!existing_scripts[@]}"; do
        local script="${existing_scripts[$i]}"
        local script_name="${script%.sh}"
        case "$script" in
            "ma.sh") echo -e "  $((i+1))) ${RED}ma.sh${NC}  - Merge Approvals (合并请求自动处理)" ;;
            "bc.sh") echo -e "  $((i+1))) ${RED}bc.sh${NC}  - Branch Clean (Git分支清理)" ;;
            "br.sh") echo -e "  $((i+1))) ${RED}br.sh${NC}  - Branch merge Request (分支合并请求管理)" ;;
            "mb.sh") echo -e "  $((i+1))) ${RED}mb.sh${NC}  - Maven Batch (项目批量构建)" ;;
            "ci.sh") echo -e "  $((i+1))) ${RED}ci.sh${NC}  - CI/CD (流水线管理)" ;;
            "gs.sh") echo -e "  $((i+1))) ${RED}gs.sh${NC}  - Git Search (Git提交记录查询)" ;;
            "bu.sh") echo -e "  $((i+1))) ${RED}bu.sh${NC}  - Branch Update (Git分支批量更新)" ;;
            "vpn.sh") echo -e "  $((i+1))) ${RED}vpn.sh${NC} - VPN (VPN连接管理)" ;;
        esac
    done

    echo ""
    echo -e "${CYAN}操作选项：${NC}"
    echo -e "  1) 选择要删除的脚本"
    echo -e "  2) 删除所有脚本"
    echo -e "  3) 返回"
    echo ""

    read -p "请选择 (1-3): " choice
    case $choice in
        1)
            echo ""
            read -p "请输入要删除的脚本序号 (多个用空格分隔): " selections
            local deleted_count=0
            for selection in $selections; do
                if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#existing_scripts[@]} ]]; then
                    local script="${existing_scripts[$((selection-1))]}"
                    if delete_script "$script"; then
                        ((deleted_count++))
                    fi
                else
                    log_warning "无效选择: $selection"
                fi
            done

            if [[ $deleted_count -gt 0 ]]; then
                echo ""
                log_success "成功删除 $deleted_count 个脚本"
            fi
            ;;
        2)
            echo ""
            read -p "确认删除所有脚本？(y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                local deleted_count=0
                for script in "${existing_scripts[@]}"; do
                    if delete_script "$script"; then
                        ((deleted_count++))
                    fi
                done
                echo ""
                log_success "成功删除 $deleted_count 个脚本"
            else
                log_info "已取消删除操作"
            fi
            ;;
        3)
            return 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 检查Token配置
check_token_config() {
    local token="${GITLAB_TOKEN:-}"

    if [[ -z "$token" ]]; then
        echo -e "${BOLD}${ROCKET} SV - Shell Version Manager${NC}"
        echo -e "${YELLOW}${WARNING} 首次使用需要配置 GitLab Token${NC}"
        echo ""
        echo -e "${CYAN}请输入您的 GitLab Personal Access Token:${NC}"
        echo -e "${BLUE}(Token 将自动保存到环境变量中)${NC}"
        echo ""
        read -p "Token: " user_token

        if [[ -n "$user_token" ]]; then
            set_env_variable "GITLAB_TOKEN" "$user_token"
            echo ""
            log_success "Token 配置完成"
            echo ""
            return 0
        else
            log_error "Token 不能为空"
            exit 1
        fi
    fi
    return 0
}

# 检查脚本执行权限
check_scripts_permissions() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local all_scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh" "sv.sh")
    local non_executable_scripts=()

    for script in "${all_scripts[@]}"; do
        local script_path="$script_dir/$script"
        if [[ -f "$script_path" ]] && [[ ! -x "$script_path" ]]; then
            non_executable_scripts+=("$script")
        fi
    done

    if [[ ${#non_executable_scripts[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${WARNING} 检测到以下脚本缺少执行权限：${NC}"
        echo ""
        for script in "${non_executable_scripts[@]}"; do
            case "$script" in
                "ma.sh") echo -e "  ${YELLOW}ma.sh${NC}  - Merge Approvals (合并请求自动处理)" ;;
                "bc.sh") echo -e "  ${YELLOW}bc.sh${NC}  - Branch Clean (Git分支清理)" ;;
                "br.sh") echo -e "  ${YELLOW}br.sh${NC}  - Branch merge Request (分支合并请求管理)" ;;
                "mb.sh") echo -e "  ${YELLOW}mb.sh${NC}  - Maven Batch (项目批量构建)" ;;
                "ci.sh") echo -e "  ${YELLOW}ci.sh${NC}  - CI/CD (流水线管理)" ;;
                "gs.sh") echo -e "  ${YELLOW}gs.sh${NC}  - Git Search (Git提交记录查询)" ;;
                "bu.sh") echo -e "  ${YELLOW}bu.sh${NC}  - Branch Update (Git分支批量更新)" ;;
                "vpn.sh") echo -e "  ${YELLOW}vpn.sh${NC} - VPN (VPN连接管理)" ;;
                "sv.sh") echo -e "  ${YELLOW}sv.sh${NC}  - Shell Version Manager (脚本版本管理)" ;;
            esac
        done
        echo ""

        read -p "是否自动添加执行权限？(Y/n): " permission_confirm
        if [[ "$permission_confirm" =~ ^[Nn]$ ]]; then
            log_info "跳过权限设置"
            return 1
        else
            log_info "开始设置执行权限..."
            local fixed_count=0
            for script in "${non_executable_scripts[@]}"; do
                local script_path="$script_dir/$script"
                if chmod +x "$script_path" 2>/dev/null; then
                    log_success "已设置执行权限: $script"
                    ((fixed_count++))
                else
                    log_error "设置执行权限失败: $script"
                fi
            done

            if [[ $fixed_count -gt 0 ]]; then
                echo ""
                log_success "成功设置 $fixed_count 个脚本的执行权限"
                echo ""
            fi
        fi
    fi
    return 0
}

# 检查脚本完整性
check_scripts_completeness() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local all_scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh")
    local missing_scripts=()

    for script in "${all_scripts[@]}"; do
        if [[ ! -f "$script_dir/$script" ]]; then
            missing_scripts+=("$script")
        fi
    done

    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${WARNING} 检测到缺少以下脚本：${NC}"
        echo ""
        for script in "${missing_scripts[@]}"; do
            case "$script" in
                "ma.sh") echo -e "  ${RED}ma.sh${NC}  - Merge Approvals (合并请求自动处理)" ;;
                "bc.sh") echo -e "  ${RED}bc.sh${NC}  - Branch Clean (Git分支清理)" ;;
                "br.sh") echo -e "  ${RED}br.sh${NC}  - Branch merge Request (分支合并请求管理)" ;;
                "mb.sh") echo -e "  ${RED}mb.sh${NC}  - Maven Batch (项目批量构建)" ;;
                "ci.sh") echo -e "  ${RED}ci.sh${NC}  - CI/CD (流水线管理)" ;;
                "gs.sh") echo -e "  ${RED}gs.sh${NC}  - Git Search (Git提交记录查询)" ;;
                "bu.sh") echo -e "  ${RED}bu.sh${NC}  - Branch Update (Git分支批量更新)" ;;
                "vpn.sh") echo -e "  ${RED}vpn.sh${NC} - VPN (VPN连接管理)" ;;
            esac
        done
        echo ""

        read -p "是否自动下载缺少的脚本？(Y/n): " download_confirm
        if [[ "$download_confirm" =~ ^[Nn]$ ]]; then
            log_info "跳过脚本下载"
            return 1
        else
            log_info "开始下载缺少的脚本..."
            local downloaded_count=0
            for script in "${missing_scripts[@]}"; do
                if download_script "$script"; then
                    ((downloaded_count++))
                fi
            done

            if [[ $downloaded_count -gt 0 ]]; then
                echo ""
                log_success "成功下载 $downloaded_count 个脚本"
                echo ""
            fi
        fi
    fi
    return 0
}

# 检查别名配置
check_aliases_config() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh" "sv.sh")
    local missing_aliases=()

    for script in "${scripts[@]}"; do
        local alias_name="${script%.sh}"
        local script_path="$script_dir/$script"

        if [[ -f "$script_path" ]] && ! check_alias_exists "$alias_name"; then
            missing_aliases+=("$script")
        fi
    done

    if [[ ${#missing_aliases[@]} -gt 0 ]]; then
        echo -e "${YELLOW}${WARNING} 检测到以下脚本缺少别名：${NC}"
        echo ""
        for script in "${missing_aliases[@]}"; do
            local alias_name="${script%.sh}"
            echo -e "  ${YELLOW}$alias_name${NC} -> $script"
        done
        echo ""

        read -p "是否自动配置别名？(Y/n): " alias_confirm
        if [[ "$alias_confirm" =~ ^[Nn]$ ]]; then
            log_info "跳过别名配置"
            return 1
        else
            log_info "开始配置别名..."
            local added_count=0
            for script in "${missing_aliases[@]}"; do
                if add_script_alias "$script"; then
                    ((added_count++))
                fi
            done

            if [[ $added_count -gt 0 ]]; then
                echo ""
                log_success "成功配置 $added_count 个别名"
                local config_file
                config_file=$(get_shell_config_file)
                log_warning "请重新打开终端或执行 'source $config_file' 使别名生效"
                echo ""
            fi
        fi
    fi
    return 0
}

# 智能交互式主流程
smart_interactive_flow() {
    local is_first_run=false

    # 检查是否首次运行（没有token）
    if [[ -z "${GITLAB_TOKEN:-}" ]]; then
        is_first_run=true
        check_token_config
    fi

    # 检查脚本完整性
    check_scripts_completeness

    # 检查脚本执行权限
    check_scripts_permissions

    # 检查别名配置
    check_aliases_config

    # 如果不是首次运行，执行自动更新
    if [[ "$is_first_run" == "false" ]]; then
        echo -e "${CYAN}${INFO} 检查脚本更新...${NC}"
        update_all_scripts
    fi

    echo -e "${GREEN}${SUCCESS} SV 配置和检查完成！${NC}"
    echo ""
    echo -e "${CYAN}${GEAR} 现在您可以使用以下别名快速执行脚本：${NC}"
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local scripts=("ma" "bc" "br" "mb" "ci" "gs" "bu" "vpn" "sv")
    for alias_name in "${scripts[@]}"; do
        if check_alias_exists "$alias_name"; then
            case "$alias_name" in
                "ma") echo -e "  ${GREEN}ma${NC}  - 合并请求自动处理" ;;
                "bc") echo -e "  ${GREEN}bc${NC}  - Git分支清理" ;;
                "br") echo -e "  ${GREEN}br${NC}  - 分支合并请求管理" ;;
                "mb") echo -e "  ${GREEN}mb${NC}  - 项目批量构建" ;;
                "ci") echo -e "  ${GREEN}ci${NC}  - 流水线管理" ;;
                "gs") echo -e "  ${GREEN}gs${NC}  - Git提交记录查询" ;;
                "bu") echo -e "  ${GREEN}bu${NC}  - Git分支批量更新" ;;
                "vpn") echo -e "  ${GREEN}vpn${NC} - VPN连接管理" ;;
                "sv") echo -e "  ${GREEN}sv${NC}  - 脚本版本管理" ;;
            esac
        fi
    done
}

# 主函数 - 当直接运行此脚本时调用
main() {
    case "${1:-}" in
        -h|--help)
            echo -e "${BOLD}${ROCKET} SV - Shell Version Manager (统一脚本版本和配置管理)${NC}"
            echo -e "${CYAN}使用说明：${NC}"
            echo -e "  ${BOLD}智能交互模式：${NC}     sv.sh"
            echo -e "  ${BOLD}更新指定脚本：${NC}     sv.sh [脚本名]"
            echo -e "  ${BOLD}下载所有脚本：${NC}     sv.sh -d"
            echo -e "  ${BOLD}删除脚本：${NC}         sv.sh --delete"
            echo -e "  ${BOLD}配置管理：${NC}         sv.sh -c"
            echo -e "  ${BOLD}别名管理：${NC}         sv.sh -a"
            echo -e "  ${BOLD}版本管理：${NC}         sv.sh -v"
            echo -e "  ${BOLD}权限检查：${NC}         sv.sh --check-permissions"
            echo -e "  ${BOLD}快速升级patch：${NC}    sv.sh --patch"
            echo -e "  ${BOLD}快速升级minor：${NC}    sv.sh --minor"
            echo -e "  ${BOLD}快速升级major：${NC}    sv.sh --major"
            echo -e "  ${BOLD}帮助信息：${NC}         sv.sh -h"
            echo ""
            echo -e "${CYAN}${GEAR} 支持的脚本：${NC}"
            echo -e "  ma.sh  - Merge Approvals (合并请求自动处理)"
            echo -e "  bc.sh  - Branch Clean (Git分支清理)"
            echo -e "  br.sh  - Branch merge Request (分支合并请求管理)"
            echo -e "  mb.sh  - Maven Batch (项目批量构建)"
            echo -e "  ci.sh  - CI/CD (流水线管理)"
            echo -e "  gs.sh  - Git Search (Git提交记录查询)"
            echo -e "  bu.sh  - Branch Update (Git分支批量更新)"
            echo -e "  vpn.sh - VPN (VPN连接管理)"
            echo ""
            echo -e "${CYAN}${GEAR} 环境变量：${NC}"
            echo -e "  GITLAB_TOKEN - GitLab Personal Access Token"
            echo -e "  GITLAB_HOST  - GitLab 服务器地址 (默认: gitlab.example.com)"
            ;;
        -c|--config)
            manage_config
            ;;
        -d|--download)
            download_all_scripts
            ;;
        --delete)
            delete_scripts
            ;;
        -a|--alias)
            manage_aliases
            ;;
        -v|--version)
            manage_versions
            ;;
        --check-permissions)
            check_scripts_permissions
            ;;
        --patch|--minor|--major)
            # 快速版本升级
            local upgrade_type="${1#--}"
            local script_dir
            script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
            local all_scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh" "sv.sh")

            echo -e "${BOLD}${GEAR} 快速升级所有脚本 $upgrade_type 版本${NC}"
            echo ""

            read -p "确认升级所有脚本的 $upgrade_type 版本？(y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                log_info "开始批量升级版本号..."
                local updated_count=0

                for script in "${all_scripts[@]}"; do
                    local script_path="$script_dir/$script"
                    if [[ -f "$script_path" ]]; then
                        local current_version
                        current_version=$(get_script_version "$script_path")

                        if [[ -n "$current_version" ]]; then
                            local new_version
                            new_version=$(upgrade_version "$current_version" "$upgrade_type")
                            if update_script_version "$script_path" "$new_version"; then
                                ((updated_count++))
                            fi
                        fi
                    fi
                done

                echo ""
                log_success "成功升级 $updated_count 个脚本的版本号"
            else
                log_info "已取消升级操作"
            fi
            ;;
        "")
            smart_interactive_flow
            ;;
        *)
            check_script_update "$1"
            ;;
    esac
}

# 获取脚本版本号
get_script_version() {
    local script_path="$1"

    if [[ ! -f "$script_path" ]]; then
        echo ""
        return 1
    fi

    local version_line
    version_line=$(grep 'readonly.*SCRIPT_VERSION=' "$script_path" | head -1) || true
    if [[ -n "$version_line" ]]; then
        echo "$version_line" | grep -o '"[^"]*"' | tr -d '"' || echo ""
    else
        echo ""
    fi
}

# 升级版本号
# 参数：$1 - 当前版本，$2 - 升级类型 (major|minor|patch)
upgrade_version() {
    local current_version="$1"
    local upgrade_type="$2"

    # 解析版本号
    local IFS='.'
    local version_parts=($current_version)
    local major=${version_parts[0]:-0}
    local minor=${version_parts[1]:-0}
    local patch=${version_parts[2]:-0}

    # 移除非数字字符
    major=$(echo "$major" | sed 's/[^0-9]//g')
    minor=$(echo "$minor" | sed 's/[^0-9]//g')
    patch=$(echo "$patch" | sed 's/[^0-9]//g')

    # 如果为空，设为0
    [[ -z "$major" ]] && major=0
    [[ -z "$minor" ]] && minor=0
    [[ -z "$patch" ]] && patch=0

    case "$upgrade_type" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch"|*)
            patch=$((patch + 1))
            ;;
    esac

    echo "${major}.${minor}.${patch}"
}

# 更新脚本版本号
update_script_version() {
    local script_path="$1"
    local new_version="$2"

    if [[ ! -f "$script_path" ]]; then
        log_error "脚本文件不存在: $script_path"
        return 1
    fi

    # 检查是否有版本号定义
    if ! grep -q 'readonly.*SCRIPT_VERSION=' "$script_path"; then
        log_warning "$(basename "$script_path") 没有版本号定义，跳过"
        return 1
    fi

    # 更新版本号
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/readonly SCRIPT_VERSION=\"[^\"]*\"/readonly SCRIPT_VERSION=\"$new_version\"/" "$script_path"
    else
        # Linux
        sed -i "s/readonly SCRIPT_VERSION=\"[^\"]*\"/readonly SCRIPT_VERSION=\"$new_version\"/" "$script_path"
    fi

    if [[ $? -eq 0 ]]; then
        log_success "$(basename "$script_path"): $new_version"
        return 0
    else
        log_error "更新 $(basename "$script_path") 版本号失败"
        return 1
    fi
}

# 版本号管理功能
manage_versions() {
    local script_dir
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    local all_scripts=("ma.sh" "bc.sh" "br.sh" "mb.sh" "ci.sh" "gs.sh" "bu.sh" "vpn.sh" "sv.sh")

    echo -e "${BOLD}${GEAR} 脚本版本号管理${NC}"
    echo ""

    # 显示当前版本号
    echo -e "${CYAN}当前版本号：${NC}"
    local existing_scripts=()
    for script in "${all_scripts[@]}"; do
        local script_path="$script_dir/$script"
        if [[ -f "$script_path" ]]; then
            local current_version
            current_version=$(get_script_version "$script_path")
            if [[ -n "$current_version" ]]; then
                printf "  %-8s %s\n" "${script%.sh}:" "$current_version"
                existing_scripts+=("$script")
            else
                printf "  %-8s %s\n" "${script%.sh}:" "${RED}无版本号${NC}"
            fi
        else
            printf "  %-8s %s\n" "${script%.sh}:" "${GRAY}不存在${NC}"
        fi
    done

    if [[ ${#existing_scripts[@]} -eq 0 ]]; then
        log_error "没有找到可管理版本的脚本"
        return 1
    fi

    echo ""
    echo -e "${CYAN}升级选项：${NC}"
    echo -e "  1) 全部脚本升级 patch 版本 (x.x.x+1)"
    echo -e "  2) 全部脚本升级 minor 版本 (x.x+1.0)"
    echo -e "  3) 全部脚本升级 major 版本 (x+1.0.0)"
    echo -e "  4) 指定脚本升级"
    echo -e "  5) 返回"
    echo ""

    read -p "请选择 (1-5): " choice
    case $choice in
        1|2|3)
            local upgrade_type
            case $choice in
                1) upgrade_type="patch" ;;
                2) upgrade_type="minor" ;;
                3) upgrade_type="major" ;;
            esac

            echo ""
            read -p "确认升级所有脚本的 $upgrade_type 版本？(y/N): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                log_info "开始批量升级版本号..."
                local updated_count=0

                for script in "${existing_scripts[@]}"; do
                    local script_path="$script_dir/$script"
                    local current_version
                    current_version=$(get_script_version "$script_path")

                    if [[ -n "$current_version" ]]; then
                        local new_version
                        new_version=$(upgrade_version "$current_version" "$upgrade_type")
                        if update_script_version "$script_path" "$new_version"; then
                            ((updated_count++))
                        fi
                    fi
                done

                echo ""
                log_success "成功升级 $updated_count 个脚本的版本号"
            else
                log_info "已取消升级操作"
            fi
            ;;
        4)
            echo ""
            echo -e "${CYAN}选择要升级的脚本：${NC}"
            for i in "${!existing_scripts[@]}"; do
                local script="${existing_scripts[$i]}"
                local script_path="$script_dir/$script"
                local current_version
                current_version=$(get_script_version "$script_path")
                printf "  %d) %-8s %s\n" $((i+1)) "${script%.sh}" "$current_version"
            done
            echo ""

            read -p "请输入脚本序号 (多个用空格分隔): " selections
            if [[ -n "$selections" ]]; then
                echo ""
                echo -e "${CYAN}升级类型：${NC}"
                echo -e "  1) patch (x.x.x+1)"
                echo -e "  2) minor (x.x+1.0)"
                echo -e "  3) major (x+1.0.0)"
                echo ""
                read -p "请选择升级类型 (1-3): " type_choice

                local upgrade_type
                case $type_choice in
                    1) upgrade_type="patch" ;;
                    2) upgrade_type="minor" ;;
                    3) upgrade_type="major" ;;
                    *)
                        log_error "无效的升级类型"
                        return 1
                        ;;
                esac

                echo ""
                log_info "开始升级选定脚本的版本号..."
                local updated_count=0

                for selection in $selections; do
                    if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#existing_scripts[@]} ]]; then
                        local script="${existing_scripts[$((selection-1))]}"
                        local script_path="$script_dir/$script"
                        local current_version
                        current_version=$(get_script_version "$script_path")

                        if [[ -n "$current_version" ]]; then
                            local new_version
                            new_version=$(upgrade_version "$current_version" "$upgrade_type")
                            if update_script_version "$script_path" "$new_version"; then
                                ((updated_count++))
                            fi
                        fi
                    else
                        log_warning "无效选择: $selection"
                    fi
                done

                echo ""
                log_success "成功升级 $updated_count 个脚本的版本号"
            else
                log_info "未选择任何脚本"
            fi
            ;;
        5)
            return 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# sv.sh自身的自动更新检查
check_sv_self_update() {
    local token
    token=$(get_gitlab_token)

    if [[ -n "$token" ]]; then
        # 使用子shell避免变量冲突，并抑制输出
        (check_script_update "sv.sh") 2>/dev/null || true
    fi
}

# 如果直接运行此脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 先检查自身更新
    check_sv_self_update
    main "$@"
fi
