#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.6"

set -euo pipefail  # 启用严格模式

#######################################
# 常量定义
#######################################

# 颜色和样式定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[1;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'  # 重置颜色

# Emoji定义
readonly EMOJI_SUCCESS="✅"
readonly EMOJI_ERROR="❌"
readonly EMOJI_WARNING="⚠️"
readonly EMOJI_INFO="ℹ️"
readonly EMOJI_ROCKET="🚀"
readonly EMOJI_BRANCH="🌿"
readonly EMOJI_PROJECT="📁"
readonly EMOJI_ENV="🌍"
readonly EMOJI_MR="🔀"
readonly EMOJI_LOADING="⏳"

# 脚本配置
readonly SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
readonly CONF_FILE="${SCRIPT_DIR}/br.conf"
readonly GITLAB_HOST="gitlab.example.com"
readonly GITLAB_API_BASE="http://${GITLAB_HOST}/api/v4"

# API相关常量
readonly API_TIMEOUT=30
readonly MAX_RETRIES=3

#######################################
# 全局变量
#######################################

# 配置存储结构
declare -a project_names=()    # 项目名称数组
declare -a project_paths=()    # 项目路径数组
declare -a env_names=()        # 环境名称数组
declare -a env_branches=()     # 环境分支数组
declare gitlab_token=""        # GitLab访问令牌
declare gitlab_username=""      # GitLab用户名
declare gitlab_name=""          # GitLab姓名
declare last_update_date=""     # 最后更新日期
declare hook_access_token=""    # 机器人access_token
declare hook_mobiles=""         # @人手机号列表（逗号分隔）
declare hook_message=""         # 消息补充内容

# 自动合并到主分支功能配置
declare auto_merge_to_main_enabled="false"     # 是否启用自动合并到main功能（默认关闭）
declare auto_merge_branch_prefixes="feature,hotfix"  # 触发自动合并的分支前缀列表
declare main_branch_name="main"                # 主分支名称

# 运行时变量
declare -a selected_envs=()      # 用户选择的环境列表
declare -a selected_projects=()  # 用户选择的项目列表
declare selected_branch=""       # 用户选择的源分支
declare temp_auto_merge_enabled="false"  # 临时启用自动合并功能（通过参数控制）
declare temp_main_branch=""      # 临时指定的主分支名称

# MR结果收集（使用普通数组）
declare -a mr_env_names=()       # 环境名称列表
declare -a mr_urls=()            # 对应的URL列表
declare -a mr_statuses=()        # 对应的状态列表

#######################################
# 工具函数
#######################################

# 打印错误信息并退出
# 参数：$1 - 错误信息
print_error_and_exit() {
    local message="$1"
    echo -e "${RED}${EMOJI_ERROR} 错误: ${message}${NC}" >&2
    exit 1
}

# 打印错误信息（不退出）
# 参数：$1 - 错误信息
print_error() {
    local message="$1"
    echo -e "${RED}${EMOJI_ERROR} 错误: ${message}${NC}" >&2
}

# 打印成功信息
# 参数：$1 - 成功信息
print_success() {
    local message="$1"
    echo -e "${GREEN}${EMOJI_SUCCESS} ${message}${NC}"
}

# 打印警告信息
# 参数：$1 - 警告信息
print_warning() {
    local message="$1"
    echo -e "${YELLOW}${EMOJI_WARNING} ${message}${NC}"
}

# 打印信息
# 参数：$1 - 信息内容
print_info() {
    local message="$1"
    echo -e "${BLUE}${EMOJI_INFO} ${message}${NC}"
}

# 打印步骤标题
# 参数：$1 - 步骤标题
print_step() {
    local message="$1"
    echo -e "\n${WHITE}${EMOJI_ROCKET} ${message}${NC}"
    echo -e "${GRAY}──────────────────────────────────────────────────${NC}"
}

# 打印项目信息
# 参数：$1 - 项目名称
print_project() {
    local project="$1"
    echo -e "${CYAN}${EMOJI_PROJECT} ${project}${NC}"
}

# 打印环境信息
# 参数：$1 - 环境名称
print_env() {
    local env="$1"
    echo -e "${PURPLE}${EMOJI_ENV} ${env}${NC}"
}

# 打印分支信息
# 参数：$1 - 分支名称
print_branch() {
    local branch="$1"
    echo -e "${GREEN}${EMOJI_BRANCH} ${branch}${NC}"
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

#######################################
# 脚本自动更新函数
#######################################

# 通用脚本自动更新函数
# 参数：$1 - 脚本文件路径（相对于当前脚本），$2 - GitLab项目路径，$3 - GitLab Token，$4+ - 传递给重新执行脚本的参数
# 示例：auto_update_script "sh/br.sh" "project/project-dev" "$gitlab_token" "$@"
auto_update_script() {
    local script_file_path="${1:-}"
    local gitlab_project="${2:-}"
    local token="${3:-}"
    shift 3  # 移除前三个参数，剩下的都是要传递给重新执行脚本的参数

    # 参数验证
    [[ -n "$script_file_path" ]] || {
        print_error "脚本文件路径不能为空"
        return 1
    }

    [[ -n "$gitlab_project" ]] || {
        print_error "GitLab项目路径不能为空"
        return 1
    }

    [[ -n "$token" ]] || {
        print_error "GitLab Token不能为空"
        return 1
    }

    # 获取当前脚本的绝对路径
    local current_script
    current_script=$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)/$(basename "${BASH_SOURCE[1]}")

    # 构建API URL（URL编码项目路径和文件路径）
    local encoded_project
    encoded_project=$(echo "$gitlab_project" | sed 's|/|%2F|g')
    local encoded_file_path
    encoded_file_path=$(echo "$script_file_path" | sed 's|/|%2F|g')
    local api_url="http://${GITLAB_HOST}/api/v4/projects/${encoded_project}/repository/files/${encoded_file_path}?ref=main"

    print_info "检查脚本更新..."



    # 获取远程文件信息
    local response
    response=$(curl -s --max-time "$API_TIMEOUT" \
        -H "PRIVATE-TOKEN: $token" \
        "$api_url" 2>/dev/null)

    if [[ $? -ne 0 || -z "$response" ]]; then
        print_warning "无法获取远程脚本信息，跳过更新检查"
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
        print_warning "API返回错误: $error_msg，跳过更新检查"
        return 0
    fi

    # 解析远程文件内容
    local remote_content
    if command -v jq >/dev/null 2>&1; then
        # 使用jq解析
        local base64_content
        base64_content=$(echo "$response" | jq -r '.content // empty')


        if [[ -n "$base64_content" && "$base64_content" != "null" && "$base64_content" != "empty" ]]; then
            remote_content=$(echo "$base64_content" | base64 -d 2>/dev/null)
        fi
    else
        # 备用解析方案
        local base64_content
        base64_content=$(echo "$response" | grep -o '"content":"[^"]*"' | cut -d'"' -f4)


        if [[ -n "$base64_content" ]]; then
            remote_content=$(echo "$base64_content" | base64 -d 2>/dev/null)
        fi
    fi

    if [[ -z "$remote_content" ]]; then
        print_warning "无法解析远程脚本内容，跳过更新检查"
        return 0
    fi

    # 提取远程脚本版本号
    local remote_version=""
    local version_line

    # 使用更安全的方式提取版本号
    version_line=$(echo "$remote_content" | grep 'readonly SCRIPT_VERSION=' | head -1) || true

    if [[ -n "$version_line" ]]; then
        remote_version=$(echo "$version_line" | grep -o '"[^"]*"' | tr -d '"') || true
    fi

    if [[ -z "$remote_version" ]]; then
        # 如果远程脚本没有版本号，说明远程是旧版本，当前本地版本更新
        print_info "本地脚本版本 ($SCRIPT_VERSION) 比远程脚本更新，无需更新"
        return 0
    fi

    # 比较版本号
    if [[ "$remote_version" == "$SCRIPT_VERSION" ]]; then
        print_success "脚本已是最新版本 ($SCRIPT_VERSION)"
        return 0
    fi

    # 语义化版本比较
    if version_compare "$SCRIPT_VERSION" "$remote_version"; then
        print_info "本地脚本版本 ($SCRIPT_VERSION) 比远程版本 ($remote_version) 更新，无需更新"
        return 0
    fi

    # 发现新版本，进行更新
    print_info "发现新版本: $remote_version (当前版本: $SCRIPT_VERSION)"
    print_info "正在自动更新脚本..."

    # 写入新版本到临时文件
    local temp_file="${current_script}.tmp"
    echo "$remote_content" > "$temp_file" || {
        print_error "无法创建临时文件"
        return 1
    }

    # 验证新脚本的语法
    if ! bash -n "$temp_file" 2>/dev/null; then
        print_error "新脚本语法检查失败，取消更新"
        rm -f "$temp_file"
        return 1
    fi

    # 保存原脚本的权限
    local original_permissions
    if command -v stat >/dev/null 2>&1; then
        # 使用stat命令获取权限（适用于大多数系统）
        original_permissions=$(stat -c "%a" "$current_script" 2>/dev/null || stat -f "%A" "$current_script" 2>/dev/null)
    fi

    # 如果无法获取权限，使用默认的可执行权限
    [[ -z "$original_permissions" ]] && original_permissions="755"

    # 替换当前脚本
    if mv "$temp_file" "$current_script"; then
        # 恢复原有权限
        chmod "$original_permissions" "$current_script" 2>/dev/null || chmod +x "$current_script"

        print_success "脚本已更新到版本 $remote_version"
        print_info "请重新执行脚本以使用新版本："
        echo -e "${CYAN}  $current_script${NC}"

        # 退出当前脚本，让用户手动重新执行
        exit 0
    else
        print_error "脚本更新失败"
        rm -f "$temp_file"
        return 1
    fi
}

# br脚本专用的自动更新函数
# 使用当前配置的GitLab Token和项目信息
# 参数：传递给重新执行脚本的所有参数
check_and_update_br_script() {
    # 检查是否有GitLab Token
    [[ -n "$gitlab_token" ]] || return 0

    # 调用通用更新函数，传递所有参数
    auto_update_script "sh/br.sh" "project/project-dev" "$gitlab_token" "$@"
}

#######################################
# API调用封装函数
#######################################

# 通用的GitLab API调用函数
# 参数：$1 - HTTP方法(GET/POST), $2 - API路径, $3 - 请求体(可选)
# 输出：API响应内容
gitlab_api_call() {
    local method="${1:-GET}"
    local api_path="$2"
    local data="${3:-}"

    [[ -n "$gitlab_token" ]] || {
        print_error "GitLab Token 未配置"
        return 1
    }

    local url="${GITLAB_API_BASE}${api_path}"
    local response
    local retry_count=0

    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        if [[ "$method" == "POST" && -n "$data" ]]; then
            response=$(curl -s --max-time "$API_TIMEOUT" \
                -X POST \
                -H "PRIVATE-TOKEN: $gitlab_token" \
                -H "Content-Type: application/x-www-form-urlencoded" \
                "$url" \
                --data "$data" 2>/dev/null)
        else
            response=$(curl -s --max-time "$API_TIMEOUT" \
                -H "PRIVATE-TOKEN: $gitlab_token" \
                "$url" 2>/dev/null)
        fi

        # 检查curl是否成功
        if [[ $? -eq 0 && -n "$response" ]]; then
            echo "$response"
            return 0
        fi

        ((retry_count++))
        [[ $retry_count -lt $MAX_RETRIES ]] && sleep 1
    done

    print_error "API调用失败: $url (重试 $MAX_RETRIES 次后仍失败)"
    return 1
}

# 获取项目ID
# 参数：$1 - 项目名称
# 输出：项目ID
get_project_id() {
    local project_name="$1"
    local response

    response=$(gitlab_api_call "GET" "/projects/project%2F${project_name}")
    [[ $? -eq 0 ]] || return 1

    if command -v jq >/dev/null 2>&1; then
        echo "$response" | jq -r '.id // empty'
    else
        echo "$response" | grep -o '"id":[^,}]*' | head -1 | cut -d':' -f2 | tr -d ' "'
    fi
}

# 获取GitLab用户信息
# 输出：设置全局变量 gitlab_username 和 gitlab_name
fetch_gitlab_username() {
    local response

    response=$(gitlab_api_call "GET" "/user")
    [[ $? -eq 0 ]] || return 1

    if command -v jq >/dev/null 2>&1; then
        local username name
        username=$(echo "$response" | jq -r '.username // empty')
        name=$(echo "$response" | jq -r '.name // empty')

        if [[ -n "$username" && "$username" != "null" ]]; then
            gitlab_username="$username"
            [[ -n "$name" && "$name" != "null" ]] && gitlab_name="$name"
            save_config
            return 0
        fi
    else
        if echo "$response" | grep -q '"username"'; then
            local username name
            username=$(echo "$response" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
            name=$(echo "$response" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
            if [[ -n "$username" ]]; then
                gitlab_username="$username"
                [[ -n "$name" ]] && gitlab_name="$name"
                save_config
                return 0
            fi
        fi
    fi

    return 1
}

# 解析JSON响应的通用函数
# 参数：$1 - JSON字符串, $2 - 字段名, $3 - 上下文(可选，用于复杂解析)
# 输出：字段值
parse_json_field() {
    local json="$1"
    local field="$2"
    local context="${3:-}"

    if command -v jq >/dev/null 2>&1; then
        echo "$json" | jq -r ".${field} // empty"
    else
        # 备用解析方案，针对不同字段类型进行优化
        case "$field" in
            "web_url")
                # 对于web_url，需要确保获取的是MR的URL而不是用户的URL
                # MR的web_url通常在JSON的顶层，且包含merge_requests路径
                parse_mr_web_url "$json"
                ;;
            "message")
                # 处理可能是数组的message字段
                parse_message_field "$json"
                ;;
            "changes_count")
                # 处理数字字段，可能带引号
                echo "$json" | grep -o "\"${field}\":[^,}]*" | cut -d':' -f2 | tr -d ' "'
                ;;
            *)
                # 默认字符串字段解析，使用更灵活的正则表达式
                echo "$json" | grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/"
                ;;
        esac
    fi
}

