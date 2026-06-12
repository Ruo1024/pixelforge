#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

status=0
gdscript_paths=(core infra services ui tests)
local_gdtoolkit_bin="$(pwd)/.godot/gdtoolkit-venv/bin"

if [[ -d "${local_gdtoolkit_bin}" ]]; then
  PATH="${local_gdtoolkit_bin}:${PATH}"
fi

if ! command -v gdformat >/dev/null 2>&1; then
  echo "gdformat not found. Install gdtoolkit before running lint: python -m pip install gdtoolkit" >&2
  exit 127
fi

if ! command -v gdlint >/dev/null 2>&1; then
  echo "gdlint not found. Install gdtoolkit before running lint: python -m pip install gdtoolkit" >&2
  exit 127
fi

gdformat --check "${gdscript_paths[@]}"
gdlint "${gdscript_paths[@]}"

if rg --line-number --glob '*.gd' --glob '!addons/gut/**' --glob '!infra/logger.gd' '\bprint(_rich|_verbose)?\s*\(' .; then
  echo "Bare print calls are only allowed inside infra/logger.gd. Use Logger instead." >&2
  status=1
fi

exit "${status}"
