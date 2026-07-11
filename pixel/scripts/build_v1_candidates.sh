#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/_godot_path.sh

readonly VERSION="1.0.0-rc.1"
readonly FORBIDDEN='(^|/)(test picture|tests/fixtures/real)(/|$)'
readonly REQUIRE_ALL="${1:-}"

if [[ -n "${REQUIRE_ALL}" && "${REQUIRE_ALL}" != "--all" ]]; then
  echo "usage: scripts/build_v1_candidates.sh [--all]" >&2
  exit 2
fi

grep -Fq "config/version=\"${VERSION}\"" project.godot
grep -Fq "APP_VERSION := \"${VERSION}\"" core/util/app_info.gd

GODOT="$(find_godot)"
prepare_godot_env
template_version="$("${GODOT}" --version | cut -d. -f1-3).stable"
template_root="${HOME}/Library/Application Support/Godot/export_templates/${template_version}"
cp export_presets.cfg.example export_presets.cfg
mkdir -p build

presets=(Linux Windows macOS)
templates=(linux_release.x86_64 windows_release_x86_64.exe macos.zip)
outputs=(
  "build/PixelForge-${VERSION}-linux.x86_64"
  "build/PixelForge-${VERSION}-windows.exe"
  "build/PixelForge-${VERSION}-macOS.zip"
)

built=0
missing=()
for index in "${!presets[@]}"; do
  preset="${presets[$index]}"
  template="${template_root}/${templates[$index]}"
  output="${outputs[$index]}"
  if [[ ! -f "${template}" ]]; then
    missing+=("${preset}:${template}")
    continue
  fi
  rm -f "${output}" "${output%.*}.pck"
  "${GODOT}" --headless --export-release "${preset}" "${output}"
  test -s "${output}"
  built=$((built + 1))

  if [[ "${preset}" == "macOS" ]]; then
    audit_dir="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-v1-audit.XXXXXX")"
    unzip -q "${output}" -d "${audit_dir}"
    pck="${audit_dir}/PixelForge.app/Contents/Resources/PixelForge.pck"
    test -f "${pck}"
    if unzip -Z1 "${output}" | grep -Ei "${FORBIDDEN}"; then
      echo "Protected image path found in ${output}." >&2
      exit 1
    fi
    candidate_home="${audit_dir}/clean-home"
    mkdir -p "${candidate_home}/AppData/Roaming" "${candidate_home}/AppData/Local"
    startup_log="${audit_dir}/clean-startup.log"
    HOME="${candidate_home}" APPDATA="${candidate_home}/AppData/Roaming" \
      LOCALAPPDATA="${candidate_home}/AppData/Local" \
      "${audit_dir}/PixelForge.app/Contents/MacOS/PixelForge" \
      --headless --quit-after 2 >"${startup_log}" 2>&1
    if rg -n 'SCRIPT ERROR|(^|[[:space:]])ERROR:' "${startup_log}"; then
      echo "macOS candidate failed clean-user startup." >&2
      exit 1
    fi
    if python3 scripts/audit_pck_paths.py "${pck}" | grep -Ei "${FORBIDDEN}"; then
      echo "Protected image path found in ${preset} resource pack." >&2
      exit 1
    fi
    rm -rf "${audit_dir}"
  else
    pck="${output%.*}.pck"
    test -f "${pck}"
    if python3 scripts/audit_pck_paths.py "${pck}" | grep -Ei "${FORBIDDEN}"; then
      echo "Protected image path found in ${preset} resource pack." >&2
      exit 1
    fi
  fi
  shasum -a 256 "${output}"
done

if [[ ${built} -eq 0 ]]; then
  echo "No matching Godot ${template_version} export templates are installed." >&2
  exit 3
fi
if [[ ${#missing[@]} -gt 0 ]]; then
  printf 'Skipped missing template: %s\n' "${missing[@]}"
  if [[ "${REQUIRE_ALL}" == "--all" ]]; then
    exit 4
  fi
fi

echo "v1 engineering candidates built: ${built}"
