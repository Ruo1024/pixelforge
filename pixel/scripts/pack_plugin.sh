#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: scripts/pack_plugin.sh PLUGIN_DIRECTORY OUTPUT.pck" >&2
  exit 2
fi

source_path="$1"
output_path="$2"
if [[ "${source_path}" != /* ]]; then
  source_path="$(pwd)/${source_path}"
fi
if [[ "${output_path}" != /* ]]; then
  output_path="$(pwd)/${output_path}"
fi

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh
prepare_godot_env

"$(find_godot)" --headless --path . --script scripts/pack_plugin.gd \
  -- "${source_path}" "${output_path}"
