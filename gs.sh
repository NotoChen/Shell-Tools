#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.3"

set -euo pipefail  # 启用严格模式

#######################################
# 常量定义
#######################################

# 颜色和样式定义 - 优化配色方案
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly LIGHT_BLUE='\033[1;36m'
readonly LIGHT_GREEN='\033[1;32m'
readonly LIGHT_YELLOW='\033[1;93m'
readonly LIGHT_PURPLE='\033[1;35m'
readonly LIGHT_GRAY='\033[0;37m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'  # 重置颜色

# Emoji定义 - 更丰富的图标
readonly EMOJI_SUCCESS="✨"
readonly EMOJI_ERROR="💥"
readonly EMOJI_WARNING="⚡"
readonly EMOJI_INFO="💡"
readonly EMOJI_ROCKET="🚀"
readonly EMOJI_BRANCH="🌿"
readonly EMOJI_COMMIT="📋"
readonly EMOJI_SEARCH="🔎"
readonly EMOJI_TIME="⏰"
readonly EMOJI_USER="👨‍💻"
readonly EMOJI_HASH="🔖"
readonly EMOJI_ENV="🌐"
readonly EMOJI_FILE="📄"
readonly EMOJI_LINE="📍"
readonly EMOJI_COUNT="🔢"
readonly EMOJI_FILTER="🔽"
readonly EMOJI_SYNC="🔄"

# 脚本配置
readonly SCRIPT_NAME="GS - Git Search (Git提交记录查询工具)"
readonly DEFAULT_COMMIT_COUNT=10

# 环境列表
readonly ENV_NAMES=("灰度1" "灰度2" "灰度3" "灰度4" "灰度5" "灰度6" "预发1" "预发2" "vip" "线上")

#######################################
# 全局变量
#######################################

declare target_env=""           # 目标环境
declare class_name=""           # 类名
declare line_range=""           # 行号范围
declare commit_count="$DEFAULT_COMMIT_COUNT"  # 提交记录数量
declare filter_merge=false      # 是否过滤merge提交
declare current_branch=""       # 当前分支

# 参数指定标记
declare env_specified=false     # 是否通过参数指定了环境
declare class_specified=false   # 是否通过参数指定了类名
declare line_specified=false    # 是否通过参数指定了行号
declare count_specified=false   # 是否通过参数指定了数量
declare merge_specified=false   # 是否通过参数指定了merge过滤

#######################################
# 工具函数
#######################################

# 计算相对时间
calculate_relative_time() {
    local commit_timestamp="$1"
    local current_timestamp
    current_timestamp=$(date +%s)

    local diff=$((current_timestamp - commit_timestamp))

    # 如果时间差为负数或0，返回"刚刚"
    if [[ $diff -le 0 ]]; then
        echo "刚刚"
        return
    fi

    local years=$((diff / 31536000))   # 365 * 24 * 60 * 60
    local months=$(((diff % 31536000) / 2592000))  # 30 * 24 * 60 * 60
    local days=$(((diff % 2592000) / 86400))       # 24 * 60 * 60
    local hours=$(((diff % 86400) / 3600))         # 60 * 60
    local minutes=$(((diff % 3600) / 60))
    local seconds=$((diff % 60))

    local result=""

    # 构建相对时间字符串
    if [[ $years -gt 0 ]]; then
        result="${result}${years}年"
    fi

    if [[ $months -gt 0 ]]; then
        result="${result}${months}个月"
    fi

    if [[ $days -gt 0 ]]; then
        result="${result}${days}天"
    fi

    if [[ $hours -gt 0 ]]; then
        result="${result}${hours}小时"
    fi

    if [[ $minutes -gt 0 ]]; then
        result="${result}${minutes}分钟"
    fi

    # 如果所有大单位都是0，显示秒数
    if [[ -z "$result" ]]; then
        if [[ $seconds -gt 0 ]]; then
            result="${seconds}秒"
        else
            result="刚刚"
        fi
    fi

    echo "${result}前"
}

# 打印错误信息并退出
print_error_and_exit() {
    local message="$1"
    echo -e "${RED}${EMOJI_ERROR} ${BOLD}错误${NC}: ${message}" >&2
    exit 1
}

# 打印错误信息（不退出）
print_error() {
    local message="$1"
    echo -e "${RED}${EMOJI_ERROR} ${BOLD}错误${NC}: ${message}" >&2
}

# 打印成功信息
print_success() {
    local message="$1"
    echo -e "${LIGHT_GREEN}${EMOJI_SUCCESS} ${message}${NC}"
}

# 打印警告信息
print_warning() {
    local message="$1"
    echo -e "${LIGHT_YELLOW}${EMOJI_WARNING} ${message}${NC}"
}

# 打印信息
print_info() {
    local message="$1"
    echo -e "${LIGHT_BLUE}${EMOJI_INFO} ${message}${NC}"
}

