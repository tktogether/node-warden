#!/usr/bin/env bash
# BBR 功能目录：状态、安装、回滚、方案兼容性和带宽测试。

if [[ -z "${TOOLBOX_ROOT:-}" ]]; then
  TOOLBOX_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)
  export TOOLBOX_ROOT
fi
# shellcheck source=/dev/null
source "$TOOLBOX_ROOT/toolbox/lib/common.sh"

MODULE_ID="bbr"
MODULE_TITLE="BBR"
MODULE_DESCRIPTION="配置 BBR、检查所有 BBR 方案兼容性并测试带宽。"
TOOLBOX_MODULE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
BBR_CONF="${BBR_CONF:-/etc/sysctl.d/99-bbr.conf}"
BBR_STATE_DIR="${BBR_STATE_DIR:-/var/lib/node-warden/toolbox}"
BBR_STATE_FILE="$BBR_STATE_DIR/bbr.previous"
TCP_SH_URL="https://gist.github.com/zeruns/a0ec603f20d1b86de6a774a8ba27588f/raw/4f9957ae23f5efb2bb7c57a198ae2cffebfb1c56/tcp.sh"

bbr_current_cc() {
  sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || printf 'unknown\n'
}

bbr_current_qdisc() {
  sysctl -n net.core.default_qdisc 2>/dev/null || printf 'unknown\n'
}

bbr_available() {
  local scheme=$1
  sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | tr ' ' '\n' | grep -qx "$scheme"
}

