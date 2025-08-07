#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.3"

# 设置字符编码环境，避免sort命令出现"Illegal byte sequence"错误
export LC_ALL=C
export LANG=C

#######################################
#            配置区域                   #
#######################################

# 分支分类配置
FEATURE_PREFIXES=("feature/" "hotfix/" "bugfix/")
ENVIRONMENT_PREFIXES=("gray" "release" "vip")
MERGE_PREFIX="merge/"
MAIN_BRANCHES=("main" "master" "develop")

# 清理策略配置（天数）
DEFAULT_CLEANUP_DAYS=90  # 默认清理阈值

#######################################
#            颜色和图标配置              #
#######################################

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m'

# Emoji 定义
readonly EMOJI_SUCCESS="✅"
readonly EMOJI_ERROR="❌"
readonly EMOJI_WARNING="⚠️"
readonly EMOJI_INFO="ℹ️"
readonly EMOJI_ROCKET="🚀"
readonly EMOJI_BRANCH="🌿"
readonly EMOJI_CLOCK="🕐"
readonly EMOJI_STATS="📊"
readonly EMOJI_CLEAN="🧹"
readonly EMOJI_TRASH="🗑️"
readonly EMOJI_KEEP="💾"
readonly EMOJI_SEARCH="🔍"

#######################################
#            核心函数                   #
#######################################

# 检查当前目录是否为git仓库
check_git_repository() {
    if [ ! -d ".git" ]; then
        echo -e "${RED}${EMOJI_ERROR} 错误: 当前目录不是git项目!${NC}"
        echo -e "${GRAY}请在git项目的根目录下运行此脚本。${NC}"
        exit 1
    fi
    echo -e "${GREEN}${EMOJI_SUCCESS} 检测到当前目录是git项目${NC}"
}

# 更新远程仓库信息
fetch_remote_info() {
    echo -e "${BLUE}${EMOJI_SEARCH} 正在获取远程分支信息...${NC}"
    git fetch --all --prune >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}${EMOJI_ERROR} 获取远程信息失败!${NC}"
        exit 1
    fi
    echo -e "${GREEN}${EMOJI_SUCCESS} 远程分支信息获取完成${NC}"
}

# 获取所有本地分支
get_all_local_branches() {
    git branch --format='%(refname:short)' | grep -v '^HEAD$'
}

# 获取所有远程分支（去掉origin/前缀）
get_all_remote_branches() {
    git branch -r --format='%(refname:short)' | grep -v '^origin/HEAD$' | sed 's/^origin\///'
}

# 获取本地环境分支
get_local_environment_branches() {
    local local_branches=$(get_all_local_branches)

    # 过滤出符合规范的本地环境分支
    local env_branches=""

    for branch in $local_branches; do
        # Gray分支: gray[1-6]/yyMMdd
        if [[ "$branch" =~ ^gray[1-6]/[0-9]{6}$ ]]; then
            env_branches="$env_branches $branch"
        # Release正式分支: release/x.xxx.x
        elif [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            env_branches="$env_branches $branch"
        # Release预发分支: release/x.xxx.preissue_yyMMdd 或 release/x.xxx.preissue2_yyMMdd
        elif [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.preissue2?_[0-9]{6}$ ]]; then
            env_branches="$env_branches $branch"
        # VIP分支: vip/yyMMdd
        elif [[ "$branch" =~ ^vip/[0-9]{6}$ ]]; then
            env_branches="$env_branches $branch"
        fi
    done

    echo "$env_branches" | tr ' ' '\n' | grep -v '^$' | sort
}

# 获取环境分支（包括本地和远程，用于feature分支合并检查）
get_environment_branches() {
    local local_branches=$(get_all_local_branches)
    local remote_branches=$(get_all_remote_branches)

    # 合并本地和远程分支，去重
    local all_branches=$(echo -e "$local_branches\n$remote_branches" | sort -u)

    # 过滤出符合规范的环境分支
    local env_branches=""

    for branch in $all_branches; do
        # Gray分支: gray[1-6]/yyMMdd
        if [[ "$branch" =~ ^gray[1-6]/[0-9]{6}$ ]]; then
            env_branches="$env_branches $branch"
        # Release正式分支: release/x.xxx.x
        elif [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            env_branches="$env_branches $branch"
        # Release预发分支: release/x.xxx.preissue_yyMMdd 或 release/x.xxx.preissue2_yyMMdd
        elif [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.preissue2?_[0-9]{6}$ ]]; then
            env_branches="$env_branches $branch"
        # VIP分支: vip/yyMMdd
        elif [[ "$branch" =~ ^vip/[0-9]{6}$ ]]; then
            env_branches="$env_branches $branch"
        fi
    done

    echo "$env_branches" | tr ' ' '\n' | grep -v '^$' | sort
}

