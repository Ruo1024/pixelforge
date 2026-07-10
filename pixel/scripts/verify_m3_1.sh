#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/configure_editor_game_view.sh
./pixel/scripts/lint.sh
./pixel/scripts/run_tests.sh
./pixel/scripts/check_ui_scaling.sh
./pixel/scripts/check_export_templates.sh

staged_files="$(git diff --cached --name-only)"
if printf '%s\n' "${staged_files}" | grep -iE '\.(png|jpe?g)$' >/dev/null; then
  echo "Staged image files are not allowed for M3.1 commits." >&2
  exit 1
fi

if printf '%s\n' "${staged_files}" \
  | grep -E '^(test picture/|pixel/tests/fixtures/real/|垃圾桶/|godot-interactive-guide/)' \
  >/dev/null; then
  echo "Protected local reference files are not allowed for M3.1 commits." >&2
  exit 1
fi

echo "verify_m3_1: ok"
