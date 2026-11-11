#!/usr/bin/env bash
# Node Warden 统一入口：安装、更新、卸载、状态检查、国内机设置与恢复。
# 只通过本脚本执行变更；组件细节由 deploy 目录中的固定文件提供。
set -Eeuo pipefail

SELF_SOURCE=${BASH_SOURCE[0]:-}
SELF_DIR=$(cd "$(dirname "$SELF_SOURCE")" && pwd)
SRC_DIR=${NW_SOURCE_DIR:-$SELF_DIR}
NW_REPO=${NW_REPO:-tktogether/node-warden}
NW_BRANCH=${NW_BRANCH:-main}
NW_GITHUB_PROXY=${NW_GITHUB_PROXY:-}
NW_ARCHIVE_URLS=${NW_ARCHIVE_URLS:-}
VERSION=$(cat "$SRC_DIR/VERSION" 2>/dev/null || printf 'unknown')
TMP_DIR=''
cleanup() { if [ -n "$TMP_DIR" ]; then rm -rf "$TMP_DIR"; fi; }
trap cleanup EXIT

if [ $# -eq 0 ] && [ -r /dev/tty ]; then
  COMMAND=install
elif [ $# -eq 0 ]; then
  COMMAND=help
else
  COMMAND=$1
  shift
fi

PANEL=1
GHPROXY=1
DOCKER_PROXY=1
PUBLIC_URL=${PANEL_PUBLIC_URL:-}
BASE_PATH=${PANEL_BASE_PATH:-/warden}
CERT_DOMAIN=${PANEL_CERT_DOMAIN:-}
NODE_HOST=${PANEL_NODE_HOST:-}
SERVICES_FILE=''
PANEL_INSTALL_DIR=${NW_PANEL_INSTALL_DIR:-/opt/node-warden}
PANEL_CONFIG_DIR=${NW_PANEL_CONFIG_DIR:-/etc/node-warden}
PANEL_DATA_DIR=${NW_PANEL_DATA_DIR:-/var/lib/node-warden}
GHPROXY_PORT=${NW_GHPROXY_PORT:-8082}
GHPROXY_DIR=${NW_GHPROXY_DIR:-/opt/node-warden-ghproxy}
DOCKER_PROXY_PORT=${NW_DOCKER_PROXY_PORT:-8080}
DOCKER_FRONT_PORT=${NW_DOCKER_FRONT_PORT:-8081}
DOCKER_PROXY_IMAGE=${NW_DOCKER_PROXY_IMAGE:-ghcr.io/daocloud/crproxy/crproxy:v0.9.1}
DOCKER_FRONT_IMAGE=${NW_DOCKER_FRONT_IMAGE:-nginx:1.27-alpine}
DOCKER_CRPROXY_NAME=${NW_DOCKER_CRPROXY_NAME:-node-warden-crproxy}
DOCKER_FRONT_NAME=${NW_DOCKER_FRONT_NAME:-node-warden-crproxy-front}
SKIP_DOCKER_INSTALL=0
SKIP_SOURCE_UPDATE=0
RECREATE=0
PURGE=0
DRY_RUN=0
NO_APT=0
NO_BBR=0
NO_APT_UPDATE=0
APT_MIRROR=https://mirrors.aliyun.com
DOCKER_MIRROR=''
BACKUP_DIR=''
NON_INTERACTIVE=0
ASSUME_YES=0
AUTO_CERT=${NW_AUTO_CERT:-1}
ACME_EMAIL=${NW_ACME_EMAIL:-}
CN_SCRIPT_URL=${NW_CN_SCRIPT_URL:-}

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }
warn() { printf '警告：%s\n' "$*" >&2; }

run() {
  printf '+ %s\n' "$*"
  if [ "$DRY_RUN" = 1 ]; then return 0; fi
  "$@"
}

require_root() { if [ "$DRY_RUN" = 1 ]; then return 0; fi; [ "$(id -u)" = 0 ] || die '请以 root 运行'; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "未找到命令：$1"; }
need_linux() { if [ "$DRY_RUN" = 1 ]; then return 0; fi; [ "$(uname -s)" = Linux ] || die '只支持 Linux'; }

usage() {
  cat <<'EOF'
Node Warden 统一入口

用法：bash bootstrap.sh <命令> [选项]

命令：
  install      安装面板、GitHub 下载代理和 Docker 镜像代理
  update       更新源码并升级已安装组件
  uninstall    停止并删除面板和代理组件
  status       显示组件状态和监听端口
  self-test    运行本地语法、单元测试和组件自检
  cn-setup     设置国内机的 APT 镜像、BBR 和可选 Docker 镜像
  cn-restore   恢复最近一次 cn-setup 修改的文件
  help         显示本帮助

安装与更新选项：
  --public-url URL       面板对外地址，例如 https://panel.example.com/warden
  --domain DOMAIN        面板域名；不提供 public URL 时自动拼成 https://DOMAIN/warden
  --email EMAIL          ACME 证书邮箱；留空时不提供邮箱
  --no-auto-cert         不自动申请证书
  --yes, -y              非交互确认
  --non-interactive      不显示安装向导
  --cn-script-url URL    安装后提示的国内网络设置脚本地址
  --base-path PATH       面板路径，默认 /warden
  --cert-domain DOMAIN   证书域名，默认取 public URL 主机名
  --node-host HOST       sing-box 分享链接主机名，默认同证书域名
  --services FILE        首次安装使用的服务清单
  --panel-only           只处理面板
  --no-panel             不处理面板
  --no-ghproxy           不处理 GitHub 下载代理
  --no-docker-proxy      不处理 Docker 镜像代理
  --ghproxy-port PORT    GitHub 代理端口，默认 8082
  --docker-proxy-port N  Docker 镜像代理端口，默认 8080
  --docker-front-port N  Docker 代理修正层端口，默认 8081
  --docker-proxy-image I Docker 代理镜像
  --skip-docker-install  不自动安装 Docker
  --skip-source-update   update 时不执行 git pull
  --source-dir DIR       使用指定源码目录
  --archive-url URL      指定源码压缩包地址
  --archive-urls LIST    空格分隔的多个源码压缩包地址
  --github-proxy URL     GitHub 下载代理前缀，例如 https://proxy.example.com
  --repo OWNER/REPO      源码仓库，默认 tktogether/node-warden
  --branch BRANCH        源码分支，默认 main
  --recreate             删除并重建 Docker 代理容器
  --dry-run              只打印将执行的变更，不修改系统
  --purge                uninstall 时同时删除面板配置和数据

远程源码选项（不手动下载源码时使用）：
  --source-dir DIR       使用本地源码目录
  --archive-url URL      指定源码压缩包
  --archive-urls LIST    空格分隔的多个源码压缩包，按顺序尝试
  --github-proxy URL     GitHub 下载代理前缀
  --repo OWNER/REPO      源码仓库，默认 tktogether/node-warden
  --branch BRANCH        源码分支，默认 main
  也可用环境变量 NW_SOURCE_DIR、NW_ARCHIVE_URL、NW_ARCHIVE_URLS、NW_GITHUB_PROXY、NW_REPO、NW_BRANCH。

国内机选项：
  --apt-mirror URL       APT 镜像根地址，默认 https://mirrors.aliyun.com
  --no-apt               不修改 APT 源
  --no-bbr               不启用 BBR
  --no-apt-update        cn-setup 后不执行 apt-get update
  --docker-mirror URL    写入 Docker daemon.json 的 registry-mirrors
  --backup-dir DIR       指定 cn-setup 备份目录（cn-restore 也可使用）

示例：
  sudo bash bootstrap.sh install
  sudo bash bootstrap.sh install --public-url https://panel.example.com/warden --non-interactive
  sudo bash -c 'bash <(curl -fsSL https://raw.githubusercontent.com/tktogether/node-warden/main/bootstrap.sh) install --public-url https://panel.example.com/warden'
  sudo bash bootstrap.sh install --github-proxy https://proxy.example.com --public-url https://panel.example.com/warden
  sudo bash bootstrap.sh update
  sudo bash bootstrap.sh status
  sudo bash bootstrap.sh cn-setup --docker-mirror https://docker.example.com
  sudo bash bootstrap.sh cn-restore --backup-dir /var/backups/node-warden-cn/20260101-000000
EOF
}

parse_options() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --public-url) [ $# -ge 2 ] || die '--public-url 缺少值'; PUBLIC_URL=$2; shift 2 ;;
      --domain) [ $# -ge 2 ] || die '--domain 缺少值'; CERT_DOMAIN=$2; shift 2 ;;
      --email) [ $# -ge 2 ] || die '--email 缺少值'; ACME_EMAIL=$2; shift 2 ;;
      --no-auto-cert) AUTO_CERT=0; shift ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      --non-interactive) NON_INTERACTIVE=1; shift ;;
      --cn-script-url) [ $# -ge 2 ] || die '--cn-script-url 缺少值'; CN_SCRIPT_URL=$2; shift 2 ;;
      --base-path) [ $# -ge 2 ] || die '--base-path 缺少值'; BASE_PATH=$2; shift 2 ;;
      --cert-domain) [ $# -ge 2 ] || die '--cert-domain 缺少值'; CERT_DOMAIN=$2; shift 2 ;;
      --node-host) [ $# -ge 2 ] || die '--node-host 缺少值'; NODE_HOST=$2; shift 2 ;;
      --services) [ $# -ge 2 ] || die '--services 缺少值'; SERVICES_FILE=$2; shift 2 ;;
      --panel-only) PANEL=1; GHPROXY=0; DOCKER_PROXY=0; shift ;;
      --no-panel) PANEL=0; shift ;;
      --no-ghproxy) GHPROXY=0; shift ;;
      --no-docker-proxy) DOCKER_PROXY=0; shift ;;
      --ghproxy-port) [ $# -ge 2 ] || die '--ghproxy-port 缺少值'; GHPROXY_PORT=$2; shift 2 ;;
      --docker-proxy-port) [ $# -ge 2 ] || die '--docker-proxy-port 缺少值'; DOCKER_PROXY_PORT=$2; shift 2 ;;
      --docker-front-port) [ $# -ge 2 ] || die '--docker-front-port 缺少值'; DOCKER_FRONT_PORT=$2; shift 2 ;;
      --docker-proxy-image) [ $# -ge 2 ] || die '--docker-proxy-image 缺少值'; DOCKER_PROXY_IMAGE=$2; shift 2 ;;
      --skip-docker-install) SKIP_DOCKER_INSTALL=1; shift ;;
      --skip-source-update) SKIP_SOURCE_UPDATE=1; shift ;;
      --source-dir) [ $# -ge 2 ] || die '--source-dir 缺少值'; [ -d "$2" ] || die "源码目录不存在：$2"; SRC_DIR=$(cd "$2" && pwd); shift 2 ;;
      --archive-url) [ $# -ge 2 ] || die '--archive-url 缺少值'; NW_ARCHIVE_URL=$2; shift 2 ;;
      --archive-urls) [ $# -ge 2 ] || die '--archive-urls 缺少值'; NW_ARCHIVE_URLS=$2; shift 2 ;;
      --github-proxy) [ $# -ge 2 ] || die '--github-proxy 缺少值'; NW_GITHUB_PROXY=$2; shift 2 ;;
      --repo) [ $# -ge 2 ] || die '--repo 缺少值'; NW_REPO=$2; shift 2 ;;
      --branch) [ $# -ge 2 ] || die '--branch 缺少值'; NW_BRANCH=$2; shift 2 ;;
      --recreate) RECREATE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --purge) PURGE=1; shift ;;
      --apt-mirror) [ $# -ge 2 ] || die '--apt-mirror 缺少值'; APT_MIRROR=$2; shift 2 ;;
      --no-apt) NO_APT=1; shift ;;
      --no-bbr) NO_BBR=1; shift ;;
      --no-apt-update) NO_APT_UPDATE=1; shift ;;
      --docker-mirror) [ $# -ge 2 ] || die '--docker-mirror 缺少值'; DOCKER_MIRROR=$2; shift 2 ;;
      --backup-dir) [ $# -ge 2 ] || die '--backup-dir 缺少值'; BACKUP_DIR=$2; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "未知参数：$1" ;;
    esac
  done
}

