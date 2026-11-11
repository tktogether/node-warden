#!/usr/bin/env bash
# Node Warden Toolbox 总入口。
# 统一管理常用工具、Node Warden 安装和 BBR 配置。
# 单独运行本文件时，会自动获取仓库源码后继续，不需要手工下载。

set -Eeuo pipefail

SELF_SOURCE=${BASH_SOURCE[0]:-}
SELF_DIR=$(cd -- "$(dirname -- "$SELF_SOURCE")" 2>/dev/null && pwd -P || printf '.')
TOOLBOX_REPO=${NW_REPO:-tktogether/node-warden}
TOOLBOX_BRANCH=${NW_BRANCH:-main}
TOOLBOX_ARCHIVE_URL=${NW_TOOLBOX_ARCHIVE_URL:-${NW_ARCHIVE_URL:-}}
TOOLBOX_ARCHIVE_URLS=${NW_TOOLBOX_ARCHIVE_URLS:-${NW_ARCHIVE_URLS:-}}
TOOLBOX_GITHUB_PROXY=${NW_GITHUB_PROXY:-}

toolbox_download() {
  local url=$1 dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 180 --retry 1 --retry-delay 2 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=2 --timeout=30 -O "$dest" "$url"
  else
    return 1
  fi
}

toolbox_fetch_source() {
  local tmp=$1 url
  local direct="https://github.com/${TOOLBOX_REPO}/archive/refs/heads/${TOOLBOX_BRANCH}.tar.gz"
  local codeload="https://codeload.github.com/${TOOLBOX_REPO}/tar.gz/refs/heads/${TOOLBOX_BRANCH}"
  local -a urls=()

  if [[ -n "$TOOLBOX_ARCHIVE_URLS" ]]; then
    # 允许使用空格分隔多个地址。
    # shellcheck disable=SC2206
    urls+=($TOOLBOX_ARCHIVE_URLS)
  fi
  if [[ -n "$TOOLBOX_ARCHIVE_URL" ]]; then
    urls+=("$TOOLBOX_ARCHIVE_URL")
  fi
  urls+=("$direct" "$codeload")
  if [[ -n "$TOOLBOX_GITHUB_PROXY" ]]; then
    urls+=("${TOOLBOX_GITHUB_PROXY%/}/$direct" "${TOOLBOX_GITHUB_PROXY%/}/$codeload")
  fi
  urls+=("https://ghfast.top/$direct" "https://gh-proxy.com/$direct")

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    printf '错误：需要 curl 或 wget 才能自动获取工具箱源码。\n' >&2
    printf 'Ubuntu/Debian：apt-get update && apt-get install -y curl\n' >&2
    return 1
  fi
  if ! command -v tar >/dev/null 2>&1; then
    printf '错误：需要 tar 才能解压工具箱源码。\n' >&2
    return 1
  fi

  for url in "${urls[@]}"; do
    [[ -n "$url" ]] || continue
    printf '获取工具箱源码：%s\n' "$url"
    rm -f "$tmp/source.tar.gz"
    if ! toolbox_download "$url" "$tmp/source.tar.gz"; then
      printf '下载失败，尝试下一个地址。\n' >&2
      continue
    fi
    if tar -tzf "$tmp/source.tar.gz" >/dev/null 2>&1; then
      return 0
    fi
    printf '下载内容不是有效压缩包，尝试下一个地址。\n' >&2
  done
  return 1
}

toolbox_bootstrap_self() {
  local tmp root
  tmp=$(mktemp -d)
  if ! toolbox_fetch_source "$tmp"; then
    rm -rf "$tmp"
    printf '错误：无法获取工具箱源码。\n' >&2
    printf '可设置 NW_ARCHIVE_URL 指向可访问的源码压缩包，或设置 NW_GITHUB_PROXY。\n' >&2
    exit 1
  fi
  if ! tar -xzf "$tmp/source.tar.gz" -C "$tmp"; then
    rm -rf "$tmp"
    printf '错误：工具箱源码解压失败。\n' >&2
    exit 1
  fi
  root=$(find "$tmp" -maxdepth 5 -type f -name toolbox.sh -print -quit 2>/dev/null || true)
  if [[ -z "$root" ]]; then
    rm -rf "$tmp"
    printf '错误：源码压缩包中没有 toolbox.sh。\n' >&2
    exit 1
  fi
  root=$(dirname -- "$root")
  if [[ ! -r "$root/toolbox/lib/common.sh" ]]; then
    rm -rf "$tmp"
    printf '错误：源码压缩包不完整。\n' >&2
    exit 1
  fi
  rm -f "$tmp/source.tar.gz"
  if [[ ! -t 0 ]] && ( exec </dev/tty ) 2>/dev/null; then
    exec bash "$root/toolbox.sh" "$@" < /dev/tty
  fi
  exec bash "$root/toolbox.sh" "$@"
}

