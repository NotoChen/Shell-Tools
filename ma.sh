#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.5"

set -e

TOKEN="${GITLAB_TOKEN:-}"
LEADER_TOKEN="${GITLAB_LEADER_TOKEN:-}"
AUTHOR_WHITELIST="${MR_AUTHOR_WHITELIST:-}"
BOT_USER_ID="1013"  # 机器人用户ID
DEBUG_MODE="${MA_DEBUG:-false}"
SKIP_APPROVAL_CHECK="${MA_SKIP_APPROVAL_CHECK:-false}"

GITLAB_HOST="gitlab.example.com"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
BOLD='\033[1m'
NC='\033[0m' # 无颜色

# Emoji 图标
readonly SUCCESS="✅"
readonly FAILED="❌"
readonly WARNING="⚠️"
readonly SPARKLES="✨"
readonly ROCKET="🚀"
readonly GEAR="⚙️"
readonly SEARCH="🔍"
readonly LIST="📋"
readonly USER="👤"
readonly PROJECT="📁"
readonly BRANCH="🌿"
readonly COMMIT="💾"
readonly TIME="⏰"
readonly LINK="🔗"

# 调试输出函数
debug_log() {
    if [[ "$DEBUG_MODE" == "true" ]]; then
        echo -e "${GRAY}[DEBUG] $1${NC}" >&2
    fi
}

# 获取shell配置文件路径
get_shell_config_file() {
    if [[ -n "$ZSH_VERSION" ]]; then
        echo "$HOME/.zshrc"
    elif [[ -n "$BASH_VERSION" ]]; then
        if [[ -f "$HOME/.bash_profile" ]]; then
            echo "$HOME/.bash_profile"
        else
            echo "$HOME/.bashrc"
        fi
    else
        echo "$HOME/.profile"
    fi
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
        echo -e "${CYAN}${SPARKLES} 已更新环境变量 $var_name 在文件: $config_file${NC}"
    else
        # 添加新的环境变量
        echo "" >> "$config_file"
        echo "# ERP Scripts Configuration" >> "$config_file"
        echo "export ${var_name}=\"${var_value}\"" >> "$config_file"
        echo -e "${GREEN}${SUCCESS} 已添加环境变量 $var_name 到文件: $config_file${NC}"
    fi

    # 立即设置到当前会话
    export "${var_name}=${var_value}"
    echo -e "${CYAN}${SPARKLES} 环境变量已在当前会话中生效${NC}"
    echo -e "${YELLOW}${WARNING} 请重新打开终端或执行 'source $config_file' 使环境变量永久生效${NC}"
}

# 检查并设置 TOKEN
check_and_set_token() {
  if [[ -z "$TOKEN" ]]; then
    echo -e "${YELLOW}${WARNING} 检测到未设置 GitLab Token${NC}"
    echo -e "${CYAN}请输入您的 GitLab Personal Access Token:${NC}"
    echo -e "${BLUE}(Token 将自动保存到环境变量中，下次无需重新输入)${NC}"
    echo ""
    read -p "Token: " user_token

    if [[ -n "$user_token" ]]; then
      # 设置到环境变量
      set_env_variable "GITLAB_TOKEN" "$user_token"
      TOKEN="$user_token"
      echo ""
      echo -e "${GREEN}${SUCCESS} Token 已保存到环境变量，继续执行...${NC}"
      echo ""
    else
      echo -e "${RED}${FAILED} Token 不能为空${NC}"
      exit 1
    fi
  fi
}

# 打印脚本使用说明
print_usage() {
    echo -e "${BOLD}${BLUE}${SPARKLES} MA - Merge Approvals ${GRAY}(合并请求自动处理工具)${NC}"
    echo -e "${CYAN}使用方法:${NC}"
    echo -e "  $0                           # 交互模式：自动获取并选择MR"
    echo -e "  $0 [合并请求URL1] [URL2] ... # 直接处理指定的MR"
    echo ""
    echo -e "${CYAN}示例:${NC}"
    echo -e "  $0  # 进入交互模式"
    echo -e "  $0 https://gitlab.example.com/project/project-core/merge_requests/15128"
    echo ""
    echo -e "${CYAN}选项:${NC}"
    echo -e "  -u, --update              手动检查脚本更新"
    echo -e "  -w, --whitelist           管理白名单"
    echo -e "  -w add <用户名或ID>       添加用户到白名单"
    echo -e "  -w remove <用户名或ID>    从白名单移除用户"
    echo -e "  -w list                   显示当前白名单"
    echo -e "  -w clear                  清空白名单"
    echo -e "  --test-api                测试API调用，显示原始响应"
    echo ""
    echo -e "${CYAN}环境变量:${NC}"
    echo -e "  GITLAB_TOKEN              GitLab Personal Access Token"
    echo -e "  MR_AUTHOR_WHITELIST       MR创建人白名单，支持用户名或用户ID，用逗号分隔"
    echo -e "  MA_DEBUG                  启用调试模式 (true/false)"
    echo -e "  MA_SKIP_APPROVAL_CHECK    跳过审批权限检查，显示所有MR (true/false)"
    echo ""
    echo -e "${CYAN}白名单示例:${NC}"
    echo -e "  export MR_AUTHOR_WHITELIST=\"用户A,用户B,123,456\"  # 混合用户名和ID"
    echo -e "  export MR_AUTHOR_WHITELIST=\"123,456,789\"       # 纯用户ID（推荐）"
    echo ""
    echo -e "${CYAN}调试模式使用:${NC}"
    echo -e "  export MA_DEBUG=true && ./ma.sh  # 启用详细调试输出"
    echo ""
    echo -e "${CYAN}权限说明:${NC}"
    echo -e "  脚本会自动过滤项目权限，只显示您有Maintainer权限(access_level >= 40)的项目中的MR"
    echo -e "  这样可以避免显示无法审批的MR，提高效率"
    echo ""
    echo -e "${CYAN}${SPARKLES} 首次使用会提示输入 GitLab Token，自动保存到环境变量${NC}"
}

