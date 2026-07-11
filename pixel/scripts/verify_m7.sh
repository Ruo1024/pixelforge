#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

./pixel/scripts/verify_m6.sh
./pixel/scripts/audit_v1_security.sh

rg -q 'load_resource_pack' pixel/services/plugin_service.gd
rg -q 'comfyui.run_workflow' pixel/plugins/bridge_comfyui/comfyui_workflow_node.gd
rg -q '/system_stats' pixel/plugins/bridge_comfyui/comfyui_provider.gd
rg -q '/prompt' pixel/plugins/bridge_comfyui/comfyui_provider.gd
rg -q '/history/' pixel/plugins/bridge_comfyui/comfyui_provider.gd
rg -q '/interrupt' pixel/plugins/bridge_comfyui/comfyui_provider.gd
rg -q 'test_directory_plugin_unload_ghost_and_reload_restore' pixel/tests/integration/test_plugin_service.gd
rg -q 'test_mock_comfyui_queue_history_view_and_cancel_paths' pixel/tests/integration/test_comfyui_provider.gd

for document in plugin-dev.md user-manual.md faq.md licenses-and-models.md manual-test-v1.md; do
  test -s "pixel/docs/${document}"
done

pack_root="$(mktemp -d "${TMPDIR:-/tmp}/pixelforge-plugin-pack.XXXXXX")"
trap 'rm -rf "${pack_root}"' EXIT
./pixel/scripts/pack_plugin.sh \
  pixel/templates/plugin_template "${pack_root}/image_invert_example.pck"
test -s "${pack_root}/image_invert_example.pck"

if rg -n --glob '*.gd' '\b(TODO|FIXME|HACK)\b' \
  pixel/services/plugin_service.gd pixel/services/plugin_api.gd \
  pixel/plugins/bridge_comfyui pixel/ui/dialogs/plugin_manager_dialog.gd \
  pixel/ui/dialogs/comfyui_template_dialog.gd pixel/ui/dialogs/v1_onboarding_dialog.gd; then
  echo "M7 contains an unowned TODO/FIXME/HACK marker." >&2
  exit 1
fi

if git diff --cached --name-only | rg -i '\.(png|jpg|jpeg)$' | rg -v '^pixel/addons/gut/'; then
  echo "Protected or generated raster images must not be staged." >&2
  exit 1
fi

echo "verify_m7: ok"
