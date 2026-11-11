#!/usr/bin/env bash
# 检查本机监听端口和远程 TCP 端口连通性。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

usage() {
  cat <<'EOF'
用法：
  port-check.sh                    列出本机监听端口
  port-check.sh PORT               检查本机 127.0.0.1:PORT
  port-check.sh HOST PORT          检查远程 HOST:PORT

示例：
  port-check.sh 443
  port-check.sh example.com 443
EOF
}

if [[ $# -eq 0 ]]; then
  section "本机监听端口"
  ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null || warn "缺少 ss 和 netstat。"
  exit 0
fi

if [[ $# -eq 1 ]]; then
  HOST=127.0.0.1
  PORT=$1
elif [[ $# -eq 2 ]]; then
  HOST=$1
  PORT=$2
else
  usage
  exit 1
fi

validate_host "$HOST" || die "主机无效：$HOST"
validate_port "$PORT" || die "端口无效：$PORT"

section "$HOST:$PORT"
printf 'TCP 连接：'
if timeout 5 bash -c "exec 3<>/dev/tcp/$HOST/$PORT" 2>/dev/null; then
  printf '可连接\n'
else
  printf '不可连接或超时\n'
fi

printf '\n本机监听：\n'
if have_cmd ss; then
  ss -ltnp "sport = :$PORT" 2>/dev/null || true
else
  netstat -ltnp 2>/dev/null | awk -v p=":$PORT" '$4 ~ p {print}' || true
fi
