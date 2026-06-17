#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

if rg -n "_scaled_int|_scaled_vec2" ui --glob '*.gd'; then
  fail=1
fi

if rg -n "ui_scale" ui --glob '*.gd' | rg -v "# scale-exempt"; then
  fail=1
fi

if rg -n "custom_minimum_size\\s*=\\s*Vector2i?\\(\\s*[0-9]" ui --glob '*.gd'; then
  fail=1
fi

if rg -n "add_theme_font_size_override\\([^,]+,\\s*[0-9]" ui --glob '*.gd'; then
  fail=1
fi

if rg -n "item_layer\\.position\\s*=" ui/canvas/infinite_canvas.gd | rg -v "snap_position_to_physical_pixel"; then
  fail=1
fi

if [[ "${fail}" == "0" ]]; then
  echo "check_ui_scaling: ok"
else
  echo "banned UI scaling pattern found" >&2
  exit 1
fi