# 专门解析MR的web_url（备用方案）
# 参数：$1 - JSON字符串
# 输出：MR的web_url
parse_mr_web_url() {
    local json="$1"

    # 首先清理JSON，移除换行符和多余空格
    local clean_json
    clean_json=$(echo "$json" | tr -d '\n\r\t' | sed 's/[[:space:]]\+/ /g')

    # 方法1: 查找包含merge_requests的URL（最准确的方法）
    local mr_url
    mr_url=$(echo "$clean_json" | sed -n 's/.*"web_url"[[:space:]]*:[[:space:]]*"\([^"]*merge_requests[^"]*\)".*/\1/p' | head -1)

    if [[ -n "$mr_url" ]]; then
        echo "$mr_url"
        return 0
    fi

    # 方法2: 基于GitLab API v4响应结构的智能解析
    # 提取第一个出现的web_url（通常是顶级对象的）
    local top_level_url
    top_level_url=$(echo "$clean_json" | sed -n 's/.*"web_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)

    # 验证这个URL是否看起来像MR的URL或项目URL
    if [[ -n "$top_level_url" ]]; then
        # 如果包含merge_requests路径，肯定是MR的URL
        if [[ "$top_level_url" =~ merge_requests ]]; then
            echo "$top_level_url"
            return 0
        fi
        # 如果是项目URL格式（包含至少两个路径段），也可能是MR的URL
        if [[ "$top_level_url" =~ ^https?://[^/]+/[^/]+/[^/]+ ]]; then
            echo "$top_level_url"
            return 0
        fi
    fi

    # 方法3: 基于URL模式的过滤
    # MR的URL通常包含项目路径，而用户URL通常只是用户名
    local all_urls filtered_url
    all_urls=$(echo "$clean_json" | sed -n 's/.*"web_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/gp')

    # 选择包含至少两个路径段的URL（项目URL的特征）
    filtered_url=$(echo "$all_urls" | grep -E "^[^/]+//[^/]+/[^/]+/[^/]+" | head -1)

    if [[ -n "$filtered_url" ]]; then
        echo "$filtered_url"
        return 0
    fi

    # 方法4: 最后的备用方案
    echo "$all_urls" | head -1
}

# 专门解析message字段（备用方案）
# 参数：$1 - JSON字符串
# 输出：错误消息
parse_message_field() {
    local json="$1"

    # 检查message是否是数组格式
    if echo "$json" | grep -q '"message":[[:space:]]*\['; then
        # 数组格式：提取所有消息并用逗号连接
        local array_content
        array_content=$(echo "$json" | sed -n 's/.*"message":[[:space:]]*\[\([^]]*\)\].*/\1/p')

        if [[ -n "$array_content" ]]; then
            # 清理引号和格式化
            echo "$array_content" | sed 's/"//g' | sed 's/,/, /g' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
        else
            echo "解析错误消息失败"
        fi
    else
        # 字符串格式：直接提取
        local message
        message=$(echo "$json" | grep -o '"message"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

        if [[ -n "$message" ]]; then
            echo "$message"
        else
            # 尝试提取error字段作为备用
            echo "$json" | grep -o '"error"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"error"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
        fi
    fi
}

# 验证和清理JSON响应
# 参数：$1 - JSON字符串
# 输出：清理后的JSON或错误信息
validate_json_response() {
    local json="$1"

    # 基本的JSON格式验证
    if [[ -z "$json" ]]; then
        echo "空响应"
        return 1
    fi

    # 检查是否是有效的JSON开始
    if [[ ! "$json" =~ ^[[:space:]]*[\{\[] ]]; then
        echo "无效的JSON格式"
        return 1
    fi

    # 移除可能的控制字符和多余空白
    echo "$json" | tr -d '\r\n\t' | sed 's/[[:space:]]\+/ /g'
}

# 专门处理GitLab API错误响应
# 参数：$1 - JSON响应
# 输出：格式化的错误信息
parse_gitlab_error() {
    local json="$1"

    # 验证JSON
    local clean_json
    clean_json=$(validate_json_response "$json")
    [[ $? -eq 0 ]] || {
        echo "API响应格式错误: $clean_json"
        return 1
    }

    # 尝试解析不同类型的错误信息
    local error_msg

    # 1. 标准的message字段
    error_msg=$(parse_message_field "$clean_json")

    if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
        echo "$error_msg"
        return 0
    fi

    # 2. error字段
    error_msg=$(parse_json_field "$clean_json" "error")

    if [[ -n "$error_msg" && "$error_msg" != "null" ]]; then
        echo "$error_msg"
        return 0
    fi

    # 3. 检查HTTP错误状态
    if echo "$clean_json" | grep -q '"status":[45][0-9][0-9]'; then
        local status
        status=$(parse_json_field "$clean_json" "status")
        echo "HTTP错误 $status"
        return 0
    fi

    # 4. 默认错误信息
    echo "未知的API错误"
    return 1
}

#######################################
# 配置管理函数
#######################################

# 初始化默认环境配置
# 在配置文件为空或没有环境配置时自动添加十个环境
init_default_environments() {
    # 如果已经有环境配置，则跳过
    [[ "${#env_names[@]}" -eq 0 ]] || return 0

    print_info "检测到没有环境配置，正在初始化默认环境..."

    # 定义默认环境配置（使用占位符分支名）
    local default_envs=(
        "灰度1:gray1/000000"
        "灰度2:gray2/000000"
        "灰度3:gray3/000000"
        "灰度4:gray4/000000"
        "灰度5:gray5/000000"
        "灰度6:gray6/000000"
        "预发1:release/0.0.preissue_000000"
        "预发2:release/0.0.preissue2_000000"
        "vip:vip/000000"
        "线上:release/0.0.0"
    )

    # 添加默认环境
    for env_config in "${default_envs[@]}"; do
        IFS=':' read -r env_name branch_name <<< "$env_config"
        env_names+=("$env_name")
        env_branches+=("$branch_name")
    done

    print_success "已初始化 ${#default_envs[@]} 个默认环境"
    save_config
}

# 加载配置文件（仅在环境变量不存在时使用）
# 从配置文件中读取项目、环境和Token信息
load_config_from_file() {
    # 如果配置文件不存在则创建
    [[ -f "$CONF_FILE" ]] || touch "$CONF_FILE"

    # 逐行解析配置文件
    while IFS= read -r line; do
        # 跳过空行和注释行
        [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]] || continue

        if [[ $line =~ ^project_([^=]+)=\"(.*)\"$ ]]; then
            # 解析项目配置
            local name="${BASH_REMATCH[1]}"
            local path="${BASH_REMATCH[2]}"
            _update_project_config "$name" "$path"
        elif [[ $line =~ ^env_([^=]+)=\"(.*)\"$ ]]; then
            # 解析环境配置
            local name="${BASH_REMATCH[1]}"
            local branch="${BASH_REMATCH[2]}"
            _update_env_config "$name" "$branch"
        elif [[ $line =~ ^gitlab_token=\"(.*)\"$ ]]; then
            # 解析GitLab Token
            gitlab_token="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^gitlab_username=\"(.*)\"$ ]]; then
            # 解析GitLab Username
            gitlab_username="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^gitlab_name=\"(.*)\"$ ]]; then
            # 解析GitLab Name
            gitlab_name="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^last_update_date=\"(.*)\"$ ]]; then
            # 解析最后更新日期
            last_update_date="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^hook_access_token=\"(.*)\"$ ]]; then
            # 解析机器人access_token
            hook_access_token="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^hook_mobiles=\"(.*)\"$ ]]; then
            # 解析@人手机号
            hook_mobiles="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^hook_message=\"(.*)\"$ ]]; then
            # 解析消息补充内容
            hook_message="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^auto_merge_to_main_enabled=\"(.*)\"$ ]]; then
            # 解析自动合并到main功能开关
            auto_merge_to_main_enabled="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^auto_merge_branch_prefixes=\"(.*)\"$ ]]; then
            # 解析自动合并分支前缀列表
            auto_merge_branch_prefixes="${BASH_REMATCH[1]}"
        elif [[ $line =~ ^main_branch_name=\"(.*)\"$ ]]; then
            # 解析主分支名称
            main_branch_name="${BASH_REMATCH[1]}"
        fi
    done < "$CONF_FILE"
}

# 检查是否有配置文件中的配置需要迁移
has_config_in_file() {
    [[ -f "$CONF_FILE" ]] || return 1

    # 检查是否有非注释的配置行
    grep -q '^[^#]*=' "$CONF_FILE" 2>/dev/null
}

# 统一的配置加载函数
# 优先级：环境变量 > 配置文件
load_config() {
    # 首先尝试从环境变量加载
    load_all_config_from_env

    # 检查是否有环境变量配置
    local has_env_config=false
    if [[ -n "${!ENV_GITLAB_TOKEN:-}" ]] || [[ "${#project_names[@]}" -gt 0 ]] || [[ "${#env_names[@]}" -gt 0 ]]; then
        has_env_config=true
        print_info "使用环境变量中的配置"
    fi

    # 检查配置文件中是否还有未迁移的配置
    local need_migration=false
    if has_config_in_file; then
        # 临时加载配置文件内容来检查
        local temp_project_names=()
        local temp_project_paths=()
        local temp_env_names=()
        local temp_env_branches=()
        local temp_gitlab_username=""
        local temp_gitlab_name=""
        local temp_last_update_date=""
        local temp_hook_access_token=""
        local temp_hook_mobiles=""
        local temp_hook_message=""

        # 解析配置文件检查是否有项目或其他配置
        while IFS= read -r line; do
            [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]] || continue
            if [[ $line =~ ^project_([^=]+)=\"(.*)\"$ ]]; then
                temp_project_names+=("${BASH_REMATCH[1]}")
                temp_project_paths+=("${BASH_REMATCH[2]}")
                need_migration=true
            elif [[ $line =~ ^env_([^=]+)=\"(.*)\"$ ]] && [[ "${#env_names[@]}" -eq 0 ]]; then
                need_migration=true
            elif [[ $line =~ ^gitlab_username=\"(.*)\"$ ]] && [[ -z "${!ENV_GITLAB_USERNAME:-}" ]]; then
                need_migration=true
            elif [[ $line =~ ^gitlab_name=\"(.*)\"$ ]] && [[ -z "${!ENV_GITLAB_NAME:-}" ]]; then
                need_migration=true
            elif [[ $line =~ ^(last_update_date|hook_access_token|hook_mobiles|hook_message)=\"(.*)\"$ ]]; then
                need_migration=true
            fi
        done < "$CONF_FILE"
    fi

    # 如果需要迁移，则从配置文件加载并迁移
    if [[ "$need_migration" == "true" ]]; then
        print_info "检测到配置文件中有未迁移的配置，正在加载并迁移..."
        load_config_from_file

        # 迁移到环境变量
        migrate_config_to_env
    fi

    # 如果没有环境配置，初始化默认环境
    if [[ "${#env_names[@]}" -eq 0 ]]; then
        init_default_environments
    fi
}

# 迁移配置文件到环境变量
migrate_config_to_env() {
    print_info "正在将配置迁移到环境变量..."

    # 保存到环境变量
    save_all_config_to_env

    # 询问是否删除配置文件
    if [[ -n "${CONF_FILE:-}" && -f "$CONF_FILE" ]]; then
        print_success "配置已成功迁移到环境变量"
        print_info "配置文件 $CONF_FILE 现在可以删除"
        print_warning "建议执行 'source $(get_shell_config_file)' 使环境变量永久生效"

        echo -n -e "${BLUE}${EMOJI_INFO} 是否删除配置文件 $CONF_FILE ?(y/n): ${NC}"
        read delete_confirm

        case "$delete_confirm" in
            [Yy]|[Yy][Ee][Ss])
                if rm -f "$CONF_FILE"; then
                    print_success "配置文件已删除"
                else
                    print_error "删除配置文件失败"
                fi
                ;;
            *)
                print_info "保留配置文件，但脚本将优先使用环境变量"
                ;;
        esac
    fi
}

# 通用的数组更新函数
# 参数：$1 - 数组名前缀(project/env), $2 - 名称, $3 - 值
_update_config_array() {
    local prefix="$1"
    local name="$2"
    local value="$3"

    case "$prefix" in
        "project")
            # 查找是否已存在
            local found=false
            for i in "${!project_names[@]}"; do
                if [[ "${project_names[$i]}" == "$name" ]]; then
                    project_paths[$i]="$value"
                    found=true
                    break
                fi
            done

            # 如果不存在则添加
            if [[ "$found" == "false" ]]; then
                project_names+=("$name")
                project_paths+=("$value")
            fi
            ;;
        "env")
            # 查找是否已存在
            local found=false
            for i in "${!env_names[@]}"; do
                if [[ "${env_names[$i]}" == "$name" ]]; then
                    env_branches[$i]="$value"
                    found=true
                    break
                fi
            done

            # 如果不存在则添加
            if [[ "$found" == "false" ]]; then
                env_names+=("$name")
                env_branches+=("$value")
            fi
            ;;
    esac
}

# 更新项目配置（内部函数）
# 参数：$1 - 项目名称，$2 - 项目路径
_update_project_config() {
    _update_config_array "project" "$1" "$2"
}

# 更新环境配置（内部函数）
# 参数：$1 - 环境名称，$2 - 分支名称
_update_env_config() {
    _update_config_array "env" "$1" "$2"
}

# 保存配置（现在保存到环境变量）
# 将当前配置保存到环境变量
save_config() {
    save_all_config_to_env
}

#######################################
# 自动环境分支更新函数
#######################################

# 检查是否需要每日更新
# 返回：0 - 需要更新，1 - 不需要更新
check_daily_update() {
    local today=$(date '+%Y-%m-%d')

    # 如果没有记录更新日期或者日期不是今天，则需要更新
    [[ "$last_update_date" == "$today" ]] && return 1
    return 0
}

# 获取项目的远程分支列表
# 参数：$1 - 项目路径
# 输出：分支列表，每行一个分支名
fetch_remote_branches() {
    local project_path="${1:-}"

    [[ -n "$project_path" ]] || {
        print_error "项目路径不能为空"
        return 1
    }

    [[ -d "$project_path" ]] || {
        print_error "项目路径不存在: $project_path"
        return 1
    }

    # 切换到项目目录
    cd "$project_path" || {
        print_error "无法切换到项目目录: $project_path"
        return 1
    }

    # 检查是否是Git仓库
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "不是有效的Git仓库: $project_path"
        return 1
    fi

    # 使用git ls-remote获取远程分支（不需要本地fetch）
    git ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's/refs\/heads\///' || {
        print_error "无法获取远程分支列表，请检查网络连接和仓库权限"
        return 1
    }
}

# 环境分支匹配规则配置
# 返回：环境名称对应的分支匹配模式和排序方式
get_env_branch_pattern() {
    local env_name="$1"

    case "$env_name" in
        "灰度"[1-6])
            local gray_num="${env_name#灰度}"
            echo "^gray${gray_num}/[0-9]{6}$|sort -t'/' -k2 -n"
            ;;
        "预发1")
            echo "^release/[0-9]+\.[0-9]+\.preissue_[0-9]{6}$|sort -t'_' -k2 -n"
            ;;
        "预发2")
            echo "^release/[0-9]+\.[0-9]+\.preissue2_[0-9]{6}$|sort -t'_' -k2 -n"
            ;;
        "vip")
            echo "^vip/[0-9]{6}$|sort -t'/' -k2 -n"
            ;;
        "线上")
            echo "^release/[0-9]+\.[0-9]+\.[0-9]+$|sort -V"
            ;;
        *)
            return 1
            ;;
    esac
}

# 从分支列表中找到指定环境的最新分支
# 参数：$1 - 环境名称，$2 - 分支列表
# 输出：最新的分支名称
find_latest_branch_for_env() {
    local env_name="${1:-}"
    local branches="${2:-}"

    local pattern_and_sort
    pattern_and_sort=$(get_env_branch_pattern "$env_name")
    [[ $? -eq 0 ]] || return 1

    local pattern sort_cmd
    IFS='|' read -r pattern sort_cmd <<< "$pattern_and_sort"

    # 使用 eval 来正确执行包含引号的排序命令
    echo "$branches" | grep -E "$pattern" | eval "$sort_cmd" | tail -1
}

# 自动更新环境分支配置
# 参数：$1 - 项目名称（可选，如果不提供则使用第一个配置的项目）
auto_update_env_branches() {
    local target_project_name="${1:-}"
    local updated_count=0
    local total_envs=${#env_names[@]}
    local skipped_count=0

    # 如果没有指定项目，使用第一个配置的项目
    if [[ -z "$target_project_name" && "${#project_names[@]}" -gt 0 ]]; then
        target_project_name="${project_names[0]}"
    fi

    [[ -n "$target_project_name" ]] || {
        print_warning "没有可用的项目进行分支更新"
        return 1
    }

    # 获取项目路径
    local target_project_path
    target_project_path=$(get_project_path "$target_project_name")

    [[ -n "$target_project_path" ]] || {
        print_error "未找到项目 '$target_project_name' 的路径配置"
        return 1
    }

    print_info "正在从项目 '$target_project_name' ($target_project_path) 获取最新环境分支..."

    # 获取远程分支列表
    local remote_branches
    remote_branches=$(fetch_remote_branches "$target_project_path")

    [[ -n "$remote_branches" ]] || {
        print_error "无法获取项目 '$target_project_name' 的远程分支列表"
        return 1
    }

    local branch_count
    branch_count=$(echo "$remote_branches" | wc -l)
    print_info "获取到 $branch_count 个远程分支"

    # 遍历所有环境，检查是否有更新
    for i in "${!env_names[@]}"; do
        local env_name="${env_names[$i]}"
        local current_branch="${env_branches[$i]}"
        local latest_branch

        latest_branch=$(find_latest_branch_for_env "$env_name" "$remote_branches")

        if [[ -z "$latest_branch" ]]; then
            print_warning "环境 '$env_name' 未找到匹配的远程分支"
            ((skipped_count++))
        elif [[ "$latest_branch" != "$current_branch" ]]; then
            print_success "发现环境 '$env_name' 有更新: $current_branch -> $latest_branch"
            env_branches[$i]="$latest_branch"
            ((updated_count++))
        else
            print_info "环境 '$env_name' 已是最新版本: $current_branch"
        fi
    done

    # 更新最后更新日期
    last_update_date=$(date '+%Y-%m-%d')

    # 显示更新结果摘要
    if [[ $updated_count -gt 0 ]]; then
        print_success "已更新 $updated_count/$total_envs 个环境分支"
        if [[ $skipped_count -gt 0 ]]; then
            print_warning "跳过 $skipped_count 个环境（未找到匹配分支）"
        fi
        save_config
    else
        print_info "所有环境分支已是最新版本"
        if [[ $skipped_count -gt 0 ]]; then
            print_warning "跳过 $skipped_count 个环境（未找到匹配分支）"
        fi
        # 即使没有更新也要保存配置以更新时间戳
        save_config
    fi

    return 0
}

# 自动检测并添加同目录的Git项目
# 参数：$1 - 已添加项目的路径
auto_detect_sibling_projects() {
    local added_project_path="$1"

    [[ -n "$added_project_path" ]] || return 0
    [[ -d "$added_project_path" ]] || return 0

    # 获取项目的父目录
    local parent_dir
    parent_dir=$(dirname "$added_project_path")

    [[ -d "$parent_dir" ]] || return 0

    print_info "正在检测 '$parent_dir' 目录下的其他Git项目..."

    local detected_count=0
    local added_count=0

    # 遍历父目录下的所有子目录
    for dir in "$parent_dir"/*; do
        [[ -d "$dir" ]] || continue

        # 跳过已添加的项目
        [[ "$dir" != "$added_project_path" ]] || continue

        # 检查是否是Git仓库
        if [[ -d "$dir/.git" ]] || (cd "$dir" && git rev-parse --git-dir >/dev/null 2>&1); then
            ((detected_count++))

            # 获取目录名作为项目名
            local project_name
            project_name=$(basename "$dir")

            # 检查项目是否已存在
            if ! _project_exists "$project_name"; then
                project_names+=("$project_name")
                project_paths+=("$dir")
                print_success "自动添加项目: $project_name -> $dir"
                ((added_count++))
            else
                print_info "项目 '$project_name' 已存在，跳过"
            fi
        fi
    done

    if [[ $detected_count -gt 0 ]]; then
        if [[ $added_count -gt 0 ]]; then
            print_success "检测到 $detected_count 个Git项目，自动添加了 $added_count 个新项目"
            save_config
        else
            print_info "检测到 $detected_count 个Git项目，但都已存在于配置中"
        fi
    else
        print_info "未在同目录下检测到其他Git项目"
    fi
}

#######################################
# 验证和帮助函数
#######################################

# 验证 GitLab Token 是否已配置
validate_gitlab_token() {
    [[ -n "$gitlab_token" ]] || print_error_and_exit "GitLab Token 未配置，请先执行 br.sh -t <token> 进行配置"
}

# 验证项目配置是否存在
validate_project_config() {
    [[ "${#project_names[@]}" -gt 0 ]] || print_error_and_exit "没有配置项目，请先执行 br.sh -p 初始化项目"
}

# 验证环境配置是否存在
validate_env_config() {
    [[ "${#env_names[@]}" -gt 0 ]] || print_error_and_exit "没有配置环境，请先执行 br.sh -e 初始化环境"
}

# 显示帮助信息
show_help() {
    cat << EOF
$(print_info "GitLab 分支合并请求管理工具")

$(print_info "使用方法:")
  br.sh [选项]

$(print_info "选项:")
  -h           显示帮助信息
  -e [环境配置] 初始化/修改环境配置（格式：环境名称:分支名称）
  -p [项目配置] 初始化/修改项目配置（格式：项目名称:项目路径）
  -t [token]   设置/修改 GitLab Token（保存到环境变量）
  -u [项目名]  手动更新环境分支（可选指定项目名，默认使用第一个项目）
  -us          手动检查脚本更新
  -hk [Hook配置] 配置机器人Hook（格式：token:access_token 或 mobiles:手机号 或 message:消息）
  -am [配置]   配置自动合并到主分支功能（格式：enabled:true/false 或 prefixes:前缀列表 或 main:分支名）
  -amc         临时启用自动合并到主分支功能（仅本次执行有效）
  -amb [分支名] 临时指定主分支名称（仅本次执行有效）
  -migrate     手动将配置文件迁移到环境变量
  -lp          列出所有已配置项目
  -le          列出所有已配置环境
  -l           列出所有配置信息

$(print_info "示例:")
  br.sh -e 灰度1:gray1/250724
  br.sh -p project-core:/path/to/project
  br.sh -t your_gitlab_token
  br.sh -u project-core
  br.sh -migrate
  br.sh -hk token:your_access_token_here
  br.sh -hk mobiles:13800000000,13900000000
  br.sh -hk message:[恭喜][恭喜][恭喜] 老板发财
  br.sh -am enabled:true
  br.sh -am prefixes:feature,hotfix,bugfix
  br.sh -am main:master
  br.sh -amc
  br.sh -amb develop

$(print_info "功能特性:")
  • 智能检测当前分支，支持直接回车使用或输入其他分支名
  • 支持多项目和多环境配置管理
  • 支持同时向多个环境创建合并请求
  • 自动检测合并状态并提供彩色反馈
  • 每日首次运行自动更新环境分支到最新版本
  • 首次使用时自动初始化十个默认环境配置
  • 添加项目时自动检测同目录下的其他Git项目
  • 支持机器人Hook通知MR结果汇总（钉钉）
  • 自动检测并更新脚本到最新版本
  • 支持自动合并feature/hotfix分支到主分支（可配置）
  • 配置完全基于环境变量，支持自动迁移旧配置文件
EOF
}

#######################################
# 配置初始化函数
#######################################

# 检查项目是否存在于项目数组中
# 参数：$1 - 要检查的项目名称
_project_exists() {
    local item="$1"

    for element in "${project_names[@]}"; do
        [[ "$element" == "$item" ]] && return 0
    done
    return 1
}

# 检查环境是否存在于环境数组中
# 参数：$1 - 要检查的环境名称
_env_exists() {
    local item="$1"

    for element in "${env_names[@]}"; do
        [[ "$element" == "$item" ]] && return 0
    done
    return 1
}

# 通用的输入验证函数
# 参数：$1 - 提示信息，$2 - 验证类型(non-empty/path)
prompt_and_validate() {
    local prompt="$1"
    local validation_type="${2:-non-empty}"
    local input=""

    while true; do
        read -p "$(print_info "$prompt")" input
        [[ "$input" == "q" ]] && return 1

        case "$validation_type" in
            "non-empty")
                if [[ -n "$input" ]]; then
                    echo "$input"
                    return 0
                else
                    print_warning "输入不能为空，请重新输入"
                fi
                ;;
            "path")
                if [[ -n "$input" ]]; then
                    [[ -d "$input" ]] || print_warning "警告: 路径 '$input' 不存在"
                    echo "$input"
                    return 0
                else
                    print_warning "路径不能为空，请重新输入"
                fi
                ;;
        esac
    done
}

# 更新或添加环境配置
# 参数：$1 - 环境名称，$2 - 分支名称
_update_or_add_env() {
    local env_name="$1"
    local branch_name="$2"

    if _env_exists "$env_name"; then
        print_success "已更新环境 '$env_name' 的分支为 '$branch_name'"
    else
        print_success "已添加新环境 '$env_name' -> '$branch_name'"
    fi

    _update_env_config "$env_name" "$branch_name"
}

# 初始化环境配置
# 参数：$1 - 可选的环境配置字符串（格式：环境名称:分支名称）
init_env_config() {
    local input="$1"

    if [[ -z "$input" ]]; then
        # 交互式配置多个环境
        print_info "交互式环境配置（输入 'q' 退出）"
        while true; do
            local env_name branch_name

            env_name=$(prompt_and_validate "请输入环境名称: ")
            [[ $? -eq 0 ]] || break

            branch_name=$(prompt_and_validate "请输入分支名称: ")
            [[ $? -eq 0 ]] || continue

            _update_or_add_env "$env_name" "$branch_name"
        done
    else
        # 单个环境配置
        IFS=':' read -r env_name branch_name <<< "$input"

        # 验证输入格式
        [[ -n "$env_name" && -n "$branch_name" ]] || print_error_and_exit "环境配置格式错误，正确格式：环境名称:分支名称"

        _update_or_add_env "$env_name" "$branch_name"
    fi

    save_config
}

# 更新或添加项目配置
# 参数：$1 - 项目名称，$2 - 项目路径
_update_or_add_project() {
    local project_name="$1"
    local project_path="$2"
    local is_new_project=false

    # 验证项目路径是否存在
    [[ -d "$project_path" ]] || print_warning "警告: 项目路径 '$project_path' 不存在"

    if _project_exists "$project_name"; then
        # 项目已存在，更新路径
        for i in "${!project_names[@]}"; do
            if [[ "${project_names[$i]}" == "$project_name" ]]; then
                project_paths[$i]="$project_path"
                print_success "已更新项目 '$project_name' 的路径为 '$project_path'"
                break
            fi
        done
    else
        # 项目不存在，添加新项目
        project_names+=("$project_name")
        project_paths+=("$project_path")
        print_success "已添加新项目 '$project_name' -> '$project_path'"
        is_new_project=true
    fi

    # 如果是新项目且路径有效，检测同目录的其他Git项目
    if [[ "$is_new_project" == "true" && -d "$project_path" ]]; then
        # 检查是否是Git仓库
        if [[ -d "$project_path/.git" ]] || (cd "$project_path" && git rev-parse --git-dir >/dev/null 2>&1); then
            auto_detect_sibling_projects "$project_path"
        fi
    fi
}

# 初始化项目配置
# 参数：$1 - 可选的项目配置字符串（格式：项目名称:项目路径）
init_project_config() {
    local input="$1"

    if [[ -z "$input" ]]; then
        # 交互式配置多个项目
        print_info "交互式项目配置（输入 'q' 退出）"
        while true; do
            local project_name project_path

            project_name=$(prompt_and_validate "请输入项目名称: ")
            [[ $? -eq 0 ]] || break

            project_path=$(prompt_and_validate "请输入项目路径: " "path")
            [[ $? -eq 0 ]] || continue

            _update_or_add_project "$project_name" "$project_path"
        done
    else
        # 单个项目配置
        IFS=':' read -r project_name project_path <<< "$input"

        # 验证输入格式
        [[ -n "$project_name" && -n "$project_path" ]] || print_error_and_exit "项目配置格式错误，正确格式：项目名称:项目路径"

        _update_or_add_project "$project_name" "$project_path"
    fi

    save_config
}

# 配置自动合并到主分支功能
# 参数：$1 - 配置字符串（格式：enabled:true/false 或 prefixes:前缀列表 或 main:分支名）
init_auto_merge_config() {
    local input="$1"

    if [[ -z "$input" ]]; then
        # 交互式配置
        print_info "自动合并到主分支功能配置（输入 'q' 退出）"

        # 配置功能开关
        while true; do
            local current_status="关闭"
            [[ "$auto_merge_to_main_enabled" == "true" ]] && current_status="开启"

            echo -e "${BLUE}${EMOJI_INFO} 当前状态: ${current_status}${NC}"
            echo -n -e "${BLUE}${EMOJI_INFO} 是否启用自动合并到主分支功能？(y/n/q): ${NC}"
            read enable_input

            case "$enable_input" in
                [Yy]|[Yy][Ee][Ss])
                    auto_merge_to_main_enabled="true"
                    print_success "已启用自动合并到主分支功能"
                    break
                    ;;
                [Nn]|[Nn][Oo])
                    auto_merge_to_main_enabled="false"
                    print_success "已禁用自动合并到主分支功能"
                    break
                    ;;
                [Qq])
                    return 0
                    ;;
                *)
                    print_warning "请输入 y/n/q"
                    ;;
            esac
        done

        # 如果启用了功能，继续配置其他选项
        if [[ "$auto_merge_to_main_enabled" == "true" ]]; then
            # 配置分支前缀
            echo -e "${BLUE}${EMOJI_INFO} 当前分支前缀: ${auto_merge_branch_prefixes}${NC}"
            echo -n -e "${BLUE}${EMOJI_INFO} 请输入触发自动合并的分支前缀（逗号分隔，直接回车保持当前设置）: ${NC}"
            read prefixes_input

            if [[ -n "$prefixes_input" ]]; then
                auto_merge_branch_prefixes="$prefixes_input"
                print_success "已更新分支前缀为: $auto_merge_branch_prefixes"
            fi

            # 配置主分支名称
            echo -e "${BLUE}${EMOJI_INFO} 当前主分支名称: ${main_branch_name}${NC}"
            echo -n -e "${BLUE}${EMOJI_INFO} 请输入主分支名称（直接回车保持当前设置）: ${NC}"
            read main_branch_input

            if [[ -n "$main_branch_input" ]]; then
                main_branch_name="$main_branch_input"
                print_success "已更新主分支名称为: $main_branch_name"
            fi
        fi
    else
        # 单个配置项
        IFS=':' read -r config_type config_value <<< "$input"

        case "$config_type" in
            "enabled")
                if [[ "$config_value" == "true" || "$config_value" == "false" ]]; then
                    auto_merge_to_main_enabled="$config_value"
                    local status="禁用"
                    [[ "$config_value" == "true" ]] && status="启用"
                    print_success "已${status}自动合并到主分支功能"
                else
                    print_error_and_exit "enabled 配置值必须是 true 或 false"
                fi
                ;;
            "prefixes")
                if [[ -n "$config_value" ]]; then
                    auto_merge_branch_prefixes="$config_value"
                    print_success "已更新分支前缀为: $auto_merge_branch_prefixes"
                else
                    print_error_and_exit "prefixes 配置值不能为空"
                fi
                ;;
            "main")
                if [[ -n "$config_value" ]]; then
                    main_branch_name="$config_value"
                    print_success "已更新主分支名称为: $main_branch_name"
                else
                    print_error_and_exit "main 配置值不能为空"
                fi
                ;;
            *)
                print_error_and_exit "无效的配置类型，支持的类型：enabled、prefixes、main"
                ;;
        esac
    fi

    save_config
}

#######################################
# 配置显示函数
#######################################

# 列出所有已配置的项目
list_projects() {
    print_info "已配置项目:"
    if [[ "${#project_names[@]}" -eq 0 ]]; then
        print_warning "  暂无配置的项目"
        return
    fi

    for i in "${!project_names[@]}"; do
        local status_icon="✓"
        local status_color="$GREEN"

        # 检查项目路径是否存在
        if [[ ! -d "${project_paths[$i]}" ]]; then
            status_icon="✗"
            status_color="$RED"
        fi

        echo -e "  ${status_color}${status_icon} ${project_names[$i]}${NC} -> ${project_paths[$i]}"
    done
}

# 列出所有已配置的环境
list_environments() {
    print_info "已配置环境:"
    if [[ "${#env_names[@]}" -eq 0 ]]; then
        print_warning "  暂无配置的环境"
        return
    fi

    for i in "${!env_names[@]}"; do
        echo -e "  ${GREEN}• ${env_names[$i]}${NC} -> ${env_branches[$i]}"
    done
}

# 列出所有配置信息
list_all_config() {
    print_info "当前配置信息:"
    echo ""

    # 显示GitLab Token状态
    if [[ -n "$gitlab_token" ]]; then
        local masked_token="${gitlab_token:0:8}***${gitlab_token: -4}"
        echo -e "${GREEN}[GitLab Token]${NC} $masked_token"
    else
        echo -e "${RED}[GitLab Token]${NC} 未配置"
    fi

    # 显示自动合并配置
    echo ""
    print_info "自动合并到主分支配置:"
    local status_text="关闭"
    local status_color="$RED"
    if [[ "$auto_merge_to_main_enabled" == "true" ]]; then
        status_text="开启"
        status_color="$GREEN"
    fi
    echo -e "  ${status_color}功能状态: ${status_text}${NC}"
    echo -e "  ${BLUE}分支前缀: ${auto_merge_branch_prefixes}${NC}"
    echo -e "  ${BLUE}主分支名称: ${main_branch_name}${NC}"

    echo ""
    list_projects
    echo ""
    list_environments
}

#######################################
# 分支管理函数
#######################################

# 获取项目的当前Git分支
# 参数：$1 - 项目路径
# 返回：纯净的分支名称（如果成功）或空字符串（如果失败）
get_current_branch() {
    local project_path="$1"
    local branch_name=""

    # 检查是否为有效的Git仓库
    if [[ -d "$project_path" && -d "$project_path/.git" ]]; then
        branch_name=$(cd "$project_path" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
    fi

    # 确保返回纯净的分支名称
    if [[ -n "$branch_name" ]]; then
        printf '%s' "$branch_name" | tr -d '\r\n\t' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    else
        echo ""
    fi
}

# 询问用户选择源分支
# 参数：$1 - 当前分支名称
# 输出：选择的分支名称
ask_source_branch() {
    local current_branch="$1"

    # 将所有显示输出重定向到stderr，避免混入函数返回值
    echo -e "${BLUE}${EMOJI_BRANCH} 当前分支: ${GREEN}$current_branch${NC}" >&2
    echo -n -e "${BLUE}${EMOJI_INFO} 请选择源分支 [直接回车使用当前分支，或输入其他分支名]: ${NC}" >&2
    read user_input

    # 如果用户直接回车或输入y/Y，使用当前分支
    if [[ -z "$user_input" || "$user_input" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}${EMOJI_SUCCESS} 使用当前分支: $current_branch${NC}" >&2
        echo "$current_branch"
        return 0
    else
        # 用户输入了具体的分支名称
        echo -e "${GREEN}${EMOJI_SUCCESS} 使用指定分支: $user_input${NC}" >&2
        echo "$user_input"
        return 0
    fi
}

# 全局分支选择（在项目选择后统一进行）
# 输出：选择的分支名称（通过全局变量selected_branch）
select_branch() {
    print_step "选择分支"

    # 如果只选择了一个项目，可以获取其当前分支
    if [[ "${#selected_projects[@]}" -eq 1 ]]; then
        local project_name="${selected_projects[0]}"
        local project_path
        project_path=$(get_project_path "$project_name")

        if [[ -n "$project_path" && -d "$project_path" ]]; then
            local current_branch
            current_branch=$(get_current_branch "$project_path")

            if [[ -n "$current_branch" ]]; then
                selected_branch=$(ask_source_branch "$current_branch")
                return 0
            fi
        fi
    fi

    # 多项目或无法获取当前分支时，手动输入
    echo -e "${BLUE}${EMOJI_BRANCH} 多项目模式或无法检测当前分支${NC}"
    while [[ -z "${selected_branch:-}" ]]; do
        echo -n -e "${BLUE}${EMOJI_INFO} 请输入源分支名称: ${NC}"
        read selected_branch
        [[ -n "$selected_branch" ]] || echo -e "${YELLOW}${EMOJI_WARNING} 分支名称不能为空，请重新输入${NC}" >&2
    done
    echo -e "${GREEN}${EMOJI_SUCCESS} 使用指定分支: $selected_branch${NC}"
}



#######################################
# 项目和环境选择函数
#######################################

# 检测当前目录是否匹配已配置的项目
# 输出：匹配的项目名称（如果找到）
detect_current_project() {
    local current_dir
    current_dir=$(pwd)

    # 遍历所有配置的项目，检查当前目录是否匹配
    for i in "${!project_names[@]}"; do
        local project_path="${project_paths[$i]}"
        # 将路径转换为绝对路径进行比较
        if [[ -d "$project_path" ]]; then
            local abs_project_path
            abs_project_path=$(cd "$project_path" && pwd 2>/dev/null)
            if [[ "$current_dir" == "$abs_project_path" ]]; then
                echo "${project_names[$i]}"
                return 0
            fi
        fi
    done
    # 没有检测到匹配的项目，返回空（这是正常情况，不是错误）
    return 0
}

# 选择项目（支持多选，带智能检测）
# 输出：选中的项目列表（通过全局变量selected_projects）
select_projects() {
    print_step "选择项目"

    # 智能检测当前项目
    local detected_project
    detected_project=$(detect_current_project)

    # 显示项目列表
    echo -e "${BLUE}${EMOJI_PROJECT} 请选择项目（可多选，用空格分隔序号）:${NC}"

    # 如果检测到当前项目，显示提示信息
    if [[ -n "$detected_project" ]]; then
        echo -e "${GREEN}${EMOJI_SUCCESS} 检测到当前目录为项目: ${WHITE}$detected_project${NC}"
        echo -e "${BLUE}${EMOJI_INFO} 直接回车使用检测到的项目，或输入序号选择其他项目${NC}"
    fi

    # 显示项目列表
    for i in "${!project_names[@]}"; do
        local status_icon="${EMOJI_SUCCESS}"
        local status_color="${GREEN}"
        local highlight=""

        # 检查项目路径是否存在
        if [[ ! -d "${project_paths[$i]}" ]]; then
            status_icon="${EMOJI_ERROR}"
            status_color="${RED}"
        fi

        # 高亮显示检测到的项目
        if [[ -n "$detected_project" && "${project_names[$i]}" == "$detected_project" ]]; then
            highlight="${YELLOW}[当前目录] ${NC}"
        fi

        echo -e "  ${WHITE}$((i+1)))${NC} ${status_color}${status_icon}${NC} ${highlight}${CYAN}${project_names[$i]}${NC} ${GRAY}(${project_paths[$i]})${NC}"
    done

    # 获取用户选择
    local input
    echo -n -e "\n${BLUE}${EMOJI_INFO} 请输入选择的序号（可多选，用空格分隔，直接回车使用检测到的项目）: ${NC}"
    read input

    # 如果用户直接回车且检测到项目，使用检测到的项目
    if [[ -z "$input" && -n "$detected_project" ]]; then
        selected_projects=("$detected_project")
        echo -e "${GREEN}${EMOJI_SUCCESS} 已选择项目: $detected_project${NC}"
        return 0
    fi

    # 如果用户输入了序号，解析选择
    if [[ -n "$input" ]]; then
        local indices=()
        read -r -a indices <<< "$input"

        # 验证选择并构建项目列表
        selected_projects=()
        for index in "${indices[@]}"; do
            local idx=$((index - 1))
            if [[ "$idx" -ge 0 && "$idx" -lt "${#project_names[@]}" ]]; then
                selected_projects+=("${project_names[$idx]}")
            else
                echo -e "${YELLOW}${EMOJI_WARNING} 忽略无效选择: $index${NC}" >&2
            fi
        done

        # 确认选择
        if [[ "${#selected_projects[@]}" -gt 0 ]]; then
            echo -e "\n${GREEN}${EMOJI_SUCCESS} 已选择项目: ${selected_projects[*]}${NC}"
            return 0
        fi
    fi

    # 如果没有有效选择，报错
    print_error_and_exit "没有选择有效的项目"
}

# 从分支名检测目标环境（仅检测merge分支）
# 参数：$1 - 分支名称
# 输出：检测到的环境名称（如果找到）
detect_environment_from_branch() {
    local branch_name="$1"

    # 严格检查是否符合 merge/{user}/{environment}/{date} 模式
    # 确保分支名以 "merge/" 开头，避免 feature/zangbai/gray3/240515 等被误判
    if [[ "$branch_name" =~ ^merge/[^/]+/([^/]+/[0-9]+)$ ]]; then
        local detected_env_branch="${BASH_REMATCH[1]}"

        # 遍历所有配置的环境，检查是否有完全匹配的环境分支
        for i in "${!env_names[@]}"; do
            local env_name="${env_names[$i]}"
            local env_branch="${env_branches[$i]}"

            # 完全匹配检测到的环境分支
            # 例如：merge/zangbai/gray3/240515 提取出 gray3/240515，与配置中的 gray3/240515 完全匹配
            if [[ "$env_branch" == "$detected_env_branch" ]]; then
                echo "$env_name"
                return 0
            fi
        done
    fi

    # 没有检测到匹配的环境，返回空（这是正常情况，不是错误）
    return 0
}

# 选择环境（支持多选，带智能检测）
# 输出：选中的环境列表（通过全局变量selected_envs）
select_environments() {
    print_step "选择环境"

    # 智能检测目标环境（基于分支名）
    local detected_env
    if [[ -n "${selected_branch:-}" ]]; then
        detected_env=$(detect_environment_from_branch "$selected_branch")
    fi

    # 显示环境列表
    echo -e "${BLUE}${EMOJI_ENV} 请选择环境（可多选，用空格分隔序号）:${NC}"

    # 如果检测到环境，显示提示信息
    if [[ -n "$detected_env" ]]; then
        echo -e "${GREEN}${EMOJI_SUCCESS} 从分支名称中检测到目标环境为: ${WHITE}$detected_env${NC}"
        echo -e "${BLUE}${EMOJI_INFO} 直接回车使用检测到的环境，或输入序号选择其他环境${NC}"
    fi

    # 显示环境列表
    for i in "${!env_names[@]}"; do
        local highlight=""

        # 高亮显示检测到的环境
        if [[ -n "$detected_env" && "${env_names[$i]}" == "$detected_env" ]]; then
            highlight="${YELLOW}[检测到] ${NC}"
        fi

        echo -e "  ${WHITE}$((i+1)))${NC} ${highlight}${PURPLE}${EMOJI_ENV} ${env_names[$i]}${NC} ${GRAY}(${env_branches[$i]})${NC}"
    done

    # 获取用户选择
    local input
    echo -n -e "\n${BLUE}${EMOJI_INFO} 请输入选择的序号（可多选，用空格分隔，直接回车使用检测到的环境）: ${NC}"
    read input

    # 如果用户直接回车且检测到环境，使用检测到的环境
    if [[ -z "$input" && -n "$detected_env" ]]; then
        selected_envs=("$detected_env")
        echo -e "${GREEN}${EMOJI_SUCCESS} 已选择环境: $detected_env${NC}"
        return 0
    fi

    # 如果用户输入了序号，解析选择
    if [[ -n "$input" ]]; then
        local indices=()
        read -r -a indices <<< "$input"

        # 验证选择并构建环境列表
        selected_envs=()
        for index in "${indices[@]}"; do
            local idx=$((index - 1))
            if [[ "$idx" -ge 0 && "$idx" -lt "${#env_names[@]}" ]]; then
                selected_envs+=("${env_names[$idx]}")
            else
                echo -e "${YELLOW}${EMOJI_WARNING} 忽略无效选择: $index${NC}" >&2
            fi
        done

        # 确认选择
        if [[ "${#selected_envs[@]}" -gt 0 ]]; then
            echo -e "\n${GREEN}${EMOJI_SUCCESS} 已选择环境: ${selected_envs[*]}${NC}"
            return 0
        fi
    fi

    # 如果没有有效选择，报错
    print_error_and_exit "没有选择有效的环境"
}

#######################################
# 自动合并到主分支功能
#######################################

# 检查分支是否匹配自动合并前缀
# 参数：$1 - 分支名称
# 返回：0 - 匹配，1 - 不匹配
check_auto_merge_branch_prefix() {
    local branch_name="$1"

    # 检查是否启用了自动合并功能（包括临时启用）
    if [[ "$auto_merge_to_main_enabled" != "true" && "$temp_auto_merge_enabled" != "true" ]]; then
        return 1
    fi

    # 分割前缀列表并检查匹配
    IFS=',' read -ra prefixes <<< "$auto_merge_branch_prefixes"
    for prefix in "${prefixes[@]}"; do
        # 去除前后空格
        prefix=$(echo "$prefix" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ "$branch_name" =~ ^${prefix}/ ]]; then
            return 0
        fi
    done

    return 1
}

# 获取实际使用的主分支名称
# 输出：主分支名称
get_effective_main_branch() {
    if [[ -n "$temp_main_branch" ]]; then
        echo "$temp_main_branch"
    else
        echo "$main_branch_name"
    fi
}

# 自动合并源分支到主分支
# 参数：$1 - 项目名称，$2 - 项目路径，$3 - 源分支名称
auto_merge_to_main_branch() {
    local project_name="$1"
    local project_path="$2"
    local source_branch="$3"
    local main_branch
    main_branch=$(get_effective_main_branch)

    print_step "自动合并到主分支"
    print_info "项目: $project_name"
    print_info "源分支: $source_branch"
    print_info "目标分支: $main_branch"

    # 切换到项目目录
    cd "$project_path" || {
        print_error "无法切换到项目目录: $project_path"
        return 1
    }

    # 检查是否是Git仓库
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "不是有效的Git仓库: $project_path"
        return 1
    fi

    # 更新远程分支信息
    print_info "更新远程分支信息..."
    git fetch origin || {
        print_warning "获取远程分支信息失败，继续执行..."
    }

    # 检查主分支是否存在
    if ! git show-ref --verify --quiet "refs/remotes/origin/$main_branch"; then
        print_error "远程主分支 '$main_branch' 不存在"
        return 1
    fi

    # 切换到主分支
    print_info "切换到主分支: $main_branch"
    if git show-ref --verify --quiet "refs/heads/$main_branch"; then
        # 本地分支存在，切换并拉取最新
        git checkout "$main_branch" || {
            print_error "无法切换到主分支: $main_branch"
            return 1
        }
        git pull origin "$main_branch" || {
            print_error "无法拉取主分支最新代码"
            return 1
        }
    else
        # 本地分支不存在，从远程创建
        git checkout -b "$main_branch" "origin/$main_branch" || {
            print_error "无法创建主分支: $main_branch"
            return 1
        }
    fi

    # 检查源分支是否存在
    if ! git show-ref --verify --quiet "refs/remotes/origin/$source_branch"; then
        print_error "远程源分支 '$source_branch' 不存在"
        return 1
    fi

    # 合并源分支到主分支
    print_info "合并源分支 '$source_branch' 到主分支 '$main_branch'..."
    if git merge "origin/$source_branch" --no-ff -m "Auto merge $source_branch to $main_branch"; then
        print_success "合并成功，无冲突"

        # 推送到远程
        print_info "推送合并结果到远程..."
        if git push origin "$main_branch"; then
            print_success "已成功推送到远程主分支: $main_branch"
            return 0
        else
            print_error "推送到远程失败"
            return 1
        fi
    else
        print_warning "合并时发现冲突，需要手动解决"
        print_info "请在项目目录 '$project_path' 中手动解决冲突后执行："
        print_info "  git add ."
        print_info "  git commit"
        print_info "  git push origin $main_branch"
        return 1
    fi
}

#######################################
# 合并请求创建函数
#######################################

# 获取环境对应的目标分支
# 参数：$1 - 环境名称
# 输出：目标分支名称
get_target_branch_for_env() {
    local env_name="$1"

    for i in "${!env_names[@]}"; do
        if [[ "${env_names[$i]}" == "$env_name" ]]; then
            echo "${env_branches[$i]}"
            return
        fi
    done

    print_error_and_exit "未找到环境 '$env_name' 对应的分支"
}

# 获取项目路径
# 参数：$1 - 项目名称
# 输出：项目路径
get_project_path() {
    local project_name="$1"

    for i in "${!project_names[@]}"; do
        if [[ "${project_names[$i]}" == "$project_name" ]]; then
            echo "${project_paths[$i]}"
            return
        fi
    done

    echo ""
}



# 查找已存在的MR并获取详细信息
# 参数：$1 - 项目名称，$2 - 源分支，$3 - 目标分支
# 输出：JSON格式的MR信息（如果找到）
find_existing_mr_details() {
    local project_name="$1"
    local source_branch="$2"
    local target_branch="$3"

    # 获取项目ID用于验证
    local project_id
    project_id=$(get_project_id "$project_name")
    [[ -n "$project_id" ]] || {
        print_warning "无法获取项目ID，跳过查找已存在的MR"
        return 1
    }

    # 构建查询参数
    local api_path="/merge_requests"
    api_path="${api_path}?state=opened"
    api_path="${api_path}&source_branch=${source_branch}"
    api_path="${api_path}&target_branch=${target_branch}"
    api_path="${api_path}&scope=all"

    local response
    response=$(gitlab_api_call "GET" "$api_path")
    [[ $? -eq 0 ]] || return 1

    if command -v jq >/dev/null 2>&1; then
        local mr_details
        mr_details=$(echo "$response" | jq -r --arg project_id "$project_id" \
            '[.[] | select(.project_id == ($project_id | tonumber))] | .[0] // empty')

        if [[ -n "$mr_details" && "$mr_details" != "null" ]]; then
            echo "$mr_details"
            return 0
        fi
    else
        print_warning "需要jq工具来解析复杂的JSON响应"
        return 1
    fi

    return 1
}

# 查找已存在的MR（保持向后兼容）
# 参数：$1 - 项目名称，$2 - 源分支，$3 - 目标分支
# 输出：MR的web_url（如果找到）
find_existing_mr() {
    local project_name="$1"
    local source_branch="$2"
    local target_branch="$3"

    local mr_details
    mr_details=$(find_existing_mr_details "$project_name" "$source_branch" "$target_branch")

    if [[ -n "$mr_details" ]]; then
        parse_json_field "$mr_details" "web_url"
        return 0
    fi

    return 1
}

# 处理已存在的MR
# 参数：$1 - 项目名称，$2 - 源分支，$3 - 目标分支，$4 - 环境名称
handle_existing_mr() {
    local project_name="$1"
    local source_branch="$2"
    local target_branch="$3"
    local env_name="$4"

    echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${YELLOW}MR已存在，正在查找并检查状态...${NC}"

    local existing_mr_details
    existing_mr_details=$(find_existing_mr_details "$project_name" "$source_branch" "$target_branch")

    if [[ -n "$existing_mr_details" ]]; then
        # 使用统一的状态处理函数
        if handle_mr_status "$env_name" "$existing_mr_details" "existing"; then
            # 有合并冲突，需要处理
            local project_path
            project_path=$(get_project_path "$project_name")
            if [[ -n "$project_path" && -d "$project_path" ]]; then
                echo -e "    ${YELLOW}${EMOJI_LOADING} 自动处理合并冲突...${NC}"
                handle_merge_conflict "$project_name" "$project_path" "$source_branch" "$target_branch" "$env_name"
                return 0
            fi
        fi
        # 无论是否有冲突，MR信息都已经在handle_mr_status中添加到汇总了
    else
        # 没有找到已存在的MR
        mr_env_names+=("$env_name")
        mr_urls+=("失败")
        mr_statuses+=("失败: MR已存在但无法找到")
        echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: MR已存在但无法找到${NC}"
    fi
}

# 处理合并冲突
# 参数：$1 - 项目名称，$2 - 项目路径，$3 - 源分支，$4 - 目标分支，$5 - 环境名称
handle_merge_conflict() {
    local project_name="$1"
    local project_path="$2"
    local source_branch="$3"
    local target_branch="$4"
    local env_name="$5"

    # 检查是否有用户名
    [[ -n "$gitlab_username" ]] || {
        print_warning "未获取到GitLab用户名，跳过合并冲突处理"
        return 1
    }

    # 检查源分支是否已经是merge分支
    if [[ "$source_branch" =~ ^merge/${gitlab_username}/ ]]; then
        print_info "源分支已是merge分支，跳过合并冲突处理"
        return 0
    fi

    local merge_branch="merge/${gitlab_username}/${target_branch}"

    print_info "检测到合并冲突，准备创建/切换到merge分支: $merge_branch"

    # 切换到项目目录
    cd "$project_path" || {
        print_error "无法切换到项目目录: $project_path"
        return 1
    }

    # 更新远程分支信息
    print_info "更新远程分支信息..."
    git fetch origin || {
        print_warning "获取远程分支信息失败，继续执行..."
    }

    # 检查merge分支是否存在
    if git show-ref --verify --quiet "refs/heads/$merge_branch"; then
        print_info "merge分支已存在，切换到: $merge_branch"
        git checkout "$merge_branch" || {
            print_error "无法切换到merge分支: $merge_branch"
            return 1
        }

        # 更新目标分支
        print_info "更新目标分支: $target_branch"
        if git show-ref --verify --quiet "refs/heads/$target_branch"; then
            # 本地分支存在，切换并拉取
            git checkout "$target_branch" && git pull origin "$target_branch" || {
                print_error "无法更新目标分支: $target_branch"
                return 1
            }
        else
            # 本地分支不存在，从远程创建
            git checkout -b "$target_branch" "origin/$target_branch" || {
                print_error "无法创建目标分支: $target_branch"
                return 1
            }
        fi

        # 切回merge分支并同步目标分支的最新内容
        git checkout "$merge_branch" || {
            print_error "无法切换回merge分支: $merge_branch"
            return 1
        }

        print_info "同步目标分支最新内容到merge分支"
        git merge "origin/$target_branch" || {
            print_warning "同步目标分支时出现冲突，请手动解决"
        }
    else
        print_info "创建新的merge分支: $merge_branch"

        # 确保目标分支是最新的
        print_info "更新目标分支: $target_branch"
        if git show-ref --verify --quiet "refs/heads/$target_branch"; then
            # 本地分支存在，切换并拉取
            git checkout "$target_branch" && git pull origin "$target_branch" || {
                print_error "无法更新目标分支: $target_branch"
                return 1
            }
        else
            # 本地分支不存在，从远程创建
            git checkout -b "$target_branch" "origin/$target_branch" || {
                print_error "无法创建目标分支: $target_branch"
                return 1
            }
        fi

        # 基于目标分支创建merge分支
        git checkout -b "$merge_branch" || {
            print_error "无法创建merge分支: $merge_branch"
            return 1
        }
    fi

    # 合并源分支到merge分支
    print_info "合并源分支 $source_branch 到merge分支"
    local merge_success=false
    if git merge "$source_branch"; then
        print_success "合并完成，无冲突"
        merge_success=true
    else
        # 检查是否真的有冲突，还是其他错误
        if [[ -f ".git/MERGE_HEAD" ]]; then
            # 检查是否有未解决的冲突文件
            if git diff --name-only --diff-filter=U | grep -q .; then
                print_warning "合并出现冲突，请手动解决冲突后提交"
            else
                print_info "合并状态异常但无冲突文件，可能已自动解决"
                merge_success=true
            fi
        else
            # 没有MERGE_HEAD文件，说明合并已经完成或者出现了其他错误
            local git_status
            git_status=$(git status --porcelain)
            if [[ -z "$git_status" ]]; then
                print_success "合并已完成，无需额外处理"
                merge_success=true
            else
                print_warning "Git状态异常，请检查: $git_status"
            fi
        fi
    fi

    # 等待用户处理冲突
    wait_for_conflict_resolution "$project_name" "$project_path" "$merge_branch" "$target_branch" "$env_name" "$merge_success"

    return 0
}

# 等待冲突解决并创建新的MR
# 参数：$1 - 项目名称，$2 - 项目路径，$3 - merge分支，$4 - 目标分支，$5 - 环境名称，$6 - 是否自动合并成功
wait_for_conflict_resolution() {
    local project_name="$1"
    local project_path="$2"
    local merge_branch="$3"
    local target_branch="$4"
    local env_name="$5"
    local merge_success="$6"

    # 如果自动合并成功，直接推送并创建MR
    if [[ "$merge_success" == "true" ]]; then
        cd "$project_path" || return 1
        git push origin "$merge_branch" || {
            print_error "无法推送merge分支: $merge_branch"
            return 1
        }
        create_merge_request_from_merge_branch "$project_name" "$merge_branch" "$env_name" "$target_branch"
        return 0
    fi

    # 如果有冲突，等待用户处理
    echo -e "\n${YELLOW}${EMOJI_WARNING} 请在IDE中解决冲突，完成后按任意键继续...${NC}"
    read -n 1 -s

    # 检查状态并等待用户完成
    while true; do
        cd "$project_path" || return 1

        # 检查是否处于合并状态（存在 .git/MERGE_HEAD）
        if [[ -f ".git/MERGE_HEAD" ]]; then
            # 检查是否还有未解决的冲突
            if git diff --name-only --diff-filter=U | grep -q .; then
                echo -e "${RED}${EMOJI_ERROR} 检测到未解决的合并冲突${NC}"
                echo -e "${GRAY}  请在IDE中解决以下冲突文件：${NC}"
                git diff --name-only --diff-filter=U | sed 's/^/    /'
                echo -e "${YELLOW}解决冲突后按任意键继续...${NC}"
                read -n 1 -s
                continue
            else
                # 冲突已解决，但还在合并状态，需要提交
                echo -e "${YELLOW}${EMOJI_INFO} 冲突已解决，准备提交合并...${NC}"
                # 继续到下面的提交逻辑
            fi
        else
            # 没有MERGE_HEAD文件，检查是否有其他需要处理的情况
            local git_status
            git_status=$(git status --porcelain)
            if [[ -z "$git_status" ]]; then
                # 没有任何变更，说明冲突已经解决或者没有冲突
                echo -e "${GREEN}${EMOJI_SUCCESS} 检测到合并已完成，无需额外处理${NC}"
                break
            fi
            # 如果有变更，继续到下面的提交逻辑
        fi

        # 检查是否有已暂存但未提交的更改，或者处于合并状态需要提交
        if ! git diff --cached --quiet || [[ -f ".git/MERGE_HEAD" ]]; then
            echo -e "${YELLOW}${EMOJI_INFO} 检测到需要提交的更改，自动提交...${NC}"

            # 如果有未暂存的更改，先暂存
            if ! git diff --quiet; then
                echo -e "${YELLOW}${EMOJI_INFO} 暂存所有更改...${NC}"
                git add . || {
                    echo -e "${RED}${EMOJI_ERROR} 暂存更改失败${NC}"
                    echo -e "${YELLOW}请手动处理后按任意键继续...${NC}"
                    read -n 1 -s
                    continue
                }
            fi

            # 提交更改
            if [[ -f ".git/MERGE_MSG" ]]; then
                # 使用合并消息文件提交
                git commit -F .git/MERGE_MSG || {
                    echo -e "${RED}${EMOJI_ERROR} 提交失败${NC}"
                    echo -e "${YELLOW}请手动执行: git commit -F .git/MERGE_MSG${NC}"
                    echo -e "${YELLOW}完成后按任意键继续...${NC}"
                    read -n 1 -s
                    continue
                }
            else
                # 使用默认提交消息
                git commit -m "Resolve merge conflicts" || {
                    echo -e "${RED}${EMOJI_ERROR} 提交失败${NC}"
                    echo -e "${YELLOW}请手动执行: git commit${NC}"
                    echo -e "${YELLOW}完成后按任意键继续...${NC}"
                    read -n 1 -s
                    continue
                }
            fi
            print_success "冲突解决完成，已自动提交"
        fi

        # 检查是否有额外的未提交变更（解决冲突后的手动调整）
        if ! git diff --quiet; then
            echo -e "${YELLOW}${EMOJI_WARNING} 检测到解决冲突后的额外变更${NC}"
            echo -e "${GRAY}  这些变更可能是解决冲突时的手动调整${NC}"

            # 显示变更的文件
            echo -e "${GRAY}  变更的文件：${NC}"
            git diff --name-only | sed 's/^/    /'

            # 自动暂存并提交这些变更
            echo -e "${YELLOW}${EMOJI_INFO} 自动提交这些变更...${NC}"
            git add . || {
                echo -e "${RED}${EMOJI_ERROR} 暂存变更失败${NC}"
                echo -e "${YELLOW}请手动执行: git add .${NC}"
                echo -e "${YELLOW}完成后按任意键继续...${NC}"
                read -n 1 -s
                continue
            }

            git commit -m "merge: 解决冲突时代码处理的不对, 重新调整下" || {
                echo -e "${RED}${EMOJI_ERROR} 提交额外变更失败${NC}"
                echo -e "${YELLOW}请手动执行: git commit -m \"merge: 解决冲突时代码处理的不对, 重新调整下\"${NC}"
                echo -e "${YELLOW}完成后按任意键继续...${NC}"
                read -n 1 -s
                continue
            }

            print_success "已自动提交解决冲突后的额外变更"
        fi

        # 检查是否有未推送的提交
        local unpushed_commits=0
        if git show-ref --verify --quiet "refs/remotes/origin/$merge_branch"; then
            # 远程分支存在，检查未推送的提交
            unpushed_commits=$(git log "origin/$merge_branch..$merge_branch" --oneline 2>/dev/null | wc -l || echo "0")
        else
            # 远程分支不存在，检查本地分支是否有提交
            unpushed_commits=$(git log "$merge_branch" --oneline 2>/dev/null | wc -l || echo "0")
        fi

        if [[ "$unpushed_commits" -gt 0 ]]; then
            echo -e "${YELLOW}${EMOJI_INFO} 检测到 $unpushed_commits 个未推送的提交，自动推送...${NC}"
            git push origin "$merge_branch" || {
                echo -e "${RED}${EMOJI_ERROR} 推送失败${NC}"
                echo -e "${GRAY}  使用命令: git push origin $merge_branch${NC}"
                echo -e "${YELLOW}完成后按任意键继续...${NC}"
                read -n 1 -s
                continue
            }
            print_success "已自动推送到远程仓库"
        fi

        # 最终状态检查
        if [[ -f ".git/MERGE_HEAD" ]]; then
            echo -e "${RED}${EMOJI_ERROR} 合并状态仍未完成，请检查Git状态${NC}"
            echo -e "${YELLOW}请手动完成合并后按任意键继续...${NC}"
            read -n 1 -s
            continue
        fi

        # 所有检查通过，创建MR
        print_success "合并分支准备完成，即将创建MR"
        break
    done

    # 使用merge分支创建新的MR
    create_merge_request_from_merge_branch "$project_name" "$merge_branch" "$env_name" "$target_branch" || {
        print_error "创建MR失败，请检查网络连接和权限"
        return 1
    }
}

# 使用merge分支创建MR
# 参数：$1 - 项目名称，$2 - merge分支，$3 - 环境名称，$4 - 目标分支
create_merge_request_from_merge_branch() {
    local project_name="$1"
    local merge_branch="$2"
    local env_name="$3"
    local target_branch="$4"

    local commit_msg="Merge branch '${merge_branch}' into '${target_branch}'"
    local api_url="${GITLAB_API_BASE}/projects/project%2F${project_name}/merge_requests"

    echo -e "  ${YELLOW}${EMOJI_LOADING} 使用merge分支为环境 ${PURPLE}$env_name${NC} 创建合并请求..."

    # 发送API请求创建MR
    local response
    response=$(curl -s -X POST \
        -H "PRIVATE-TOKEN: $gitlab_token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        "$api_url" \
        --data-urlencode "source_branch=$merge_branch" \
        --data-urlencode "target_branch=$target_branch" \
        --data-urlencode "title=$commit_msg")

    # 解析响应
    if command -v jq >/dev/null 2>&1; then
        # 使用jq解析JSON
        local web_url
        web_url=$(echo "$response" | jq -r '.web_url // empty')

        if [[ -n "$web_url" && "$web_url" != "null" ]]; then
            # 更新MR结果数组，替换原来的冲突MR
            for i in "${!mr_env_names[@]}"; do
                if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                    mr_urls[$i]="$web_url"
                    mr_statuses[$i]="已解决冲突"
                    break
                fi
            done

            echo -e "    ${GREEN}${EMOJI_SUCCESS} ${PURPLE}${env_name}${NC} ${GRAY}(已解决冲突)${NC}: ${CYAN}$web_url${NC}"
        else
            local error="创建merge分支MR失败"
            if echo "$response" | jq -e '.message' >/dev/null 2>&1; then
                if echo "$response" | jq -e '.message | type' | grep -q "array"; then
                    error=$(echo "$response" | jq -r '.message | join(", ")')
                else
                    error=$(echo "$response" | jq -r '.message')
                fi
            fi

            # 检查是否是MR已存在的错误
            if [[ "$error" =~ "This merge request already exists" ]]; then
                echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${YELLOW}merge分支MR已存在，正在查找并检查状态...${NC}"

                # 查找已存在的MR详细信息
                local existing_mr_details
                existing_mr_details=$(find_existing_mr_details "$project_name" "$merge_branch" "$target_branch")

                if [[ -n "$existing_mr_details" ]]; then
                    # 解析MR详细信息
                    local existing_mr_url
                    local merge_status

                    if command -v jq >/dev/null 2>&1; then
                        existing_mr_url=$(echo "$existing_mr_details" | jq -r '.web_url // empty')
                        merge_status=$(echo "$existing_mr_details" | jq -r '.merge_status // "unknown"')
                    else
                        # 备用方案：简单的文本解析
                        existing_mr_url=$(echo "$existing_mr_details" | grep -o '"web_url":"[^"]*"' | cut -d'"' -f4)
                        merge_status=$(echo "$existing_mr_details" | grep -o '"merge_status":"[^"]*"' | cut -d'"' -f4)
                    fi

                    if [[ -n "$existing_mr_url" ]]; then
                        # 检查是否有合并冲突（merge分支通常不应该有冲突，但为了完整性还是检查）
                        if [[ "$merge_status" == "cannot_be_merged" ]]; then
                            echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${YELLOW}merge分支MR仍有合并冲突，需要手动处理${NC}"

                            # 更新结果
                            for i in "${!mr_env_names[@]}"; do
                                if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                                    mr_urls[$i]="$existing_mr_url"
                                    mr_statuses[$i]="已存在-仍有冲突"
                                    break
                                fi
                            done

                            echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${GRAY}(已存在-仍有冲突)${NC}: ${CYAN}$existing_mr_url${NC}"
                        else
                            # 没有合并冲突，正常显示
                            # 更新结果
                            for i in "${!mr_env_names[@]}"; do
                                if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                                    mr_urls[$i]="$existing_mr_url"
                                    mr_statuses[$i]="已存在(已解决冲突)"
                                    break
                                fi
                            done

                            echo -e "    ${GREEN}${EMOJI_SUCCESS} ${PURPLE}${env_name}${NC} ${GRAY}(已存在-已解决冲突)${NC}: ${CYAN}$existing_mr_url${NC}"
                        fi
                    else
                        # 没有找到已存在的MR
                        for i in "${!mr_env_names[@]}"; do
                            if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                                mr_urls[$i]="失败"
                                mr_statuses[$i]="失败: merge分支MR已存在但无法找到"
                                break
                            fi
                        done

                        echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: merge分支MR已存在但无法找到${NC}"
                    fi
                else
                    # 没有找到已存在的MR
                    for i in "${!mr_env_names[@]}"; do
                        if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                            mr_urls[$i]="失败"
                            mr_statuses[$i]="失败: merge分支MR已存在但无法找到"
                            break
                        fi
                    done

                    echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: merge分支MR已存在但无法找到${NC}"
                fi
            else
                # 其他类型的错误
                for i in "${!mr_env_names[@]}"; do
                    if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                        mr_urls[$i]="失败"
                        mr_statuses[$i]="失败: $error"
                        break
                    fi
                done

                echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: ${error}${NC}"
            fi
        fi
    else
        # 备用方案：简单的文本解析
        if echo "$response" | grep -q '"web_url"'; then
            local web_url
            web_url=$(echo "$response" | grep -o '"web_url":"[^"]*"' | cut -d'"' -f4)

            # 更新MR结果数组
            for i in "${!mr_env_names[@]}"; do
                if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                    mr_urls[$i]="$web_url"
                    mr_statuses[$i]="已解决冲突"
                    break
                fi
            done

            echo -e "    ${GREEN}${EMOJI_SUCCESS} ${PURPLE}${env_name}${NC} ${GRAY}(已解决冲突)${NC}: ${CYAN}$web_url${NC}"
        else
            # 检查是否是MR已存在的错误（备用方案）
            if echo "$response" | grep -q "This merge request already exists"; then
                echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${YELLOW}merge分支MR已存在，正在查找并检查状态...${NC}"

                # 查找已存在的MR详细信息
                local existing_mr_details
                existing_mr_details=$(find_existing_mr_details "$project_name" "$merge_branch" "$target_branch")

                if [[ -n "$existing_mr_details" ]]; then
                    # 解析MR详细信息
                    local existing_mr_url
                    local merge_status
                    local changes_count

                    existing_mr_url=$(echo "$existing_mr_details" | grep -o '"web_url":"[^"]*"' | cut -d'"' -f4)
                    merge_status=$(echo "$existing_mr_details" | grep -o '"merge_status":"[^"]*"' | cut -d'"' -f4)
                    changes_count=$(echo "$existing_mr_details" | grep -o '"changes_count":[^,}]*' | cut -d':' -f2 | tr -d ' "')

                    if [[ -n "$existing_mr_url" ]]; then
                        # 检查是否有合并冲突（merge分支通常不应该有冲突，但为了完整性还是检查）
                        if [[ "$merge_status" == "cannot_be_merged" ]]; then
                            local changes_info=""
                            if [[ "$changes_count" =~ ^[0-9]+\+?$ ]]; then
                                changes_info=" (${changes_count}个变更)"
                            fi

                            echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${YELLOW}merge分支MR仍有合并冲突${changes_info}，需要手动处理${NC}"

                            # 更新结果
                            for i in "${!mr_env_names[@]}"; do
                                if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                                    mr_urls[$i]="$existing_mr_url"
                                    mr_statuses[$i]="已存在-仍有冲突$changes_info"
                                    break
                                fi
                            done

                            echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${GRAY}(已存在-仍有冲突${changes_info})${NC}: ${CYAN}$existing_mr_url${NC}"
                        else
                            # 没有合并冲突，正常显示
                            local changes_info=""
                            if [[ "$changes_count" =~ ^[0-9]+\+?$ ]]; then
                                changes_info=" (${changes_count}个变更)"
                            fi

                            # 更新结果
                            for i in "${!mr_env_names[@]}"; do
                                if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                                    mr_urls[$i]="$existing_mr_url"
                                    mr_statuses[$i]="已存在(已解决冲突)$changes_info"
                                    break
                                fi
                            done

                            echo -e "    ${GREEN}${EMOJI_SUCCESS} ${PURPLE}${env_name}${NC} ${GRAY}(已存在-已解决冲突${changes_info})${NC}: ${CYAN}$existing_mr_url${NC}"
                        fi
                    else
                        # 没有找到已存在的MR
                        for i in "${!mr_env_names[@]}"; do
                            if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                                mr_urls[$i]="失败"
                                mr_statuses[$i]="失败: merge分支MR已存在但无法找到"
                                break
                            fi
                        done

                        echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: merge分支MR已存在但无法找到${NC}"
                    fi
                else
                    # 没有找到已存在的MR
                    for i in "${!mr_env_names[@]}"; do
                        if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                            mr_urls[$i]="失败"
                            mr_statuses[$i]="失败: merge分支MR已存在但无法找到"
                            break
                        fi
                    done

                    echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: merge分支MR已存在但无法找到${NC}"
                fi
            else
                # 其他类型的错误
                for i in "${!mr_env_names[@]}"; do
                    if [[ "${mr_env_names[$i]}" == "$env_name" ]]; then
                        mr_urls[$i]="失败"
                        mr_statuses[$i]="失败: 请求失败"
                        break
                    fi
                done

                echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: 请求失败${NC}"
            fi
        fi
    fi
}

# MR状态处理函数
# 参数：$1 - 环境名称，$2 - MR详情JSON，$3 - 状态类型(new/existing)
handle_mr_status() {
    local env_name="$1"
    local mr_details="$2"
    local status_type="${3:-new}"

    local web_url merge_status changes_count
    web_url=$(parse_json_field "$mr_details" "web_url")
    merge_status=$(parse_json_field "$mr_details" "merge_status")
    changes_count=$(parse_json_field "$mr_details" "changes_count")

    # 默认值处理
    [[ -n "$changes_count" && "$changes_count" != "null" ]] || changes_count="0"
    [[ -n "$merge_status" && "$merge_status" != "null" ]] || merge_status="unknown"

    local status_icon status_text changes_info=""

    # 构建变更信息
    if [[ "$changes_count" =~ ^[0-9]+$ ]]; then
        changes_info=" (${changes_count}个变更)"
    fi

    # 根据状态设置图标和文本
    case "$merge_status" in
        "cannot_be_merged")
            status_icon="${EMOJI_WARNING}"
            status_text="${status_type}合并冲突"
            ;;
        "can_be_merged")
            status_icon="${EMOJI_SUCCESS}"
            status_text="${status_type}可合并"
            ;;
        *)
            if [[ "$changes_count" == "0" ]]; then
                status_icon="${EMOJI_INFO}"
                status_text="${status_type}无变更"
            else
                status_icon="${EMOJI_INFO}"
                status_text="${status_type}状态检查中"
            fi
            ;;
    esac

    # 添加前缀
    [[ "$status_type" == "existing" ]] && status_text="已存在-${status_text#existing}"

    # 收集MR结果
    mr_env_names+=("$env_name")
    mr_urls+=("$web_url")
    mr_statuses+=("$status_text$changes_info")

    # 显示结果
    local color="${GREEN}"
    [[ "$merge_status" == "cannot_be_merged" ]] && color="${YELLOW}"
    echo -e "    ${color}${status_icon} ${PURPLE}${env_name}${NC} ${GRAY}(${status_text}${changes_info})${NC}: ${CYAN}$web_url${NC}"

    # 返回是否需要处理冲突
    [[ "$merge_status" == "cannot_be_merged" ]]
}

# 创建单个合并请求
# 参数：$1 - 项目名称，$2 - 源分支，$3 - 环境名称，$4 - 目标分支
create_merge_request() {
    local project_name="$1"
    local source_branch="$2"
    local env_name="$3"
    local target_branch="$4"

    # 验证参数
    [[ -n "$source_branch" ]] || print_error_and_exit "源分支名称为空"
    [[ -n "$target_branch" ]] || print_error_and_exit "目标分支名称为空"

    local commit_msg="Merge branch '${source_branch}' into '${target_branch}'"
    echo -e "  ${YELLOW}${EMOJI_LOADING} 正在为环境 ${PURPLE}$env_name${NC} 创建合并请求..."

    # 构建请求数据
    local data
    data="source_branch=$(printf '%s' "$source_branch" | sed 's/ /%20/g')"
    data="${data}&target_branch=$(printf '%s' "$target_branch" | sed 's/ /%20/g')"
    data="${data}&title=$(printf '%s' "$commit_msg" | sed 's/ /%20/g')"

    # 发送API请求创建MR
    local response
    response=$(gitlab_api_call "POST" "/projects/project%2F${project_name}/merge_requests" "$data")

    # 检查API调用是否成功
    if [[ $? -ne 0 ]]; then
        mr_env_names+=("$env_name")
        mr_urls+=("失败")
        mr_statuses+=("失败: API调用失败")
        echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: API调用失败${NC}"
        return 1
    fi

    # 解析响应
    local web_url
    web_url=$(parse_json_field "$response" "web_url")

    if [[ -n "$web_url" && "$web_url" != "null" ]]; then
        # 成功创建MR，处理状态
        if handle_mr_status "$env_name" "$response" "new"; then
            # 有合并冲突，需要处理
            local project_path
            project_path=$(get_project_path "$project_name")
            if [[ -n "$project_path" && -d "$project_path" ]]; then
                echo -e "    ${YELLOW}${EMOJI_LOADING} 自动处理合并冲突...${NC}"
                handle_merge_conflict "$project_name" "$project_path" "$source_branch" "$target_branch" "$env_name"
                return 0
            fi
        fi
    else
        # 使用改进的错误解析
        local error
        error=$(parse_gitlab_error "$response")

        # 检查是否是MR已存在的错误
        if [[ "$error" =~ "This merge request already exists" ]]; then
            handle_existing_mr "$project_name" "$source_branch" "$target_branch" "$env_name"
            return 0
        else
            # 其他类型的错误
            mr_env_names+=("$env_name")
            mr_urls+=("失败")
            mr_statuses+=("失败: $error")
            echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: ${error}${NC}"
        fi


    fi

    # 备用方案：简单的文本解析（当jq不可用时）
    if [[ -z "$web_url" || "$web_url" == "null" ]]; then
        if echo "$response" | grep -q '"web_url"'; then
            local web_url
            web_url=$(echo "$response" | grep -o '"web_url":"[^"]*"' | cut -d'"' -f4)

            # 尝试解析 merge_status 和 changes_count
            local status="unknown"
            local changes_count="0"

            if echo "$response" | grep -q '"merge_status"'; then
                status=$(echo "$response" | grep -o '"merge_status":"[^"]*"' | cut -d'"' -f4)
            fi

            if echo "$response" | grep -q '"changes_count"'; then
                changes_count=$(echo "$response" | grep -o '"changes_count":[^,}]*' | cut -d':' -f2 | tr -d ' "')
            fi

            local status_icon="${EMOJI_SUCCESS}"
            local status_text="成功"
            local changes_info=""

            # 根据 merge_status 和 changes_count 综合判断状态
            if [[ "$changes_count" == "0" ]]; then
                status_icon="${EMOJI_INFO}"
                status_text="无变更"
                changes_info=" (0个变更)"
            elif [[ "$status" == "cannot_be_merged" ]]; then
                status_icon="${EMOJI_WARNING}"
                status_text="合并冲突"
                if [[ "$changes_count" =~ ^[0-9]+\+?$ ]]; then
                    changes_info=" (${changes_count}个变更)"
                fi

                # 先收集初始MR结果（合并冲突状态）
                mr_env_names+=("$env_name")
                mr_urls+=("处理中")
                mr_statuses+=("合并冲突$changes_info")

                # 自动处理合并冲突
                if [[ -n "$project_path" && -d "$project_path" ]]; then
                    echo -e "    ${YELLOW}${EMOJI_LOADING} 自动处理合并冲突...${NC}"
                    handle_merge_conflict "$project_name" "$project_path" "$source_branch" "$target_branch" "$env_name"
                    return 0
                fi
            elif [[ "$status" == "can_be_merged" ]]; then
                status_icon="${EMOJI_SUCCESS}"
                status_text="可合并"
                if [[ "$changes_count" =~ ^[0-9]+\+?$ ]]; then
                    changes_info=" (${changes_count}个变更)"
                fi
            else
                # 其他状态（如 checking, unchecked 等）
                status_icon="${EMOJI_INFO}"
                status_text="状态检查中"
                if [[ "$changes_count" =~ ^[0-9]+\+?$ ]]; then
                    changes_info=" (${changes_count}个变更)"
                fi
            fi

            # 收集MR结果到全局数组
            mr_env_names+=("$env_name")
            mr_urls+=("$web_url")
            mr_statuses+=("$status_text$changes_info")

            echo -e "    ${GREEN}${status_icon} ${PURPLE}${env_name}${NC} ${GRAY}(${status_text}${changes_info})${NC}: ${CYAN}$web_url${NC}"
        else
            # 检查是否是MR已存在的错误（备用方案）
            if echo "$response" | grep -q "This merge request already exists"; then
                echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${YELLOW}MR已存在，正在查找并检查状态...${NC}"

                # 查找已存在的MR详细信息
                local existing_mr_details
                existing_mr_details=$(find_existing_mr_details "$project_name" "$source_branch" "$target_branch")

                if [[ -n "$existing_mr_details" ]]; then
                    # 解析MR详细信息
                    local existing_mr_url
                    local merge_status
                    local changes_count

                    existing_mr_url=$(echo "$existing_mr_details" | grep -o '"web_url":"[^"]*"' | cut -d'"' -f4)
                    merge_status=$(echo "$existing_mr_details" | grep -o '"merge_status":"[^"]*"' | cut -d'"' -f4)
                    changes_count=$(echo "$existing_mr_details" | grep -o '"changes_count":[^,}]*' | cut -d':' -f2 | tr -d ' "')

                    if [[ -n "$existing_mr_url" ]]; then
                        # 检查是否有合并冲突
                        if [[ "$merge_status" == "cannot_be_merged" ]]; then
                            local changes_info=""
                            if [[ "$changes_count" =~ ^[0-9]+\+?$ ]]; then
                                changes_info=" (${changes_count}个变更)"
                            fi

                            echo -e "    ${YELLOW}${EMOJI_WARNING} ${PURPLE}${env_name}${NC} ${YELLOW}已存在MR有合并冲突${changes_info}，正在处理...${NC}"

                            # 先收集初始MR结果（合并冲突状态）
                            mr_env_names+=("$env_name")
                            mr_urls+=("$existing_mr_url")
                            mr_statuses+=("已存在-合并冲突$changes_info")

                            # 自动处理合并冲突
                            if [[ -n "$project_path" && -d "$project_path" ]]; then
                                echo -e "    ${YELLOW}${EMOJI_LOADING} 自动处理合并冲突...${NC}"
                                handle_merge_conflict "$project_name" "$project_path" "$source_branch" "$target_branch" "$env_name"
                                return 0
                            fi
                        else
                            # 没有合并冲突，正常显示
                            local status_text="已存在"
                            local changes_info=""
                            if [[ "$changes_count" =~ ^[0-9]+\+?$ ]]; then
                                changes_info=" (${changes_count}个变更)"
                            fi

                            mr_env_names+=("$env_name")
                            mr_urls+=("$existing_mr_url")
                            mr_statuses+=("$status_text$changes_info")

                            echo -e "    ${GREEN}${EMOJI_SUCCESS} ${PURPLE}${env_name}${NC} ${GRAY}(${status_text}${changes_info})${NC}: ${CYAN}$existing_mr_url${NC}"
                        fi
                    else
                        # 没有找到已存在的MR
                        mr_env_names+=("$env_name")
                        mr_urls+=("失败")
                        mr_statuses+=("失败: MR已存在但无法找到")

                        echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: MR已存在但无法找到${NC}"
                    fi
                else
                    # 没有找到已存在的MR
                    mr_env_names+=("$env_name")
                    mr_urls+=("失败")
                    mr_statuses+=("失败: MR已存在但无法找到")

                    echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: MR已存在但无法找到${NC}"
                fi
            else
                # 其他类型的错误
                mr_env_names+=("$env_name")
                mr_urls+=("失败")
                mr_statuses+=("失败: 请求失败")

                echo -e "    ${RED}${EMOJI_ERROR} ${PURPLE}${env_name}${NC} ${RED}失败: 请求失败${NC}"
            fi
        fi
    fi
}

# 批量创建合并请求（单个项目）
# 参数：$1 - 项目名称，$2 - 源分支
# 使用全局变量 selected_envs 作为环境列表
create_merge_requests_for_project() {
    local project_name="$1"
    local source_branch="$2"

    echo -e "\n${CYAN}${EMOJI_PROJECT} 项目: ${WHITE}$project_name${NC}"
    echo -e "${GREEN}${EMOJI_BRANCH} 源分支: ${WHITE}$source_branch${NC}"
    echo -e "${PURPLE}${EMOJI_ENV} 目标环境: ${WHITE}${selected_envs[*]}${NC}"

    # 为每个环境创建MR
    for env in "${selected_envs[@]}"; do
        local target_branch
        target_branch=$(get_target_branch_for_env "$env")
        create_merge_request "$project_name" "$source_branch" "$env" "$target_branch"
    done
}

# 批量创建合并请求（多个项目）
# 使用全局变量 selected_projects 和 selected_envs
create_merge_requests_for_all_projects() {
    print_step "创建合并请求"

    local total_projects=${#selected_projects[@]}
    local total_envs=${#selected_envs[@]}
    local total_mrs=$((total_projects * total_envs))

    echo -e "${BLUE}${EMOJI_INFO} 准备创建 ${WHITE}$total_mrs${NC} ${BLUE}个合并请求${NC}"
    echo -e "${GRAY}  项目数量: $total_projects${NC}"
    echo -e "${GRAY}  环境数量: $total_envs${NC}"

    local success_count=0
    local error_count=0

    # 为每个项目创建MR
    for project in "${selected_projects[@]}"; do
        # 为该项目创建所有环境的MR
        echo -e "\n${YELLOW}${EMOJI_LOADING} 处理项目: ${WHITE}$project${NC} ${GRAY}(分支: $selected_branch)${NC}"
        create_merge_requests_for_project "$project" "$selected_branch"
    done

    # 显示最终的MR结果汇总
    show_mr_summary
}

# 显示MR结果汇总
show_mr_summary() {


    if [[ ${#mr_env_names[@]} -eq 0 ]]; then
        echo -e "\n${YELLOW}${EMOJI_WARNING} 没有MR结果需要汇总${NC}"
        return
    fi

    echo -e "\n${WHITE}${EMOJI_MR} MR结果汇总${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"

    # 简洁的汇总格式：环境名: URL（根据状态着色）
    for env in "${selected_envs[@]}"; do
        # 查找该环境的所有MR
        for i in "${!mr_env_names[@]}"; do
            if [[ "${mr_env_names[$i]}" == "$env" ]]; then
                local url="${mr_urls[$i]}"
                local status="${mr_statuses[$i]}"

                if [[ "$url" == "失败" ]]; then
                    echo -e "${RED} ${env}: ${status}${NC}"
                elif [[ "$url" == "处理中" ]]; then
                    echo -e "${YELLOW} ${env}: ${status}${NC}"
                elif [[ "$status" == "已解决冲突" ]]; then
                    echo -e "${GREEN} ${env}: ${url}${NC}"
                elif [[ "$status" =~ 合并冲突 ]]; then
                    echo -e "${YELLOW} ${env}: ${url}${NC}"
                else
                    echo -e "${GREEN} ${env}: ${url}${NC}"
                fi
                break
            fi
        done
    done

    # 发送机器人通知（仅在配置了access_token时）
    if [[ -n "$hook_access_token" ]]; then
        local summary_message
        if summary_message=$(build_mr_summary_message); then
            echo ""
            read -p "$(print_info "是否发送机器人通知? [Y/n]: ")" send_notification
            send_notification=${send_notification:-Y}

            if [[ "$send_notification" =~ ^[Yy]$ ]]; then
                print_info "正在发送钉钉通知..."
                send_dingtalk_notification "$summary_message"
            else
                print_info "已跳过机器人通知"
            fi
        else
            print_warning "无法获取用户姓名信息，跳过机器人通知"
        fi
    fi
}

#######################################
# 主要工作流程函数
#######################################

# 主要的项目选择和MR创建流程
main_workflow() {
    # 显示欢迎信息
    echo -e "\n${WHITE}${EMOJI_ROCKET} GitLab 分支合并请求管理工具${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}\n"

    # 验证必要的配置
    validate_gitlab_token
    validate_project_config
    validate_env_config

    # 检查是否需要自动更新环境分支（仅在主工作流程中执行）
    if [[ "${#env_names[@]}" -gt 0 && "${#project_names[@]}" -gt 0 ]]; then
        if check_daily_update; then
            print_info "检测到今日首次运行，正在自动更新环境分支..."
            auto_update_env_branches
            echo ""  # 添加空行分隔
        fi
    fi

    # 清空全局选择数组和结果数组
    selected_projects=()
    selected_envs=()
    selected_branch=""
    mr_env_names=()
    mr_urls=()
    mr_statuses=()

    # 1. 选择项目（支持多选，带智能检测）
    select_projects

    # 2. 选择分支（基于项目信息）
    select_branch

    # 3. 选择环境（支持多选，带基于分支的智能检测）
    select_environments

    # 4. 创建合并请求（多项目 x 多环境）
    create_merge_requests_for_all_projects

    # 5. 检查是否需要自动合并到主分支
    if check_auto_merge_branch_prefix "$selected_branch"; then
        local main_branch
        main_branch=$(get_effective_main_branch)

        print_info "检测到源分支 '$selected_branch' 匹配自动合并条件"
        print_info "将自动合并到主分支: $main_branch"

        # 询问用户确认（除非是临时启用模式）
        if [[ "$temp_auto_merge_enabled" != "true" ]]; then
            echo -n -e "${YELLOW}${EMOJI_WARNING} 是否继续执行自动合并到主分支？[Y/n]: ${NC}"
            read auto_merge_confirm
            auto_merge_confirm=${auto_merge_confirm:-Y}

            if [[ ! "$auto_merge_confirm" =~ ^[Yy]$ ]]; then
                print_info "已跳过自动合并到主分支"
                return 0
            fi
        fi

        # 为每个项目执行自动合并
        for project in "${selected_projects[@]}"; do
            local project_path
            project_path=$(get_project_path "$project")

            if [[ -n "$project_path" && -d "$project_path" ]]; then
                auto_merge_to_main_branch "$project" "$project_path" "$selected_branch"
            else
                print_warning "项目 '$project' 路径无效，跳过自动合并"
            fi
        done
    fi

    # 显示完成信息
    echo -e "\n${WHITE}${EMOJI_ROCKET} 所有合并请求创建完成！${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
}

#######################################
# 钉钉机器人通知函数
#######################################

# 构建@人手机号JSON数组
# 输出：JSON格式的手机号数组
build_at_mobiles_json() {
    [[ -n "$hook_mobiles" ]] || return 1

    local at_mobiles=""
    IFS=',' read -ra MOBILES <<< "$hook_mobiles"
    for mobile in "${MOBILES[@]}"; do
        mobile=$(echo "$mobile" | tr -d ' ')  # 去除空格
        [[ -n "$mobile" ]] || continue

        if [[ -n "$at_mobiles" ]]; then
            at_mobiles="$at_mobiles,\"$mobile\""
        else
            at_mobiles="\"$mobile\""
        fi
    done

    [[ -n "$at_mobiles" ]] && echo "[$at_mobiles]"
}

# 构建钉钉消息JSON
# 参数：$1 - 消息内容
# 输出：完整的JSON消息体
build_dingtalk_json() {
    local message="$1"
    local content="$message"
    local final_message="${hook_message:-"[恭喜][恭喜][恭喜] 老板发财"}"
    content="$content
$final_message"

    # 转义JSON特殊字符，包括换行符
    content=$(echo "$content" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/g' | tr -d '\n' | sed 's/\\n$//')

    local at_mobiles_json
    if at_mobiles_json=$(build_at_mobiles_json); then
        echo "{\"msgtype\":\"text\",\"text\":{\"content\":\"$content\"},\"at\":{\"atMobiles\":$at_mobiles_json}}"
    else
        echo "{\"msgtype\":\"text\",\"text\":{\"content\":\"$content\"}}"
    fi
}

# 发送钉钉机器人通知
# 参数：$1 - 消息内容
send_dingtalk_notification() {
    local message="$1"

    # 检查是否配置了access_token
    [[ -n "$hook_access_token" ]] || return 0

    # 构建钉钉webhook URL
    local webhook_url="https://oapi.dingtalk.com/robot/send?access_token=$hook_access_token"

    # 构建JSON数据
    local json_data
    json_data=$(build_dingtalk_json "$message")

    # 发送请求
    if curl -s --max-time "$API_TIMEOUT" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$json_data" \
        "$webhook_url" >/dev/null 2>&1; then
        print_success "钉钉通知发送成功"
        return 0
    else
        print_warning "钉钉通知发送失败"
        return 1
    fi
}

# 组装MR结果汇总消息
# 输出：格式化的消息内容，如果没有name则返回空
build_mr_summary_message() {
    local message=""

    # 检查是否有name，如果没有则尝试获取
    if [[ -z "$gitlab_name" && -n "$gitlab_token" ]]; then
        print_info "正在获取GitLab用户信息..."
        fetch_gitlab_username
    fi

    # 构建用户信息行
    if [[ -n "$gitlab_name" ]]; then
        message="[$gitlab_name]"
    else
        # 没有name就不发送通知
        return 1
    fi

    # 添加MR链接
    for i in "${!mr_env_names[@]}"; do
        local env_name="${mr_env_names[$i]}"
        local mr_url="${mr_urls[$i]}"
        message="$message
$env_name: $mr_url"
    done

    echo "$message"
}

#######################################
# 环境变量管理函数
#######################################

# 环境变量名称定义
readonly ENV_GITLAB_TOKEN="GITLAB_TOKEN"
readonly ENV_GITLAB_USERNAME="GITLAB_USERNAME"
readonly ENV_GITLAB_NAME="GITLAB_NAME"
readonly ENV_LAST_UPDATE_DATE="LAST_UPDATE_DATE"
readonly ENV_HOOK_ACCESS_TOKEN="HOOK_ACCESS_TOKEN"
readonly ENV_HOOK_MOBILES="HOOK_MOBILES"
readonly ENV_HOOK_MESSAGE="HOOK_MESSAGE"
readonly ENV_AUTO_MERGE_ENABLED="AUTO_MERGE_TO_MAIN_ENABLED"
readonly ENV_AUTO_MERGE_PREFIXES="AUTO_MERGE_BRANCH_PREFIXES"
readonly ENV_MAIN_BRANCH_NAME="MAIN_BRANCH_NAME"

# 获取shell配置文件路径
get_shell_config_file() {
    # 首先检查用户的默认shell
    local user_shell
    user_shell=$(basename "${SHELL:-}" 2>/dev/null)

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
# 参数：$1 - 变量名，$2 - 变量值
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
        print_info "已更新环境变量 $var_name 在文件: $config_file"
    else
        # 添加新的环境变量（不重复添加注释）
        echo "export ${var_name}=\"${var_value}\"" >> "$config_file"
        print_success "已添加环境变量 $var_name 到文件: $config_file"
    fi

    # 立即设置到当前会话
    export "${var_name}=${var_value}"
}

# 将名称转换为有效的环境变量名称
# 参数：$1 - 原始名称
# 输出：有效的环境变量名称
sanitize_env_var_name() {
    local name="$1"
    # 处理中文和特殊字符的映射
    case "$name" in
        "灰度1") echo "GRAY1" ;;
        "灰度2") echo "GRAY2" ;;
        "灰度3") echo "GRAY3" ;;
        "灰度4") echo "GRAY4" ;;
        "灰度5") echo "GRAY5" ;;
        "灰度6") echo "GRAY6" ;;
        "预发1") echo "PREISSUE1" ;;
        "预发2") echo "PREISSUE2" ;;
        "vip") echo "VIP" ;;
        "线上") echo "PRODUCTION" ;;
        *)
            # 对于其他名称，将连字符转换为下划线，移除其他特殊字符
            echo "$name" | sed 's/-/_/g' | sed 's/[^a-zA-Z0-9_]//g'
            ;;
    esac
}

# 保存项目配置到环境变量（一一映射）
save_projects_to_env() {
    if [[ "${#project_names[@]}" -gt 0 ]]; then
        local config_file
        config_file=$(get_shell_config_file)

        # 添加项目配置分组注释
        if ! grep -q "# Project Configurations" "$config_file" 2>/dev/null; then
            echo "" >> "$config_file"
            echo "# Project Configurations" >> "$config_file"
        fi

        for i in "${!project_names[@]}"; do
            local project_name="${project_names[$i]}"
            local project_path="${project_paths[$i]}"
            local safe_name
            safe_name=$(sanitize_env_var_name "$project_name")
            set_env_variable "PROJECT_${safe_name}" "$project_path"
        done
    fi
}

# 保存环境配置到环境变量（一一映射）
save_envs_to_env() {
    if [[ "${#env_names[@]}" -gt 0 ]]; then
        local config_file
        config_file=$(get_shell_config_file)

        # 添加环境配置分组注释
        if ! grep -q "# Environment Configurations" "$config_file" 2>/dev/null; then
            echo "" >> "$config_file"
            echo "# Environment Configurations" >> "$config_file"
        fi

        for i in "${!env_names[@]}"; do
            local env_name="${env_names[$i]}"
            local env_branch="${env_branches[$i]}"
            local safe_name
            safe_name=$(sanitize_env_var_name "$env_name")
            set_env_variable "ENV_${safe_name}" "$env_branch"
        done
    fi
}

# 将环境变量名称转换回原始名称
# 参数：$1 - 环境变量名称
# 输出：原始名称
restore_original_name() {
    local env_name="$1"
    # 处理中文和特殊字符的逆映射
    case "$env_name" in
        "GRAY1") echo "灰度1" ;;
        "GRAY2") echo "灰度2" ;;
        "GRAY3") echo "灰度3" ;;
        "GRAY4") echo "灰度4" ;;
        "GRAY5") echo "灰度5" ;;
        "GRAY6") echo "灰度6" ;;
        "PREISSUE1") echo "预发1" ;;
        "PREISSUE2") echo "预发2" ;;
        "VIP") echo "vip" ;;
        "PRODUCTION") echo "线上" ;;
        *)
            # 对于其他名称，将下划线转换回连字符
            echo "$env_name" | sed 's/_/-/g'
            ;;
    esac
}

# 从环境变量加载项目配置（一一映射）
load_projects_from_env() {
    # 清空现有数组
    project_names=()
    project_paths=()

    # 定义项目的预期顺序（基于配置文件中的顺序）
    local expected_projects=("project-core" "project-platform" "project-pt" "project-trade-project" "project-data" "project-items-core")

    # 按预期顺序加载项目
    for project_name in "${expected_projects[@]}"; do
        local safe_name
        safe_name=$(sanitize_env_var_name "$project_name")
        local var_name="PROJECT_${safe_name}"
        local project_path="${!var_name:-}"

        if [[ -n "$project_path" ]]; then
            project_names+=("$project_name")
            project_paths+=("$project_path")
        fi
    done

    # 加载其他未在预期列表中的项目
    for var_name in $(env | grep '^PROJECT_' | cut -d'=' -f1); do
        local safe_project_name="${var_name#PROJECT_}"
        local original_project_name
        original_project_name=$(restore_original_name "$safe_project_name")
        local project_path="${!var_name}"

        # 检查是否已经在预期列表中
        local already_loaded=false
        for existing_name in "${project_names[@]}"; do
            if [[ "$existing_name" == "$original_project_name" ]]; then
                already_loaded=true
                break
            fi
        done

        if [[ "$already_loaded" == "false" && -n "$project_path" ]]; then
            project_names+=("$original_project_name")
            project_paths+=("$project_path")
        fi
    done
}

# 从环境变量加载环境配置（一一映射）
load_envs_from_env() {
    # 清空现有数组
    env_names=()
    env_branches=()

    # 定义环境的预期顺序（基于配置文件中的顺序）
    local expected_envs=("灰度1" "灰度2" "灰度3" "灰度4" "灰度5" "灰度6" "预发1" "预发2" "vip" "线上")

    # 按预期顺序加载环境
    for env_name in "${expected_envs[@]}"; do
        local safe_name
        safe_name=$(sanitize_env_var_name "$env_name")
        local var_name="ENV_${safe_name}"
        local env_branch="${!var_name:-}"

        if [[ -n "$env_branch" ]]; then
            env_names+=("$env_name")
            env_branches+=("$env_branch")
        fi
    done

    # 加载其他未在预期列表中的环境
    for var_name in $(env | grep '^ENV_' | cut -d'=' -f1); do
        local safe_env_name="${var_name#ENV_}"
        local original_env_name
        original_env_name=$(restore_original_name "$safe_env_name")
        local env_branch="${!var_name}"

        # 检查是否已经在预期列表中
        local already_loaded=false
        for existing_name in "${env_names[@]}"; do
            if [[ "$existing_name" == "$original_env_name" ]]; then
                already_loaded=true
                break
            fi
        done

        if [[ "$already_loaded" == "false" && -n "$env_branch" ]]; then
            env_names+=("$original_env_name")
            env_branches+=("$env_branch")
        fi
    done
}

# 添加项目脚本配置注释块到配置文件
add_project_config_header() {
    local config_file
    config_file=$(get_shell_config_file)

    # 检查是否已存在完整的项目配置注释块
    if ! grep -q "# ============================================" "$config_file" 2>/dev/null || \
       ! grep -q "# Project Scripts Configuration" "$config_file" 2>/dev/null; then
        echo "" >> "$config_file"
        echo "# ============================================" >> "$config_file"
        echo "# Project Scripts Configuration" >> "$config_file"
        echo "# Generated by br.sh - $(date '+%Y-%m-%d %H:%M:%S')" >> "$config_file"
        echo "# ============================================" >> "$config_file"
    fi
}

# 保存所有配置到环境变量
save_all_config_to_env() {
    print_info "正在保存配置到环境变量..."

    # 添加配置注释头
    add_project_config_header

    # 保存基本配置
    [[ -n "$gitlab_token" ]] && set_env_variable "$ENV_GITLAB_TOKEN" "$gitlab_token"
    [[ -n "$gitlab_username" ]] && set_env_variable "$ENV_GITLAB_USERNAME" "$gitlab_username"
    [[ -n "$gitlab_name" ]] && set_env_variable "$ENV_GITLAB_NAME" "$gitlab_name"
    [[ -n "$last_update_date" ]] && set_env_variable "$ENV_LAST_UPDATE_DATE" "$last_update_date"
    [[ -n "$hook_access_token" ]] && set_env_variable "$ENV_HOOK_ACCESS_TOKEN" "$hook_access_token"
    [[ -n "$hook_mobiles" ]] && set_env_variable "$ENV_HOOK_MOBILES" "$hook_mobiles"
    [[ -n "$hook_message" ]] && set_env_variable "$ENV_HOOK_MESSAGE" "$hook_message"
    [[ -n "$auto_merge_to_main_enabled" ]] && set_env_variable "$ENV_AUTO_MERGE_ENABLED" "$auto_merge_to_main_enabled"
    [[ -n "$auto_merge_branch_prefixes" ]] && set_env_variable "$ENV_AUTO_MERGE_PREFIXES" "$auto_merge_branch_prefixes"
    [[ -n "$main_branch_name" ]] && set_env_variable "$ENV_MAIN_BRANCH_NAME" "$main_branch_name"

    # 保存项目和环境配置（一一映射）
    if [[ "${#project_names[@]}" -gt 0 ]]; then
        save_projects_to_env
    fi

    if [[ "${#env_names[@]}" -gt 0 ]]; then
        save_envs_to_env
    fi

    print_success "配置已保存到环境变量"
}

# 从环境变量加载所有配置
load_all_config_from_env() {
    # 加载基本配置
    gitlab_token="${!ENV_GITLAB_TOKEN:-}"
    gitlab_username="${!ENV_GITLAB_USERNAME:-}"
    gitlab_name="${!ENV_GITLAB_NAME:-}"
    last_update_date="${!ENV_LAST_UPDATE_DATE:-}"
    hook_access_token="${!ENV_HOOK_ACCESS_TOKEN:-}"
    hook_mobiles="${!ENV_HOOK_MOBILES:-}"
    hook_message="${!ENV_HOOK_MESSAGE:-}"
    auto_merge_to_main_enabled="${!ENV_AUTO_MERGE_ENABLED:-false}"
    auto_merge_branch_prefixes="${!ENV_AUTO_MERGE_PREFIXES:-feature,hotfix}"
    main_branch_name="${!ENV_MAIN_BRANCH_NAME:-main}"

    # 加载项目和环境配置（一一映射）
    load_projects_from_env
    load_envs_from_env
}

# 初始化GitLab Token环境变量（已集成到统一配置加载中）
init_gitlab_token_env() {
    # 这个函数现在主要用于向后兼容
    # 实际的token初始化已经在load_config中处理
    local current_env_token="${GITLAB_TOKEN:-}"

    if [[ -n "$current_env_token" ]]; then
        gitlab_token="$current_env_token"
        print_info "使用环境变量中的 GitLab Token"
    fi
}

#######################################
# Token管理函数
#######################################

# 设置GitLab Token
# 参数：$1 - Token值
set_gitlab_token() {
    local token="$1"

    [[ -n "$token" ]] || print_error_and_exit "必须指定Token值"

    # 设置到环境变量
    set_env_variable "$ENV_GITLAB_TOKEN" "$token"
    gitlab_token="$token"

    # 尝试获取用户信息
    if fetch_gitlab_username; then
        if [[ -n "$gitlab_name" ]]; then
            print_success "GitLab Token 已设置到环境变量，用户名: $gitlab_username，姓名: $gitlab_name"
        else
            print_success "GitLab Token 已设置到环境变量，用户名: $gitlab_username"
        fi
        # 保存用户信息到环境变量
        save_config
    else
        print_success "GitLab Token 已设置到环境变量"
        print_warning "无法获取用户信息，请检查Token权限"
    fi

    print_warning "请重新打开终端或执行 'source $(get_shell_config_file)' 使环境变量永久生效"
}



# 设置机器人Hook配置
# 参数：$1 - 配置类型:值（token:access_token 或 mobiles:手机号列表 或 message:消息内容）
set_hook_config() {
    local input="${1:-}"

    if [[ -z "$input" ]]; then
        # 交互式配置
        print_info "机器人Hook配置（输入 'q' 退出）"

        # 配置access_token
        if [[ -z "$hook_access_token" ]]; then
            read -p "$(print_info "请输入机器人access_token: ")" token
            if [[ -n "$token" && "$token" != "q" ]]; then
                hook_access_token="$token"
            fi
        else
            local masked_token="${hook_access_token:0:8}***${hook_access_token: -4}"
            echo -e "${GREEN}当前access_token: $masked_token${NC}"
            read -p "$(print_info "是否修改access_token? [y/N]: ")" modify
            if [[ "$modify" =~ ^[Yy]$ ]]; then
                read -p "$(print_info "请输入新的access_token: ")" token
                if [[ -n "$token" ]]; then
                    hook_access_token="$token"
                fi
            fi
        fi

        # 配置@人手机号
        echo -e "${GREEN}当前@人手机号: ${hook_mobiles:-"未配置"}${NC}"
        read -p "$(print_info "请输入@人手机号(逗号分隔，留空跳过): ")" mobiles
        if [[ -n "$mobiles" ]]; then
            hook_mobiles="$mobiles"
        fi

        # 配置消息补充内容
        local current_message="${hook_message:-"[恭喜][恭喜][恭喜] 老板发财"}"
        echo -e "${GREEN}当前消息补充: $current_message${NC}"
        read -p "$(print_info "请输入消息补充内容(留空跳过): ")" message
        if [[ -n "$message" ]]; then
            hook_message="$message"
        fi

        save_config
        print_success "机器人Hook配置已更新"
    else
        # 单项配置
        if [[ "$input" =~ ^token:(.+)$ ]]; then
            hook_access_token="${BASH_REMATCH[1]}"
            print_success "机器人access_token已更新"
        elif [[ "$input" =~ ^mobiles:(.+)$ ]]; then
            hook_mobiles="${BASH_REMATCH[1]}"
            print_success "机器人@人手机号已更新: $hook_mobiles"
        elif [[ "$input" =~ ^message:(.+)$ ]]; then
            hook_message="${BASH_REMATCH[1]}"
            print_success "机器人消息补充已更新: $hook_message"
        else
            print_error_and_exit "Hook配置格式错误，正确格式：token:access_token 或 mobiles:手机号列表 或 message:消息内容"
        fi
        save_config
    fi
}

#######################################
# 主程序入口
#######################################

# 初始化脚本
# 参数：传递给脚本的所有原始参数
init_script() {
    # 加载配置文件
    load_config

    # 初始化GitLab Token环境变量
    init_gitlab_token_env

    # 检查脚本更新（在有Token的情况下）
    if [[ -n "$gitlab_token" ]]; then
        # 使用新的sv.sh进行更新检查
        local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
        if [[ -f "$sv_script" ]]; then
            # 使用子shell避免变量冲突
            (source "$sv_script" && check_script_update "br.sh") 2>/dev/null || true
        else
            # 回退到原有的更新方式
            check_and_update_br_script "$@"
        fi
    fi

    # 如果存在token但没有用户信息，则获取用户信息
    if [[ -n "$gitlab_token" && (-z "$gitlab_username" || -z "$gitlab_name") ]]; then
        if fetch_gitlab_username; then
            if [[ -n "$gitlab_name" ]]; then
                print_success "已获取GitLab用户信息: $gitlab_username ($gitlab_name)"
            else
                print_success "已获取GitLab用户名: $gitlab_username"
            fi
        fi
    fi

    # 检查必要的命令是否存在
    if ! command -v curl >/dev/null 2>&1; then
        print_error_and_exit "curl 命令未找到，请先安装 curl"
    fi

    if ! command -v git >/dev/null 2>&1; then
        print_warning "git 命令未找到，分支检测功能将不可用"
    fi
}

# 主逻辑处理
main() {
    # 初始化脚本，传递所有参数
    init_script "$@"

    # 解析命令行参数
    case "${1:-}" in
        -h|--help)
            show_help
            ;;
        -e|--env)
            shift
            init_env_config "${1:-}"
            ;;
        -p|--project)
            shift
            init_project_config "${1:-}"
            ;;
        -t|--token)
            shift
            set_gitlab_token "${1:-}"
            ;;
        -lp|--list-projects)
            list_projects
            ;;
        -le|--list-envs)
            list_environments
            ;;
        -l|--list)
            list_all_config
            ;;
        -u|--update)
            # 手动更新环境分支
            validate_project_config
            validate_env_config
            shift
            auto_update_env_branches "${1:-}"
            ;;
        -us|--update-script)
            # 手动触发脚本更新检查
            if [[ -n "${GITLAB_TOKEN:-}" ]]; then
                local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
                if [[ -f "$sv_script" ]]; then
                    # 使用子shell避免变量冲突
                    if (source "$sv_script" && check_script_update "br.sh") 2>/dev/null; then
                        print_success "脚本更新检查完成"
                        exit 0
                    else
                        print_error "脚本更新检查失败"
                        exit 1
                    fi
                else
                    print_error_and_exit "更新脚本不存在: $sv_script"
                fi
            else
                print_error_and_exit "未设置 GITLAB_TOKEN 环境变量，无法检查更新。请先使用 sv.sh -c 进行配置"
            fi
            ;;
        -hk|--hook)
            # 配置机器人Hook
            shift
            set_hook_config "${1:-}"
            ;;
        -am|--auto-merge)
            # 配置自动合并到主分支功能
            shift
            init_auto_merge_config "${1:-}"
            ;;
        -amc|--auto-merge-current)
            # 临时启用自动合并功能（仅本次执行有效）
            temp_auto_merge_enabled="true"
            print_success "已临时启用自动合并到主分支功能（仅本次执行有效）"
            # 继续执行主工作流程
            main_workflow
            ;;
        -amb|--auto-merge-branch)
            # 临时指定主分支名称
            shift
            temp_main_branch="${1:-}"
            [[ -n "$temp_main_branch" ]] || print_error_and_exit "主分支名称不能为空"
            print_success "已临时指定主分支为: $temp_main_branch（仅本次执行有效）"
            # 继续执行主工作流程
            main_workflow
            ;;
        -migrate|--migrate-config)
            # 手动触发配置迁移到环境变量
            if has_config_in_file; then
                print_info "检测到配置文件，开始迁移..."
                load_config_from_file
                migrate_config_to_env
            else
                print_info "没有检测到配置文件或配置文件为空"
            fi
            ;;
        "")
            # 默认行为：启动主工作流程
            main_workflow
            ;;
        *)
            print_error_and_exit "未知选项: $1，使用 -h 查看帮助信息"
            ;;
    esac
}

# 脚本入口点
main "$@"