# 计算时间差（返回人类可读格式）
get_time_ago() {
    local commit_time="$1"

    if [ -z "$commit_time" ]; then
        echo "未知时间"
        return
    fi

    local current_time=$(date +%s)
    local commit_timestamp

    # macOS 系统使用不同的 date 命令格式
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 系统，直接使用 date -j 解析 ISO 格式
        commit_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$commit_time" +%s 2>/dev/null || echo "0")
        if [ "$commit_timestamp" -eq 0 ]; then
            # 尝试不带时区的格式
            local time_without_tz=$(echo "$commit_time" | cut -d' ' -f1,2)
            commit_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$time_without_tz" +%s 2>/dev/null || echo "0")
        fi
    else
        # Linux 系统
        commit_timestamp=$(date -d "$commit_time" +%s 2>/dev/null || echo "0")
    fi

    if [ "$commit_timestamp" -eq 0 ]; then
        echo "未知时间"
        return
    fi

    local diff=$((current_time - commit_timestamp))
    local days=$((diff / 86400))
    local hours=$(((diff % 86400) / 3600))
    local minutes=$(((diff % 3600) / 60))

    # 构建更详细的时间描述
    local time_parts=""

    if [ $days -gt 365 ]; then
        local years=$((days / 365))
        local remaining_days=$((days % 365))
        if [ $remaining_days -gt 30 ]; then
            local months=$((remaining_days / 30))
            remaining_days=$((remaining_days % 30))
            if [ $remaining_days -gt 0 ]; then
                time_parts="${years}年${months}个月${remaining_days}天前"
            else
                time_parts="${years}年${months}个月前"
            fi
        elif [ $remaining_days -gt 0 ]; then
            time_parts="${years}年${remaining_days}天前"
        else
            time_parts="${years}年前"
        fi
    elif [ $days -gt 30 ]; then
        local months=$((days / 30))
        local remaining_days=$((days % 30))
        if [ $remaining_days -gt 0 ]; then
            time_parts="${months}个月${remaining_days}天前"
        else
            time_parts="${months}个月前"
        fi
    elif [ $days -gt 0 ]; then
        if [ $hours -gt 0 ]; then
            time_parts="${days}天${hours}小时前"
        else
            time_parts="${days}天前"
        fi
    elif [ $hours -gt 0 ]; then
        if [ $minutes -gt 0 ]; then
            time_parts="${hours}小时${minutes}分钟前"
        else
            time_parts="${hours}小时前"
        fi
    else
        time_parts="${minutes}分钟前"
    fi

    echo "$time_parts"
}

# 获取分支最后提交时间
get_branch_last_commit_time() {
    local branch="$1"
    local commit_time=$(git log -1 --format="%ci" "$branch" 2>/dev/null)
    if [ -n "$commit_time" ]; then
        echo "$commit_time" | cut -d' ' -f1,2 | cut -d'+' -f1
    else
        echo ""
    fi
}

# 获取分支最后提交信息（hash + message + time）
get_branch_last_commit_info() {
    local branch="$1"
    local commit_info=$(git log -1 --format="%h|%s|%ci" "$branch" 2>/dev/null)
    if [ -n "$commit_info" ]; then
        echo "$commit_info"
    else
        echo "||"
    fi
}

# 获取分支最后提交的天数差
get_branch_age_days() {
    local branch="$1"
    local commit_time=$(get_branch_last_commit_time "$branch")

    if [ -z "$commit_time" ]; then
        echo "999999"  # 返回一个很大的数字表示未知
        return
    fi

    local current_time=$(date +%s)
    local commit_timestamp

    # macOS 系统使用不同的 date 命令格式
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 系统，直接使用 date -j 解析 ISO 格式
        commit_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$commit_time" +%s 2>/dev/null || echo "0")
        if [ "$commit_timestamp" -eq 0 ]; then
            # 尝试不带时区的格式
            local time_without_tz=$(echo "$commit_time" | cut -d' ' -f1,2)
            commit_timestamp=$(date -j -f "%Y-%m-%d %H:%M:%S" "$time_without_tz" +%s 2>/dev/null || echo "0")
        fi
    else
        # Linux 系统
        commit_timestamp=$(date -d "$commit_time" +%s 2>/dev/null || echo "0")
    fi

    if [ "$commit_timestamp" -eq 0 ]; then
        echo "999999"
        return
    fi

    local diff=$((current_time - commit_timestamp))
    echo $((diff / 86400))
}

# 检查分支类型
get_branch_type() {
    local branch="$1"
    
    # 检查是否是主分支
    for main_branch in "${MAIN_BRANCHES[@]}"; do
        if [ "$branch" == "$main_branch" ]; then
            echo "main"
            return
        fi
    done
    
    # 检查是否是merge分支
    if [[ "$branch" =~ ^${MERGE_PREFIX} ]]; then
        echo "merge"
        return
    fi
    
    # 检查是否是环境分支
    for prefix in "${ENVIRONMENT_PREFIXES[@]}"; do
        if [[ "$branch" =~ ^${prefix} ]]; then
            echo "environment"
            return
        fi
    done
    
    # 检查是否是feature分支
    for prefix in "${FEATURE_PREFIXES[@]}"; do
        if [[ "$branch" =~ ^${prefix} ]]; then
            echo "feature"
            return
        fi
    done
    
    # 其他分支按feature处理
    echo "feature"
}

# 检查分支是否只存在于本地（没有远程分支）
is_local_only_branch() {
    local branch="$1"

    # 检查远程分支是否存在
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        return 1  # 远程分支存在
    else
        return 0  # 只有本地分支
    fi
}

# 获取环境分支的最新版本
get_latest_environment_branches() {
    local branches="$1"
    local result=""
    local temp_file="/tmp/bc_branches_$$"

    # 创建临时文件存储分支信息
    > "$temp_file"

    for branch in $branches; do
        # Gray分支处理: gray[1-6]/yyMMdd
        if [[ "$branch" =~ ^gray[1-6]/[0-9]{6}$ ]]; then
            local gray_num=$(echo "$branch" | cut -d'/' -f1)
            local date_suffix=$(echo "$branch" | cut -d'/' -f2)
            echo "gray|${gray_num}|${date_suffix}|${branch}" >> "$temp_file"
        # Release正式分支: release/x.xxx.x
        elif [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            local version=$(echo "$branch" | cut -d'/' -f2)
            echo "release_formal|${version}|${version}|${branch}" >> "$temp_file"
        # Release预发分支: release/x.xxx.preissue_yyMMdd 或 release/x.xxx.preissue2_yyMMdd
        elif [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.preissue2?_[0-9]{6}$ ]]; then
            local date_suffix=$(echo "$branch" | sed 's/.*_//')
            echo "release_preissue|${date_suffix}|${date_suffix}|${branch}" >> "$temp_file"
        # VIP分支: vip/yyMMdd
        elif [[ "$branch" =~ ^vip/[0-9]{6}$ ]]; then
            local date_suffix=$(echo "$branch" | cut -d'/' -f2)
            echo "vip|${date_suffix}|${date_suffix}|${branch}" >> "$temp_file"
        fi
    done

    # 处理每个分组，找出最新的分支
    # Gray分支按gray1-gray6分组
    for i in {1..6}; do
        local latest_branch=$(grep "^gray|gray${i}|" "$temp_file" | sort -t'|' -k3,3nr | head -1 | cut -d'|' -f4)
        if [ -n "$latest_branch" ]; then
            result="$result $latest_branch"
        fi
    done

    # Release正式分支取最新版本
    local latest_release=$(grep "^release_formal|" "$temp_file" | sort -t'|' -k3,3V | tail -1 | cut -d'|' -f4)
    if [ -n "$latest_release" ]; then
        result="$result $latest_release"
    fi

    # Release预发分支取最新日期
    local latest_preissue=$(grep "^release_preissue|" "$temp_file" | sort -t'|' -k3,3nr | head -1 | cut -d'|' -f4)
    if [ -n "$latest_preissue" ]; then
        result="$result $latest_preissue"
    fi

    # VIP分支取最新日期
    local latest_vip=$(grep "^vip|" "$temp_file" | sort -t'|' -k3,3nr | head -1 | cut -d'|' -f4)
    if [ -n "$latest_vip" ]; then
        result="$result $latest_vip"
    fi

    # 清理临时文件
    rm -f "$temp_file"

    echo "$result" | tr ' ' '\n' | grep -v '^$' | sort
}

