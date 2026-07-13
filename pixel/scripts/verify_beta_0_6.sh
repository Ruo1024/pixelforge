#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/lint.sh
./pixel/scripts/run_tests.sh
./pixel/scripts/check_i18n_catalogs.sh
./pixel/scripts/check_ui_scaling.sh
./pixel/scripts/check_export_templates.sh
./pixel/scripts/capture_beta_0_6.sh
git diff --check

if git diff --cached --name-only | rg -i '\.(png|jpg|jpeg)$' | rg -v '^pixel/addons/gut/'; then
  echo "Protected or generated raster images must not be staged." >&2
  exit 1
fi

echo "verify_beta_0_6: engineering gates passed"
