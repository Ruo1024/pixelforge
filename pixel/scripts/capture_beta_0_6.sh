#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

output_root="${1:-../scratch/beta-evidence/beta-0.6}"
GODOT="$(find_godot)"
workspace_root="$(cd .. && pwd)"
capture_home="$(mktemp -d "${workspace_root}/scratch/beta-0-6-capture-home.XXXXXX")"
metadata_root="$(mktemp -d "${workspace_root}/scratch/beta-0-6-metadata.XXXXXX")"
git_status_file="${metadata_root}/git-status.txt"
trap 'rm -rf "${capture_home}" "${metadata_root}"' EXIT
export GODOT_HOME="${capture_home}"
prepare_godot_env
import_godot_project "${GODOT}"

rm -rf "${output_root}"
mkdir -p "${output_root}"
started_unix="$(python3 -c 'import time; print(time.time())')"

scenarios=(
  "1080x560-en-100-closed.png|en|closed"
  "1080x560-zh-50-overlay.png|zh_CN|overlay"
  "1280x720-en-50-batch-12-13.png|en|batch_12_13"
  "1280x720-zh-100-inspector.png|zh_CN|inspector"
  "1440x900-en-50-batch-50-all.png|en|batch_50"
  "1440x900-zh-100-card-families.png|zh_CN|card_families"
  "1440x900-en-400-inspect.png|en|inspect"
)

for entry in "${scenarios[@]}"; do
  IFS='|' read -r filename locale scenario <<<"${entry}"
  "${GODOT}" \
    --path . \
    --rendering-method gl_compatibility \
    res://scripts/capture_beta_workspace.tscn \
    -- \
    "${output_root}/${filename}" \
    "${locale}" \
    "${scenario}" \
    "${metadata_root}/${scenario}.json"
done

git -C .. status --short >"${git_status_file}"
python3 scripts/beta_0_6_evidence.py assemble \
  --output "${output_root}" \
  --metadata "${metadata_root}" \
  --git-head "$(git -C .. rev-parse HEAD)" \
  --git-status-file "${git_status_file}"
python3 scripts/beta_0_6_evidence.py verify \
  --output "${output_root}" \
  --started-unix "${started_unix}"

echo "Beta 0.6 screenshot evidence verified: ${output_root}"
