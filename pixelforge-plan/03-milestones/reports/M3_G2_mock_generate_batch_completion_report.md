# M3 G-2 Mock Generate 落 Batch 完成报告

> 日期：2026-06-17  
> 分支：`codex/m3-g2-mock-batch`  
> 范围：M3 `G-2 Mock generate 落 batch` 的最小可测基础卡。  
> 初始完整代码 diff：`pixelforge-plan/03-milestones/reports/M3_G2_mock_generate_batch_full_code.diff`  
> 后续追加开发的 diff 直接内联在本文档末尾，不再新建报告名。

## 本轮实现

- 新增三类内置节点，并纳入 `PFNodeRegistry`：
  - `object_list`：多行文本输入，输出 `text_list`。
  - `size_spec`：输出 `{width, height, per_subject}` 规格。
  - `ai_generate`：M3 阶段仅支持 `provider_id=mock`，按 `seed` 和 subject 生成确定性占位 `Image` 列表。
- 新增 `PFGraphMockRunner`：
  - 只服务 M3 G-2 的最小链路，不是完整 executor。
  - 按拓扑序执行当前已注册的本地节点。
  - 将 `ai_generate.images` 传入 `batch.in` 后注册进 `AssetLibrary`。
  - 写回 batch 节点 `params.asset_ids`，生成 metadata/provenance：`origin=generated`、`provider=mock`、`graph_id=graph_main`、递增 seed。
- 新增测试：
  - mock 节点单测：object list 清洗、size spec 输出、mock 生成确定性、非 mock provider 拒绝。
  - mock runner 集成测试：5 个对象 × batch_size 2 → 10 张素材，写回 batch 并随项目保存/打开恢复。
- 新增 `pixel/scripts/verify_m3_g2.sh`，作为本卡出口门控。
- 追加开发：新增 File 菜单 `Generate Mock Batch`，可手动生成 10 张 mock sprite 并在当前画布显示为批次卡，同时把正式 graph 写入项目数据。

## 修改文件

- `pixel/core/graph/node_registry.gd`
- `pixel/core/graph/nodes/object_list_node.gd`
- `pixel/core/graph/nodes/size_spec_node.gd`
- `pixel/core/graph/nodes/ai_generate_node.gd`
- `pixel/services/graph_mock_runner.gd`
- `pixel/tests/unit/test_graph_mock_generate.gd`
- `pixel/tests/integration/test_graph_mock_runner.gd`
- `pixel/tests/unit/test_graph_model.gd`
- `pixel/tests/smoke/test_main_window_ui.gd`
- `pixel/ui/shell/strings.gd`
- `pixel/scripts/verify_m3_g2.sh`
- `pixel/CHANGELOG.md`
- 对应 Godot `.gd.uid` 文件

## 验证

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：129/129 passed。
- `./pixel/scripts/verify_m3_g2.sh`：通过，输出 `verify_m3_g2: ok`。
- staged 图片红线：`git diff --cached --name-only | grep -iE '\.png$|\.jpe?g$'` 无输出。

已知现象：GUT 仍报告既有 orphan/leaked resource 警告；run summary 为 all tests passed。本轮没有新增图片资源。

## DoD 核查

| 项 | 状态 | 证据/路径 |
|---|---|---|
| 代码规范 | 通过 | `./pixel/scripts/lint.sh` |
| 自动测试 | 通过 | `./pixel/scripts/run_tests.sh`，129/129 |
| 手动测试 | 待人工验收 | File > Generate Mock Batch；步骤见本轮交付说明 |
| 契约同步 | 不适用 | 未修改 `02-contracts/`，按现有 G-2 降级范围实现 |
| TODO | 通过 | 未新增 TODO/FIXME/HACK |
| 性能预算 | 不适用 | 本轮 mock 图生成规模小，不含 executor 性能预算 |
| 跨平台 | 延期登记 | 本轮仅本机 headless；UI/UX 卡再做实机验收 |
| 出口门控 | 通过 | `./pixel/scripts/verify_m3_g2.sh` |

## 边界与下一步

本轮只跑最小 mock 链，不是完整 executor：没有异步任务包装、取消、缓存、批量 map 泛化、失败节点 UI、端口连线 UI 或用户可鼠标搭链体验。

下一张基础卡建议进入 `G-4 最小节点链验收` 的画布端入口，或先做 `UX-1/UX-7` 的导航/命中仲裁地基，让节点链有真实操作载体。

## 追加开发：手动验证入口

追加目标：G-2 基础功能不能只停留在 headless 测试，必须能被人工直接操作验证。本轮在现有 M2.1 File 菜单中新增 `Generate Mock Batch`，复用同一条 `PFGraphMockRunner` 路径，把 `object_list -> size_spec -> ai_generate(mock) -> batch` 的输出注册为素材并创建可见批次卡。

追加验证：

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：129/129 passed。
- `./pixel/scripts/verify_m3_g2.sh`：通过，输出 `verify_m3_g2: ok`。

追加 diff：

