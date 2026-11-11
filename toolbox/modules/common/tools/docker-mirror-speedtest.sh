#!/usr/bin/env bash
# =============================================================================
# docker-mirror-speedtest.sh — Docker Hub 镜像加速器测速（支持"直连 vs 代理"对照）
# -----------------------------------------------------------------------------
# 功能：
#   1. 测试候选镜像源的 /v2/、token、manifest、blob 下载速度
#   2. 配置了代理时，同一个源会分别测"直连"和"走代理"两次，表格并排对比
#   3. 检测各源能否拉取"非白名单仓库"（如 coollabsio/coolify-helper）
#   4. 可选 --apply：把直连测速最快的源写回 /etc/docker/daemon.json 并 reload
#
# 依赖：bash、curl、python3；--apply 需要 root 和 systemctl
#
# 用法：
#   bash docker-mirror-speedtest.sh                          # 只测直连
#   bash docker-mirror-speedtest.sh --proxy socks5://u:p@127.0.0.1:1080   # 本地 DNS（不带 h）
#                                                            # 直连 + 代理 对照
#   bash docker-mirror-speedtest.sh --proxy ... --proxy-only # 只测代理
#   bash docker-mirror-speedtest.sh --proxy ... --direct-only# 忽略代理，只测直连
#   bash docker-mirror-speedtest.sh --seconds 10             # 每源采样 10 秒
#   bash docker-mirror-speedtest.sh --apply                  # 测速并写回直连最快的源
#
# 定时任务示例：
#   */30 * * * * /usr/local/bin/docker-mirror-speedtest.sh --apply --quiet >>/var/log/docker-mirror-speedtest.log 2>&1
# =============================================================================

set -uo pipefail

# ---------------------------- 默认配置 --------------------------------------
SAMPLE_SECONDS=8
MIN_SPEED_MB=0.8
MAX_MIRRORS=3
REPO="library/node"
TAG="20"
CATALOG_REPO="coollabsio/coolify-helper"
CATALOG_TAG="1.0.19"
DAEMON_JSON="/etc/docker/daemon.json"
MIRRORS="docker.m.daocloud.io docker.1ms.run hub.rat.dev proxy.vvvv.ee docker.xuanyuan.me docker.1panel.top"

# ========== 可选代理（默认注释；需要时取消注释） ==========
# 本脚本里的代理只用于"测速请求"；要让 dockerd 拉镜像也走代理，需另配 systemd drop-in：
#
#   mkdir -p /etc/systemd/system/docker.service.d
#   cat > /etc/systemd/system/docker.service.d/proxy.conf <<'EOF'
#   [Service]
#   Environment="HTTP_PROXY=socks5://user:pass@host:port"
#   Environment="HTTPS_PROXY=socks5://user:pass@host:port"
#   Environment="NO_PROXY=localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
#   EOF
#   systemctl daemon-reload && systemctl restart docker
#
# 说明：socks5:// = 本地解析 DNS，只有流量走代理；socks5h:// = DNS 也交给代理。
# 旧机 /etc/systemd/system/docker.service.d/proxy.conf 里曾有一个被注释的 socks5 代理，
# 如果还在用，取消下面注释并填入地址：
# # 代理示例已移除；需要时使用 --proxy 参数。
# PROXY="http://127.0.0.1:3128"
PROXY=""

# ---------------------------- 参数解析 --------------------------------------
APPLY=false
QUIET=false
MODE="auto"     # auto / direct / both / proxy

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)       APPLY=true; shift ;;
    --quiet)       QUIET=true; shift ;;
    --proxy)       PROXY="$2"; shift 2 ;;
    --both)        MODE="both"; shift ;;
    --proxy-only)  MODE="proxy"; shift ;;
    --direct-only) MODE="direct"; shift ;;
    --repo)        REPO="$2"; shift 2 ;;
    --tag)         TAG="$2"; shift 2 ;;
    --seconds)     SAMPLE_SECONDS="$2"; shift 2 ;;
    --min-speed)   MIN_SPEED_MB="$2"; shift 2 ;;
    -h|--help)     sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "未知参数: $1（--help 查看用法）" >&2; exit 1 ;;
  esac
done

