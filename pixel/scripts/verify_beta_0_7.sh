#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

readonly BASELINE="1b3f93481be5e8fc517344d2460abc6df2c6ad1c"
test_log="$(mktemp)"
trap 'rm -f "${test_log}"' EXIT

run_single_gut() {
  local test_path="$1"
  (
    cd pixel
    source scripts/_godot_path.sh
    local godot
    godot="$(find_godot)"
    prepare_godot_env
    import_godot_project "${godot}"
    "${godot}" --headless -s addons/gut/gut_cmdln.gd \
      -gconfig= -gtest="${test_path}" -gno_error_tracking -gexit
  )
}

echo "[1/10] lint / format"
./pixel/scripts/lint.sh

echo "[2/10] full GUT with local mock HTTP"
./pixel/scripts/run_tests.sh | tee "${test_log}"
if python3 - "${test_log}" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
raise SystemExit(0 if re.search(r"Risky/Pending\s+[1-9][0-9]*", text) else 1)
PY
then
  echo "Full GUT contains pending or risky tests." >&2
  exit 1
fi

echo "[3/10] i18n catalog"
./pixel/scripts/check_i18n_catalogs.sh

echo "[4/10] i18n source guard"
run_single_gut res://tests/unit/test_i18n_source_guard.gd

echo "[5/10] UI scaling"
./pixel/scripts/check_ui_scaling.sh

echo "[6/10] 18-case geometry"
run_single_gut res://tests/smoke/test_i18n_geometry_matrix_v2.gd

echo "[7/10] deterministic screenshots + manifest"
./pixel/scripts/capture_beta_0_7.sh

echo "[8/10] export template"
(
  source pixel/scripts/_godot_path.sh
  godot="$(find_godot)"
  template_version="$("${godot}" --version | cut -d. -f1-3).stable"
  template_path="${HOME}/Library/Application Support/Godot/export_templates/${template_version}/macos.zip"
  [[ -f "${template_path}" ]] || { echo "Missing official macOS export template: ${template_path}" >&2; exit 1; }
  echo "Official macOS export template found: ${template_path}"
)
./pixel/scripts/check_export_templates.sh

echo "[9/10] diff check"
git diff --check

echo "[10/10] complete raster guard"
raster_paths="$({
  git diff --cached --name-only
  git diff --name-only "${BASELINE}...HEAD"
  git diff --name-only
  git ls-files --others --exclude-standard
} | sort -u | rg -i '\.(png|jpg|jpeg)$' | rg -v '^pixel/addons/gut/' || true)"
if [[ -n "${raster_paths}" ]]; then
  echo "Protected or generated raster changes detected:" >&2
  echo "${raster_paths}" >&2
  exit 1
fi
echo "verify_beta_0_7: engineering gates passed"