```diff
diff --git a/pixel/tests/smoke/test_main_window_ui.gd b/pixel/tests/smoke/test_main_window_ui.gd
index 5322a4e..60769a2 100644
--- a/pixel/tests/smoke/test_main_window_ui.gd
+++ b/pixel/tests/smoke/test_main_window_ui.gd
@@ -217,3 +217,23 @@ func test_selection_tool_buttons_are_hidden_until_selection_actions_are_wired()
 			assert_ne(child.text, "W")
 			assert_ne(child.text, "M")
 			assert_ne(child.text, "L")
+
+
+func test_mock_generate_menu_action_creates_visible_batch_and_graph() -> void:
+	ProjectService.new_project("Mock UI")
+	var main: Control = MainScript.new()
+	main.size = Vector2(1280, 800)
+	add_child_autofree(main)
+	await wait_process_frames(2)
+
+	var controller: Node = main.get_node("M21UiController")
+	var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
+	controller.generate_mock_batch()
+	await wait_process_frames(2)
+
+	assert_eq(canvas.get_item_count(), 1)
+	assert_eq(ProjectService.current_project.graphs.size(), 1)
+	var graph_data: Dictionary = ProjectService.current_project.graphs.values()[0]
+	var batch_node: Dictionary = graph_data["nodes"][3]
+	assert_eq(batch_node["type"], "batch")
+	assert_eq(batch_node["params"]["asset_ids"].size(), 10)
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index 8aaa0f0..1b87de2 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -18,12 +18,24 @@ const OutlineDialogScript := preload("res://ui/dialogs/outline_dialog.gd")
 const OnboardingScript := preload("res://ui/dialogs/onboarding.gd")
 const DialogScalePolicy := preload("res://ui/shell/dialog_scale_policy.gd")
 const Pipeline := preload("res://core/pixel/pipeline.gd")
+const GraphScript := preload("res://core/graph/pf_graph.gd")
+const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
+const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
+const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
+const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
+const GraphMockRunnerScript := preload("res://services/graph_mock_runner.gd")
+const IdUtil := preload("res://core/util/id_util.gd")
 const Log := preload("res://core/util/log_util.gd")
 
 const TOOLBAR_BUTTON_HEIGHT := 34
 const TOOLBAR_FONT_SIZE := 14
 const FILE_MENU_BUTTON_WIDTH := 84
 const TOOL_BUTTON_SIZE := 84
+const FILE_MENU_IMPORT_IMAGES := 0
+const FILE_MENU_GENERATE_MOCK_BATCH := 1
+const FILE_MENU_NEW := 2
+const FILE_MENU_OPEN := 3
+const FILE_MENU_SAVE := 4
 const BATCH_MENU_CLEANUP := 0
 const BATCH_MENU_MATTE := 1
 const BATCH_MENU_OUTLINE := 2
@@ -78,11 +90,12 @@ func add_file_menu(parent: Control) -> void:
 	file_menu_button.focus_mode = Control.FOCUS_NONE
 	file_menu_button.add_theme_font_size_override("font_size", TOOLBAR_FONT_SIZE)
 	var popup := file_menu_button.get_popup()
-	popup.add_item(Strings.MENU_IMPORT_IMAGES, 0)
+	popup.add_item(Strings.MENU_IMPORT_IMAGES, FILE_MENU_IMPORT_IMAGES)
+	popup.add_item(Strings.MENU_GENERATE_MOCK_BATCH, FILE_MENU_GENERATE_MOCK_BATCH)
 	popup.add_separator()
-	popup.add_item(Strings.ACTION_NEW, 1)
-	popup.add_item(Strings.ACTION_OPEN, 2)
-	popup.add_item(Strings.ACTION_SAVE, 3)
+	popup.add_item(Strings.ACTION_NEW, FILE_MENU_NEW)
+	popup.add_item(Strings.ACTION_OPEN, FILE_MENU_OPEN)
+	popup.add_item(Strings.ACTION_SAVE, FILE_MENU_SAVE)
 	popup.id_pressed.connect(_on_file_menu_pressed)
 	parent.add_child(file_menu_button)
 
@@ -184,6 +197,26 @@ func batch_selected_sprites() -> void:
 		_focus_canvas_on_card(card)
 
 
+func generate_mock_batch() -> void:
+	var graph := _make_mock_generate_graph()
+	var runner := GraphMockRunnerScript.new()
+	var result: Dictionary = runner.run_to_batch(graph, AssetLibrary, "batch_1")
+	if not bool(result.get("ok", false)):
+		var error: Dictionary = result.get("error", {})
+		Log.warn("Mock graph generation failed", error)
+		_status_label.text = Strings.STATUS_MOCK_GENERATE_FAILED
+		return
+
+	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
+	var asset_ids: Array = result["asset_ids"]
+	var card: Node = _canvas._add_batch_card(
+		asset_ids, _canvas.get_mouse_world_position(), Strings.MOCK_BATCH_LABEL, "", true
+	)
+	if card != null:
+		_focus_canvas_on_card(card)
+	_status_label.text = Strings.STATUS_MOCK_GENERATE_DONE % asset_ids.size()
+
+
 func show_onboarding_if_needed() -> void:
 	if DisplayServer.get_name() == "headless":
 		return
@@ -241,13 +274,15 @@ func _init_tools() -> void:
 
 func _on_file_menu_pressed(id: int) -> void:
 	match id:
-		0:
+		FILE_MENU_IMPORT_IMAGES:
 			_import_dialog.popup_centered_ratio(0.7)
-		1:
+		FILE_MENU_GENERATE_MOCK_BATCH:
+			generate_mock_batch()
+		FILE_MENU_NEW:
 			_new_project_callback.call()
-		2:
+		FILE_MENU_OPEN:
 			_open_project_callback.call()
-		3:
+		FILE_MENU_SAVE:
 			_save_project_callback.call()
 
 
@@ -393,6 +428,37 @@ func _project_style_preset() -> Dictionary:
 	return style_data if style_data is Dictionary else {}
 
 
+func _make_mock_generate_graph() -> PFGraph:
+	var graph := GraphScript.new()
+	graph.id = "graph_mock_%s" % IdUtil.uuid_v4().left(8)
+	graph.name = "Mock Generate Batch"
+	graph.add_node(
+		ObjectListNodeScript.new(),
+		"objects",
+		{"items": "barrel\nfence\nscarecrow\ncrate\nwell"},
+		Vector2(0, 0)
+	)
+	graph.add_node(
+		SizeSpecNodeScript.new(),
+		"size",
+		{"width": 32, "height": 32, "per_subject": 1},
+		Vector2(220, 0)
+	)
+	graph.add_node(
+		AiGenerateNodeScript.new(),
+		"generate",
+		{"provider_id": "mock", "batch_size": 2, "seed": 1000},
+		Vector2(440, 0)
+	)
+	graph.add_node(
+		BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(660, 0)
+	)
+	graph.add_edge("objects", "items", "generate", "items")
+	graph.add_edge("size", "spec", "generate", "spec")
+	graph.add_edge("generate", "images", "batch_1", "in")
+	return graph
+
+
 func _show_onboarding_dialog() -> void:
 	var dialog: AcceptDialog = OnboardingScript.show_first_run_tips(self)
 	if dialog == null:
diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index b7bff2a..25d32a0 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -15,6 +15,7 @@ const ACTION_OUTLINE := "Outline"
 const ACTION_EXPORT_PNG := "Export PNG"
 const MENU_FILE := "File"
 const MENU_IMPORT_IMAGES := "Import Images..."
+const MENU_GENERATE_MOCK_BATCH := "Generate Mock Batch"
 const STATUS_READY := "Ready"
 const STATUS_SAVED := "Saved"
 const STATUS_DIRTY := "Unsaved changes"
@@ -41,6 +42,8 @@ const ZOOM_CONTROL_TOOLTIP := "Canvas zoom"
 const STATUS_BATCH_NEEDS_SELECTION := "Select two or more sprites to make a batch"
 const STATUS_BATCH_SPLIT := "Batch subset created"
 const STATUS_BATCH_SPLIT_EMPTY := "Select thumbnails inside a batch before splitting"
+const STATUS_MOCK_GENERATE_DONE := "Mock batch generated: %d sprites"
+const STATUS_MOCK_GENERATE_FAILED := "Mock batch generation failed"
 const CLEANUP_TITLE := "Pixel Cleanup"
 const CLEANUP_SELECTED_FORMAT := "%d selected"
 const CLEANUP_PRESET_PRIOR_FORMAT := "Preset prior: %dpx"
@@ -118,6 +121,7 @@ const OUTLINE_CORNER_CROSS := "Cross"
 const OUTLINE_CORNER_SQUARE := "Square"
 const OUTLINE_COLORED := "Use colored outline"
 const BATCH_DEFAULT_LABEL := "Batch"
+const MOCK_BATCH_LABEL := "Mock Batch"
const BATCH_ACTION_CLEANUP := "Clean Batch"
const BATCH_ACTION_MATTE := "Matte Batch"
const BATCH_ACTION_OUTLINE := "Outline Batch"
```

## 追加开发：G-3 批次菜单与 PixelOperations