case "$SAMPLE_SECONDS" in
  ''|*[!0-9]*) echo "SAMPLE_SECONDS 必须是整数" >&2; exit 1 ;;
esac
[ "$SAMPLE_SECONDS" -ge 2 ] || { echo "SAMPLE_SECONDS 必须 >= 2" >&2; exit 1; }

if [ "$MODE" = "auto" ]; then
  if [ -n "$PROXY" ]; then MODE="both"; else MODE="direct"; fi
fi
case "$MODE" in
  direct|proxy|both) ;;
  *) echo "MODE 非法: $MODE" >&2; exit 1 ;;
esac
if [ "$MODE" = "proxy" ] && [ -z "$PROXY" ]; then
  echo "--proxy-only 需要配合 --proxy <地址>" >&2; exit 1
fi

CURL_BASE="-sS -L --connect-timeout 5"
ACCEPT="application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

log() { $QUIET || echo "$@"; }

# probe 结果（全局）
V2="000"; V2T="0"; MAN="000"; SPEED="0"; CATALOG="-"

# 当前 curl 选项（probe 内会根据是否走代理重设）
CUR_OPTS="$CURL_BASE"

parse_manifest() {
  python3 - "$1" <<'PY'
import sys, json
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("error -"); sys.exit(0)
if isinstance(d, dict) and "manifests" in d:
    for m in d["manifests"]:
        p = m.get("platform") or {}
        if p.get("architecture") == "amd64" and p.get("os") == "linux":
            print("index", m["digest"]); sys.exit(0)
    print("index", d["manifests"][0]["digest"]); sys.exit(0)
layers = d.get("layers") or []
if layers:
    layers.sort(key=lambda x: x.get("size", 0), reverse=True)
    print("layer", layers[0]["digest"], layers[0]["size"])
else:
    print("error -")
PY
}

get_token() {
  local realm="$1" svc="$2" repo="$3"
  curl $CUR_OPTS -m 10 "$realm?service=$svc&scope=repository:$repo:pull" 2>/dev/null \
    | python3 -c 'import sys,json
try:
    j = json.load(sys.stdin)
    print(j.get("token") or j.get("access_token") or "")
except Exception:
    print("")' 2>/dev/null
}

