#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

readonly OUTPUT_ROOT="${1:-../scratch/beta0-7-evidence}"
readonly GODOT="$(find_godot)"
readonly WORKSPACE_ROOT="$(cd .. && pwd)"
capture_home="$(mktemp -d "${WORKSPACE_ROOT}/scratch/beta0-7-capture-home.XXXXXX")"
metadata_root="$(mktemp -d "${WORKSPACE_ROOT}/scratch/beta0-7-metadata.XXXXXX")"
trap 'rm -rf "${capture_home}" "${metadata_root}"' EXIT
export GODOT_HOME="${capture_home}"
prepare_godot_env
import_godot_project "${GODOT}"

rm -rf "${OUTPUT_ROOT}"
mkdir -p "${OUTPUT_ROOT}"
started_unix="$(python3 -c 'import time; print(time.time())')"

scenarios=(
  "1280x720-en-100-example-reflow.png|en|example_reflow|1.0"
  "1440x900-zh-100-generation-ready.png|zh_CN|generation_ready|1.0"
  "1440x900-en-100-running-output-edge.png|en|running_output_edge|1.0"
  "1440x900-zh-100-output-12.png|zh_CN|output_12|1.0"
  "1440x900-en-100-output-13-50-scroll.png|en|output_13_50_scroll|1.0"
  "2560x1440-en-100-reference-12.png|en|reference_12|1.0"
  "1440x900-zh-100-detached-sprite.png|zh_CN|detached_sprite|1.0"
  "1440x900-en-100-cleanup-running.png|en|cleanup_running|1.0"
  "1080x560-zh-150-partial-dialog.png|zh_CN|partial_dialog|1.5"
)

for entry in "${scenarios[@]}"; do
  IFS='|' read -r filename locale scenario scale <<<"${entry}"
  "${GODOT}" --path . --rendering-method gl_compatibility \
    res://scripts/capture_beta_0_7.tscn -- \
    "${OUTPUT_ROOT}/${filename}" "${locale}" "${scenario}" "${scale}" \
    "${metadata_root}/${scenario}.json"
done

python3 scripts/beta_0_7_evidence.py assemble \
  --output "${OUTPUT_ROOT}" --metadata "${metadata_root}" \
  --git-head "$(git -C .. rev-parse HEAD)"
python3 scripts/beta_0_7_evidence.py verify \
  --output "${OUTPUT_ROOT}" --started-unix "${started_unix}"

echo "Beta 0.7 screenshot evidence verified: ${OUTPUT_ROOT}"
