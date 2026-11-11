#!/usr/bin/env bash
# 检查远程 TLS 证书主题、签发者、有效期和剩余时间。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

require_cmd openssl

TARGET="${1:-example.com}"
PORT=443
HOST=$TARGET
if [[ "$TARGET" == *:* ]]; then
  HOST="${TARGET%:*}"
  PORT="${TARGET##*:}"
fi
validate_host "$HOST" || die "主机无效：$HOST"
validate_port "$PORT" || die "端口无效：$PORT"

tmp=$(mktemp)
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

if [[ "$HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  if ! timeout 15 openssl s_client -connect "$HOST:$PORT" -showcerts </dev/null > "$tmp" 2>/dev/null; then
    die "无法建立 TLS 连接：$HOST:$PORT"
  fi
else
  if ! timeout 15 openssl s_client -connect "$HOST:$PORT" -servername "$HOST" -showcerts </dev/null > "$tmp" 2>/dev/null; then
    die "无法建立 TLS 连接：$HOST:$PORT"
  fi
fi

section "$HOST:$PORT"
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$tmp" | openssl x509 -noout -subject -issuer -dates
printf '\n扩展：\n'
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$tmp" | openssl x509 -noout -ext subjectAltName 2>/dev/null || true
printf '\n有效期检查：\n'
if awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$tmp" | openssl x509 -noout -checkend 2592000 >/dev/null 2>&1; then
  info "30 天内不会过期。"
else
  warn "证书将在 30 天内过期或已过期。"
fi
