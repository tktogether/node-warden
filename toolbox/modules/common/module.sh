#!/usr/bin/env bash
# 常用工具功能目录。

if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
  TOOLBOX_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
  export TOOLBOX_ROOT
fi
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

MODULE_ID="common"
MODULE_TITLE="常用工具"
MODULE_DESCRIPTION="系统信息、网络测试、镜像测速、DNS、端口、证书和 Docker 状态。"
TOOLBOX_MODULE_DIR="$TOOLBOX_ROOT/toolbox/modules/common"

COMMON_TOOLS=(
  "system-info"
  "net-bench"
  "docker-mirror-speedtest"
  "dns-check"
  "port-check"
  "github-speedtest"
  "cert-check"
  "disk-usage"
  "docker-info"
)

common_tool_title() {
  case "$1" in
    system-info) printf '系统信息\n' ;;
    net-bench) printf '网络测试\n' ;;
    docker-mirror-speedtest) printf 'Docker 镜像测速\n' ;;
    dns-check) printf 'DNS 检查\n' ;;
    port-check) printf '端口检查\n' ;;
    github-speedtest) printf 'GitHub 下载测速\n' ;;
    cert-check) printf 'TLS 证书检查\n' ;;
    disk-usage) printf '磁盘占用\n' ;;
    docker-info) printf 'Docker 状态\n' ;;
    *) printf '未知工具\n' ;;
  esac
}

common_tool_path() {
  local id=$1
  local path="$TOOLBOX_MODULE_DIR/tools/$id.sh"
  if [[ ! -f "$path" ]]; then
    die "工具不存在：$id"
  fi
  printf '%s\n' "$path"
}

module_list() {
  local id
  printf '常用工具：\n'
  for id in "${COMMON_TOOLS[@]}"; do
    printf '  %-24s %s\n' "$id" "$(common_tool_title "$id")"
  done
}

module_run_tool() {
  local id=$1
  shift
  local path
  path=$(common_tool_path "$id")
  bash "$path" "$@"
}

module_run() {
  case "${1:-}" in
    ""|list)
      module_list
      ;;
    run)
      shift
      if [[ $# -lt 1 ]]; then
        die "用法：common run <工具> [参数]"
      fi
      module_run_tool "$@"
      ;;
    *)
      module_run_tool "$@"
      ;;
  esac
}

module_menu() {
  local choice id i
  printf '\n常用工具\n'
  for i in "${!COMMON_TOOLS[@]}"; do
    id="${COMMON_TOOLS[$i]}"
    printf '  %d) %-24s %s\n' "$((i + 1))" "$id" "$(common_tool_title "$id")"
  done
  printf '  0) 返回\n'
  read -r -p '选择: ' choice || return 0
  if [[ "$choice" == "0" || "$choice" == "q" ]]; then
    return 0
  fi
  if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
    warn "无效选择。"
    return 1
  fi
  i=$((choice - 1))
  if (( i < 0 || i >= ${#COMMON_TOOLS[@]} )); then
    warn "无效选择。"
    return 1
  fi
  id="${COMMON_TOOLS[$i]}"
  module_run_tool "$id"
  pause_if_tty
}
