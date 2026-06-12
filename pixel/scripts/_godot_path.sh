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
  printf "%s\n" "${godot_home}"
}