追加目标：让批次菜单的 Clean / Matte / Outline 不再把算法和素材登记逻辑散落在 UI controller 内，而是通过 `PFPixelOperations` 这一条服务层入口执行。该入口后续可直接被 process 节点复用，避免“菜单可用”和“节点可复现”分叉。

本轮也把 `Generate Mock Batch` 创建的批次卡升级为 graph batch 节点的画布渲染壳：画布保存为 `type=node` + `graph_id/node_id` 引用，`asset_ids` 队列继续以 graph batch 节点 params 为事实来源。批次菜单替换整批素材后，会同步写回对应 graph batch 节点，保存重开时不会出现画布批次和 graph 逻辑不一致。

### G-3 实现

- 新增 `pixel/services/pixel_operations.gd`：
  - `apply_image()`：统一执行 `pixel_cleanup` / `matting` / `outline`。
  - `apply_to_assets()`：按 asset 队列批处理，支持取消检查与进度回调。
  - `register_result_asset()` / `make_provenance()`：统一生成派生素材 metadata/provenance。
  - `json_safe()`：把 `Color`、`Vector2`、`Rect2i` 等结果转为可 JSON 持久化数据；matting report 不再把 `Image` 对象塞进 metadata。
- 重接 `PFM2ActionController`：
  - 单图 Matte / Outline 复用 `PFPixelOperations`。
  - 批次 Clean / Matte / Outline 复用 `PFPixelOperations.apply_to_assets()`。
  - 素材派生登记统一走 `register_result_asset()`。
- 扩展 `PFCanvasBatchCard` 与 `PFInfiniteCanvas`：
  - 兼容旧 `batch_card`。
  - 支持正式 graph batch 节点引用渲染。
  - graph batch 卡导出为 `canvas.items[].type = "node"`，不再把 `asset_ids` 重复写进 canvas。
  - `_replace_batch_asset_ids()` 会维护 AssetLibrary 引用计数，并同步写回 graph batch 节点 params。
- `Generate Mock Batch` 现在创建 graph 绑定批次卡。
- 新增 `pixel/scripts/verify_m3_g3.sh` 作为本卡出口门控。

### G-3 修改文件

- `pixel/services/pixel_operations.gd`
- `pixel/services/pixel_operations.gd.uid`
- `pixel/ui/shell/m2_action_controller.gd`
- `pixel/ui/shell/m2_1_ui_controller.gd`
- `pixel/ui/canvas/canvas_batch_card.gd`
- `pixel/ui/canvas/infinite_canvas.gd`
- `pixel/tests/unit/test_pixel_operations.gd`
- `pixel/tests/unit/test_pixel_operations.gd.uid`
- `pixel/tests/unit/test_canvas_batch_card.gd`
- `pixel/tests/smoke/test_main_window_ui.gd`
- `pixel/scripts/verify_m3_g3.sh`
- `pixel/CHANGELOG.md`

### G-3 验证

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：132/132 passed。
- `./pixel/scripts/verify_m3_g3.sh`：通过，输出 `verify_m3_g3: ok`。
- 既有 GUT orphan/resource warning 仍存在；run summary 为 all tests passed。

### G-3 人工测试步骤

1. 打开 Godot 项目：`/Users/ruo/Desktop/pixelforge/pixel/project.godot`。
2. 运行主场景。
3. 点击 `File > Generate Mock Batch`，画布应出现 `Mock Batch` 批次卡，状态栏显示 `Mock batch generated: 10 sprites`。
4. 右键该批次卡，选择 `Outline Batch`，等待状态栏显示 `Outline complete`；批次卡内缩略图应整体变为描边后的新版本。
5. 再右键选择 `Clean Batch` 或 `Matte Batch`，确认批次仍可整体替换，并可继续右键打开菜单。
6. 保存为 `.pxproj` 后重新打开，批次卡仍存在；它的画布项应来自 graph batch 节点引用，素材队列随最近一次整批处理后的结果恢复。

G-3 追加 diff：

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index 4591b44..2769c04 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -24,3 +24,4 @@
 - M2.4 编辑器嵌入式调试修复: 新增本地 Game View 配置脚本，默认禁用 Godot Game embedding；若重新启用 Game bar，则将 Embedded Window Sizing 固定为 `Stretch to Fit`，避免默认 `Fixed Size` 造成居中盲区。
 - M3 G-1: 新增节点图最小领域模型、内置 batch 节点注册、端口连接矩阵/环检测，以及 `.pxproj` graphs 往返保存骨架。
 - M3 G-2: 新增 object_list / size_spec / ai_generate(mock) 节点和最小 mock runner，可将确定性生成图物化进正式 batch 节点。