# 检查提交是否已合并到目标分支
check_commit_merged() {
    local source_branch="$1"
    local target_branch="$2"

    # 获取源分支的最后一个提交
    local last_commit=$(git rev-parse "$source_branch" 2>/dev/null)
    if [ -z "$last_commit" ]; then
        return 1
    fi

    # 尝试检查本地分支
    if git show-ref --verify --quiet "refs/heads/$target_branch"; then
        git merge-base --is-ancestor "$last_commit" "$target_branch" 2>/dev/null
        return $?
    fi

    # 如果本地分支不存在，检查远程分支
    if git show-ref --verify --quiet "refs/remotes/origin/$target_branch"; then
        git merge-base --is-ancestor "$last_commit" "origin/$target_branch" 2>/dev/null
        return $?
    fi

    return 1
}

# 显示帮助信息
show_help() {
    echo -e "${WHITE}${EMOJI_CLEAN} BC - Branch Clean (Git分支清理工具)${NC}"
    echo ""
    echo -e "${YELLOW}用法:${NC}"
    echo "  $0 [选项]"
    echo ""
    echo -e "${YELLOW}选项:${NC}"
    echo "  -h, --help              显示此帮助信息"
    echo "  -d, --days <天数>       设置分支清理天数阈值 (默认: ${DEFAULT_CLEANUP_DAYS}天)"
    echo "  -b, --branch <关键词>   只分析包含指定关键词的分支"
    echo "  --dry-run              只分析不删除，预览清理结果"
    echo "  --force                跳过确认提示，直接执行删除"
    echo ""
    echo -e "${YELLOW}执行模式:${NC}"
    echo -e "  • ${GREEN}默认模式${NC}: 分析分支 → 列出可删除分支 → 询问确认 → 执行删除"
    echo -e "  • ${BLUE}预览模式${NC}: 只分析分支状态，不执行删除 (--dry-run)"
    echo -e "  • ${RED}强制模式${NC}: 分析后直接删除，跳过确认 (--force)"
    echo ""
    echo -e "${YELLOW}分支处理策略:${NC}"
    echo -e "  • ${GREEN}Feature/Merge分支${NC}: 本地和远程都清理"
    echo -e "  • ${BLUE}环境分支${NC}: 只清理本地分支"
    echo -e "  • ${CYAN}主分支${NC}: 永不清理"
    echo ""
    echo -e "${YELLOW}环境分支颜色说明:${NC}"
    echo -e "  • ${GRAY}Gray环境${NC}: 灰度测试环境"
    echo -e "  • ${GREEN}预发/VIP环境${NC}: 预发布环境"
    echo -e "  • ${RED}生产环境${NC}: 正式生产环境"
    echo -e "  • ${CYAN}主分支${NC}: 主开发分支"
    echo ""
    echo -e "${YELLOW}示例:${NC}"
    echo "  $0                      # 默认模式：分析并询问是否删除"
    echo "  $0 -b 253032           # 只处理包含253032的分支"
    echo "  $0 -d 30               # 设置30天阈值"
    echo "  $0 --dry-run           # 只分析不删除"
    echo "  $0 --force             # 分析后直接删除"
    echo ""
}