# 检查提交是否在main分支中
check_commits_in_main() {
    local host=$1
    local encoded_project_path=$2
    local mr_id=$3
    local project_path=$4

    commits_info=$(curl -s --request GET \
        --header "PRIVATE-TOKEN: $TOKEN" \
        "http://$host/api/v4/projects/$encoded_project_path/merge_requests/$mr_id/commits")

    # 计算提交数量
    if command -v jq &> /dev/null; then
        commit_count=$(echo "$commits_info" | jq '. | length')
        echo -e "${BOLD}${BLUE}本次合并请求共包含 ${commit_count} 个提交${NC}"

        # 获取提交的最早和最晚时间
        earliest_date=$(echo "$commits_info" | jq -r '[.[].created_at] | min')
        latest_date=$(echo "$commits_info" | jq -r '[.[].created_at] | max')
    else
        # 对于不支持jq的情况，我们使用grep和sort来获取日期
        all_dates=$(echo "$commits_info" | grep -o '"created_at":"[^"]*"' | cut -d'"' -f4)
        earliest_date=$(echo "$all_dates" | sort | head -1)
        latest_date=$(echo "$all_dates" | sort | tail -1)
    fi

    # GitLab API 需要 ISO 8601 格式（含时区信息）
    # 我们不需要改变时区信息，只需要确保格式正确，并调整日期
    # 提取当前日期时区信息
    timezone_part=$(echo "$earliest_date" | grep -o '+[0-9]\{2\}:[0-9]\{2\}$' || echo '+08:00')

    # 添加时间缓冲（前后各1天）
    if command -v date &> /dev/null; then
        # 先将日期部分提取出来，不包含时区
        earliest_date_main=$(echo "$earliest_date" | sed 's/+[0-9]\{2\}:[0-9]\{2\}$//')
        latest_date_main=$(echo "$latest_date" | sed 's/+[0-9]\{2\}:[0-9]\{2\}$//')

        # 使用date命令调整日期
        earliest_with_buffer=$(date -v -1d -j -f '%Y-%m-%dT%H:%M:%S.000' "$earliest_date_main" '+%Y-%m-%dT%H:%M:%S.000Z')
        latest_with_buffer=$(date -v +1d -j -f '%Y-%m-%dT%H:%M:%S.000' "$latest_date_main" '+%Y-%m-%dT%H:%M:%S.000Z')

        # 添加回时区信息
        earliest_date_with_buffer="${earliest_with_buffer}${timezone_part}"
        latest_date_with_buffer="${latest_with_buffer}${timezone_part}"
    else
        # 如果date命令不可用，直接使用原始日期
        earliest_date_with_buffer=$earliest_date
        latest_date_with_buffer=$latest_date
    fi

    # 对URL中的日期参数进行正确的URL编码
    earliest_date_encoded=$(echo "$earliest_date_with_buffer" | sed 's/:/%3A/g' | sed 's/+/%2B/g')
    latest_date_encoded=$(echo "$latest_date_with_buffer" | sed 's/:/%3A/g' | sed 's/+/%2B/g')

    # 获取main分支在指定时间范围内的提交，使用正确的参数名 ref_name
    main_commits=$(curl -s --request GET \
        --header "PRIVATE-TOKEN: $TOKEN" \
        "http://$host/api/v4/projects/$encoded_project_path/repository/commits?ref_name=main&since=$earliest_date_encoded&until=$latest_date_encoded&per_page=100")

    # 提取main分支所有提交哈希
    if command -v jq &> /dev/null; then
        main_commit_hashes=$(echo "$main_commits" | jq -r '.[].id')
    else
        main_commit_hashes=$(echo "$main_commits" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    fi

    # 标记是否有未合并的提交
    local has_unmerged=false

    # 逐个检查合并请求中的提交
    if command -v jq &> /dev/null; then
        while read -r commit; do
            commit_hash=$(echo "$commit" | jq -r '.id')
            commit_title=$(echo "$commit" | jq -r '.title')
            commit_author=$(echo "$commit" | jq -r '.author_name')
            commit_date=$(echo "$commit" | jq -r '.created_at')

            # 过滤掉merge相关提交
            if [[ "$commit_title" == *"Merge "* ]] || [[ "$commit_title" == *"merge "* ]]; then
                continue
            fi

            # 检查提交是否在main分支中
            if echo "$main_commit_hashes" | grep -q "$commit_hash"; then
                echo -e "${GREEN}✓ ${GRAY}$commit_hash${NC} - ${BLUE}已合并到main${NC}"
            else
                echo -e "${RED}✗ ${GRAY}$commit_hash${NC} - ${YELLOW}未合并到main${NC}"
                echo -e "   ${BOLD}提交信息:${NC} $commit_title"
                echo -e "   ${BOLD}作者:${NC} $commit_author"
                echo -e "   ${BOLD}时间:${NC} $commit_date"
                has_unmerged=true
            fi
        done < <(echo "$commits_info" | jq -c '.[]')
    else
        # 备用方案，不使用jq
        commit_lines=$(echo "$commits_info" | grep -o '{[^}]*}')
        while read -r commit_line; do
            commit_hash=$(echo "$commit_line" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
            commit_title=$(echo "$commit_line" | grep -o '"title":"[^"]*"' | cut -d'"' -f4)
            commit_author=$(echo "$commit_line" | grep -o '"author_name":"[^"]*"' | cut -d'"' -f4)
            commit_date=$(echo "$commit_line" | grep -o '"created_at":"[^"]*"' | cut -d'"' -f4)

            # 过滤掉merge相关提交
            if [[ "$commit_title" == *"Merge "* ]] || [[ "$commit_title" == *"merge "* ]]; then
                continue
            fi

            # 检查提交是否在main分支中
            if echo "$main_commit_hashes" | grep -q "$commit_hash"; then
                echo -e "${GREEN}✓ ${GRAY}$commit_hash${NC} - ${BLUE}已合并到main${NC}"
            else
                echo -e "${RED}✗ ${GRAY}$commit_hash${NC} - ${YELLOW}未合并到main${NC}"
                echo -e "   ${BOLD}提交信息:${NC} $commit_title"
                echo -e "   ${BOLD}作者:${NC} $commit_author"
                echo -e "   ${BOLD}时间:${NC} $commit_date"
                has_unmerged=true
            fi
        done < <(echo "$commit_lines")
    fi
    # 总结检查结果
    if "$has_unmerged"; then
        echo -e "${BOLD}${YELLOW}⚠️ 有提交尚未合并到main分支，请检查${NC}"
    else
        echo -e "${BOLD}${GREEN}✅ 所有提交已成功合并到main分支${NC}"
    fi
}

# 白名单管理函数
manage_whitelist() {
    local action="$1"
    local user_input="$2"

    case "$action" in
        add)
            if [[ -z "$user_input" ]]; then
                echo -e "${RED}${FAILED} 请提供要添加的用户名或ID${NC}"
                return 1
            fi
            add_to_whitelist "$user_input"
            ;;
        remove)
            if [[ -z "$user_input" ]]; then
                echo -e "${RED}${FAILED} 请提供要移除的用户名或ID${NC}"
                return 1
            fi
            remove_from_whitelist "$user_input"
            ;;
        list)
            show_whitelist
            ;;
        clear)
            clear_whitelist
            ;;
        *)
            echo -e "${RED}${FAILED} 无效的白名单操作: $action${NC}"
            echo -e "${CYAN}支持的操作: add, remove, list, clear${NC}"
            return 1
            ;;
    esac
}

