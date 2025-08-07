#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.3"

#######################################
#            VPN 连接管理工具           #
#######################################

# 设置严格模式（但允许函数返回非零值）
set -uo pipefail

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
readonly BOLD='\033[1m'
readonly NC='\033[0m' # 无颜色

# Emoji 定义
readonly EMOJI_SUCCESS="✅"
readonly EMOJI_ERROR="❌"
readonly EMOJI_WARNING="⚠️"
readonly EMOJI_INFO="ℹ️"
readonly EMOJI_ROCKET="🚀"
readonly EMOJI_VPN="🔐"
readonly EMOJI_CONNECT="🔗"
readonly EMOJI_DISCONNECT="🔌"
readonly EMOJI_CLOCK="🕐"
readonly EMOJI_SEARCH="🔍"
readonly EMOJI_LIST="📋"

#######################################
#            配置区域                   #
#######################################

# VPN 配置
readonly DEFAULT_TIMEOUT=60
readonly CHECK_INTERVAL=2
readonly VPN_SECRET="your_vpn_secret"  # 可以通过环境变量 VPN_SECRET 覆盖

#######################################
#            工具函数                   #
#######################################

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
    echo -e "${GREEN}${EMOJI_SUCCESS} ${message}${NC}"
}

# 打印警告信息
print_warning() {
    local message="$1"
    echo -e "${YELLOW}${EMOJI_WARNING} ${message}${NC}"
}

# 打印信息
print_info() {
    local message="$1"
    echo -e "${BLUE}${EMOJI_INFO} ${message}${NC}"
}

# 打印标题
print_title() {
    local message="$1"
    echo -e "${CYAN}${BOLD}${EMOJI_VPN} ${message}${NC}"
}

# 检查系统兼容性
check_system_compatibility() {
    # 检查是否为 macOS
    if [[ "$OSTYPE" != "darwin"* ]]; then
        print_error_and_exit "此脚本仅支持 macOS 系统"
    fi

    # 检查必要命令
    if ! command -v scutil >/dev/null 2>&1; then
        print_error_and_exit "scutil 命令未找到，请确保在 macOS 系统上运行"
    fi
}

# 获取 VPN 列表（兼容 bash 和 zsh）
get_vpn_list() {
    local vpn_raw_list
    local vpn_list=()

    # 获取原始 VPN 列表
    vpn_raw_list=$(scutil --nc list 2>/dev/null | sed -n 's/.*"\(.*\)".*/\1/p' | grep -v '^$' || true)

    if [[ -z "$vpn_raw_list" ]]; then
        return 1
    fi

    # 使用 while 循环读取，兼容所有 shell
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            vpn_list+=("$line")
        fi
    done <<< "$vpn_raw_list"

    # 输出数组元素
    printf '%s\n' "${vpn_list[@]}"
}

# 显示 VPN 列表
show_vpn_list() {
    local vpns=()
    local vpn_list_output

    print_title "VPN 连接管理工具"
    echo

    print_info "正在扫描 VPN 配置..."

    # 获取 VPN 列表
    vpn_list_output=$(get_vpn_list)
    if [[ $? -ne 0 || -z "$vpn_list_output" ]]; then
        print_error "未检测到任何 VPN 配置"
        echo
        print_info "请在系统偏好设置中配置 VPN 连接"
        return 1
    fi

    # 读取到数组中
    while IFS= read -r line; do
        vpns+=("$line")
    done <<< "$vpn_list_output"

    echo
    echo -e "${CYAN}${EMOJI_LIST} 可用的 VPN 配置：${NC}"
    echo

    local i=1
    for vpn in "${vpns[@]}"; do
        local status_info
        status_info=$(get_vpn_status_info "$vpn")
        echo -e "  ${BOLD}$i)${NC} ${WHITE}$vpn${NC} $status_info"
        ((i++))
    done

    echo
    return 0
}
# 获取 VPN 状态信息
get_vpn_status_info() {
    local vpn_name="$1"
    local status_code
    local status_text

    status_code=$(scutil --nc status "$vpn_name" 2>/dev/null | grep 'Status' | awk '{print $3}' | tail -n 1 || echo "0")

    case "$status_code" in
        0)
            status_text="${GRAY}[未连接]${NC}"
            ;;
        1)
            status_text="${YELLOW}[连接中...]${NC}"
            ;;
        2|3)
            status_text="${GREEN}[已连接]${NC}"
            ;;
        *)
            status_text="${GRAY}[未知状态]${NC}"
            ;;
    esac

    echo "$status_text"
}