# 打印步骤标题
print_step() {
    local message="$1"
    echo -e "\n${BOLD}${LIGHT_BLUE}${EMOJI_BRANCH} ${message}${NC}"
    echo -e "${DIM}${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 显示帮助信息
show_help() {
    cat << EOF
$(print_info "$SCRIPT_NAME")

$(print_info "使用方法:")
  gc.sh [选项]

$(print_info "选项:")
  -h                显示帮助信息
  -e <环境>         指定环境 (灰度1-6, 预发1-2, vip, 线上)
  -c <类名>         指定类名 (支持完整类名或部分路径)
  -l <行号>         指定行号 (单行号或区间，如: 100 或 100-200)
  -n <数量>         指定查询的提交记录数量 (默认: $DEFAULT_COMMIT_COUNT)
  -m                过滤包含merge字样的提交记录
  -v                显示详细信息

$(print_info "环境列表:")
  灰度1, 灰度2, 灰度3, 灰度4, 灰度5, 灰度6
  预发1, 预发2, vip, 线上

$(print_info "示例:")
  gc.sh                                    # 交互式输入查询参数
  gc.sh -e 灰度1                           # 查询灰度1环境的提交记录
  gc.sh -e 预发1 -c UserService            # 查询预发1环境中UserService相关提交
  gc.sh -c UserService:100                 # 查询UserService类第100行相关提交
  gc.sh -c UserService:[100,25]            # 查询UserService类第100行相关提交(忽略列号)
  gc.sh -c UserService -l 100-200 -n 20    # 查询UserService类100-200行最近20条提交
  gc.sh -m                                 # 查询当前分支提交记录，过滤merge提交
  gc.sh UserService:100                    # 位置参数方式查询
EOF
}

#######################################
# Git操作函数
#######################################

# 检查是否为Git仓库
check_git_repository() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error_and_exit "当前目录不是有效的Git仓库"
    fi
}

# 获取当前分支
get_current_branch() {
    current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ -z "$current_branch" ]]; then
        print_error_and_exit "无法获取当前分支信息"
    fi
}

# 检查环境名是否有效
is_valid_env() {
    local env="$1"
    for valid_env in "${ENV_NAMES[@]}"; do
        if [[ "$valid_env" == "$env" ]]; then
            return 0
        fi
    done
    return 1
}

# 根据环境名获取最新的分支
get_latest_branch_by_env() {
    local env="$1"
    local latest_branch=""

    # 获取所有远程分支
    local all_branches
    all_branches=$(git branch -r | sed 's/origin\///' | sed 's/^[[:space:]]*//' | grep -v '^HEAD')

    case "$env" in
        "灰度1")
            # 匹配 gray1/yyMMdd 格式，找最新日期
            latest_branch=$(echo "$all_branches" | grep -E "^gray1/[0-9]{6}$" | sort -t'/' -k2 -n | tail -1)
            ;;
        "灰度2")
            latest_branch=$(echo "$all_branches" | grep -E "^gray2/[0-9]{6}$" | sort -t'/' -k2 -n | tail -1)
            ;;
        "灰度3")
            latest_branch=$(echo "$all_branches" | grep -E "^gray3/[0-9]{6}$" | sort -t'/' -k2 -n | tail -1)
            ;;
        "灰度4")
            latest_branch=$(echo "$all_branches" | grep -E "^gray4/[0-9]{6}$" | sort -t'/' -k2 -n | tail -1)
            ;;
        "灰度5")
            latest_branch=$(echo "$all_branches" | grep -E "^gray5/[0-9]{6}$" | sort -t'/' -k2 -n | tail -1)
            ;;
        "灰度6")
            latest_branch=$(echo "$all_branches" | grep -E "^gray6/[0-9]{6}$" | sort -t'/' -k2 -n | tail -1)
            ;;
        "预发1")
            # 匹配 release/x.xxx.preissue_yyMMdd 格式，按日期排序
            latest_branch=$(echo "$all_branches" | grep -E "^release/[0-9]+\.[0-9]+\.preissue_[0-9]{6}$" | sort -t'_' -k2 -n | tail -1)
            ;;
        "预发2")
            # 匹配 release/x.xxx.preissue2_yyMMdd 格式，按日期排序
            latest_branch=$(echo "$all_branches" | grep -E "^release/[0-9]+\.[0-9]+\.preissue2_[0-9]{6}$" | sort -t'_' -k2 -n | tail -1)
            ;;
        "vip")
            # 匹配 vip/yyMMdd 格式，找最新日期
            latest_branch=$(echo "$all_branches" | grep -E "^vip/[0-9]{6}$" | sort -t'/' -k2 -n | tail -1)
            ;;
        "线上")
            # 匹配 release/x.xxx.x 格式，按版本号排序
            latest_branch=$(echo "$all_branches" | grep -E "^release/[0-9]+\.[0-9]+\.[0-9]+$" | sort -V | tail -1)
            ;;
        *)
            print_error_and_exit "未知的环境: $env"
            ;;
    esac

    if [[ -z "$latest_branch" ]]; then
        print_warning "未找到环境 '$env' 对应的分支"
        return 1
    fi

    echo "$latest_branch"
}

