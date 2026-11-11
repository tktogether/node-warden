#!/usr/bin/env bash
# Node Warden Toolbox 总入口。
# 统一管理常用工具、Node Warden 安装和 BBR 配置。

set -Eeuo pipefail

TOOLBOX_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

MODULES_DIR="$TOOLBOX_ROOT/toolbox/modules"
TOOLBOX_VERSION="unknown"
if [[ -r "$TOOLBOX_ROOT/VERSION" ]]; then
  TOOLBOX_VERSION=$(tr -d '[:space:]' < "$TOOLBOX_ROOT/VERSION")
fi

usage() {
  cat <<'EOF'
Node Warden Toolbox

用法：
  sudo bash toolbox.sh                         交互式菜单
  sudo bash toolbox.sh list                    列出功能目录
  sudo bash toolbox.sh common [工具] [参数]     常用工具
  sudo bash toolbox.sh node-warden [操作]       安装、更新、卸载 Node Warden
  sudo bash toolbox.sh bbr [操作]               BBR 配置与测试
  sudo bash toolbox.sh self-test               检查脚本语法和模块清单
  sudo bash toolbox.sh help                    显示本帮助

常用工具：
  sudo bash toolbox.sh common system-info
  sudo bash toolbox.sh common net-bench 1.1.1.1
  sudo bash toolbox.sh common docker-mirror-speedtest
  sudo bash toolbox.sh common dns-check github.com
  sudo bash toolbox.sh common port-check 443
  sudo bash toolbox.sh common github-speedtest
  sudo bash toolbox.sh common cert-check example.com
  sudo bash toolbox.sh common disk-usage
  sudo bash toolbox.sh common docker-info

Node Warden：
  sudo bash toolbox.sh node-warden install
  sudo bash toolbox.sh node-warden update
  sudo bash toolbox.sh node-warden status
  sudo bash toolbox.sh node-warden uninstall

BBR：
  sudo bash toolbox.sh bbr status
  sudo bash toolbox.sh bbr install
  sudo bash toolbox.sh bbr rollback
  sudo bash toolbox.sh bbr schemes
  sudo bash toolbox.sh bbr benchmark --peer 203.0.113.10 --seconds 15

说明：
  读取类工具可以直接运行；安装、配置和测试类操作需要 root 权限。
  所有操作不使用 shell 拼接执行外部输入，参数会经过校验。
EOF
}

module_ids() {
  local dir id
  for dir in "$MODULES_DIR"/*; do
    [[ -d "$dir" && -f "$dir/module.sh" ]] || continue
    id=$(basename -- "$dir")
    printf '%s\n' "$id"
  done
}

list_modules() {
  local id dir title
  printf '功能目录：\n'
  for id in $(module_ids); do
    dir="$MODULES_DIR/$id"
    title=$(
      unset MODULE_ID MODULE_TITLE MODULE_DESCRIPTION
      # shellcheck source=/dev/null
      source "$dir/module.sh" >/dev/null 2>&1 || true
      printf '%s' "${MODULE_TITLE:-$id}"
    )
    printf '  %-14s %s\n' "$id" "$title"
  done
}

load_module() {
  local id=$1
  MODULE_DIR="$MODULES_DIR/$id"
  if [[ ! -f "$MODULE_DIR/module.sh" ]]; then
    die "功能目录不存在：$id"
  fi
  # shellcheck source=/dev/null
  source "$MODULE_DIR/module.sh"
  if [[ "${MODULE_ID:-}" != "$id" ]]; then
    die "功能目录标识不一致：$id"
  fi
}

run_module() {
  local id=$1
  shift
  load_module "$id"
  if [[ $# -eq 0 ]]; then
    if is_tty; then
      module_menu
    else
      module_run list
    fi
  else
    module_run "$@"
  fi
}

main_menu() {
  local ids=() id choice i
  while IFS= read -r id; do
    ids+=("$id")
  done < <(module_ids)
  if (( ${#ids[@]} == 0 )); then
    die "没有找到功能目录。"
  fi
  printf '\nNode Warden Toolbox %s\n' "$TOOLBOX_VERSION"
  printf '请选择功能目录：\n'
  for i in "${!ids[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${ids[$i]}"
  done
  printf '  0) 退出\n'
  read -r -p '选择: ' choice || exit 0
  if [[ "$choice" == "0" || "$choice" == "q" ]]; then
    exit 0
  fi
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#ids[@]} )); then
    warn "无效选择。"
    return 1
  fi
  run_module "${ids[$((choice - 1))]}"
}

self_test() {
  local file failed=0
  for file in \
    "$TOOLBOX_ROOT/toolbox.sh" \
    "$TOOLBOX_ROOT/toolbox/lib/common.sh" \
    "$TOOLBOX_ROOT"/toolbox/modules/*/module.sh \
    "$TOOLBOX_ROOT"/toolbox/modules/*/tools/*.sh \
    "$TOOLBOX_ROOT"/toolbox/modules/bbr/*.sh; do
    [[ -f "$file" ]] || continue
    if bash -n "$file"; then
      printf '  OK   %s\n' "${file#$TOOLBOX_ROOT/}"
    else
      failed=1
    fi
  done
  list_modules
  if (( failed != 0 )); then
    error "存在语法错误。"
    return 1
  fi
  info "语法和模块清单检查通过。"
}

main() {
  if [[ $# -eq 0 ]]; then
    if is_tty; then
      main_menu
      return 0
    fi
    usage
    return 1
  fi
  case "$1" in
    help|--help|-h)
      usage
      ;;
    version|--version)
      printf 'Node Warden Toolbox %s\n' "$TOOLBOX_VERSION"
      ;;
    list|--list)
      list_modules
      ;;
    self-test)
      self_test
      ;;
    *)
      run_module "$@"
      ;;
  esac
}

main "$@"
