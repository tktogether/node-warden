#!/usr/bin/env bash
# Install Node Warden on a systemd host. Run as root.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALL_DIR=/opt/node-warden
CONFIG_DIR=/etc/node-warden
DATA_DIR=/var/lib/node-warden
BASE_PATH=/warden
PUBLIC_URL=${PANEL_PUBLIC_URL:-}
CERT_DOMAIN=${PANEL_CERT_DOMAIN:-}
NODE_HOST=${PANEL_NODE_HOST:-}
SERVICES_SOURCE="$ROOT_DIR/examples/services.example.json"
RESET_KEY=0
UPGRADE=0
START=1
FORCE_SERVICES=0
BASE_PATH_SET=0

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
用法：install.sh [选项]

  --public-url URL       面板对外地址，路径必须与 --base-path 一致
  --base-path PATH       面板路径，默认 /warden
  --cert-domain DOMAIN   证书域名，默认取 --public-url 的主机名
  --node-host HOST       sing-box 分享链接中使用的主机名，默认同证书域名
  --services FILE        首次安装时复制到 /etc/node-warden/services.json 的服务清单
  --install-dir DIR      程序目录，默认 /opt/node-warden
  --config-dir DIR       配置目录，默认 /etc/node-warden
  --data-dir DIR         数据目录，默认 /var/lib/node-warden
  --force-services       覆盖已有 services.json
  --reset-key            生成新的访问密钥并使旧会话失效
  --upgrade              升级模式，保留现有配置和密钥
  --no-start             安装后不启动服务
  -h, --help             显示帮助

首次安装示例：
  sudo ./deploy/install.sh --public-url https://panel.example.com/warden \
    --cert-domain panel.example.com --services examples/services.example.json

升级示例：
  sudo ./deploy/upgrade.sh
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --public-url) [ $# -ge 2 ] || die '--public-url 缺少值'; PUBLIC_URL=$2; shift 2 ;;
    --base-path) [ $# -ge 2 ] || die '--base-path 缺少值'; BASE_PATH=$2; BASE_PATH_SET=1; shift 2 ;;
    --cert-domain) [ $# -ge 2 ] || die '--cert-domain 缺少值'; CERT_DOMAIN=$2; shift 2 ;;
    --node-host) [ $# -ge 2 ] || die '--node-host 缺少值'; NODE_HOST=$2; shift 2 ;;
    --services) [ $# -ge 2 ] || die '--services 缺少值'; SERVICES_SOURCE=$2; shift 2 ;;
    --install-dir) [ $# -ge 2 ] || die '--install-dir 缺少值'; INSTALL_DIR=$2; shift 2 ;;
    --config-dir) [ $# -ge 2 ] || die '--config-dir 缺少值'; CONFIG_DIR=$2; shift 2 ;;
    --data-dir) [ $# -ge 2 ] || die '--data-dir 缺少值'; DATA_DIR=$2; shift 2 ;;
    --force-services) FORCE_SERVICES=1; shift ;;
    --reset-key) RESET_KEY=1; shift ;;
    --upgrade) UPGRADE=1; shift ;;
    --no-start) START=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die '请以 root 运行'
command -v systemctl >/dev/null 2>&1 || die '未找到 systemctl；Node Warden 需要 systemd'
command -v curl >/dev/null 2>&1 || die '未找到 curl'
PYTHON_BIN=${PYTHON_BIN:-python3}
command -v "$PYTHON_BIN" >/dev/null 2>&1 || die '未找到 python3'
PYTHON_BIN=$(command -v "$PYTHON_BIN") || die '未找到 python3'
"$PYTHON_BIN" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' \
  || die '需要 Python 3.10 或更高版本'

EXISTING_ENV="$CONFIG_DIR/panel.env"
env_get() {
  [ -f "$EXISTING_ENV" ] || return 0
  sed -n "s/^$1=//p" "$EXISTING_ENV" | tail -n 1
}

if [ -f "$EXISTING_ENV" ]; then
  [ -n "$PUBLIC_URL" ] || PUBLIC_URL=$(env_get PANEL_PUBLIC_URL)
  [ -n "$CERT_DOMAIN" ] || CERT_DOMAIN=$(env_get PANEL_CERT_DOMAIN)
  [ -n "$NODE_HOST" ] || NODE_HOST=$(env_get PANEL_NODE_HOST)
  if [ "$BASE_PATH_SET" = 0 ]; then
    EXISTING_BASE=$(env_get PANEL_BASE_PATH)
    [ -n "$EXISTING_BASE" ] && BASE_PATH=$EXISTING_BASE
  fi
fi

if [ "$UPGRADE" = 1 ] && [ ! -f "$EXISTING_ENV" ]; then
  die '未发现安装配置；请先执行首次安装'
