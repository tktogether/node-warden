#!/usr/bin/env bash
# 测试目标的延迟、丢包、TCP 端口和可选 iperf3 带宽。
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

usage() {
  cat <<'EOF'
用法：
  net-bench.sh [选项] 目标 [目标...]

选项：
  --count N           ping 次数，默认 4
  --port PORT         TCP 端口，默认 443
  --iperf             额外运行 iperf3 客户端
  --iperf-seconds N   iperf3 时长，默认 10

示例：
  net-bench.sh 1.1.1.1
  net-bench.sh --port 80 example.com
  net-bench.sh --iperf --iperf-seconds 15 203.0.113.10
EOF
}

COUNT=4
PORT=443
IPERF=0
IPERF_SECONDS=10
TARGETS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count)
      [[ $# -ge 2 ]] || die "--count 需要参数"
      COUNT=$2
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port 需要参数"
      PORT=$2
      shift 2
      ;;
    --iperf)
      IPERF=1
      shift
      ;;
    --iperf-seconds)
      [[ $# -ge 2 ]] || die "--iperf-seconds 需要参数"
      IPERF_SECONDS=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      die "未知选项：$1"
      ;;
    *)
      TARGETS+=("$1")
      shift
      ;;
  esac
done

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  usage
  exit 1
fi
validate_seconds "$COUNT" || die "ping 次数无效：$COUNT"
validate_port "$PORT" || die "端口无效：$PORT"
if [[ "$IPERF" == "1" ]]; then
  validate_seconds "$IPERF_SECONDS" || die "iperf3 时长无效：$IPERF_SECONDS"
  require_cmd iperf3
fi

for target in "${TARGETS[@]}"; do
  validate_host "$target" || die "目标主机无效：$target"
  section "$target"
  if have_cmd ping; then
    ping -c "$COUNT" -W 2 "$target" || true
  else
    warn "未安装 ping。"
  fi
  if have_cmd mtr; then
    printf '\n路由（mtr）：\n'
    mtr -rwc "$COUNT" "$target" 2>/dev/null || true
  fi
  printf '\nTCP %s:%s：' "$target" "$PORT"
  if timeout 5 bash -c "exec 3<>/dev/tcp/$target/$PORT" 2>/dev/null; then
    printf '可连接\n'
  else
    printf '不可连接\n'
  fi
  if [[ "$IPERF" == "1" ]]; then
    printf '\niperf3（%s 秒）：\n' "$IPERF_SECONDS"
    iperf3 -c "$target" -p 5201 -t "$IPERF_SECONDS" -P 1 || true
  fi
done
