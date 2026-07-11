#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m5.sh

rg -q 'test_palette_constraint_survives_one_thousand_random_operations' pixel/tests/unit/test_pixel_drawing.gd
rg -q 'test_32_layer_by_64_frame_matrix_has_explicit_limit_budget' pixel/tests/unit/test_edit_document.gd
rg -q 'test_eight_frame_editor_animation_is_immediately_available_to_board' pixel/tests/integration/test_editor_animation_board.gd
rg -q 'asset_edit_requested' pixel/ui/canvas/infinite_canvas.gd pixel/ui/shell/m2_1_ui_controller.gd
rg -q 'EDITOR_INPAINT_DISABLED' pixel/ui/editor/pixel_editor.gd pixel/ui/shell/strings.gd
rg -q 'PFCompositor' pixel/services/compositor.gd

if rg -n --glob '*.gd' '\b(TODO|FIXME|HACK)\b' pixel/core/editor pixel/ui/editor pixel/services/compositor.gd; then
	echo "M6 contains an unowned TODO/FIXME/HACK marker." >&2
	exit 1
fi

if git diff --cached --name-only | rg -i '\.(png|jpg|jpeg)$' | rg -v '^pixel/addons/gut/'; then
	echo "Protected or generated raster images must not be staged." >&2
	exit 1
fi

echo "verify_m6: ok"
