#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

stage="${1:-beta-0.3}"
output_root="${2:-../scratch/beta-evidence/${stage}}"
GODOT="$(find_godot)"
workspace_root="$(cd .. && pwd)"
capture_home="$(mktemp -d "${workspace_root}/scratch/beta-capture-home.XXXXXX")"
trap 'rm -rf "${capture_home}"' EXIT
export GODOT_HOME="${capture_home}"
prepare_godot_env
import_godot_project "${GODOT}"
mkdir -p "${output_root}"

for locale in en zh_CN; do
  "${GODOT}" \
    --path . \
    --rendering-method gl_compatibility \
    res://scripts/capture_beta_workspace.tscn \
    -- "${output_root}/workspace-${locale}.png" "${locale}"
done

for screenshot in "${output_root}"/workspace-*.png; do
  test -s "${screenshot}"
done

echo "Beta screenshot evidence: ${output_root}"
