#!/usr/bin/env bash
# Node Warden Toolbox 转发脚本测试：参数转发、本地覆盖、错误提示和行尾。

set -uo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
TOOLBOX="$ROOT_DIR/toolbox.sh"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'not ok %s：%s\n' "$1" "$2"; }

check_rc() {
  local name=$1 expected=$2 actual=$3
  if [[ "$actual" -eq "$expected" ]]; then ok "$name"; else bad "$name" "退出码 $actual，期望 $expected"; fi
}

check_contains() {
  local name=$1 text=$2 needle=$3
  if [[ "$text" == *"$needle"* ]]; then ok "$name"; else bad "$name" "缺少：$needle"; fi
}

check_empty() {
  local name=$1 text=$2
  if [[ -z "$text" ]]; then ok "$name"; else bad "$name" "内容非空：$text"; fi
}

printf '#!/usr/bin/env bash\nprintf "FAKE_TOOLBOX %%s\\n" "$*"\n' > "$TMP_DIR/fake-toolbox.sh"
printf '#!/usr/bin/env bash\nexit 3\n' > "$TMP_DIR/fail-toolbox.sh"

out=$(WARDEN_TOOLBOX_LOCAL="$TMP_DIR/fake-toolbox.sh" bash "$TOOLBOX" version 2>&1)
rc=$?
check_rc "版本转发退出码" 0 "$rc"
check_contains "版本转发参数" "$out" "FAKE_TOOLBOX version"

out=$(WARDEN_TOOLBOX_LOCAL="$TMP_DIR/fake-toolbox.sh" bash "$TOOLBOX" common port-check 443 2>&1)
check_contains "多参数转发" "$out" "FAKE_TOOLBOX common port-check 443"

out=$(WARDEN_TOOLBOX_LOCAL="$TMP_DIR/fake-toolbox.sh" bash "$TOOLBOX" 2>&1)
rc=$?
check_rc "无参数转发退出码" 0 "$rc"
check_contains "无参数转发" "$out" "FAKE_TOOLBOX"

out=$(WARDEN_TOOLBOX_LOCAL="$TMP_DIR/fail-toolbox.sh" bash "$TOOLBOX" status 2>&1)
rc=$?
check_rc "子脚本退出码透传" 3 "$rc"

out=$(WARDEN_TOOLBOX_LOCAL="$TMP_DIR/missing.sh" bash "$TOOLBOX" version 2>&1)
rc=$?
check_rc "本地覆盖不可用退出码" 1 "$rc"
check_contains "本地覆盖不可用提示" "$out" "WARDEN_TOOLBOX_LOCAL"

content=$(cat "$TOOLBOX")
check_contains "文件含 Node Warden Toolbox 标识" "$content" "Node Warden Toolbox"
check_contains "转发到独立仓库" "$content" "tktogether/warden-toolbox"
check_contains "提供地址覆盖" "$content" "WARDEN_TOOLBOX_URL"
check_contains "提供本地覆盖" "$content" "WARDEN_TOOLBOX_LOCAL"

if [[ -d "$ROOT_DIR/toolbox" ]]; then
  bad "仓库不再包含 toolbox 目录" "目录仍存在"
else
  ok "仓库不再包含 toolbox 目录"
fi

if grep -q 'NW_TOOLBOX_ARCHIVE_URL' "$TOOLBOX"; then
  bad "转发脚本不含旧自举逻辑" "发现 NW_TOOLBOX_ARCHIVE_URL"
else
  ok "转发脚本不含旧自举逻辑"
fi

cr_files=$(grep -rIl $'\r' "$TOOLBOX" "$ROOT_DIR/docs/TOOLBOX.md" 2>/dev/null || true)
check_empty "脚本与文档为 LF 行尾" "$cr_files"

if (( FAIL > 0 )); then
  printf '\n通过 %d 项，失败 %d 项。\n' "$PASS" "$FAIL"
  exit 1
fi
printf '\n通过 %d 项，失败 0 项。\n' "$PASS"