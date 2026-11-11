#!/usr/bin/env bash
# Remove Node Warden. Configuration and data are kept unless --purge is used.
set -euo pipefail

INSTALL_DIR=/opt/node-warden
CONFIG_DIR=/etc/node-warden
DATA_DIR=/var/lib/node-warden
PURGE=0

usage() {
  cat <<'EOF'
用法：uninstall.sh [--purge]

  --purge   同时删除 /etc/node-warden 和 /var/lib/node-warden
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '未知参数：%s\n' "$1" >&2; exit 1 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { printf '请以 root 运行\n' >&2; exit 1; }

if command -v systemctl >/dev/null 2>&1; then
  systemctl disable --now node-warden.service 2>/dev/null || true
fi
rm -f /etc/systemd/system/node-warden.service
if command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload
fi
rm -rf "$INSTALL_DIR"
rm -f /etc/logrotate.d/node-warden

if [ "$PURGE" = 1 ]; then
  rm -rf "$CONFIG_DIR" "$DATA_DIR"
  printf 'Node Warden 已卸载，配置和数据已删除。\n'
else
  printf 'Node Warden 已卸载。\n'
  printf '配置保留在：%s\n' "$CONFIG_DIR"
  printf '数据保留在：%s\n' "$DATA_DIR"
fi
