#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

GODOT="$(find_godot)"
prepare_godot_env
import_godot_project "${GODOT}"
"${GODOT}" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gno_error_tracking -gexit