# 格式化Java文件路径显示
format_java_path() {
    local file_path="$1"
    local clean_path="${file_path#./}"

    # 检查是否是Java文件
    if [[ "$clean_path" =~ \.java$ ]]; then
        # 查找src/main/java的位置
        if [[ "$clean_path" =~ ^(.*/)?src/main/java/(.+)\.java$ ]]; then
            local java_package_path="${BASH_REMATCH[2]}"

            # 将包路径的斜杠转换为点号
            local java_class_path="${java_package_path//\//.}.java"

            # 显示完整文件路径 + (Java类路径)
            echo "${GRAY}${clean_path}${NC} ${BLUE}(${java_class_path})${NC}"
        else
            # 不符合标准Java项目结构，直接显示原路径
            echo "${GRAY}${clean_path}${NC}"
        fi
    else
        # 非Java文件，直接显示路径
        echo "${GRAY}${clean_path}${NC}"
    fi
}

# 显示找到的文件列表并让用户选择
select_files_to_query() {
    local files="$1"
    local selected_files=()

    echo -e "  ${BOLD}${LIGHT_BLUE}${EMOJI_FILE} 相关文件${NC}" >&2
    echo -e "  ${DIM}${GRAY}─────────────────────────────────────────${NC}" >&2

    # 将文件转换为数组
    local file_array=()
    while read -r file; do
        [[ -n "$file" ]] || continue
        file_array+=("$file")
    done <<< "$files"

    # 如果只有一个文件，直接使用
    if [[ ${#file_array[@]} -eq 1 ]]; then
        local formatted_path
        formatted_path=$(format_java_path "${file_array[0]}")
        echo -e "    ${LIGHT_GREEN}${EMOJI_SEARCH}${NC} ${formatted_path}" >&2
        echo "${file_array[0]}"
        return 0
    fi

    # 显示文件列表供选择
    for i in "${!file_array[@]}"; do
        local formatted_path
        formatted_path=$(format_java_path "${file_array[$i]}")
        printf "    ${LIGHT_GRAY}%2d)${NC} ${formatted_path}\n" "$((i+1))" >&2
    done

    echo -e "\n  ${LIGHT_BLUE}${EMOJI_INFO}${NC} ${GRAY}请选择文件 (直接回车查询${LIGHT_GREEN}所有文件${GRAY}):${NC} " >&2
    read -r choice

    # 验证选择
    if [[ -z "$choice" ]]; then
        # 直接回车，查询所有文件
        for file in "${file_array[@]}"; do
            echo "$file"
        done
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#file_array[@]} ]]; then
        # 查询指定文件
        echo "${file_array[$((choice-1))]}"
    else
        echo -e "    ${LIGHT_YELLOW}${EMOJI_WARNING}${NC} ${GRAY}无效选择，将查询所有文件${NC}" >&2
        for file in "${file_array[@]}"; do
            echo "$file"
        done
    fi
}

# 查找并返回选中的文件列表
find_and_select_files() {
    local class="$1"

    if [[ -z "$class" ]]; then
        return 0
    fi

    # 查找包含类名的文件
    local files
    files=$(find . -name "*.java" -o -name "*.kt" -o -name "*.scala" -o -name "*.groovy" | grep -i "$class" | head -20)

    if [[ -z "$files" ]]; then
        # 如果没找到文件，尝试在所有文件中搜索类名
        files=$(git ls-files | grep -E '\.(java|kt|scala|groovy)$' | xargs grep -l "$class" 2>/dev/null | head -20)
    fi

    if [[ -n "$files" ]]; then
        # 让用户选择文件
        select_files_to_query "$files"
    else
        print_warning "在当前环境下未找到包含类名 '$class' 的文件"
        print_info "提示: 该文件可能在其他环境中存在，或者类名拼写有误"
        return 1
    fi
}

# 格式化提交信息显示 - 优化对齐和美观度
format_commit_info() {
    local hash="$1"
    local author="$2"
    local date="$3"
    local message="$4"

    # 格式化日期，去掉时区信息 (YYYY-MM-DD HH:MM:SS)
    local formatted_date
    # 先去掉时区部分，然后格式化
    local clean_date="${date%% +*}"
    clean_date="${clean_date%% -*}"

    # 兼容macOS和Linux的日期格式化
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        formatted_date=$(echo "$clean_date" | sed 's/T/ /' | cut -d' ' -f1-2)
        # 计算时间戳 - macOS格式
        local commit_timestamp
        commit_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$formatted_date" "+%s" 2>/dev/null || echo "0")
    else
        # Linux
        formatted_date=$(date -d "$clean_date" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "${clean_date}")
        # 计算时间戳 - Linux格式
        local commit_timestamp
        commit_timestamp=$(date -d "$clean_date" '+%s' 2>/dev/null || echo "0")
    fi

    # 计算相对时间
    local relative_time=""
    if [[ "$commit_timestamp" != "0" ]]; then
        relative_time=$(calculate_relative_time "$commit_timestamp")
    fi

    # 截断过长的作者名
    local short_author
    if [[ ${#author} -gt 12 ]]; then
        short_author="${author:0:9}..."
    else
        short_author="$author"
    fi

    # 截断过长的提交消息
    local short_message
    if [[ ${#message} -gt 85 ]]; then
        short_message="${message:0:82}..."
    else
        short_message="$message"
    fi

    # 使用对齐格式显示：时间→hash→作者(相对时间)，实现天然对齐
    if [[ -n "$relative_time" ]]; then
        printf "${EMOJI_TIME} ${LIGHT_BLUE}%-19s${NC} ${EMOJI_HASH} ${YELLOW}%-8s${NC} ${EMOJI_USER} ${LIGHT_PURPLE}%s${NC} ${DIM}${GRAY}(%s)${NC}\n" \
               "$formatted_date" "${hash:0:8}" "$short_author" "$relative_time"
    else
        printf "${EMOJI_TIME} ${LIGHT_BLUE}%-19s${NC} ${EMOJI_HASH} ${YELLOW}%-8s${NC} ${EMOJI_USER} ${LIGHT_PURPLE}%s${NC}\n" \
               "$formatted_date" "${hash:0:8}" "$short_author"
    fi
    printf "   ${EMOJI_COMMIT} ${LIGHT_GREEN}%s${NC}\n" "$short_message"
}

# 检查文件是否存在于指定分支
check_file_exists_in_branch() {
    local branch="$1"
    local file="$2"

    # 检查文件是否存在于指定分支
    if [[ "$branch" != "$current_branch" ]]; then
        git show "origin/$branch:$file" >/dev/null 2>&1
    else
        [[ -f "$file" ]]
    fi
}

# 检查行号是否存在于文件中
check_line_exists_in_file() {
    local branch="$1"
    local file="$2"
    local line_number="$3"

    local file_content
    if [[ "$branch" != "$current_branch" ]]; then
        file_content=$(git show "origin/$branch:$file" 2>/dev/null)
    else
        file_content=$(cat "$file" 2>/dev/null)
    fi

    if [[ -z "$file_content" ]]; then
        return 1
    fi

    local total_lines
    total_lines=$(echo "$file_content" | wc -l)

    if [[ "$line_number" -gt "$total_lines" ]]; then
        return 1
    fi

    return 0
}

# 查询单个文件的提交记录
query_commits_for_file() {
    local branch="$1"
    local file="$2"
    local line_range="$3"
    local count="$4"
    local filter_merge_flag="$5"

    local formatted_path
    formatted_path=$(format_java_path "$file")
    echo -e "\n${BOLD}${LIGHT_BLUE}${EMOJI_FILE} 查询文件${NC}"
    echo -e "${DIM}${GRAY}─────────────────────────────────────────${NC}"
    echo -e "  ${LIGHT_GREEN}${EMOJI_SEARCH}${NC} ${formatted_path}"
    if [[ -n "$line_range" ]]; then
        echo -e "  ${LIGHT_YELLOW}${EMOJI_LINE}${NC} ${GRAY}行号范围: ${LIGHT_YELLOW}${line_range}${NC}"
    fi
    echo ""

    # 检查文件是否存在于指定分支
    if ! check_file_exists_in_branch "$branch" "$file"; then
        print_warning "文件在分支 '$branch' 中不存在"
        print_info "提示: 该文件可能在其他分支中存在，或者已被删除"
        return 1
    fi

    # 如果指定了行号，检查行号是否存在
    if [[ -n "$line_range" ]]; then
        local check_line=""
        if [[ "$line_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            # 行号区间，检查起始行号
            check_line="${BASH_REMATCH[1]}"
        elif [[ "$line_range" =~ ^[0-9]+$ ]]; then
            # 单行号
            check_line="$line_range"
        fi

        if [[ -n "$check_line" ]] && ! check_line_exists_in_file "$branch" "$file" "$check_line"; then
            print_warning "指定的行号 $check_line 在文件中不存在"
            local file_content
            if [[ "$branch" != "$current_branch" ]]; then
                file_content=$(git show "origin/$branch:$file" 2>/dev/null)
            else
                file_content=$(cat "$file" 2>/dev/null)
            fi
            local total_lines
            total_lines=$(echo "$file_content" | wc -l)
            print_info "提示: 该文件共有 $total_lines 行"
            return 1
        fi
    fi

    # 如果需要过滤merge提交，获取更多记录以确保最终数量足够
    local fetch_count="$count"
    if [[ "$filter_merge_flag" == "true" ]]; then
        fetch_count=$((count * 5))  # 获取5倍数量以应对过滤
    else
        fetch_count=$((count * 2))  # 获取2倍数量以防不足
    fi

    # 构建git log命令 - 不使用-L参数避免显示diff
    local git_cmd="git log --oneline --pretty=format:'%H|%an|%ai|%s' -n $fetch_count"

    # 添加分支参数
    if [[ "$branch" != "$current_branch" ]]; then
        git_cmd="$git_cmd origin/$branch"
    fi

    # 添加文件参数
    git_cmd="$git_cmd -- $file"

    # 执行查询
    local commits
    commits=$(eval "$git_cmd" 2>/dev/null)

    if [[ -z "$commits" ]]; then
        print_warning "未找到该文件的提交记录"
        print_info "提示: 该文件可能是新文件，或者在当前分支中没有提交历史"
        return 1
    fi

    # 处理结果
    local display_count=0
    local total_processed=0
    local available_commits=0

    # 先统计可用的提交数量
    while IFS='|' read -r hash author date message; do
        ((available_commits++))
    done <<< "$commits"

    # 如果可用提交数量少于请求数量，给出提示
    if [[ $available_commits -lt $count ]]; then
        print_info "注意: 该文件只有 $available_commits 条提交记录，少于请求的 $count 条"
    fi

    while IFS='|' read -r hash author date message && [[ $display_count -lt $count ]]; do
        ((total_processed++))

        # 过滤merge提交
        if [[ "$filter_merge_flag" == "true" && "$message" =~ [Mm]erge ]]; then
            continue
        fi

        # 如果指定了行号范围，检查该提交是否涉及指定行号
        if [[ -n "$line_range" ]]; then
            local line_changed=false
            if [[ "$line_range" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                # 行号区间
                local start_line="${BASH_REMATCH[1]}"
                local end_line="${BASH_REMATCH[2]}"
                # 简化处理：检查提交是否修改了文件（实际项目中可以更精确地检查行号）
                line_changed=true
            elif [[ "$line_range" =~ ^[0-9]+$ ]]; then
                # 单行号
                line_changed=true
            fi

            if [[ "$line_changed" != "true" ]]; then
                continue
            fi
        fi

        ((display_count++))
        format_commit_info "$hash" "$author" "$date" "$message"
        echo ""
    done <<< "$commits"

    if [[ $display_count -eq 0 ]]; then
        if [[ "$filter_merge_flag" == "true" ]]; then
            print_warning "过滤merge提交后没有找到匹配的提交记录"
            print_info "提示: 尝试不过滤merge提交，或者该文件的提交都是merge类型"
        else
            print_warning "没有找到匹配的提交记录"
        fi
        return 1
    fi

    echo -e "${LIGHT_GREEN}${EMOJI_SUCCESS}${NC} ${GRAY}该文件找到 ${LIGHT_GREEN}$display_count${GRAY} 条提交记录${NC}"
    if [[ "$filter_merge_flag" == "true" && $total_processed -gt $display_count ]]; then
        echo -e "${LIGHT_BLUE}${EMOJI_FILTER}${NC} ${GRAY}已过滤 ${LIGHT_YELLOW}$((total_processed - display_count))${GRAY} 条merge提交${NC}"
    fi

    # 如果实际显示数量少于请求数量，给出说明
    if [[ $display_count -lt $count ]]; then
        if [[ "$filter_merge_flag" == "true" ]]; then
            print_info "说明: 该文件实际可显示 $display_count 条记录（过滤merge提交后），少于请求的 $count 条"
        else
            print_info "说明: 该文件实际可显示 $display_count 条记录，少于请求的 $count 条"
        fi
    fi
}

# 查询提交记录（支持多文件）
query_commits() {
    local branch="$1"
    local selected_files="$2"
    local line_range="$3"
    local count="$4"
    local filter_merge_flag="$5"

    print_step "查询分支: $branch"

    if [[ -z "$selected_files" ]]; then
        # 没有指定文件，查询整个分支
        # 如果需要过滤merge提交，获取更多记录以确保最终数量足够
        local fetch_count="$count"
        if [[ "$filter_merge_flag" == "true" ]]; then
            fetch_count=$((count * 3))  # 获取3倍数量以应对过滤
        fi

        # 构建git log命令
        local git_cmd="git log --oneline --pretty=format:'%H|%an|%ai|%s' -n $fetch_count"

        # 添加分支参数
        if [[ "$branch" != "$current_branch" ]]; then
            git_cmd="$git_cmd origin/$branch"
        fi

        # 执行查询
        local commits
        commits=$(eval "$git_cmd" 2>/dev/null)

        if [[ -z "$commits" ]]; then
            print_warning "未找到匹配的提交记录"
            print_info "提示: 该分支可能没有提交记录，或者分支不存在"
            return 1
        fi

        # 处理结果
        local display_count=0
        local total_processed=0
        local available_commits=0

        # 先统计可用的提交数量
        while IFS='|' read -r hash author date message; do
            ((available_commits++))
        done <<< "$commits"

        # 如果可用提交数量少于请求数量，给出提示
        if [[ $available_commits -lt $count ]]; then
            print_info "注意: 该分支只有 $available_commits 条提交记录，少于请求的 $count 条"
        fi

        while IFS='|' read -r hash author date message && [[ $display_count -lt $count ]]; do
            ((total_processed++))

            # 过滤merge提交
            if [[ "$filter_merge_flag" == "true" && "$message" =~ [Mm]erge ]]; then
                continue
            fi

            ((display_count++))
            format_commit_info "$hash" "$author" "$date" "$message"
            echo ""
        done <<< "$commits"

        if [[ $display_count -eq 0 ]]; then
            if [[ "$filter_merge_flag" == "true" ]]; then
                print_warning "过滤merge提交后没有找到匹配的提交记录"
                print_info "提示: 尝试不过滤merge提交，或者该分支的提交都是merge类型"
            else
                print_warning "没有找到匹配的提交记录"
            fi
            return 1
        fi

        print_success "共找到 $display_count 条提交记录"
        if [[ "$filter_merge_flag" == "true" && $total_processed -gt $display_count ]]; then
            print_info "已过滤 $((total_processed - display_count)) 条merge提交"
        fi

        # 如果实际显示数量少于请求数量，给出说明
        if [[ $display_count -lt $count ]]; then
            if [[ "$filter_merge_flag" == "true" ]]; then
                print_info "说明: 该分支实际可显示 $display_count 条记录（过滤merge提交后），少于请求的 $count 条"
            else
                print_info "说明: 该分支实际可显示 $display_count 条记录，少于请求的 $count 条"
            fi
        fi
    else
        # 查询指定文件 - 每个文件都查询指定数量
        local file_count=0
        while read -r file; do
            [[ -n "$file" ]] || continue
            ((file_count++))
            query_commits_for_file "$branch" "$file" "$line_range" "$count" "$filter_merge_flag"
        done <<< "$selected_files"

        if [[ $file_count -gt 1 ]]; then
            print_success "共查询了 $file_count 个文件，每个文件 $count 条记录"
        fi
    fi
}

# 同步远程分支信息
sync_remote_branches() {
    echo -e "${LIGHT_BLUE}${EMOJI_SYNC}${NC} ${GRAY}正在同步远程分支信息...${NC}"
    git fetch --all --prune >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        echo -e "${LIGHT_GREEN}${EMOJI_SUCCESS}${NC} ${GRAY}远程分支信息同步完成${NC}"
    else
        echo -e "${LIGHT_YELLOW}${EMOJI_WARNING}${NC} ${GRAY}远程分支信息同步失败，继续使用本地缓存${NC}"
    fi
}

# 显示环境选择菜单
select_environment() {
    echo -e "  ${BOLD}${LIGHT_BLUE}${EMOJI_ENV} 环境选择${NC}" >&2
    echo -e "  ${DIM}${GRAY}─────────────────────────────────────────${NC}" >&2

    local index=1
    for env in "${ENV_NAMES[@]}"; do
        printf "    ${LIGHT_GRAY}%2d)${NC} ${LIGHT_PURPLE}%s${NC}\n" "$index" "$env" >&2
        ((index++))
    done

    echo -e "\n  ${LIGHT_BLUE}${EMOJI_INFO}${NC} ${GRAY}请选择环境 (直接回车使用本地分支: ${LIGHT_GREEN}$current_branch${GRAY}):${NC} " >&2
    read -r choice

    if [[ -z "$choice" ]]; then
        # 直接回车，使用本地
        echo ""
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#ENV_NAMES[@]} ]]; then
        # 选择环境
        local env_index=$((choice - 1))
        echo "${ENV_NAMES[$env_index]}"
    else
        echo -e "    ${LIGHT_YELLOW}${EMOJI_WARNING}${NC} ${GRAY}无效选择，使用本地环境${NC}" >&2
        echo ""
    fi
}

# 主查询逻辑
perform_query() {
    local target_branch=""

    # 确定要查询的分支
    if [[ -n "$target_env" ]]; then
        # 指定了环境，同步远程分支并获取最新分支
        sync_remote_branches
        print_info "正在查找环境 '$target_env' 的最新分支..."
        target_branch=$(get_latest_branch_by_env "$target_env")
        if [[ $? -ne 0 || -z "$target_branch" ]]; then
            return 1
        fi
        print_success "找到最新分支: $target_branch"
    else
        # 使用当前分支
        target_branch="$current_branch"
    fi

    # 查找并选择文件
    local selected_files=""
    if [[ -n "$class_name" ]]; then
        selected_files=$(find_and_select_files "$class_name")
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    # 查询分支
    query_commits "$target_branch" "$selected_files" "$line_range" "$commit_count" "$filter_merge"
}

#######################################
# 参数解析函数
#######################################

# 解析类名和行号的组合格式
parse_class_and_line() {
    local input="$1"

    # 支持格式: ClassName:line 或 ClassName:[line,column]
    if [[ "$input" =~ ^([^:]+):(.+)$ ]]; then
        local class_part="${BASH_REMATCH[1]}"
        local line_part="${BASH_REMATCH[2]}"

        # 去掉可能的.java后缀
        class_name="${class_part%.java}"

        # 解析行号部分
        if [[ "$line_part" =~ ^\[([0-9]+),([0-9]+)\]$ ]]; then
            # 格式: [line,column] - 忽略列号
            line_range="${BASH_REMATCH[1]}"
        elif [[ "$line_part" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
            # 格式: line 或 line-line
            line_range="$line_part"
        else
            print_error_and_exit "无效的行号格式: $line_part"
        fi

        return 0
    fi

    return 1
}

# 解析命令行参数
parse_arguments() {
    while getopts "he:c:l:n:mv" opt; do
        case $opt in
            h)
                show_help
                exit 0
                ;;
            e)
                target_env="$OPTARG"
                env_specified=true
                # 验证环境名称
                if ! is_valid_env "$target_env"; then
                    print_error_and_exit "无效的环境名称: $target_env"
                fi
                ;;
            c)
                class_specified=true
                # 尝试解析组合格式
                if parse_class_and_line "$OPTARG"; then
                    # 已经在函数中设置了class_name和line_range
                    line_specified=true
                else
                    class_name="$OPTARG"
                fi
                ;;
            l)
                line_range="$OPTARG"
                line_specified=true
                # 验证行号格式
                if [[ ! "$line_range" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                    print_error_and_exit "无效的行号格式: $line_range (应为数字或数字-数字)"
                fi
                ;;
            n)
                commit_count="$OPTARG"
                count_specified=true
                # 验证数量格式
                if [[ ! "$commit_count" =~ ^[0-9]+$ ]] || [[ "$commit_count" -le 0 ]]; then
                    print_error_and_exit "无效的提交记录数量: $commit_count"
                fi
                ;;
            m)
                filter_merge=true
                merge_specified=true
                ;;
            v)
                set -x  # 启用详细模式
                ;;
            \?)
                print_error_and_exit "无效的选项: -$OPTARG"
                ;;
        esac
    done

    # 处理位置参数（支持直接传入 ClassName:line 格式）
    shift $((OPTIND-1))
    if [[ $# -gt 0 && -z "$class_name" ]]; then
        class_specified=true
        if parse_class_and_line "$1"; then
            # 已经在函数中设置了class_name和line_range
            line_specified=true
        else
            class_name="$1"
        fi
    fi
}

#######################################
# 主程序入口
#######################################

# 智能参数询问 - 只询问缺少的参数
smart_input_missing_params() {
    local need_input=false

    # 检查是否需要询问环境
    if [[ "$env_specified" == "false" ]]; then
        echo -e "${CYAN}选择环境:${NC}"
        local selected_env
        selected_env=$(select_environment)
        if [[ -n "$selected_env" ]]; then
            target_env="$selected_env"
        fi
        need_input=true
        echo ""
    fi

    # 检查是否需要询问类名
    if [[ "$class_specified" == "false" ]]; then
        echo -e "${CYAN}输入类名或文件名 (支持 ClassName:line 格式):${NC}"
        echo -n -e "  ${BLUE}${EMOJI_SEARCH} 类名/文件名 (默认: 无): ${NC}"
        read -r input_class
        if [[ -n "$input_class" ]]; then
            if parse_class_and_line "$input_class"; then
                # 已经在函数中设置了class_name和line_range
                :
            else
                class_name="$input_class"
            fi
        fi
        need_input=true
        echo ""
    fi

    # 检查是否需要询问行号
    if [[ "$line_specified" == "false" && -z "$line_range" ]]; then
        echo -e "${CYAN}输入行号范围:${NC}"
        echo -n -e "  ${BLUE}${EMOJI_SEARCH} 行号 (格式: 100 或 100-200, 默认: 无): ${NC}"
        read -r input_line
        if [[ -n "$input_line" ]]; then
            if [[ "$input_line" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                line_range="$input_line"
            else
                print_warning "无效的行号格式，忽略"
            fi
        fi
        need_input=true
        echo ""
    fi

    # 检查是否需要询问提交记录数量（只有在没有指定主要查询参数时才询问）
    if [[ "$count_specified" == "false" && "$env_specified" == "false" && "$class_specified" == "false" && "$line_specified" == "false" ]]; then
        echo -e "${CYAN}查询提交记录数量:${NC}"
        echo -n -e "  ${BLUE}${EMOJI_SEARCH} 数量 (默认: $DEFAULT_COMMIT_COUNT): ${NC}"
        read -r input_count
        if [[ -n "$input_count" ]]; then
            if [[ "$input_count" =~ ^[0-9]+$ ]] && [[ "$input_count" -gt 0 ]]; then
                commit_count="$input_count"
            else
                print_warning "无效的数量格式，使用默认值"
            fi
        fi
        need_input=true
        echo ""
    fi

    # 检查是否需要询问过滤merge提交（只有在没有指定主要查询参数时才询问）
    if [[ "$merge_specified" == "false" && "$env_specified" == "false" && "$class_specified" == "false" && "$line_specified" == "false" ]]; then
        echo -e "${CYAN}是否过滤merge提交:${NC}"
        echo -n -e "  ${BLUE}${EMOJI_SEARCH} 过滤merge提交 (y/n, 默认: 不过滤): ${NC}"
        read -r input_filter
        if [[ "$input_filter" =~ ^[Yy]$ ]]; then
            filter_merge=true
        fi
        need_input=true
        echo ""
    fi

    if [[ "$need_input" == "true" ]]; then
        echo -e "${GRAY}──────────────────────────────────────────────────${NC}"
    fi
}

# 完整交互式输入参数（无参数时使用）
full_interactive_input() {
    echo -e "${BLUE}${EMOJI_INFO} 交互式参数输入 (直接回车使用默认值)${NC}\n"

    # 环境选择
    echo -e "${CYAN}1. 选择环境:${NC}"
    local selected_env
    selected_env=$(select_environment)
    if [[ -n "$selected_env" ]]; then
        target_env="$selected_env"
    fi

    # 类名输入
    echo -e "\n${CYAN}2. 输入类名或文件名 (支持 ClassName:line 格式):${NC}"
    echo -n -e "  ${BLUE}${EMOJI_SEARCH} 类名/文件名 (默认: 无): ${NC}"
    read -r input_class
    if [[ -n "$input_class" ]]; then
        if parse_class_and_line "$input_class"; then
            # 已经在函数中设置了class_name和line_range
            :
        else
            class_name="$input_class"
        fi
    fi

    # 行号输入（如果还没有设置）
    if [[ -z "$line_range" ]]; then
        echo -e "\n${CYAN}3. 输入行号范围:${NC}"
        echo -n -e "  ${BLUE}${EMOJI_SEARCH} 行号 (格式: 100 或 100-200, 默认: 无): ${NC}"
        read -r input_line
        if [[ -n "$input_line" ]]; then
            if [[ "$input_line" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                line_range="$input_line"
            else
                print_warning "无效的行号格式，忽略"
            fi
        fi
    fi

    # 提交记录数量
    echo -e "\n${CYAN}4. 查询提交记录数量:${NC}"
    echo -n -e "  ${BLUE}${EMOJI_SEARCH} 数量 (默认: $DEFAULT_COMMIT_COUNT): ${NC}"
    read -r input_count
    if [[ -n "$input_count" ]]; then
        if [[ "$input_count" =~ ^[0-9]+$ ]] && [[ "$input_count" -gt 0 ]]; then
            commit_count="$input_count"
        else
            print_warning "无效的数量格式，使用默认值"
        fi
    fi

    # 是否过滤merge提交
    echo -e "\n${CYAN}5. 是否过滤merge提交:${NC}"
    echo -n -e "  ${BLUE}${EMOJI_SEARCH} 过滤merge提交 (y/N, 默认: 不过滤): ${NC}"
    read -r input_filter
    if [[ "$input_filter" =~ ^[Yy]$ ]]; then
        filter_merge=true
    fi

    echo ""
}

main() {
    # 检查是否是更新参数
    for arg in "$@"; do
        if [[ "$arg" == "-u" || "$arg" == "--update" ]]; then
            # 手动触发更新检查
            if [[ -n "${GITLAB_TOKEN:-}" ]]; then
                local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
                if [[ -f "$sv_script" ]]; then
                    # 使用子shell避免变量冲突
                    if (source "$sv_script" && check_script_update "gs.sh") 2>/dev/null; then
                        exit 0
                    else
                        echo -e "${RED}错误: 更新检查失败${NC}"
                        exit 1
                    fi
                else
                    echo -e "${RED}错误: 更新脚本不存在: $sv_script${NC}"
                    exit 1
                fi
            else
                echo -e "${YELLOW}警告: 未设置 GITLAB_TOKEN 环境变量，无法检查更新${NC}"
                echo -e "${CYAN}请先使用 sv.sh -c 进行配置或运行 br.sh 脚本${NC}"
                exit 1
            fi
        fi
    done

    # 自动更新检查（如果有Token的话）
    if [[ -n "${GITLAB_TOKEN:-}" ]]; then
        local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
        if [[ -f "$sv_script" ]]; then
            # 使用子shell避免变量冲突
            (source "$sv_script" && check_script_update "gs.sh") 2>/dev/null || true
        fi
    fi

    # 显示欢迎信息
    echo -e "\n${BOLD}${LIGHT_BLUE}${EMOJI_ROCKET} $SCRIPT_NAME${NC}"
    echo -e "${DIM}${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    # 检查Git仓库
    check_git_repository

    # 获取当前分支
    get_current_branch

    # 解析参数
    parse_arguments "$@"

    # 根据参数情况决定输入方式
    if [[ $# -eq 0 ]]; then
        # 没有任何参数，启用完整交互式输入
        full_interactive_input
    else
        # 有参数，智能询问缺少的参数
        smart_input_missing_params
    fi

    # 显示查询参数
    echo -e "${BOLD}${LIGHT_BLUE}${EMOJI_SEARCH} 查询参数${NC}"
    echo -e "${DIM}${GRAY}─────────────────────────────────────────${NC}"
    printf "  ${LIGHT_BLUE}${EMOJI_ENV}${NC} ${GRAY}%-6s${NC} ${LIGHT_GREEN}%s${NC}\n" "环境:" "${target_env:-当前分支($current_branch)}"
    [[ -n "$class_name" ]] && printf "  ${LIGHT_BLUE}${EMOJI_FILE}${NC} ${GRAY}%-6s${NC} ${LIGHT_PURPLE}%s${NC}\n" "类名:" "$class_name"
    [[ -n "$line_range" ]] && printf "  ${LIGHT_BLUE}${EMOJI_LINE}${NC} ${GRAY}%-6s${NC} ${LIGHT_YELLOW}%s${NC}\n" "行号:" "$line_range"
    printf "  ${LIGHT_BLUE}${EMOJI_COUNT}${NC} ${GRAY}%-6s${NC} ${WHITE}%s${NC}\n" "数量:" "$commit_count"
    [[ "$filter_merge" == "true" ]] && printf "  ${LIGHT_BLUE}${EMOJI_FILTER}${NC} ${GRAY}%-6s${NC} ${LIGHT_YELLOW}%s${NC}\n" "过滤:" "排除merge"
    echo ""

    # 执行查询
    perform_query

    echo -e "\n${BOLD}${LIGHT_GREEN}${EMOJI_SUCCESS} 查询完成！${NC}"
    echo -e "${DIM}${GRAY}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 执行主程序
main "$@"
