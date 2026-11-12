#!/usr/bin/env bash
# Node Warden Toolbox 转发脚本。
# 工具箱已独立为 tktogether/warden-toolbox 仓库；本文件保留 bash toolbox.sh <操作> 的旧用法，
# 下载独立仓库的 toolbox.sh 并转发全部参数。
set -Eeuo pipefail

TOOLBOX_REPO=${TOOLBOX_REPO:-tktogether/warden-toolbox}
TOOLBOX_BRANCH=${TOOLBOX_BRANCH:-main}
TOOLBOX_URL=${WARDEN_TOOLBOX_URL:-https://raw.githubusercontent.com/$TOOLBOX_REPO/$TOOLBOX_BRANCH/toolbox.sh}
TOOLBOX_LOCAL=${WARDEN_TOOLBOX_LOCAL:-}

TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

info() { printf '[信息] %s\n' "$*" >&2; }
fail() { printf '[错误] %s\n' "$*" >&2; exit 1; }

fetch() {
  local url=$1 dest=$2
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 90 --retry 0 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --tries=1 --timeout=30 -O "$dest" "$url"
  else
    return 1
  fi
}

candidates() {
  printf '%s\n' "$TOOLBOX_URL"
  printf 'https://gh-proxy.com/%s\n' "$TOOLBOX_URL"
  printf 'https://ghfast.top/%s\n' "$TOOLBOX_URL"
  printf 'https://ghproxy.net/%s\n' "$TOOLBOX_URL"
}

run_local() {
  local script=$1
  shift
  [[ -r "$script" ]] || fail "WARDEN_TOOLBOX_LOCAL 指向的文件不可用：$script"
  info "Node Warden Toolbox 已独立为 $TOOLBOX_REPO，转发到独立工具箱执行。"
  bash "$script" "$@"
}

main() {
  if [[ -n "$TOOLBOX_LOCAL" ]]; then
    run_local "$TOOLBOX_LOCAL" "$@"
    return $?
  fi
  TMP_DIR=$(mktemp -d 2>/dev/null) || fail "无法创建临时目录。"
  local candidate="${TMP_DIR}/toolbox.sh" found="" url=""
  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    info "获取工具箱：$url"
    if fetch "$url" "$candidate" && [[ -s "$candidate" ]]; then
      found=$candidate
      break
    fi
    rm -f -- "$candidate"
  done < <(candidates)
  [[ -n "$found" ]] || fail "未能获取工具箱脚本。可设置 WARDEN_TOOLBOX_URL 指定地址，或访问 https://github.com/$TOOLBOX_REPO 手动下载。"
  local first_line=""
  IFS= read -r first_line < "$found" || true
  [[ "$first_line" == '#!'* ]] || fail "获取的工具箱脚本格式不正确。"
  info "Node Warden Toolbox 已独立为 $TOOLBOX_REPO，转发到独立工具箱执行。"
  bash "$found" "$@"
}

main "$@"