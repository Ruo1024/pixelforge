#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

readonly VERSION="0.5.0-beta.1"
readonly PRESET="macOS"
readonly OUTPUT="$(pwd)/build/PixelForge-${VERSION}-macOS.zip"
readonly CHECKSUM="${OUTPUT}.sha256"
readonly FORBIDDEN='(^|/)(test picture|tests/fixtures/real)(/|$)'
readonly SOURCE_GODOT_HOME="$(pwd)/.godot/home"

GODOT="$(find_godot)"
template_version="$("${GODOT}" --version | cut -d. -f1-3).stable"
template_root="${SOURCE_GODOT_HOME}/Library/Application Support/Godot/export_templates/${template_version}"
if [[ ! -f "${template_root}/macos.zip" ]]; then
  echo "Missing macOS export template: ${template_root}/macos.zip" >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-beta-0-5-build.XXXXXX")"
audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-beta-0-5-audit.XXXXXX")"
trap 'rm -rf "${work_dir}" "${audit_dir}"' EXIT
rsync -a \
  --exclude '.godot/' \
  --exclude 'build/' \
  --exclude 'test picture/' \
  --exclude 'tests/fixtures/real/' \
  ./ "${work_dir}/"

perl -0pi -e "s/config\/version=\"[^\"]+\"/config\/version=\"${VERSION}\"/" \
  "${work_dir}/project.godot"
perl -0pi -e "s/APP_VERSION := \"[^\"]+\"/APP_VERSION := \"${VERSION}\"/" \
  "${work_dir}/core/util/app_info.gd"
grep -Fq "config/version=\"${VERSION}\"" "${work_dir}/project.godot"
grep -Fq "APP_VERSION := \"${VERSION}\"" "${work_dir}/core/util/app_info.gd"

mkdir -p build
rm -f "${OUTPUT}" "${CHECKSUM}"
(
  cd "${work_dir}"
  GODOT_HOME="${SOURCE_GODOT_HOME}" prepare_godot_env
  "${GODOT}" --headless --export-release "${PRESET}" "${OUTPUT}"
)
test -s "${OUTPUT}"

unzip -q "${OUTPUT}" -d "${audit_dir}"
test -x "${audit_dir}/PixelForge.app/Contents/MacOS/PixelForge"
if unzip -Z1 "${OUTPUT}" | grep -Ei "${FORBIDDEN}"; then
  echo "Protected test image path found in candidate archive." >&2
  exit 1
fi
pck="${audit_dir}/PixelForge.app/Contents/Resources/PixelForge.pck"
test -f "${pck}"
if python3 scripts/audit_pck_paths.py "${pck}" | grep -Ei "${FORBIDDEN}"; then
  echo "Protected test image path found in candidate resource pack." >&2
  exit 1
fi

candidate_home="${audit_dir}/clean-home"
mkdir -p "${candidate_home}/AppData/Roaming" "${candidate_home}/AppData/Local"
startup_log="${audit_dir}/clean-startup.log"
HOME="${candidate_home}" \
  APPDATA="${candidate_home}/AppData/Roaming" \
  LOCALAPPDATA="${candidate_home}/AppData/Local" \
  "${audit_dir}/PixelForge.app/Contents/MacOS/PixelForge" \
  --headless --quit-after 2 >"${startup_log}" 2>&1
if grep -E 'SCRIPT ERROR|(^|[[:space:]])ERROR:' "${startup_log}"; then
  echo "Candidate failed clean-user startup." >&2
  exit 1
fi

shasum -a 256 "${OUTPUT}" >"${CHECKSUM}"
echo "macOS Beta 0.3–0.5 unified candidate: ${OUTPUT}"
echo "Protected test image audit: ok"
echo "Clean-user headless startup: ok"
cat "${CHECKSUM}"
