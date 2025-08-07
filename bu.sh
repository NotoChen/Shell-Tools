#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.3"

#######################################
#            配置区域                   #
#######################################

# 需要忽略的分支前缀集合（可自由增删）
IGNORED_BRANCH_PREFIXES=(
    "feature/"
    "merge/"
    "hotfix/"
)

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
readonly EMOJI_UPDATE="🔄"
readonly EMOJI_MERGE="🔀"
readonly EMOJI_SKIP="⏭️"

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
    echo -e "${GREEN}${EMOJI_SUCCESS} 检测到当前目录是git项目，开始更新分支...${NC}"
}

# 更新远程仓库信息
fetch_remote_info() {
    echo -e "${BLUE}${EMOJI_UPDATE} 正在更新远程仓库信息...${NC}"
    git fetch --all --prune >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}${EMOJI_ERROR} 获取远程信息失败!${NC}"
        exit 1
    fi
    echo -e "${GREEN}${EMOJI_SUCCESS} 远程仓库信息更新完成${NC}"
}

# 构建忽略分支的grep模式
build_ignore_pattern() {
    local pattern=""
    for prefix in "${IGNORED_BRANCH_PREFIXES[@]}"; do
        if [ -z "$pattern" ]; then
            pattern="^${prefix}"
        else
            pattern="${pattern}|^${prefix}"
        fi
    done
    echo "$pattern"
}

# 获取需要更新的本地分支列表
get_local_branches() {
    local ignore_pattern=$(build_ignore_pattern)
    if [ -n "$ignore_pattern" ]; then
        git branch --format='%(refname:short)' | grep -v -E "$ignore_pattern"
    else
        git branch --format='%(refname:short)'
    fi
}

# 获取分支的最新提交时间
get_branch_last_commit_time() {
    local branch="$1"
    git log -1 --format="%ci" "$branch" 2>/dev/null | cut -d' ' -f1,2 | cut -d'+' -f1
}

# 获取分支更新统计信息
get_branch_update_stats() {
    local branch="$1"
    local current_branch="$2"

    # 检查远程分支是否存在
    if ! git branch -r | grep -q "origin/$branch" >/dev/null 2>&1; then
        echo "no_remote"
        return
    fi

    # 获取本地和远程的提交差异
    local behind_count=$(git rev-list --count "$branch..origin/$branch" 2>/dev/null || echo "0")
    local ahead_count=$(git rev-list --count "origin/$branch..$branch" 2>/dev/null || echo "0")

    if [ "$behind_count" -eq 0 ] && [ "$ahead_count" -eq 0 ]; then
        echo "up_to_date"
    elif [ "$behind_count" -gt 0 ] && [ "$ahead_count" -eq 0 ]; then
        echo "behind:$behind_count"
    elif [ "$behind_count" -eq 0 ] && [ "$ahead_count" -gt 0 ]; then
        echo "ahead:$ahead_count"
    else
        echo "diverged:$behind_count:$ahead_count"
    fi
}

# 获取分支变更统计（新增、修改、删除）
get_branch_change_stats() {
    local branch="$1"

    # 检查远程分支是否存在
    if ! git branch -r | grep -q "origin/$branch" >/dev/null 2>&1; then
        echo ""
        return
    fi

    # 获取变更统计
    local stats=$(git diff --stat "$branch" "origin/$branch" 2>/dev/null | tail -1)
    if [ -n "$stats" ]; then
        # 解析统计信息，格式类似：3 files changed, 15 insertions(+), 8 deletions(-)
        local insertions=$(echo "$stats" | grep -o '[0-9]\+ insertion' | cut -d' ' -f1)
        local deletions=$(echo "$stats" | grep -o '[0-9]\+ deletion' | cut -d' ' -f1)
        local files=$(echo "$stats" | grep -o '[0-9]\+ file' | cut -d' ' -f1)

        [ -z "$insertions" ] && insertions="0"
        [ -z "$deletions" ] && deletions="0"
        [ -z "$files" ] && files="0"

        echo "$files:$insertions:$deletions"
    else
        echo "0:0:0"
    fi
}

# 检查是否存在对应的merge分支（使用模糊匹配）
check_merge_branch() {
    local original_branch="$1"

    # 使用模糊匹配查找对应的merge分支
    # 匹配模式：merge/*/原分支名称
    local merge_branch=$(git branch | grep -E "^\s*merge/.+/${original_branch}$" | sed 's/^[ \t*]*//' | head -1)

    if [ -n "$merge_branch" ]; then
        echo "$merge_branch"
        return 0
    fi

    return 1
}

# 检查merge分支是否需要更新
check_merge_branch_needs_update() {
    local original_branch="$1"
    local merge_branch="$2"

    # 检查merge分支与原分支是否有差异
    local diff_count=$(git rev-list --count "$merge_branch..$original_branch" 2>/dev/null || echo "0")

    if [ "$diff_count" -eq 0 ]; then
        return 1  # 不需要更新
    else
        return 0  # 需要更新
    fi
}

