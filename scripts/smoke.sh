#!/usr/bin/env bash
# Check that a running Node Warden answers the unauthenticated session endpoint.
set -euo pipefail
URL=${1:-http://127.0.0.1:9090/warden/api/session}
CODE=$(curl -sS -o /tmp/node-warden-session.json -w '%{http_code}' "$URL")
printf 'HTTP %s\n' "$CODE"
cat /tmp/node-warden-session.json
printf '\n'
[ "$CODE" = 200 ]