validate_base_path() {
  case "$BASE_PATH" in
    /*) ;;
    *) die '--base-path 必须以 / 开头' ;;
  esac
  BASE_PATH="/${BASE_PATH#/}"
  BASE_PATH="${BASE_PATH%/}"
  [ -n "$BASE_PATH" ] || BASE_PATH=/
  case "$BASE_PATH" in
    *..*) die '--base-path 不能包含 ..' ;;
    *[!A-Za-z0-9/_.-]*) die '--base-path 只能包含字母、数字、点、下划线、连字符和斜杠' ;;
  esac
}

validate_options() {
  if [ -n "$CERT_DOMAIN" ] && ! is_ipv4 "$CERT_DOMAIN" && ! is_domain "$CERT_DOMAIN"; then
    die "域名无效：$CERT_DOMAIN"
  fi
  if [ -n "$PUBLIC_URL" ]; then
    case "$PUBLIC_URL" in
      http://?*|https://?*) ;;
      *) die "面板地址必须是 http(s) 绝对地址：$PUBLIC_URL" ;;
    esac
    local rest host path
    rest=${PUBLIC_URL#*://}
    host=${rest%%/*}
    [ -n "$host" ] || die "面板地址缺少主机名：$PUBLIC_URL"
    case "$rest" in
      */*) path="/${rest#*/}" ;;
      *) path='/' ;;
    esac
    path="${path%/}"
    [ -n "$path" ] || path=/
    [ "$path" = "$BASE_PATH" ] || die "面板地址路径必须等于 $BASE_PATH：$PUBLIC_URL"
  fi
  if [ -n "$ACME_EMAIL" ]; then
    case "$ACME_EMAIL" in
      *@*.*) ;;
      *) die "邮箱格式无效：$ACME_EMAIL" ;;
    esac
  fi
  local name value
  for name in GHPROXY_PORT DOCKER_PROXY_PORT DOCKER_FRONT_PORT; do
    eval "value=\$$name"
    case "$value" in
      ''|*[!0-9]*) die "$name 必须是数字：$value" ;;
    esac
    [ "$value" -ge 1 ] 2>/dev/null && [ "$value" -le 65535 ] 2>/dev/null || die "$name 超出端口范围：$value"
  done
}