# 分析feature分支
analyze_feature_branch() {
    local branch="$1"
    local cleanup_days="$2"

    # 获取详细的提交信息
    local commit_info=$(get_branch_last_commit_info "$branch")
    local commit_hash=$(echo "$commit_info" | cut -d'|' -f1)
    local commit_msg=$(echo "$commit_info" | cut -d'|' -f2)
    local commit_time=$(echo "$commit_info" | cut -d'|' -f3 | cut -d' ' -f1,2 | cut -d'+' -f1)
    local time_ago=$(get_time_ago "$commit_time")
    local age_days=$(get_branch_age_days "$branch")

    # 检查是否只有本地分支
    local branch_label="$branch"
    local is_local_only=false
    if is_local_only_branch "$branch"; then
        branch_label="$branch ${YELLOW}(仅本地)${NC}"
        is_local_only=true
    fi

    echo -e "\n${CYAN}${EMOJI_BRANCH} 分支: ${WHITE}$branch_label${NC} ${GRAY}(feature)${NC}"
    echo -e "  ${GRAY}${EMOJI_CLOCK} 最后提交: ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"

    # 获取目标环境分支进行合并检查（包括远程分支）
    local env_branches=$(get_environment_branches)
    local all_local_branches=$(get_all_local_branches)
    local main_branches=$(echo "$all_local_branches" | grep -E "^(main|master|develop)$")

    # 获取最新的环境分支
    local latest_env_branches=$(get_latest_environment_branches "$env_branches")

    # 按指定顺序排序目标分支：main → gray1-6 → 预发1 → 预发2 → vip → 生产
    local sorted_targets=$(sort_target_branches "$latest_env_branches $main_branches")

    local merged_to=""
    local gray_merged=false
    local release_merged=false
    local production_merged=false

    # 检查合并状态
    for target in $sorted_targets; do
        if [ -n "$target" ] && check_commit_merged "$branch" "$target"; then
            merged_to="$merged_to $target"
            if [[ "$target" =~ ^gray ]]; then
                gray_merged=true
            fi
            if [[ "$target" =~ ^release ]]; then
                release_merged=true
                # 检查是否是生产分支（正式版本）
                if [[ "$target" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    production_merged=true
                fi
            fi
        fi
    done

    # 如果本地没有找到合并信息，额外检查远程主分支
    if [ -z "$merged_to" ]; then
        for main_branch in "main" "master" "develop"; do
            if git show-ref --verify --quiet "refs/remotes/origin/$main_branch"; then
                if check_commit_merged "$branch" "$main_branch"; then
                    merged_to="$merged_to origin/$main_branch"
                fi
            fi
        done
    fi

    # 显示合并状态（无论是否符合阈值）- 使用颜色化显示
    if [ -n "$merged_to" ]; then
        local colored_merged=""
        for target in $merged_to; do
            colored_merged="$colored_merged $(colorize_branch "$target")"
        done
        echo -e "  ${GREEN}${EMOJI_SUCCESS} 已合并到:${NC}$colored_merged"
    else
        echo -e "  ${RED}${EMOJI_WARNING} 未合并到任何目标分支${NC}"
    fi

    # 判断是否可以清理
    local can_cleanup=false
    local cleanup_reason=""

    if [ -n "$merged_to" ]; then
        # 如果已合并到生产环境，无视时间阈值直接清理
        if [ "$production_merged" = true ]; then
            can_cleanup=true
            cleanup_reason="已合并到生产环境"
            echo -e "  ${RED}${EMOJI_ROCKET} 已合并到生产环境，无视时间阈值${NC}"
        # 如果同时合并到gray和release分支，且超过阈值
        elif [ "$gray_merged" = true ] && [ "$release_merged" = true ]; then
            if [ "$age_days" -gt "$cleanup_days" ]; then
                can_cleanup=true
                cleanup_reason="已同时合并到gray和release分支且超过${cleanup_days}天"
                echo -e "  ${YELLOW}${EMOJI_WARNING} 分支已超过 ${cleanup_days} 天${NC}"
            else
                echo -e "  ${YELLOW}${EMOJI_KEEP} 建议: 暂时保留 (已合并但分支较新)${NC}"
                return 1
            fi
        else
            if [ "$age_days" -gt "$cleanup_days" ]; then
                echo -e "  ${YELLOW}${EMOJI_WARNING} 分支已超过 ${cleanup_days} 天${NC}"
                echo -e "  ${YELLOW}${EMOJI_KEEP} 建议: 暂时保留 (未完全合并)${NC}"
            else
                echo -e "  ${YELLOW}${EMOJI_KEEP} 建议: 暂时保留 (未完全合并且分支较新)${NC}"
            fi
            return 1
        fi
    else
        if [ "$age_days" -gt "$cleanup_days" ]; then
            echo -e "  ${YELLOW}${EMOJI_WARNING} 分支已超过 ${cleanup_days} 天${NC}"
            echo -e "  ${YELLOW}${EMOJI_KEEP} 建议: 暂时保留 (需要人工确认)${NC}"
        else
            echo -e "  ${GREEN}${EMOJI_KEEP} 建议: 保留 (分支较新且未合并)${NC}"
        fi
        return 1
    fi

    # 如果可以清理
    if [ "$can_cleanup" = true ]; then
        echo -e "  ${GREEN}${EMOJI_TRASH} 建议: 可以清理 ($cleanup_reason)${NC}"
        # 返回删除建议：分支名|类型|是否仅本地|删除理由
        echo "DELETABLE:$branch|feature|$is_local_only|$cleanup_reason" >&3
        return 0
    fi

    return 1
}

# 按指定顺序排序目标分支：main → gray1-6 → 预发1 → 预发2 → vip → 生产
sort_target_branches() {
    local branches="$1"
    local result=""

    # 1. 主分支 (main, master, develop)
    for branch in $branches; do
        if [[ "$branch" =~ ^(main|master|develop)$ ]]; then
            result="$result $branch"
        fi
    done

    # 2. Gray分支 (gray1-gray6)
    for i in {1..6}; do
        for branch in $branches; do
            if [[ "$branch" =~ ^gray${i}/ ]]; then
                result="$result $branch"
                break
            fi
        done
    done

    # 3. Release预发分支1 (preissue_)
    for branch in $branches; do
        if [[ "$branch" =~ ^release/.*\.preissue_[0-9]{6}$ ]]; then
            result="$result $branch"
        fi
    done

    # 4. Release预发分支2 (preissue2_)
    for branch in $branches; do
        if [[ "$branch" =~ ^release/.*\.preissue2_[0-9]{6}$ ]]; then
            result="$result $branch"
        fi
    done

    # 5. VIP分支
    for branch in $branches; do
        if [[ "$branch" =~ ^vip/ ]]; then
            result="$result $branch"
        fi
    done

    # 6. Release正式分支 (生产)
    for branch in $branches; do
        if [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            result="$result $branch"
        fi
    done

    echo "$result" | tr ' ' '\n' | grep -v '^$'
}

# 为分支添加颜色标识
colorize_branch() {
    local branch="$1"

    # Gray环境 - 灰色
    if [[ "$branch" =~ ^gray[1-6]/ ]]; then
        echo -e "${GRAY}${branch}${NC}"
    # 预发环境 - 绿色
    elif [[ "$branch" =~ ^release/.*\.preissue ]]; then
        echo -e "${GREEN}${branch}${NC}"
    # VIP环境 - 绿色
    elif [[ "$branch" =~ ^vip/ ]]; then
        echo -e "${GREEN}${branch}${NC}"
    # 生产环境 - 红色
    elif [[ "$branch" =~ ^release/[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}${branch}${NC}"
    # 主分支 - 青色
    elif [[ "$branch" =~ ^(main|master|develop)$ ]]; then
        echo -e "${CYAN}${branch}${NC}"
    # 其他分支 - 默认颜色
    else
        echo "$branch"
    fi
}

#######################################
#            清理功能                   #
#######################################

# 清理feature分支（本地和远程都清理）
clean_feature_branch() {
    local branch="$1"
    local is_local_only="$2"

    echo -e "    ${BLUE}${EMOJI_CLEAN} 正在清理分支: ${branch}${NC}"

    # 删除本地分支
    if git branch -D "$branch" >/dev/null 2>&1; then
        echo -e "    ${GREEN}${EMOJI_SUCCESS} 本地分支删除成功${NC}"
    else
        echo -e "    ${RED}${EMOJI_ERROR} 本地分支删除失败${NC}"
        return 1
    fi

    # 如果不是仅本地分支，删除远程分支
    if [ "$is_local_only" = "false" ]; then
        if git push origin --delete "$branch" >/dev/null 2>&1; then
            echo -e "    ${GREEN}${EMOJI_SUCCESS} 远程分支删除成功${NC}"
        else
            echo -e "    ${YELLOW}${EMOJI_WARNING} 远程分支删除失败或不存在${NC}"
        fi
    fi

    return 0
}

# 清理环境分支（只清理本地）
clean_environment_branch() {
    local branch="$1"

    echo -e "    ${BLUE}${EMOJI_CLEAN} 正在清理环境分支: ${branch}${NC}"

    # 只删除本地分支
    if git branch -D "$branch" >/dev/null 2>&1; then
        echo -e "    ${GREEN}${EMOJI_SUCCESS} 本地环境分支删除成功${NC}"
        return 0
    else
        echo -e "    ${RED}${EMOJI_ERROR} 本地环境分支删除失败${NC}"
        return 1
    fi
}

# 清理merge分支（本地和远程都清理）
clean_merge_branch() {
    local branch="$1"
    local is_local_only="$2"

    echo -e "    ${BLUE}${EMOJI_CLEAN} 正在清理merge分支: ${branch}${NC}"

    # 删除本地分支
    if git branch -D "$branch" >/dev/null 2>&1; then
        echo -e "    ${GREEN}${EMOJI_SUCCESS} 本地merge分支删除成功${NC}"
    else
        echo -e "    ${RED}${EMOJI_ERROR} 本地merge分支删除失败${NC}"
        return 1
    fi

    # 如果不是仅本地分支，删除远程分支
    if [ "$is_local_only" = "false" ]; then
        if git push origin --delete "$branch" >/dev/null 2>&1; then
            echo -e "    ${GREEN}${EMOJI_SUCCESS} 远程merge分支删除成功${NC}"
        else
            echo -e "    ${YELLOW}${EMOJI_WARNING} 远程merge分支删除失败或不存在${NC}"
        fi
    fi

    return 0
}

# 分析环境分支
analyze_environment_branches() {
    local cleanup_days="$1"

    # 只获取本地环境分支
    local env_branches=$(get_local_environment_branches)

    if [ -z "$env_branches" ]; then
        return
    fi

    echo -e "\n${BLUE}${EMOJI_STATS} 环境分支分析${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"

    # 按分支类型分组分析
    local gray_branches=$(echo "$env_branches" | grep "^gray[1-6]/")
    local release_formal_branches=$(echo "$env_branches" | grep "^release/[0-9]")
    local release_preissue_branches=$(echo "$env_branches" | grep "^release/.*preissue")
    local vip_branches=$(echo "$env_branches" | grep "^vip/")

    # 分析Gray分支
    if [ -n "$gray_branches" ]; then
        echo -e "\n${PURPLE}${EMOJI_BRANCH} Gray 分支组:${NC}"

        # 按gray1-gray6分组
        for i in {1..6}; do
            local gray_group=$(echo "$gray_branches" | grep "^gray${i}/")
            if [ -z "$gray_group" ]; then
                continue
            fi

            echo -e "  ${CYAN}gray${i} 环境:${NC}"
            local latest_branch=""
            local latest_suffix=""

            for branch in $gray_group; do
                local commit_time=$(get_branch_last_commit_time "$branch")
                local time_ago=$(get_time_ago "$commit_time")
                local suffix=$(echo "$branch" | cut -d'/' -f2)

                if [ -z "$latest_suffix" ] || [ "$suffix" -gt "$latest_suffix" ]; then
                    latest_branch="$branch"
                    latest_suffix="$suffix"
                fi
            done

            # 显示分支状态
            for branch in $gray_group; do
                # 获取详细的提交信息
                local commit_info=$(get_branch_last_commit_info "$branch")
                local commit_hash=$(echo "$commit_info" | cut -d'|' -f1)
                local commit_msg=$(echo "$commit_info" | cut -d'|' -f2)
                local commit_time=$(echo "$commit_info" | cut -d'|' -f3 | cut -d' ' -f1,2 | cut -d'+' -f1)
                local time_ago=$(get_time_ago "$commit_time")

                if [ "$branch" == "$latest_branch" ]; then
                    echo -e "    ${WHITE}${EMOJI_BRANCH} $(colorize_branch "$branch") ${GREEN}${EMOJI_KEEP} 最新版本${NC}"
                    echo -e "      ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
                else
                    echo -e "    $(colorize_branch "$branch") ${RED}${EMOJI_TRASH} 可清理${NC}"
                    echo -e "      ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
                    # 收集删除建议
                    echo "DELETABLE:$branch|environment|true|非最新版本的环境分支" >&3
                fi
            done
        done
    fi

    # 分析Release分支
    if [ -n "$release_formal_branches" ] || [ -n "$release_preissue_branches" ]; then
        echo -e "\n${PURPLE}${EMOJI_BRANCH} Release 分支组:${NC}"

        # 正式版本分支
        if [ -n "$release_formal_branches" ]; then
            echo -e "  ${CYAN}正式版本:${NC}"
            local latest_version=""
            local latest_branch=""

            for branch in $release_formal_branches; do
                local version=$(echo "$branch" | cut -d'/' -f2)
                if [ -z "$latest_version" ] || [ "$(printf '%s\n%s' "$version" "$latest_version" | sort -V | tail -1)" == "$version" ]; then
                    latest_version="$version"
                    latest_branch="$branch"
                fi
            done

            for branch in $release_formal_branches; do
                # 获取详细的提交信息
                local commit_info=$(get_branch_last_commit_info "$branch")
                local commit_hash=$(echo "$commit_info" | cut -d'|' -f1)
                local commit_msg=$(echo "$commit_info" | cut -d'|' -f2)
                local commit_time=$(echo "$commit_info" | cut -d'|' -f3 | cut -d' ' -f1,2 | cut -d'+' -f1)
                local time_ago=$(get_time_ago "$commit_time")

                if [ "$branch" == "$latest_branch" ]; then
                    echo -e "    ${WHITE}${EMOJI_BRANCH} $(colorize_branch "$branch") ${GREEN}${EMOJI_KEEP} 最新版本${NC}"
                    echo -e "      ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
                else
                    echo -e "    $(colorize_branch "$branch") ${RED}${EMOJI_TRASH} 可清理${NC}"
                    echo -e "      ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
                    # 收集删除建议
                    echo "DELETABLE:$branch|environment|true|非最新版本的环境分支" >&3
                fi
            done
        fi

        # 预发版本分支
        if [ -n "$release_preissue_branches" ]; then
            echo -e "  ${CYAN}预发版本:${NC}"
            local latest_date=""
            local latest_branch=""

            for branch in $release_preissue_branches; do
                local date_suffix=$(echo "$branch" | sed 's/.*_//')
                if [ -z "$latest_date" ] || [ "$date_suffix" -gt "$latest_date" ]; then
                    latest_date="$date_suffix"
                    latest_branch="$branch"
                fi
            done

            for branch in $release_preissue_branches; do
                # 获取详细的提交信息
                local commit_info=$(get_branch_last_commit_info "$branch")
                local commit_hash=$(echo "$commit_info" | cut -d'|' -f1)
                local commit_msg=$(echo "$commit_info" | cut -d'|' -f2)
                local commit_time=$(echo "$commit_info" | cut -d'|' -f3 | cut -d' ' -f1,2 | cut -d'+' -f1)
                local time_ago=$(get_time_ago "$commit_time")

                if [ "$branch" == "$latest_branch" ]; then
                    echo -e "    ${WHITE}${EMOJI_BRANCH} $(colorize_branch "$branch") ${GREEN}${EMOJI_KEEP} 最新版本${NC}"
                    echo -e "      ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
                else
                    echo -e "    $(colorize_branch "$branch") ${RED}${EMOJI_TRASH} 可清理${NC}"
                    echo -e "      ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
                    # 收集删除建议
                    echo "DELETABLE:$branch|environment|true|非最新版本的环境分支" >&3
                fi
            done
        fi
    fi

    # 分析VIP分支
    if [ -n "$vip_branches" ]; then
        echo -e "\n${PURPLE}${EMOJI_BRANCH} VIP 分支组:${NC}"
        local latest_date=""
        local latest_branch=""

        for branch in $vip_branches; do
            local date_suffix=$(echo "$branch" | cut -d'/' -f2)
            if [ -z "$latest_date" ] || [ "$date_suffix" -gt "$latest_date" ]; then
                latest_date="$date_suffix"
                latest_branch="$branch"
            fi
        done

        for branch in $vip_branches; do
            # 获取详细的提交信息
            local commit_info=$(get_branch_last_commit_info "$branch")
            local commit_hash=$(echo "$commit_info" | cut -d'|' -f1)
            local commit_msg=$(echo "$commit_info" | cut -d'|' -f2)
            local commit_time=$(echo "$commit_info" | cut -d'|' -f3 | cut -d' ' -f1,2 | cut -d'+' -f1)
            local time_ago=$(get_time_ago "$commit_time")

            if [ "$branch" == "$latest_branch" ]; then
                echo -e "  ${WHITE}${EMOJI_BRANCH} $(colorize_branch "$branch") ${GREEN}${EMOJI_KEEP} 最新版本${NC}"
                echo -e "    ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
            else
                echo -e "  $(colorize_branch "$branch") ${RED}${EMOJI_TRASH} 可清理${NC}"
                echo -e "    ${GRAY}${EMOJI_CLOCK} ${YELLOW}$commit_hash${NC} ${WHITE}$commit_msg${NC} ${GRAY}($time_ago)${NC}"
                # 收集删除建议
                echo "DELETABLE:$branch|environment|true|非最新版本的环境分支" >&3
            fi
        done
    fi
}

# 分析merge分支
analyze_merge_branches() {
    local all_branches="$1"

    local merge_branches=$(echo "$all_branches" | grep "^${MERGE_PREFIX}")

    if [ -z "$merge_branches" ]; then
        return
    fi

    echo -e "\n${CYAN}${EMOJI_STATS} Merge分支分析${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"

    for branch in $merge_branches; do
        local commit_time=$(get_branch_last_commit_time "$branch")
        local time_ago=$(get_time_ago "$commit_time")
        local is_local_only=false

        # 检查是否只有本地分支
        if is_local_only_branch "$branch"; then
            is_local_only=true
        fi

        echo -e "\n${CYAN}${EMOJI_BRANCH} 分支: ${WHITE}$branch${NC} ${GRAY}(merge类)${NC}"
        echo -e "  ${GRAY}${EMOJI_CLOCK} 最后提交: ${time_ago}${NC}"

        # 尝试解析对应的原始分支
        # merge分支格式通常是: merge/username/target_branch
        local target_branch=$(echo "$branch" | sed 's/^merge\/[^\/]*\///')

        if [ -n "$target_branch" ]; then
            # 检查对应的目标分支是否存在且需要清理
            if echo "$all_branches" | grep -q "^${target_branch}$"; then
                echo -e "  ${BLUE}${EMOJI_INFO} 对应分支: ${target_branch}${NC}"
                echo -e "  ${YELLOW}${EMOJI_KEEP} 建议: 根据对应分支状态决定${NC}"
            else
                echo -e "  ${RED}${EMOJI_WARNING} 对应分支不存在: ${target_branch}${NC}"
                echo -e "  ${GREEN}${EMOJI_TRASH} 建议: 可以清理${NC}"
                # 收集删除建议
                echo "DELETABLE:$branch|merge|$is_local_only|对应分支不存在" >&3
            fi
        else
            echo -e "  ${YELLOW}${EMOJI_WARNING} 无法解析对应分支${NC}"
            echo -e "  ${YELLOW}${EMOJI_KEEP} 建议: 需要人工确认${NC}"
        fi
    done
}

# 主分析函数
analyze_branches() {
    local cleanup_days="$1"
    local branch_filter="$2"

    echo -e "\n${WHITE}${EMOJI_ROCKET} Git 分支清理分析${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${EMOJI_INFO} 分支清理阈值: ${WHITE}${cleanup_days}天${NC}"

    local all_branches=$(get_all_local_branches)

    # 如果有分支过滤条件，应用过滤
    if [ -n "$branch_filter" ]; then
        all_branches=$(echo "$all_branches" | grep "$branch_filter")
        echo -e "${BLUE}${EMOJI_INFO} 分支过滤条件: ${WHITE}${branch_filter}${NC}"
    fi

    local branch_count=$(echo "$all_branches" | wc -w)
    echo -e "${BLUE}${EMOJI_INFO} 发现 ${WHITE}${branch_count}${NC} ${BLUE}个本地分支${NC}"

    # 统计变量
    local feature_cleanable=0
    local feature_total=0
    local env_cleanable=0
    local env_total=0
    local merge_total=0

    # 分析feature分支
    echo -e "\n${GREEN}${EMOJI_STATS} Feature分支分析${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"

    for branch in $all_branches; do
        local branch_type=$(get_branch_type "$branch")

        if [ "$branch_type" == "feature" ]; then
            ((feature_total++))
            if analyze_feature_branch "$branch" "$cleanup_days"; then
                ((feature_cleanable++))
            fi
        fi
    done

    # 分析环境分支
    analyze_environment_branches "$cleanup_days"

    # 分析merge分支
    analyze_merge_branches "$all_branches"

    # 显示统计信息
    echo -e "\n${WHITE}${EMOJI_STATS} 分析统计${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${EMOJI_SUCCESS} Feature分支: ${WHITE}${feature_total}${NC} ${GREEN}个，可清理: ${WHITE}${feature_cleanable}${NC} ${GREEN}个${NC}"

    local env_branches=$(echo "$all_branches" | grep -E "^(gray|release|vip)" | wc -l)
    echo -e "${BLUE}${EMOJI_INFO} 环境分支: ${WHITE}${env_branches}${NC} ${BLUE}个${NC}"

    local merge_branches=$(echo "$all_branches" | grep "^${MERGE_PREFIX}" | wc -l)
    echo -e "${PURPLE}${EMOJI_INFO} Merge分支: ${WHITE}${merge_branches}${NC} ${PURPLE}个${NC}"
}

# 参数解析
parse_arguments() {
    local cleanup_days="$DEFAULT_CLEANUP_DAYS"
    local branch_filter=""
    local dry_run=false
    local force=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--days)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    cleanup_days="$2"
                    shift 2
                else
                    echo -e "${RED}${EMOJI_ERROR} 错误: --days 需要一个数字参数${NC}"
                    exit 1
                fi
                ;;
            -b|--branch)
                if [[ -n "$2" ]]; then
                    branch_filter="$2"
                    shift 2
                else
                    echo -e "${RED}${EMOJI_ERROR} 错误: --branch 需要一个关键词参数${NC}"
                    exit 1
                fi
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            --force)
                force=true
                shift
                ;;
            *)
                echo -e "${RED}${EMOJI_ERROR} 错误: 未知参数 '$1'${NC}"
                echo -e "${GRAY}使用 --help 查看帮助信息${NC}"
                exit 1
                ;;
        esac
    done

    # 返回解析的参数
    echo "$cleanup_days $branch_filter $dry_run $force"
}

# 收集并显示可删除分支
collect_and_show_deletable_branches() {
    local deletable_file="$1"

    if [ ! -s "$deletable_file" ]; then
        echo -e "\n${GREEN}${EMOJI_SUCCESS} 没有发现可删除的分支！${NC}"
        return 1
    fi

    echo -e "\n${YELLOW}${EMOJI_CLEAN} 可删除分支列表${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"

    local feature_count=0
    local env_count=0
    local merge_count=0

    while IFS='|' read -r branch_name branch_type is_local_only reason; do
        case "$branch_type" in
            "feature")
                ((feature_count++))
                local scope_text="本地+远程"
                if [ "$is_local_only" = "true" ]; then
                    scope_text="仅本地"
                fi
                echo -e "${GREEN}${EMOJI_BRANCH} Feature分支: ${WHITE}$branch_name${NC} ${GRAY}($scope_text)${NC}"
                echo -e "  ${GRAY}删除理由: $reason${NC}"
                ;;
            "environment")
                ((env_count++))
                echo -e "${BLUE}${EMOJI_BRANCH} 环境分支: $(colorize_branch "$branch_name") ${GRAY}(仅本地)${NC}"
                echo -e "  ${GRAY}删除理由: $reason${NC}"
                ;;
            "merge")
                ((merge_count++))
                local scope_text="本地+远程"
                if [ "$is_local_only" = "true" ]; then
                    scope_text="仅本地"
                fi
                echo -e "${PURPLE}${EMOJI_BRANCH} Merge分支: ${WHITE}$branch_name${NC} ${GRAY}($scope_text)${NC}"
                echo -e "  ${GRAY}删除理由: $reason${NC}"
                ;;
        esac
        echo ""
    done < <(grep "^DELETABLE:" "$deletable_file" | sed 's/^DELETABLE://')

    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${EMOJI_STATS} 删除统计: Feature(${feature_count}) + 环境(${env_count}) + Merge(${merge_count}) = 总计 $((feature_count + env_count + merge_count)) 个分支${NC}"

    return 0
}

