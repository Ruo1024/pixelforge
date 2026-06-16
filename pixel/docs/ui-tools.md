# PixelForge UI Tools (M2.1)

M2.1 adds a small pixel-selection tool layer for manual correction before matting,
slicing, and outlining. The tool layer lives entirely in `ui/`; it calls
`core/pixel/selection.gd` for pixel math and never edits images directly.

## Ownership

- `ui/tools/base_tool.gd`: shared tool contract, selection overlay helpers, and
  Shift/Alt boolean selection semantics.
- `ui/tools/magic_wand_tool.gd`: click-to-select using `PFSelection.magic_wand`.
- `ui/tools/rectangle_tool.gd`: drag rectangle preview, commit on mouse release.
- `ui/tools/lasso_tool.gd`: left-click polygon points, right-click close.
- `ui/tools/tool_manager.gd`: active tool, shared current selection, undo/redo
  wrapping, and keyboard shortcuts.
- `ui/shell/m2_1_ui_controller.gd`: shell wiring for File import, W/M/L buttons,
  M2 parameter dialogs, onboarding, and batch-card context menus.

## Input Flow

1. `PFInfiniteCanvas` keeps normal pan/zoom/select behavior as the default.
2. When a W/M/L tool is active and exactly one sprite is selected, the canvas
   converts mouse positions into image pixel coordinates and delegates to
   `PFToolManager`.
3. The active tool emits a `PFSelection`; `PFToolManager` records it through
   `UndoService.perform_action("Tool selection", ...)`.
4. `PFInfiniteCanvas._draw()` asks the active tool to draw the overlay in screen
   space, preserving nearest-neighbor sprite rendering.

Batch cards are deliberately not graph nodes in M2.1. `PFCanvasBatchCard` stores
only an `asset_id` queue and card-local thumbnail selection so the alpha can test
whole-batch menu processing before M3 introduces formal graph persistence.