if [[ ! -r "$SELF_DIR/toolbox/lib/common.sh" ]]; then
  toolbox_bootstrap_self "$@"
fi

TOOLBOX_ROOT=$SELF_DIR
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
  sudo bash toolbox.sh                          交互式菜单
  sudo bash toolbox.sh install [选项]            一键安装 Node Warden（面板、GitHub 代理、Docker 代理）
  sudo bash toolbox.sh update [选项]             更新 Node Warden
  sudo bash toolbox.sh status                    查看 Node Warden 状态
  sudo bash toolbox.sh uninstall [选项]          卸载 Node Warden
  sudo bash toolbox.sh common [工具] [参数]      常用工具
  sudo bash toolbox.sh bbr [操作]                BBR 配置与测试
  sudo bash toolbox.sh cn-setup                  国内网络设置
  sudo bash toolbox.sh cn-restore                恢复国内网络设置
  sudo bash toolbox.sh remote                    显示远程运行命令
  sudo bash toolbox.sh self-test                 检查脚本语法和模块清单
  sudo bash toolbox.sh help                      显示本帮助

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

安装示例：
  sudo bash toolbox.sh install
  sudo bash toolbox.sh install --public-url https://panel.example.com/warden
  sudo bash toolbox.sh install --panel-only --yes
  sudo bash toolbox.sh update

远程运行（不需要手工下载源码）：
  sudo bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/toolbox.sh)
  sudo bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/toolbox.sh) install

说明：
  读取类工具可以直接运行；安装、配置和测试类操作需要 root 权限。
  单独运行 toolbox.sh 时会自动获取源码；在仓库内运行时不下载。
EOF
}

remote_command() {
  printf '远程运行命令：\n'
  printf '  sudo bash <(curl -fsSL https://raw.githubusercontent.com/%s/%s/toolbox.sh)\n' "$TOOLBOX_REPO" "$TOOLBOX_BRANCH"
  printf '  sudo bash <(curl -fsSL https://raw.githubusercontent.com/%s/%s/toolbox.sh) install\n' "$TOOLBOX_REPO" "$TOOLBOX_BRANCH"
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

run_node_action() {
  ( run_module node-warden "$@" )
}

menu_action() {
  local rc=0
  set +e
  ( "$@" )
  rc=$?
  set -e
  if (( rc != 0 )); then
    warn "操作未完成（退出码 $rc）。"
  fi
}

main_menu() {
  local choice
  while true; do
    printf '\nNode Warden Toolbox %s\n' "$TOOLBOX_VERSION"
    printf '请选择操作：\n'
    printf '  1) 一键安装或重新配置 Node Warden\n'
    printf '  2) 更新 Node Warden\n'
    printf '  3) 查看 Node Warden 状态\n'
    printf '  4) 卸载 Node Warden\n'
    printf '  5) 常用工具\n'
    printf '  6) BBR 配置与测试\n'
    printf '  7) 国内网络设置\n'
    printf '  8) 恢复国内网络设置\n'
    printf '  9) 运行工具箱自检\n'
    printf '  0) 退出\n'
    if ! read -r -p '选择: ' choice; then
      return 0
    fi
    case "$choice" in
      0|q) return 0 ;;
      1) menu_action run_module node-warden install ;;
      2) menu_action run_module node-warden update ;;
      3) menu_action run_module node-warden status ;;
      4) menu_action run_module node-warden uninstall ;;
      5) menu_action run_module common ;;
      6) menu_action run_module bbr ;;
      7) menu_action run_module node-warden cn-setup ;;
      8) menu_action run_module node-warden cn-restore ;;
      9) menu_action self_test ;;
      *) warn "无效选择。" ;;
    esac
    pause_if_tty
  done
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
    remote)
      remote_command
      ;;
    self-test)
      self_test
      ;;
    install|update|status|uninstall|cn-setup|cn-restore)
      run_node_action "$@"
      ;;
    common|tools)
      shift
      run_module common "$@"
      ;;
    bbr)
      shift
      run_module bbr "$@"
      ;;
    node-warden)
      shift
      run_module node-warden "$@"
      ;;
    *)
      run_module "$@"
      ;;
  esac
}

main "$@"
