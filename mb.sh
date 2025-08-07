#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.3"

# =============================================================================
# 项目构建脚本
# 描述: 用于项目的自动化构建工具，具有增强的日志记录、
#       错误处理和用户体验改进功能
# 作者: 开发者
# 版本: 1.0
# =============================================================================

set -euo pipefail  # 启用严格错误处理

# =============================================================================
# 配置设置
# =============================================================================

# 终端设置
readonly TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# 构建配置
readonly DEFAULT_MAVEN_OPTS="-DfailOnError=false -DinstallAtEnd=true -Dmaven.test.skip=true -T 2C"
readonly BUILD_TIMEOUT=1800  # 构建超时时间：30分钟

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # 无颜色

# =============================================================================
# 日志记录函数
# =============================================================================

# 带颜色和表情符号的增强日志记录函数
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "SUCCESS")
            echo -e "${GREEN}✅ [${timestamp}] ${message}${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ [${timestamp}] ${message}${NC}" >&2
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  [${timestamp}] ${message}${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  [${timestamp}] ${message}${NC}"
            ;;
        "PROGRESS")
            echo -e "${PURPLE}🚀 [${timestamp}] ${message}${NC}"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-}" == "true" ]]; then
                echo -e "${CYAN}🔍 [${timestamp}] ${message}${NC}"
            fi
            ;;
        *)
            echo -e "${WHITE}📝 [${timestamp}] ${message}${NC}"
            ;;
    esac
}

# 打印分隔线
print_separator() {
    local char="${1:-=}"
    local length="${2:-$TERM_WIDTH}"
    printf "%*s\n" "$length" | tr ' ' "$char"
}

