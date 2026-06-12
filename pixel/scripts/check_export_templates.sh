#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

GODOT="$(find_godot)"
prepare_godot_env
version="$("${GODOT}" --version | cut -d. -f1-3)"
template_root="${HOME}/Library/Application Support/Godot/export_templates/${version}.stable"

if [[ -d "${template_root}" ]]; then
  echo "Export templates found: ${template_root}"
else
  echo "Export templates not found for Godot ${version}. M0 local gate only verifies headless startup."
fi

"${GODOT}" --headless --quit