source_dir_ready() { [ -d "$SRC_DIR/app" ] && [ -d "$SRC_DIR/static" ]; }

download_source() {
  need_cmd curl
  need_cmd tar
  local tmp url root ok=0
  local direct="https://github.com/${NW_REPO}/archive/refs/heads/${NW_BRANCH}.tar.gz"
  local codeload="https://codeload.github.com/${NW_REPO}/tar.gz/refs/heads/${NW_BRANCH}"
  local urls=()
  if [ -n "${NW_ARCHIVE_URLS:-}" ]; then
    # 允许用空格分隔多个地址。
    # shellcheck disable=SC2206
    urls+=(${NW_ARCHIVE_URLS})
  fi
  [ -n "${NW_ARCHIVE_URL:-}" ] && urls+=("$NW_ARCHIVE_URL")
  urls+=("$direct" "$codeload")
  if [ -n "${NW_GITHUB_PROXY:-}" ]; then
    urls+=("${NW_GITHUB_PROXY%/}/$direct" "${NW_GITHUB_PROXY%/}/$codeload")
  fi
  urls+=("https://ghfast.top/$direct" "https://gh-proxy.com/$direct")
  if [ "$DRY_RUN" = 1 ]; then
    note '将按以下顺序尝试下载源码：'
    printf '  %s\n' "${urls[@]}"
    SRC_DIR=/tmp/node-warden-source
    return 0
  fi
  tmp=$(mktemp -d)
  TMP_DIR=$tmp
  for url in "${urls[@]}"; do
    [ -n "$url" ] || continue
    note "下载源码：$url"
    if curl -fL --connect-timeout 10 --max-time 180 --retry 1 --retry-delay 2 -o "$tmp/source.tar.gz" "$url"; then
      if tar -tzf "$tmp/source.tar.gz" >/dev/null 2>&1; then
        ok=1
        break
      fi
      warn '下载内容不是有效压缩包，尝试下一个地址。'
    else
      warn '下载失败，尝试下一个地址。'
    fi
  done
  [ "$ok" = 1 ] || die '所有源码下载地址均失败；请设置 NW_SOURCE_DIR 指向本地源码，或设置 NW_ARCHIVE_URL / NW_ARCHIVE_URLS。'
  tar -xzf "$tmp/source.tar.gz" -C "$tmp"
  root=$(find "$tmp" -maxdepth 3 -type d -name app -printf '%h\n' | head -n 1)
  [ -n "$root" ] || die '下载的源码中没有 app 目录'
  SRC_DIR=$root
  VERSION=$(cat "$SRC_DIR/VERSION" 2>/dev/null || printf 'unknown')
}

sync_source() {
  [ "$SKIP_SOURCE_UPDATE" = 1 ] && { note '已跳过源码更新。'; return 0; }
  if [ -d "$SRC_DIR/.git" ]; then
    need_cmd git
    if [ -n "$(git -C "$SRC_DIR" remote 2>/dev/null || true)" ]; then
      run git -C "$SRC_DIR" pull --ff-only
    else
      note '源码目录没有远程仓库，跳过 git pull。'
    fi
  elif source_dir_ready && [ -z "${NW_ARCHIVE_URL:-}" ] && [ -z "${NW_ARCHIVE_URLS:-}" ]; then
    note '使用当前目录源码。'
  else
    download_source
  fi
}

ensure_source() {
  source_dir_ready || download_source
}


panel_installed() { [ -f "$PANEL_CONFIG_DIR/panel.env" ] && [ -f /etc/systemd/system/node-warden.service ]; }

install_panel() {
  [ "$PANEL" = 1 ] || return 0
  if [ "$DRY_RUN" = 0 ]; then source_dir_ready || die "找不到源码目录：$SRC_DIR"; fi
  local args=(--base-path "$BASE_PATH" --install-dir "$PANEL_INSTALL_DIR" --config-dir "$PANEL_CONFIG_DIR" --data-dir "$PANEL_DATA_DIR")
  if [ -n "$PUBLIC_URL" ]; then args+=(--public-url "$PUBLIC_URL"); fi
  if [ -n "$CERT_DOMAIN" ]; then args+=(--cert-domain "$CERT_DOMAIN"); fi
  if [ -n "$NODE_HOST" ]; then args+=(--node-host "$NODE_HOST"); fi
  if [ -n "$SERVICES_FILE" ]; then args+=(--services "$SERVICES_FILE"); fi
  if [ "$COMMAND" = update ]; then
    panel_installed || die '面板尚未安装；请先执行 install'
    args+=(--upgrade)
  fi
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ bash %s/deploy/install.sh %s\n' "$SRC_DIR" "${args[*]}"
    return 0
  fi
  bash "$SRC_DIR/deploy/install.sh" "${args[@]}"
}