# 将原分支合并到对应的merge分支
merge_to_merge_branch() {
    local original_branch="$1"
    local merge_branch="$2"
    local current_branch="$3"

    echo -e "    ${CYAN}${EMOJI_MERGE} 检测到merge分支: ${WHITE}${merge_branch}${NC}"

    # 检查merge分支是否需要更新
    if ! check_merge_branch_needs_update "$original_branch" "$merge_branch"; then
        echo -e "    ${GREEN}${EMOJI_SUCCESS} merge分支已是最新，无需合并${NC}"
        return 0
    fi

    # 切换到merge分支
    git checkout "$merge_branch" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "    ${RED}${EMOJI_ERROR} 切换到merge分支失败${NC}"
        return 1
    fi

    # 合并原分支到merge分支
    git merge "$original_branch" --no-edit >/dev/null 2>&1
    local merge_result=$?

    if [ $merge_result -eq 0 ]; then
        echo -e "    ${GREEN}${EMOJI_SUCCESS} 成功合并到 ${WHITE}${merge_branch}${NC}"

        # 推送merge分支到远程
        echo -e "    ${BLUE}${EMOJI_UPDATE} 正在推送merge分支到远程...${NC}"
        git push origin "$merge_branch" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "    ${GREEN}${EMOJI_SUCCESS} merge分支推送成功${NC}"
        else
            echo -e "    ${YELLOW}${EMOJI_WARNING} merge分支推送失败，可能需要手动推送${NC}"
        fi
    else
        echo -e "    ${RED}${EMOJI_ERROR} 合并失败，可能存在冲突${NC}"
    fi

    # 切换回原来的分支
    git checkout "$current_branch" >/dev/null 2>&1

    return $merge_result
}

# 更新单个分支
update_branch() {
    local branch="$1"
    local current_branch="$2"

    # 获取更新前的信息
    local before_time=$(get_branch_last_commit_time "$branch")
    local update_stats=$(get_branch_update_stats "$branch" "$current_branch")

    # 显示分支信息
    echo -e "\n${CYAN}${EMOJI_BRANCH} 分支: ${WHITE}$branch${NC}"
    if [ -n "$before_time" ]; then
        echo -e "  ${GRAY}${EMOJI_CLOCK} 最新提交: ${before_time}${NC}"
    fi

    # 处理不同的更新状态
    case "$update_stats" in
        "no_remote")
            echo -e "  ${YELLOW}${EMOJI_SKIP} 没有对应的远程分支，跳过更新${NC}"
            return 0
            ;;
        "up_to_date")
            echo -e "  ${GREEN}${EMOJI_SUCCESS} 已是最新版本${NC}"
            local change_stats=$(get_branch_change_stats "$branch")
            if [ "$change_stats" != "0:0:0" ]; then
                local files=$(echo "$change_stats" | cut -d':' -f1)
                local insertions=$(echo "$change_stats" | cut -d':' -f2)
                local deletions=$(echo "$change_stats" | cut -d':' -f3)
                echo -e "  ${GRAY}${EMOJI_STATS} 变更: ${files}个文件, +${insertions}, -${deletions}${NC}"
            fi
            ;;
        behind:*)
            local behind_count=$(echo "$update_stats" | cut -d':' -f2)
            echo -e "  ${YELLOW}${EMOJI_UPDATE} 落后 ${behind_count} 个提交，正在更新...${NC}"

            # 执行更新
            if [ "$branch" == "$current_branch" ]; then
                git pull >/dev/null 2>&1
            else
                git fetch origin $branch:$branch >/dev/null 2>&1
            fi

            if [ $? -eq 0 ]; then
                local after_time=$(get_branch_last_commit_time "$branch")
                echo -e "  ${GREEN}${EMOJI_SUCCESS} 更新成功${NC}"
                if [ -n "$after_time" ] && [ "$after_time" != "$before_time" ]; then
                    echo -e "  ${GRAY}${EMOJI_CLOCK} 新的提交时间: ${after_time}${NC}"
                fi

                # 显示变更统计
                local change_stats=$(get_branch_change_stats "$branch")
                if [ "$change_stats" != "0:0:0" ]; then
                    local files=$(echo "$change_stats" | cut -d':' -f1)
                    local insertions=$(echo "$change_stats" | cut -d':' -f2)
                    local deletions=$(echo "$change_stats" | cut -d':' -f3)
                    echo -e "  ${GRAY}${EMOJI_STATS} 本次更新: ${files}个文件, +${insertions}, -${deletions}${NC}"
                fi
            else
                echo -e "  ${RED}${EMOJI_ERROR} 更新失败${NC}"
                return 1
            fi
            ;;
        ahead:*)
            local ahead_count=$(echo "$update_stats" | cut -d':' -f2)
            echo -e "  ${BLUE}${EMOJI_INFO} 领先远程 ${ahead_count} 个提交${NC}"
            ;;
        diverged:*)
            local behind_count=$(echo "$update_stats" | cut -d':' -f2)
            local ahead_count=$(echo "$update_stats" | cut -d':' -f3)
            echo -e "  ${PURPLE}${EMOJI_WARNING} 分支已分叉 (落后${behind_count}, 领先${ahead_count})${NC}"
            ;;
    esac

    # 检查是否存在对应的merge分支并自动合并
    local merge_branch=$(check_merge_branch "$branch")
    if [ $? -eq 0 ] && [ -n "$merge_branch" ]; then
        merge_to_merge_branch "$branch" "$merge_branch" "$current_branch"
    fi

    return 0
}

