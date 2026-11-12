#!/usr/bin/env bash
# Node Warden 功能目录：直接调用仓库根目录的 bootstrap.sh。

if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
  TOOLBOX_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
  export TOOLBOX_ROOT
fi
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

MODULE_ID="node-warden"
MODULE_TITLE="Node Warden"
MODULE_DESCRIPTION="安装、更新、卸载和检查 Node Warden 面板、GitHub 代理与 Docker 代理。"
BOOTSTRAP="$TOOLBOX_ROOT/bootstrap.sh"

module_list() {
  printf 'Node Warden 操作：\n'
  printf '  %-14s %s\n' "install" "从零安装或重新配置"
  printf '  %-14s %s\n' "update" "更新已安装的 Node Warden"
  printf '  %-14s %s\n' "status" "显示组件和端口状态"
  printf '  %-14s %s\n' "uninstall" "卸载组件"
  printf '  %-14s %s\n' "self-test" "运行安装器自检"
  printf '  %-14s %s\n' "cn-setup" "国内网络设置"
  printf '  %-14s %s\n' "cn-restore" "恢复国内网络设置"
}

module_run() {
  local action="${1:-}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$action" in
    ""|list)
      module_list
      ;;
    install|update|status|uninstall|self-test|cn-setup|cn-restore)
      if [[ ! -f "$BOOTSTRAP" ]]; then
        die "未找到 bootstrap.sh：$BOOTSTRAP"
      fi
      require_root
      exec bash "$BOOTSTRAP" "$action" "$@"
      ;;
    remote)
      local url
      printf '远程运行命令（按可用性选择）：\n'
      while IFS= read -r url; do
        printf '  curl -fsSL %s -o /tmp/node-warden-toolbox.sh && sudo bash /tmp/node-warden-toolbox.sh\n' "$url"
      done < <(github_url_candidates 'https://raw.githubusercontent.com/tktogether/node-warden/main/toolbox.sh')
      printf '\n安装 Node Warden：在命令末尾加 install。\n'
      ;;
    help|--help|-h)
      module_list
      printf '\n示例：\n'
      printf '  sudo bash toolbox.sh node-warden install\n'
      printf '  sudo bash toolbox.sh node-warden update\n'
      printf '  sudo bash toolbox.sh node-warden status\n'
      ;;
    *)
      die "未知操作：$action"
      ;;
  esac
}

module_menu() {
  local choice
  while true; do
    printf '\nNode Warden\n'
    printf '  1) install      从零安装或重新配置\n'
    printf '  2) update       更新已安装的 Node Warden\n'
    printf '  3) status       显示组件和端口状态\n'
    printf '  4) self-test    运行安装器自检\n'
    printf '  5) uninstall    卸载组件\n'
    printf '  6) cn-setup     国内网络设置\n'
    printf '  7) cn-restore   恢复国内网络设置\n'
    printf '  0) 返回\n'
    read -r -p '选择: ' choice || return 0
    case "$choice" in
      0|q) return 0 ;;
      1) module_run install ;;
      2) module_run update ;;
      3) module_run status ;;
      4) module_run self-test ;;
      5) module_run uninstall ;;
      6) module_run cn-setup ;;
      7) module_run cn-restore ;;
      *) warn "无效选择。" ;;
    esac
  done
}
