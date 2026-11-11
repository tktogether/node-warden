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

help=$(bash toolbox.sh help)
grep -q '一键安装 Node Warden' <<< "$help" || fail 'install entry missing from help'
grep -q 'toolbox.sh remote' <<< "$help" || fail 'remote entry missing from help'
grep -q '不需要手工下载源码' <<< "$help" || fail 'remote install note missing from help'

remote=$(bash toolbox.sh remote)
grep -q 'toolbox.sh' <<< "$remote" || fail 'remote command missing'
grep -q ' install' <<< "$remote" || fail 'remote install command missing'

modules=$(bash toolbox.sh list)
for id in common node-warden bbr; do
  grep -q "$id" <<< "$modules" || fail "module missing: $id"
done

node_list=$(bash toolbox.sh node-warden list)
grep -q 'install' <<< "$node_list" || fail 'node-warden install action missing'

common=$(bash toolbox.sh common list)
for id in system-info net-bench docker-mirror-speedtest dns-check port-check github-speedtest cert-check disk-usage docker-info; do
  grep -q "$id" <<< "$common" || fail "common tool missing: $id"
done

bbr=$(bash toolbox.sh bbr list)
for action in status install rollback schemes benchmark legacy; do
  grep -q "$action" <<< "$bbr" || fail "bbr action missing: $action"
done

bash toolbox.sh self-test >/dev/null || fail 'self-test failed'

# 单独复制 toolbox.sh，验证会自动获取源码并继续执行。
self_tmp=$(mktemp -d)
mkdir -p "$self_tmp/standalone"
cp "$ROOT_DIR/toolbox.sh" "$self_tmp/standalone/toolbox.sh"
tar --exclude='.git' --exclude='__pycache__' --exclude='.chrome-warden-c' -czf "$self_tmp/pkg.tar.gz" -C "$ROOT_DIR" .
if command -v cygpath >/dev/null 2>&1; then
  self_url="file://$(cygpath -m "$self_tmp/pkg.tar.gz")"
else
  self_url="file://$self_tmp/pkg.tar.gz"
fi
self_output=$(cd "$self_tmp/standalone" && NW_TOOLBOX_ARCHIVE_URL="$self_url" bash toolbox.sh version)
grep -q 'Node Warden Toolbox' <<< "$self_output" || fail 'self bootstrap did not run toolbox'
cd "$ROOT_DIR"
rm -rf "$self_tmp"
printf 'toolbox tests passed.\n'