panel_env_value() {
  local name=$1
  [ -f "$PANEL_CONFIG_DIR/panel.env" ] || return 0
  sed -n "s/^${name}=//p" "$PANEL_CONFIG_DIR/panel.env" | tail -n 1
}

add_panel_env() {
  local name=$1 value=$2 env_file="$PANEL_CONFIG_DIR/panel.env"
  [ -f "$env_file" ] || return 0
  if grep -q "^${name}=" "$env_file"; then return 0; fi
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ add %s=%s to %s\n' "$name" "$value" "$env_file"
    return 0
  fi
  printf '%s=%s\n' "$name" "$value" >> "$env_file"
  chmod 0600 "$env_file"
}

configure_panel_proxy_env() {
  [ "$PANEL" = 1 ] || return 0
  [ -f "$PANEL_CONFIG_DIR/panel.env" ] || return 0
  if [ "$DOCKER_PROXY" = 1 ]; then
    add_panel_env PANEL_DOCKER_MIRROR_URL "http://127.0.0.1:${DOCKER_FRONT_PORT}/v2/"
  fi
  if [ "$GHPROXY" = 1 ]; then
    add_panel_env PANEL_GHPROXY_STATS_URL "http://127.0.0.1:${GHPROXY_PORT}/__stats"
  fi
  if [ "$DRY_RUN" = 0 ] && panel_installed; then
    run systemctl restart node-warden.service
  fi
}