# 添加用户到白名单
add_to_whitelist() {
    local user_input="$1"
    local user_id=""
    local user_name=""

    # 检查是否为纯数字（用户ID）
    if [[ "$user_input" =~ ^[0-9]+$ ]]; then
        user_id="$user_input"
        # 获取用户名用于注释
        user_info=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$GITLAB_HOST/api/v4/users/$user_id")

        if command -v jq &> /dev/null; then
            user_name=$(echo "$user_info" | jq -r '.name // .username // "未知用户"')
        else
            user_name=$(echo "$user_info" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
            [[ -z "$user_name" ]] && user_name=$(echo "$user_info" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
            [[ -z "$user_name" ]] && user_name="未知用户"
        fi
    else
        # 搜索用户名获取用户ID
        user_search=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$GITLAB_HOST/api/v4/users?search=$user_input&per_page=10")

        if command -v jq &> /dev/null; then
            user_id=$(echo "$user_search" | jq -r ".[] | select(.name == \"$user_input\" or .username == \"$user_input\") | .id" | head -1)
            user_name=$(echo "$user_search" | jq -r ".[] | select(.name == \"$user_input\" or .username == \"$user_input\") | .name" | head -1)
        fi

        if [[ -z "$user_id" || "$user_id" == "null" ]]; then
            echo -e "${RED}${FAILED} 未找到用户: $user_input${NC}"
            return 1
        fi
    fi

    # 检查是否已存在
    if [[ -n "$AUTHOR_WHITELIST" && ",$AUTHOR_WHITELIST," == *",$user_id,"* ]]; then
        echo -e "${YELLOW}${WARNING} 用户 $user_name (ID: $user_id) 已在白名单中${NC}"
        return 0
    fi

    # 添加到白名单
    if [[ -n "$AUTHOR_WHITELIST" ]]; then
        AUTHOR_WHITELIST="$AUTHOR_WHITELIST,$user_id"
    else
        AUTHOR_WHITELIST="$user_id"
    fi

    # 更新环境变量，包含注释
    update_whitelist_env "$AUTHOR_WHITELIST"

    echo -e "${GREEN}${SUCCESS} 已添加用户 $user_name (ID: $user_id) 到白名单${NC}"
}

# 从白名单移除用户
remove_from_whitelist() {
    local user_input="$1"
    local user_id=""

    if [[ -z "$AUTHOR_WHITELIST" ]]; then
        echo -e "${YELLOW}${WARNING} 白名单为空${NC}"
        return 0
    fi

    # 检查是否为纯数字（用户ID）
    if [[ "$user_input" =~ ^[0-9]+$ ]]; then
        user_id="$user_input"
    else
        # 搜索用户名获取用户ID
        user_search=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$GITLAB_HOST/api/v4/users?search=$user_input&per_page=10")

        if command -v jq &> /dev/null; then
            user_id=$(echo "$user_search" | jq -r ".[] | select(.name == \"$user_input\" or .username == \"$user_input\") | .id" | head -1)
        fi

        if [[ -z "$user_id" || "$user_id" == "null" ]]; then
            echo -e "${RED}${FAILED} 未找到用户: $user_input${NC}"
            return 1
        fi
    fi

    # 从白名单中移除
    AUTHOR_WHITELIST=$(echo "$AUTHOR_WHITELIST" | sed "s/^$user_id,//;s/,$user_id,/,/;s/,$user_id$//;s/^$user_id$//")

    # 更新环境变量
    update_whitelist_env "$AUTHOR_WHITELIST"

    echo -e "${GREEN}${SUCCESS} 已从白名单移除用户 (ID: $user_id)${NC}"
}

# 显示当前白名单
show_whitelist() {
    if [[ -z "$AUTHOR_WHITELIST" ]]; then
        echo -e "${YELLOW}${WARNING} 白名单为空${NC}"
        return 0
    fi

    echo -e "${BOLD}${BLUE}当前白名单:${NC}"
    IFS=',' read -ra USER_IDS <<< "$AUTHOR_WHITELIST"
    for user_id in "${USER_IDS[@]}"; do
        user_info=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$GITLAB_HOST/api/v4/users/$user_id")

        if command -v jq &> /dev/null; then
            user_name=$(echo "$user_info" | jq -r '.name // "未知用户"')
            username=$(echo "$user_info" | jq -r '.username // "未知"')
        else
            user_name=$(echo "$user_info" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
            username=$(echo "$user_info" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
            [[ -z "$user_name" ]] && user_name="未知用户"
            [[ -z "$username" ]] && username="未知"
        fi

        echo -e "  ${YELLOW}$user_id${NC} - ${GREEN}$user_name${NC} (@$username)"
    done
}

# 清空白名单
clear_whitelist() {
    AUTHOR_WHITELIST=""
    update_whitelist_env ""
    echo -e "${GREEN}${SUCCESS} 已清空白名单${NC}"
}

# 更新白名单环境变量（带注释）
update_whitelist_env() {
    local whitelist_value="$1"
    local config_file

    config_file=$(get_shell_config_file)

    # 构建注释
    local comment=""
    if [[ -n "$whitelist_value" ]]; then
        comment="# MR Author Whitelist: "
        IFS=',' read -ra USER_IDS <<< "$whitelist_value"
        local user_names=()

        for user_id in "${USER_IDS[@]}"; do
            user_info=$(curl -s --request GET \
                --header "PRIVATE-TOKEN: $TOKEN" \
                "http://$GITLAB_HOST/api/v4/users/$user_id" 2>/dev/null)

            if command -v jq &> /dev/null; then
                user_name=$(echo "$user_info" | jq -r '.name // "ID'$user_id'"' 2>/dev/null)
            else
                user_name=$(echo "$user_info" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4 2>/dev/null)
                [[ -z "$user_name" ]] && user_name="ID$user_id"
            fi
            user_names+=("$user_name")
        done

        comment="$comment$(IFS=', '; echo "${user_names[*]}")"
    fi

    # 更新环境变量
    if grep -q "^export MR_AUTHOR_WHITELIST=" "$config_file" 2>/dev/null; then
        # 更新现有的环境变量
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            if [[ -n "$whitelist_value" ]]; then
                sed -i '' "/^export MR_AUTHOR_WHITELIST=/c\\
$comment\\
export MR_AUTHOR_WHITELIST=\"$whitelist_value\"" "$config_file"
            else
                sed -i '' '/^export MR_AUTHOR_WHITELIST=/d' "$config_file"
                sed -i '' '/^# MR Author Whitelist:/d' "$config_file"
            fi
        else
            # Linux
            if [[ -n "$whitelist_value" ]]; then
                sed -i "/^export MR_AUTHOR_WHITELIST=/c\\$comment\\nexport MR_AUTHOR_WHITELIST=\"$whitelist_value\"" "$config_file"
            else
                sed -i '/^export MR_AUTHOR_WHITELIST=/d' "$config_file"
                sed -i '/^# MR Author Whitelist:/d' "$config_file"
            fi
        fi
    else
        # 添加新的环境变量
        if [[ -n "$whitelist_value" ]]; then
            echo "" >> "$config_file"
            echo "$comment" >> "$config_file"
            echo "export MR_AUTHOR_WHITELIST=\"$whitelist_value\"" >> "$config_file"
        fi
    fi

    # 立即设置到当前会话
    export MR_AUTHOR_WHITELIST="$whitelist_value"

    if [[ -n "$whitelist_value" ]]; then
        echo -e "${CYAN}${SPARKLES} 白名单已更新到文件: $config_file${NC}"
    else
        echo -e "${CYAN}${SPARKLES} 白名单已从文件中移除: $config_file${NC}"
    fi
}

# 计算时间差的函数
calculate_time_diff() {
    local created_at="$1"
    local current_time=$(date +%s)

    # 将GitLab时间转换为时间戳
    if command -v date &> /dev/null; then
        # 提取日期部分，去掉时区信息
        local date_part=$(echo "$created_at" | sed 's/\.[0-9]*+.*$//' | sed 's/T/ /')
        local created_timestamp

        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            created_timestamp=$(date -j -f '%Y-%m-%d %H:%M:%S' "$date_part" +%s 2>/dev/null || echo "$current_time")
        else
            # Linux
            created_timestamp=$(date -d "$date_part" +%s 2>/dev/null || echo "$current_time")
        fi

        local diff=$((current_time - created_timestamp))

        if [ $diff -lt 60 ]; then
            echo "${diff}秒前"
        elif [ $diff -lt 3600 ]; then
            echo "$((diff / 60))分钟前"
        elif [ $diff -lt 86400 ]; then
            echo "$((diff / 3600))小时前"
        else
            echo "$((diff / 86400))天前"
        fi
    else
        echo "未知"
    fi
}

# 格式化日期时间
format_datetime() {
    local created_at="$1"
    # 提取日期部分，去掉时区信息，格式化为易读格式
    echo "$created_at" | sed 's/\.[0-9]*+.*$//' | sed 's/T/ /'
}

# 获取MR列表的函数
list_merge_requests() {
    echo -e "${CYAN}${SEARCH} 正在获取您有权限审批的合并请求...${NC}" >&2

    debug_log "开始获取当前用户信息"
    # 获取当前用户信息
    local user_api_url="http://$GITLAB_HOST/api/v4/user"
    debug_log "用户API URL: $user_api_url"

    user_info=$(curl -s --request GET \
        --header "PRIVATE-TOKEN: $TOKEN" \
        "$user_api_url")

    debug_log "用户信息响应: $(echo "$user_info" | head -c 200)..."

    if command -v jq &> /dev/null; then
        current_user_id=$(echo "$user_info" | jq -r '.id')
        current_username=$(echo "$user_info" | jq -r '.username')
    else
        current_user_id=$(echo "$user_info" | grep -o '"id":[0-9]*' | cut -d':' -f2)
        current_username=$(echo "$user_info" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
    fi

    echo -e "${BLUE}${USER} 当前用户: ${YELLOW}$current_username${NC} ${GRAY}(ID: $current_user_id)${NC}" >&2
    debug_log "解析得到用户ID: $current_user_id, 用户名: $current_username"

    # 存储所有MR的临时文件
    local temp_mr_file="/tmp/ma_mrs_$$"
    > "$temp_mr_file"

    # 构建白名单用户ID列表（如果设置了白名单）
    local author_ids=""
    local updated_whitelist=""
    local whitelist_changed=false

    if [[ -n "$AUTHOR_WHITELIST" ]]; then
        echo -e "${CYAN}${GEAR} 正在解析白名单用户...${NC}" >&2
        debug_log "白名单设置: $AUTHOR_WHITELIST"

        # 解析白名单，支持用户名和用户ID混合
        IFS=',' read -ra WHITELIST_ENTRIES <<< "$AUTHOR_WHITELIST"
        for entry in "${WHITELIST_ENTRIES[@]}"; do
            entry=$(echo "$entry" | tr -d ' ')  # 去除空格
            debug_log "处理白名单条目: $entry"

            # 检查是否为纯数字（用户ID）
            if [[ "$entry" =~ ^[0-9]+$ ]]; then
                debug_log "识别为用户ID: $entry"
                # 直接使用用户ID
                if [[ -n "$author_ids" ]]; then
                    author_ids="$author_ids,$entry"
                    updated_whitelist="$updated_whitelist,$entry"
                else
                    author_ids="$entry"
                    updated_whitelist="$entry"
                fi
            else
                debug_log "识别为用户名，需要搜索: $entry"
                # 搜索用户名获取用户ID
                local user_search_url="http://$GITLAB_HOST/api/v4/users?search=$entry&per_page=10"
                debug_log "用户搜索API URL: $user_search_url"

                user_search=$(curl -s --request GET \
                    --header "PRIVATE-TOKEN: $TOKEN" \
                    "$user_search_url")

                debug_log "用户搜索响应: $(echo "$user_search" | head -c 200)..."

                if command -v jq &> /dev/null; then
                    # 查找精确匹配的用户
                    user_id=$(echo "$user_search" | jq -r ".[] | select(.name == \"$entry\" or .username == \"$entry\") | .id" | head -1)
                    user_name=$(echo "$user_search" | jq -r ".[] | select(.name == \"$entry\" or .username == \"$entry\") | .name" | head -1)
                    debug_log "找到用户ID: $user_id, 用户名: $user_name (for $entry)"

                    if [[ -n "$user_id" && "$user_id" != "null" ]]; then
                        if [[ -n "$author_ids" ]]; then
                            author_ids="$author_ids,$user_id"
                            updated_whitelist="$updated_whitelist,$user_id"
                        else
                            author_ids="$user_id"
                            updated_whitelist="$user_id"
                        fi

                        # 标记白名单已更改（用户名被替换为用户ID）
                        whitelist_changed=true
                        echo -e "${CYAN}${SPARKLES} 已将用户名 '$entry' 替换为用户ID '$user_id' ($user_name)${NC}" >&2
                    else
                        echo -e "${YELLOW}${WARNING} 未找到用户: $entry${NC}" >&2
                        # 保留原始条目
                        if [[ -n "$updated_whitelist" ]]; then
                            updated_whitelist="$updated_whitelist,$entry"
                        else
                            updated_whitelist="$entry"
                        fi
                    fi
                else
                    echo -e "${YELLOW}${WARNING} 需要jq工具来解析用户名: $entry${NC}" >&2
                    # 保留原始条目
                    if [[ -n "$updated_whitelist" ]]; then
                        updated_whitelist="$updated_whitelist,$entry"
                    else
                        updated_whitelist="$entry"
                    fi
                fi
            fi
        done

        # 如果白名单有变化，自动更新环境变量
        if [[ "$whitelist_changed" == true && "$updated_whitelist" != "$AUTHOR_WHITELIST" ]]; then
            echo -e "${CYAN}正在自动更新白名单配置...${NC}" >&2
            update_whitelist_env "$updated_whitelist"
            AUTHOR_WHITELIST="$updated_whitelist"
        fi

        echo -e "${BLUE}${LIST} 白名单用户ID: ${YELLOW}$author_ids${NC}" >&2
        debug_log "最终白名单用户ID列表: $author_ids"
    fi

    # 获取用户有权限的项目，然后查询这些项目的开放MR
    echo -e "${CYAN}${ROCKET} 正在获取待审批的合并请求...${NC}" >&2

    # 获取用户有权限的项目列表
    debug_log "获取用户有权限的项目列表"
    local projects_api_url="http://$GITLAB_HOST/api/v4/projects?membership=true&per_page=100"
    debug_log "项目列表API URL: $projects_api_url"

    projects=$(curl -s --request GET \
        --header "PRIVATE-TOKEN: $TOKEN" \
        "$projects_api_url")

    debug_log "项目列表响应: $(echo "$projects" | head -c 200)..."

    # 如果有白名单，添加author_id过滤
    if [[ -n "$author_ids" ]]; then
        debug_log "使用白名单过滤，将分别查询每个作者ID"
        # 对于多个author_id，需要分别查询然后合并结果
        IFS=',' read -ra AUTHOR_ID_ARRAY <<< "$author_ids"
        for author_id in "${AUTHOR_ID_ARRAY[@]}"; do
            debug_log "查询作者ID: $author_id 的MR"

            # 构建API查询参数
            local api_params="state=opened&scope=all&author_id=${author_id}&per_page=100"
            local mr_api_url="http://$GITLAB_HOST/api/v4/merge_requests?${api_params}"
            debug_log "MR API URL (author_id=$author_id): $mr_api_url"

            mrs=$(curl -s --request GET \
                --header "PRIVATE-TOKEN: $TOKEN" \
                "$mr_api_url")

            debug_log "MR响应 (author_id=$author_id): $(echo "$mrs" | head -c 200)..."

            # 处理MR数据，使用项目权限过滤
            process_mr_data_with_project_filter "$mrs" "$temp_mr_file" "$projects" >/dev/null
        done
    else
        debug_log "未设置白名单，不执行MR检索"
        echo -e "${YELLOW}${WARNING} 未设置创建人白名单，为了安全考虑，不会显示所有MR${NC}" >&2
        echo -e "${CYAN}请设置 MR_AUTHOR_WHITELIST 环境变量来指定要关注的创建人${NC}" >&2
        echo -e "${CYAN}示例: export MR_AUTHOR_WHITELIST=\"用户A,用户B,123,456\"${NC}" >&2
        echo -e "${CYAN}或使用白名单管理命令: $0 -w add 用户A${NC}" >&2

        if command -v jq &> /dev/null; then
            # 统计项目权限信息
            local total_projects=$(echo "$projects" | jq '. | length')
            local maintainer_projects=$(echo "$projects" | jq '[.[] | select(.permissions.project_access.access_level >= 40)] | length')
            debug_log "项目权限统计: 总项目数=$total_projects, Maintainer权限项目数=$maintainer_projects"

            # 过滤出有Maintainer权限(access_level >= 40)的项目
            echo "$projects" | jq -r '.[] | select(.permissions.project_access.access_level >= 40) | "\(.id)|\(.name)|\(.permissions.project_access.access_level)"' | while IFS='|' read -r project_id project_name access_level; do
                debug_log "查询项目: $project_name (ID: $project_id, 权限级别: $access_level) 的开放MR"

                # 构建API查询参数（项目级API不需要scope=all）
                local api_params="state=opened&per_page=50"
                local mr_api_url="http://$GITLAB_HOST/api/v4/projects/$project_id/merge_requests?${api_params}"
                debug_log "项目MR API URL: $mr_api_url"

                mrs=$(curl -s --request GET \
                    --header "PRIVATE-TOKEN: $TOKEN" \
                    "$mr_api_url")

                debug_log "项目MR响应 (project_id=$project_id): $(echo "$mrs" | head -c 200)..."

                # 处理MR数据
                process_mr_data "$mrs" "$temp_mr_file" "$project_name" >/dev/null
            done
        else
            debug_log "备用方案：使用全局MR API（无jq工具，无法进行项目权限过滤）"
            echo -e "${YELLOW}${WARNING} 建议安装jq工具以启用项目权限过滤功能${NC}" >&2

            # 备用方案：获取所有开放的MR
            local api_params="state=opened&scope=all&per_page=100"
            local mr_api_url="http://$GITLAB_HOST/api/v4/merge_requests?${api_params}"
            debug_log "全局MR API URL: $mr_api_url"

            mrs=$(curl -s --request GET \
                --header "PRIVATE-TOKEN: $TOKEN" \
                "$mr_api_url")

            debug_log "全局MR响应: $(echo "$mrs" | head -c 200)..."

            # 处理MR数据
            process_mr_data "$mrs" "$temp_mr_file" >/dev/null
        fi
    fi

    echo "$temp_mr_file"
}

# 获取MR的实际作者（处理机器人情况）
get_actual_author() {
    local project_id="$1"
    local mr_id="$2"
    local author_id="$3"
    local author_name="$4"

    # 如果是机器人用户，从最新commit获取实际作者
    if [[ "$author_id" == "$BOT_USER_ID" ]]; then
        debug_log "检测到机器人用户 (ID: $BOT_USER_ID)，获取最新commit作者"

        # 获取MR的commits
        local commits_response=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$GITLAB_HOST/api/v4/projects/$project_id/merge_requests/$mr_id/commits")

        if command -v jq &> /dev/null && [[ "$commits_response" != "[]" ]]; then
            # 获取最新commit的作者
            local latest_commit_author=$(echo "$commits_response" | jq -r '.[0].author_name // empty')
            if [[ -n "$latest_commit_author" && "$latest_commit_author" != "null" ]]; then
                debug_log "从最新commit获取到实际作者: $latest_commit_author"
                echo "$latest_commit_author"
                return 0
            fi
        fi

        debug_log "无法获取实际作者，使用机器人名称"
        echo "$author_name (机器人)"
    else
        echo "$author_name"
    fi
}

# 检查是否需要使用领导Token
should_use_leader_token() {
    local mr_author="$1"
    local current_username="$2"

    # 如果MR作者是当前用户，且有领导Token，则使用领导Token
    if [[ "$mr_author" == "$current_username" && -n "$LEADER_TOKEN" ]]; then
        debug_log "检测到自己的MR，将使用领导Token进行审批"
        return 0
    fi
    return 1
}

# 使用项目权限过滤的MR数据处理函数
process_mr_data_with_project_filter() {
    local mrs="$1"
    local temp_mr_file="$2"
    local projects="$3"

    debug_log "开始处理MR数据（使用项目权限过滤）"

    if command -v jq &> /dev/null; then
        local mr_count=$(echo "$mrs" | jq '. | length')
        debug_log "找到 $mr_count 个MR"

        echo "$mrs" | jq -c '.[]' | while read -r mr; do
            mr_id=$(echo "$mr" | jq -r '.iid')
            project_id=$(echo "$mr" | jq -r '.project_id')
            author_id=$(echo "$mr" | jq -r '.author.id')
            author_name=$(echo "$mr" | jq -r '.author.name')
            author_username=$(echo "$mr" | jq -r '.author.username')
            title=$(echo "$mr" | jq -r '.title')
            created_at=$(echo "$mr" | jq -r '.created_at')
            source_branch=$(echo "$mr" | jq -r '.source_branch')
            target_branch=$(echo "$mr" | jq -r '.target_branch')
            has_conflicts=$(echo "$mr" | jq -r '.has_conflicts')
            web_url=$(echo "$mr" | jq -r '.web_url')

            debug_log "处理MR: $mr_id (项目ID: $project_id, 作者: $author_name, 作者ID: $author_id)"

            # 获取实际作者（处理机器人情况）
            actual_author=$(get_actual_author "$project_id" "$mr_id" "$author_id" "$author_name")

            # 检查项目权限级别
            local project_access_level=$(echo "$projects" | jq -r ".[] | select(.id == $project_id) | .permissions.project_access.access_level // 0")
            debug_log "项目权限级别: $project_access_level"

            if [[ "$project_access_level" -ge 40 ]]; then
                debug_log "项目权限足够 (>= 40)，显示此MR"

                # 获取项目名称
                project_name=$(echo "$projects" | jq -r ".[] | select(.id == $project_id) | .name")
                debug_log "项目名称: $project_name"

                # 获取MR详细信息
                mr_details=$(curl -s --request GET \
                    --header "PRIVATE-TOKEN: $TOKEN" \
                    "http://$GITLAB_HOST/api/v4/projects/$project_id/merge_requests/$mr_id")

                # 获取提交数
                commits_info=$(curl -s --request GET \
                    --header "PRIVATE-TOKEN: $TOKEN" \
                    "http://$GITLAB_HOST/api/v4/projects/$project_id/merge_requests/$mr_id/commits")

                commit_count=$(echo "$commits_info" | jq '. | length')
                changes_count=$(echo "$mr_details" | jq -r '.changes_count // "未知"')

                debug_log "统计信息: commits=$commit_count, changes=$changes_count"

                # 冲突状态
                conflict_status="无"
                if [[ "$has_conflicts" == "true" ]]; then
                    conflict_status="有冲突"
                fi

                debug_log "保存MR信息到文件: $project_name|$actual_author|..."

                # 保存MR信息到临时文件（包含实际作者和原始作者信息）
                echo "$project_name|$actual_author|$created_at|$commit_count|$changes_count|0|$conflict_status|$web_url|$title|$source_branch|$target_branch|$author_username" >> "$temp_mr_file"
            else
                debug_log "项目权限不足 (< 40)，跳过此MR"
            fi
        done
    else
        debug_log "无jq工具，使用备用处理方式"
        # 备用方案，功能有限
        echo "$mrs" | grep -o '"iid":[0-9]*' | cut -d':' -f2 | while read -r mr_id; do
            project_id=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"project_id":[0-9]*' | head -1 | cut -d':' -f2)
            author_name=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
            title=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
            web_url=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"web_url":"[^"]*"' | head -1 | cut -d'"' -f4)

            # 简化的项目信息获取
            project_info=$(curl -s --request GET \
                --header "PRIVATE-TOKEN: $TOKEN" \
                "http://$GITLAB_HOST/api/v4/projects/$project_id")
            project_name=$(echo "$project_info" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)

            echo "$project_name|$author_name|未知|未知|未知|0|未知|$web_url|$title|未知|未知" >> "$temp_mr_file"
        done
    fi
}

# 处理MR数据的辅助函数
process_mr_data() {
    local mrs="$1"
    local temp_mr_file="$2"
    local project_name_override="$3"  # 可选参数，用于已知项目名称的情况

    debug_log "开始处理MR数据"

    if command -v jq &> /dev/null; then
        local mr_count=$(echo "$mrs" | jq '. | length')
        debug_log "找到 $mr_count 个MR"

        echo "$mrs" | jq -c '.[]' | while read -r mr; do
            mr_id=$(echo "$mr" | jq -r '.iid')
            project_id=$(echo "$mr" | jq -r '.project_id')
            author_id=$(echo "$mr" | jq -r '.author.id')
            author_name=$(echo "$mr" | jq -r '.author.name')
            author_username=$(echo "$mr" | jq -r '.author.username')
            title=$(echo "$mr" | jq -r '.title')
            created_at=$(echo "$mr" | jq -r '.created_at')
            source_branch=$(echo "$mr" | jq -r '.source_branch')
            target_branch=$(echo "$mr" | jq -r '.target_branch')
            has_conflicts=$(echo "$mr" | jq -r '.has_conflicts')
            web_url=$(echo "$mr" | jq -r '.web_url')

            debug_log "处理MR: $mr_id (项目ID: $project_id, 作者: $author_name, 作者ID: $author_id)"

            # 获取实际作者（处理机器人情况）
            actual_author=$(get_actual_author "$project_id" "$mr_id" "$author_id" "$author_name")

            # 获取项目名称（如果没有提供的话）
            if [[ -n "$project_name_override" ]]; then
                project_name="$project_name_override"
                debug_log "使用提供的项目名称: $project_name"
            else
                local project_api_url="http://$GITLAB_HOST/api/v4/projects/$project_id"
                debug_log "项目API URL: $project_api_url"

                project_info=$(curl -s --request GET \
                    --header "PRIVATE-TOKEN: $TOKEN" \
                    "$project_api_url")
                project_name=$(echo "$project_info" | jq -r '.name')
                debug_log "项目名称: $project_name"
            fi

            # 检查用户是否有权限审批此MR且未审批
            local approvals_api_url="http://$GITLAB_HOST/api/v4/projects/$project_id/merge_requests/$mr_id/approvals"
            debug_log "审批API URL: $approvals_api_url"

            approvals_info=$(curl -s --request GET \
                --header "PRIVATE-TOKEN: $TOKEN" \
                "$approvals_api_url")

            debug_log "审批信息响应: $(echo "$approvals_info" | head -c 200)..."

            user_can_approve=$(echo "$approvals_info" | jq -r '.user_can_approve')
            user_has_approved=$(echo "$approvals_info" | jq -r '.user_has_approved')

            debug_log "审批权限: can_approve=$user_can_approve, has_approved=$user_has_approved"

            # 检查权限条件并提供详细日志
            debug_log "权限检查详情:"
            debug_log "  user_can_approve: '$user_can_approve' (类型: $(echo "$user_can_approve" | wc -c) 字符)"
            debug_log "  user_has_approved: '$user_has_approved' (类型: $(echo "$user_has_approved" | wc -c) 字符)"

            # 更宽松的权限检查逻辑
            local can_approve=false
            local has_approved=false

            # 检查是否可以审批
            if [[ "$user_can_approve" == "true" ]] || [[ "$user_can_approve" == true ]]; then
                can_approve=true
            fi

            # 检查是否已经审批
            if [[ "$user_has_approved" == "true" ]] || [[ "$user_has_approved" == true ]]; then
                has_approved=true
            fi

            debug_log "  解析结果: can_approve=$can_approve, has_approved=$has_approved"

            # 权限检查：可以审批且未审批，或者跳过权限检查模式
            if [[ "$SKIP_APPROVAL_CHECK" == "true" ]] || [[ "$can_approve" == true && "$has_approved" == false ]]; then
                if [[ "$SKIP_APPROVAL_CHECK" == "true" ]]; then
                    debug_log "跳过权限检查模式，直接显示MR"
                else
                    debug_log "MR符合条件，获取详细信息"
                fi

                # 获取MR详细信息（包含changes_count）
                local mr_details_api_url="http://$GITLAB_HOST/api/v4/projects/$project_id/merge_requests/$mr_id"
                debug_log "MR详情API URL: $mr_details_api_url"

                mr_details=$(curl -s --request GET \
                    --header "PRIVATE-TOKEN: $TOKEN" \
                    "$mr_details_api_url")

                # 获取提交数
                local commits_api_url="http://$GITLAB_HOST/api/v4/projects/$project_id/merge_requests/$mr_id/commits"
                debug_log "提交API URL: $commits_api_url"

                commits_info=$(curl -s --request GET \
                    --header "PRIVATE-TOKEN: $TOKEN" \
                    "$commits_api_url")

                commit_count=$(echo "$commits_info" | jq '. | length')
                changes_count=$(echo "$mr_details" | jq -r '.changes_count // "未知"')

                debug_log "统计信息: commits=$commit_count, changes=$changes_count"

                # 冲突状态
                conflict_status="无"
                if [[ "$has_conflicts" == "true" ]]; then
                    conflict_status="有冲突"
                fi

                debug_log "保存MR信息到文件: $project_name|$actual_author|..."

                # 保存MR信息到临时文件（包含实际作者和原始作者信息）
                echo "$project_name|$actual_author|$created_at|$commit_count|$changes_count|0|$conflict_status|$web_url|$title|$source_branch|$target_branch|$author_username" >> "$temp_mr_file"
            else
                debug_log "MR不符合条件，跳过 (MR: $mr_id, 项目: $project_name, 作者: $author_name)"

                # 在调试模式下，即使不符合条件也显示基本信息
                if [[ "$DEBUG_MODE" == "true" ]]; then
                    echo "DEBUG_SKIP|$project_name|$author_name|$created_at|未知|未知|0|权限不足|$web_url|$title|$source_branch|$target_branch" >> "$temp_mr_file"
                fi
            fi
        done
    else
        echo -e "${YELLOW}${WARNING} 建议安装 jq 工具以获得更好的体验${NC}"
        # 备用方案：使用简化的API调用
        mrs=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$GITLAB_HOST/api/v4/merge_requests?state=opened&scope=assigned_to_me&per_page=100")

        # 简化处理，只获取基本信息
        echo "$mrs" | grep -o '"iid":[0-9]*' | cut -d':' -f2 | while read -r mr_id; do
            project_id=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"project_id":[0-9]*' | head -1 | cut -d':' -f2)
            author_name=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
            title=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
            web_url=$(echo "$mrs" | grep -A10 -B10 "\"iid\":$mr_id" | grep -o '"web_url":"[^"]*"' | head -1 | cut -d'"' -f4)

            # 获取项目名称
            project_info=$(curl -s --request GET \
                --header "PRIVATE-TOKEN: $TOKEN" \
                "http://$GITLAB_HOST/api/v4/projects/$project_id")
            project_name=$(echo "$project_info" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)

            # 检查白名单
            if [[ -n "$AUTHOR_WHITELIST" && ",$AUTHOR_WHITELIST," != *",$author_name,"* ]]; then
                continue
            fi

            echo "$project_name|$author_name|未知|未知|未知|0|未知|$web_url|$title|未知|未知" >> "$temp_mr_file"
        done
    fi

    echo "$temp_mr_file"
}

# 显示MR的commits信息
show_mr_commits() {
    local web_url="$1"

    # 从URL中提取项目路径和合并请求ID
    if [[ $web_url =~ https?://([^/]+)/([^/]+/[^/]+)/merge_requests/([0-9]+) ]]; then
        local host=${BASH_REMATCH[1]}
        local project_path=${BASH_REMATCH[2]}
        local mr_id=${BASH_REMATCH[3]}

        # 对项目路径进行URL编码用于API调用
        local encoded_project_path=$(echo "$project_path" | sed 's|/|%2F|g')

        # 获取commits信息
        local commits_api_url="http://$host/api/v4/projects/$encoded_project_path/merge_requests/$mr_id/commits"
        debug_log "获取commits API URL: $commits_api_url"

        commits_info=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "$commits_api_url")

        debug_log "Commits响应: $(echo "$commits_info" | head -c 200)..."

        if command -v jq &> /dev/null; then
            local commit_count=$(echo "$commits_info" | jq '. | length')
            # 第五行：提交列表
            if [[ $commit_count -gt 0 ]]; then
                echo -e "    ${COMMIT} ${BOLD}最近提交:${NC}"

                # 显示最多10个commits，按时间倒序，每个commit一行
                echo "$commits_info" | jq -r '.[] | "\(.id)|\(.author_name)|\(.title)|\(.created_at)"' | head -10 | while IFS='|' read -r commit_hash author_name commit_title commit_time; do
                    # 格式化时间
                    local commit_time_diff=$(calculate_time_diff "$commit_time")

                    # 截取hash前8位
                    local short_hash=$(echo "$commit_hash" | cut -c1-8)

                    # 截取commit标题（最多40字符）
                    local short_title="$commit_title"
                    if [[ ${#short_title} -gt 40 ]]; then
                        short_title="${short_title:0:37}..."
                    fi

                    # 一行显示：hash + 作者 + 标题 + 时间
                    echo -e "      ${GRAY}$short_hash${NC} ${YELLOW}$author_name${NC} ${CYAN}$short_title${NC} ${GRAY}($commit_time_diff)${NC}"
                done
            fi
        else
            # 备用方案，简化显示
            local commit_lines=$(echo "$commits_info" | grep -o '"id":"[^"]*"' | wc -l)
            if [[ $commit_lines -gt 0 ]]; then
                echo -e "    ${BOLD}提交数:${NC} $commit_lines ${GRAY}(需要jq工具显示详细信息)${NC}"
            fi
        fi
    fi
}

# 显示MR列表并提供选择
display_and_select_mrs() {
    local temp_mr_file="$1"

    debug_log "检查临时文件: $temp_mr_file"
    debug_log "文件是否存在: $(test -f "$temp_mr_file" && echo "是" || echo "否")"
    debug_log "文件是否非空: $(test -s "$temp_mr_file" && echo "是" || echo "否")"
    debug_log "文件大小: $(wc -c < "$temp_mr_file" 2>/dev/null || echo "0") 字节"
    debug_log "文件行数: $(wc -l < "$temp_mr_file" 2>/dev/null || echo "0") 行"

    if [[ ! -f "$temp_mr_file" ]] || [[ ! -s "$temp_mr_file" ]]; then
        echo -e "${YELLOW}${WARNING} 没有找到需要审批的合并请求${NC}"
        if [[ -n "$AUTHOR_WHITELIST" ]]; then
            echo -e "${CYAN}当前白名单: ${YELLOW}$AUTHOR_WHITELIST${NC}"
            echo -e "${CYAN}提示: 可以通过设置 MR_AUTHOR_WHITELIST 环境变量来调整白名单${NC}"
        fi
        rm -f "$temp_mr_file"
        return 1
    fi

    echo ""
    echo -e "${BOLD}${GREEN}${LIST} 待审批的合并请求列表${NC}"
    echo -e "${BOLD}${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local index=1
    declare -a mr_urls=()

    while IFS='|' read -r project_name author_name created_at commit_count additions deletions conflict_status web_url title source_branch target_branch author_username; do
        # 检查是否为调试跳过的条目
        if [[ "$project_name" == "DEBUG_SKIP" ]]; then
            if [[ "$DEBUG_MODE" == "true" ]]; then
                # 显示被跳过的MR（调试用）
                echo -e "${BOLD}${RED}[SKIP]${NC} ${BOLD}项目:${NC} ${GREEN}$author_name${NC} | ${BOLD}作者:${NC} ${YELLOW}$created_at${NC}"
                echo -e "    ${BOLD}原因:${NC} ${RED}$conflict_status${NC}"
                echo -e "    ${BOLD}标题:${NC} $title"
                echo -e "    ${BOLD}URL:${NC} ${BLUE}$web_url${NC}"
                echo -e "${GRAY}----------------------------------------${NC}"
            fi
            # 跳过调试条目，不增加索引
            continue
        fi

        # 格式化时间
        local formatted_time=$(format_datetime "$created_at")
        local time_diff=$(calculate_time_diff "$created_at")

        # 第一行：序号 + 项目(红色) + 作者(绿色) + 分支(蓝色)
        echo -e "${BOLD}${CYAN}[$index]${NC} ${RED}$project_name${NC} | ${GREEN}$author_name${NC} | ${BLUE}$source_branch${NC} ${BOLD}→${NC} ${BLUE}$target_branch${NC}"

        # 第二行：时间(黄色) + 标题(灰色)
        echo -e "    ${YELLOW}$formatted_time ($time_diff)${NC} | ${GRAY}$title${NC}"

        # 第三行：提交数 + 变更数 + 冲突状态
        local conflict_color="${GREEN}"
        if [[ "$conflict_status" != "无" ]]; then
            conflict_color="${RED}"
        fi
        echo -e "    ${COMMIT} ${commit_count}个提交 | ${BOLD}变更:${NC} ${GREEN}+$additions${NC}/${RED}-$deletions${NC} | ${BOLD}冲突:${NC} ${conflict_color}$conflict_status${NC}"

        # 第四行：URL
        echo -e "    ${LINK} ${BOLD}URL:${NC} ${BLUE}$web_url${NC}"

        # 显示最近的commits（最多10个）
        show_mr_commits "$web_url"

        echo -e "${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        mr_urls[$index]="$web_url"
        ((index++))
    done < "$temp_mr_file"

    rm -f "$temp_mr_file"

    if [[ ${#mr_urls[@]} -eq 0 ]]; then
        echo -e "${YELLOW}${WARNING} 没有找到需要审批的合并请求${NC}"
        return 1
    fi

    echo ""
    echo -e "${CYAN}${GEAR} 请选择要处理的合并请求:${NC}"
    echo -e "${GRAY}📝 输入选项:${NC}"
    echo -e "  ${YELLOW}数字${NC} - 处理单个MR ${GRAY}(如: 1)${NC}"
    echo -e "  ${YELLOW}范围${NC} - 处理多个MR ${GRAY}(如: 1-3 或 1,3,5)${NC}"
    echo -e "  ${YELLOW}all${NC}  - 处理所有MR"
    echo -e "  ${YELLOW}q${NC}    - 退出"
    echo ""

    while true; do
        read -p "请输入选择: " selection

        case "$selection" in
            q|Q|quit|exit)
                echo -e "${CYAN}👋 已退出${NC}"
                return 0
                ;;
            all|ALL)
                echo -e "${CYAN}${ROCKET} 将处理所有 ${#mr_urls[@]} 个合并请求${NC}"
                for i in $(seq 1 ${#mr_urls[@]}); do
                    if [[ -n "${mr_urls[$i]}" ]]; then
                        echo -e "${BOLD}${BLUE}处理第 $i 个合并请求...${NC}"
                        process_merge_request "${mr_urls[$i]}"
                    fi
                done
                return 0
                ;;
            *-*)
                # 处理范围选择 (如 1-3)
                local start_num=$(echo "$selection" | cut -d'-' -f1)
                local end_num=$(echo "$selection" | cut -d'-' -f2)

                if [[ "$start_num" =~ ^[0-9]+$ ]] && [[ "$end_num" =~ ^[0-9]+$ ]] &&
                   [[ $start_num -ge 1 ]] && [[ $end_num -le ${#mr_urls[@]} ]] && [[ $start_num -le $end_num ]]; then
                    echo -e "${CYAN}将处理第 $start_num 到第 $end_num 个合并请求${NC}"
                    for i in $(seq $start_num $end_num); do
                        if [[ -n "${mr_urls[$i]}" ]]; then
                            echo -e "${BOLD}${BLUE}处理第 $i 个合并请求...${NC}"
                            process_merge_request "${mr_urls[$i]}"
                        fi
                    done
                    return 0
                else
                    echo -e "${RED}无效的范围选择，请重新输入${NC}"
                fi
                ;;
            *,*)
                # 处理逗号分隔的选择 (如 1,3,5)
                local valid=true
                local selected_nums=()

                IFS=',' read -ra NUMS <<< "$selection"
                for num in "${NUMS[@]}"; do
                    num=$(echo "$num" | tr -d ' ')  # 去除空格
                    if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#mr_urls[@]} ]]; then
                        selected_nums+=("$num")
                    else
                        echo -e "${RED}无效的选择: $num${NC}"
                        valid=false
                        break
                    fi
                done

                if [[ "$valid" == true ]]; then
                    echo -e "${CYAN}将处理选中的 ${#selected_nums[@]} 个合并请求${NC}"
                    for num in "${selected_nums[@]}"; do
                        if [[ -n "${mr_urls[$num]}" ]]; then
                            echo -e "${BOLD}${BLUE}处理第 $num 个合并请求...${NC}"
                            process_merge_request "${mr_urls[$num]}"
                        fi
                    done
                    return 0
                fi
                ;;
            *)
                # 处理单个数字选择
                if [[ "$selection" =~ ^[0-9]+$ ]] && [[ $selection -ge 1 ]] && [[ $selection -le ${#mr_urls[@]} ]]; then
                    echo -e "${CYAN}将处理第 $selection 个合并请求${NC}"
                    process_merge_request "${mr_urls[$selection]}"
                    return 0
                else
                    echo -e "${RED}无效的选择，请输入 1-${#mr_urls[@]} 之间的数字、范围、逗号分隔的数字、'all' 或 'q'${NC}"
                fi
                ;;
        esac
    done
}

# 交互模式主函数
interactive_mode() {
    echo -e "${BOLD}${BLUE}${SPARKLES} 进入交互模式${NC}"

    if [[ -n "$AUTHOR_WHITELIST" ]]; then
        echo -e "${CYAN}${LIST} 当前创建人白名单: ${YELLOW}$AUTHOR_WHITELIST${NC}"
    else
        echo -e "${YELLOW}${WARNING} 未设置创建人白名单，为了安全考虑，不会显示所有MR${NC}"
        echo -e "${CYAN}💡 提示: 可以通过设置 MR_AUTHOR_WHITELIST 环境变量来过滤特定创建人的MR${NC}"
        echo -e "${CYAN}📝 示例: export MR_AUTHOR_WHITELIST=\"用户A,用户B,用户C\"${NC}"
    fi

    echo ""

    local temp_mr_file=$(list_merge_requests)
    display_and_select_mrs "$temp_mr_file"
}

# 处理单个合并请求的函数
process_merge_request() {
    local url=$1

    # 从URL中提取项目路径和合并请求ID
    if [[ $url =~ https?://([^/]+)/([^/]+/[^/]+)/merge_requests/([0-9]+) ]]; then
        local host=${BASH_REMATCH[1]}
        local project_path=${BASH_REMATCH[2]}
        local mr_id=${BASH_REMATCH[3]}

        # 对项目路径进行URL编码用于API调用
        local encoded_project_path=$(echo "$project_path" | sed 's|/|%2F|g')

        # 首先，获取合并请求详情以检查当前状态
        mr_details=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$host/api/v4/projects/$encoded_project_path/merge_requests/$mr_id")

        # 从响应中提取相关信息 - 使用更可靠的jq工具（如果可用）
        if command -v jq &> /dev/null; then
            # 使用jq解析JSON（推荐方式）
            merge_status=$(echo "$mr_details" | jq -r '.state')
            can_be_merged=$(echo "$mr_details" | jq -r '.merge_status')

            # 获取额外信息
            title=$(echo "$mr_details" | jq -r '.title')
            source_branch=$(echo "$mr_details" | jq -r '.source_branch')
            target_branch=$(echo "$mr_details" | jq -r '.target_branch')
            author=$(echo "$mr_details" | jq -r '.author.name')
            merged_by=$(echo "$mr_details" | jq -r '.merged_by.name // "未知"')
        else
            # 备用方案：使用grep提取信息
            merge_status=$(echo "$mr_details" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
            can_be_merged=$(echo "$mr_details" | grep -o '"merge_status":"[^"]*"' | head -1 | cut -d'"' -f4)

            # 获取额外信息
            title=$(echo "$mr_details" | grep -o '"title":"[^"]*"' | head -1 | cut -d'"' -f4)
            source_branch=$(echo "$mr_details" | grep -o '"source_branch":"[^"]*"' | head -1 | cut -d'"' -f4)
            target_branch=$(echo "$mr_details" | grep -o '"target_branch":"[^"]*"' | head -1 | cut -d'"' -f4)
            author=$(echo "$mr_details" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
            merged_by=$(echo "$mr_details" | grep -o '"merged_by":{[^}]*"name":"[^"]*"' | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
            [ -z "$merged_by" ] && merged_by="未知"
        fi

        # 获取当前用户信息
        current_user_info=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "http://$host/api/v4/user")

        if command -v jq &> /dev/null; then
            current_username=$(echo "$current_user_info" | jq -r '.username')
            mr_author_username=$(echo "$mr_details" | jq -r '.author.username')
        else
            current_username=$(echo "$current_user_info" | grep -o '"username":"[^"]*"' | cut -d'"' -f4)
            mr_author_username=$(echo "$mr_details" | grep -o '"username":"[^"]*"' | head -1 | cut -d'"' -f4)
        fi

        # 检查是否是自己的MR，决定使用哪个Token
        local use_token="$TOKEN"
        local is_own_mr=false
        if [[ "$mr_author_username" == "$current_username" ]]; then
            is_own_mr=true
            if [[ -n "$LEADER_TOKEN" ]]; then
                use_token="$LEADER_TOKEN"
                echo -e "${YELLOW}${WARNING} 检测到这是您自己的MR，将使用领导Token进行审批${NC}"
            else
                echo -e "${RED}${FAILED} 这是您自己的MR，但未设置领导Token (GITLAB_LEADER_TOKEN)，无法审批和合并${NC}"
                return 1
            fi
        fi

        # 获取批准者信息
        approvals_info=$(curl -s --request GET \
            --header "PRIVATE-TOKEN: $use_token" \
            "http://$host/api/v4/projects/$encoded_project_path/merge_requests/$mr_id/approvals")

        # 解析批准信息
        if command -v jq &> /dev/null; then
            user_has_approved=$(echo "$approvals_info" | jq -r '.user_has_approved')
            user_can_approve=$(echo "$approvals_info" | jq -r '.user_can_approve')
            approvals_required=$(echo "$approvals_info" | jq -r '.approvals_required')
            approvals_left=$(echo "$approvals_info" | jq -r '.approvals_left')

            # 获取最后一个批准者（如果有批准者）
            approver_count=$(echo "$approvals_info" | jq -r '.approved_by | length')
            if [ "$approver_count" -gt 0 ]; then
                last_approver=$(echo "$approvals_info" | jq -r ".approved_by[$approver_count-1].user.name")
                has_been_approved=true
            else
                last_approver="未知"
                has_been_approved=false
            fi

            # 获取所有批准者
            all_approvers=$(echo "$approvals_info" | jq -r '.approved_by[].user.name' 2>/dev/null)
        else
            # 备用方案，使用grep提取（注意这不太可靠）
            user_has_approved=$(echo "$approvals_info" | grep -o '"user_has_approved":\(true\|false\)' | cut -d':' -f2)
            user_can_approve=$(echo "$approvals_info" | grep -o '"user_can_approve":\(true\|false\)' | cut -d':' -f2)
            approvals_required=$(echo "$approvals_info" | grep -o '"approvals_required":[0-9]*' | cut -d':' -f2)
            approvals_left=$(echo "$approvals_info" | grep -o '"approvals_left":[0-9]*' | cut -d':' -f2)

            # 尝试获取批准者名称
            approvers=$(echo "$approvals_info" | grep -o '"approved_by":\[[^]]*\]')
            if [[ "$approvers" == *"name"* ]]; then
                last_approver=$(echo "$approvers" | grep -o '"name":"[^"]*"' | tail -1 | cut -d'"' -f4)
                has_been_approved=true
                all_approvers=$(echo "$approvers" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
            else
                last_approver="未知"
                has_been_approved=false
                all_approvers=""
            fi
        fi

        # 显示详细信息
        echo -e "${BOLD}${PURPLE}----------------------------------------${NC}"
        echo -e "${BOLD}${BLUE}📌 标题:${NC} $title"
        echo -e "${BOLD}${YELLOW}👤 作者:${NC} $author"
        echo -e "${BOLD}${CYAN}🔀 源分支:${NC} ${GREEN}$source_branch${NC} ${BOLD}→${NC} ${GREEN}$target_branch${NC}"
        echo -e "${BOLD}${GRAY}🔄 当前状态:${NC} $merge_status, ${BOLD}可合并状态:${NC} $can_be_merged"

        # 显示批准和合并状态
        if [ "$has_been_approved" = true ]; then
            echo -e "${BOLD}${GREEN}👍 合并请求已被 [${YELLOW}$last_approver${GREEN}] 批准${NC}"
            # 显示所有批准者（如果有多个）
            if [ "$(echo "$all_approvers" | wc -l)" -gt 1 ]; then
                echo -e "${BOLD}${GREEN}   所有批准者:${NC}"
                echo "$all_approvers" | while read -r approver; do
                    echo -e "   ${YELLOW}→ $approver${NC}"
                done
            fi
        fi

        if [ "$merge_status" = "merged" ]; then
            echo -e "${BOLD}${GREEN}✅ 合并请求已被 [${YELLOW}$merged_by${GREEN}] 合并${NC}"

            # 检查提交是否已合并到main分支
            check_commits_in_main "$host" "$encoded_project_path" "$mr_id" "$project_path"

            echo -e "${BOLD}${PURPLE}----------------------------------------${NC}"
            return 0
        fi

        if [ "$merge_status" = "closed" ]; then
            echo -e "${BOLD}${RED}❌ 合并请求已关闭${NC}"
            echo -e "${BOLD}${PURPLE}----------------------------------------${NC}"
            return 0
        fi

        # 执行批准操作（如果用户可以批准且尚未批准）
        if [ "$user_can_approve" = "true" ] && [ "$user_has_approved" != "true" ]; then
            if [[ "$is_own_mr" == "true" ]]; then
                echo -e "${CYAN}正在使用领导Token批准合并请求...${NC}"
            else
                echo -e "${CYAN}正在批准合并请求...${NC}"
            fi
            approve_result=$(curl -s --request POST \
                --header "PRIVATE-TOKEN: $use_token" \
                "http://$host/api/v4/projects/$encoded_project_path/merge_requests/$mr_id/approve")

            if [[ "$approve_result" == *"approved"* ]] || [[ "$approve_result" == *"已批准"* ]] || [[ "$approve_result" == *"already approved"* ]]; then
                echo -e "${BOLD}${GREEN}✅ 批准成功${NC}"
            else
                echo -e "${BOLD}${YELLOW}⚠️ 批准状态:${NC} $approve_result"
            fi
        elif [ "$user_has_approved" = "true" ]; then
            echo -e "${BOLD}${GREEN}✅ 您已经批准过此合并请求${NC}"
        elif [ "$user_can_approve" != "true" ]; then
            echo -e "${BOLD}${YELLOW}⚠️ 您没有权限批准此合并请求${NC}"
        fi

        if [ "$TOKEN" == "-QY8_uzM2WwT5QyD_yZz" ]; then
            echo "可手动合并"
            return 0
        fi
        # 检查是否可以合并
        if [ "$can_be_merged" = "can_be_merged" ] || [ "$can_be_merged" = "checking" ]; then
            # 合并请求
            if [[ "$is_own_mr" == "true" ]]; then
                echo -e "${CYAN}正在使用领导Token合并请求...${NC}"
            else
                echo -e "${CYAN}正在合并请求...${NC}"
            fi
            merge_result=$(curl -s --request PUT \
                --header "PRIVATE-TOKEN: $use_token" \
                "http://$host/api/v4/projects/$encoded_project_path/merge_requests/$mr_id/merge")

            if [[ "$merge_result" == *"merge_commit_sha"* ]]; then
                echo -e "${BOLD}${GREEN}✅ 合并成功${NC}"

                # 提取合并提交的 SHA
                if command -v jq &> /dev/null; then
                    merge_commit_sha=$(echo "$merge_result" | jq -r '.merge_commit_sha')
                else
                    merge_commit_sha=$(echo "$merge_result" | grep -o '"merge_commit_sha":"[^"]*"' | cut -d'"' -f4)
                fi

                echo -e "${BOLD}${BLUE}🔗 合并提交:${NC} ${GRAY}$merge_commit_sha${NC}"

                # 检查提交是否已合并到main分支
                check_commits_in_main "$host" "$encoded_project_path" "$mr_id" "$project_path"
            else
                echo -e "${BOLD}${RED}❌ 合并失败:${NC} $merge_result"
            fi
        else
            echo -e "${BOLD}${RED}❌ 合并请求无法被合并，状态:${NC} $can_be_merged"
            # 根据不同状态添加更详细的错误处理
            if [[ "$mr_details" == *"\"has_conflicts\":true"* ]]; then
                echo -e "   ${YELLOW}原因:${NC} 存在冲突，需要手动解决"
            elif [[ "$mr_details" == *"\"work_in_progress\":true"* ]]; then
                echo -e "   ${YELLOW}原因:${NC} 这是一个进行中的工作，标记为WIP/Draft"
            elif [[ "$mr_details" == *"\"blocked_by_approval_rules\":true"* ]]; then
                echo -e "   ${YELLOW}原因:${NC} 被批准规则阻止"
            fi
        fi

        echo -e "${BOLD}${PURPLE}----------------------------------------${NC}"
    else
        echo -e "${BOLD}${RED}❌ 无效的合并请求 URL:${NC} $url"
        return 1
    fi
}

# 检查特殊参数
case "${1:-}" in
    -u|--update)
        # 手动触发脚本更新检查
        if [[ -n "${GITLAB_TOKEN:-}" ]]; then
            sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
            if [[ -f "$sv_script" ]]; then
                # 使用子shell避免变量冲突
                if (source "$sv_script" && check_script_update "ma.sh") 2>/dev/null; then
                    echo -e "${GREEN}${SUCCESS} 脚本更新检查完成${NC}"
                    exit 0
                else
                    echo -e "${RED}${FAILED} 脚本更新检查失败${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}${FAILED} 更新脚本不存在: $sv_script${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}${WARNING} 未设置 GITLAB_TOKEN 环境变量，无法检查更新${NC}"
            echo -e "${CYAN}请先使用 sv.sh -c 进行配置${NC}"
            exit 1
        fi
        ;;
    -w|--whitelist)
        # 白名单管理
        check_and_set_token
        if [[ $# -lt 2 ]]; then
            echo -e "${RED}${FAILED} 白名单操作需要指定动作${NC}"
            echo -e "${CYAN}使用方法: $0 -w <add|remove|list|clear> [用户名或ID]${NC}"
            exit 1
        fi

        action="$2"
        user_input="${3:-}"

        manage_whitelist "$action" "$user_input"
        exit 0
        ;;
esac

# 自动更新检查（如果有Token的话）
if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
    if [[ -f "$sv_script" ]]; then
        # 使用子shell避免变量冲突
        (source "$sv_script" && check_script_update "ma.sh") 2>/dev/null || true
    fi
fi

# 检查 Token
check_and_set_token

# 检查是否有参数
if [ $# -eq 0 ]; then
    # 没有参数，进入交互模式
    interactive_mode
else
    # 有参数，按原有方式处理指定的MR URL
    echo -e "${BOLD}${BLUE}👉 开始处理 $# 个合并请求${NC}"
    echo -e "${BOLD}${PURPLE}----------------------------------------${NC}"

    # 处理每个作为参数提供的URL
    for url in "$@"; do
        process_merge_request "$url"
    done

    echo -e "${BOLD}${GREEN}✨ 所有合并请求处理完成${NC}"
fi