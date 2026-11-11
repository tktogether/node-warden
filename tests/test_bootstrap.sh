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

printf 'bootstrap tests ok\n'
