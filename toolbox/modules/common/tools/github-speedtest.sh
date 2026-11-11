#!/usr/bin/env bash
# 测试 GitHub 主要下载入口的响应时间和下载速度。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

require_cmd curl

URLS=(
  "https://raw.githubusercontent.com/tktogether/node-warden/main/VERSION"
  "https://api.github.com/repos/tktogether/node-warden"
  "https://codeload.github.com/tktogether/node-warden/tar.gz/refs/heads/main"
)

if [[ $# -gt 0 ]]; then
  URLS=("$@")
fi

for url in "${URLS[@]}"; do
  if [[ ! "$url" =~ ^https:// ]]; then
    warn "跳过非 HTTPS 地址：$url"
    continue
  fi
  section "$url"
  result=$(curl -sS -L --connect-timeout 10 --max-time 45 -o /dev/null \
    -w '%{http_code} %{time_connect} %{time_total} %{size_download} %{speed_download}' \
    "$url" 2>&1) || {
    warn "请求失败：$result"
    continue
  }
  read -r code connect total size speed <<< "$result"
  kv "HTTP 状态" "$code"
  kv "连接时间" "${connect}s"
  kv "总时间" "${total}s"
  kv "下载大小" "$(awk -v b="$size" 'BEGIN { printf "%.2f MB", b / 1048576 }')"
  kv "下载速度" "$(awk -v s="$speed" 'BEGIN { printf "%.2f MB/s", s / 1048576 }')"
done