# 执行分支删除
execute_branch_deletion() {
    local deletable_file="$1"
    local deleted_count=0
    local failed_count=0

    echo -e "\n${BLUE}${EMOJI_CLEAN} 开始执行分支删除...${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"

    while IFS='|' read -r branch_name branch_type is_local_only reason; do
        echo -e "${CYAN}${EMOJI_BRANCH} 删除分支: ${WHITE}$branch_name${NC}"

        case "$branch_type" in
            "feature")
                if clean_feature_branch "$branch_name" "$is_local_only"; then
                    ((deleted_count++))
                else
                    ((failed_count++))
                fi
                ;;
            "environment")
                if clean_environment_branch "$branch_name"; then
                    ((deleted_count++))
                else
                    ((failed_count++))
                fi
                ;;
            "merge")
                if clean_merge_branch "$branch_name" "$is_local_only"; then
                    ((deleted_count++))
                else
                    ((failed_count++))
                fi
                ;;
        esac
        echo ""
    done < <(grep "^DELETABLE:" "$deletable_file" | sed 's/^DELETABLE://')

    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    if [ $failed_count -eq 0 ]; then
        echo -e "${GREEN}${EMOJI_SUCCESS} 删除完成！成功删除 ${deleted_count} 个分支${NC}"
    else
        echo -e "${YELLOW}${EMOJI_WARNING} 删除完成！成功 ${deleted_count} 个，失败 ${failed_count} 个${NC}"
    fi
}

