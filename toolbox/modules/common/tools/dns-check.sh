#!/usr/bin/env bash
# 检查域名解析结果，区分系统解析和 DNS 查询。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

if [[ $# -eq 0 ]]; then
  set -- github.com raw.githubusercontent.com registry-1.docker.io
fi

section "DNS 服务器"
if [[ -r /etc/resolv.conf ]]; then
  awk '/^nameserver/ {print "  " $2}' /etc/resolv.conf
else
  warn "无法读取 /etc/resolv.conf。"
fi

for domain in "$@"; do
  validate_host "$domain" || die "域名无效：$domain"
  section "$domain"
  printf '系统解析（getent）：\n'
  if have_cmd getent; then
    timeout 5 getent ahostsv4 "$domain" | awk '{print "  " $1}' | sort -u || true
  else
    warn "缺少 getent。"
  fi
  if have_cmd dig; then
    printf 'A 记录（dig）：\n'
    timeout 8 dig +short A "$domain" +time=3 +tries=1 | sed 's/^/  /' || true
    printf 'AAAA 记录（dig）：\n'
    timeout 8 dig +short AAAA "$domain" +time=3 +tries=1 | sed 's/^/  /' || true
  else
    warn "缺少 dig，跳过直接 DNS 查询。"
  fi
done
