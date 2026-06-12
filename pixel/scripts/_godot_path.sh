#!/usr/bin/env bash
set -euo pipefail

find_godot() {
  if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]]; then
    printf "%s\n" "${GODOT_BIN}"
    return 0
  fi

  if command -v godot >/dev/null 2>&1; then
    command -v godot
    return 0
  fi

  if command -v godot4 >/dev/null 2>&1; then
    command -v godot4
    return 0
  fi

  if [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    printf "%s\n" "/Applications/Godot.app/Contents/MacOS/Godot"
    return 0
  fi

  if [[ -x "/Applications/godot/Godot.app/Contents/MacOS/Godot" ]]; then
    printf "%s\n" "/Applications/godot/Godot.app/Contents/MacOS/Godot"
    return 0
  fi

  printf "Godot executable not found. Set GODOT_BIN=/path/to/Godot.\n" >&2
  return 1
}

prepare_godot_home() {
  local godot_home="${GODOT_HOME:-$(pwd)/.godot/home}"
  mkdir -p "${godot_home}/Library/Application Support/Godot/app_userdata/PixelForge/logs"
  mkdir -p "${godot_home}/.local/share/godot/app_userdata/PixelForge/logs"
  mkdir -p "${godot_home}/AppData/Roaming/Godot/app_userdata/PixelForge/logs"
  mkdir -p "${godot_home}/AppData/Local/Godot"
  printf "%s\n" "${godot_home}"
}

prepare_godot_env() {
  GODOT_HOME="$(prepare_godot_home)"
  export HOME="${GODOT_HOME}"
  export APPDATA="${GODOT_HOME}/AppData/Roaming"
  export LOCALAPPDATA="${GODOT_HOME}/AppData/Local"
  mkdir -p "${APPDATA}" "${LOCALAPPDATA}"
}

import_godot_project() {
  local godot_bin="$1"
  local project_file="project.godot"
  local backup_file=".godot/project.godot.before-import"
  mkdir -p ".godot"
  cp "${project_file}" "${backup_file}"
  "${godot_bin}" --headless --import --quit
  if ! cmp -s "${project_file}" "${backup_file}"; then
    cp "${backup_file}" "${project_file}"
  fi
}