# 确认清理操作
confirm_cleanup() {
    local force="$1"

    if [ "$force" = "true" ]; then
        return 0
    fi

    echo -e "\n${YELLOW}${EMOJI_WARNING} 即将执行分支清理操作！${NC}"
    echo -e "${RED}${EMOJI_WARNING} 此操作将永久删除分支，请确认！${NC}"
    echo -e "${GRAY}清理策略:${NC}"
    echo -e "  • ${GREEN}Feature/Merge分支${NC}: 删除本地和远程分支"
    echo -e "  • ${BLUE}环境分支${NC}: 只删除本地分支"
    echo ""

    read -p "确认执行清理操作？(y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}${EMOJI_INFO} 操作已取消${NC}"
        exit 0
    fi

    return 0
}

# 主函数
main() {
    # 先检查是否是帮助或更新参数
    for arg in "$@"; do
        if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
            show_help
            exit 0
        elif [[ "$arg" == "-u" || "$arg" == "--update" ]]; then
            # 手动触发更新检查
            if [[ -n "${GITLAB_TOKEN:-}" ]]; then
                local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
                if [[ -f "$sv_script" ]]; then
                    # 使用子shell避免变量冲突
                    if (source "$sv_script" && check_script_update "bc.sh") 2>/dev/null; then
                        exit 0
                    else
                        echo -e "${RED}${EMOJI_ERROR} 更新检查失败${NC}"
                        exit 1
                    fi
                else
                    echo -e "${RED}${EMOJI_ERROR} 更新脚本不存在: $sv_script${NC}"
                    exit 1
                fi
            else
                echo -e "${YELLOW}${EMOJI_WARNING} 未设置 GITLAB_TOKEN 环境变量，无法检查更新${NC}"
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
            (source "$sv_script" && check_script_update "bc.sh") 2>/dev/null || true
        fi
    fi

    # 显示脚本名称含义
    echo -e "${WHITE}${EMOJI_CLEAN} BC - Branch Clean (Git分支清理工具)${NC}"
    echo ""

    # 解析参数
    local params=$(parse_arguments "$@")
    local cleanup_days=$(echo "$params" | cut -d' ' -f1)
    local branch_filter=$(echo "$params" | cut -d' ' -f2)
    local dry_run=$(echo "$params" | cut -d' ' -f3)
    local force=$(echo "$params" | cut -d' ' -f4)

    # 基础检查
    check_git_repository
    fetch_remote_info

    # 创建临时文件收集删除建议
    local deletable_file="/tmp/bc_deletable_$$"
    exec 3>"$deletable_file"

    # 执行分析
    analyze_branches "$cleanup_days" "$branch_filter"

    # 关闭文件描述符
    exec 3>&-

    # 显示分析完成信息
    echo -e "\n${GREEN}${EMOJI_SUCCESS} 分支分析完成！${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"

    # 收集并显示可删除分支
    if collect_and_show_deletable_branches "$deletable_file"; then
        # 如果是预览模式，只显示不删除
        if [ "$dry_run" = "true" ]; then
            echo -e "${YELLOW}${EMOJI_INFO} 预览模式：以上分支可以删除，但未执行实际删除操作${NC}"
        else
            # 默认模式：询问是否删除
            if [ "$force" = "true" ]; then
                echo -e "${RED}${EMOJI_WARNING} 强制模式：将直接执行删除操作${NC}"
                execute_branch_deletion "$deletable_file"
            else
                echo -e "${YELLOW}${EMOJI_WARNING} 即将删除以上分支，此操作不可撤销！${NC}"
                read -p "确认删除这些分支？(y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    execute_branch_deletion "$deletable_file"
                else
                    echo -e "${BLUE}${EMOJI_INFO} 操作已取消${NC}"
                fi
            fi
        fi
    fi

    # 清理临时文件
    rm -f "$deletable_file"

    exit 0
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
