#!/bin/bash

# 脚本版本号 - 用于自动更新检测
readonly SCRIPT_VERSION="1.0.3"

#######################################
#            配置区域（修改这里）            #
#######################################

API_URL="https://gitlab.example.com/api/v4"
PROJECT_ID="664"
TOKEN="${GITLAB_TOKEN:-}"

# 任务执行失败后console日志的链接是否直接在浏览器打开 0关闭 1开启
open_in_default_browser=1

#######################################
#              颜色和图标定义             #
#######################################

# 颜色定义
readonly RED='\033[31m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly MAGENTA='\033[35m'
readonly CYAN='\033[36m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'

# Emoji 图标
readonly SUCCESS="✅"
readonly FAILED="❌"
readonly RUNNING="🔄"
readonly WAITING="⏳"
readonly WARNING="⚠️"
readonly ROCKET="🚀"
readonly SPARKLES="✨"
readonly GEAR="⚙️"
readonly EYES="👀"

#######################################
#              快捷命令配置              #
#######################################

# 快速模式 快捷命令配置（格式：参数名:REF值:项目名称）
PRESETS=(
  "c1:Gray1_CI:project-core"
  "c2:Gray2_CI:project-core"
  "c3:Gray3_CI:project-core"
  "c4:Gray4_CI:project-core"
  "c5:Gray5_CI:project-core"
  "c6:Gray6_CI:project-core"
  "c7:Preissue_CI:project-core"
  "c8:Preissue2_CI:project-core"
  "c9:VIP_CI:project-core"
  "f1:Gray1_CI:project-platform"
  "f2:Gray2_CI:project-platform"
  "f3:Gray3_CI:project-platform"
  "f4:Gray4_CI:project-platform"
  "f5:Gray5_CI:project-platform"
  "f6:Gray6_CI:project-platform"
  "f7:Preissue_CI:project-platform"
  "f8:Preissue2_CI:project-platform"
  "f9:VIP_CI:project-platform"
  "p1:Gray1_CI:project-pt"
  "p2:Gray2_CI:project-pt"
  "p3:Gray3_CI:project-pt"
  "p4:Gray4_CI:project-pt"
  "p5:Gray5_CI:project-pt"
  "p6:Gray6_CI:project-pt"
  "p7:Preissue_CI:project-pt"
  "p8:Preissue2_CI:project-pt"
  "p9:VIP_CI:project-pt"
  "i1:Gray1_CI:project-items-core"
  "i2:Gray2_CI:project-items-core"
  "i3:Gray3_CI:project-items-core"
  "i4:Gray4_CI:project-items-core"
  "i5:Gray5_CI:project-items-core"
  "i6:Gray6_CI:project-items-core"
  "i7:Preissue_CI:project-items-core"
  "i8:Preissue2_CI:project-items-core"
  "i9:VIP_CI:project-items-core"
)

# 可选的CI环境（REF）列表
REF_OPTIONS=(
  "Gray1_CI"
  "Gray2_CI"
  "Gray3_CI"
  "Gray4_CI"
  "Gray5_CI"
  "Gray6_CI"
  "Preissue_CI"
  "Preissue2_CI"
  "VIP_CI"
  "Gray3_INR_CI"
)

# 可选的CI项目列表
VALUE_OPTIONS=(
  "project-core"
  "project-platform"
  "project-pt"
  "project-items-core"
)

#######################################
#          核心逻辑（不要修改）            #
#######################################

# 全局变量
pipeline_ids=()
notified_pipelines=()

# 工具函数
log_info() {
  echo -e "${CYAN}${SPARKLES} $1${RESET}"
}

log_success() {
  echo -e "${GREEN}${SUCCESS} $1${RESET}"
}

log_error() {
  echo -e "${RED}${FAILED} $1${RESET}"
}

log_warning() {
  echo -e "${YELLOW}${WARNING} $1${RESET}"
}

open_browser() {
  if [ $open_in_default_browser -eq 1 ]; then
     open "$1" &
  fi
}

# 参数处理函数
show_help() {
  echo -e "${BOLD}${ROCKET} CI - CI/CD (流水线管理工具)${RESET}"
  echo -e "${CYAN}使用说明：${RESET}"
  echo -e "  ${BOLD}批量模式（默认）：${RESET} ci"
  echo -e "  ${BOLD}快速模式：${RESET}       ci [预设参数...]"
  echo -e "  ${BOLD}脚本更新：${RESET}       ci -u|--update"
  echo -e "  ${BOLD}帮助信息：${RESET}       ci -h|--help"
  echo ""
  echo -e "${CYAN}${GEAR} 可用预设参数：${RESET}"
  for preset in "${PRESETS[@]}"; do
    IFS=':' read -r key ref value <<< "$preset"
    printf "  ${YELLOW}%-5s${RESET} => ${MAGENTA}%-12s${RESET} + ${GREEN}%s${RESET}\n" "$key" "$ref" "$value"
  done
  echo ""
  echo -e "${CYAN}${SPARKLES} 快捷模式示例：${RESET}"
  echo -e "  ci c1           # 单个命令: Gray1_CI + project-core"
  echo -e "  ci c1 f5        # 多个命令: c1 和 f5"
  echo -e "  ci c123         # 连续命令: c1, c2, c3"
  echo -e "  ci c123 f56     # 组合命令: c1,c2,c3 和 f5,f6"
  echo -e "  ci              # 批量模式: 交互选择多个环境和项目"
  echo ""
  echo -e "${CYAN}${EYES} 首次使用会提示输入 GitLab Token，自动保存后续无需重复输入${RESET}"
  exit 0
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
        echo -e "${CYAN}${SPARKLES} 已更新环境变量 $var_name 在文件: $config_file${RESET}"
    else
        # 添加新的环境变量
        echo "" >> "$config_file"
        echo "# GitLab Token for project scripts" >> "$config_file"
        echo "export ${var_name}=\"${var_value}\"" >> "$config_file"
        log_success "已添加环境变量 $var_name 到文件: $config_file"
    fi

    # 立即设置到当前会话
    export "${var_name}=${var_value}"
    echo -e "${CYAN}${SPARKLES} 环境变量已在当前会话中生效${RESET}"
    echo -e "${YELLOW}${WARNING} 请重新打开终端或执行 'source $config_file' 使环境变量永久生效${RESET}"
}

# 检查并设置 TOKEN
check_and_set_token() {
  if [[ -z "$TOKEN" ]]; then
    echo -e "${YELLOW}${WARNING} 检测到未设置 GitLab Token${RESET}"
    echo -e "${CYAN}请输入您的 GitLab Personal Access Token:${RESET}"
    echo -e "${BLUE}(Token 将自动保存到环境变量中，下次无需重新输入)${RESET}"
    echo ""
    read -p "Token: " user_token

    if [[ -n "$user_token" ]]; then
      # 设置到环境变量
      set_env_variable "GITLAB_TOKEN" "$user_token"
      TOKEN="$user_token"
      echo ""
      log_success "Token 已保存到环境变量，继续执行..."
      echo ""
    else
      log_error "Token 不能为空"
      exit 1
    fi
  fi
}

# 解析快捷命令组合
parse_quick_commands() {
  local input="$1"
  local commands=()

  # 支持 c123456 这样的连续命令
  if [[ "$input" =~ ^[cfpi][0-9]+$ ]]; then
    local prefix="${input:0:1}"
    local numbers="${input:1}"
    for ((i=0; i<${#numbers}; i++)); do
      local num="${numbers:i:1}"
      if [[ "$num" =~ ^[1-9]$ ]]; then
        commands+=("${prefix}${num}")
      fi
    done
  else
    # 单个命令
    commands+=("$input")
  fi

  printf "%s\n" "${commands[@]}"
}

# 解析选项参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      ;;
    -u|--update)
      # 手动触发脚本更新检查
      if [[ -n "${GITLAB_TOKEN:-}" ]]; then
        local sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
        if [[ -f "$sv_script" ]]; then
          # 使用子shell避免变量冲突
          if (source "$sv_script" && check_script_update "ci.sh") 2>/dev/null; then
            log_success "脚本更新检查完成"
            exit 0
          else
            log_error "脚本更新检查失败"
            exit 1
          fi
        else
          log_error "更新脚本不存在: $sv_script"
          exit 1
        fi
      else
        log_error "未设置 GITLAB_TOKEN 环境变量，无法检查更新"
        echo -e "${CYAN}请先使用 sv.sh -c 进行配置${RESET}"
        exit 1
      fi
      ;;
    *)
      break
      ;;
  esac
  shift
done


# 触发流水线函数
trigger_pipeline() {
  local ref="$1"
  local value="$2"

  echo -e "${CYAN}${SPARKLES} 正在触发流水线 ${MAGENTA}$ref${RESET} → ${GREEN}$value${RESET}"

  JSON_DATA=$(cat <<EOF
{
  "ref": "$ref",
  "variables": [
    {
      "key": "project",
      "value": "$value"
    }
  ]
}
EOF
  )

  response=$(curl -sS -X POST \
    -H "PRIVATE-TOKEN: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$JSON_DATA" \
    "$API_URL/projects/$PROJECT_ID/pipeline")

  if [ $? -eq 0 ]; then
    pipeline_id=$(grep -o '"id":[0-9]*' <<< "$response" | cut -d':' -f2 | head -n1)

    response=$(curl -sS -X GET \
      -H "PRIVATE-TOKEN: $TOKEN" \
      "$API_URL/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs")

    web_url=$(grep -o '"web_url":"[^"]*' <<< "$response" | cut -d'"' -f4 | head -n3 | tail -n1)

    if [[ -n "$web_url" && -n "$pipeline_id" ]]; then
      echo -e "${GREEN}${SUCCESS} 流水线触发成功 ${MAGENTA}$ref${RESET} → ${GREEN}$value${RESET} ${BLUE}(ID: $pipeline_id)${RESET}"
      echo -e "${CYAN}${EYES} Console: ${BLUE}$web_url${RESET}"
      pipeline_ids+=("$pipeline_id")
      return 0
    else
      log_error "响应数据异常 $ref"
      echo "$response"
      return 1
    fi
  else
    log_error "请求失败 $ref"
    echo "详细错误："
    echo "$response"
    return 1
  fi
}

# 轮询任务状态函数，支持多个pipeline_id
poll_job_status() {
  local timeout=400
  local interval=5
  local all_done=0
  local has_failure=0
  local first_run=1

  log_info "开始监控任务状态... ${YELLOW}Ctrl+C${RESET} 可强制退出"

  for ((i=0; i<timeout; i+=interval)); do
    local status_output="${CYAN}${GEAR} === 实时任务状态 ===${RESET}\n"
    all_done=1
    has_failure=0

    for pipeline_id in "${pipeline_ids[@]}"; do
      response=$(curl -sS -X GET \
        -H "PRIVATE-TOKEN: $TOKEN" \
        "$API_URL/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs")

      local job_id=$(echo "$response" | grep -o '"id":[0-9]*' | cut -d':' -f2 | head -n1)
      job_name=($(grep -o '"name":"[^"]*' <<< "$response" | cut -d'"' -f4 | head -n1))
      status=($(grep -o '"status":"[^"]*' <<< "$response" | cut -d'"' -f4 | head -n1))
      duration=($(grep -o '"duration":[0-9]*' <<< "$response" | cut -d':' -f2 | head -n1))
      web_url=$(grep -o '"web_url":"[^"]*' <<< "$response" | cut -d'"' -f4 | head -n3 | tail -n1)

      case $status in
        "running")
          all_done=0
          status_output+="${BLUE}${RUNNING} ${job_name} → ${YELLOW}运行中${RESET} ${BLUE}(${duration}s | ID: $pipeline_id)${RESET}\n"
          ;;
        "success")
          status_output+="${GREEN}${SUCCESS} ${job_name} → ${GREEN}成功${RESET} ${BLUE}(${duration}s | ID: $pipeline_id)${RESET}\n"
          # 只在首次成功时发送通知
          if [[ ! " ${notified_pipelines[@]} " =~ " ${pipeline_id} " ]]; then
            echo $'\e]9;'"${SUCCESS} ${job_name} 成功 (${duration}s)"$'\007'
            notified_pipelines+=("$pipeline_id")
          fi
          ;;
        "failed")
          has_failure=1
          status_output+="${RED}${FAILED} ${job_name} → ${RED}失败${RESET} ${BLUE}(${duration}s | ID: $pipeline_id)${RESET}\n"
          # 只在首次失败时发送通知
          if [[ ! " ${notified_pipelines[@]} " =~ " ${pipeline_id} " ]]; then
            echo $'\e]9;'"${FAILED} ${job_name} 失败 (${duration}s)"$'\007'
            notified_pipelines+=("$pipeline_id")
          fi
          ;;
        "canceled")
          has_failure=1
          status_output+="${YELLOW}${WARNING} ${job_name} → ${YELLOW}已取消${RESET} ${BLUE}(${duration}s | ID: $pipeline_id)${RESET}\n"
          # 只在首次取消时发送通知
          if [[ ! " ${notified_pipelines[@]} " =~ " ${pipeline_id} " ]]; then
            echo $'\e]9;'"${WARNING} ${job_name} 已取消 (${duration}s)"$'\007'
            notified_pipelines+=("$pipeline_id")
          fi
          ;;
        *)
          all_done=0
          status_output+="${CYAN}${WAITING} ${job_name} → ${CYAN}等待中${RESET} ${BLUE}(ID: $pipeline_id)${RESET}\n"
          ;;
      esac
    done

    if [ $first_run -eq 1 ]; then
      echo -ne "$status_output"
      first_run=0
    else
      echo -ne "\033[$(( ${#pipeline_ids[@]} + 1 ))A\033[J"
      echo -ne "$status_output"
    fi

    # 判断终止条件
    if [ $has_failure -eq 1 ]; then
      echo ""
      log_error "发现失败任务！"
      for pipeline_id in "${pipeline_ids[@]}"; do
        response=$(curl -sS -X GET \
          -H "PRIVATE-TOKEN: $TOKEN" \
          "$API_URL/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs")

         local status=($(grep -o '"status":"[^"]*' <<< "$response" | cut -d'"' -f4 | head -n1))
         local web_url=$(grep -o '"web_url":"[^"]*' <<< "$response" | cut -d'"' -f4 | head -n3 | tail -n1)

        if [[ "$status" == "failed" || "$status" == "canceled" ]]; then
          echo -e "${RED}${EYES} 失败日志: ${BLUE}$web_url${RESET}"
          open_browser "$web_url"
        fi
      done
      return 1
    fi

    if [ $all_done -eq 1 ]; then
      echo ""
      log_success "所有任务执行成功！"
      for pipeline_id in "${pipeline_ids[@]}"; do
        web_url=$(curl -sS -X GET \
          -H "PRIVATE-TOKEN: $TOKEN" \
          "$API_URL/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs" | grep -o '"web_url":"[^"]*' | cut -d'"' -f4 | head -n3 | tail -n1)
        echo -e "${CYAN}${EYES} Console: ${BLUE}$web_url${RESET}"
      done
      return 0
    fi

    sleep $interval
  done

  echo ""
  log_warning "监测超时($(( timeout / 60 ))分钟)，请手动检查CI进度："
  for pipeline_id in "${pipeline_ids[@]}"; do
    web_url=$(curl -sS -X GET \
      -H "PRIVATE-TOKEN: $TOKEN" \
      "$API_URL/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs" | grep -o '"web_url":"[^"]*' | cut -d'"' -f4 | head -n3 | tail -n1)
    echo -e "${CYAN}${EYES} Console: ${BLUE}$web_url${RESET}"
  done
  return 2
}