# 批量更新所有分支
update_all_branches() {
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    echo -e "\n${WHITE}${EMOJI_ROCKET} Git 分支批量更新工具${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${EMOJI_INFO} 当前分支: ${WHITE}${current_branch}${NC}"

    local local_branches=$(get_local_branches)
    local branch_count=$(echo "$local_branches" | wc -w)
    local ignored_prefixes_str=$(IFS=', '; echo "${IGNORED_BRANCH_PREFIXES[*]}")

    echo -e "${BLUE}${EMOJI_INFO} 发现 ${WHITE}${branch_count}${NC} ${BLUE}个分支需要检查${NC}"
    echo -e "${GRAY}忽略前缀: ${ignored_prefixes_str}${NC}"
    echo -e "${CYAN}${EMOJI_MERGE} 自动合并到merge分支功能已启用${NC}"

    local failed_count=0
    local success_count=0
    local up_to_date_count=0
    local updated_count=0

    # 创建分支列表，当前分支优先
    local sorted_branches=""
    local other_branches=""

    for branch in $local_branches; do
        if [ "$branch" == "$current_branch" ]; then
            sorted_branches="$branch"
        else
            other_branches="$other_branches $branch"
        fi
    done

    # 合并分支列表：当前分支在前
    sorted_branches="$sorted_branches$other_branches"

    for branch in $sorted_branches; do
        local before_stats=$(get_branch_update_stats "$branch" "$current_branch")

        if update_branch "$branch" "$current_branch"; then
            ((success_count++))
            case "$before_stats" in
                "up_to_date")
                    ((up_to_date_count++))
                    ;;
                behind:*)
                    ((updated_count++))
                    ;;
            esac
        else
            ((failed_count++))
        fi
    done

    # 显示详细统计
    echo -e "\n${WHITE}${EMOJI_STATS} 更新统计报告${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${EMOJI_SUCCESS} 处理成功: ${WHITE}${success_count}${NC}"
    echo -e "${BLUE}${EMOJI_INFO} 已是最新: ${WHITE}${up_to_date_count}${NC}"
    echo -e "${YELLOW}${EMOJI_UPDATE} 已更新: ${WHITE}${updated_count}${NC}"
    if [ $failed_count -gt 0 ]; then
        echo -e "${RED}${EMOJI_ERROR} 处理失败: ${WHITE}${failed_count}${NC}"
    fi

    if [ $failed_count -gt 0 ]; then
        exit 1
    fi
}

#######################################
#            主程序入口                 #
#######################################

main() {
    # 检查是否是更新参数
    for arg in "$@"; do
        if [[ "$arg" == "-u" || "$arg" == "--update" ]]; then
            # 手动触发更新检查
            if [[ -n "${GITLAB_TOKEN:-}" ]]; then
                local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
                if [[ -f "$sv_script" ]]; then
                    # 使用子shell避免变量冲突
                    if (source "$sv_script" && check_script_update "bu.sh") 2>/dev/null; then
                        exit 0
                    else
                        echo -e "${RED}${EMOJI_FAILED} 更新检查失败${NC}"
                        exit 1
                    fi
                else
                    echo -e "${RED}${EMOJI_FAILED} 更新脚本不存在: $sv_script${NC}"
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
            (source "$sv_script" && check_script_update "bu.sh") 2>/dev/null || true
        fi
    fi

    # 显示脚本名称含义
    echo -e "${BOLD}${BLUE}${EMOJI_ROCKET} BU - Branch Update (Git分支批量更新工具)${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    echo ""

    check_git_repository
    fetch_remote_info
    update_all_branches
    echo -e "\n${GREEN}${EMOJI_SUCCESS} 所有分支处理完成！${NC}"
    echo -e "${GRAY}═══════════════════════════════════════════════════${NC}"
    exit 0
}

# 执行主程序
main "$@"
