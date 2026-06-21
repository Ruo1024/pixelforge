#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/configure_editor_game_view.sh
./pixel/scripts/lint.sh
./pixel/scripts/run_tests.sh
./pixel/scripts/check_ui_scaling.sh
./pixel/scripts/check_export_templates.sh

if git diff --cached --name-only | grep -iE '\.(png|jpe?g)$' >/dev/null; then
  echo "Staged image files are not allowed for M3 UX-5 commits." >&2
  exit 1
fi

echo "verify_m3_ux5: ok"