# 获取当前连接的 VPN
get_connected_vpn() {
    local vpn_list_output
    local connected_vpns=()

    vpn_list_output=$(get_vpn_list)
    if [[ $? -ne 0 || -z "$vpn_list_output" ]]; then
        return 1
    fi

    while IFS= read -r vpn; do
        local status_code
        status_code=$(scutil --nc status "$vpn" 2>/dev/null | grep 'Status' | awk '{print $3}' | tail -n 1 || echo "0")
        if [[ "$status_code" -ge 2 ]]; then
            connected_vpns+=("$vpn")
        fi
    done <<< "$vpn_list_output"

    if [[ ${#connected_vpns[@]} -gt 0 ]]; then
        printf '%s\n' "${connected_vpns[@]}"
        return 0
    else
        return 1
    fi
}

# 断开 VPN 连接
disconnect_vpn() {
    local vpn_name="$1"

    print_info "正在断开 VPN: $vpn_name"

    if scutil --nc stop "$vpn_name" 2>/dev/null; then
        sleep 2
        local status_code
        status_code=$(scutil --nc status "$vpn_name" 2>/dev/null | grep 'Status' | awk '{print $3}' | tail -n 1 || echo "0")

        if [[ "$status_code" -eq 0 ]]; then
            print_success "VPN 已断开: $vpn_name"
            return 0
        else
            print_warning "VPN 断开可能未完成: $vpn_name"
            return 1
        fi
    else
        print_error "断开 VPN 失败: $vpn_name"
        return 1
    fi
}

# 连接 VPN
connect_vpn() {
    local vpn_name="$1"
    local vpn_password="$2"
    local vpn_secret="${VPN_SECRET:-$3}"
    local timeout="${4:-$DEFAULT_TIMEOUT}"

    print_info "正在连接 VPN: ${BOLD}$vpn_name${NC}"

    # 启动 VPN 连接
    if ! scutil --nc start "$vpn_name" --password "$vpn_password" --secret "$vpn_secret" 2>/dev/null; then
        print_error "启动 VPN 连接失败"
        return 1
    fi

    local elapsed=0
    local last_status=""

    # 轮询连接状态
    while [[ $elapsed -lt $timeout ]]; do
        local vpn_status
        vpn_status=$(scutil --nc status "$vpn_name" 2>/dev/null | grep 'Status' | awk '{print $3}' | tail -n 1 || echo "0")

        case "$vpn_status" in
            0)
                print_error "VPN 连接失败: $vpn_name"
                return 1
                ;;
            1)
                if [[ "$last_status" != "1" ]]; then
                    echo -ne "${YELLOW}${EMOJI_CLOCK} 正在连接"
                fi
                echo -ne "."
                last_status="1"
                ;;
            2|3)
                echo  # 换行
                print_success "VPN 连接成功: $vpn_name"

                # 显示连接信息
                show_connection_info "$vpn_name"
                return 0
                ;;
        esac

        sleep $CHECK_INTERVAL
        ((elapsed += CHECK_INTERVAL))
    done

    echo  # 换行
    print_error "连接超时，未能成功连接 VPN: $vpn_name (${timeout}秒)"
    return 1
}

# 显示连接信息
show_connection_info() {
    local vpn_name="$1"

    echo
    print_info "连接详情:"
    echo -e "  ${BOLD}VPN 名称:${NC} $vpn_name"

    # 获取 IP 地址信息
    local public_ip
    public_ip=$(curl -s --max-time 5 "https://api.ipify.org" 2>/dev/null || echo "获取失败")
    echo -e "  ${BOLD}公网 IP:${NC} $public_ip"

    # 获取网络接口信息
    local vpn_interface
    vpn_interface=$(route get default 2>/dev/null | grep interface | awk '{print $2}' || echo "未知")
    echo -e "  ${BOLD}网络接口:${NC} $vpn_interface"

    echo
}

# 读取用户输入（兼容不同 shell）
read_user_input() {
    local prompt="$1"
    local var_name="$2"
    local is_password="${3:-false}"

    if [[ "$is_password" == "true" ]]; then
        echo -ne "${prompt}"
        read -s user_input
        echo  # 换行
    else
        echo -ne "${prompt}"
        read user_input
    fi

    eval "$var_name=\"\$user_input\""
}
#######################################
#            主要功能函数                #
#######################################

# 显示当前状态
show_status() {
    print_title "VPN 连接状态"
    echo

    local connected_vpns
    local vpn_status
    connected_vpns=$(get_connected_vpn)
    vpn_status=$?

    if [[ $vpn_status -eq 0 && -n "$connected_vpns" ]]; then
        print_success "当前已连接的 VPN:"
        while IFS= read -r vpn; do
            echo -e "  ${GREEN}${EMOJI_CONNECT}${NC} ${BOLD}$vpn${NC}"

            # 显示详细信息
            local public_ip
            public_ip=$(curl -s --max-time 3 "https://api.ipify.org" 2>/dev/null || echo "获取失败")
            echo -e "    ${GRAY}公网 IP: $public_ip${NC}"
        done <<< "$connected_vpns"
    else
        print_warning "当前没有连接的 VPN"
    fi

    echo
    return 0  # 总是返回成功，因为这只是状态显示
}

# 断开所有 VPN
disconnect_all() {
    print_title "断开所有 VPN 连接"
    echo

    local connected_vpns
    connected_vpns=$(get_connected_vpn)

    if [[ $? -ne 0 || -z "$connected_vpns" ]]; then
        print_info "当前没有连接的 VPN"
        return 0
    fi

    local disconnected_count=0
    while IFS= read -r vpn; do
        if disconnect_vpn "$vpn"; then
            ((disconnected_count++))
        fi
    done <<< "$connected_vpns"

    echo
    if [[ $disconnected_count -gt 0 ]]; then
        print_success "已断开 $disconnected_count 个 VPN 连接"
    else
        print_warning "没有成功断开任何 VPN 连接"
    fi
}