# 交互选择函数（支持多选）
interactive_selector() {
  local prompt="$1"
  local multi_select="$2"
  shift 2
  local options=("$@")
  local selected=()

  echo -e "${CYAN}${prompt}${RESET}" >&2
  echo "" >&2

  # 显示选项列表
  for i in "${!options[@]}"; do
    printf "${YELLOW}%3d)${RESET} ${GREEN}%s${RESET}\n" $((i+1)) "${options[$i]}" >&2
  done

  echo "" >&2
  while true; do
    echo -ne "${BLUE}${GEAR} 请输入选项编号（多个用空格分隔）: ${RESET}" >&2
    read -a choices

    selected=()  # 重置选择数组
    for choice in "${choices[@]}"; do
      if [[ "$choice" =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#options[@]} ]]; then
        selected+=("${options[$((choice-1))]}")
      else
        echo -e "${RED}${WARNING} 无效选项: $choice 将被忽略${RESET}" >&2
      fi
    done

    if [ ${#selected[@]} -gt 0 ]; then
      if [ "$multi_select" == "single" ]; then
        echo "${selected[0]}"
        break
      else
        printf "%s\n" "${selected[@]}"
        break
      fi
    else
      echo -e "${RED}${WARNING} 至少需要选择一个有效选项${RESET}" >&2
    fi
  done
}

# 信号处理函数
cleanup() {
  echo ""
  log_warning "脚本被强制退出！"
  for pipeline_id in "${pipeline_ids[@]}"; do
    web_url=$(curl -sS -X GET \
      -H "PRIVATE-TOKEN: $TOKEN" \
      "$API_URL/projects/$PROJECT_ID/pipelines/$pipeline_id/jobs" | grep -o '"web_url":"[^"]*' | cut -d'"' -f4 | head -n3 | tail -n1)
    echo -e "${CYAN}${EYES} Console: ${BLUE}$web_url${RESET}"
    open_browser "$web_url"
  done
  exit 1
}

# 捕获 SIGINT (Ctrl+C) 和 SIGTERM (kill) 信号
trap cleanup SIGINT SIGTERM

# 检查脚本更新（如果有Token的话）
if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    sv_script="$(dirname "${BASH_SOURCE[0]}")/sv.sh"
    if [[ -f "$sv_script" ]]; then
        # 使用子shell避免变量冲突
        (source "$sv_script" && check_script_update "ci.sh") 2>/dev/null || true
    fi
fi

# 检查 Token
check_and_set_token

# 显示脚本名称含义
echo -e "${BOLD}${ROCKET} CI - CI/CD (流水线管理工具)${RESET}"
echo ""

# 处理快捷命令参数
if [ $# -ge 1 ]; then
  echo -e "${CYAN}${SPARKLES} 快捷模式 - 解析命令参数${RESET}"
  echo ""

  all_commands=()

  # 解析所有参数
  for arg in "$@"; do
    commands=($(parse_quick_commands "$arg"))
    all_commands+=("${commands[@]}")
  done

  # 验证并执行命令
  for cmd in "${all_commands[@]}"; do
    found=0
    for preset in "${PRESETS[@]}"; do
      IFS=':' read -r key preset_ref preset_value <<< "$preset"
      if [ "$cmd" == "$key" ]; then
        echo -e "${YELLOW}${GEAR} 执行命令: ${BOLD}$cmd${RESET} → ${MAGENTA}$preset_ref${RESET} + ${GREEN}$preset_value${RESET}"
        trigger_pipeline "$preset_ref" "$preset_value"
        found=1
        break
      fi
    done

    if [ $found -eq 0 ]; then
      log_error "无效预设参数: $cmd"
      echo -e "${CYAN}${SPARKLES} 使用 ${YELLOW}ci -h${RESET} 查看可用预设参数"
      exit 1
    fi
  done

else
  # 批量模式处理（默认模式）
  echo -e "${BOLD}${ROCKET} CI - CI/CD (流水线管理工具)${RESET}"
  echo ""
  echo -e "${CYAN}${SPARKLES} 批量模式 - 可同时选择多个环境和项目${RESET}"
  echo ""

  # 多选REF
  selected_refs=($(interactive_selector "${GEAR} 请选择要触发的REF分支（可多选）：" "multi" "${REF_OPTIONS[@]}"))

  echo ""

  # 多选VALUE并用逗号拼接
  selected_values=($(interactive_selector "${ROCKET} 请选择要设置的变量值（可多选）：" "multi" "${VALUE_OPTIONS[@]}"))
  joined_values=$(IFS=,; echo "${selected_values[*]}")

  echo ""
  echo -e "${CYAN}${SPARKLES} 开始触发流水线...${RESET}"
  echo ""

  # 循环触发所有选中的REF
  for ref in "${selected_refs[@]}"; do
    trigger_pipeline "$ref" "$joined_values"
  done
fi

# 开始监控任务状态
if [ ${#pipeline_ids[@]} -gt 0 ]; then
  echo ""
  poll_job_status
  echo ""
  log_success "所有任务执行完成！"
else
  log_error "没有成功触发任何流水线"
  exit 1
fi

