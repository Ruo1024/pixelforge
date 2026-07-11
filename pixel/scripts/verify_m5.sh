#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m4_5.sh

rg -Fq 'boards/{board_id}.json' pixelforge-plan/02-contracts/PROJECT-FORMAT.md
rg -Fq 'anim/{id}.anim.json' pixelforge-plan/02-contracts/PROJECT-FORMAT.md
rg -q 'test_all_256_masks_normalize_to_exactly_47_valid_roles' pixel/tests/unit/test_terrain_blob.gd
rg -q 'test_ten_thousand_tile_board_composes_under_export_budget' pixel/tests/integration/test_board_exporter.gd
rg -q 'BOARD_TOOL_FILL' pixel/ui/shell/strings.gd pixel/ui/board/board_editor.gd
rg -q 'MENU_OPEN_BOARD' pixel/ui/shell/m2_1_ui_controller.gd pixel/ui/shell/strings.gd

if git diff --cached --name-only | rg -i '\.(png|jpg|jpeg)$' | rg -v '^pixel/addons/gut/'; then
	echo "Protected or generated raster images must not be staged." >&2
	exit 1
fi

echo "verify_m5: ok"
