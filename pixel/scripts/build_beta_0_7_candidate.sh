#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

readonly VERSION="0.7.0-beta.1"
readonly PRESET="macOS"
readonly CANDIDATE_DIR="/Users/ruo/Desktop/pixelforge/scratch/candidates/beta0-7"
readonly OUTPUT="${CANDIDATE_DIR}/PixelForge-${VERSION}-macOS.zip"
readonly DESKTOP_OUTPUT="/Users/ruo/Desktop/PixelForge-${VERSION}-macOS.zip"

[[ ! -e "${OUTPUT}" ]] || { echo "Candidate already exists; refusing to overwrite: ${OUTPUT}" >&2; exit 1; }
[[ ! -e "${DESKTOP_OUTPUT}" ]] || { echo "Desktop target already exists; refusing to overwrite: ${DESKTOP_OUTPUT}" >&2; exit 1; }
grep -Fq "APP_VERSION := \"${VERSION}\"" core/util/app_info.gd

GODOT="$(find_godot)"
template_version="$("${GODOT}" --version | cut -d. -f1-3).stable"
template_root="${HOME}/Library/Application Support/Godot/export_templates/${template_version}"
[[ -f "${template_root}/macos.zip" ]] || {
  echo "Missing official macOS export template: ${template_root}/macos.zip" >&2
  exit 1
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-beta-0-7-build.XXXXXX")"
audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-beta-0-7-audit.XXXXXX")"
export_home="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-beta-0-7-home.XXXXXX")"
trap 'rm -rf "${work_dir}" "${audit_dir}" "${export_home}"' EXIT

rsync -a \
  --exclude '.godot/' --exclude 'build/' --exclude 'test picture/' \
  --exclude 'tests/fixtures/real/' --exclude 'user/' --exclude 'scratch/' \
  ./ "${work_dir}/"
cp "${work_dir}/export_presets.cfg.example" "${work_dir}/export_presets.cfg"
# The project source keeps its single version truth in app_info.gd; this temporary export copy
# only disables signing because signing and notarization require separate owner authorization.
perl -0pi -e 's/codesign\/codesign=1/codesign\/codesign=0/g' "${work_dir}/export_presets.cfg"
grep -Fq 'codesign/codesign=0' "${work_dir}/export_presets.cfg"

export_template_dir="${export_home}/Library/Application Support/Godot/export_templates/${template_version}"
mkdir -p "${export_template_dir}" "${CANDIDATE_DIR}"
ln -s "${template_root}/macos.zip" "${export_template_dir}/macos.zip"

(
  cd "${work_dir}"
  GODOT_HOME="${export_home}" prepare_godot_env
  "${GODOT}" --headless --export-release "${PRESET}" "${OUTPUT}"
)
[[ -s "${OUTPUT}" ]]

unzip -q "${OUTPUT}" -d "${audit_dir}/unpacked"
app="${audit_dir}/unpacked/PixelForge.app"
binary="${app}/Contents/MacOS/PixelForge"
pck="${app}/Contents/Resources/PixelForge.pck"
[[ -x "${binary}" && -f "${pck}" ]]
python3 scripts/audit_pck_paths.py "${pck}" >"${audit_dir}/pck-paths.txt"
python3 scripts/audit_beta_0_7_candidate.py \
  --root "${audit_dir}/unpacked" --pck-paths "${audit_dir}/pck-paths.txt"

signature_info="$(codesign -dv --verbose=4 "${app}" 2>&1)"
if ! grep -Fq 'Authority=Developer ID Application: Prehensile Tales B.V. (6K46PWY5DM)' <<<"${signature_info}" \
  || ! grep -Fq 'TeamIdentifier=6K46PWY5DM' <<<"${signature_info}"; then
  echo "Candidate signature is not the unchanged official Godot template identity." >&2
  exit 1
fi

candidate_home="${audit_dir}/clean-home"
mkdir -p "${candidate_home}"
startup_log="${audit_dir}/clean-startup.log"
env -i HOME="${candidate_home}" TMPDIR="${TMPDIR:-/tmp}" PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  "${binary}" --headless --quit-after 2 >"${startup_log}" 2>&1
if rg 'SCRIPT ERROR|(^|[[:space:]])ERROR:' "${startup_log}"; then
  echo "Candidate failed clean-HOME headless startup." >&2
  exit 1
fi

readonly SHA256="$(shasum -a 256 "${OUTPUT}" | awk '{print $1}')"
readonly SIZE="$(stat -f %z "${OUTPUT}")"
[[ ! -e "${DESKTOP_OUTPUT}" ]] || { echo "Desktop target appeared during build; refusing to overwrite." >&2; exit 1; }
cp -n "${OUTPUT}" "${DESKTOP_OUTPUT}"
readonly DESKTOP_SHA256="$(shasum -a 256 "${DESKTOP_OUTPUT}" | awk '{print $1}')"
[[ "${DESKTOP_SHA256}" == "${SHA256}" ]] || { echo "Desktop copy hash mismatch." >&2; exit 1; }

echo "candidate=${OUTPUT}"
echo "desktop=${DESKTOP_OUTPUT}"
echo "sha256=${SHA256}"
echo "size=${SIZE}"
echo "signature=official_godot_template_vendor_only"
echo "project_signing=none"
echo "notarization=none"
echo "clean_home_startup=ok"
