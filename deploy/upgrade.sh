#!/usr/bin/env bash
# Upgrade Node Warden: replace program files, keep /etc/node-warden and /var/lib/node-warden.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec bash "$ROOT_DIR/deploy/install.sh" --upgrade "$@"