install_ghproxy() {
  [ "$GHPROXY" = 1 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ install %s/deploy/ghproxy.py %s/ghproxy.py\n' "$SRC_DIR" "$GHPROXY_DIR"
    return 0
  fi
  source_dir_ready || die "找不到源码目录：$SRC_DIR"
  need_cmd python3
  local python_bin unit=/etc/systemd/system/node-warden-ghproxy.service
  python_bin=$(command -v python3)
  run install -d -m 0755 "$GHPROXY_DIR"
  run install -m 0755 "$SRC_DIR/deploy/ghproxy.py" "$GHPROXY_DIR/ghproxy.py"
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ write %s\n' "$unit"
  else
    cat > "$unit" <<EOF
[Unit]
Description=Node Warden GitHub download proxy
After=network.target

[Service]
Type=simple
ExecStart=$python_bin $GHPROXY_DIR/ghproxy.py --host 127.0.0.1 --port $GHPROXY_PORT
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=full
ReadOnlyPaths=$GHPROXY_DIR

[Install]
WantedBy=multi-user.target
EOF
    chmod 0644 "$unit"
  fi
  run systemctl daemon-reload
  run systemctl enable node-warden-ghproxy.service
  run systemctl restart node-warden-ghproxy.service
  if [ "$DRY_RUN" = 0 ]; then
    local code=''
    for _ in $(seq 1 30); do
      code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${GHPROXY_PORT}/__stats" 2>/dev/null || true)
      [ "$code" = 200 ] && break
      sleep 0.5
    done
    [ "$code" = 200 ] || die "GitHub 下载代理未通过健康检查（HTTP $code）"
  fi
}

ensure_docker() {
  [ "$DOCKER_PROXY" = 1 ] || return 0
  if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then return 0; fi
    warn 'Docker 已安装但守护进程不可用，尝试启动。'
    run systemctl start docker
    if [ "$DRY_RUN" = 0 ] && ! docker info >/dev/null 2>&1; then die 'Docker 守护进程未运行'; fi
    return 0
  fi
  [ "$SKIP_DOCKER_INSTALL" = 0 ] || die '未安装 Docker；请先安装或去掉 --skip-docker-install'
  command -v apt-get >/dev/null 2>&1 || die '未找到 Docker，且当前系统没有 apt-get'
  warn '未安装 Docker，将使用 apt-get 安装 docker.io。'
  run apt-get update
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  run systemctl enable --now docker
}

write_crproxy_front_config() {
  local path="$PANEL_CONFIG_DIR/crproxy-front.conf"
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ write %s\n' "$path"
    return 0
  fi
  install -d -m 0755 "$PANEL_CONFIG_DIR"
  cat > "$path" <<EOF
events {}
http {
    upstream crproxy {
        server 127.0.0.1:${DOCKER_PROXY_PORT};
    }
    server {
        listen 127.0.0.1:${DOCKER_FRONT_PORT};
        location ~ ^/v2/.*/referrers/ {
            return 200 '{"schemaVersion":2,"mediaType":"application/vnd.oci.image.index.v1+json","manifests":[]}';
        }
        location / {
            proxy_pass http://crproxy;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_buffering off;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
        }
    }
}
EOF
  chmod 0644 "$path"
}

install_docker_proxy() {
  [ "$DOCKER_PROXY" = 1 ] || return 0
  ensure_docker
  run docker pull "$DOCKER_PROXY_IMAGE"
  run docker pull "$DOCKER_FRONT_IMAGE"
  if [ "$RECREATE" = 1 ] || [ "$COMMAND" = update ]; then
    run docker rm -f "$DOCKER_CRPROXY_NAME" || true
    run docker rm -f "$DOCKER_FRONT_NAME" || true
  fi
  if docker inspect "$DOCKER_CRPROXY_NAME" >/dev/null 2>&1; then
    note "保留现有容器：$DOCKER_CRPROXY_NAME"
  else
    run docker run -d --name "$DOCKER_CRPROXY_NAME" --restart unless-stopped \
      -p "127.0.0.1:${DOCKER_PROXY_PORT}:8080" "$DOCKER_PROXY_IMAGE" \
      --address=:8080 --default-registry=docker.io
  fi
  write_crproxy_front_config
  if docker inspect "$DOCKER_FRONT_NAME" >/dev/null 2>&1; then
    note "保留现有容器：$DOCKER_FRONT_NAME"
    return 0
  fi
  run docker run -d --name "$DOCKER_FRONT_NAME" --restart unless-stopped --network host \
    -v "$PANEL_CONFIG_DIR/crproxy-front.conf:/etc/nginx/nginx.conf:ro" "$DOCKER_FRONT_IMAGE"
  if [ "$DRY_RUN" = 0 ]; then
    local code=''
    for _ in $(seq 1 40); do
      code=$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${DOCKER_FRONT_PORT}/v2/" 2>/dev/null || true)
      [ "$code" = 200 ] && break
      [ "$code" = 401 ] && break
      sleep 0.5
    done
    if [ "$code" != 200 ] && [ "$code" != 401 ]; then
      docker logs --tail 30 "$DOCKER_FRONT_NAME" >&2 || true
      die "Docker 镜像代理未通过健康检查（HTTP $code）"
    fi
  fi
}


uninstall_panel() {
  [ "$PANEL" = 1 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ remove node-warden.service and $PANEL_INSTALL_DIR\n'
    if [ "$PURGE" = 1 ]; then printf '+ remove %s and %s\n' "$PANEL_CONFIG_DIR" "$PANEL_DATA_DIR"; fi
    return 0
  fi
  if [ -f /etc/systemd/system/node-warden.service ]; then
    run systemctl disable --now node-warden.service || true
    run rm -f /etc/systemd/system/node-warden.service
    run systemctl daemon-reload
  fi
  run rm -rf "$PANEL_INSTALL_DIR"
  run rm -f /etc/logrotate.d/node-warden
  if [ "$PURGE" = 1 ]; then
    run rm -rf "$PANEL_CONFIG_DIR" "$PANEL_DATA_DIR"
  else
    note "保留面板配置和数据：$PANEL_CONFIG_DIR、$PANEL_DATA_DIR"
  fi
}

uninstall_ghproxy() {
  [ "$GHPROXY" = 1 ] || return 0
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ remove node-warden-ghproxy.service and %s\n' "$GHPROXY_DIR"
    return 0
  fi
  if [ -f /etc/systemd/system/node-warden-ghproxy.service ]; then
    run systemctl disable --now node-warden-ghproxy.service || true
    run rm -f /etc/systemd/system/node-warden-ghproxy.service
    run systemctl daemon-reload
  fi
  run rm -rf "$GHPROXY_DIR"
}

uninstall_docker_proxy() {
  [ "$DOCKER_PROXY" = 1 ] || return 0
  command -v docker >/dev/null 2>&1 || return 0
  run docker rm -f "$DOCKER_FRONT_NAME" || true
  run docker rm -f "$DOCKER_CRPROXY_NAME" || true
}

show_status() {
  note "Node Warden $VERSION"
  if panel_installed; then
    local state public
    state=$(systemctl is-active node-warden.service 2>/dev/null || true)
    public=$(panel_env_value PANEL_PUBLIC_URL)
    printf '面板：%s  %s\n' "$state" "${public:-未设置对外地址}"
    systemctl status node-warden.service --no-pager -n 3 2>/dev/null || true
  else
    note '面板：未安装'
  fi
  local gh_unit=''
  for gh_unit in node-warden-ghproxy.service ghproxy.service; do
    if [ -f "/etc/systemd/system/$gh_unit" ] || [ -f "/lib/systemd/system/$gh_unit" ]; then break; fi
    gh_unit=''
  done
  if [ -n "$gh_unit" ]; then
    printf 'GitHub 下载代理：%s 127.0.0.1:%s\n' "$(systemctl is-active "$gh_unit" 2>/dev/null || true)" "$GHPROXY_PORT"
  else
    note 'GitHub 下载代理：未安装'
  fi
  if command -v docker >/dev/null 2>&1; then
    local state name
    for name in "$DOCKER_CRPROXY_NAME" crproxy-local; do
      state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)
      [ -n "$state" ] && break
    done
    printf 'Docker 镜像代理：%s 127.0.0.1:%s\n' "${state:-未安装}" "$DOCKER_PROXY_PORT"
    state=''
    for name in "$DOCKER_FRONT_NAME" crproxy-front; do
      state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || true)
      [ -n "$state" ] && break
    done
    printf 'Docker 修复层：%s 127.0.0.1:%s\n' "${state:-未安装}" "$DOCKER_FRONT_PORT"
  else
    note 'Docker：未安装'
  fi
  if command -v ss >/dev/null 2>&1; then
    note '监听端口：'
    ss -lntp 2>/dev/null | awk 'NR==1 || $4 ~ /:(9090|8080|8081|8082|8083)$/' || true
  fi
}

