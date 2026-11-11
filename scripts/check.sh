#!/usr/bin/env bash
# Run local checks before committing or deploying.
set -euo pipefail
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PYTHON_BIN=${PYTHON_BIN:-python3}
cd "$ROOT_DIR"
"$PYTHON_BIN" -m compileall -q app tests deploy/ghproxy.py
"$PYTHON_BIN" -m unittest discover -s tests -v
"$PYTHON_BIN" deploy/ghproxy.py --self-test
bash -n bootstrap.sh
bash tests/test_bootstrap.sh
bash tests/test_toolbox.sh
for script in deploy/*.sh; do
  bash -n "$script"
done
if command -v node >/dev/null 2>&1; then
  node --check static/app.js
  printf 'JavaScript 语法检查通过。\n'
else
  printf '未找到 node，跳过 static/app.js 语法检查。\n'
fi
