#!/usr/bin/env bash
# 输出主机、系统、CPU、内存、磁盘和网络摘要。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

section "主机"
kv "主机名" "$(uname -n)"
kv "系统" "$(. /etc/os-release 2>/dev/null && printf '%s %s' "${NAME:-unknown}" "${VERSION_ID:-}")"
kv "内核" "$(uname -r)"
kv "架构" "$(uname -m)"
kv "运行时间" "$(uptime -p 2>/dev/null || uptime)"
kv "当前时间" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
if have_cmd systemd-detect-virt; then
  kv "虚拟化" "$(systemd-detect-virt 2>/dev/null || printf 'none')"
fi

section "CPU 与内存"
if have_cmd lscpu; then
  lscpu | sed -n 's/^Model name:/型号:/p; s/^CPU(s):/逻辑 CPU:/p; s/^Thread(s) per core:/每核线程:/p; s/^Core(s) per socket:/每路核心:/p; s/^Socket(s):/路数:/p'
fi
free -h
kv "负载" "$(cat /proc/loadavg)"

section "磁盘"
df -hT /
printf '\n挂载点：\n'
df -hT | awk 'NR == 1 || $2 != "tmpfs"'

section "网络"
printf '默认路由：\n'
ip -4 route show default 2>/dev/null || true
printf '\n地址：\n'
ip -4 -o addr show scope global 2>/dev/null | awk '{printf "  %-12s %s\n", $2, $4}' || true
printf '\nDNS：\n'
if [[ -r /etc/resolv.conf ]]; then
  awk '/^nameserver/ {print "  " $2}' /etc/resolv.conf
fi
printf '\n监听端口数：'
ss -ltnH 2>/dev/null | wc -l
