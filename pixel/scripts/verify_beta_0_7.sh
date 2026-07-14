#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

readonly BASELINE="26a6070"
readonly CONTROL_FIXTURES="${PF_CONTROL_REAL_FIXTURE_DIR:-/Users/ruo/Desktop/pixelforge/pixel/tests/fixtures/real}"
readonly LOCAL_FIXTURES="pixel/tests/fixtures/real"
readonly FIXTURE_SPECS=(
  "real_ai_01_character.png:0b0a83f933683dad5461934eb710745e77e0d35490ac4e36df5a8f42c7051fd0"
  "real_ai_02_robot.png:2fc1ae9af927d169984e8ec0b5df4bb00abaeea0d2898a460baf8d60610007b9"
  "real_ai_03_hair_detail.png:b37fe2ed13b8ba181c77239a04945b4c45df96dc3b28f53b50b0e48aab1b9d69"
)

fixtures_present=0
gdignore_backup=""
cleanup_fixtures() {
  if [[ "${fixtures_present}" == "1" ]]; then
    for spec in "${FIXTURE_SPECS[@]}"; do
      rm -f "${LOCAL_FIXTURES}/${spec%%:*}" "${LOCAL_FIXTURES}/${spec%%:*}.import"
    done
    find pixel/.godot/imported -maxdepth 1 -type f -name 'real_ai_*' -delete 2>/dev/null || true
    rm -f pixel/.godot/editor/filesystem_cache*
  fi
  if [[ -n "${gdignore_backup}" && -f "${gdignore_backup}" ]]; then
    mv "${gdignore_backup}" "${LOCAL_FIXTURES}/.gdignore"
    gdignore_backup=""
  fi
}
trap cleanup_fixtures EXIT

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

copy_fixtures() {
  mkdir -p "${LOCAL_FIXTURES}"
  if [[ -f "${LOCAL_FIXTURES}/.gdignore" ]]; then
    gdignore_backup="$(mktemp "${TMPDIR:-/tmp}/pixelforge-real-fixture-gdignore.XXXXXX")"
    mv "${LOCAL_FIXTURES}/.gdignore" "${gdignore_backup}"
  fi
  rm -f pixel/.godot/editor/filesystem_cache*
  fixtures_present=1
  for spec in "${FIXTURE_SPECS[@]}"; do
    local name="${spec%%:*}"
    local expected="${spec#*:}"
    local source="${CONTROL_FIXTURES}/${name}"
    local target="${LOCAL_FIXTURES}/${name}"
    [[ -f "${source}" ]] || { echo "Missing protected fixture: ${source}" >&2; exit 1; }
    [[ "$(shasum -a 256 "${source}" | awk '{print $1}')" == "${expected}" ]] || {
      echo "Protected fixture hash mismatch: ${name}" >&2
      exit 1
    }
    cp "${source}" "${target}"
    [[ "$(shasum -a 256 "${target}" | awk '{print $1}')" == "${expected}" ]] || {
      echo "Copied fixture hash mismatch: ${name}" >&2
      exit 1
    }
  done
}

echo "[1/10] lint / format"
./pixel/scripts/lint.sh

echo "[2/10] full GUT with local mock HTTP"
copy_fixtures
./pixel/scripts/run_tests.sh
cleanup_fixtures
fixtures_present=0
if find "${LOCAL_FIXTURES}" -maxdepth 1 -type f \( -name '*.png' -o -name '*.png.import' \) -print -quit | grep -q .; then
  echo "Protected fixtures or imports remained after tests." >&2
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

echo "[7/10] eight deterministic screenshots + manifest"
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

echo "[10/10] complete raster and protected-material guard"
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
if git status --short --ignored "${LOCAL_FIXTURES}" | rg '\.(png|jpg|jpeg)(\.import)?$'; then
  echo "Protected fixtures/imports remain in the execution worktree." >&2
  exit 1
fi

echo "verify_beta_0_7: engineering gates passed"