run_self_test() {
  need_cmd python3
  ensure_source
  source_dir_ready || die "找不到源码目录：$SRC_DIR"
  local python_bin
  python_bin=$(command -v python3)
  note 'Python 编译检查'
  "$python_bin" -m compileall -q "$SRC_DIR/app" "$SRC_DIR/tests" "$SRC_DIR/deploy/ghproxy.py"
  note 'Python 单元测试'
  (cd "$SRC_DIR" && "$python_bin" -m unittest discover -s tests -v)
  if command -v node >/dev/null 2>&1; then
    note 'JavaScript 语法检查'
    node --check "$SRC_DIR/static/app.js"
  else
    warn '未找到 node，跳过 JavaScript 语法检查。'
  fi
  note 'ghproxy 自检'
  "$python_bin" "$SRC_DIR/deploy/ghproxy.py" --self-test
  note 'Shell 语法检查'
  bash -n "$SRC_DIR/bootstrap.sh"
  local script
  for script in "$SRC_DIR"/deploy/*.sh; do [ -f "$script" ] && bash -n "$script"; done
  note '自检通过。'
}

CN_BACKUP_ROOT=/var/backups/node-warden-cn

cn_new_backup_dir() {
  local ts
  ts=$(date -u +%Y%m%d-%H%M%S)
  CN_BACKUP_DIR="$CN_BACKUP_ROOT/$ts"
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ create backup directory %s\n' "$CN_BACKUP_DIR" >&2
    printf '%s\n' "$CN_BACKUP_DIR"
    return 0
  fi
  install -d -m 0700 "$CN_BACKUP_DIR/files"
  chmod 0700 "$CN_BACKUP_ROOT"
  printf '%s\n' "$CN_BACKUP_DIR"
}

cn_latest_backup_dir() {
  [ -d "$CN_BACKUP_ROOT" ] || return 0
  ls -1 "$CN_BACKUP_ROOT" 2>/dev/null | sort | tail -n 1
}

cn_record_file() {
  local backup_dir=$1 path=$2
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ backup %s\n' "$path"
    return 0
  fi
  [ -e "$path" ] || { printf 'missing\t%s\n' "$path" >> "$backup_dir/manifest.tsv"; return 0; }
  run install -d -m 0700 "$backup_dir/files"
  run cp -a --parents "$path" "$backup_dir/files/"
  printf 'file\t%s\n' "$path" >> "$backup_dir/manifest.tsv"
}

cn_apt_file() {
  local file
  if [ -f /etc/apt/sources.list ]; then printf '%s\n' /etc/apt/sources.list; return 0; fi
  for file in /etc/apt/sources.list.d/*; do
    [ -f "$file" ] || continue
    if grep -qE '^(deb|URIs:)' "$file" 2>/dev/null; then printf '%s\n' "$file"; return 0; fi
  done
  return 1
}

cn_apply_apt_mirror() {
  local backup_dir=$1 source mirror tmp
  source=$(cn_apt_file) || die '未找到 APT 源文件'
  mirror=${APT_MIRROR%/}
  cn_record_file "$backup_dir" "$source"
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ replace ubuntu archive URLs in %s with %s/ubuntu\n' "$source" "$mirror"
    return 0
  fi
  tmp=$(mktemp)
  sed -e "s#http://[^ ]*ubuntu#${mirror}/ubuntu#g" -e "s#https://[^ ]*ubuntu#${mirror}/ubuntu#g" "$source" > "$tmp"
  install -m 0644 "$tmp" "$source"
  rm -f "$tmp"
  note "已设置 APT 镜像：$source"
}

cn_apply_bbr() {
  local backup_dir=$1 path=/etc/sysctl.d/99-node-warden-bbr.conf
  cn_record_file "$backup_dir" "$path"
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ enable BBR: net.core.default_qdisc=fq, net.ipv4.tcp_congestion_control=bbr\n'
    return 0
  fi
  install -d -m 0755 /etc/sysctl.d
  cat > "$path" <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
  chmod 0644 "$path"
  run modprobe tcp_bbr || true
  run sysctl -w net.core.default_qdisc=fq || true
  run sysctl -w net.ipv4.tcp_congestion_control=bbr || true
}

cn_apply_docker_mirror() {
  local backup_dir=$1 mirror=$2 daemon=/etc/docker/daemon.json
  command -v docker >/dev/null 2>&1 || { warn '未安装 Docker，跳过 Docker 镜像配置。'; return 0; }
  cn_record_file "$backup_dir" "$daemon"
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ set %s registry-mirrors to [%s]\n' "$daemon" "$mirror"
    return 0
  fi
  install -d -m 0755 /etc/docker
  python3 - "$daemon" "$mirror" <<'PY'
import json
import os
import sys

path, mirror = sys.argv[1], sys.argv[2]
data = {}
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as handle:
        data = json.load(handle)
data['registry-mirrors'] = [mirror]
text = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
tmp = path + '.tmp'
with open(tmp, 'w', encoding='utf-8') as handle:
    handle.write(text)
os.chmod(tmp, 0o644)
os.replace(tmp, path)
PY
  python3 -m json.tool "$daemon" >/dev/null
  run systemctl reload docker || run systemctl restart docker
  note "已设置 Docker 镜像：$mirror"
}

cn_setup() {
  require_root
  need_linux
  need_cmd python3
  local backup_dir
  backup_dir=$(cn_new_backup_dir) || die '无法创建备份目录'
  [ -n "$backup_dir" ] || backup_dir=$CN_BACKUP_DIR
  if [ "$DRY_RUN" = 0 ]; then printf '%s\n' "$backup_dir" > "$backup_dir/INFO"; fi
  if [ "$NO_APT" = 0 ]; then
    cn_apply_apt_mirror "$backup_dir"
  else
    note '已跳过 APT 镜像。'
  fi
  if [ "$NO_BBR" = 0 ]; then
    cn_apply_bbr "$backup_dir"
  else
    note '已跳过 BBR。'
  fi
  if [ -n "$DOCKER_MIRROR" ]; then
    cn_apply_docker_mirror "$backup_dir" "$DOCKER_MIRROR"
  fi
  if [ "$NO_APT_UPDATE" = 0 ]; then
    run apt-get update
  fi
  note "国内机设置完成。备份目录：$backup_dir"
  if [ "$DRY_RUN" = 0 ]; then
    note "恢复命令：bash bootstrap.sh cn-restore --backup-dir $backup_dir"
  fi
}

cn_restore_one() {
  local backup_dir=$1 kind=$2 path=$3
  case "$kind" in
    file)
      if [ ! -e "$backup_dir/files$path" ]; then warn "备份中缺少 $path，跳过。"; return 0; fi
      if [ -d "$backup_dir/files$path" ]; then
        run mkdir -p "$path"
        run cp -a "$backup_dir/files$path/." "$path/"
      else
        run cp -a "$backup_dir/files$path" "$path"
      fi
      ;;
    missing)
      run rm -f "$path"
      ;;
    *) warn "未知备份类型：$kind" ;;
  esac
}

cn_restore() {
  require_root
  need_linux
  local backup_dir=$BACKUP_DIR
  if [ -z "$backup_dir" ]; then
    local latest
    latest=$(cn_latest_backup_dir)
    [ -n "$latest" ] || die "未找到备份目录：$CN_BACKUP_ROOT"
    backup_dir="$CN_BACKUP_ROOT/$latest"
  fi
  [ -f "$backup_dir/manifest.tsv" ] || die "备份不完整：$backup_dir/manifest.tsv"
  note "从备份恢复：$backup_dir"
  local kind path
  while IFS=$'\t' read -r kind path; do
    [ -n "$path" ] || continue
    cn_restore_one "$backup_dir" "$kind" "$path"
  done < "$backup_dir/manifest.tsv"
  if [ "$DRY_RUN" = 0 ]; then
    if grep -q '/etc/apt/sources' "$backup_dir/manifest.tsv" 2>/dev/null; then run apt-get update; fi
    if grep -q 'sysctl.d' "$backup_dir/manifest.tsv" 2>/dev/null; then run sysctl --system || true; fi
    if command -v docker >/dev/null 2>&1 && grep -q '/etc/docker/daemon.json' "$backup_dir/manifest.tsv" 2>/dev/null; then
      run systemctl reload docker || run systemctl restart docker || true
    fi
  fi
  note '恢复完成。请检查服务状态。'
}


resolve_panel_url() {
  if [ -z "$PUBLIC_URL" ] && panel_installed; then
    PUBLIC_URL=$(panel_env_value PANEL_PUBLIC_URL)
  fi
  if [ -z "$CERT_DOMAIN" ] && [ -n "$PUBLIC_URL" ]; then
    local host=${PUBLIC_URL#*://}
    host=${host%%/*}
    host=${host%%:*}
    CERT_DOMAIN=$host
  fi
  if [ -z "$NODE_HOST" ] && [ -n "$CERT_DOMAIN" ]; then NODE_HOST=$CERT_DOMAIN; fi
  if [ -z "$PUBLIC_URL" ] && [ -n "$CERT_DOMAIN" ]; then
    PUBLIC_URL="https://${CERT_DOMAIN}${BASE_PATH}"
  fi
}


is_ipv4() {
  case "$1" in
    ''|*[!0-9.]*) return 1 ;;
  esac
  local IFS=.
  set -- $1
  [ $# -eq 4 ] || return 1
  local octet
  for octet in "$@"; do
    [ -n "$octet" ] || return 1
    [ "$octet" -le 255 ] 2>/dev/null || return 1
  done
}

is_domain() {
  case "$1" in
    *.*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!A-Za-z0-9.-]*|.*|*.) return 1 ;;
  esac
}

cert_not_expired() {
  [ -f "$1" ] || return 1
  if command -v openssl >/dev/null 2>&1; then
    openssl x509 -checkend 0 -noout -in "$1" >/dev/null 2>&1
  else
    return 0
  fi
}

detect_domain() {
  local value domain cert
  if [ -n "${CERT_DOMAIN:-}" ] && is_domain "$CERT_DOMAIN"; then
    printf '%s\n' "$CERT_DOMAIN"
    return 0
  fi
  value=$(panel_env_value PANEL_CERT_DOMAIN)
  [ -n "$value" ] || value=$(panel_env_value PANEL_PUBLIC_URL)
  if [ -n "$value" ]; then
    case "$value" in
      *://*) domain=${value#*://}; domain=${domain%%/*}; domain=${domain%%:*} ;;
      *) domain=$value ;;
    esac
    if is_domain "$domain"; then
      printf '%s\n' "$domain"
      return 0
    fi
  fi
  if command -v certbot >/dev/null 2>&1; then
    value=$(certbot certificates 2>/dev/null | awk '/Certificate Name:/ { name=$3 } /Domains:/ { print name " " $2; exit }')
    if [ -n "$value" ]; then
      domain=${value#* }
      domain=${domain%%,*}
      cert="/etc/letsencrypt/live/${value%% *}/fullchain.pem"
      if is_domain "$domain" && cert_not_expired "$cert"; then
        printf '%s\n' "$domain"
        return 0
      fi
    fi
  fi
  for cert in /etc/letsencrypt/live/*/fullchain.pem; do
    [ -f "$cert" ] || continue
    domain=${cert#/etc/letsencrypt/live/}
    domain=${domain%%/*}
    if is_domain "$domain" && cert_not_expired "$cert"; then
      printf '%s\n' "$domain"
      return 0
    fi
  done
  if command -v hostname >/dev/null 2>&1; then
    value=$(hostname -f 2>/dev/null || true)
    if is_domain "$value"; then
      printf '%s\n' "$value"
      return 0
    fi
  fi
  return 1
}

detect_public_ip() {
  local ip url
  if command -v curl >/dev/null 2>&1; then
    for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
      ip=$(curl -4 -fsS --max-time 6 "$url" 2>/dev/null | tr -d '\r\n' | head -c 64 || true)
      if is_ipv4 "$ip"; then
        printf '%s\n' "$ip"
        return 0
      fi
    done
  fi
  ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  if is_ipv4 "$ip"; then
    printf '%s\n' "$ip"
    return 0
  fi
  return 1
}

auto_configure_public_url() {
  [ -n "$PUBLIC_URL" ] && return 0
  [ -n "$CERT_DOMAIN" ] && return 0
  local domain ip
  domain=$(detect_domain || true)
  if [ -n "$domain" ]; then
    CERT_DOMAIN=$domain
    PUBLIC_URL="https://${domain}${BASE_PATH}"
    note "检测到域名：${domain}"
    return 0
  fi
  ip=$(detect_public_ip || true)
  if [ -n "$ip" ]; then
    CERT_DOMAIN=$ip
    PUBLIC_URL="http://${ip}${BASE_PATH}"
    warn "未检测到域名，使用 HTTP 地址：${PUBLIC_URL}"
    warn '需要在 80 端口提供反向代理，或改用 --public-url / --domain 指定域名。'
    return 0
  fi
  CERT_DOMAIN=127.0.0.1
  PUBLIC_URL="http://127.0.0.1:9090${BASE_PATH}"
  warn "未检测到域名和公网地址，使用本机地址：${PUBLIC_URL}"
  warn '请通过 SSH 隧道访问，或配置反向代理。'
}

ensure_certificate() {
  [ "$AUTO_CERT" = 1 ] || return 0
  [ -n "$CERT_DOMAIN" ] || return 0
  if ! is_domain "$CERT_DOMAIN"; then
    note "跳过自动证书：未提供域名（${CERT_DOMAIN}）。"
    return 0
  fi
  if [ -f "/etc/letsencrypt/live/${CERT_DOMAIN}/fullchain.pem" ]; then
    return 0
  fi
  if ! command -v certbot >/dev/null 2>&1; then
    warn '未找到 certbot，跳过自动证书申请。'
    return 0
  fi
  if ! command -v nginx >/dev/null 2>&1; then
    warn '未找到 nginx，跳过自动证书申请；请先配置 80 端口反向代理。'
    return 0
  fi
  local args=(certonly --nginx -d "$CERT_DOMAIN" --non-interactive --agree-tos)
  if [ -n "$ACME_EMAIL" ]; then
    args+=(--email "$ACME_EMAIL")
  else
    args+=(--register-unsafely-without-email)
  fi
  note "申请证书：${CERT_DOMAIN}"
  if [ "$DRY_RUN" = 1 ]; then
    printf '+ certbot %s\n' "${args[*]}"
    return 0
  fi
  if ! certbot "${args[@]}"; then
    warn '证书申请失败，继续安装；可稍后手动运行 certbot。'
    return 0
  fi
  note '证书申请完成。'
}

tty_available() { ( : < /dev/tty ) >/dev/null 2>&1; }

ask_value() {
  local prompt=$1 default=$2 out=$3 answer=''
  if [ -n "$default" ]; then
    printf '%s [%s]: ' "$prompt" "$default" > /dev/tty
  else
    printf '%s: ' "$prompt" > /dev/tty
  fi
  IFS= read -r answer < /dev/tty || return 1
  [ -n "$answer" ] || answer=$default
  printf -v "$out" '%s' "$answer"
}

ask_yes_no() {
  local prompt=$1 default=$2 answer=''
  while :; do
    if [ "$default" = y ]; then
      printf '%s [Y/n]: ' "$prompt" > /dev/tty
    else
      printf '%s [y/N]: ' "$prompt" > /dev/tty
    fi
    IFS= read -r answer < /dev/tty || return 1
    [ -n "$answer" ] || answer=$default
    case "$answer" in
      y|Y|yes|YES) return 0 ;;
      n|N|no|NO) return 1 ;;
      *) note '请输入 y 或 n。' ;;
    esac
  done
}

interactive_install() {
  [ "$DRY_RUN" = 0 ] || return 0
  [ "$NON_INTERACTIVE" = 0 ] || return 0
  tty_available || return 0
  note 'Node Warden 安装向导'
  local default_scope=1 input detected
  if [ "$PANEL" = 1 ] && [ "$GHPROXY" = 0 ] && [ "$DOCKER_PROXY" = 0 ]; then default_scope=2; fi
  if [ "$PANEL" = 0 ]; then default_scope=3; fi
  ask_value '安装组件 [1] 全部 [2] 仅面板 [3] 仅代理' "$default_scope" input
  case "$input" in
    1) PANEL=1; GHPROXY=1; DOCKER_PROXY=1 ;;
    2) PANEL=1; GHPROXY=0; DOCKER_PROXY=0 ;;
    3) PANEL=0; GHPROXY=1; DOCKER_PROXY=1 ;;
    *) die '安装组件选择无效' ;;
  esac
  ask_value '面板路径' "$BASE_PATH" BASE_PATH
  if [ -z "$PUBLIC_URL" ] && [ -z "$CERT_DOMAIN" ]; then
    detected=$(detect_domain || true)
    ask_value '面板域名或完整 URL（留空自动检测；无域名使用 HTTP）' "$detected" input
    if [ -n "$input" ]; then
      case "$input" in
        http://*|https://*) PUBLIC_URL=$input ;;
        *[!A-Za-z0-9.:/-]*) die '域名或 URL 包含无效字符' ;;
        *)
          if is_ipv4 "$input"; then
            CERT_DOMAIN=$input
            PUBLIC_URL="http://${input}${BASE_PATH}"
          else
            CERT_DOMAIN=$input
            PUBLIC_URL="https://${input}${BASE_PATH}"
          fi
          ;;
      esac
    fi
  fi
  if [ "$ASSUME_YES" = 0 ]; then
    ask_yes_no '确认开始安装？' y || die '已取消安装'
  fi
}

show_cn_hint() {
  local url=${CN_SCRIPT_URL:-}
  if [ -z "$url" ] && [ "$PANEL" = 1 ] && [ -n "$PUBLIC_URL" ]; then
    url="${PUBLIC_URL%/}/bootstrap.sh"
  fi
  note ''
  note '国内网络设置（可选）：'
  if [ -n "$url" ]; then
    printf '脚本地址：%s\n' "$url"
    printf '执行：sudo bash <(curl -fsSL %s) cn-setup\n' "$url"
  else
    printf '在源码目录执行：sudo bash bootstrap.sh cn-setup\n'
  fi
  if [ "$DRY_RUN" = 0 ] && [ "$NON_INTERACTIVE" = 0 ] && tty_available; then
    if ask_yes_no '现在执行国内网络设置？' n; then
      cn_setup
    fi
  fi
}

main() {
  parse_options "$@"
  VERSION=$(cat "$SRC_DIR/VERSION" 2>/dev/null || printf 'unknown')
  validate_base_path
  validate_options
  case "$COMMAND" in
    help|-h|--help)
      usage
      ;;
    install)
      require_root
      need_linux
      interactive_install
      sync_source
      if [ "$DRY_RUN" = 0 ]; then source_dir_ready || die "找不到源码目录：$SRC_DIR"; fi
      resolve_panel_url
      if [ "$PANEL" = 1 ]; then
        if [ "$DRY_RUN" = 0 ]; then auto_configure_public_url; fi
        resolve_panel_url
        ensure_certificate
      fi
      install_panel
      install_ghproxy
      install_docker_proxy
      configure_panel_proxy_env
      show_status
      show_cn_hint
      ;;
    update)
      require_root
      need_linux
      sync_source
      if [ "$DRY_RUN" = 0 ]; then source_dir_ready || die "找不到源码目录：$SRC_DIR"; fi
      resolve_panel_url
      if [ "$PANEL" = 1 ] && [ "$DRY_RUN" = 0 ]; then auto_configure_public_url; resolve_panel_url; ensure_certificate; fi
      install_panel
      install_ghproxy
      install_docker_proxy
      configure_panel_proxy_env
      show_status
      ;;
    uninstall)
      require_root
      need_linux
      uninstall_docker_proxy
      uninstall_ghproxy
      uninstall_panel
      show_status
      ;;
    status)
      require_root
      show_status
      ;;
    self-test)
      run_self_test
      ;;
    cn-setup)
      cn_setup
      ;;
    cn-restore)
      cn_restore
      ;;
    *)
      usage
      die "未知命令：$COMMAND"
      ;;
  esac
}

main "$@"
