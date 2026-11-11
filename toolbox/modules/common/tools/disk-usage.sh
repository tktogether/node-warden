#!/usr/bin/env bash
# 输出文件系统、主要目录、日志和 Docker 的磁盘占用。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

section "文件系统"
df -hT

section "根目录一级占用"
if have_cmd du; then
  timeout 60 du -xhd1 / 2>/dev/null | sort -h | tail -n 15 || true
else
  warn "缺少 du。"
fi

section "日志占用"
if have_cmd journalctl; then
  journalctl --disk-usage 2>/dev/null || true
fi
if [[ -d /var/log ]]; then
  timeout 30 du -xhd1 /var/log 2>/dev/null | sort -h | tail -n 10 || true
fi

section "Docker 占用"
if have_cmd docker && docker info >/dev/null 2>&1; then
  docker system df
else
  info "Docker 未运行或未安装。"
fi