+- M3 G-3: 新增 PixelOperations 共用服务，批次菜单 Clean/Matte/Outline 复用同一 core 操作，并让 Mock 批次卡以 graph batch 节点引用保存和同步资产队列。
diff --git a/pixel/scripts/verify_m3_g3.sh b/pixel/scripts/verify_m3_g3.sh
new file mode 100755
index 0000000..ebc33d9
--- /dev/null
+++ b/pixel/scripts/verify_m3_g3.sh
@@ -0,0 +1,19 @@
+#!/usr/bin/env bash
+set -euo pipefail
+
+cd "$(dirname "$0")/.."
+
+./scripts/configure_editor_game_view.sh
+./scripts/lint.sh
+./scripts/run_tests.sh
+./scripts/check_ui_scaling.sh
+./scripts/check_export_templates.sh
+
+if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
+  if git diff --cached --name-only | grep -iE '\.png$|\.jpe?g$' >/dev/null; then
+    echo "Staged image files are not allowed for M3 G-3 commits." >&2
+    exit 1
+  fi
+fi
+
+echo "verify_m3_g3: ok"
diff --git a/pixel/services/pixel_operations.gd b/pixel/services/pixel_operations.gd
new file mode 100644
index 0000000..b9c356c
--- /dev/null
+++ b/pixel/services/pixel_operations.gd
@@ -0,0 +1,210 @@
+class_name PFPixelOperations
+extends RefCounted
+
+## M3 批次菜单与未来 process 节点共用的像素操作入口。
+## contract: 03-milestones/M3-开发规划.md G-3；本层只编排 core 算法和素材派生元数据，不依赖 UI。
+
+const IdUtil := preload("res://core/util/id_util.gd")
+const Matting := preload("res://core/pixel/matting.gd")
+const Outliner := preload("res://core/pixel/outliner.gd")
+const Pipeline := preload("res://core/pixel/pipeline.gd")
+
+const OP_CLEANUP := "pixel_cleanup"
+const OP_MATTING := "matting"
+const OP_OUTLINE := "outline"
+
+
+static func apply_image(operation: String, source: Image, params: Dictionary = {}) -> Dictionary:
+	match operation:
+		OP_CLEANUP:
+			return _apply_cleanup(source, params)
+		OP_MATTING:
+			return _apply_matting(source, params)
+		OP_OUTLINE:
+			return _apply_outline(source, params)
+		_:
+			return {"ok": false, "error": "unsupported_operation", "operation": operation}
+
+
+static func apply_to_assets(
+	asset_ids: Array,
+	asset_library: Node,
+	operation: String,
+	params: Dictionary = {},
+	cancel_check: Callable = Callable(),
+	progress: Callable = Callable()
+) -> Dictionary:
+	var ids := _string_array(asset_ids)
+	var results := []
+	for index in range(ids.size()):
+		if cancel_check.is_valid() and bool(cancel_check.call()):
+			return {"canceled": true, "items": results}
+
+		var asset_id := String(ids[index])
+		var image: Image = asset_library.get_image(asset_id)
+		if image == null:
+			continue
+
+		var item_result := apply_image(operation, image, params)
+		if bool(item_result.get("ok", false)):
+			item_result["parent_asset"] = asset_id
+			results.append(item_result)
+
+		if progress.is_valid():
+			progress.call(float(index + 1) / float(maxi(1, ids.size())), operation)
+	return {"canceled": false, "items": results}
+
+
+static func register_result_asset(
+	asset_library: Node, parent_asset_id: String, item_result: Dictionary
+) -> String:
+	var parent_id := String(item_result.get("parent_asset", parent_asset_id))
+	var suffix := String(item_result.get("name_suffix", item_result.get("suffix", "operation")))
+	return (
+		asset_library
+		. register_image(
+			item_result["image"],
+			"%s_%s" % [parent_id.left(8), suffix],
+			{
+				"origin": String(item_result.get("origin", "edited")),
+				"tags": item_result.get("tags", []),
+				"provenance": make_provenance(parent_id, item_result),
+			}
+		)
+	)
+
+
+static func make_provenance(parent_asset_id: String, item_result: Dictionary) -> Dictionary:
+	var provenance_key := String(item_result.get("provenance_key", "operation"))
+	var operation_report: Variant = json_safe(item_result.get("report", {}))
+	if operation_report is Dictionary:
+		var report_dict: Dictionary = operation_report
+		if not report_dict.has("source_asset"):
+			report_dict["source_asset"] = parent_asset_id
+		operation_report = report_dict
+
+	var provenance := {
+		"provider": null,
+		"model": null,
+		"prompt": "",
+		"seed": null,
+		"parent_asset": parent_asset_id,
+		"graph_id": null,
+		"created_at": IdUtil.utc_now_iso(),
+	}
+	provenance[provenance_key] = operation_report
+	return provenance
+
+
+static func normalize_matte_params(params: Dictionary) -> Dictionary:
+	if params.is_empty():
+		return {"mode": Matting.MODE_FLOOD, "tolerance": 12.0, "feather": 0}
+	return {
+		"mode": String(params.get("mode", Matting.MODE_FLOOD)),
+		"tolerance": float(params.get("tolerance", 12.0)),
+		"feather": int(params.get("feather", 0)),
+	}
+
+
+static func normalize_outline_params(params: Dictionary) -> Dictionary:
+	if params.is_empty():
+		return {"type": Outliner.TYPE_OUTER, "color": Color.BLACK, "corner": Outliner.CORNER_CROSS}
+	return {
+		"type": String(params.get("type", Outliner.TYPE_OUTER)),
+		"color": params.get("color", Color.BLACK),
+		"corner": String(params.get("corner", Outliner.CORNER_CROSS)),
+		"colored": bool(params.get("colored", false)),
+	}
+
+
+static func json_safe(value: Variant) -> Variant:
+	match typeof(value):
+		TYPE_DICTIONARY:
+			var output := {}
+			for key in Dictionary(value).keys():
+				output[String(key)] = json_safe(Dictionary(value)[key])
+			return output
+		TYPE_ARRAY:
+			var output := []
+			for item in Array(value):
+				output.append(json_safe(item))
+			return output
+		TYPE_VECTOR2:
+			var vector := Vector2(value)
+			return [vector.x, vector.y]
+		TYPE_VECTOR2I:
+			var vector_i := Vector2i(value)
+			return [vector_i.x, vector_i.y]
+		TYPE_RECT2I:
+			var rect := Rect2i(value)
+			return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
+		TYPE_COLOR:
+			return Color(value).to_html(true)
+		_:
+			return value
+
+
+static func _apply_cleanup(source: Image, params: Dictionary) -> Dictionary:
+	var normalized := Pipeline.normalize_params(params)
+	var cleanup_result := Pipeline.apply(source, normalized)
+	return {
+		"ok": true,
+		"operation": OP_CLEANUP,
+		"image": cleanup_result["image"],
+		"suffix": "clean",
+		"name_suffix": "clean",
+		"origin": "edited",
+		"tags": ["cleanup"],
+		"provenance_key": "cleanup",
+		"report":
+		{
+			"params": json_safe(normalized),
+			"report": json_safe(cleanup_result.get("report", {})),
+		},
+	}
+
+
+static func _apply_matting(source: Image, params: Dictionary) -> Dictionary:
+	var normalized := normalize_matte_params(params)
+	var matting_result: Dictionary = Matting.matte(source, normalized)
+	# Provenance must stay JSON-safe; the generated Image is stored as an asset, not in metadata.
+	var report := matting_result.duplicate(true)
+	report.erase("image")
+	report["params"] = json_safe(normalized)
+	return {
+		"ok": true,
+		"operation": OP_MATTING,
+		"image": matting_result["image"],
+		"suffix": "matte",
+		"name_suffix": "matte",
+		"origin": "edited",
+		"tags": ["matting"],
+		"provenance_key": "matting",
+		"report": json_safe(report),
+		"warning": String(matting_result.get("warning", "")),
+	}
+
+
+static func _apply_outline(source: Image, params: Dictionary) -> Dictionary:
+	var normalized := normalize_outline_params(params)
+	return {
+		"ok": true,
+		"operation": OP_OUTLINE,
+		"image": Outliner.add_outline(source, normalized),
+		"suffix": "outline",
+		"name_suffix": "outline",
+		"origin": "edited",
+		"tags": ["outline"],
+		"provenance_key": "outline",
+		"report": json_safe(normalized),
+	}
+
+
+static func _string_array(value: Variant) -> Array[String]:
+	var result: Array[String] = []
+	if value is Array:
+		for item in Array(value):
+			var id := String(item)
+			if not id.is_empty():
+				result.append(id)
+	return result
diff --git a/pixel/services/pixel_operations.gd.uid b/pixel/services/pixel_operations.gd.uid
new file mode 100644
index 0000000..ec06ca5
--- /dev/null
+++ b/pixel/services/pixel_operations.gd.uid
@@ -0,0 +1 @@
+uid://bg0s3mhxysos
diff --git a/pixel/tests/smoke/test_main_window_ui.gd b/pixel/tests/smoke/test_main_window_ui.gd
index 60769a2..72a4393 100644
--- a/pixel/tests/smoke/test_main_window_ui.gd
+++ b/pixel/tests/smoke/test_main_window_ui.gd
@@ -233,7 +233,12 @@ func test_mock_generate_menu_action_creates_visible_batch_and_graph() -> void:
 
 	assert_eq(canvas.get_item_count(), 1)
 	assert_eq(ProjectService.current_project.graphs.size(), 1)
