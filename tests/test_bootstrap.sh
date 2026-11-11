#!/usr/bin/env bash
# Test bootstrap option validation and interactive wizard without touching the system.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LIB=$(mktemp)
trap 'rm -f "$LIB"' EXIT
sed -n '1,/^main() {/p' "$ROOT_DIR/bootstrap.sh" | sed '$d' > "$LIB"
# shellcheck disable=SC1090
. "$LIB"

fail() { printf 'bootstrap test failed: %s\n' "$1" >&2; exit 1; }

validate_options
CERT_DOMAIN=example.com validate_options
if is_domain 203.0.113.9; then fail 'IP accepted as domain'; fi
( PUBLIC_URL='' CERT_DOMAIN=203.0.113.9; resolve_panel_url; [ "$PUBLIC_URL" = 'http://203.0.113.9/warden' ] ) || fail 'IP public URL uses HTTP'
if ( CERT_DOMAIN='bad domain'; validate_options ) >/dev/null 2>&1; then fail 'bad domain accepted'; fi
if ( PUBLIC_URL='https://panel.example.com/wrong'; validate_options ) >/dev/null 2>&1; then fail 'bad path accepted'; fi
if ( PUBLIC_URL='http://'; validate_options ) >/dev/null 2>&1; then fail 'empty URL accepted'; fi
if ( ACME_EMAIL='bad'; validate_options ) >/dev/null 2>&1; then fail 'bad email accepted'; fi
if ( GHPROXY_PORT=70000; validate_options ) >/dev/null 2>&1; then fail 'bad port accepted'; fi
if ( BASE_PATH='/../etc'; validate_base_path ) >/dev/null 2>&1; then fail 'bad base path accepted'; fi

(
  tty_available() { return 0; }
  detect_domain() { printf '%s\n' 'detected.example.com'; }
  ask_value() { printf -v "$3" '%s' "${answers[$index]}"; index=$((index + 1)); }
  ask_yes_no() { return 0; }
  DRY_RUN=0
  NON_INTERACTIVE=0
  ASSUME_YES=0
  PUBLIC_URL=''
  CERT_DOMAIN=''
  PANEL=1
  GHPROXY=1
  DOCKER_PROXY=1
  BASE_PATH=/warden
  index=0
  answers=('1' '/warden' 'example.com' 'y')
  interactive_install >/dev/null
  [ "$PUBLIC_URL" = 'https://example.com/warden' ] || fail 'interactive public URL'
  [ "$CERT_DOMAIN" = 'example.com' ] || fail 'interactive certificate domain'
)

(
  detect_domain() { return 1; }
  detect_public_ip() { printf '%s\n' '203.0.113.9'; }
  PUBLIC_URL=''
  CERT_DOMAIN=''
  auto_configure_public_url >/dev/null 2>&1
  [ "$PUBLIC_URL" = 'http://203.0.113.9/warden' ] || fail 'automatic IP URL'
  [ "$CERT_DOMAIN" = '203.0.113.9' ] || fail 'automatic IP certificate domain'
)

tmp_gateway=$(mktemp -d)
trap 'rm -rf "$tmp_gateway"; rm -f "$LIB"' EXIT
(
  GATEWAY_CONFIG="$tmp_gateway/gateway.conf"
  GATEWAY_ACME_ROOT="$tmp_gateway/acme"
  BASE_PATH=/warden
  CERT_DOMAIN=example.com
  PANEL=1
  DOCKER_PROXY=1
  GHPROXY=1
  DRY_RUN=0
  write_gateway_config 0
  grep -q 'location /warden/' "$GATEWAY_CONFIG" || fail 'gateway panel route'
  grep -q 'proxy_pass http://127.0.0.1:9090' "$GATEWAY_CONFIG" || fail 'gateway panel upstream'
  grep -q 'location /v2/' "$GATEWAY_CONFIG" || fail 'gateway docker route'
  grep -q 'proxy_pass http://127.0.0.1:8082' "$GATEWAY_CONFIG" || fail 'gateway ghproxy route'
  grep -q 'stub_status' "$GATEWAY_CONFIG" || fail 'gateway status stub'
)
(
  GATEWAY_CONFIG="$tmp_gateway/panel-only.conf"
  GATEWAY_ACME_ROOT="$tmp_gateway/acme"
  BASE_PATH=/warden
  CERT_DOMAIN=example.com
  PANEL=1
  DOCKER_PROXY=0
  GHPROXY=0
  DRY_RUN=0
  write_gateway_config 0
  grep -q 'location /warden/' "$GATEWAY_CONFIG" || fail 'panel-only route'
  if grep -q 'location /v2/' "$GATEWAY_CONFIG"; then fail 'panel-only docker route'; fi
)
(
  PUBLIC_URL=https://example.com/warden
  BASE_PATH=/warden
  [ "$(public_origin)" = 'https://example.com' ] || fail 'public origin'
)
(
  PANEL=1
  GHPROXY=1
  DOCKER_PROXY=1
  GATEWAY=1
  GATEWAY_ATTEMPTED=1
  SERVICES_TMP=''
  out=$(prepare_default_services "$ROOT_DIR/examples/services.example.json")
  [ -s "$out" ] || fail 'generated services file is empty'
  python - "$out" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as handle:
    data = json.load(handle)
ids = [item['id'] for item in data.get('services', [])]
for wanted in ('gateway', 'crproxy-local', 'crproxy-front', 'ghproxy'):
    if wanted not in ids:
        raise SystemExit('missing service: ' + wanted)
if 'sing-box' in ids:
    raise SystemExit('unexpected sing-box service')
gateway = next(item for item in data['services'] if item['id'] == 'gateway')
if 'reload' not in gateway.get('actions', []):
    raise SystemExit('gateway reload action missing')
if not gateway.get('nginx'):
    raise SystemExit('gateway nginx flag missing')
PY
  rm -f "$out"
)

printf 'bootstrap tests ok\n'
