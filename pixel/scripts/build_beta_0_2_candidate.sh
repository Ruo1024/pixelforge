#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

readonly VERSION="0.2.0-beta.1"
readonly PRESET="macOS"
readonly OUTPUT="build/PixelForge-${VERSION}-macOS.zip"
readonly FORBIDDEN='(^|/)(test picture|tests/fixtures/real)(/|$)'

grep -Fq "config/version=\"${VERSION}\"" project.godot
grep -Fq "APP_VERSION := \"${VERSION}\"" core/util/app_info.gd

GODOT="$(find_godot)"
prepare_godot_env
template_version="$("${GODOT}" --version | cut -d. -f1-3).stable"
template_root="${HOME}/Library/Application Support/Godot/export_templates/${template_version}"
if [[ ! -f "${template_root}/macos.zip" ]]; then
  echo "Missing macOS export template: ${template_root}/macos.zip" >&2
  exit 1
fi

mkdir -p build
rm -f "${OUTPUT}"
"${GODOT}" --headless --export-release "${PRESET}" "${OUTPUT}"
test -s "${OUTPUT}"

audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-beta-0-2-audit.XXXXXX")"
trap 'rm -rf "${audit_dir}"' EXIT
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

echo "macOS Beta 0.2 candidate: $(pwd)/${OUTPUT}"
echo "Protected test image audit: ok"
echo "Clean-user headless startup: ok"