-	var graph_data: Dictionary = ProjectService.current_project.graphs.values()[0]
+	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
+	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
 	var batch_node: Dictionary = graph_data["nodes"][3]
 	assert_eq(batch_node["type"], "batch")
 	assert_eq(batch_node["params"]["asset_ids"].size(), 10)
+	var canvas_item: Dictionary = canvas.export_canvas_data()["items"][0]
+	assert_eq(canvas_item["type"], "node")
+	assert_eq(canvas_item["graph_id"], graph_id)
+	assert_eq(canvas_item["node_id"], "batch_1")
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index c5f5d58..aefa8fb 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -1,6 +1,8 @@
 extends "res://addons/gut/test.gd"
 
 const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
+const GraphScript := preload("res://core/graph/pf_graph.gd")
+const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
 
 
 func before_each() -> void:
@@ -32,6 +34,50 @@ func test_canvas_batch_card_exports_asset_queue_and_can_split_subset() -> void:
 	assert_eq(canvas.get_item_count(), 2)
 
 
+func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
+	var canvas: Control = CanvasScript.new()
+	canvas.size = Vector2(512, 512)
+	add_child_autofree(canvas)
+	await wait_process_frames(2)
+
+	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+	var graph := GraphScript.new()
+	graph.id = "graph_batch_test"
+	graph.add_node(
+		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+	)
+	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+	var card: Node = canvas._add_batch_card(
+		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+	)
+	assert_eq(card.asset_ids, ids)
+
+	var canvas_data: Dictionary = canvas.export_canvas_data()
+	var item: Dictionary = canvas_data["items"][0]
+	assert_eq(item["type"], "node")
+	assert_eq(item["graph_id"], graph.id)
+	assert_eq(item["node_id"], "batch_1")
+	assert_false(item.has("asset_ids"))
+
+	var green_id := _register_asset(Color.GREEN, "green")
+	canvas._replace_batch_asset_ids("node_item_1", [green_id], false)
+
+	assert_eq(card.asset_ids, [green_id])
+	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+	var batch_node: Dictionary = graph_data["nodes"][0]
+	assert_eq(batch_node["params"]["asset_ids"], [green_id])
+
+	var reloaded_canvas: Control = CanvasScript.new()
+	reloaded_canvas.size = Vector2(512, 512)
+	add_child_autofree(reloaded_canvas)
+	await wait_process_frames(2)
+	reloaded_canvas.load_canvas_data(canvas_data)
+
+	assert_eq(reloaded_canvas.get_item_count(), 1)
+	assert_eq(reloaded_canvas._get_batch_asset_ids("node_item_1"), [green_id])
+
+
 func _register_asset(color: Color, name: String) -> String:
 	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
 	image.fill(color)
diff --git a/pixel/tests/unit/test_pixel_operations.gd b/pixel/tests/unit/test_pixel_operations.gd
new file mode 100644
index 0000000..357a8f8
--- /dev/null
+++ b/pixel/tests/unit/test_pixel_operations.gd
@@ -0,0 +1,62 @@
+extends "res://addons/gut/test.gd"
+
+const PixelOperations := preload("res://services/pixel_operations.gd")
+const Pipeline := preload("res://core/pixel/pipeline.gd")
+
+
+func before_each() -> void:
+	get_tree().root.get_node("ProjectService").new_project("Pixel Operations")
+
+
+func test_cleanup_operation_processes_assets_and_registers_provenance() -> void:
+	var source_id := AssetLibrary.register_image(
+		_make_source_image(), "source", {"origin": "imported"}
+	)
+	var result: Dictionary = PixelOperations.apply_to_assets(
+		[source_id], AssetLibrary, PixelOperations.OP_CLEANUP, _disabled_cleanup_params()
+	)
+
+	assert_false(bool(result.get("canceled", false)))
+	assert_eq(result["items"].size(), 1)
+
+	var output_id := PixelOperations.register_result_asset(
+		AssetLibrary, source_id, result["items"][0]
+	)
+	var meta := AssetLibrary.get_asset_meta(output_id)
+	var provenance: Dictionary = meta["provenance"]
+
+	assert_eq(meta["origin"], "edited")
+	assert_eq(meta["tags"], ["cleanup"])
+	assert_eq(provenance["parent_asset"], source_id)
+	assert_eq(provenance["cleanup"]["source_asset"], source_id)
+	assert_true(provenance["cleanup"].has("params"))
+	assert_true(provenance["cleanup"].has("report"))
+
+
+func test_matting_report_is_metadata_safe() -> void:
+	var result: Dictionary = PixelOperations.apply_image(
+		PixelOperations.OP_MATTING, _make_source_image(), {}
+	)
+	var report: Dictionary = result["report"]
+
+	assert_true(bool(result.get("ok", false)))
+	assert_false(report.has("image"))
+	assert_eq(String(result.get("provenance_key", "")), "matting")
+
+
+func _make_source_image() -> Image:
+	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
+	image.fill(Color.WHITE)
+	image.set_pixel(1, 1, Color.RED)
+	image.set_pixel(2, 1, Color.RED)
+	image.set_pixel(1, 2, Color.RED)
+	image.set_pixel(2, 2, Color.RED)
+	return image
+
+
+func _disabled_cleanup_params() -> Dictionary:
+	return {
+		Pipeline.STEP_DETECT_GRID: {"enabled": false},
+		Pipeline.STEP_RESAMPLE: {"enabled": false},
+		Pipeline.STEP_QUANTIZE: {"enabled": false},
+	}
diff --git a/pixel/tests/unit/test_pixel_operations.gd.uid b/pixel/tests/unit/test_pixel_operations.gd.uid
new file mode 100644
index 0000000..6e7dc88
--- /dev/null
+++ b/pixel/tests/unit/test_pixel_operations.gd.uid
@@ -0,0 +1 @@
+uid://raslxfxmwisg
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 0a510bd..3a73278 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -2,7 +2,7 @@ class_name PFCanvasBatchCard
 extends Node2D
 
 ## M2.1 批次内容卡（无连线 MVP）。
-## 只持有 asset_id 队列和卡内勾选状态；节点图双身份与正式 graph 持久化留到 M3。
+## M3 过渡期同时支持旧 batch_card 和正式 graph batch 节点引用的渲染。
 
 const IdUtil := preload("res://core/util/id_util.gd")
 
@@ -19,6 +19,8 @@ const SELECTED_BORDER := Color(0.1, 0.85, 0.65, 1.0)
 const THUMB_BACKGROUND := Color(0.08, 0.085, 0.09, 1.0)
 
 var item_id := ""
+var graph_id := ""
+var node_id := ""
 var asset_ids: Array[String] = []
 var selected_asset_ids: Array[String] = []
 var label := ""
@@ -30,8 +32,12 @@ var _font: Font = null
 
 func setup_from_data(data: Dictionary) -> void:
 	item_id = String(data.get("id", IdUtil.uuid_v4()))
