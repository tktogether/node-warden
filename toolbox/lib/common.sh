#!/usr/bin/env bash
# Node Warden Toolbox 公共函数库。
# 只提供通用检查、日志和文件辅助函数，不执行服务操作。

if [[ -n "${TOOLBOX_COMMON_LOADED:-}" ]]; then
  return 0
fi
TOOLBOX_COMMON_LOADED=1

if [[ -t 1 ]]; then
  TOOLBOX_C_RESET=$'\033[0m'
  TOOLBOX_C_INFO=$'\033[32m'
  TOOLBOX_C_WARN=$'\033[33m'
  TOOLBOX_C_ERROR=$'\033[31m'
  TOOLBOX_C_TITLE=$'\033[36m'
else
  TOOLBOX_C_RESET=""
  TOOLBOX_C_INFO=""
  TOOLBOX_C_WARN=""
  TOOLBOX_C_ERROR=""
  TOOLBOX_C_TITLE=""
fi

log() {
  local level=$1 color=$2
  shift 2
  printf '%s[%s]%s %s\n' "$color" "$level" "$TOOLBOX_C_RESET" "$*"
}

info() { log "信息" "$TOOLBOX_C_INFO" "$*"; }
warn() { log "注意" "$TOOLBOX_C_WARN" "$*" >&2; }
error() { log "错误" "$TOOLBOX_C_ERROR" "$*" >&2; }
die() { error "$*"; exit 1; }

section() {
  printf '\n%s== %s ==%s\n' "$TOOLBOX_C_TITLE" "$*" "$TOOLBOX_C_RESET"
}

kv() {
  printf '  %-26s %s\n' "$1" "$2"
}

is_tty() {
  [[ -t 0 && -t 1 ]]
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "此操作需要 root 权限，请使用 sudo 运行。"
  fi
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

require_cmd() {
  have_cmd "$1" || die "缺少命令：$1"
}

confirm() {
  local prompt=$1
  local answer=""
  if [[ "${TOOLBOX_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  if ! is_tty; then
    return 1
  fi
  read -r -p "$prompt [y/N] " answer || answer=""
  [[ "$answer" == "y" || "$answer" == "Y" || "$answer" == "yes" || "$answer" == "YES" ]]
}

backup_file() {
  local src=$1
  local dir base stamp dest
  [[ -e "$src" ]] || return 0
  dir=$(dirname -- "$src")
  base=$(basename -- "$src")
  stamp=$(date +%Y%m%d-%H%M%S)
  dest="$dir/$base.bak-toolbox-$stamp"
  cp -a -- "$src" "$dest"
  printf '%s\n' "$dest"
}

github_raw_jsdelivr() {
  local url=$1 rest owner repo ref path
  case "$url" in
    https://raw.githubusercontent.com/*) rest=${url#https://raw.githubusercontent.com/} ;;
    *) return 1 ;;
  esac
  owner=${rest%%/*}
  rest=${rest#*/}
  repo=${rest%%/*}
  rest=${rest#*/}
  ref=${rest%%/*}
  path=${rest#*/}
  if [[ -z "$owner" || -z "$repo" || -z "$ref" || "$path" == "$rest" || -z "$path" ]]; then
    return 1
  fi
  printf 'https://cdn.jsdelivr.net/gh/%s/%s@%s/%s\n' "$owner" "$repo" "$ref" "$path"
  printf 'https://cdn.statically.io/gh/%s/%s/%s/%s\n' "$owner" "$repo" "$ref" "$path"
}

github_url_candidates() {
  local url=$1 proxy=${NW_GITHUB_PROXY:-}
  printf '%s\n' "$url"
  case "$url" in
    https://github.com/*|https://raw.githubusercontent.com/*|https://codeload.github.com/*|https://api.github.com/*|https://gist.github.com/*|https://objects.githubusercontent.com/*) ;;
    *) return 0 ;;
  esac
  if [[ -n "$proxy" ]]; then
    printf '%s/%s\n' "${proxy%/}" "$url"
  fi
  printf 'https://ghfast.top/%s\n' "$url"
  printf 'https://gh-proxy.com/%s\n' "$url"
  printf 'https://ghproxy.net/%s\n' "$url"
  case "$url" in
    https://raw.githubusercontent.com/*) github_raw_jsdelivr "$url" || true ;;
  esac
}

fetch_url() {
  local url=$1
  local dest=$2
  local tmp="${dest}.part.$$"
  mkdir -p "$(dirname -- "$dest")"
  if have_cmd curl; then
    curl -fL --retry 2 --retry-delay 2 --connect-timeout 10 --max-time 180 -o "$tmp" "$url" || {
      rm -f "$tmp"
      return 1
    }
  elif have_cmd wget; then
    wget -q --tries=2 --timeout=30 -O "$tmp" "$url" || {
      rm -f "$tmp"
      return 1
    }
  else
    return 1
  fi
  mv -f -- "$tmp" "$dest"
}

download_file() {
  local url=$1 dest=$2
  if ! have_cmd curl && ! have_cmd wget; then
    die "缺少 curl 或 wget，无法下载：$url"
  fi
  fetch_url "$url" "$dest" || die "下载失败：$url"
}

download_github() {
  local url=$1 dest=$2 candidate
  local -a candidates=()
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] && candidates+=("$candidate")
  done < <(github_url_candidates "$url")
  for candidate in "${candidates[@]}"; do
    if fetch_url "$candidate" "$dest"; then
      return 0
    fi
    warn "下载失败，尝试下一个地址：$candidate"
  done
  die "下载失败：$url"
}

pkg_manager() {
  if have_cmd apt-get; then
    printf 'apt\n'
  elif have_cmd dnf; then
    printf 'dnf\n'
  elif have_cmd yum; then
    printf 'yum\n'
  elif have_cmd apk; then
    printf 'apk\n'
  else
    printf 'unknown\n'
  fi
}

os_id() {
  local id="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    id=$(. /etc/os-release; printf '%s' "${ID:-unknown}")
  fi
  printf '%s\n' "$id"
}

os_version() {
  local version="unknown"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    version=$(. /etc/os-release; printf '%s' "${VERSION_ID:-unknown}")
  fi
  printf '%s\n' "$version"
}

validate_host() {
  local host=$1
  [[ "$host" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$ ]]
}

validate_port() {
  local port=$1
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

validate_seconds() {
  local seconds=$1
  [[ "$seconds" =~ ^[0-9]+$ ]] && (( seconds >= 1 && seconds <= 3600 ))
}

pause_if_tty() {
  if is_tty; then
    read -r -p "按回车继续..." _ || true
  fi
}
