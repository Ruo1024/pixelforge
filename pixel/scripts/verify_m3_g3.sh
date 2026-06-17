#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/configure_editor_game_view.sh
./scripts/lint.sh
./scripts/run_tests.sh
./scripts/check_ui_scaling.sh
./scripts/check_export_templates.sh

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git diff --cached --name-only | grep -iE '\.png$|\.jpe?g$' >/dev/null; then
    echo "Staged image files are not allowed for M3 G-3 commits." >&2
    exit 1
  fi
fi

echo "verify_m3_g3: ok"