# 主连接流程
vpn_connect_workflow() {
    local vpns=()
    local vpn_list_output

    # 检查是否已有连接的 VPN
    local connected_vpns
    connected_vpns=$(get_connected_vpn)
    if [[ $? -eq 0 && -n "$connected_vpns" ]]; then
        echo
        print_warning "检测到已连接的 VPN:"
        while IFS= read -r vpn; do
            echo -e "  ${GREEN}${EMOJI_CONNECT}${NC} $vpn"
        done <<< "$connected_vpns"

        echo
        local choice
        read_user_input "${YELLOW}是否要断开现有连接? (y/N): ${NC}" choice

        if [[ "$choice" =~ ^[Yy]$ ]]; then
            disconnect_all
            echo
        fi
    fi

    # 显示 VPN 列表
    if ! show_vpn_list; then
        return 1
    fi

    # 获取 VPN 列表到数组
    vpn_list_output=$(get_vpn_list)
    while IFS= read -r line; do
        vpns+=("$line")
    done <<< "$vpn_list_output"

    # 用户选择
    local choice
    read_user_input "${CYAN}${EMOJI_SEARCH} 请输入数字编号 (1-${#vpns[@]}): ${NC}" choice

    # 验证输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt ${#vpns[@]} ]]; then
        print_error "无效选择，已取消"
        return 1
    fi

    # 获取选中的 VPN
    local selected_vpn="${vpns[$((choice-1))]}"

    # 获取密码
    local vpn_password
    read_user_input "${CYAN}${EMOJI_VPN} 请输入 VPN 密码: ${NC}" vpn_password true

    if [[ -z "$vpn_password" ]]; then
        print_error "密码不能为空"
        return 1
    fi

    echo

    # 连接 VPN
    connect_vpn "$selected_vpn" "$vpn_password" "$VPN_SECRET"
}

# 显示帮助信息
show_help() {
    print_title "VPN 连接管理工具 - 帮助"
    echo
    echo -e "${BOLD}用法:${NC}"
    echo -e "  $0 [选项]"
    echo
    echo -e "${BOLD}选项:${NC}"
    echo -e "  ${GREEN}-h, --help${NC}        显示此帮助信息"
    echo -e "  ${GREEN}-s, --status${NC}      显示当前 VPN 连接状态"
    echo -e "  ${GREEN}-d, --disconnect${NC}  断开所有 VPN 连接"
    echo -e "  ${GREEN}-l, --list${NC}        仅列出可用的 VPN 配置"
    echo
    echo -e "${BOLD}环境变量:${NC}"
    echo -e "  ${GREEN}VPN_SECRET${NC}        VPN 共享密钥 (默认: $VPN_SECRET)"
    echo
    echo -e "${BOLD}示例:${NC}"
    echo -e "  $0                    # 交互式连接 VPN"
    echo -e "  $0 --status           # 查看连接状态"
    echo -e "  $0 --disconnect       # 断开所有连接"
    echo -e "  VPN_SECRET=xxx $0     # 使用自定义密钥"
    echo
}

#######################################
#            主程序入口                 #
#######################################

# 主函数
main() {
    # 检查系统兼容性
    check_system_compatibility

    # 自动更新检查（如果有Token的话）
    if [[ -n "${GITLAB_TOKEN:-}" ]]; then
        local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
        if [[ -f "$sv_script" ]]; then
            # 使用子shell避免变量冲突
            (source "$sv_script" && check_script_update "vpn.sh") 2>/dev/null || true
        fi
    fi

    # 解析命令行参数
    case "${1:-}" in
        -h|--help)
            show_help
            ;;
        -u|--update)
            # 手动触发更新检查
            if [[ -n "${GITLAB_TOKEN:-}" ]]; then
                local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
                if [[ -f "$sv_script" ]]; then
                    # 使用子shell避免变量冲突
                    if (source "$sv_script" && check_script_update "vpn.sh") 2>/dev/null; then
                        exit 0
                    else
                        print_error_and_exit "更新检查失败"
                    fi
                else
                    print_error_and_exit "更新脚本不存在: $sv_script"
                fi
            else
                print_error_and_exit "未设置 GITLAB_TOKEN 环境变量，无法检查更新。请先使用 sv.sh -c 进行配置或运行 br.sh 脚本"
            fi
            ;;
        -s|--status)
            show_status
            ;;
        -d|--disconnect)
            disconnect_all
            ;;
        -l|--list)
            show_vpn_list
            ;;
        "")
            # 默认行为：启动连接流程
            vpn_connect_workflow
            ;;
        *)
            print_error_and_exit "未知选项: $1，使用 -h 查看帮助信息"
            ;;
    esac
}

# 脚本入口点
main "$@"