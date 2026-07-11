#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

GODOT="$(find_godot)"
prepare_godot_env
import_godot_project "${GODOT}"
"${GODOT}" --headless --script res://scripts/check_i18n_catalogs.gd
echo "check_i18n_catalogs: ok"