# 打印章节标题
print_section() {
    local title="$1"
    local padding=$(( (TERM_WIDTH - ${#title} - 4) / 2 ))

    echo
    print_separator "="
    printf "%*s %s %*s\n" "$padding" "" "$title" "$padding" ""
    print_separator "="
    echo
}

# =============================================================================
# 实用工具函数
# =============================================================================

# 将秒数转换为人类可读的格式
convert_time() {
    local total_seconds="$1"
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))

    if [[ $hours -gt 0 ]]; then
        echo "${hours}小时 ${minutes}分钟 ${seconds}秒"
    elif [[ $minutes -gt 0 ]]; then
        echo "${minutes}分钟 ${seconds}秒"
    else
        echo "${seconds}秒"
    fi
}

# 执行命令并记录时间和日志
execute_with_timing() {
    local label="$1"
    shift 1

    log "PROGRESS" "开始执行: $label"
    local start_timestamp
    start_timestamp=$(date +%s)

    # 执行命令
    if "$@"; then
        local end_timestamp
        end_timestamp=$(date +%s)
        local elapsed_time=$((end_timestamp - start_timestamp))
        local elapsed_time_converted
        elapsed_time_converted=$(convert_time "$elapsed_time")

        log "SUCCESS" "$label 完成 (耗时: $elapsed_time_converted)"
        return 0
    else
        local exit_code=$?
        local end_timestamp
        end_timestamp=$(date +%s)
        local elapsed_time=$((end_timestamp - start_timestamp))
        local elapsed_time_converted
        elapsed_time_converted=$(convert_time "$elapsed_time")

        log "ERROR" "$label 失败 (耗时: $elapsed_time_converted, 退出码: $exit_code)"
        return $exit_code
    fi
}

# =============================================================================
# 项目发现和验证
# =============================================================================

# 检查当前目录是否为 git 仓库或包含 git 仓库
validate_environment() {
    log "INFO" "验证构建环境..."

    # 检查是否安装了 git
    if ! command -v git &> /dev/null; then
        log "ERROR" "Git 未安装或不在 PATH 中"
        exit 1
    fi

    # 检查是否安装了 maven
    if ! command -v mvn &> /dev/null; then
        log "ERROR" "Maven 未安装或不在 PATH 中"
        exit 1
    fi

    log "SUCCESS" "环境验证通过"
}

# 在当前目录中发现所有 Git 项目并进行增强验证
discover_git_projects() {
    local all_projects=()

    # 检查当前目录是否为包含 Maven 项目的 Git 仓库
    if git rev-parse --git-dir &>/dev/null 2>&1; then
        # 首先查找子目录中的独立 Git 仓库
        while IFS= read -r -d '' git_dir; do
            local project_path
            project_path=$(dirname "$git_dir")
            project_path=${project_path#./}  # 移除前导 ./

            # 跳过空路径（当前目录）
            if [[ -z "$project_path" ]] || [[ "$project_path" == "." ]]; then
                continue
            fi

            # 验证这确实是一个有效的 git 仓库
            if git -C "$project_path" rev-parse --git-dir &>/dev/null 2>&1; then
                # 检查是否为 Maven 项目
                if [[ -f "$project_path/pom.xml" ]]; then
                    all_projects+=("$project_path")
                fi
            fi
        done < <(find . -maxdepth 2 -name ".git" -type d -print0 2>/dev/null)

        # 如果没有找到独立的 Git 仓库，则在当前仓库中查找 Maven 模块
        if [[ ${#all_projects[@]} -eq 0 ]]; then
            # 检查当前目录是否有 pom.xml（根项目）
            if [[ -f "./pom.xml" ]]; then
                all_projects+=(".")
            fi

            # 在子目录中查找 Maven 模块
            while IFS= read -r -d '' pom_file; do
                local module_path
                module_path=$(dirname "$pom_file")
                module_path=${module_path#./}  # 移除前导 ./

                # 跳过根 pom.xml 和空路径
                if [[ -z "$module_path" ]] || [[ "$module_path" == "." ]]; then
                    continue
                fi

                # 只包含直接子目录（不包含嵌套模块）
                if [[ "$module_path" != *"/"* ]]; then
                    all_projects+=("$module_path")
                fi
            done < <(find . -maxdepth 2 -name "pom.xml" -type f -print0 2>/dev/null)
        fi
    else
        # 不在 Git 仓库中，查找独立的 Git 仓库
        while IFS= read -r -d '' git_dir; do
            local project_path
            project_path=$(dirname "$git_dir")
            project_path=${project_path#./}  # 移除前导 ./

            # 验证这确实是一个有效的 git 仓库
            if git -C "$project_path" rev-parse --git-dir &>/dev/null 2>&1; then
                # 检查是否为 Maven 项目
                if [[ -f "$project_path/pom.xml" ]]; then
                    all_projects+=("$project_path")
                fi
            fi
        done < <(find . -maxdepth 2 -name ".git" -type d -print0 2>/dev/null)
    fi

    if [[ ${#all_projects[@]} -eq 0 ]]; then
        return 1
    fi

    # 按优先级项目排序
    local top_projects=("." "project-core" "project-items-core" "project-platform" "project-pt" "project-wms")
    local final_projects=()
    local remaining_projects=()

    # 首先添加优先级项目（如果存在）
    for priority_proj in "${top_projects[@]}"; do
        for proj in "${all_projects[@]}"; do
            if [[ "$proj" == "$priority_proj" ]]; then
                final_projects+=("$proj")
                break
            fi
        done
    done

    # 添加剩余项目（已排序）
    for proj in "${all_projects[@]}"; do
        local is_priority=false
        for priority_proj in "${top_projects[@]}"; do
            if [[ "$proj" == "$priority_proj" ]]; then
                is_priority=true
                break
            fi
        done
        if [[ "$is_priority" == false ]]; then
            remaining_projects+=("$proj")
        fi
    done

    # 对剩余项目排序并添加到最终列表
    if [[ ${#remaining_projects[@]} -gt 0 ]]; then
        IFS=$'\n' remaining_projects=($(sort <<<"${remaining_projects[*]}"))
        final_projects+=("${remaining_projects[@]}")
    fi

    printf '%s\n' "${final_projects[@]}"
}

# 获取所有项目的分支信息并进行错误处理
get_project_branches() {
    local projects=("$@")
    local branches=()

    for proj in "${projects[@]}"; do
        local branch
        if branch=$(git -C "$proj" rev-parse --abbrev-ref HEAD 2>/dev/null); then
            # 简单检查是否有未跟踪或已修改的文件（仅用于显示，不影响构建）
            local status_output
            if status_output=$(git -C "$proj" status --porcelain 2>/dev/null) && [[ -n "$status_output" ]]; then
                branch="$branch*"  # 用星号标记有未提交更改的分支
            fi
            branches+=("$branch")
        else
            branches+=("unknown")
        fi
    done

    printf '%s\n' "${branches[@]}"
}

# =============================================================================
# 用户界面和输入处理
# =============================================================================

# 以格式化表格显示项目，具有增强的视觉效果
display_projects() {
    local projects=("$@")
    local branches
    IFS=$'\n' read -d '' -r -a branches < <(get_project_branches "${projects[@]}" && printf '\0')

    print_section "可用的项目列表"

    # 计算列宽
    local max_proj_length=0
    local max_branch_length=0

    for proj in "${projects[@]}"; do
        if [[ ${#proj} -gt $max_proj_length ]]; then
            max_proj_length=${#proj}
        fi
    done

    for branch in "${branches[@]}"; do
        if [[ ${#branch} -gt $max_branch_length ]]; then
            max_branch_length=${#branch}
        fi
    done

    # 确保最小宽度
    max_proj_length=$((max_proj_length < 15 ? 15 : max_proj_length))
    max_branch_length=$((max_branch_length < 10 ? 10 : max_branch_length))

    # 计算布局
    local num_width=4  # 项目编号宽度
    local status_width=8  # 状态指示器宽度
    local column_width=$((num_width + max_proj_length + max_branch_length + status_width + 10))
    local num_columns=$((TERM_WIDTH / column_width))
    num_columns=$((num_columns < 1 ? 1 : num_columns))

    # 打印表头
    printf "${BOLD}${BLUE}%-${num_width}s %-${max_proj_length}s %-${max_branch_length}s %-${status_width}s${NC}\n" \
           "编号" "项目名称" "当前分支" "状态"
    print_separator "-" $((column_width - 5))

    # 打印项目
    for i in "${!projects[@]}"; do
        local proj="${projects[$i]}"
        local branch="${branches[$i]}"
        local status="✅ 就绪"
        local color="$GREEN"

        # 检查项目状态
        if [[ "$branch" == *"*" ]]; then
            status="📝 有更改"
            color="$CYAN"  # 使用青色，不那么刺眼
        elif [[ "$branch" == "unknown" ]]; then
            status="❌ 错误"
            color="$RED"
        fi

        printf "${color}%-${num_width}s %-${max_proj_length}s %-${max_branch_length}s %-${status_width}s${NC}" \
               "$((i + 1))." "$proj" "$branch" "$status"

        # 根据列布局添加换行
        if [[ $(( (i + 1) % num_columns )) -eq 0 ]] || [[ $i -eq $((${#projects[@]} - 1)) ]]; then
            echo
        else
            echo -n "  "
        fi
    done

    echo
}

# Validate user input for project selection
validate_project_selection() {
    local input="$1"
    local max_projects="$2"
    local numbers

    # Split input into array
    IFS=' ' read -r -a numbers <<< "$input"

    # Validate each number
    for number in "${numbers[@]}"; do
        # Check if it's a valid number
        if ! [[ "$number" =~ ^[0-9]+$ ]]; then
            log "ERROR" "无效输入 '$number': 必须是数字"
            return 1
        fi

        # Check if it's in valid range
        if [[ "$number" -le 0 ]] || [[ "$number" -gt "$max_projects" ]]; then
            log "ERROR" "无效编号 '$number': 必须在 1-$max_projects 范围内"
            return 1
        fi
    done

    # Check for duplicates
    local unique_numbers
    IFS=$'\n' unique_numbers=($(printf '%s\n' "${numbers[@]}" | sort -nu))

    if [[ ${#unique_numbers[@]} -ne ${#numbers[@]} ]]; then
        log "WARNING" "检测到重复的项目编号，已自动去重"
    fi

    printf '%s\n' "${unique_numbers[@]}"
}

# 获取用户输入，具有增强的提示和验证功能
get_user_selection() {
    local projects=("$@")
    local project_numbers=()
    local ignore_logs="Y"

    # 显示项目列表
    display_projects "${projects[@]}"

    # 获取项目选择
    while true; do
        echo
        log "INFO" "请选择要构建的项目"
        echo -e "${CYAN}💡 提示: 可以输入多个编号，用空格分隔 (例如: 1 3 5)${NC}"
        echo -n "请输入项目编号: "

        local input
        read -r input

        if [[ -z "$input" ]]; then
            project_numbers=($(seq 1 ${#projects[@]}))
            log "INFO" "未输入项目编号，默认选择所有 ${#projects[@]} 个项目"
            break
        fi

        if project_numbers=($(validate_project_selection "$input" "${#projects[@]}")); then
            log "SUCCESS" "已选择 ${#project_numbers[@]} 个项目进行构建"
            break
        fi
    done

    # 获取日志偏好设置
    echo
    log "INFO" "配置构建选项"
    echo -e "${CYAN}💡 提示: 忽略日志可以加快构建速度，但出错时难以调试${NC}"
    echo -n "是否忽略构建日志? [Y/n] (默认: Y): "

    local ignore_logs_input
    read -r ignore_logs_input
    ignore_logs_input=$(echo "$ignore_logs_input" | tr '[:lower:]' '[:upper:]')

    if [[ -z "$ignore_logs_input" ]] || [[ "$ignore_logs_input" == "Y" ]]; then
        ignore_logs="Y"
        log "INFO" "构建日志将被忽略"
    else
        ignore_logs="N"
        log "INFO" "构建日志将显示在终端"
    fi

    # 将选择存储在全局变量中供其他函数使用
    SELECTED_PROJECT_NUMBERS=("${project_numbers[@]}")
    IGNORE_LOGS="$ignore_logs"
}

# =============================================================================
# 构建操作
# =============================================================================

# 拉取最新代码，具有增强的错误处理和日志记录
pull_latest_code() {
    local project_dir="$1"
    local temp_log
    temp_log=$(mktemp)

    log "PROGRESS" "拉取最新代码: $project_dir"

    # 检查是否有未提交的更改（仅用于提示，不阻塞构建）
    local status_output
    if status_output=$(git status --porcelain 2>/dev/null) && [[ -n "$status_output" ]]; then
        log "INFO" "项目 $project_dir 存在未提交的更改，但不影响构建"
    fi

    # 执行 git pull，使用 --autostash 自动处理未提交的更改
    local git_pull_cmd="git pull --autostash"

    if [[ "$IGNORE_LOGS" != "Y" ]]; then
        eval "$git_pull_cmd" 2>&1 | tee "$temp_log"
        local git_pull_exit_code=${PIPESTATUS[0]}
    else
        eval "$git_pull_cmd" > "$temp_log" 2>&1
        local git_pull_exit_code=$?
    fi

    # 检查拉取结果
    if [[ $git_pull_exit_code -eq 0 ]]; then
        # 检查是否有更新
        if grep -q "Already up to date\|已经是最新的" "$temp_log"; then
            log "INFO" "代码已是最新版本"
        else
            log "SUCCESS" "代码拉取成功"
        fi
    else
        log "ERROR" "Git pull 失败 (退出码: $git_pull_exit_code)"
        if [[ "$IGNORE_LOGS" == "Y" ]]; then
            echo "错误详情:"
            cat "$temp_log"
        fi
        rm -f "$temp_log"
        return 1
    fi

    rm -f "$temp_log"
    return 0
}

# 构建单个项目，具有全面的错误处理
build_single_project() {
    local project_dir="$1"
    local branch="$2"
    local temp_log
    temp_log=$(mktemp)

    # 项目信息已在上层显示，这里不再重复显示分隔符

    # 验证 Maven 项目
    if [[ ! -f "pom.xml" ]]; then
        log "ERROR" "项目 $project_dir 不是有效的 Maven 项目 (缺少 pom.xml)"
        rm -f "$temp_log"
        return 1
    fi

    # 检查磁盘空间（至少需要1GB可用空间）
    local available_space
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then  # 1GB转换为KB
        log "WARNING" "磁盘空间不足 (剩余: $(($available_space/1024))MB)，构建可能失败"
    fi

    log "PROGRESS" "开始构建项目: $project_dir"
    log "INFO" "Maven 参数: clean source:jar install $DEFAULT_MAVEN_OPTS"

    # 带超时的构建
    local mvn_pid
    local build_start_time
    build_start_time=$(date +%s)

    if [[ "$IGNORE_LOGS" != "Y" ]]; then
        mvn clean source:jar install $DEFAULT_MAVEN_OPTS 2>&1 | tee "$temp_log" &
        mvn_pid=$!
    else
        mvn clean source:jar install $DEFAULT_MAVEN_OPTS > "$temp_log" 2>&1 &
        mvn_pid=$!
    fi

    # 监控构建进度
    local dots=0
    local last_line=""
    while kill -0 $mvn_pid 2>/dev/null; do
        sleep 2
        dots=$(( (dots + 1) % 4 ))
        local progress_indicator
        case $dots in
            0) progress_indicator="🔄" ;;
            1) progress_indicator="🔃" ;;
            2) progress_indicator="🔄" ;;
            3) progress_indicator="🔃" ;;
        esac

        local elapsed=$(($(date +%s) - build_start_time))
        local elapsed_formatted
        elapsed_formatted=$(convert_time $elapsed)

        # 获取日志文件的最新一行
        if [[ -f "$temp_log" ]]; then
            local current_line
            current_line=$(tail -n 1 "$temp_log" 2>/dev/null | sed 's/\[INFO\] //g' | sed 's/\[WARNING\] //g' | sed 's/\[ERROR\] //g' | cut -c1-80)
            if [[ -n "$current_line" && "$current_line" != "$last_line" ]]; then
                last_line="$current_line"
            fi
        fi

        # 显示进度和最新日志行
        if [[ -n "$last_line" ]]; then
            echo -ne "\r${PURPLE}$progress_indicator 构建中 ($elapsed_formatted) ${CYAN}$last_line${NC}"
        else
            echo -ne "\r${PURPLE}$progress_indicator 构建进行中... (已用时: $elapsed_formatted)${NC}"
        fi

        # 检查是否超时
        if [[ $elapsed -gt $BUILD_TIMEOUT ]]; then
            echo  # 换行
            log "ERROR" "构建超时 (${BUILD_TIMEOUT}秒)"
            kill $mvn_pid 2>/dev/null || true
            rm -f "$temp_log"
            return 1
        fi
    done
    echo  # 进度指示器后换行

    # 检查构建结果
    wait $mvn_pid
    local mvn_exit_code=$?
    local build_end_time
    build_end_time=$(date +%s)
    local total_time=$((build_end_time - build_start_time))
    local total_time_formatted
    total_time_formatted=$(convert_time $total_time)

    if [[ $mvn_exit_code -eq 0 ]]; then
        log "SUCCESS" "构建成功 (耗时: $total_time_formatted)"
    else
        log "ERROR" "构建失败 (耗时: $total_time_formatted, 退出码: $mvn_exit_code)"
        if [[ "$IGNORE_LOGS" == "Y" ]]; then
            echo "错误详情:"
            tail -50 "$temp_log"
        fi
        rm -f "$temp_log"
        return 1
    fi

    rm -f "$temp_log"
    return 0
}

# 构建多个项目，具有全面的错误处理和报告功能
build_selected_projects() {
    local projects=("$@")
    local project_numbers=("${SELECTED_PROJECT_NUMBERS[@]}")
    local branches
    IFS=$'\n' read -d '' -r -a branches < <(get_project_branches "${projects[@]}" && printf '\0')

    local total_projects=${#project_numbers[@]}
    local successful_builds=()
    local failed_builds=()
    local skipped_builds=()
    local overall_start_time
    overall_start_time=$(date +%s)

    print_section "开始批量构建 ($total_projects 个项目)"

    # 构建每个选定的项目
    for i in "${!project_numbers[@]}"; do
        local number="${project_numbers[$i]}"
        local project_index=$((number - 1))
        local selected_project="${projects[$project_index]}"
        local branch="${branches[$project_index]}"
        local current_project=$((i + 1))

        log "INFO" "进度: [$current_project/$total_projects] 处理项目: $selected_project"

        # 跳过分支信息未知的项目
        if [[ "$branch" == "unknown" ]]; then
            log "WARNING" "跳过项目 $selected_project (无法获取分支信息)"
            skipped_builds+=("$selected_project")
            continue
        fi

        # 切换到项目目录
        local original_dir
        original_dir=$(pwd)
        if ! cd "$selected_project" 2>/dev/null; then
            log "ERROR" "无法进入项目目录: $selected_project"
            failed_builds+=("$selected_project")
            continue
        fi

        # 开始项目处理（拉取代码 + 构建）
        print_section "处理项目: $selected_project ($branch)"

        # 拉取最新代码
        if execute_with_timing "拉取代码" pull_latest_code "$selected_project"; then
            # 构建项目
            if execute_with_timing "构建项目" build_single_project "$selected_project" "$branch"; then
                successful_builds+=("$selected_project")
                log "SUCCESS" "项目 $selected_project 处理完成"
            else
                failed_builds+=("$selected_project")
                log "ERROR" "项目 $selected_project 构建失败"
            fi
        else
            failed_builds+=("$selected_project")
            log "ERROR" "项目 $selected_project 代码拉取失败"
        fi

        # 返回原始目录
        cd "$original_dir" || {
            log "ERROR" "无法返回原始目录: $original_dir"
            exit 1
        }

        # 在项目之间添加分隔符（除了最后一个）
        if [[ $current_project -lt $total_projects ]]; then
            print_separator "-" 50
            echo
        fi
    done

    # 计算总时间
    local overall_end_time
    overall_end_time=$(date +%s)
    local total_time=$((overall_end_time - overall_start_time))
    local total_time_formatted
    total_time_formatted=$(convert_time $total_time)

    # 显示构建摘要
    display_build_summary "$total_time_formatted" "${#successful_builds[@]}" "${#failed_builds[@]}" "${#skipped_builds[@]}" "${successful_builds[@]:-}" "${failed_builds[@]:-}" "${skipped_builds[@]:-}"

    # 返回适当的退出码
    if [[ ${#failed_builds[@]} -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# 显示全面的构建摘要
display_build_summary() {
    local total_time="$1"
    local successful_count="$2"
    local failed_count="$3"
    local skipped_count="$4"
    shift 4

    # 解析项目名称
    local successful_builds=()
    local failed_builds=()
    local skipped_builds=()

    # 读取成功的项目
    for ((i=0; i<successful_count; i++)); do
        if [[ -n "$1" ]]; then
            successful_builds+=("$1")
            shift
        fi
    done

    # 读取失败的项目
    for ((i=0; i<failed_count; i++)); do
        if [[ -n "$1" ]]; then
            failed_builds+=("$1")
            shift
        fi
    done

    # 读取跳过的项目
    for ((i=0; i<skipped_count; i++)); do
        if [[ -n "$1" ]]; then
            skipped_builds+=("$1")
            shift
        fi
    done

    print_section "构建总结报告"

    # 总体统计
    local total_attempted=$((${#successful_builds[@]} + ${#failed_builds[@]}))
    local success_rate=0
    if [[ $total_attempted -gt 0 ]]; then
        success_rate=$(( (${#successful_builds[@]} * 100) / total_attempted ))
    fi

    echo -e "${BOLD}📊 构建统计:${NC}"
    echo -e "   总耗时: ${CYAN}$total_time${NC}"
    echo -e "   成功: ${GREEN}${#successful_builds[@]}${NC}"
    echo -e "   失败: ${RED}${#failed_builds[@]}${NC}"
    echo -e "   跳过: ${YELLOW}${#skipped_builds[@]}${NC}"
    echo -e "   成功率: ${CYAN}${success_rate}%${NC}"
    echo

    # 成功构建的项目
    if [[ ${#successful_builds[@]} -gt 0 ]]; then
        echo -e "${GREEN}✅ 构建成功的项目:${NC}"
        for project in "${successful_builds[@]}"; do
            echo -e "   ${GREEN}• $project${NC}"
        done
        echo
    fi

    # 失败构建的项目
    if [[ ${#failed_builds[@]} -gt 0 ]]; then
        echo -e "${RED}❌ 构建失败的项目:${NC}"
        for project in "${failed_builds[@]}"; do
            echo -e "   ${RED}• $project${NC}"
        done
        echo
    fi

    # 跳过的项目
    if [[ ${#skipped_builds[@]} -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  跳过的项目:${NC}"
        for project in "${skipped_builds[@]}"; do
            echo -e "   ${YELLOW}• $project${NC}"
        done
        echo
    fi

    # 最终状态
    if [[ ${#failed_builds[@]} -eq 0 ]]; then
        log "SUCCESS" "所有项目构建完成！"
    else
        log "ERROR" "部分项目构建失败，请检查错误信息"
    fi
}

# =============================================================================
# 帮助和使用说明
# =============================================================================

# 显示帮助信息
show_help() {
    echo -e "${BOLD}项目构建脚本 - 增强版本 2.0${NC}"
    echo
    echo -e "${BOLD}描述:${NC}"
    echo "    自动化构建工具，用于批量构建项目。支持项目发现、代码拉取、"
    echo "    Maven 构建，并提供详细的构建报告和错误处理。"
    echo
    echo -e "${BOLD}用法:${NC}"
    echo "    $SCRIPT_NAME [选项] [查询条件]"
    echo
    echo -e "${BOLD}选项:${NC}"
    echo "    -h, --help          显示此帮助信息"
    echo "    -v, --version       显示版本信息"
    echo "    -d, --debug         启用调试模式"
    echo "    --dry-run          预览模式，不执行实际构建"
    echo "    --no-pull          跳过代码拉取步骤"
    echo "    --timeout SECONDS   设置构建超时时间 (默认: $BUILD_TIMEOUT 秒)"
    echo
    echo -e "${BOLD}参数:${NC}"
    echo "    查询条件            可选的项目名称过滤条件 (支持正则表达式)"
    echo
    echo -e "${BOLD}示例:${NC}"
    echo "    $SCRIPT_NAME                    # 交互式选择项目构建"
    echo "    $SCRIPT_NAME project-core          # 只显示包含 'project-core' 的项目"
    echo "    $SCRIPT_NAME --debug           # 启用调试模式"
    echo "    $SCRIPT_NAME --dry-run         # 预览将要构建的项目"
    echo "    $SCRIPT_NAME --timeout 3600    # 设置1小时构建超时"
    echo
    echo -e "${BOLD}环境要求:${NC}"
    echo "    - Git (用于代码管理)"
    echo "    - Maven (用于项目构建)"
    echo "    - 当前目录包含 Git Maven 项目"
    echo
    echo -e "${BOLD}特性:${NC}"
    echo -e "    ${GREEN}✅ 自动发现 Git Maven 项目${NC}"
    echo -e "    ${GREEN}✅ 智能项目排序 (常用项目优先)${NC}"
    echo -e "    ${GREEN}✅ 彩色输出和进度指示${NC}"
    echo -e "    ${GREEN}✅ 详细的构建报告${NC}"
    echo -e "    ${GREEN}✅ 错误处理和恢复${NC}"
    echo -e "    ${GREEN}✅ 构建超时保护${NC}"
    echo -e "    ${GREEN}✅ 自动处理未提交更改 (--autostash)${NC}"
    echo -e "    ${GREEN}✅ 实时构建进度显示${NC}"
    echo
    echo -e "${BOLD}作者:${NC} Augment Agent 增强版"
    echo -e "${BOLD}版本:${NC} 2.0"
}

# 显示版本信息
show_version() {
    echo -e "${BOLD}项目构建脚本 v2.0${NC}"
    echo -e "${BOLD}作者:${NC} Augment Agent 增强版"
    echo -e "${BOLD}兼容系统:${NC} macOS/Linux"
}

# =============================================================================
# 主函数
# =============================================================================

# 具有增强参数解析和错误处理的主函数
main() {
    local query=""
    local dry_run=false
    local no_pull=false
    local custom_timeout=""

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            -u|--update)
                # 手动触发更新检查
                if [[ -n "${GITLAB_TOKEN:-}" ]]; then
                    local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
                    if [[ -f "$sv_script" ]]; then
                        # 使用子shell避免变量冲突
                        if (source "$sv_script" && check_script_update "mb.sh") 2>/dev/null; then
                            exit 0
                        else
                            log "ERROR" "更新检查失败"
                            exit 1
                        fi
                    else
                        log "ERROR" "更新脚本不存在: $sv_script"
                        exit 1
                    fi
                else
                    log "WARNING" "未设置 GITLAB_TOKEN 环境变量，无法检查更新"
                    log "INFO" "请先使用 sv.sh -c 进行配置或运行 br.sh 脚本"
                    exit 1
                fi
                ;;
            -d|--debug)
                export DEBUG=true
                log "INFO" "调试模式已启用"
                shift
                ;;
            --dry-run)
                dry_run=true
                log "INFO" "预览模式已启用"
                shift
                ;;
            --no-pull)
                no_pull=true
                log "INFO" "将跳过代码拉取步骤"
                shift
                ;;
            --timeout)
                if [[ -n "$2" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    custom_timeout="$2"
                    shift 2
                else
                    log "ERROR" "--timeout 需要一个数字参数"
                    exit 1
                fi
                ;;
            -*)
                log "ERROR" "未知选项: $1"
                echo "使用 $SCRIPT_NAME --help 查看帮助信息"
                exit 1
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done

    # 如果提供了自定义超时时间则设置
    if [[ -n "$custom_timeout" ]]; then
        readonly BUILD_TIMEOUT="$custom_timeout"
        log "INFO" "构建超时设置为: ${BUILD_TIMEOUT}秒"
    fi

    # 自动更新检查（如果有Token的话）
    if [[ -n "${GITLAB_TOKEN:-}" ]]; then
        local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
        if [[ -f "$sv_script" ]]; then
            # 使用子shell避免变量冲突
            (source "$sv_script" && check_script_update "mb.sh") 2>/dev/null || true
        fi
    fi

    # 显示脚本标题
    print_section "MB - Maven Batch (项目批量构建工具)"
    log "INFO" "开始执行构建脚本"
    log "INFO" "工作目录: $(pwd)"

    # 验证环境
    validate_environment

    # 发现项目
    log "INFO" "搜索 Git Maven 项目..."
    local projects
    if ! projects=($(discover_git_projects)); then
        log "ERROR" "当前目录下未找到任何有效的 Git Maven 项目"
        exit 1
    fi
    log "SUCCESS" "发现 ${#projects[@]} 个 Git Maven 项目"

    # 根据查询条件过滤项目
    if [[ -n "$query" ]]; then
        log "INFO" "应用过滤条件: $query"
        local filtered_projects=()
        for proj in "${projects[@]}"; do
            if [[ "$proj" =~ $query ]]; then
                filtered_projects+=("$proj")
            fi
        done

        if [[ ${#filtered_projects[@]} -eq 0 ]]; then
            log "ERROR" "没有项目匹配过滤条件: $query"
            exit 1
        fi

        projects=("${filtered_projects[@]}")
        log "SUCCESS" "找到 ${#projects[@]} 个匹配的项目"
    fi

    # 获取用户选择
    get_user_selection "${projects[@]}"

    # 预览模式
    if [[ "$dry_run" == true ]]; then
        print_section "预览模式 - 将要构建的项目"
        for number in "${SELECTED_PROJECT_NUMBERS[@]}"; do
            local project_index=$((number - 1))
            echo -e "${CYAN}• ${projects[$project_index]}${NC}"
        done
        log "INFO" "预览完成，退出 (使用 --dry-run 模式)"
        exit 0
    fi

    # 执行构建
    local build_start_time
    build_start_time=$(date "+%Y-%m-%d %H:%M:%S")
    log "INFO" "构建开始时间: $build_start_time"

    if build_selected_projects "${projects[@]}"; then
        local build_end_time
        build_end_time=$(date "+%Y-%m-%d %H:%M:%S")
        log "SUCCESS" "所有构建任务完成"
        log "INFO" "构建结束时间: $build_end_time"
        exit 0
    else
        local build_end_time
        build_end_time=$(date "+%Y-%m-%d %H:%M:%S")
        log "ERROR" "部分构建任务失败"
        log "INFO" "构建结束时间: $build_end_time"
        exit 1
    fi
}

# =============================================================================
# 脚本执行
# =============================================================================

# 捕获信号进行清理
trap 'log "WARNING" "脚本被中断"; exit 130' INT TERM

# 使用所有参数执行主函数
main "$@"

