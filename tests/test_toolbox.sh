#!/usr/bin/env bash
# 测试 toolbox.sh 的入口、清单和公共参数校验，不修改系统。
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$ROOT_DIR"

fail() { printf 'toolbox test failed: %s\n' "$1" >&2; exit 1; }

# shellcheck source=/dev/null
source "$ROOT_DIR/toolbox/lib/common.sh"

validate_host example.com || fail 'valid host rejected'
if validate_host '-bad.example.com'; then fail 'bad host accepted'; fi
if validate_host 'bad host'; then fail 'host with space accepted'; fi
validate_port 443 || fail 'valid port rejected'
if validate_port 0; then fail 'port 0 accepted'; fi
if validate_port 65536; then fail 'port 65536 accepted'; fi
validate_seconds 10 || fail 'valid seconds rejected'
if validate_seconds 0; then fail 'seconds 0 accepted'; fi

version=$(bash toolbox.sh version)
[ "$version" = "Node Warden Toolbox $(tr -d '[:space:]' < VERSION)" ] || fail "unexpected version: $version"

modules=$(bash toolbox.sh list)
for id in common node-warden bbr; do
  grep -q "$id" <<< "$modules" || fail "module missing: $id"
done

common=$(bash toolbox.sh common list)
for id in system-info net-bench docker-mirror-speedtest dns-check port-check github-speedtest cert-check disk-usage docker-info; do
  grep -q "$id" <<< "$common" || fail "common tool missing: $id"
done

bbr=$(bash toolbox.sh bbr list)
for action in status install rollback schemes benchmark legacy; do
  grep -q "$action" <<< "$bbr" || fail "bbr action missing: $action"
done

bash toolbox.sh self-test >/dev/null || fail 'self-test failed'
printf 'toolbox tests passed.\n'