-	label = String(data.get("label", "Batch"))
-	asset_ids = _string_array(data.get("asset_ids", []))
+	graph_id = String(data.get("graph_id", ""))
+	node_id = String(data.get("node_id", ""))
+	var graph_node_data := _resolve_graph_batch_node_data()
+	var graph_params: Dictionary = graph_node_data.get("params", {})
+	label = String(graph_params.get("label", data.get("label", "Batch")))
+	asset_ids = _string_array(graph_params.get("asset_ids", data.get("asset_ids", [])))
 	selected_asset_ids = _string_array(data.get("selected_asset_ids", []))
 	locked = bool(data.get("locked", false))
 	z_index = int(data.get("z_index", 0))
@@ -43,6 +49,17 @@ func setup_from_data(data: Dictionary) -> void:
 
 
 func to_canvas_data() -> Dictionary:
+	if has_graph_binding():
+		return {
+			"id": item_id,
+			"type": "node",
+			"graph_id": graph_id,
+			"node_id": node_id,
+			"position": [int(round(position.x)), int(round(position.y))],
+			"z_index": z_index,
+			"collapsed": false,
+			"locked": locked,
+		}
 	return {
 		"id": item_id,
 		"type": "batch_card",
@@ -55,6 +72,10 @@ func to_canvas_data() -> Dictionary:
 	}
 
 
+func has_graph_binding() -> bool:
+	return not graph_id.is_empty() and not node_id.is_empty()
+
+
 func get_canvas_bounds() -> Rect2:
 	return Rect2(position, Vector2(CARD_WIDTH, _card_height()))
 
@@ -184,6 +205,22 @@ func _rebuild_thumbnails() -> void:
 		_thumbnail_textures[asset_id] = ImageTexture.create_from_image(thumb)
 
 