fi
[ -n "$PUBLIC_URL" ] || die '缺少 --public-url（或 PANEL_PUBLIC_URL）'
PUBLIC_URL=${PUBLIC_URL%/}
case "$BASE_PATH" in
  /*) ;;
  *) die '--base-path 必须以 / 开头' ;;
esac
BASE_PATH="/${BASE_PATH#/}"
BASE_PATH="${BASE_PATH%/}"
[ -n "$BASE_PATH" ] || BASE_PATH=/

PUBLIC_HOST=$("$PYTHON_BIN" - "$PUBLIC_URL" "$BASE_PATH" <<'PY'
import sys
from urllib.parse import urlparse
url, base = sys.argv[1], sys.argv[2]
parsed = urlparse(url)
if parsed.scheme not in ('http', 'https') or not parsed.hostname:
    raise SystemExit('PANEL_PUBLIC_URL 必须是 http(s) 绝对地址')
want = '/' + base.strip('/')
if parsed.path.rstrip('/') != want.rstrip('/'):
    raise SystemExit('PANEL_PUBLIC_URL 的路径必须等于 ' + want)
print(parsed.hostname)
PY
) || die 'PANEL_PUBLIC_URL 无效'
[ -n "$CERT_DOMAIN" ] || CERT_DOMAIN=$PUBLIC_HOST
[ -n "$NODE_HOST" ] || NODE_HOST=$CERT_DOMAIN

[ -d "$ROOT_DIR/app" ] || die "找不到程序目录：$ROOT_DIR/app"
[ -d "$ROOT_DIR/static" ] || die "找不到静态目录：$ROOT_DIR/static"

install -d -m 0755 "$INSTALL_DIR"
install -d -m 0700 "$CONFIG_DIR"
install -d -m 0700 "$DATA_DIR" "$DATA_DIR/backups"

if [ ! -f "$CONFIG_DIR/services.json" ] || [ "$FORCE_SERVICES" = 1 ]; then
  [ -f "$SERVICES_SOURCE" ] || die "找不到服务清单：$SERVICES_SOURCE"
  install -m 0600 "$SERVICES_SOURCE" "$CONFIG_DIR/services.json"
  note "已写入服务清单：$CONFIG_DIR/services.json"
else
  note "保留现有服务清单：$CONFIG_DIR/services.json"
fi

NEW_KEY=0
KEY=''
if [ ! -f "$EXISTING_ENV" ]; then
  KEY=$("$PYTHON_BIN" -c 'import secrets; print(secrets.token_urlsafe(32))')
  KEY_HASH=$(printf '%s' "$KEY" | "$PYTHON_BIN" -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
  SESSION_SECRET=$("$PYTHON_BIN" -c 'import secrets; print(secrets.token_hex(32))')
  umask 077
  ENV_TMP=$(mktemp "$CONFIG_DIR/panel.env.XXXXXX")
  {
    printf 'PANEL_PUBLIC_URL=%s\n' "$PUBLIC_URL"
    printf 'PANEL_BASE_PATH=%s\n' "$BASE_PATH"
    printf 'PANEL_KEY_SHA256=%s\n' "$KEY_HASH"
    printf 'PANEL_SESSION_SECRET=%s\n' "$SESSION_SECRET"
    printf 'PANEL_SERVICES_FILE=%s\n' "$CONFIG_DIR/services.json"
    printf 'PANEL_DATA_DIR=%s\n' "$DATA_DIR"
    printf 'PANEL_ENV_FILE=%s\n' "$EXISTING_ENV"
    printf 'PANEL_KEY_FILE=%s\n' "$DATA_DIR/access-key"
    printf 'PANEL_CERT_DOMAIN=%s\n' "$CERT_DOMAIN"
    printf 'PANEL_CERT_CONNECT_HOST=127.0.0.1\n'
    printf 'PANEL_CERT_CONNECT_PORT=443\n'
    printf 'PANEL_NODE_HOST=%s\n' "$NODE_HOST"
    printf 'PANEL_TRUST_PROXY=1\n'
    printf 'PANEL_MONITOR_ENABLED=1\n'
    printf 'PANEL_MONITOR_INTERVAL=60\n'
  } > "$ENV_TMP"
  chmod 0600 "$ENV_TMP"
  mv "$ENV_TMP" "$EXISTING_ENV"
  NEW_KEY=1
  note "已生成访问密钥和会话密钥"
elif [ "$RESET_KEY" = 1 ]; then
  KEY=$("$PYTHON_BIN" -c 'import secrets; print(secrets.token_urlsafe(32))')
  KEY_HASH=$(printf '%s' "$KEY" | "$PYTHON_BIN" -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())')
  ENV_TMP=$(mktemp "$CONFIG_DIR/panel.env.XXXXXX")
  if grep -q '^PANEL_KEY_SHA256=' "$EXISTING_ENV"; then
    sed "s|^PANEL_KEY_SHA256=.*|PANEL_KEY_SHA256=$KEY_HASH|" "$EXISTING_ENV" > "$ENV_TMP"
  else
    cat "$EXISTING_ENV" > "$ENV_TMP"
    printf 'PANEL_KEY_SHA256=%s\n' "$KEY_HASH" >> "$ENV_TMP"
  fi
  chmod 0600 "$ENV_TMP"
  mv "$ENV_TMP" "$EXISTING_ENV"
  NEW_KEY=1
  note "已重置访问密钥；旧会话将在服务重启后失效"
fi

if [ "$NEW_KEY" = 1 ]; then
  printf '%s\n' "$KEY" > "$DATA_DIR/access-key"
  chmod 0600 "$DATA_DIR/access-key"
fi
chmod 0700 "$CONFIG_DIR" "$DATA_DIR" "$DATA_DIR/backups" 2>/dev/null || true
chmod 0600 "$CONFIG_DIR/services.json" "$EXISTING_ENV"

if command -v logrotate >/dev/null 2>&1; then
  LOGROTATE_TMP=$(mktemp)
  sed -e "s|@DATA_DIR@|$DATA_DIR|g" "$ROOT_DIR/deploy/node-warden.logrotate" > "$LOGROTATE_TMP"
  install -d -m 0755 /etc/logrotate.d
  install -m 0644 "$LOGROTATE_TMP" /etc/logrotate.d/node-warden
  rm -f "$LOGROTATE_TMP"
  note '已安装日志轮转配置：/etc/logrotate.d/node-warden'
else
  note '未找到 logrotate，跳过审计日志轮转配置。'
fi

if systemctl list-unit-files node-warden.service >/dev/null 2>&1; then
  systemctl stop node-warden.service 2>/dev/null || true
fi
rm -rf "$INSTALL_DIR/app" "$INSTALL_DIR/static"
cp -a "$ROOT_DIR/app" "$INSTALL_DIR/app"
cp -a "$ROOT_DIR/static" "$INSTALL_DIR/static"
install -m 0644 "$ROOT_DIR/VERSION" "$INSTALL_DIR/VERSION"
install -m 0644 "$ROOT_DIR/README.md" "$INSTALL_DIR/README.md"
install -m 0755 "$ROOT_DIR/bootstrap.sh" "$INSTALL_DIR/bootstrap.sh"
find "$INSTALL_DIR" -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
chown -R root:root "$INSTALL_DIR"

set -a
# shellcheck disable=SC1090
. "$EXISTING_ENV"
set +a
(
  cd "$INSTALL_DIR"
  "$PYTHON_BIN" - <<'PY'
from app.config import Settings, load_services, load_backups
settings = Settings.from_env()
services = load_services(settings.services_file)
load_backups(settings.services_file, settings.backup_allowed_roots)
print('配置校验通过：%d 个服务' % len(services))
PY
)

UNIT_TMP=$(mktemp)
sed \
  -e "s|/opt/node-warden|$INSTALL_DIR|g" \
  -e "s|/etc/node-warden|$CONFIG_DIR|g" \
  -e "s|/usr/bin/python3|$PYTHON_BIN|g" \
  "$ROOT_DIR/deploy/node-warden.service" > "$UNIT_TMP"
install -m 0644 "$UNIT_TMP" /etc/systemd/system/node-warden.service
rm -f "$UNIT_TMP"
systemctl daemon-reload
systemctl enable node-warden.service >/dev/null 2>&1

if [ "$START" = 1 ]; then
  systemctl restart node-warden.service
  PORT=${PANEL_PORT:-9090}
  HEALTH_URL="http://127.0.0.1:${PORT}${BASE_PATH%/}/api/session"
  CODE=''
  for _ in $(seq 1 40); do
    CODE=$(curl -sS -o /dev/null -w '%{http_code}' "$HEALTH_URL" 2>/dev/null || true)
    [ "$CODE" = 200 ] && break
    sleep 0.5
  done
  if [ "$CODE" != 200 ]; then
    journalctl -u node-warden.service -n 40 --no-pager || true
    die "服务未通过健康检查（HTTP $CODE）"
  fi
  note 'Node Warden 已启动。'
else
  note 'Node Warden 已安装，但未启动。'
fi

note ''
note "访问地址：$PUBLIC_URL/"
note "服务状态：systemctl status node-warden"
note "服务清单：$CONFIG_DIR/services.json"
if [ "$NEW_KEY" = 1 ]; then
  note "初始访问密钥：$KEY"
  note "该密钥仅在此处显示；请登录后立即在设置页修改。"
else
  note '访问密钥保持为现有密钥。'
fi