bbr_module_available() {
  local name=$1
  bbr_available "$name" && return 0
  if have_cmd modinfo && modinfo "$name" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

bbr_install() {
  require_root
  if ! bbr_available bbr; then
    warn "当前内核没有可用的 bbr 算法。"
    bbr_schemes
    die "无法启用 BBR。"
  fi

  mkdir -p "$BBR_STATE_DIR"
  chmod 700 "$BBR_STATE_DIR"
  if [[ ! -f "$BBR_STATE_FILE" ]]; then
    local conf_backup=""
    local conf_existed=0
    if [[ -f "$BBR_CONF" ]]; then
      conf_existed=1
      conf_backup=$(backup_file "$BBR_CONF")
    fi
    {
      printf 'cc=%s\n' "$(bbr_current_cc)"
      printf 'qdisc=%s\n' "$(bbr_current_qdisc)"
      printf 'conf_existed=%s\n' "$conf_existed"
      printf 'conf_backup=%s\n' "$conf_backup"
    } > "$BBR_STATE_FILE"
    chmod 600 "$BBR_STATE_FILE"
  fi

  local tmp
  tmp=$(mktemp)
  if [[ -f "$BBR_CONF" ]]; then
    grep -vE '^[[:space:]]*(net\.core\.default_qdisc|net\.ipv4\.tcp_congestion_control)[[:space:]]*=' "$BBR_CONF" > "$tmp" || true
  fi
  {
    printf 'net.core.default_qdisc = fq\n'
    printf 'net.ipv4.tcp_congestion_control = bbr\n'
  } >> "$tmp"
  install -m 0644 "$tmp" "$BBR_CONF"
  rm -f "$tmp"

  if ! sysctl --system >/dev/null 2>&1; then
    warn "sysctl --system 返回非零，尝试直接设置。"
    sysctl -w net.core.default_qdisc=fq >/dev/null || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null || true
  fi

  if [[ "$(bbr_current_cc)" != "bbr" ]]; then
    die "BBR 未生效，当前算法：$(bbr_current_cc)"
  fi
  info "BBR 已启用。"
  bbr_status
}

bbr_rollback() {
  require_root
  if [[ ! -f "$BBR_STATE_FILE" ]]; then
    die "没有可回滚的记录：$BBR_STATE_FILE"
  fi
  local prev_cc prev_qdisc conf_existed conf_backup
  prev_cc=$(awk -F= '$1 == "cc" {print $2; exit}' "$BBR_STATE_FILE")
  prev_qdisc=$(awk -F= '$1 == "qdisc" {print $2; exit}' "$BBR_STATE_FILE")
  conf_existed=$(awk -F= '$1 == "conf_existed" {print $2; exit}' "$BBR_STATE_FILE")
  conf_backup=$(awk -F= '$1 == "conf_backup" {print substr($0, index($0, "=") + 1); exit}' "$BBR_STATE_FILE")

  if [[ "$conf_existed" == "1" && -n "$conf_backup" && -f "$conf_backup" ]]; then
    cp -a -- "$conf_backup" "$BBR_CONF"
    info "已恢复配置文件：$BBR_CONF"
  else
    rm -f "$BBR_CONF"
    info "已删除配置文件：$BBR_CONF"
  fi

  if [[ -n "$prev_qdisc" ]]; then
    sysctl -w "net.core.default_qdisc=$prev_qdisc" >/dev/null || true
  fi
  if [[ -n "$prev_cc" ]]; then
    sysctl -w "net.ipv4.tcp_congestion_control=$prev_cc" >/dev/null || true
  fi
  if have_cmd sysctl; then
    sysctl --system >/dev/null 2>&1 || true
  fi
  rm -f "$BBR_STATE_FILE"
  info "已回滚到：$(bbr_current_cc) / $(bbr_current_qdisc)"
}

bbr_status() {
  section "BBR 状态"
  kv "内核" "$(uname -r)"
  kv "当前算法" "$(bbr_current_cc)"
  kv "当前队列" "$(bbr_current_qdisc)"
  kv "可用算法" "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf 'unknown')"
  if [[ -f "$BBR_CONF" ]]; then
    kv "配置文件" "$BBR_CONF"
    grep -E '^[[:space:]]*net\.(core\.default_qdisc|ipv4\.tcp_congestion_control)' "$BBR_CONF" || true
  else
    kv "配置文件" "不存在"
  fi
  if [[ -f "$BBR_STATE_FILE" ]]; then
    kv "回滚记录" "$BBR_STATE_FILE"
  fi
}

bbr_schemes() {
  section "内核"
  kv "版本" "$(uname -r)"
  kv "当前" "$(bbr_current_cc) / $(bbr_current_qdisc)"
  kv "可用" "$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || printf 'unknown')"

  local gcc49="不可用"
  local headers="不可用"
  if have_cmd gcc-4.9; then gcc49="可用"; fi
  if [[ -d "/lib/modules/$(uname -r)/build" ]]; then headers="可用"; fi

  section "方案兼容性"
  printf '%-24s %-12s %s\n' "方案" "状态" "说明"
  printf '%-24s %-12s %s\n' "------------------------" "------------" "----------------------------------------"
  if bbr_available bbr; then
    printf '%-24s %-12s %s\n' "原生 BBR" "可用" "内核自带，当前配置"
  else
    printf '%-24s %-12s %s\n' "原生 BBR" "不可用" "当前内核未提供 bbr"
  fi
  if bbr_module_available tcp_tsunami; then
    printf '%-24s %-12s %s\n' "BBR 魔改（tsunami）" "可用" "已存在 tcp_tsunami 模块"
  else
    printf '%-24s %-12s %s\n' "BBR 魔改（tsunami）" "不可用" "需第三方模块；tcp.sh 需 gcc-4.9 和内核头"
  fi
  if bbr_module_available tcp_nanqinlang; then
    printf '%-24s %-12s %s\n' "暴力 BBR 魔改" "可用" "已存在 tcp_nanqinlang 模块"
  else
    printf '%-24s %-12s %s\n' "暴力 BBR 魔改" "不可用" "需第三方模块；tcp.sh 需 gcc-4.9 和内核头"
  fi
  if bbr_module_available tcp_bbrplus; then
    printf '%-24s %-12s %s\n' "BBRplus" "可用" "已存在 tcp_bbrplus 模块"
  else
    printf '%-24s %-12s %s\n' "BBRplus" "不可用" "需替换 4.14 内核，未自动执行"
  fi
  printf '%-24s %-12s %s\n' "Lotserver" "未启用" "非 BBR；需替换内核，未自动执行"

  section "编译前提"
  kv "gcc-4.9" "$gcc49"
  kv "内核头目录" "$headers"
  kv "gcc" "$(command -v gcc || printf '不可用')"
  kv "make" "$(command -v make || printf '不可用')"

  info "tcp.sh 的 5、6、7 会修改内核或编译第三方模块，本工具不自动执行。"
}

bbr_legacy() {
  require_root
  require_cmd curl
  local tmp
  tmp=$(mktemp)
  info "下载 tcp.sh 以检查版本；不会执行。"
  download_github "$TCP_SH_URL" "$tmp"
  kv "文件大小" "$(wc -c < "$tmp") 字节"
  if have_cmd sha256sum; then
    kv "SHA-256" "$(sha256sum "$tmp" | awk '{print $1}')"
  fi
  printf '\n脚本菜单：\n'
  grep -nE '^[[:space:]]*[0-9]+[.)]|BBR|Lotserver' "$tmp" | head -n 20 || true
  rm -f "$tmp"
  info "未执行下载的脚本。需要切换内核时请先在可重建的机器上测试。"
}

bbr_benchmark() {
  if [[ ! -f "$TOOLBOX_MODULE_DIR/benchmark.sh" ]]; then
    die "缺少 benchmark.sh。"
  fi
  bash "$TOOLBOX_MODULE_DIR/benchmark.sh" "$@"
}

module_list() {
  printf 'BBR 操作：\n'
  printf '  %-16s %s\n' "status" "显示当前状态"
  printf '  %-16s %s\n' "install" "启用 fq + bbr"
  printf '  %-16s %s\n' "rollback" "恢复启用前的设置"
  printf '  %-16s %s\n' "schemes" "检查所有 BBR 方案兼容性"
  printf '  %-16s %s\n' "benchmark" "测试可用方案的带宽"
  printf '  %-16s %s\n' "legacy" "下载 tcp.sh 并检查，不执行"
}

module_run() {
  local action="${1:-}"
  if [[ $# -gt 0 ]]; then
    shift
  fi
  case "$action" in
    ""|list)
      module_list
      ;;
    status)
      bbr_status
      ;;
    install)
      bbr_install
      ;;
    rollback)
      bbr_rollback
      ;;
    schemes)
      bbr_schemes
      ;;
    benchmark)
      bbr_benchmark "$@"
      ;;
    legacy)
      bbr_legacy
      ;;
    help|--help|-h)
      module_list
      ;;
    *)
      die "未知操作：$action"
      ;;
  esac
}

module_menu() {
  local choice
  while true; do
    printf '\nBBR\n'
    printf '  1) status       显示当前状态\n'
    printf '  2) install      启用 fq + bbr\n'
    printf '  3) rollback     恢复启用前的设置\n'
    printf '  4) schemes      检查所有 BBR 方案兼容性\n'
    printf '  5) benchmark    测试可用方案的带宽\n'
    printf '  6) legacy       下载 tcp.sh 并检查，不执行\n'
    printf '  0) 返回\n'
    read -r -p '选择: ' choice || return 0
    case "$choice" in
      0|q) return 0 ;;
      1) bbr_status ;;
      2) bbr_install ;;
      3) bbr_rollback ;;
      4) bbr_schemes ;;
      5) bbr_benchmark ;;
      6) bbr_legacy ;;
      *) warn "无效选择。" ;;
    esac
  done
}