# probe <host> <proxy|"">
probe() {
  local host="$1" px="$2"
  local headers mfile wa realm svc token mcode ctoken ccode
  local kind a b digest

  CUR_OPTS="$CURL_BASE"
  [ -n "$px" ] && CUR_OPTS="$CUR_OPTS --proxy $px"

  V2="000"; V2T="0"; MAN="000"; SPEED="0"; CATALOG="-"

  # 1) /v2/ 连通性
  read -r V2 V2T < <(curl $CUR_OPTS -o /dev/null -m 10 \
      -w '%{http_code} %{time_total}' "https://$host/v2/" 2>/dev/null || echo "000 0")

  # 2) 认证信息
  headers="$TMPDIR/hdrs.$$"
  : > "$headers"
  curl $CUR_OPTS -D "$headers" -o /dev/null -m 10 "https://$host/v2/" >/dev/null 2>&1 || true
  wa="$(grep -i '^www-authenticate:' "$headers" 2>/dev/null | tail -1 | tr -d '\r')"
  realm="$(sed -n 's/.*realm="\([^"]*\)".*/\1/p' <<<"$wa")"
  svc="$(sed -n 's/.*service="\([^"]*\)".*/\1/p' <<<"$wa")"
  [ -z "$realm" ] && realm="https://$host/token"
  [ -z "$svc" ] && svc="docker.io"

  token=""
  [ -n "$wa" ] && token="$(get_token "$realm" "$svc" "$REPO")"

  # 3) manifest + 最大层
  mfile="$TMPDIR/manifest.$$"
  : > "$mfile"
  set --
  [ -n "$token" ] && set -- -H "Authorization: Bearer $token"
  mcode="$(curl $CUR_OPTS -m 15 -o "$mfile" -w '%{http_code}' \
      -H "Accept: $ACCEPT" "$@" \
      "https://$host/v2/$REPO/manifests/$TAG" 2>/dev/null || echo "000")"
  MAN="$mcode"
  digest=""
  if [ "$mcode" = "200" ]; then
    read -r kind a b < <(parse_manifest "$mfile")
    if [ "$kind" = "index" ]; then
      curl $CUR_OPTS -m 15 -o "$mfile" -H "Accept: $ACCEPT" "$@" \
        "https://$host/v2/$REPO/manifests/$a" >/dev/null 2>&1 || true
      read -r kind a b < <(parse_manifest "$mfile")
    fi
    [ "$kind" = "layer" ] && digest="$a"
  fi

  # 4) blob 采样
  if [ -n "$digest" ]; then
    SPEED="$(curl $CUR_OPTS -m "$SAMPLE_SECONDS" -o /dev/null -w '%{speed_download}' \
      "$@" "https://$host/v2/$REPO/blobs/$digest" 2>/dev/null || true)"
    [ -z "$SPEED" ] && SPEED="0"
  fi

  # 5) 白名单检查（无 token 时退回匿名）
  ctoken=""
  [ -n "$token" ] && ctoken="$(get_token "$realm" "$svc" "$CATALOG_REPO")"
  set --
  [ -n "$ctoken" ] && set -- -H "Authorization: Bearer $ctoken"
  ccode="$(curl $CUR_OPTS -m 10 -o /dev/null -w '%{http_code}' "$@" \
    "https://$host/v2/$CATALOG_REPO/manifests/$CATALOG_TAG" 2>/dev/null || echo "000")"
  case "$ccode" in
    200) CATALOG="yes" ;;
    403) CATALOG="DENIED" ;;
    *)   CATALOG="$ccode" ;;
  esac
}

# ---------------------------- 逐源测试 --------------------------------------
ROWS="$TMPDIR/rows.tsv"
: > "$ROWS"

if [ -n "$PROXY" ]; then
  log "模式: $MODE   代理: $PROXY"
else
  log "模式: $MODE"
fi

for host in $MIRRORS; do
  DV2="-"; DMAN="-"; DSPEED="0"; DV2T="-"; DCAT="-"; DSPEED_MB="0.00"
  PV2="-"; PMAN="-"; PSPEED="0"; PV2T="-"; PCAT="-"; PSPEED_MB="0.00"
  sortkey="0"

  if [ "$MODE" = "direct" ] || [ "$MODE" = "both" ]; then
    log "直连测试 $host ..."
    probe "$host" ""
    DV2="$V2"; DMAN="$MAN"; DSPEED="$SPEED"; DV2T="$V2T"; DCAT="$CATALOG"
    DSPEED_MB="$(awk -v b="$DSPEED" 'BEGIN{printf "%.2f", b/1048576}')"
  fi

  if [ "$MODE" = "proxy" ] || [ "$MODE" = "both" ]; then
    log "代理测试 $host ..."
    probe "$host" "$PROXY"
    PV2="$V2"; PMAN="$MAN"; PSPEED="$SPEED"; PV2T="$V2T"; PCAT="$CATALOG"
    PSPEED_MB="$(awk -v b="$PSPEED" 'BEGIN{printf "%.2f", b/1048576}')"
  fi

  sortkey="$(awk -v d="$DSPEED" -v p="$PSPEED" 'BEGIN{print (d>p?d:p)}')"
  cat_now="$DCAT"
  [ "$cat_now" = "-" ] && cat_now="$PCAT"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$host" "$DV2" "$DMAN" "$DSPEED_MB" "$PV2" "$PMAN" "$PSPEED_MB" "$sortkey" "$cat_now" >> "$ROWS"
done

# ---------------------------- 结果表格 --------------------------------------
if ! $QUIET; then
  if [ "$MODE" = "direct" ]; then
    printf '\n%-24s %4s %4s %12s %8s %s\n' "MIRROR" "V2" "MAN" "DIRECT(MB/s)" "CATALOG" "STATUS"
  elif [ "$MODE" = "proxy" ]; then
    printf '\n%-24s %4s %4s %12s %8s %s\n' "MIRROR" "V2" "MAN" "PROXY(MB/s)" "CATALOG" "STATUS"
  else
    printf '\n%-24s %4s %4s %12s | %4s %4s %12s | %8s %s\n' \
      "MIRROR" "V2d" "MANd" "DIRECT(MB/s)" "V2p" "MANp" "PROXY(MB/s)" "CATALOG" "STATUS"
  fi
  printf '%s\n' "-------------------------------------------------------------------------------------------"
fi

sort -t"$(printf '\t')" -k8,8 -rn "$ROWS" | while IFS="$(printf '\t')" read -r host dv2 dman dsp pv2 pman psp sortkey cat;
do
  status="OK"
  d_ok=$(awk -v s="$dsp" -v min="$MIN_SPEED_MB" -v m="$dman" 'BEGIN{print (m=="200" && s>=min)?"1":"0"}')
  p_ok=$(awk -v s="$psp" -v min="$MIN_SPEED_MB" -v m="$pman" 'BEGIN{print (m=="200" && s>=min)?"1":"0"}')
  if [ "$d_ok" = "1" ] || [ "$p_ok" = "1" ]; then
    status="OK"
  elif [ "$dman" = "200" ] || [ "$pman" = "200" ]; then
    status="slow"
  else
    status="fail"
  fi
  if $QUIET; then
    printf '%s d=%s/%s p=%s/%s cat=%s\n' "$host" "$dv2" "$dsp" "$pv2" "$psp" "$cat"
  elif [ "$MODE" = "direct" ]; then
    printf '%-24s %4s %4s %12s %8s %s\n' "$host" "$dv2" "$dman" "$dsp" "$cat" "$status"
  elif [ "$MODE" = "proxy" ]; then
    printf '%-24s %4s %4s %12s %8s %s\n' "$host" "$pv2" "$pman" "$psp" "$cat" "$status"
  else
    printf '%-24s %4s %4s %12s | %4s %4s %12s | %8s %s\n' \
      "$host" "$dv2" "$dman" "$dsp" "$pv2" "$pman" "$psp" "$cat" "$status"
  fi
done

# ---------------------------- 可选：写回 daemon.json ------------------------
if $APPLY; then
  [ "$(id -u)" -eq 0 ] || { echo "--apply 需要 root 权限" >&2; exit 1; }

  awk -F"$(printf '\t')" -v min="$MIN_SPEED_MB" \
    '($3 == "200") && ($4+0 >= min) { printf "%.0f\t%s\n", $4, $1 }' "$ROWS" \
    | sort -t"$(printf '\t')" -k1,1 -rn | head -n "$MAX_MIRRORS" | cut -f2 > "$TMPDIR/hosts.txt"

  if [ ! -s "$TMPDIR/hosts.txt" ]; then
    echo "没有直连达标的镜像源（阈值 $MIN_SPEED_MB MB/s），跳过 --apply" >&2
    exit 2
  fi

  ts="$(date +%Y%m%d-%H%M%S)"
  [ -f "$DAEMON_JSON" ] && cp -a "$DAEMON_JSON" "$DAEMON_JSON.bak-$ts"
  python3 - "$DAEMON_JSON" "$TMPDIR/hosts.txt" <<'PY'
import json, sys, os
path, hosts_file = sys.argv[1], sys.argv[2]
hosts = [l.strip() for l in open(hosts_file) if l.strip()]
cfg = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    try:
        with open(path) as f:
            cfg = json.load(f)
    except Exception as e:
        print("现有 daemon.json 不是合法 JSON: %s" % e, file=sys.stderr)
        sys.exit(1)
cfg["registry-mirrors"] = ["https://" + h for h in hosts]
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print("已写入 registry-mirrors（按直连速度）:")
for h in hosts:
    print("  https://" + h)
PY
  if ! python3 -m json.tool "$DAEMON_JSON" >/dev/null 2>&1; then
    echo "写出的 daemon.json 校验失败" >&2; exit 3
  fi
  if systemctl reload docker 2>/dev/null; then
    echo "已 systemctl reload docker（SIGHUP 热加载，不中断容器）"
  elif systemctl restart docker 2>/dev/null; then
    echo "reload 不可用，已 restart docker"
  else
    echo "警告：docker reload/restart 失败，请手动处理" >&2
  fi
  docker info 2>/dev/null | sed -n '/Registry Mirrors/,+5p' || true
fi

exit 0