+func _resolve_graph_batch_node_data() -> Dictionary:
+	if not has_graph_binding():
+		return {}
+	var graph_data := ProjectService.get_graph_data(graph_id)
+	for raw_node in graph_data.get("nodes", []):
+		if not (raw_node is Dictionary):
+			continue
+		var node_data: Dictionary = raw_node
+		if (
+			String(node_data.get("id", "")) == node_id
+			and String(node_data.get("type", "")) == "batch"
+		):
+			return node_data
+	return {}
+
+
 func _string_array(value: Variant) -> Array[String]:
 	var result: Array[String] = []
 	if value is Array:
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index c87f1bb..d9118fe 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -189,14 +189,18 @@ func _add_batch_card(
 	world_position: Vector2 = Vector2.ZERO,
 	label: String = "Batch",
 	item_id: String = "",
-	record_undo: bool = true
+	record_undo: bool = true,
+	graph_id: String = "",
+	node_id: String = ""
 ) -> Node:
 	var data := {
 		"id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
-		"type": "batch_card",
+		"type": "node" if not node_id.is_empty() else "batch_card",
 		"asset_ids": asset_ids.duplicate(),
 		"selected_asset_ids": [],
 		"label": label,
+		"graph_id": graph_id,
+		"node_id": node_id,
 		"position": [int(round(world_position.x)), int(round(world_position.y))],
 		"z_index": _items_by_id.size(),
 		"locked": false,
@@ -248,7 +252,7 @@ func delete_selected(record_undo: bool = true) -> void:
 			var data: Dictionary = snapshot["data"]
 			if String(data.get("type", "")) == "sprite":
 				_add_sprite_direct(data, snapshot["image"])
-			elif String(data.get("type", "")) == "batch_card":
+			elif _is_batch_card_data(data):
 				_add_batch_direct(data)
 		_select_only(_ids_from_snapshots(snapshots))
 		_emit_canvas_changed()
@@ -298,6 +302,8 @@ func load_canvas_data(canvas_data: Dictionary) -> void:
 			_add_sprite_direct(item_data, image)
 		elif item_type == "batch_card":
 			_add_batch_direct(item_data)
+		elif item_type == "node" and _is_graph_batch_node_data(item_data):
+			_add_batch_direct(item_data)
 
 	_suppress_change_signal = false
 	_update_layer_transform()
@@ -448,11 +454,13 @@ func _replace_batch_asset_ids(
 	var before: Array = item.asset_ids.duplicate()
 	var after := new_asset_ids.duplicate()
 	var do_replace := func() -> void:
-		item.set_asset_ids(after)
+		_apply_batch_asset_ids(item, after)
+		_sync_batch_node_asset_ids(item, after)
 		_select_only([card_id])
 		_emit_canvas_changed()
 	var undo_replace := func() -> void:
-		item.set_asset_ids(before)
+		_apply_batch_asset_ids(item, before)
+		_sync_batch_node_asset_ids(item, before)
 		_select_only([card_id])
 		_emit_canvas_changed()
 	if record_undo:
@@ -461,6 +469,44 @@ func _replace_batch_asset_ids(
 		do_replace.call()
 
 
+func _apply_batch_asset_ids(item: Node, asset_ids: Array) -> void:
+	for asset_id in item.asset_ids:
+		AssetLibrary.release_ref(asset_id)
+	item.set_asset_ids(asset_ids)
+	for asset_id in item.asset_ids:
+		AssetLibrary.add_ref(asset_id)
+
+
+func _sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
+	if not item.has_method("has_graph_binding") or not item.has_graph_binding():
+		return
+
+	var graph_data := ProjectService.get_graph_data(item.graph_id)
+	if graph_data.is_empty():
+		return
+
+	var nodes := []
+	var changed := false
+	for raw_node in graph_data.get("nodes", []):
+		if not (raw_node is Dictionary):
+			nodes.append(raw_node)
+			continue
+		var node_data: Dictionary = raw_node
+		if (
+			String(node_data.get("id", "")) == item.node_id
+			and String(node_data.get("type", "")) == "batch"
+		):
+			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
+			params["asset_ids"] = _string_array(asset_ids)
+			node_data["params"] = params
+			changed = true
+		nodes.append(node_data)
+
+	if changed:
+		graph_data["nodes"] = nodes
+		ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
 func _split_batch_selection(card_id: String) -> Node:
 	if not _items_by_id.has(card_id):
 		return null
@@ -685,6 +731,31 @@ func _add_batch_direct(item_data: Dictionary) -> Node:
 	return item
 
 
+func _is_batch_card_data(item_data: Dictionary) -> bool:
+	var item_type := String(item_data.get("type", ""))
+	return (
+		item_type == "batch_card" or (item_type == "node" and _is_graph_batch_node_data(item_data))
+	)
+
+
+func _is_graph_batch_node_data(item_data: Dictionary) -> bool:
+	if String(item_data.get("type", "")) != "node":
+		return false
+	var graph_id := String(item_data.get("graph_id", ""))
+	var node_id := String(item_data.get("node_id", ""))
+	if graph_id.is_empty() or node_id.is_empty():
+		return false
+
+	var graph_data := ProjectService.get_graph_data(graph_id)
+	for raw_node in graph_data.get("nodes", []):
+		if not (raw_node is Dictionary):
+			continue
+		var node_data: Dictionary = raw_node
+		if String(node_data.get("id", "")) == node_id:
+			return String(node_data.get("type", "")) == "batch"
+	return false
+
+
 func _remove_item_direct(item_id: String) -> void:
 	if not _items_by_id.has(item_id):
 		return
@@ -762,6 +833,16 @@ func _ids_from_snapshots(snapshots: Array) -> Array:
 	return ids
 
 
+func _string_array(value: Variant) -> Array[String]:
+	var result: Array[String] = []
+	if value is Array:
+		for item in Array(value):
+			var id := String(item)
+			if not id.is_empty():
+				result.append(id)
+	return result
+
+
 func _set_zoom_to_value(value: float) -> void:
 	var nearest_index := 0
 	var nearest_distance := INF
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index 1b87de2..d1ebdc3 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -210,7 +210,13 @@ func generate_mock_batch() -> void:
 	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
 	var asset_ids: Array = result["asset_ids"]
 	var card: Node = _canvas._add_batch_card(
-		asset_ids, _canvas.get_mouse_world_position(), Strings.MOCK_BATCH_LABEL, "", true
+		asset_ids,
+		_canvas.get_mouse_world_position(),
+		Strings.MOCK_BATCH_LABEL,
+		"",
+		true,
+		graph.id,
+		"batch_1"
 	)
 	if card != null:
 		_focus_canvas_on_card(card)
diff --git a/pixel/ui/shell/m2_action_controller.gd b/pixel/ui/shell/m2_action_controller.gd
index a6a1e75..c42ea1e 100644
--- a/pixel/ui/shell/m2_action_controller.gd
+++ b/pixel/ui/shell/m2_action_controller.gd
@@ -7,11 +7,9 @@ extends RefCounted
 
 const Strings := preload("res://ui/shell/strings.gd")
 const TaskScript := preload("res://services/pf_task.gd")
-const IdUtil := preload("res://core/util/id_util.gd")
 const Matting := preload("res://core/pixel/matting.gd")
 const Segmenter := preload("res://core/pixel/segmenter.gd")
-const Outliner := preload("res://core/pixel/outliner.gd")
-const Pipeline := preload("res://core/pixel/pipeline.gd")
+const PixelOperations := preload("res://services/pixel_operations.gd")
 const ErrorHelper := preload("res://ui/dialogs/error_helper.gd")
 
 const CLEANUP_RESULT_GAP := 8
@@ -151,21 +149,11 @@ func _matting_work(task_ref: Variant) -> Dictionary:
 		if task_ref.cancel_requested:
 			return {"canceled": true, "items": results}
 		var item: Dictionary = items[index]
-		var matting_result: Dictionary = Matting.matte(item["image"], params)
-		(
-			results
-			. append(
-				{
-					"source_data": item["data"],
-					"image": matting_result["image"],
-					"suffix": "matte",
-					"tags": ["matting"],
-					"provenance_key": "matting",
-					"report": _json_safe(matting_result),
-					"warning": String(matting_result.get("warning", "")),
-				}
-			)
+		var operation_result: Dictionary = PixelOperations.apply_image(
+			PixelOperations.OP_MATTING, item["image"], params
 		)
+		operation_result["source_data"] = item["data"]
+		results.append(operation_result)
 		task_ref.report_progress(float(index + 1) / float(items.size()), "matting")
 	return {"canceled": false, "items": results}
 
@@ -215,20 +203,11 @@ func _outline_work(task_ref: Variant) -> Dictionary:
 		if task_ref.cancel_requested:
 			return {"canceled": true, "items": results}
 		var item: Dictionary = items[index]
-		var output: Image = Outliner.add_outline(item["image"], params)
-		(
-			results
-			. append(
-				{
-					"source_data": item["data"],
-					"image": output,
-					"suffix": "outline",
-					"tags": ["outline"],
-					"provenance_key": "outline",
-					"report": _json_safe(params),
-				}
-			)
+		var operation_result: Dictionary = PixelOperations.apply_image(
+			PixelOperations.OP_OUTLINE, item["image"], params
 		)
+		operation_result["source_data"] = item["data"]
+		results.append(operation_result)
 		task_ref.report_progress(float(index + 1) / float(items.size()), "outline")
 	return {"canceled": false, "items": results}
 
@@ -236,104 +215,49 @@ func _outline_work(task_ref: Variant) -> Dictionary:
 func _batch_cleanup_work(task_ref: Variant) -> Dictionary:
 	var asset_ids: Array = task_ref.payload["asset_ids"]
 	var params: Dictionary = task_ref.payload["extra"].get("params", {})
-	var results := []
-	for index in range(asset_ids.size()):
-		if task_ref.cancel_requested:
-			return {
-				"canceled": true, "card_id": String(task_ref.payload["card_id"]), "items": results
-			}
-		var asset_id := String(asset_ids[index])
-		var image := AssetLibrary.get_image(asset_id)
-		if image == null:
-			continue
-		var pipeline_result := Pipeline.apply(image, params)
-		(
-			results
-			. append(
-				{
-					"parent_asset": asset_id,
-					"image": pipeline_result["image"],
-					"name_suffix": "clean",
-					"origin": "edited",
-					"tags": ["cleanup"],
-					"provenance_key": "cleanup",
-					"report":
-					_json_safe(
-						{
-							"source_asset": asset_id,
-							"params": params,
-							"report": pipeline_result.get("report", {}),
-						}
-					),
-				}
-			)
-		)
-		task_ref.report_progress(float(index + 1) / float(asset_ids.size()), "batch_cleanup")
-	return {"canceled": false, "card_id": String(task_ref.payload["card_id"]), "items": results}
+	var result := PixelOperations.apply_to_assets(
+		asset_ids,
+		AssetLibrary,
+		PixelOperations.OP_CLEANUP,
+		params,
+		func() -> bool: return task_ref.cancel_requested,
+		func(ratio: float, _operation: String) -> void:
+			task_ref.report_progress(ratio, "batch_cleanup")
+	)
+	result["card_id"] = String(task_ref.payload["card_id"])
+	return result
 
 
 func _batch_matte_work(task_ref: Variant) -> Dictionary:
 	var asset_ids: Array = task_ref.payload["asset_ids"]
 	var params: Dictionary = _matte_params(task_ref.payload["extra"].get("params", {}))
-	var results := []
-	for index in range(asset_ids.size()):
-		if task_ref.cancel_requested:
-			return {
-				"canceled": true, "card_id": String(task_ref.payload["card_id"]), "items": results
-			}
-		var asset_id := String(asset_ids[index])
-		var image := AssetLibrary.get_image(asset_id)
-		if image == null:
-			continue
-		var matting_result: Dictionary = Matting.matte(image, params)
-		(
-			results
-			. append(
-				{
-					"parent_asset": asset_id,
-					"image": matting_result["image"],
-					"name_suffix": "matte",
-					"origin": "edited",
-					"tags": ["matting"],
-					"provenance_key": "matting",
-					"report": _json_safe(matting_result),
-					"warning": String(matting_result.get("warning", "")),
-				}
-			)
-		)
-		task_ref.report_progress(float(index + 1) / float(asset_ids.size()), "batch_matting")
-	return {"canceled": false, "card_id": String(task_ref.payload["card_id"]), "items": results}
+	var result := PixelOperations.apply_to_assets(
+		asset_ids,
+		AssetLibrary,
+		PixelOperations.OP_MATTING,
+		params,
+		func() -> bool: return task_ref.cancel_requested,
+		func(ratio: float, _operation: String) -> void:
+			task_ref.report_progress(ratio, "batch_matting")
+	)
+	result["card_id"] = String(task_ref.payload["card_id"])
+	return result
 
 
 func _batch_outline_work(task_ref: Variant) -> Dictionary:
 	var asset_ids: Array = task_ref.payload["asset_ids"]
 	var params: Dictionary = _outline_params(task_ref.payload["extra"].get("params", {}))
-	var results := []
-	for index in range(asset_ids.size()):
-		if task_ref.cancel_requested:
-			return {
-				"canceled": true, "card_id": String(task_ref.payload["card_id"]), "items": results
-			}
-		var asset_id := String(asset_ids[index])
-		var image := AssetLibrary.get_image(asset_id)
-		if image == null:
-			continue
-		(
-			results
-			. append(
-				{
-					"parent_asset": asset_id,
-					"image": Outliner.add_outline(image, params),
-					"name_suffix": "outline",
-					"origin": "edited",
-					"tags": ["outline"],
-					"provenance_key": "outline",
-					"report": _json_safe(params),
-				}
-			)
-		)
-		task_ref.report_progress(float(index + 1) / float(asset_ids.size()), "batch_outline")
-	return {"canceled": false, "card_id": String(task_ref.payload["card_id"]), "items": results}
+	var result := PixelOperations.apply_to_assets(
+		asset_ids,
+		AssetLibrary,
+		PixelOperations.OP_OUTLINE,
+		params,
+		func() -> bool: return task_ref.cancel_requested,
+		func(ratio: float, _operation: String) -> void:
+			task_ref.report_progress(ratio, "batch_outline")
+	)
+	result["card_id"] = String(task_ref.payload["card_id"])
+	return result
 
 
 func _on_generated_asset_task_finished(result: Variant, done_status: String) -> void:
@@ -356,30 +280,8 @@ func _on_generated_asset_task_finished(result: Variant, done_status: String) ->
 		var source_width := _source_width_for_canvas_data(source_data, output)
 		var placement_index := int(placement_offsets.get(parent_asset_id, 0))
 		placement_offsets[parent_asset_id] = placement_index + 1
-
-		var provenance_key := String(item_result.get("provenance_key", "operation"))
-		var provenance := {
-			"provider": null,
-			"model": null,
-			"prompt": "",
-			"seed": null,
-			"parent_asset": parent_asset_id,
-			"graph_id": null,
-			"created_at": IdUtil.utc_now_iso(),
-		}
-		provenance[provenance_key] = _json_safe(item_result.get("report", {}))
-
-		var asset_id := (
-			AssetLibrary
-			. register_image(
-				output,
-				"%s_%s" % [parent_asset_id.left(8), String(item_result.get("suffix", "m2"))],
-				{
-					"origin": "edited",
-					"tags": item_result.get("tags", []),
-					"provenance": provenance,
-				}
-			)
+		var asset_id := PixelOperations.register_result_asset(
+			AssetLibrary, parent_asset_id, item_result
 		)
 		var world_position := (
 			source_position
@@ -431,32 +333,8 @@ func _on_batch_task_finished(result: Variant, done_status: String) -> void:
 	var new_asset_ids: Array[String] = []
 	for item_result in result.get("items", []):
 		var parent_asset_id := String(item_result.get("parent_asset", ""))
-		var output: Image = item_result["image"]
-		var provenance_key := String(item_result.get("provenance_key", "operation"))
-		var provenance := {
-			"provider": null,
-			"model": null,
-			"prompt": "",
-			"seed": null,
-			"parent_asset": parent_asset_id,
-			"graph_id": null,
-			"created_at": IdUtil.utc_now_iso(),
-		}
-		provenance[provenance_key] = _json_safe(item_result.get("report", {}))
-		var asset_id := (
-			AssetLibrary
-			. register_image(
-				output,
-				(
-					"%s_%s"
-					% [parent_asset_id.left(8), String(item_result.get("name_suffix", "batch"))]
-				),
-				{
-					"origin": String(item_result.get("origin", "edited")),
-					"tags": item_result.get("tags", []),
-					"provenance": provenance,
-				}
-			)
+		var asset_id := PixelOperations.register_result_asset(
+			AssetLibrary, parent_asset_id, item_result
 		)
 		new_asset_ids.append(asset_id)
 
@@ -465,13 +343,7 @@ func _on_batch_task_finished(result: Variant, done_status: String) -> void:
 
 
 func _matte_params(params: Dictionary) -> Dictionary:
-	if params.is_empty():
-		return {"mode": Matting.MODE_FLOOD, "tolerance": 12.0, "feather": 0}
-	return {
-		"mode": String(params.get("mode", Matting.MODE_FLOOD)),
-		"tolerance": float(params.get("tolerance", 12.0)),
-		"feather": int(params.get("feather", 0)),
-	}
+	return PixelOperations.normalize_matte_params(params)
 
 
 func _slice_params(params: Dictionary) -> Dictionary:
@@ -494,14 +366,7 @@ func _slice_params(params: Dictionary) -> Dictionary:
 
 
 func _outline_params(params: Dictionary) -> Dictionary:
-	if params.is_empty():
-		return {"type": Outliner.TYPE_OUTER, "color": Color.BLACK, "corner": Outliner.CORNER_CROSS}
-	return {
-		"type": String(params.get("type", Outliner.TYPE_OUTER)),
-		"color": params.get("color", Color.BLACK),
-		"corner": String(params.get("corner", Outliner.CORNER_CROSS)),
-		"colored": bool(params.get("colored", false)),
-	}
+	return PixelOperations.normalize_outline_params(params)
 
 
 func _first_warning(items: Array) -> String:
@@ -536,29 +401,3 @@ static func _source_width_for_canvas_data(data: Dictionary, fallback_image: Imag
 
 static func _rect_to_array(rect: Rect2i) -> Array:
 	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
-
-
-static func _json_safe(value: Variant) -> Variant:
-	match typeof(value):
-		TYPE_DICTIONARY:
-			var output := {}
-			for key in Dictionary(value).keys():
-				output[String(key)] = _json_safe(Dictionary(value)[key])
-			return output
-		TYPE_ARRAY:
-			var output := []
-			for item in Array(value):
-				output.append(_json_safe(item))
-			return output
-		TYPE_VECTOR2:
-			var vector := Vector2(value)
-			return [vector.x, vector.y]
-		TYPE_VECTOR2I:
-			var vector_i := Vector2i(value)
-			return [vector_i.x, vector_i.y]
-		TYPE_RECT2I:
-			return _rect_to_array(Rect2i(value))
-		TYPE_COLOR:
-			return Color(value).to_html(true)
-		_:
-			return value
```
