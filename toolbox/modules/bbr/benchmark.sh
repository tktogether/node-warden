#!/usr/bin/env bash
# 在已安装 iperf3 服务端的两台主机之间测试可用拥塞控制算法。
# 只修改当前运行时的 sysctl，测试结束后恢复原值。

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
TOOLBOX_ROOT="${TOOLBOX_ROOT:-$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)}"
export TOOLBOX_ROOT
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

PEER=""
PORT=5201
SECONDS_TO_TEST=10
SCHEMES_CSV="bbr,cubic"
REVERSE=0

usage() {
  cat <<'EOF'
用法：
  benchmark.sh --peer HOST [选项]

选项：
  --peer HOST          iperf3 服务端地址，必填
  --port PORT          iperf3 端口，默认 5201
  --seconds N          每个方案测试时长，默认 10
  --schemes LIST       逗号分隔，默认 bbr,cubic
  --reverse            反向测试（服务端发送）

要求：
  对端已运行 iperf3 -s；本机需要 iperf3 和 root 权限。
  不可用的第三方方案会标记为 unsupported，不会编译或替换内核。

示例：
  sudo bash toolbox.sh bbr benchmark --peer 203.0.113.10 --seconds 15 --schemes bbr,cubic
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --peer)
      [[ $# -ge 2 ]] || die "--peer 需要参数"
      PEER=$2
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port 需要参数"
      PORT=$2
      shift 2
      ;;
    --seconds)
      [[ $# -ge 2 ]] || die "--seconds 需要参数"
      SECONDS_TO_TEST=$2
      shift 2
      ;;
    --schemes)
      [[ $# -ge 2 ]] || die "--schemes 需要参数"
      SCHEMES_CSV=$2
      shift 2
      ;;
    --reverse)
      REVERSE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "未知参数：$1"
      ;;
  esac
done

if [[ -z "$PEER" ]]; then
  usage
  exit 1
fi
validate_host "$PEER" || die "peer 无效：$PEER"
validate_port "$PORT" || die "端口无效：$PORT"
validate_seconds "$SECONDS_TO_TEST" || die "时长无效：$SECONDS_TO_TEST"
require_root
require_cmd iperf3
require_cmd sysctl

original_cc=$(sysctl -n net.ipv4.tcp_congestion_control)
original_qdisc=$(sysctl -n net.core.default_qdisc)
restored=0

restore() {
  if [[ "$restored" == "1" ]]; then
    return 0
  fi
  restored=1
  sysctl -w "net.ipv4.tcp_congestion_control=$original_cc" >/dev/null 2>&1 || true
  sysctl -w "net.core.default_qdisc=$original_qdisc" >/dev/null 2>&1 || true
}
trap restore EXIT INT TERM

available_scheme() {
  local scheme=$1
  sysctl -n net.ipv4.tcp_available_congestion_control | tr ' ' '\n' | grep -qx "$scheme"
}

parse_iperf() {
  local file=$1
  local sender receiver retrans
  sender=$(awk '/sender/ {for (i = 1; i <= NF; i++) if ($i == "Mbits/sec") {print $(i - 1); exit}}' "$file")
  receiver=$(awk '/receiver/ {for (i = 1; i <= NF; i++) if ($i == "Mbits/sec") {print $(i - 1); exit}}' "$file")
  retrans=$(awk '/sender/ {print $(NF - 1); exit}' "$file")
  printf '%s %s %s\n' "${sender:-0}" "${receiver:-0}" "${retrans:-0}"
}

printf '对端：%s:%s\n' "$PEER" "$PORT"
printf '时长：%s 秒/方案\n' "$SECONDS_TO_TEST"
printf '原值：%s / %s\n\n' "$original_cc" "$original_qdisc"
printf '%-24s %-12s %-12s %-12s %-10s\n' "方案" "发送(Mbps)" "接收(Mbps)" "重传" "状态"
printf '%-24s %-12s %-12s %-12s %-10s\n' "------------------------" "------------" "------------" "------------" "----------"

IFS=',' read -r -a schemes <<< "$SCHEMES_CSV"
for raw_scheme in "${schemes[@]}"; do
  scheme=$(printf '%s' "$raw_scheme" | tr -d '[:space:]')
  [[ -n "$scheme" ]] || continue
  if [[ ! "$scheme" =~ ^[a-z0-9_]+$ ]]; then
    printf '%-24s %-12s %-12s %-12s %-10s\n' "$scheme" "-" "-" "-" "invalid"
    continue
  fi
  if ! available_scheme "$scheme"; then
    printf '%-24s %-12s %-12s %-12s %-10s\n' "$scheme" "-" "-" "-" "unsupported"
    continue
  fi
  if ! sysctl -w "net.ipv4.tcp_congestion_control=$scheme" >/dev/null 2>&1; then
    printf '%-24s %-12s %-12s %-12s %-10s\n' "$scheme" "-" "-" "-" "set-failed"
    continue
  fi
  out=$(mktemp)
  args=(-c "$PEER" -p "$PORT" -t "$SECONDS_TO_TEST" -P 1 -f m)
  if [[ "$REVERSE" == "1" ]]; then
    args+=(-R)
  fi
  if ! iperf3 "${args[@]}" > "$out" 2>&1; then
    printf '%-24s %-12s %-12s %-12s %-10s\n' "$scheme" "-" "-" "-" "iperf-failed"
    rm -f "$out"
    continue
  fi
  read -r sender receiver retrans <<< "$(parse_iperf "$out")"
  printf '%-24s %-12s %-12s %-12s %-10s\n' "$scheme" "$sender" "$receiver" "$retrans" "ok"
  rm -f "$out"
done

restore
printf '\n已恢复：%s / %s\n' "$(sysctl -n net.ipv4.tcp_congestion_control)" "$(sysctl -n net.core.default_qdisc)"
