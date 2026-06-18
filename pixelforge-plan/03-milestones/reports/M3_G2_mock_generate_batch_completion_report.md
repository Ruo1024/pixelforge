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

## 追加开发：G-4 最小节点链可视化基础

追加目标：把 G-2/G-3 已经能运行的 mock graph 从隐藏数据升级为画布上可见的最小节点链。此轮只做“从无到有”的基础载体：轻节点卡、连线渲染、保存重开一致；不做完整端口拖拽编辑器、参数检查器或通用 executor。

### G-4 实现

- 新增 `PFCanvasNodeCard`：
  - 渲染非 batch 的 graph 节点卡。
  - 从 `graphs/{graph_id}.json` 读取节点类型、参数摘要与端口数量。
  - 导出仍是 `canvas.items[].type = "node"`，只保存 `graph_id/node_id/position/z_index/collapsed/locked`。
- 新增 `PFCanvasGraphEdgeRenderer`：
  - 根据 `ProjectService.current_project.graphs` 中的 edges 绘制连线。
  - 连线不写入 `canvas.json`，符合 GRAPH-SCHEMA 与 PROJECT-FORMAT 的逻辑/视图分离要求。
- 新增 `PFCanvasGraphItemBridge`：
  - 承接 graph batch 判断与 batch `asset_ids` 回写，避免 `infinite_canvas.gd` 超过职责和行数上限。
- 扩展 `PFInfiniteCanvas`：
  - 支持普通 graph node card 的加载、导出、命中、拖动、删除撤销。
  - 绘制 graph edges。
  - `infinite_canvas.gd` 拆分后保持低于 gdlint `max-file-lines` 上限。
- `File > Generate Mock Batch` 现在创建四个画布节点引用：
  - `objects`
  - `size`
  - `generate`
  - `batch_1`
  并自动对焦整条链。
- 新增 `pixel/scripts/verify_m3_g4.sh`。

### G-4 修改文件

- `pixel/ui/canvas/canvas_node_card.gd`
- `pixel/ui/canvas/canvas_node_card.gd.uid`
- `pixel/ui/canvas/canvas_graph_edge_renderer.gd`
- `pixel/ui/canvas/canvas_graph_edge_renderer.gd.uid`
- `pixel/ui/canvas/canvas_graph_item_bridge.gd`
- `pixel/ui/canvas/canvas_graph_item_bridge.gd.uid`
- `pixel/ui/canvas/infinite_canvas.gd`
- `pixel/ui/shell/m2_1_ui_controller.gd`
- `pixel/tests/smoke/test_main_window_ui.gd`
- `pixel/tests/unit/test_canvas_batch_card.gd`
- `pixel/scripts/verify_m3_g4.sh`
- `pixel/CHANGELOG.md`

### G-4 验证

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：133/133 passed。
- `./pixel/scripts/verify_m3_g4.sh`：通过，输出 `verify_m3_g4: ok`。
- 既有 GUT orphan/resource warning 仍存在；run summary 为 all tests passed。

### G-4 人工测试步骤

1. 打开 Godot 项目：`/Users/ruo/Desktop/pixelforge/pixel/project.godot`。
2. 运行主场景。
3. 点击 `File > Generate Mock Batch`。
4. 画布应出现 4 个可见节点引用：`Object List`、`Size Spec`、`AI Generate`、`Mock Batch`，并能看到从 graph edges 渲染出的连线。
5. 拖动任意轻节点卡，确认可移动、可选中，连线跟随新位置重绘。
6. 右键 `Mock Batch` 批次卡，执行 `Outline Batch` 或 `Clean Batch`，确认批次卡仍可整批处理。
7. 保存 `.pxproj` 后重新打开，4 个节点的位置、连线和 batch 队列应恢复。

G-4 追加 diff：

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index 2769c04..dbecd0d 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -25,3 +25,4 @@
 - M3 G-1: 新增节点图最小领域模型、内置 batch 节点注册、端口连接矩阵/环检测，以及 `.pxproj` graphs 往返保存骨架。
 - M3 G-2: 新增 object_list / size_spec / ai_generate(mock) 节点和最小 mock runner，可将确定性生成图物化进正式 batch 节点。
 - M3 G-3: 新增 PixelOperations 共用服务，批次菜单 Clean/Matte/Outline 复用同一 core 操作，并让 Mock 批次卡以 graph batch 节点引用保存和同步资产队列。
+- M3 G-4: 新增画布轻节点卡与 graph edge 渲染，File > Generate Mock Batch 现在生成可见最小 mock 节点链并落入正式 batch 卡。
diff --git a/pixel/scripts/verify_m3_g4.sh b/pixel/scripts/verify_m3_g4.sh
new file mode 100755
index 0000000..4db2ef7
--- /dev/null
+++ b/pixel/scripts/verify_m3_g4.sh
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
+    echo "Staged image files are not allowed for M3 G-4 commits." >&2
+    exit 1
+  fi
+fi
+
+echo "verify_m3_g4: ok"
diff --git a/pixel/tests/smoke/test_main_window_ui.gd b/pixel/tests/smoke/test_main_window_ui.gd
index 72a4393..2e30fa2 100644
--- a/pixel/tests/smoke/test_main_window_ui.gd
+++ b/pixel/tests/smoke/test_main_window_ui.gd
@@ -231,14 +231,23 @@ func test_mock_generate_menu_action_creates_visible_batch_and_graph() -> void:
 	controller.generate_mock_batch()
 	await wait_process_frames(2)
 
-	assert_eq(canvas.get_item_count(), 1)
+	assert_eq(canvas.get_item_count(), 4)
 	assert_eq(ProjectService.current_project.graphs.size(), 1)
 	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
 	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
 	var batch_node: Dictionary = graph_data["nodes"][3]
 	assert_eq(batch_node["type"], "batch")
 	assert_eq(batch_node["params"]["asset_ids"].size(), 10)
-	var canvas_item: Dictionary = canvas.export_canvas_data()["items"][0]
-	assert_eq(canvas_item["type"], "node")
-	assert_eq(canvas_item["graph_id"], graph_id)
-	assert_eq(canvas_item["node_id"], "batch_1")
+	var canvas_items: Array = canvas.export_canvas_data()["items"]
+	assert_eq(canvas_items.size(), 4)
+	assert_eq(_node_ids_from_canvas_items(canvas_items), ["objects", "size", "generate", "batch_1"])
+	for canvas_item in canvas_items:
+		assert_eq(canvas_item["type"], "node")
+		assert_eq(canvas_item["graph_id"], graph_id)
+
+
+func _node_ids_from_canvas_items(items: Array) -> Array:
+	var node_ids := []
+	for item in items:
+		node_ids.append(String(Dictionary(item).get("node_id", "")))
+	return node_ids
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index aefa8fb..e5e6e96 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -3,6 +3,7 @@ extends "res://addons/gut/test.gd"
 const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
 const GraphScript := preload("res://core/graph/pf_graph.gd")
 const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
+const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
 
 
 func before_each() -> void:
@@ -78,6 +79,41 @@ func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement()
 	assert_eq(reloaded_canvas._get_batch_asset_ids("node_item_1"), [green_id])
 
 
+func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
+	var canvas: Control = CanvasScript.new()
+	canvas.size = Vector2(512, 512)
+	add_child_autofree(canvas)
+	await wait_process_frames(2)
+
+	var graph := GraphScript.new()
+	graph.id = "graph_node_card_test"
+	graph.add_node(
+		ObjectListNodeScript.new(), "objects", {"items": "barrel\ncrate"}, Vector2(24, 32)
+	)
+	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+	var node_card: Node = canvas._add_graph_node_card(
+		graph.id, "objects", Vector2(24, 32), "node_item_objects", false
+	)
+	assert_not_null(node_card)
+
+	var canvas_data: Dictionary = canvas.export_canvas_data()
+	var item: Dictionary = canvas_data["items"][0]
+	assert_eq(item["type"], "node")
+	assert_eq(item["graph_id"], graph.id)
+	assert_eq(item["node_id"], "objects")
+	assert_false(item.has("asset_ids"))
+
+	var reloaded_canvas: Control = CanvasScript.new()
+	reloaded_canvas.size = Vector2(512, 512)
+	add_child_autofree(reloaded_canvas)
+	await wait_process_frames(2)
+	reloaded_canvas.load_canvas_data(canvas_data)
+
+	assert_eq(reloaded_canvas.get_item_count(), 1)
+	assert_eq(reloaded_canvas.export_canvas_data()["items"][0]["node_id"], "objects")
+
+
 func _register_asset(color: Color, name: String) -> String:
 	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
 	image.fill(color)
diff --git a/pixel/ui/canvas/canvas_graph_edge_renderer.gd b/pixel/ui/canvas/canvas_graph_edge_renderer.gd
new file mode 100644
index 0000000..3ee0fb5
--- /dev/null
+++ b/pixel/ui/canvas/canvas_graph_edge_renderer.gd
@@ -0,0 +1,80 @@
+class_name PFCanvasGraphEdgeRenderer
+extends RefCounted
+
+## Graph 连线渲染 helper。
+## contract: 02-contracts/GRAPH-SCHEMA.md §1；连线来自 graphs，不写入 canvas.json。
+
+
+static func draw(
+	canvas: Control,
+	items_by_id: Dictionary,
+	batch_script: Script,
+	node_script: Script,
+	color: Color
+) -> void:
+	var graph_items := _graph_items_by_node(items_by_id, batch_script, node_script)
+	for graph_id in graph_items.keys():
+		var graph_data := ProjectService.get_graph_data(String(graph_id))
+		var items_by_node: Dictionary = graph_items[graph_id]
+		for edge in graph_data.get("edges", []):
+			if edge is Dictionary:
+				_draw_edge_if_visible(canvas, Dictionary(edge), items_by_node, color)
+
+
+static func _draw_edge_if_visible(
+	canvas: Control, edge: Dictionary, items_by_node: Dictionary, color: Color
+) -> void:
+	var from_data: Array = edge.get("from", ["", ""])
+	var to_data: Array = edge.get("to", ["", ""])
+	var from_node := String(from_data[0])
+	var to_node := String(to_data[0])
+	if not items_by_node.has(from_node) or not items_by_node.has(to_node):
+		return
+	_draw_graph_edge(canvas, items_by_node[from_node], items_by_node[to_node], color)
+
+
+static func _draw_graph_edge(canvas: Control, from_item: Node, to_item: Node, color: Color) -> void:
+	var from_bounds: Rect2 = from_item.get_canvas_bounds()
+	var to_bounds: Rect2 = to_item.get_canvas_bounds()
+	var start: Vector2 = canvas.world_to_screen(
+		from_bounds.position + Vector2(from_bounds.size.x, from_bounds.size.y * 0.5)
+	)
+	var end: Vector2 = canvas.world_to_screen(
+		to_bounds.position + Vector2(0.0, to_bounds.size.y * 0.5)
+	)
+	var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
+	var control_a := start + Vector2(bend, 0.0)
+	var control_b := end - Vector2(bend, 0.0)
+	var points := PackedVector2Array()
+	for index in range(17):
+		var t := float(index) / 16.0
+		points.append(_cubic_bezier(start, control_a, control_b, end, t))
+	canvas.draw_polyline(points, color, 2.0, true)
+
+
+static func _graph_items_by_node(
+	items_by_id: Dictionary, batch_script: Script, node_script: Script
+) -> Dictionary:
+	var graph_items := {}
+	for item in items_by_id.values():
+		if not _is_canvas_graph_item(item, batch_script, node_script):
+			continue
+		if item.graph_id.is_empty() or item.node_id.is_empty():
+			continue
+		if not graph_items.has(item.graph_id):
+			graph_items[item.graph_id] = {}
+		graph_items[item.graph_id][item.node_id] = item
+	return graph_items
+
+
+static func _is_canvas_graph_item(item: Node, batch_script: Script, node_script: Script) -> bool:
+	return item.get_script() == batch_script or item.get_script() == node_script
+
+
+static func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
+	var ab := a.lerp(b, t)
+	var bc := b.lerp(c, t)
+	var cd := c.lerp(d, t)
+	var abbc := ab.lerp(bc, t)
+	var bccd := bc.lerp(cd, t)
+	return abbc.lerp(bccd, t)
diff --git a/pixel/ui/canvas/canvas_graph_edge_renderer.gd.uid b/pixel/ui/canvas/canvas_graph_edge_renderer.gd.uid
new file mode 100644
index 0000000..b4ad0ec
--- /dev/null
+++ b/pixel/ui/canvas/canvas_graph_edge_renderer.gd.uid
@@ -0,0 +1 @@
+uid://q51kyw7k2gmm
diff --git a/pixel/ui/canvas/canvas_graph_item_bridge.gd b/pixel/ui/canvas/canvas_graph_item_bridge.gd
new file mode 100644
index 0000000..9cbd4de
--- /dev/null
+++ b/pixel/ui/canvas/canvas_graph_item_bridge.gd
@@ -0,0 +1,71 @@
+class_name PFCanvasGraphItemBridge
+extends RefCounted
+
+## Graph 节点引用与画布卡片之间的桥接 helper。
+## contract: 02-contracts/PROJECT-FORMAT.md §4；canvas 只存 node 引用，batch 队列回写 graph params。
+
+
+static func is_graph_batch_node_data(item_data: Dictionary) -> bool:
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
+static func apply_batch_asset_ids(item: Node, asset_ids: Array, asset_library: Node) -> void:
+	for asset_id in item.asset_ids:
+		asset_library.release_ref(asset_id)
+	item.set_asset_ids(asset_ids)
+	for asset_id in item.asset_ids:
+		asset_library.add_ref(asset_id)
+
+
+static func sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
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
+static func _string_array(value: Variant) -> Array[String]:
+	var result: Array[String] = []
+	if value is Array:
+		for item in Array(value):
+			var id := String(item)
+			if not id.is_empty():
+				result.append(id)
+	return result
diff --git a/pixel/ui/canvas/canvas_graph_item_bridge.gd.uid b/pixel/ui/canvas/canvas_graph_item_bridge.gd.uid
new file mode 100644
index 0000000..bcbffc3
--- /dev/null
+++ b/pixel/ui/canvas/canvas_graph_item_bridge.gd.uid
@@ -0,0 +1 @@
+uid://dh7007h1o75xt
diff --git a/pixel/ui/canvas/canvas_node_card.gd b/pixel/ui/canvas/canvas_node_card.gd
new file mode 100644
index 0000000..1377b36
--- /dev/null
+++ b/pixel/ui/canvas/canvas_node_card.gd
@@ -0,0 +1,165 @@
+class_name PFCanvasNodeCard
+extends Node2D
+
+## M3 画布轻节点卡。
+## contract: 02-contracts/PROJECT-FORMAT.md §4；只保存 graph/node 引用，节点逻辑从 graphs 读取。
+
+const NodeRegistryScript := preload("res://core/graph/node_registry.gd")
+const IdUtil := preload("res://core/util/id_util.gd")
+
+const CARD_SIZE := Vector2(220, 116)
+const HEADER_HEIGHT := 32
+const PADDING := 12
+const BACKGROUND := Color(0.13, 0.145, 0.155, 0.98)
+const HEADER := Color(0.22, 0.27, 0.3, 1.0)
+const BORDER := Color(0.56, 0.64, 0.66, 1.0)
+const GHOST_BORDER := Color(0.8, 0.36, 0.36, 1.0)
+const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
+const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
+
+var item_id := ""
+var graph_id := ""
+var node_id := ""
+var locked := false
+
+var _node_type := ""
+var _display_name := "Missing Node"
+var _summary := ""
+var _input_count := 0
+var _output_count := 0
+var _is_ghost := false
+var _font: Font = null
+
+
+func setup_from_data(data: Dictionary) -> void:
+	item_id = String(data.get("id", IdUtil.uuid_v4()))
+	graph_id = String(data.get("graph_id", ""))
+	node_id = String(data.get("node_id", ""))
+	locked = bool(data.get("locked", false))
+	z_index = int(data.get("z_index", 0))
+	var raw_position: Variant = data.get("position", [0, 0])
+	position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
+	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
+	_resolve_graph_node()
+	queue_redraw()
+
+
+func to_canvas_data() -> Dictionary:
+	return {
+		"id": item_id,
+		"type": "node",
+		"graph_id": graph_id,
+		"node_id": node_id,
+		"position": [int(round(position.x)), int(round(position.y))],
+		"z_index": z_index,
+		"collapsed": false,
+		"locked": locked,
+	}
+
+
+func get_canvas_bounds() -> Rect2:
+	return Rect2(position, CARD_SIZE)
+
+
+func contains_world_point(world_position: Vector2) -> bool:
+	return get_canvas_bounds().has_point(world_position)
+
+
+func is_graph_node() -> bool:
+	return not graph_id.is_empty() and not node_id.is_empty()
+
+
+func _draw() -> void:
+	_font = ThemeDB.fallback_font if _font == null else _font
+	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
+	draw_rect(rect, BACKGROUND, true)
+	draw_rect(Rect2(Vector2.ZERO, Vector2(CARD_SIZE.x, HEADER_HEIGHT)), HEADER, true)
+	draw_rect(rect, GHOST_BORDER if _is_ghost else BORDER, false, 1.4)
+	_draw_ports()
+	if _font == null:
+		return
+	draw_string(
+		_font,
+		Vector2(PADDING, 22),
+		_display_name,
+		HORIZONTAL_ALIGNMENT_LEFT,
+		CARD_SIZE.x - PADDING * 2,
+		16,
+		Color(0.92, 0.94, 0.94, 1.0)
+	)
+	draw_string(
+		_font,
+		Vector2(PADDING, 54),
+		_node_type,
+		HORIZONTAL_ALIGNMENT_LEFT,
+		CARD_SIZE.x - PADDING * 2,
+		13,
+		Color(0.66, 0.72, 0.74, 1.0)
+	)
+	draw_string(
+		_font,
+		Vector2(PADDING, 82),
+		_summary,
+		HORIZONTAL_ALIGNMENT_LEFT,
+		CARD_SIZE.x - PADDING * 2,
+		13,
+		Color(0.82, 0.84, 0.82, 1.0)
+	)
+
+
+func _draw_ports() -> void:
+	for index in range(_input_count):
+		draw_circle(_port_position(index, _input_count, true), 5.0, PORT_IN)
+	for index in range(_output_count):
+		draw_circle(_port_position(index, _output_count, false), 5.0, PORT_OUT)
+
+
+func _port_position(index: int, count: int, is_input: bool) -> Vector2:
+	var usable_height := CARD_SIZE.y - HEADER_HEIGHT - PADDING * 2
+	var y := HEADER_HEIGHT + PADDING + usable_height * float(index + 1) / float(count + 1)
+	return Vector2(0.0 if is_input else CARD_SIZE.x, y)
+
+
+func _resolve_graph_node() -> void:
+	var node_data := _find_node_data()
+	_node_type = String(node_data.get("type", "missing"))
+	_summary = _summarize_params(node_data.get("params", {}))
+
+	var registry := NodeRegistryScript.new()
+	var node: PFNode = registry.create(_node_type)
+	if node == null:
+		_is_ghost = true
+		_display_name = "Missing: %s" % _node_type
+		_input_count = 0
+		_output_count = 0
+		return
+
+	_display_name = node.get_display_name()
+	_input_count = node.get_input_ports().size()
+	_output_count = node.get_output_ports().size()
+	_is_ghost = false
+
+
+func _find_node_data() -> Dictionary:
+	var graph_data := ProjectService.get_graph_data(graph_id)
+	for raw_node in graph_data.get("nodes", []):
+		if not (raw_node is Dictionary):
+			continue
+		var node_data: Dictionary = raw_node
+		if String(node_data.get("id", "")) == node_id:
+			return node_data
+	return {"id": node_id, "type": "missing", "params": {}}
+
+
+func _summarize_params(params: Variant) -> String:
+	if not (params is Dictionary):
+		return ""
+	var source: Dictionary = params
+	if source.has("items"):
+		var lines := String(source["items"]).split("\n", false)
+		return "%d objects" % lines.size()
+	if source.has("width") and source.has("height"):
+		return "%dx%d px" % [int(source["width"]), int(source["height"])]
+	if source.has("provider_id"):
+		return "%s seed %d" % [String(source["provider_id"]), int(source.get("seed", 0))]
+	return ""
diff --git a/pixel/ui/canvas/canvas_node_card.gd.uid b/pixel/ui/canvas/canvas_node_card.gd.uid
new file mode 100644
index 0000000..e2a9d18
--- /dev/null
+++ b/pixel/ui/canvas/canvas_node_card.gd.uid
@@ -0,0 +1 @@
+uid://drusrdh20fcat
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index d9118fe..10ef29b 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -19,8 +19,12 @@ const GRID_MIN_ZOOM := 4.0
 const SELECTION_COLOR := Color(0.1, 0.85, 0.65, 1.0)
 const BOX_COLOR := Color(1.0, 0.85, 0.25, 0.35)
 const BACKGROUND_COLOR := Color(0.105, 0.11, 0.12, 1.0)
+const EDGE_COLOR := Color(0.42, 0.58, 0.62, 0.9)
 const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
 const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
+const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
+const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
+const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
 const CanvasCleanupPreviewScript := preload("res://ui/canvas/canvas_cleanup_preview.gd")
 const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")
 const ScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
@@ -127,6 +131,7 @@ func _draw() -> void:
 		>= GRID_MIN_ZOOM
 	):
 		_draw_pixel_grid()
+	_draw_graph_edges()
 
 	for item_id in _selection.selected_ids:
 		if not _items_by_id.has(item_id):
@@ -224,6 +229,42 @@ func _add_batch_card(
 	return _items_by_id.get(String(data["id"]), null)
 
 
+func _add_graph_node_card(
+	graph_id: String,
+	node_id: String,
+	world_position: Vector2 = Vector2.ZERO,
+	item_id: String = "",
+	record_undo: bool = true
+) -> Node:
+	var data := {
+		"id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
+		"type": "node",
+		"graph_id": graph_id,
+		"node_id": node_id,
+		"position": [int(round(world_position.x)), int(round(world_position.y))],
+		"z_index": _items_by_id.size(),
+		"collapsed": false,
+		"locked": false,
+	}
+
+	var do_add := func() -> void:
+		_add_node_direct(data)
+		_select_only([String(data["id"])])
+		_emit_canvas_changed()
+
+	var undo_add := func() -> void:
+		_remove_item_direct(String(data["id"]))
+		_clear_selection()
+		_emit_canvas_changed()
+
+	if record_undo:
+		UndoService.perform_action("Add node", do_add, undo_add)
+	else:
+		do_add.call()
+
+	return _items_by_id.get(String(data["id"]), null)
+
+
 func delete_selected(record_undo: bool = true) -> void:
 	if _selection.is_empty():
 		return
@@ -254,6 +295,8 @@ func delete_selected(record_undo: bool = true) -> void:
 				_add_sprite_direct(data, snapshot["image"])
 			elif _is_batch_card_data(data):
 				_add_batch_direct(data)
+			elif String(data.get("type", "")) == "node":
+				_add_node_direct(data)
 		_select_only(_ids_from_snapshots(snapshots))
 		_emit_canvas_changed()
 
@@ -304,6 +347,8 @@ func load_canvas_data(canvas_data: Dictionary) -> void:
 			_add_batch_direct(item_data)
 		elif item_type == "node" and _is_graph_batch_node_data(item_data):
 			_add_batch_direct(item_data)
+		elif item_type == "node":
+			_add_node_direct(item_data)
 
 	_suppress_change_signal = false
 	_update_layer_transform()
@@ -322,6 +367,8 @@ func export_canvas_data() -> Dictionary:
 			items.append(node.to_canvas_data())
 		elif node.get_script() == CanvasBatchCardScript:
 			items.append(node.to_canvas_data())
+		elif node.get_script() == CanvasNodeCardScript:
+			items.append(node.to_canvas_data())
 
 	return {
 		"camera":
@@ -454,13 +501,13 @@ func _replace_batch_asset_ids(
 	var before: Array = item.asset_ids.duplicate()
 	var after := new_asset_ids.duplicate()
 	var do_replace := func() -> void:
-		_apply_batch_asset_ids(item, after)
-		_sync_batch_node_asset_ids(item, after)
+		GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
+		GraphItemBridge.sync_batch_node_asset_ids(item, after)
 		_select_only([card_id])
 		_emit_canvas_changed()
 	var undo_replace := func() -> void:
-		_apply_batch_asset_ids(item, before)
-		_sync_batch_node_asset_ids(item, before)
+		GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
+		GraphItemBridge.sync_batch_node_asset_ids(item, before)
 		_select_only([card_id])
 		_emit_canvas_changed()
 	if record_undo:
@@ -469,44 +516,6 @@ func _replace_batch_asset_ids(
 		do_replace.call()
 
 
-func _apply_batch_asset_ids(item: Node, asset_ids: Array) -> void:
-	for asset_id in item.asset_ids:
-		AssetLibrary.release_ref(asset_id)
-	item.set_asset_ids(asset_ids)
-	for asset_id in item.asset_ids:
-		AssetLibrary.add_ref(asset_id)
-
-
-func _sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
-	if not item.has_method("has_graph_binding") or not item.has_graph_binding():
-		return
-
-	var graph_data := ProjectService.get_graph_data(item.graph_id)
-	if graph_data.is_empty():
-		return
-
-	var nodes := []
-	var changed := false
-	for raw_node in graph_data.get("nodes", []):
-		if not (raw_node is Dictionary):
-			nodes.append(raw_node)
-			continue
-		var node_data: Dictionary = raw_node
-		if (
-			String(node_data.get("id", "")) == item.node_id
-			and String(node_data.get("type", "")) == "batch"
-		):
-			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
-			params["asset_ids"] = _string_array(asset_ids)
-			node_data["params"] = params
-			changed = true
-		nodes.append(node_data)
-
-	if changed:
-		graph_data["nodes"] = nodes
-		ProjectService.set_graph_data(item.graph_id, graph_data, true)
-
-
 func _split_batch_selection(card_id: String) -> Node:
 	if not _items_by_id.has(card_id):
 		return null
@@ -731,6 +740,16 @@ func _add_batch_direct(item_data: Dictionary) -> Node:
 	return item
 
 
+func _add_node_direct(item_data: Dictionary) -> Node:
+	var item: Node = CanvasNodeCardScript.new()
+	item.setup_from_data(item_data)
+	item_layer.add_child(item)
+	_items_by_id[item.item_id] = item
+	_update_item_visibility()
+	queue_redraw()
+	return item
+
+
 func _is_batch_card_data(item_data: Dictionary) -> bool:
 	var item_type := String(item_data.get("type", ""))
 	return (
@@ -739,21 +758,7 @@ func _is_batch_card_data(item_data: Dictionary) -> bool:
 
 
 func _is_graph_batch_node_data(item_data: Dictionary) -> bool:
-	if String(item_data.get("type", "")) != "node":
-		return false
-	var graph_id := String(item_data.get("graph_id", ""))
-	var node_id := String(item_data.get("node_id", ""))
-	if graph_id.is_empty() or node_id.is_empty():
-		return false
-
-	var graph_data := ProjectService.get_graph_data(graph_id)
-	for raw_node in graph_data.get("nodes", []):
-		if not (raw_node is Dictionary):
-			continue
-		var node_data: Dictionary = raw_node
-		if String(node_data.get("id", "")) == node_id:
-			return String(node_data.get("type", "")) == "batch"
-	return false
+	return GraphItemBridge.is_graph_batch_node_data(item_data)
 
 
 func _remove_item_direct(item_id: String) -> void:
@@ -783,6 +788,7 @@ func _item_at_world(world_position: Vector2) -> Node:
 			(
 				item.get_script() == CanvasItemSpriteScript
 				or item.get_script() == CanvasBatchCardScript
+				or item.get_script() == CanvasNodeCardScript
 			)
 			and item.visible
 			and item.contains_world_point(world_position)
@@ -833,16 +839,6 @@ func _ids_from_snapshots(snapshots: Array) -> Array:
 	return ids
 
 
-func _string_array(value: Variant) -> Array[String]:
-	var result: Array[String] = []
-	if value is Array:
-		for item in Array(value):
-			var id := String(item)
-			if not id.is_empty():
-				result.append(id)
-	return result
-
-
 func _set_zoom_to_value(value: float) -> void:
 	var nearest_index := 0
 	var nearest_distance := INF
@@ -916,6 +912,12 @@ func _draw_pixel_grid() -> void:
 	PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
 
 
+func _draw_graph_edges() -> void:
+	GraphEdgeRenderer.draw(
+		self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, EDGE_COLOR
+	)
+
+
 func _emit_canvas_changed() -> void:
 	if _suppress_change_signal:
 		return
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index d1ebdc3..851efd4 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -209,17 +209,9 @@ func generate_mock_batch() -> void:
 
 	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
 	var asset_ids: Array = result["asset_ids"]
-	var card: Node = _canvas._add_batch_card(
-		asset_ids,
-		_canvas.get_mouse_world_position(),
-		Strings.MOCK_BATCH_LABEL,
-		"",
-		true,
-		graph.id,
-		"batch_1"
-	)
-	if card != null:
-		_focus_canvas_on_card(card)
+	var items := _add_mock_graph_canvas_items(graph, asset_ids, _canvas.get_mouse_world_position())
+	if not items.is_empty():
+		_focus_canvas_on_bounds(_bounds_for_items(items))
 	_status_label.text = Strings.STATUS_MOCK_GENERATE_DONE % asset_ids.size()
 
 
@@ -386,7 +378,10 @@ func _emit_batch_export(asset_ids: Array) -> void:
 
 
 func _focus_canvas_on_card(card: Node) -> void:
-	var bounds: Rect2 = card.get_canvas_bounds()
+	_focus_canvas_on_bounds(card.get_canvas_bounds())
+
+
+func _focus_canvas_on_bounds(bounds: Rect2) -> void:
 	if (
 		bounds.size.x <= 0.0
 		or bounds.size.y <= 0.0
@@ -401,6 +396,13 @@ func _focus_canvas_on_card(card: Node) -> void:
 	_canvas.pan_by_pixels(_canvas.world_to_screen(bounds.get_center()) - _canvas.size * 0.5)
 
 
+func _bounds_for_items(items: Array) -> Rect2:
+	var bounds: Rect2 = items[0].get_canvas_bounds()
+	for index in range(1, items.size()):
+		bounds = bounds.merge(items[index].get_canvas_bounds())
+	return bounds
+
+
 func _single_selected_image() -> Image:
 	var snapshots: Array = _canvas.get_selected_sprite_snapshots()
 	if snapshots.size() != 1:
@@ -448,16 +450,16 @@ func _make_mock_generate_graph() -> PFGraph:
 		SizeSpecNodeScript.new(),
 		"size",
 		{"width": 32, "height": 32, "per_subject": 1},
-		Vector2(220, 0)
+		Vector2(0, 150)
 	)
 	graph.add_node(
 		AiGenerateNodeScript.new(),
 		"generate",
 		{"provider_id": "mock", "batch_size": 2, "seed": 1000},
-		Vector2(440, 0)
+		Vector2(280, 75)
 	)
 	graph.add_node(
-		BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(660, 0)
+		BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(560, -20)
 	)
 	graph.add_edge("objects", "items", "generate", "items")
 	graph.add_edge("size", "spec", "generate", "spec")
@@ -465,6 +467,34 @@ func _make_mock_generate_graph() -> PFGraph:
 	return graph
 
 
+func _add_mock_graph_canvas_items(graph: PFGraph, asset_ids: Array, anchor: Vector2) -> Array:
+	var items := []
+	for node_id in ["objects", "size", "generate"]:
+		var node_item: Node = _canvas._add_graph_node_card(
+			graph.id, node_id, anchor + _graph_node_position(graph, node_id), "", false
+		)
+		if node_item != null:
+			items.append(node_item)
+	var batch_card: Node = _canvas._add_batch_card(
+		asset_ids,
+		anchor + _graph_node_position(graph, "batch_1"),
+		Strings.MOCK_BATCH_LABEL,
+		"",
+		false,
+		graph.id,
+		"batch_1"
+	)
+	if batch_card != null:
+		items.append(batch_card)
+	return items
+
+
+func _graph_node_position(graph: PFGraph, node_id: String) -> Vector2:
+	var node_data: Dictionary = graph.nodes.get(node_id, {})
+	var raw_position: Variant = node_data.get("position", [0, 0])
+	return Vector2(float(raw_position[0]), float(raw_position[1])).round()
+
+
 func _show_onboarding_dialog() -> void:
 	var dialog: AcceptDialog = OnboardingScript.show_first_run_tips(self)
 	if dialog == null:
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

## 追加修复：G-4 端口与连线对齐

问题来源：人工验证截图中，轻节点端口点与 graph 连线端点未对齐；根因是 `PFCanvasGraphEdgeRenderer` 按卡片边缘中心连线，而 `PFCanvasNodeCard` 按端口列表位置绘制端口点。

### 修复内容

- `pixel/ui/canvas/canvas_node_card.gd`
  - 保存输入/输出端口名列表。
  - 新增 `get_graph_port_anchor(port_name, is_input)`，让连线可按 edge 中的命名端口定位到同一个点。
- `pixel/ui/canvas/canvas_batch_card.gd`
  - graph 绑定的 batch 卡新增输入/输出端口点绘制。
  - 新增 `get_graph_port_anchor(port_name, is_input)`，让 batch 输入点和连线端点一致。
- `pixel/ui/canvas/canvas_graph_edge_renderer.gd`
  - 连线从 `edge.from[1]` / `edge.to[1]` 读取端口名，优先使用卡片暴露的端口锚点。
- `pixel/ui/shell/m2_1_ui_controller.gd`
  - 微调 mock batch 默认 y 坐标，使 AI Generate 输出到 Mock Batch 输入更接近水平。
- `pixel/tests/unit/test_canvas_batch_card.gd`
  - 新增端口锚点回归测试，避免再次退回“卡片中心连线”。

### 验证

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：通过，`134/134` tests，`1107` asserts。

### 人工测试步骤

1. 打开 `/Users/ruo/Desktop/pixelforge/pixel/project.godot` 并运行主场景。
2. 点击 `File > Generate Mock Batch`。
3. 确认 `Object List` / `Size Spec` 到 `AI Generate` 的两条线分别接到对应蓝色输入点。
4. 确认 `AI Generate` 到 `Mock Batch` 的线接到绿色输出点和 batch 左侧蓝色输入点。
5. 拖动任一节点卡，确认线端点持续贴合端口点。

G-4 端口对齐修复 diff：

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index dbecd0d..4604944 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -26,3 +26,4 @@
 - M3 G-2: 新增 object_list / size_spec / ai_generate(mock) 节点和最小 mock runner，可将确定性生成图物化进正式 batch 节点。
 - M3 G-3: 新增 PixelOperations 共用服务，批次菜单 Clean/Matte/Outline 复用同一 core 操作，并让 Mock 批次卡以 graph batch 节点引用保存和同步资产队列。
 - M3 G-4: 新增画布轻节点卡与 graph edge 渲染，File > Generate Mock Batch 现在生成可见最小 mock 节点链并落入正式 batch 卡。
+- M3 G-4 follow-up: graph 连线改用命名端口锚点，修正轻节点端口点、batch 输入点与连线端点错位。
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index e5e6e96..732c28c 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -2,6 +2,8 @@ extends "res://addons/gut/test.gd"
 
 const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
 const GraphScript := preload("res://core/graph/pf_graph.gd")
+const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
+const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
 const BatchNodeScript := preload("res://core/graph/nodes/batch_node.gd")
 const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
 
@@ -114,6 +116,55 @@ func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
 	assert_eq(reloaded_canvas.export_canvas_data()["items"][0]["node_id"], "objects")
 
 
+func test_graph_edge_anchors_follow_named_ports() -> void:
+	var canvas: Control = CanvasScript.new()
+	canvas.size = Vector2(512, 512)
+	add_child_autofree(canvas)
+	await wait_process_frames(2)
+
+	var ids := [_register_asset(Color.RED, "red")]
+	var graph := GraphScript.new()
+	graph.id = "graph_anchor_test"
+	graph.add_node(
+		AiGenerateNodeScript.new(),
+		"generate",
+		{"provider_id": "mock", "batch_size": 1, "seed": 3},
+		Vector2(10, 20)
+	)
+	graph.add_node(
+		BatchNodeScript.new(),
+		"batch_1",
+		{"label": "Candidates", "asset_ids": ids},
+		Vector2(300, 69)
+	)
+	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+	var generate_card: Node = canvas._add_graph_node_card(
+		graph.id, "generate", Vector2(10, 20), "node_item_generate", false
+	)
+	var batch_card: Node = canvas._add_batch_card(
+		ids, Vector2(300, 69), "Candidates", "node_item_batch", false, graph.id, "batch_1"
+	)
+
+	var items_anchor: Vector2 = generate_card.get_graph_port_anchor("items", true)
+	var spec_anchor: Vector2 = generate_card.get_graph_port_anchor("spec", true)
+	var output_anchor: Vector2 = generate_card.get_graph_port_anchor("images", false)
+	var right_center: Vector2 = (
+		generate_card.get_canvas_bounds().position
+		+ Vector2(
+			generate_card.get_canvas_bounds().size.x, generate_card.get_canvas_bounds().size.y * 0.5
+		)
+	)
+
+	assert_ne(items_anchor, spec_anchor)
+	assert_ne(output_anchor, right_center)
+	assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "images", false), output_anchor)
+	assert_eq(
+		GraphEdgeRenderer._edge_anchor_world(batch_card, "in", true),
+		batch_card.get_graph_port_anchor("in", true)
+	)
+
+
 func _register_asset(color: Color, name: String) -> String:
 	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
 	image.fill(color)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 3a73278..426b25d 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -17,6 +17,10 @@ const BACKGROUND := Color(0.16, 0.17, 0.18, 0.96)
 const BORDER := Color(0.52, 0.62, 0.72, 1.0)
 const SELECTED_BORDER := Color(0.1, 0.85, 0.65, 1.0)
 const THUMB_BACKGROUND := Color(0.08, 0.085, 0.09, 1.0)
+const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
+const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
+const INPUT_PORTS: Array[String] = ["in"]
+const OUTPUT_PORTS: Array[String] = ["images", "assets"]
 
 var item_id := ""
 var graph_id := ""
@@ -84,6 +88,17 @@ func contains_world_point(world_position: Vector2) -> bool:
 	return get_canvas_bounds().has_point(world_position)
 
 
+func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
+	var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
+	var count := ports.size()
+	if count <= 0:
+		return position + Vector2(0.0 if is_input else CARD_WIDTH, _card_height() * 0.5)
+	var index := ports.find(port_name)
+	if index < 0:
+		index = 0
+	return position + _graph_port_position(index, count, is_input)
+
+
 func set_asset_ids(new_asset_ids: Array) -> void:
 	asset_ids = _string_array(new_asset_ids)
 	for selected_id in selected_asset_ids.duplicate():
@@ -146,6 +161,8 @@ func _draw() -> void:
 	var columns := _columns()
 	for index in range(asset_ids.size()):
 		_draw_thumbnail(index, _thumb_rect(index, columns))
+	if has_graph_binding():
+		_draw_graph_ports()
 
 
 func _draw_thumbnail(index: int, rect: Rect2) -> void:
@@ -187,6 +204,21 @@ func _columns() -> int:
 	return maxi(1, int((CARD_WIDTH - PADDING * 2 + THUMB_GAP) / (THUMB_SIZE + THUMB_GAP)))
 
 
+func _draw_graph_ports() -> void:
+	for index in range(INPUT_PORTS.size()):
+		draw_circle(_graph_port_position(index, INPUT_PORTS.size(), true), 5.0, PORT_IN)
+	for index in range(OUTPUT_PORTS.size()):
+		draw_circle(_graph_port_position(index, OUTPUT_PORTS.size(), false), 5.0, PORT_OUT)
+
+
+func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:
+	var lane_height := minf(
+		THUMB_SIZE, maxf(0.0, float(_card_height()) - HEADER_HEIGHT - PADDING * 2)
+	)
+	var y := HEADER_HEIGHT + PADDING + lane_height * float(index + 1) / float(count + 1)
+	return Vector2(0.0 if is_input else CARD_WIDTH, y)
+
+
 func _rebuild_thumbnails() -> void:
 	_thumbnail_textures.clear()
 	for asset_id in asset_ids:
diff --git a/pixel/ui/canvas/canvas_graph_edge_renderer.gd b/pixel/ui/canvas/canvas_graph_edge_renderer.gd
index 3ee0fb5..e24bbf2 100644
--- a/pixel/ui/canvas/canvas_graph_edge_renderer.gd
+++ b/pixel/ui/canvas/canvas_graph_edge_renderer.gd
@@ -30,18 +30,30 @@ static func _draw_edge_if_visible(
 	var to_node := String(to_data[0])
 	if not items_by_node.has(from_node) or not items_by_node.has(to_node):
 		return
-	_draw_graph_edge(canvas, items_by_node[from_node], items_by_node[to_node], color)
+	_draw_graph_edge(
+		canvas,
+		items_by_node[from_node],
+		String(from_data[1]),
+		items_by_node[to_node],
+		String(to_data[1]),
+		color
+	)
 
 
-static func _draw_graph_edge(canvas: Control, from_item: Node, to_item: Node, color: Color) -> void:
-	var from_bounds: Rect2 = from_item.get_canvas_bounds()
-	var to_bounds: Rect2 = to_item.get_canvas_bounds()
-	var start: Vector2 = canvas.world_to_screen(
-		from_bounds.position + Vector2(from_bounds.size.x, from_bounds.size.y * 0.5)
-	)
-	var end: Vector2 = canvas.world_to_screen(
-		to_bounds.position + Vector2(0.0, to_bounds.size.y * 0.5)
-	)
+static func _draw_graph_edge(
+	canvas: Control,
+	from_item: Node,
+	from_port: String,
+	to_item: Node,
+	to_port: String,
+	color: Color
+) -> void:
+	var start_world: Variant = _edge_anchor_world(from_item, from_port, false)
+	var end_world: Variant = _edge_anchor_world(to_item, to_port, true)
+	if not (start_world is Vector2) or not (end_world is Vector2):
+		return
+	var start: Vector2 = canvas.world_to_screen(start_world)
+	var end: Vector2 = canvas.world_to_screen(end_world)
 	var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
 	var control_a := start + Vector2(bend, 0.0)
 	var control_b := end - Vector2(bend, 0.0)
@@ -52,6 +64,13 @@ static func _draw_graph_edge(canvas: Control, from_item: Node, to_item: Node, co
 	canvas.draw_polyline(points, color, 2.0, true)
 
 
+static func _edge_anchor_world(item: Node, port_name: String, is_input: bool) -> Variant:
+	if item.has_method("get_graph_port_anchor"):
+		return item.get_graph_port_anchor(port_name, is_input)
+	var bounds: Rect2 = item.get_canvas_bounds()
+	return bounds.position + Vector2(0.0 if is_input else bounds.size.x, bounds.size.y * 0.5)
+
+
 static func _graph_items_by_node(
 	items_by_id: Dictionary, batch_script: Script, node_script: Script
 ) -> Dictionary:
diff --git a/pixel/ui/canvas/canvas_node_card.gd b/pixel/ui/canvas/canvas_node_card.gd
index 1377b36..382cf04 100644
--- a/pixel/ui/canvas/canvas_node_card.gd
+++ b/pixel/ui/canvas/canvas_node_card.gd
@@ -27,6 +27,8 @@ var _display_name := "Missing Node"
 var _summary := ""
 var _input_count := 0
 var _output_count := 0
+var _input_ports: Array[String] = []
+var _output_ports: Array[String] = []
 var _is_ghost := false
 var _font: Font = null
 
@@ -69,6 +71,16 @@ func is_graph_node() -> bool:
 	return not graph_id.is_empty() and not node_id.is_empty()
 
 
+func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
+	var count := _input_count if is_input else _output_count
+	if count <= 0:
+		return position + Vector2(0.0 if is_input else CARD_SIZE.x, CARD_SIZE.y * 0.5)
+	var index := _port_index(port_name, is_input)
+	if index < 0:
+		index = 0
+	return position + _port_position(index, count, is_input)
+
+
 func _draw() -> void:
 	_font = ThemeDB.fallback_font if _font == null else _font
 	var rect := Rect2(Vector2.ZERO, CARD_SIZE)
@@ -120,6 +132,11 @@ func _port_position(index: int, count: int, is_input: bool) -> Vector2:
 	return Vector2(0.0 if is_input else CARD_SIZE.x, y)
 
 
+func _port_index(port_name: String, is_input: bool) -> int:
+	var ports := _input_ports if is_input else _output_ports
+	return ports.find(port_name)
+
+
 func _resolve_graph_node() -> void:
 	var node_data := _find_node_data()
 	_node_type = String(node_data.get("type", "missing"))
@@ -132,14 +149,25 @@ func _resolve_graph_node() -> void:
 		_display_name = "Missing: %s" % _node_type
 		_input_count = 0
 		_output_count = 0
+		_input_ports = []
+		_output_ports = []
 		return
 
 	_display_name = node.get_display_name()
-	_input_count = node.get_input_ports().size()
-	_output_count = node.get_output_ports().size()
+	_input_ports = _port_names(node.get_input_ports())
+	_output_ports = _port_names(node.get_output_ports())
+	_input_count = _input_ports.size()
+	_output_count = _output_ports.size()
 	_is_ghost = false
 
 
+func _port_names(port_specs: Array[Dictionary]) -> Array[String]:
+	var result: Array[String] = []
+	for port_spec in port_specs:
+		result.append(String(port_spec.get("name", "")))
+	return result
+
+
 func _find_node_data() -> Dictionary:
 	var graph_data := ProjectService.get_graph_data(graph_id)
 	for raw_node in graph_data.get("nodes", []):
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index 851efd4..58e6b2d 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -459,7 +459,7 @@ func _make_mock_generate_graph() -> PFGraph:
 		Vector2(280, 75)
 	)
 	graph.add_node(
-		BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(560, -20)
+		BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(560, 29)
 	)
 	graph.add_edge("objects", "items", "generate", "items")
 	graph.add_edge("size", "spec", "generate", "spec")
```

## 追加修复：AI Generate 单视觉输入点

问题来源：人工验证截图中，`AI Generate` 左侧显示了 5 个逻辑输入点；当前基础链只连接 `items` 和 `spec`，其余未连接输入点会制造视觉噪声。

### 修复内容

- `pixel/ui/canvas/canvas_node_card.gd`
  - 新增视觉端口列表，与逻辑端口列表分离。
  - `ai_generate` 的多个逻辑输入端口在画布 MVP 中折叠为单个视觉输入点。
  - 注释明确：这里只折叠画布视觉入口，graph edge 仍保留原始命名端口。
- `pixel/tests/unit/test_canvas_batch_card.gd`
  - 更新端口锚点测试，确认 `items` / `spec` 共享同一个 AI Generate 输入锚点。
- `pixel/CHANGELOG.md`
  - 记录本次视觉折叠修复。

### 验证

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：通过，`134/134` tests，`1109` asserts。
- `./pixel/scripts/verify_m3_g4.sh`：通过，`verify_m3_g4: ok`。

### 人工测试步骤

1. 打开 `/Users/ruo/Desktop/pixelforge/pixel/project.godot` 并运行主场景。
2. 点击 `File > Generate Mock Batch`。
3. 确认 `AI Generate` 左侧只显示 1 个蓝色输入点。
4. 确认 `Object List` 和 `Size Spec` 两条线都连到这个输入点。
5. 拖动 `AI Generate` 或上游节点，确认线端点继续贴合这个单输入点。

AI Generate 单视觉输入点 diff：

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index 4604944..20427b6 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -27,3 +27,4 @@
 - M3 G-3: 新增 PixelOperations 共用服务，批次菜单 Clean/Matte/Outline 复用同一 core 操作，并让 Mock 批次卡以 graph batch 节点引用保存和同步资产队列。
 - M3 G-4: 新增画布轻节点卡与 graph edge 渲染，File > Generate Mock Batch 现在生成可见最小 mock 节点链并落入正式 batch 卡。
 - M3 G-4 follow-up: graph 连线改用命名端口锚点，修正轻节点端口点、batch 输入点与连线端点错位。
+- M3 G-4 follow-up: AI Generate 画布卡将多个逻辑输入折叠为单个视觉输入点，降低基础节点链噪声。
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index 732c28c..913ef43 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -116,7 +116,7 @@ func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
 	assert_eq(reloaded_canvas.export_canvas_data()["items"][0]["node_id"], "objects")
 
 
-func test_graph_edge_anchors_follow_named_ports() -> void:
+func test_ai_generate_inputs_share_single_canvas_anchor() -> void:
 	var canvas: Control = CanvasScript.new()
 	canvas.size = Vector2(512, 512)
 	add_child_autofree(canvas)
@@ -156,8 +156,10 @@ func test_graph_edge_anchors_follow_named_ports() -> void:
 		)
 	)
 
-	assert_ne(items_anchor, spec_anchor)
+	assert_eq(items_anchor, spec_anchor)
 	assert_ne(output_anchor, right_center)
+	assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "items", true), items_anchor)
+	assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "spec", true), items_anchor)
 	assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "images", false), output_anchor)
 	assert_eq(
 		GraphEdgeRenderer._edge_anchor_world(batch_card, "in", true),
diff --git a/pixel/ui/canvas/canvas_node_card.gd b/pixel/ui/canvas/canvas_node_card.gd
index 382cf04..256e81f 100644
--- a/pixel/ui/canvas/canvas_node_card.gd
+++ b/pixel/ui/canvas/canvas_node_card.gd
@@ -29,6 +29,8 @@ var _input_count := 0
 var _output_count := 0
 var _input_ports: Array[String] = []
 var _output_ports: Array[String] = []
+var _visible_input_ports: Array[String] = []
+var _visible_output_ports: Array[String] = []
 var _is_ghost := false
 var _font: Font = null
 
@@ -133,7 +135,7 @@ func _port_position(index: int, count: int, is_input: bool) -> Vector2:
 
 
 func _port_index(port_name: String, is_input: bool) -> int:
-	var ports := _input_ports if is_input else _output_ports
+	var ports := _visible_input_ports if is_input else _visible_output_ports
 	return ports.find(port_name)
 
 
@@ -151,16 +153,27 @@ func _resolve_graph_node() -> void:
 		_output_count = 0
 		_input_ports = []
 		_output_ports = []
+		_visible_input_ports = []
+		_visible_output_ports = []
 		return
 
 	_display_name = node.get_display_name()
 	_input_ports = _port_names(node.get_input_ports())
 	_output_ports = _port_names(node.get_output_ports())
-	_input_count = _input_ports.size()
-	_output_count = _output_ports.size()
+	_visible_input_ports = _visible_input_ports_for_node(_node_type, _input_ports)
+	_visible_output_ports = _output_ports.duplicate()
+	_input_count = _visible_input_ports.size()
+	_output_count = _visible_output_ports.size()
 	_is_ghost = false
 
 
+func _visible_input_ports_for_node(node_type: String, port_names: Array[String]) -> Array[String]:
+	# M3 画布 MVP 只折叠视觉入口；graph edge 仍保留原始命名端口。
+	if node_type == "ai_generate" and not port_names.is_empty():
+		return ["in"]
+	return port_names.duplicate()
+
+
 func _port_names(port_specs: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for port_spec in port_specs:
```

## 追加开发：G-5 最小重跑入口

追加目标：让 G-4 已经可见的最小 mock 节点链不再只是一次性生成结果，而是能在画布中选中任一 graph 节点后通过菜单重跑并刷新正式 batch 队列。本轮仍不做完整 executor、参数检查器、异步 Run/Cancel 状态机，只铺“可直接使用”的最小 Run 入口。

### G-5 实现

- `pixel/ui/shell/m2_1_ui_controller.gd`
  - File 菜单新增 `Run Selected Graph`。
  - 选中任一 graph node / graph batch 卡后，读取其 `graph_id`，用现有 `PFGraphMockRunner` 重跑 mock 链。
  - 重跑结果替换当前 batch 队列，并同步 graph batch 节点 `params.asset_ids` 与画布卡缩略图。
- `pixel/services/graph_mock_runner.gd`
  - `run_to_batch()` 增加 `replace_batch_assets` 参数。
  - 默认保持原有追加行为；菜单重跑时使用替换模式，避免一次次重复追加旧候选。
- `pixel/ui/shell/strings.gd`
  - 新增 Run 菜单文案与状态栏提示。
- `pixel/scripts/verify_m3_g5.sh`
  - 新增 G5 本地出口脚本。

### G-5 修改文件

- `pixel/CHANGELOG.md`
- `pixel/scripts/verify_m3_g5.sh`
- `pixel/services/graph_mock_runner.gd`
- `pixel/ui/shell/m2_1_ui_controller.gd`
- `pixel/ui/shell/strings.gd`
- `pixel/tests/integration/test_graph_mock_runner.gd`
- `pixel/tests/smoke/test_main_window_ui.gd`

### G-5 验证

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：通过，`135/135` tests，`1121` asserts。
- `./pixel/scripts/verify_m3_g5.sh`：通过，`verify_m3_g5: ok`。

### G-5 人工测试步骤

1. 打开 `/Users/ruo/Desktop/pixelforge/pixel/project.godot` 并运行主场景。
2. 点击 `File > Generate Mock Batch`。
3. 选中 `Object List`、`Size Spec`、`AI Generate` 或 `Mock Batch` 中任意一个节点/卡。
4. 点击 `File > Run Selected Graph`。
5. 预期：状态栏显示 `Graph run complete: 10 sprites`，Mock Batch 内仍为 10 张图，不会追加成 20 张。
6. 可重复执行第 4 步，确认每次都是刷新同一 batch 队列；保存重开后 batch 队列仍对应 graph batch 节点。

G-5 追加 diff：

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index 20427b6..bce660e 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -28,3 +28,4 @@
 - M3 G-4: 新增画布轻节点卡与 graph edge 渲染，File > Generate Mock Batch 现在生成可见最小 mock 节点链并落入正式 batch 卡。
 - M3 G-4 follow-up: graph 连线改用命名端口锚点，修正轻节点端口点、batch 输入点与连线端点错位。
 - M3 G-4 follow-up: AI Generate 画布卡将多个逻辑输入折叠为单个视觉输入点，降低基础节点链噪声。
+- M3 G-5: 新增 File > Run Selected Graph 最小重跑入口，选中 mock 节点链任一节点后可替换刷新正式 batch 队列。
diff --git a/pixel/scripts/verify_m3_g5.sh b/pixel/scripts/verify_m3_g5.sh
new file mode 100755
index 0000000..1f953e0
--- /dev/null
+++ b/pixel/scripts/verify_m3_g5.sh
@@ -0,0 +1,17 @@
+#!/usr/bin/env bash
+set -euo pipefail
+
+cd "$(dirname "$0")/../.."
+
+./pixel/scripts/configure_editor_game_view.sh
+./pixel/scripts/lint.sh
+./pixel/scripts/run_tests.sh
+./pixel/scripts/check_ui_scaling.sh
+./pixel/scripts/check_export_templates.sh
+
+if git diff --cached --name-only | grep -iE '\.(png|jpe?g)$' >/dev/null; then
+  echo "Staged image files are not allowed for M3 G-5 commits." >&2
+  exit 1
+fi
+
+echo "verify_m3_g5: ok"
diff --git a/pixel/services/graph_mock_runner.gd b/pixel/services/graph_mock_runner.gd
index bdd4954..b3f9621 100644
--- a/pixel/services/graph_mock_runner.gd
+++ b/pixel/services/graph_mock_runner.gd
@@ -7,7 +7,12 @@ extends RefCounted
 const IdUtil := preload("res://core/util/id_util.gd")
 
 
-func run_to_batch(graph: PFGraph, asset_library: Node, batch_node_id: String = "") -> Dictionary:
+func run_to_batch(
+	graph: PFGraph,
+	asset_library: Node,
+	batch_node_id: String = "",
+	replace_batch_assets: bool = false
+) -> Dictionary:
 	if graph == null:
 		return _error("missing_graph", "Graph is required")
 	if asset_library == null or not asset_library.has_method("register_image"):
@@ -22,7 +27,13 @@ func run_to_batch(graph: PFGraph, asset_library: Node, batch_node_id: String = "
 	var materialized_asset_ids := []
 	for node_id in order_result["order"]:
 		var run_result := _run_node(
-			graph, String(node_id), inputs_by_node, outputs_by_node, asset_library, batch_node_id
+			graph,
+			String(node_id),
+			inputs_by_node,
+			outputs_by_node,
+			asset_library,
+			batch_node_id,
+			replace_batch_assets
 		)
 		if not bool(run_result["ok"]):
 			return run_result
@@ -40,7 +51,8 @@ func _run_node(
 	inputs_by_node: Dictionary,
 	outputs_by_node: Dictionary,
 	asset_library: Node,
-	batch_node_id: String
+	batch_node_id: String,
+	replace_batch_assets: bool
 ) -> Dictionary:
 	var node := graph.get_node(node_id)
 	if node == null:
@@ -54,7 +66,12 @@ func _run_node(
 	if node.get_type() == "batch":
 		if batch_node_id.is_empty() or batch_node_id == node_id:
 			var materialized := _materialize_batch(
-				graph, node_id, inputs.get("in", []), inputs.get("__metadata", []), asset_library
+				graph,
+				node_id,
+				inputs.get("in", []),
+				inputs.get("__metadata", []),
+				asset_library,
+				replace_batch_assets
 			)
 			if not bool(materialized["ok"]):
 				return materialized
@@ -71,7 +88,12 @@ func _run_node(
 
 
 func _materialize_batch(
-	graph: PFGraph, node_id: String, value: Variant, metadata: Variant, asset_library: Node
+	graph: PFGraph,
+	node_id: String,
+	value: Variant,
+	metadata: Variant,
+	asset_library: Node,
+	replace_batch_assets: bool
 ) -> Dictionary:
 	var images := _image_array(value)
 	if images.is_empty():
@@ -89,7 +111,7 @@ func _materialize_batch(
 		asset_ids.append(asset_id)
 
 	var params := graph.get_node_params(node_id)
-	var existing: Array = params.get("asset_ids", [])
+	var existing: Array = [] if replace_batch_assets else _string_array(params.get("asset_ids", []))
 	for asset_id in asset_ids:
 		existing.append(asset_id)
 	params["asset_ids"] = existing
@@ -209,6 +231,16 @@ func _metadata_array(value: Variant) -> Array:
 	return result
 
 
+func _string_array(value: Variant) -> Array:
+	var result := []
+	if value is Array:
+		for item in value:
+			var id := String(item)
+			if not id.is_empty():
+				result.append(id)
+	return result
+
+
 func _edge_node(edge: Dictionary, key: String) -> String:
 	var data: Array = edge.get(key, ["", ""])
 	return String(data[0])
diff --git a/pixel/tests/integration/test_graph_mock_runner.gd b/pixel/tests/integration/test_graph_mock_runner.gd
index a29d0f7..ca71790 100644
--- a/pixel/tests/integration/test_graph_mock_runner.gd
+++ b/pixel/tests/integration/test_graph_mock_runner.gd
@@ -33,6 +33,25 @@ func test_mock_generate_chain_materializes_images_into_batch_node() -> void:
 	assert_eq(meta["provenance"]["seed"], 700)
 
 
+func test_mock_generate_chain_can_replace_existing_batch_assets() -> void:
+	var graph := _make_mock_graph()
+	var asset_library := get_tree().root.get_node("AssetLibrary")
+	var runner := MockRunnerScript.new()
+
+	var first_result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1")
+	assert_true(bool(first_result["ok"]))
+	var first_ids: Array = graph.get_node_params("batch_1")["asset_ids"].duplicate()
+	assert_eq(first_ids.size(), 10)
+
+	var second_result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1", true)
+	assert_true(bool(second_result["ok"]))
+	var second_ids: Array = graph.get_node_params("batch_1")["asset_ids"]
+
+	assert_eq(second_result["asset_ids"].size(), 10)
+	assert_eq(second_ids.size(), 10)
+	assert_ne(second_ids, first_ids)
+
+
 func test_mock_generate_chain_survives_project_roundtrip_after_materialization() -> void:
 	var project_service := get_tree().root.get_node("ProjectService")
 	var asset_library := get_tree().root.get_node("AssetLibrary")
diff --git a/pixel/tests/smoke/test_main_window_ui.gd b/pixel/tests/smoke/test_main_window_ui.gd
index 2e30fa2..16b1d28 100644
--- a/pixel/tests/smoke/test_main_window_ui.gd
+++ b/pixel/tests/smoke/test_main_window_ui.gd
@@ -245,9 +245,30 @@ func test_mock_generate_menu_action_creates_visible_batch_and_graph() -> void:
 		assert_eq(canvas_item["type"], "node")
 		assert_eq(canvas_item["graph_id"], graph_id)
 
+	var batch_item_id := _item_id_for_node(canvas_items, "batch_1")
+	var first_asset_ids: Array = batch_node["params"]["asset_ids"].duplicate()
+	canvas.select_ids([batch_item_id])
+	controller.run_selected_mock_graph()
+	await wait_process_frames(2)
+
+	graph_data = ProjectService.current_project.graphs[graph_id]
+	batch_node = graph_data["nodes"][3]
+	var rerun_asset_ids: Array = batch_node["params"]["asset_ids"]
+	assert_eq(rerun_asset_ids.size(), 10)
+	assert_ne(rerun_asset_ids, first_asset_ids)
+	assert_eq(canvas._get_batch_asset_ids(batch_item_id), rerun_asset_ids)
+
 
 func _node_ids_from_canvas_items(items: Array) -> Array:
 	var node_ids := []
 	for item in items:
 		node_ids.append(String(Dictionary(item).get("node_id", "")))
 	return node_ids
+
+
+func _item_id_for_node(items: Array, node_id: String) -> String:
+	for item in items:
+		var data: Dictionary = item
+		if String(data.get("node_id", "")) == node_id:
+			return String(data.get("id", ""))
+	return ""
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index 58e6b2d..b39fd18 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -33,9 +33,10 @@ const FILE_MENU_BUTTON_WIDTH := 84
 const TOOL_BUTTON_SIZE := 84
 const FILE_MENU_IMPORT_IMAGES := 0
 const FILE_MENU_GENERATE_MOCK_BATCH := 1
-const FILE_MENU_NEW := 2
-const FILE_MENU_OPEN := 3
-const FILE_MENU_SAVE := 4
+const FILE_MENU_RUN_SELECTED_GRAPH := 2
+const FILE_MENU_NEW := 3
+const FILE_MENU_OPEN := 4
+const FILE_MENU_SAVE := 5
 const BATCH_MENU_CLEANUP := 0
 const BATCH_MENU_MATTE := 1
 const BATCH_MENU_OUTLINE := 2
@@ -92,6 +93,7 @@ func add_file_menu(parent: Control) -> void:
 	var popup := file_menu_button.get_popup()
 	popup.add_item(Strings.MENU_IMPORT_IMAGES, FILE_MENU_IMPORT_IMAGES)
 	popup.add_item(Strings.MENU_GENERATE_MOCK_BATCH, FILE_MENU_GENERATE_MOCK_BATCH)
+	popup.add_item(Strings.MENU_RUN_SELECTED_GRAPH, FILE_MENU_RUN_SELECTED_GRAPH)
 	popup.add_separator()
 	popup.add_item(Strings.ACTION_NEW, FILE_MENU_NEW)
 	popup.add_item(Strings.ACTION_OPEN, FILE_MENU_OPEN)
@@ -215,6 +217,42 @@ func generate_mock_batch() -> void:
 	_status_label.text = Strings.STATUS_MOCK_GENERATE_DONE % asset_ids.size()
 
 
+func run_selected_mock_graph() -> void:
+	var binding := _selected_graph_binding()
+	if binding.is_empty():
+		_status_label.text = Strings.STATUS_GRAPH_RUN_NEEDS_SELECTION
+		return
+
+	var graph_id := String(binding["graph_id"])
+	var graph_data := ProjectService.get_graph_data(graph_id)
+	if graph_data.is_empty():
+		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+		return
+
+	var graph := GraphScript.from_json(graph_data)
+	var batch_node_id := _first_batch_node_id(graph)
+	if batch_node_id.is_empty():
+		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+		return
+
+	var runner := GraphMockRunnerScript.new()
+	var result: Dictionary = runner.run_to_batch(graph, AssetLibrary, batch_node_id, true)
+	if not bool(result.get("ok", false)):
+		var error: Dictionary = result.get("error", {})
+		Log.warn("Selected mock graph run failed", error)
+		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+		return
+
+	var asset_ids: Array = result["asset_ids"]
+	var batch_card_id := _graph_batch_card_id(graph.id, batch_node_id)
+	ProjectService.set_graph_data(graph.id, graph.to_json(), true)
+	if batch_card_id.is_empty():
+		_status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+		return
+	_canvas._replace_batch_asset_ids(batch_card_id, asset_ids, true)
+	_status_label.text = Strings.STATUS_GRAPH_RUN_DONE % asset_ids.size()
+
+
 func show_onboarding_if_needed() -> void:
 	if DisplayServer.get_name() == "headless":
 		return
@@ -276,6 +314,8 @@ func _on_file_menu_pressed(id: int) -> void:
 			_import_dialog.popup_centered_ratio(0.7)
 		FILE_MENU_GENERATE_MOCK_BATCH:
 			generate_mock_batch()
+		FILE_MENU_RUN_SELECTED_GRAPH:
+			run_selected_mock_graph()
 		FILE_MENU_NEW:
 			_new_project_callback.call()
 		FILE_MENU_OPEN:
@@ -495,6 +535,39 @@ func _graph_node_position(graph: PFGraph, node_id: String) -> Vector2:
 	return Vector2(float(raw_position[0]), float(raw_position[1])).round()
 
 
+func _first_batch_node_id(graph: PFGraph) -> String:
+	for node_id in graph.nodes.keys():
+		var node: PFNode = graph.get_node(String(node_id))
+		if node != null and node.get_type() == "batch":
+			return String(node_id)
+	return ""
+
+
+func _selected_graph_binding() -> Dictionary:
+	var selected_ids: Array = _canvas.get_selected_ids()
+	for item in _canvas.export_canvas_data()["items"]:
+		var item_data: Dictionary = item
+		if not selected_ids.has(String(item_data.get("id", ""))):
+			continue
+		var graph_id := String(item_data.get("graph_id", ""))
+		var node_id := String(item_data.get("node_id", ""))
+		if graph_id.is_empty() or node_id.is_empty():
+			continue
+		return {"item_id": String(item_data["id"]), "graph_id": graph_id, "node_id": node_id}
+	return {}
+
+
+func _graph_batch_card_id(graph_id: String, batch_node_id: String) -> String:
+	for item in _canvas.export_canvas_data()["items"]:
+		var item_data: Dictionary = item
+		if (
+			String(item_data.get("graph_id", "")) == graph_id
+			and String(item_data.get("node_id", "")) == batch_node_id
+		):
+			return String(item_data.get("id", ""))
+	return ""
+
+
 func _show_onboarding_dialog() -> void:
 	var dialog: AcceptDialog = OnboardingScript.show_first_run_tips(self)
 	if dialog == null:
diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index 25d32a0..fa7475e 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -16,6 +16,7 @@ const ACTION_EXPORT_PNG := "Export PNG"
 const MENU_FILE := "File"
 const MENU_IMPORT_IMAGES := "Import Images..."
 const MENU_GENERATE_MOCK_BATCH := "Generate Mock Batch"
+const MENU_RUN_SELECTED_GRAPH := "Run Selected Graph"
 const STATUS_READY := "Ready"
 const STATUS_SAVED := "Saved"
 const STATUS_DIRTY := "Unsaved changes"
@@ -44,6 +45,9 @@ const STATUS_BATCH_SPLIT := "Batch subset created"
 const STATUS_BATCH_SPLIT_EMPTY := "Select thumbnails inside a batch before splitting"
 const STATUS_MOCK_GENERATE_DONE := "Mock batch generated: %d sprites"
 const STATUS_MOCK_GENERATE_FAILED := "Mock batch generation failed"
+const STATUS_GRAPH_RUN_DONE := "Graph run complete: %d sprites"
+const STATUS_GRAPH_RUN_FAILED := "Graph run failed"
+const STATUS_GRAPH_RUN_NEEDS_SELECTION := "Select a graph node or batch before running"
const CLEANUP_TITLE := "Pixel Cleanup"
const CLEANUP_SELECTED_FORMAT := "%d selected"
const CLEANUP_PRESET_PRIOR_FORMAT := "Preset prior: %dpx"
```

---

## 2026-06-18 M3 UX-5 批次审阅状态最小闭环

### 本轮实现说明

- 服务对象：一次生成或导入一批候选图后，需要快速挑出可用素材并拆成小批次继续处理的用户。
- 当前痛点：此前 batch 只有“临时勾选 + Split Selected”，没有 keep/reject/flag 语义；用户无法把筛选判断留在卡片上，也不能直接按 keep 集合收窄。
- 技术选择：在 `PFCanvasBatchCard` 增加 `review_states`（`asset_id -> keep|reject|flag`）与可视标记；右键菜单增加 Mark Keep / Mark Reject / Flag / Clear Mark / Split Kept；正式 graph batch 将状态写入 batch 节点 params，旧 `batch_card` 则继续随 canvas 数据保存。
- 选择原因：这是 UX-5 最小可用闭环，不引入完整过滤/评分系统，先让“看一批 -> 标记 -> 拆小批次”走通。
- 优势：review 状态可撤销、可保存/重载，Split Kept 不影响原批次；批处理/重跑替换 asset ids 时会过滤或清空旧 review 状态，避免标记错位。
- 缺陷：本轮还没有键盘上一张/下一张、只看 keep/reject/未定、焦点图模式；视觉标记也是原型级。
- 改进空间：后续可在 UX-5b 补键盘审阅节奏、过滤视图、焦点图；UX-6 可接 before/after 对比。

### 验证结果

| 项 | 结果 |
|---|---|
| `./pixel/scripts/lint.sh` | 通过，105 files unchanged，gdlint no problems |
| `./pixel/scripts/run_tests.sh` | 通过，137/137 tests passing，1133 asserts |
| `./pixel/scripts/verify_m3_ux5.sh` | 通过，含 lint / tests / `check_ui_scaling` / export-template headless gate / staged image check |
| staged 图片检查 | `git diff --cached --name-only \| grep -iE '\.(png\|jpe?g)$'` 无输出 |
| staged 保留目录检查 | `test picture/`、`pixel/tests/fixtures/real/`、`垃圾桶/`、`godot-interactive-guide/` 均未 staged |

备注：GUT 仍报告既有 `1 Orphans` 与退出时 resource leak warning，但测试总结果为 All tests passed；本轮未引入图片提交。

### 人工测试步骤

1. 打开工程，使用 `File > Generate Mock Batch` 生成一条 mock graph 与 Mock Batch。
2. 在 batch 卡内左键点选 2-3 张缩略图，右键 batch 卡，依次试 `Mark Keep`、`Mark Reject`、`Flag`、`Clear Mark`，确认缩略图出现/清除绿色条、红叉、黄色角标。
3. 标记至少 1 张 Keep 后右键选择 `Split Kept`，确认右侧生成一个只含 Keep 图的新 batch，原 batch 不减少。
4. 保存项目再重开，确认 graph batch 的 keep/reject/flag 标记仍在。
5. 对原 batch 执行 `Clean Batch` 或 `File > Run Selected Graph`，确认替换后的新资产不继承旧 asset id 的标记；撤销替换时旧标记恢复。

### DoD 核查

| 项 | 核查内容 | 状态 | 证据/路径 |
|---|---|---|---|
| 代码规范 | gdlint/gdformat 零告警 | 通过 | `./pixel/scripts/lint.sh` |
| 自动测试 | 卡内验收标准已转自动化并通过 | 通过 | `pixel/tests/unit/test_canvas_batch_card.gd` 新增 2 个 review-state 测试；`./pixel/scripts/run_tests.sh` 137/137 |
| 手动测试 | 标注手动项已执行或登记延期 | 延期登记 | 上方人工测试步骤待 owner 实机验证 |
| 契约同步 | 影响契约的改动已更新 `02-contracts/` | 通过 | `pixelforge-plan/02-contracts/GRAPH-SCHEMA.md` 补充 `review_states` |
| TODO | 一方代码无无主 `TODO/FIXME/HACK` | 通过 | 本轮未新增 TODO/FIXME/HACK |
| 性能预算 | 相关卡写入实测数字或明确延期 | 不适用 | UX-5 状态标记/拆分不涉及性能预算 |
| 跨平台 | 目标平台验证结果已记录 | 通过 | macOS headless 本地验证；export templates 缺失时按现有脚本退化为 headless startup gate |
| 出口门控 | CI 绿灯或本地 agent 验证绿灯 | 通过 | `./pixel/scripts/verify_m3_ux5.sh` |

### 本轮完整 diff（报告追加前）

```diff
diff --git a/pixel/scripts/verify_m3_ux5.sh b/pixel/scripts/verify_m3_ux5.sh
new file mode 100755
index 0000000..bc900a4
--- /dev/null
+++ b/pixel/scripts/verify_m3_ux5.sh
@@ -0,0 +1,17 @@
+#!/usr/bin/env bash
+set -euo pipefail
+
+cd "$(dirname "$0")/../.."
+
+./pixel/scripts/configure_editor_game_view.sh
+./pixel/scripts/lint.sh
+./pixel/scripts/run_tests.sh
+./pixel/scripts/check_ui_scaling.sh
+./pixel/scripts/check_export_templates.sh
+
+if git diff --cached --name-only | grep -iE '\.(png|jpe?g)$' >/dev/null; then
+  echo "Staged image files are not allowed for M3 UX-5 commits." >&2
+  exit 1
+fi
+
+echo "verify_m3_ux5: ok"
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index 913ef43..bc96991 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -1,6 +1,7 @@
 extends "res://addons/gut/test.gd"
 
 const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
+const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
 const GraphScript := preload("res://core/graph/pf_graph.gd")
 const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
 const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
@@ -37,6 +38,40 @@ func test_canvas_batch_card_exports_asset_queue_and_can_split_subset() -> void:
 	assert_eq(canvas.get_item_count(), 2)
 
 
+func test_canvas_batch_card_marks_review_state_and_splits_kept_subset() -> void:
+	var canvas: Control = CanvasScript.new()
+	canvas.size = Vector2(512, 512)
+	add_child_autofree(canvas)
+	await wait_process_frames(2)
+
+	var ids := [
+		_register_asset(Color.RED, "red"),
+		_register_asset(Color.BLUE, "blue"),
+		_register_asset(Color.GREEN, "green"),
+	]
+	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+
+	assert_eq(
+		canvas._set_batch_review_state(
+			"batch_1", [ids[0], ids[2]], CanvasBatchCardScript.REVIEW_KEEP, false
+		),
+		2
+	)
+	assert_eq(card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_KEEP), [ids[0], ids[2]])
+
+	var data: Dictionary = canvas.export_canvas_data()
+	var item: Dictionary = data["items"][0]
+	assert_eq(item["review_states"][ids[0]], CanvasBatchCardScript.REVIEW_KEEP)
+	assert_eq(item["review_states"][ids[2]], CanvasBatchCardScript.REVIEW_KEEP)
+
+	var child: Node = canvas._split_batch_marked(
+		"batch_1", CanvasBatchCardScript.REVIEW_KEEP, "keep"
+	)
+	assert_not_null(child)
+	assert_eq(child.asset_ids, [ids[0], ids[2]])
+	assert_eq(canvas.get_item_count(), 2)
+
+
 func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
 	var canvas: Control = CanvasScript.new()
 	canvas.size = Vector2(512, 512)
@@ -81,6 +116,48 @@ func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement()
 	assert_eq(reloaded_canvas._get_batch_asset_ids("node_item_1"), [green_id])
 
 
+func test_graph_batch_card_persists_review_state_in_graph_params() -> void:
+	var canvas: Control = CanvasScript.new()
+	canvas.size = Vector2(512, 512)
+	add_child_autofree(canvas)
+	await wait_process_frames(2)
+
+	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+	var graph := GraphScript.new()
+	graph.id = "graph_batch_review_test"
+	graph.add_node(
+		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+	)
+	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+	var card: Node = canvas._add_batch_card(
+		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+	)
+	assert_eq(
+		canvas._set_batch_review_state(
+			"node_item_1", [ids[1]], CanvasBatchCardScript.REVIEW_FLAG, false
+		),
+		1
+	)
+	assert_eq(card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])
+
+	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+	var batch_node: Dictionary = graph_data["nodes"][0]
+	assert_eq(batch_node["params"]["review_states"][ids[1]], CanvasBatchCardScript.REVIEW_FLAG)
+
+	var canvas_data: Dictionary = canvas.export_canvas_data()
+	assert_false(Dictionary(canvas_data["items"][0]).has("review_states"))
+
+	var reloaded_canvas: Control = CanvasScript.new()
+	reloaded_canvas.size = Vector2(512, 512)
+	add_child_autofree(reloaded_canvas)
+	await wait_process_frames(2)
+	reloaded_canvas.load_canvas_data(canvas_data)
+	var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]
+
+	assert_eq(reloaded_card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])
+
+
 func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
 	var canvas: Control = CanvasScript.new()
 	canvas.size = Vector2(512, 512)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 426b25d..176a229 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -19,6 +19,13 @@ const SELECTED_BORDER := Color(0.1, 0.85, 0.65, 1.0)
 const THUMB_BACKGROUND := Color(0.08, 0.085, 0.09, 1.0)
 const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
 const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
+const REVIEW_NONE := ""
+const REVIEW_KEEP := "keep"
+const REVIEW_REJECT := "reject"
+const REVIEW_FLAG := "flag"
+const KEEP_MARK := Color(0.2, 0.88, 0.46, 1.0)
+const REJECT_MARK := Color(0.95, 0.22, 0.24, 0.95)
+const FLAG_MARK := Color(1.0, 0.78, 0.18, 1.0)
 const INPUT_PORTS: Array[String] = ["in"]
 const OUTPUT_PORTS: Array[String] = ["images", "assets"]
 
@@ -27,6 +34,7 @@ var graph_id := ""
 var node_id := ""
 var asset_ids: Array[String] = []
 var selected_asset_ids: Array[String] = []
+var review_states := {}
 var label := ""
 var locked := false
 
@@ -43,6 +51,9 @@ func setup_from_data(data: Dictionary) -> void:
 	label = String(graph_params.get("label", data.get("label", "Batch")))
 	asset_ids = _string_array(graph_params.get("asset_ids", data.get("asset_ids", [])))
 	selected_asset_ids = _string_array(data.get("selected_asset_ids", []))
+	review_states = _review_state_map(
+		graph_params.get("review_states", data.get("review_states", {})), asset_ids
+	)
 	locked = bool(data.get("locked", false))
 	z_index = int(data.get("z_index", 0))
 	var raw_position: Variant = data.get("position", [0, 0])
@@ -69,6 +80,7 @@ func to_canvas_data() -> Dictionary:
 		"type": "batch_card",
 		"asset_ids": asset_ids.duplicate(),
 		"selected_asset_ids": selected_asset_ids.duplicate(),
+		"review_states": review_states.duplicate(true),
 		"label": label,
 		"position": [int(round(position.x)), int(round(position.y))],
 		"z_index": z_index,
@@ -104,16 +116,39 @@ func set_asset_ids(new_asset_ids: Array) -> void:
 	for selected_id in selected_asset_ids.duplicate():
 		if not asset_ids.has(selected_id):
 			selected_asset_ids.erase(selected_id)
+	review_states = _review_state_map(review_states, asset_ids)
 	_rebuild_thumbnails()
 	queue_redraw()
 
 
+func get_selected_asset_ids() -> Array[String]:
+	return selected_asset_ids.duplicate()
+
+
 func get_selected_or_all_asset_ids() -> Array[String]:
 	if selected_asset_ids.is_empty():
 		return asset_ids.duplicate()
 	return selected_asset_ids.duplicate()
 
 
+func get_marked_asset_ids(review_state: String) -> Array[String]:
+	var normalized_state := _normalize_review_state(review_state)
+	var result: Array[String] = []
+	for asset_id in asset_ids:
+		if String(review_states.get(asset_id, REVIEW_NONE)) == normalized_state:
+			result.append(asset_id)
+	return result
+
+
+func get_review_states() -> Dictionary:
+	return review_states.duplicate(true)
+
+
+func set_review_states(new_review_states: Dictionary) -> void:
+	review_states = _review_state_map(new_review_states, asset_ids)
+	queue_redraw()
+
+
 func toggle_asset_at_world(world_position: Vector2) -> bool:
 	var index := asset_index_at_world(world_position)
 	if index < 0 or index >= asset_ids.size():
@@ -177,6 +212,32 @@ func _draw_thumbnail(index: int, rect: Rect2) -> void:
 		draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)
 	var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
 	draw_rect(rect, border_color, false, 1.5)
+	_draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
+
+
+func _draw_review_marker(rect: Rect2, review_state: String) -> void:
+	match _normalize_review_state(review_state):
+		REVIEW_KEEP:
+			draw_rect(Rect2(rect.position, Vector2(7.0, rect.size.y)), KEEP_MARK, true)
+		REVIEW_REJECT:
+			draw_line(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8), REJECT_MARK, 4.0)
+			draw_line(
+				Vector2(rect.end.x - 8, rect.position.y + 8),
+				Vector2(rect.position.x + 8, rect.end.y - 8),
+				REJECT_MARK,
+				4.0
+			)
+		REVIEW_FLAG:
+			draw_colored_polygon(
+				PackedVector2Array(
+					[
+						rect.position + Vector2(rect.size.x - 30.0, 0.0),
+						rect.position + Vector2(rect.size.x, 0.0),
+						rect.position + Vector2(rect.size.x, 30.0),
+					]
+				),
+				FLAG_MARK
+			)
 
 
 func _thumb_rect(index: int, columns: int) -> Rect2:
@@ -259,3 +320,29 @@ func _string_array(value: Variant) -> Array[String]:
 		for item in Array(value):
 			result.append(String(item))
 	return result
+
+
+func _review_state_map(value: Variant, valid_asset_ids: Array[String]) -> Dictionary:
+	var result := {}
+	if not (value is Dictionary):
+		return result
+	var valid_lookup := {}
+	for asset_id in valid_asset_ids:
+		valid_lookup[asset_id] = true
+	var raw_states: Dictionary = value
+	for key in raw_states.keys():
+		var asset_id := String(key)
+		if not valid_lookup.has(asset_id):
+			continue
+		var review_state := _normalize_review_state(String(raw_states[key]))
+		if not review_state.is_empty():
+			result[asset_id] = review_state
+	return result
+
+
+func _normalize_review_state(review_state: String) -> String:
+	match review_state:
+		REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
+			return review_state
+		_:
+			return REVIEW_NONE
diff --git a/pixel/ui/canvas/canvas_batch_ops.gd b/pixel/ui/canvas/canvas_batch_ops.gd
new file mode 100644
index 0000000..99403b0
--- /dev/null
+++ b/pixel/ui/canvas/canvas_batch_ops.gd
@@ -0,0 +1,175 @@
+class_name PFCanvasBatchOps
+extends RefCounted
+
+## Batch-card operations that would otherwise bloat PFInfiniteCanvas.
+
+const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
+const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
+
+const SPLIT_GAP := 24.0
+
+
+static func get_asset_ids(
+	items_by_id: Dictionary, card_id: String, selected_only: bool = false
+) -> Array:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return []
+	if selected_only:
+		return item.get_selected_or_all_asset_ids()
+	return item.asset_ids.duplicate()
+
+
+static func get_selected_asset_ids(items_by_id: Dictionary, card_id: String) -> Array:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return []
+	return item.get_selected_asset_ids()
+
+
+static func get_marked_asset_ids(
+	items_by_id: Dictionary, card_id: String, review_state: String
+) -> Array:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return []
+	return item.get_marked_asset_ids(review_state)
+
+
+static func replace_asset_ids(
+	items_by_id: Dictionary,
+	card_id: String,
+	new_asset_ids: Array,
+	record_undo: bool,
+	select_only: Callable,
+	emit_changed: Callable
+) -> void:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return
+	var before: Array = item.asset_ids.duplicate()
+	var before_review_states: Dictionary = item.get_review_states()
+	var after := new_asset_ids.duplicate()
+	var after_review_states := {}
+	var do_replace := func() -> void:
+		GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
+		_apply_review_states(item, after_review_states)
+		GraphItemBridge.sync_batch_node_asset_ids(item, after)
+		GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
+		select_only.call([card_id])
+		emit_changed.call()
+	var undo_replace := func() -> void:
+		GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
+		_apply_review_states(item, before_review_states)
+		GraphItemBridge.sync_batch_node_asset_ids(item, before)
+		GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
+		select_only.call([card_id])
+		emit_changed.call()
+	if record_undo:
+		UndoService.perform_action("Replace batch assets", do_replace, undo_replace)
+	else:
+		do_replace.call()
+
+
+static func set_review_state(
+	items_by_id: Dictionary,
+	card_id: String,
+	asset_ids: Array,
+	review_state: String,
+	record_undo: bool,
+	select_only: Callable,
+	emit_changed: Callable
+) -> int:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return 0
+	var target_ids := _valid_target_ids(item, asset_ids)
+	if target_ids.is_empty():
+		return 0
+
+	var before: Dictionary = item.get_review_states()
+	var after := before.duplicate(true)
+	var normalized_state := _normalize_review_state(review_state)
+	for asset_id in target_ids:
+		if normalized_state.is_empty():
+			after.erase(asset_id)
+		else:
+			after[asset_id] = normalized_state
+
+	var do_mark := func() -> void:
+		_apply_review_states(item, after)
+		GraphItemBridge.sync_batch_node_review_states(item, after)
+		select_only.call([card_id])
+		emit_changed.call()
+	var undo_mark := func() -> void:
+		_apply_review_states(item, before)
+		GraphItemBridge.sync_batch_node_review_states(item, before)
+		select_only.call([card_id])
+		emit_changed.call()
+
+	if record_undo:
+		UndoService.perform_action("Mark batch review state", do_mark, undo_mark)
+	else:
+		do_mark.call()
+	return target_ids.size()
+
+
+static func split_selection_spec(items_by_id: Dictionary, card_id: String) -> Dictionary:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return {}
+	return _split_spec(item, item.get_selected_or_all_asset_ids(), "subset")
+
+
+static func split_marked_spec(
+	items_by_id: Dictionary, card_id: String, review_state: String, label_suffix: String
+) -> Dictionary:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return {}
+	return _split_spec(item, item.get_marked_asset_ids(review_state), label_suffix)
+
+
+static func _batch_item(items_by_id: Dictionary, card_id: String) -> Node:
+	if not items_by_id.has(card_id):
+		return null
+	var item: Node = items_by_id[card_id]
+	if item.get_script() != CanvasBatchCardScript:
+		return null
+	return item
+
+
+static func _valid_target_ids(item: Node, asset_ids: Array) -> Array:
+	var result := []
+	for raw_id in asset_ids:
+		var asset_id := String(raw_id)
+		if item.asset_ids.has(asset_id) and not result.has(asset_id):
+			result.append(asset_id)
+	return result
+
+
+static func _split_spec(item: Node, subset: Array, label_suffix: String) -> Dictionary:
+	if subset.is_empty() or subset.size() == item.asset_ids.size():
+		return {}
+	return {
+		"asset_ids": subset,
+		"position": item.position + Vector2(item.get_canvas_bounds().size.x + SPLIT_GAP, 0.0),
+		"label": "%s %s" % [item.label, label_suffix],
+	}
+
+
+static func _apply_review_states(item: Node, review_states: Dictionary) -> void:
+	item.set_review_states(review_states)
+
+
+static func _normalize_review_state(review_state: String) -> String:
+	if (
+		review_state
+		in [
+			CanvasBatchCardScript.REVIEW_KEEP,
+			CanvasBatchCardScript.REVIEW_REJECT,
+			CanvasBatchCardScript.REVIEW_FLAG,
+		]
+	):
+		return review_state
+	return CanvasBatchCardScript.REVIEW_NONE
diff --git a/pixel/ui/canvas/canvas_batch_ops.gd.uid b/pixel/ui/canvas/canvas_batch_ops.gd.uid
new file mode 100644
index 0000000..dbe60e0
--- /dev/null
+++ b/pixel/ui/canvas/canvas_batch_ops.gd.uid
@@ -0,0 +1 @@
+uid://wabtp0ptq26k
diff --git a/pixel/ui/canvas/canvas_graph_item_bridge.gd b/pixel/ui/canvas/canvas_graph_item_bridge.gd
index 9cbd4de..5371ed5 100644
--- a/pixel/ui/canvas/canvas_graph_item_bridge.gd
+++ b/pixel/ui/canvas/canvas_graph_item_bridge.gd
@@ -52,6 +52,37 @@ static func sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
 		):
 			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
 			params["asset_ids"] = _string_array(asset_ids)
+			params["review_states"] = _review_state_map(params.get("review_states", {}), asset_ids)
+			node_data["params"] = params
+			changed = true
+		nodes.append(node_data)
+
+	if changed:
+		graph_data["nodes"] = nodes
+		ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
+static func sync_batch_node_review_states(item: Node, review_states: Dictionary) -> void:
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
+			params["review_states"] = _review_state_map(review_states, params.get("asset_ids", []))
 			node_data["params"] = params
 			changed = true
 		nodes.append(node_data)
@@ -69,3 +100,21 @@ static func _string_array(value: Variant) -> Array[String]:
 			if not id.is_empty():
 				result.append(id)
 	return result
+
+
+static func _review_state_map(value: Variant, valid_asset_ids: Variant) -> Dictionary:
+	var result := {}
+	if not (value is Dictionary):
+		return result
+	var valid_lookup := {}
+	for asset_id in _string_array(valid_asset_ids):
+		valid_lookup[asset_id] = true
+	var raw_states: Dictionary = value
+	for key in raw_states.keys():
+		var asset_id := String(key)
+		if not valid_lookup.has(asset_id):
+			continue
+		var review_state := String(raw_states[key])
+		if review_state in ["keep", "reject", "flag"]:
+			result[asset_id] = review_state
+	return result
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 10ef29b..0a76239 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -25,6 +25,7 @@ const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
 const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
 const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
 const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
+const BatchOps := preload("res://ui/canvas/canvas_batch_ops.gd")
 const CanvasCleanupPreviewScript := preload("res://ui/canvas/canvas_cleanup_preview.gd")
 const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")
 const ScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
@@ -480,58 +481,53 @@ func _get_active_tool_target() -> Dictionary:
 
 
 func _get_batch_asset_ids(card_id: String, selected_only: bool = false) -> Array:
-	if not _items_by_id.has(card_id):
-		return []
-	var item: Node = _items_by_id[card_id]
-	if item.get_script() != CanvasBatchCardScript:
-		return []
-	if selected_only:
-		return item.get_selected_or_all_asset_ids()
-	return item.asset_ids.duplicate()
+	return BatchOps.get_asset_ids(_items_by_id, card_id, selected_only)
+
+
+func _get_batch_selected_asset_ids(card_id: String) -> Array:
+	return BatchOps.get_selected_asset_ids(_items_by_id, card_id)
+
+
+func _get_batch_marked_asset_ids(card_id: String, review_state: String) -> Array:
+	return BatchOps.get_marked_asset_ids(_items_by_id, card_id, review_state)
 
 
 func _replace_batch_asset_ids(
 	card_id: String, new_asset_ids: Array, record_undo: bool = true
 ) -> void:
-	if not _items_by_id.has(card_id):
-		return
-	var item: Node = _items_by_id[card_id]
-	if item.get_script() != CanvasBatchCardScript:
-		return
-	var before: Array = item.asset_ids.duplicate()
-	var after := new_asset_ids.duplicate()
-	var do_replace := func() -> void:
-		GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
-		GraphItemBridge.sync_batch_node_asset_ids(item, after)
-		_select_only([card_id])
-		_emit_canvas_changed()
-	var undo_replace := func() -> void:
-		GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
-		GraphItemBridge.sync_batch_node_asset_ids(item, before)
-		_select_only([card_id])
-		_emit_canvas_changed()
-	if record_undo:
-		UndoService.perform_action("Replace batch assets", do_replace, undo_replace)
-	else:
-		do_replace.call()
+	BatchOps.replace_asset_ids(
+		_items_by_id, card_id, new_asset_ids, record_undo, _select_only, _emit_canvas_changed
+	)
+
+
+func _set_batch_review_state(
+	card_id: String, asset_ids: Array, review_state: String, record_undo: bool = true
+) -> int:
+	return BatchOps.set_review_state(
+		_items_by_id,
+		card_id,
+		asset_ids,
+		review_state,
+		record_undo,
+		_select_only,
+		_emit_canvas_changed
+	)
 
 
 func _split_batch_selection(card_id: String) -> Node:
-	if not _items_by_id.has(card_id):
-		return null
-	var item: Node = _items_by_id[card_id]
-	if item.get_script() != CanvasBatchCardScript:
+	var spec: Dictionary = BatchOps.split_selection_spec(_items_by_id, card_id)
+	if spec.is_empty():
 		return null
-	var subset: Array = item.get_selected_or_all_asset_ids()
-	if subset.is_empty() or subset.size() == item.asset_ids.size():
-		return null
-	return _add_batch_card(
-		subset,
-		item.position + Vector2(item.get_canvas_bounds().size.x + 24.0, 0.0),
-		"%s subset" % item.label,
-		"",
-		true
+	return _add_batch_card(spec["asset_ids"], spec["position"], spec["label"], "", true)
+
+
+func _split_batch_marked(card_id: String, review_state: String, label_suffix: String) -> Node:
+	var spec: Dictionary = BatchOps.split_marked_spec(
+		_items_by_id, card_id, review_state, label_suffix
 	)
+	if spec.is_empty():
+		return null
+	return _add_batch_card(spec["asset_ids"], spec["position"], spec["label"], "", true)
 
 
 func show_cleanup_preview(
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index b39fd18..fd0cf59 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -24,6 +24,7 @@ const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.g
 const ObjectListNodeScript := preload("res://core/graph/nodes/object_list_node.gd")
 const SizeSpecNodeScript := preload("res://core/graph/nodes/size_spec_node.gd")
 const GraphMockRunnerScript := preload("res://services/graph_mock_runner.gd")
+const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
 const IdUtil := preload("res://core/util/id_util.gd")
 const Log := preload("res://core/util/log_util.gd")
 
@@ -42,6 +43,11 @@ const BATCH_MENU_MATTE := 1
 const BATCH_MENU_OUTLINE := 2
 const BATCH_MENU_SPLIT := 3
 const BATCH_MENU_EXPORT := 4
+const BATCH_MENU_MARK_KEEP := 5
+const BATCH_MENU_MARK_REJECT := 6
+const BATCH_MENU_MARK_FLAG := 7
+const BATCH_MENU_CLEAR_MARK := 8
+const BATCH_MENU_SPLIT_KEEP := 9
 const SELECTION_TOOLS_VISIBLE := false
 
 var _canvas: Control = null
@@ -292,7 +298,14 @@ func _create_batch_menu() -> void:
 	_batch_menu.add_item(Strings.BATCH_ACTION_MATTE, BATCH_MENU_MATTE)
 	_batch_menu.add_item(Strings.BATCH_ACTION_OUTLINE, BATCH_MENU_OUTLINE)
 	_batch_menu.add_separator()
+	_batch_menu.add_item(Strings.BATCH_ACTION_MARK_KEEP, BATCH_MENU_MARK_KEEP)
+	_batch_menu.add_item(Strings.BATCH_ACTION_MARK_REJECT, BATCH_MENU_MARK_REJECT)
+	_batch_menu.add_item(Strings.BATCH_ACTION_MARK_FLAG, BATCH_MENU_MARK_FLAG)
+	_batch_menu.add_item(Strings.BATCH_ACTION_CLEAR_MARK, BATCH_MENU_CLEAR_MARK)
+	_batch_menu.add_separator()
+	_batch_menu.add_item(Strings.BATCH_ACTION_SPLIT_KEEP, BATCH_MENU_SPLIT_KEEP)
 	_batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
+	_batch_menu.add_separator()
 	_batch_menu.add_item(Strings.BATCH_ACTION_EXPORT, BATCH_MENU_EXPORT)
 	_batch_menu.id_pressed.connect(_on_batch_menu_id_pressed)
 	add_child(_batch_menu)
@@ -395,6 +408,33 @@ func _on_batch_menu_id_pressed(id: int) -> void:
 			_m2_actions.batch_outline(
 				_batch_menu_card_id, asset_ids, {"type": "outer", "color": Color.BLACK}
 			)
+		BATCH_MENU_MARK_KEEP:
+			_mark_batch_review_state(
+				CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_MARK_KEEP
+			)
+		BATCH_MENU_MARK_REJECT:
+			_mark_batch_review_state(
+				CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_MARK_REJECT
+			)
+		BATCH_MENU_MARK_FLAG:
+			_mark_batch_review_state(
+				CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_MARK_FLAG
+			)
+		BATCH_MENU_CLEAR_MARK:
+			_mark_batch_review_state(
+				CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
+			)
+		BATCH_MENU_SPLIT_KEEP:
+			var new_keep_card: Variant = _canvas._split_batch_marked(
+				_batch_menu_card_id,
+				CanvasBatchCardScript.REVIEW_KEEP,
+				Strings.BATCH_KEEP_LABEL_SUFFIX
+			)
+			_status_label.text = (
+				Strings.STATUS_BATCH_SPLIT_KEEP
+				if new_keep_card != null
+				else Strings.STATUS_BATCH_SPLIT_KEEP_EMPTY
+			)
 		BATCH_MENU_SPLIT:
 			var new_card: Variant = _canvas._split_batch_selection(_batch_menu_card_id)
 			_status_label.text = (
@@ -404,6 +444,20 @@ func _on_batch_menu_id_pressed(id: int) -> void:
 			_emit_batch_export(asset_ids)
 
 
+func _mark_batch_review_state(review_state: String, status_format: String) -> void:
+	var selected_ids: Array = _canvas._get_batch_selected_asset_ids(_batch_menu_card_id)
+	if selected_ids.is_empty():
+		_status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
+		return
+	var marked_count: int = _canvas._set_batch_review_state(
+		_batch_menu_card_id, selected_ids, review_state, true
+	)
+	if marked_count <= 0:
+		_status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
+		return
+	_status_label.text = status_format % marked_count
+
+
 func _emit_batch_export(asset_ids: Array) -> void:
 	var snapshots := []
 	for asset_id in asset_ids:
diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index fa7475e..115cf3a 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -43,6 +43,13 @@ const ZOOM_CONTROL_TOOLTIP := "Canvas zoom"
 const STATUS_BATCH_NEEDS_SELECTION := "Select two or more sprites to make a batch"
 const STATUS_BATCH_SPLIT := "Batch subset created"
 const STATUS_BATCH_SPLIT_EMPTY := "Select thumbnails inside a batch before splitting"
+const STATUS_BATCH_SPLIT_KEEP := "Kept subset created"
+const STATUS_BATCH_SPLIT_KEEP_EMPTY := "Mark at least one kept thumbnail before splitting"
+const STATUS_BATCH_MARK_NEEDS_SELECTION := "Select thumbnails inside a batch before marking"
+const STATUS_BATCH_MARK_KEEP := "%d thumbnails marked keep"
+const STATUS_BATCH_MARK_REJECT := "%d thumbnails marked reject"
+const STATUS_BATCH_MARK_FLAG := "%d thumbnails flagged"
+const STATUS_BATCH_MARK_CLEAR := "%d thumbnail marks cleared"
 const STATUS_MOCK_GENERATE_DONE := "Mock batch generated: %d sprites"
 const STATUS_MOCK_GENERATE_FAILED := "Mock batch generation failed"
 const STATUS_GRAPH_RUN_DONE := "Graph run complete: %d sprites"
@@ -130,9 +137,15 @@ const BATCH_ACTION_CLEANUP := "Clean Batch"
 const BATCH_ACTION_MATTE := "Matte Batch"
 const BATCH_ACTION_OUTLINE := "Outline Batch"
 const BATCH_ACTION_QUANTIZE := "Quantize Batch"
+const BATCH_ACTION_MARK_KEEP := "Mark Keep"
+const BATCH_ACTION_MARK_REJECT := "Mark Reject"
+const BATCH_ACTION_MARK_FLAG := "Flag"
+const BATCH_ACTION_CLEAR_MARK := "Clear Mark"
+const BATCH_ACTION_SPLIT_KEEP := "Split Kept"
 const BATCH_ACTION_SPLIT := "Split Selected"
 const BATCH_ACTION_EXPORT := "Export Batch"
 const BATCH_ACTION_SEND_TO_EDITOR := "Send to Editor"
+const BATCH_KEEP_LABEL_SUFFIX := "keep"
 const GRAPH_PARAM_OBJECT_LIST := "Objects"
 const GRAPH_PARAM_WIDTH := "Width"
 const GRAPH_PARAM_HEIGHT := "Height"
diff --git a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
index 5018177..529975e 100644
--- a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
+++ b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
@@ -127,7 +127,7 @@ func get_canvas_actions() -> Array[Dictionary]
 新概念，本模型的核心。装一个批次的图片队列，是「AI 输出自由」与「批量加工」的落脚点。
 
 - **双身份**：① 图节点（`type=batch`，`category=container`，`is_canvas_resident()=true`）；② 画布卡（PROJECT-FORMAT canvas.json 的 `node` 引用，特化渲染为容器卡）。
-- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
+- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），随 `asset_ids` 过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
 - **整批菜单**（`get_canvas_actions()` 声明，边框弹出）：整批清洗 / 整批抠图 / 整批描边 / 整批量化 / 导出整批 / 拆小批次 / 逐张发送到编辑器。均调 core，记 undo + provenance（§4.7）。
 - **拆小批次**：勾选子集 → 生成子 `batch`（新卡，引用子集 asset_id），可独立处理；复用 `select` 语义。
 - **分离单图**：把某张拖出批次卡 → 成为独立 sprite 卡（仍在同一画布，见 PROJECT-FORMAT §4 `sprite`）。
```

---

## 2026-06-18 M3 UX-5 批次审阅过滤最小闭环

### 本轮实现说明

- 服务对象：已经给 batch 缩略图标记 keep/reject/flag 后，需要快速只看保留项、未定项或废弃项继续筛选的人。
- 当前痛点：上一轮已经能标记和 Split Kept，但所有缩略图仍混在一起；50 张候选中想复查保留/未定项仍要靠肉眼找标记。
- 技术选择：在 batch 审阅状态中新增 `review_filter`，取值 `all|pending|keep|reject|flag`；batch 卡绘制、缩略图命中、默认批处理/导出范围都基于当前可见集合；右键菜单增加 Show All / Show Keep / Show Pending / Show Reject / Show Flagged。
- 选择原因：这是 UX-5 “只看保留/只看未定/只看 reject” 的最小实现，不引入完整焦点图和键盘审阅系统，先让收窄流程可用。
- 优势：过滤状态可保存/重载；正式 graph batch 写入 batch 节点 params，旧 `batch_card` 写入 canvas；当前过滤下未显式选择时，Clean/Matte/Outline/Export 默认只作用于可见集合，减少误处理隐藏项。
- 缺陷：本轮仍未实现上一张/下一张焦点审阅，也没有过滤菜单勾选态；空过滤结果仅显示空卡片，没有专门 empty-state 文案。
- 改进空间：后续可补焦点图、键盘 K/R/F 标记、过滤快捷键、菜单 checkmark，以及 UX-6 before/after A/B 过滤联动。

### 验证结果

| 项 | 结果 |
|---|---|
| `./pixel/scripts/lint.sh` | 通过，105 files unchanged，gdlint no problems |
| `./pixel/scripts/run_tests.sh` | 通过，139/139 tests passing，1147 asserts |
| `./pixel/scripts/verify_m3_ux5.sh` | 通过，含 lint / tests / `check_ui_scaling` / export-template headless gate / staged image check |
| staged 图片检查 | `git diff --cached --name-only \| grep -iE '\.(png\|jpe?g)$'` 无输出 |
| staged 保留目录检查 | `test picture/`、`pixel/tests/fixtures/real/`、`垃圾桶/`、`godot-interactive-guide/` 均未 staged |

备注：GUT 仍报告既有 `1 Orphans` 与退出时 resource leak warning，但测试总结果为 All tests passed；本轮未引入图片提交。

### 人工测试步骤

1. 打开工程，使用 `File > Generate Mock Batch` 生成 Mock Batch。
2. 点选若干缩略图，右键 batch 卡分别执行 `Mark Keep`、`Mark Reject`、`Flag`。
3. 右键 batch 卡依次切换 `Show Keep`、`Show Pending`、`Show Reject`、`Show Flagged`、`Show All`，确认卡片只显示对应集合，标题计数显示为 `可见/总数`。
4. 在 `Show Pending` 或 `Show Keep` 下点选缩略图，确认只会选中当前可见项；右键 `Export Batch` 或 `Clean Batch` 时默认只处理当前可见集合（可用少量 mock 图观察数量变化）。
5. 保存项目再重开，确认 graph batch 的过滤状态仍在；执行 `File > Run Selected Graph` 重跑后，确认新结果回到 Show All，不被旧过滤器藏起来。

### DoD 核查

| 项 | 核查内容 | 状态 | 证据/路径 |
|---|---|---|---|
| 代码规范 | gdlint/gdformat 零告警 | 通过 | `./pixel/scripts/lint.sh` |
| 自动测试 | 卡内验收标准已转自动化并通过 | 通过 | `pixel/tests/unit/test_canvas_batch_card.gd` 新增 2 个 filter 测试；`./pixel/scripts/run_tests.sh` 139/139 |
| 手动测试 | 标注手动项已执行或登记延期 | 延期登记 | 上方人工测试步骤待 owner 实机验证 |
| 契约同步 | 影响契约的改动已更新 `02-contracts/` | 通过 | `GRAPH-SCHEMA.md` 补 `review_filter`；`PROJECT-FORMAT.md` 补旧 `batch_card` 示例字段 |
| TODO | 一方代码无无主 `TODO/FIXME/HACK` | 通过 | 本轮未新增 TODO/FIXME/HACK |
| 性能预算 | 相关卡写入实测数字或明确延期 | 不适用 | UX-5 filter 仅影响 batch 卡局部列表/绘制 |
| 跨平台 | 目标平台验证结果已记录 | 通过 | macOS headless 本地验证；export templates 缺失时按现有脚本退化为 headless startup gate |
| 出口门控 | CI 绿灯或本地 agent 验证绿灯 | 通过 | `./pixel/scripts/verify_m3_ux5.sh` |

### 本轮完整 diff（报告追加前）

```diff
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index bc96991..5103402 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -72,6 +72,39 @@ func test_canvas_batch_card_marks_review_state_and_splits_kept_subset() -> void:
 	assert_eq(canvas.get_item_count(), 2)
 
 
+func test_canvas_batch_card_filters_visible_review_subset() -> void:
+	var canvas: Control = CanvasScript.new()
+	canvas.size = Vector2(512, 512)
+	add_child_autofree(canvas)
+	await wait_process_frames(2)
+
+	var ids := [
+		_register_asset(Color.RED, "red"),
+		_register_asset(Color.BLUE, "blue"),
+		_register_asset(Color.GREEN, "green"),
+	]
+	var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+	canvas._set_batch_review_state("batch_1", [ids[0]], CanvasBatchCardScript.REVIEW_KEEP, false)
+	canvas._set_batch_review_state("batch_1", [ids[1]], CanvasBatchCardScript.REVIEW_REJECT, false)
+
+	assert_true(
+		canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.REVIEW_KEEP, false)
+	)
+	assert_eq(card.get_visible_asset_ids(), [ids[0]])
+	assert_eq(canvas._get_batch_asset_ids("batch_1", true), [ids[0]])
+
+	assert_true(
+		canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.FILTER_PENDING, false)
+	)
+	assert_eq(card.get_visible_asset_ids(), [ids[2]])
+	assert_true(card.toggle_asset_at_world(card.position + Vector2(20, 60)))
+	assert_eq(card.get_selected_asset_ids(), [ids[2]])
+
+	var data: Dictionary = canvas.export_canvas_data()
+	var item: Dictionary = data["items"][0]
+	assert_eq(item["review_filter"], CanvasBatchCardScript.FILTER_PENDING)
+
+
 func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
 	var canvas: Control = CanvasScript.new()
 	canvas.size = Vector2(512, 512)
@@ -158,6 +191,49 @@ func test_graph_batch_card_persists_review_state_in_graph_params() -> void:
 	assert_eq(reloaded_card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])
 
 
+func test_graph_batch_card_persists_review_filter_in_graph_params() -> void:
+	var canvas: Control = CanvasScript.new()
+	canvas.size = Vector2(512, 512)
+	add_child_autofree(canvas)
+	await wait_process_frames(2)
+
+	var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+	var graph := GraphScript.new()
+	graph.id = "graph_batch_filter_test"
+	graph.add_node(
+		BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+	)
+	ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+	var card: Node = canvas._add_batch_card(
+		ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+	)
+	canvas._set_batch_review_state(
+		"node_item_1", [ids[1]], CanvasBatchCardScript.REVIEW_FLAG, false
+	)
+	assert_true(
+		canvas._set_batch_review_filter("node_item_1", CanvasBatchCardScript.REVIEW_FLAG, false)
+	)
+	assert_eq(card.get_visible_asset_ids(), [ids[1]])
+
+	var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+	var batch_node: Dictionary = graph_data["nodes"][0]
+	assert_eq(batch_node["params"]["review_filter"], CanvasBatchCardScript.REVIEW_FLAG)
+
+	var canvas_data: Dictionary = canvas.export_canvas_data()
+	assert_false(Dictionary(canvas_data["items"][0]).has("review_filter"))
+
+	var reloaded_canvas: Control = CanvasScript.new()
+	reloaded_canvas.size = Vector2(512, 512)
+	add_child_autofree(reloaded_canvas)
+	await wait_process_frames(2)
+	reloaded_canvas.load_canvas_data(canvas_data)
+	var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]
+
+	assert_eq(reloaded_card.get_review_filter(), CanvasBatchCardScript.REVIEW_FLAG)
+	assert_eq(reloaded_card.get_visible_asset_ids(), [ids[1]])
+
+
 func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
 	var canvas: Control = CanvasScript.new()
 	canvas.size = Vector2(512, 512)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 176a229..793f7d4 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -23,6 +23,8 @@ const REVIEW_NONE := ""
 const REVIEW_KEEP := "keep"
 const REVIEW_REJECT := "reject"
 const REVIEW_FLAG := "flag"
+const FILTER_ALL := "all"
+const FILTER_PENDING := "pending"
 const KEEP_MARK := Color(0.2, 0.88, 0.46, 1.0)
 const REJECT_MARK := Color(0.95, 0.22, 0.24, 0.95)
 const FLAG_MARK := Color(1.0, 0.78, 0.18, 1.0)
@@ -35,6 +37,7 @@ var node_id := ""
 var asset_ids: Array[String] = []
 var selected_asset_ids: Array[String] = []
 var review_states := {}
+var review_filter := FILTER_ALL
 var label := ""
 var locked := false
 
@@ -54,6 +57,10 @@ func setup_from_data(data: Dictionary) -> void:
 	review_states = _review_state_map(
 		graph_params.get("review_states", data.get("review_states", {})), asset_ids
 	)
+	review_filter = _normalize_review_filter(
+		String(graph_params.get("review_filter", data.get("review_filter", FILTER_ALL)))
+	)
+	_prune_selected_to_visible()
 	locked = bool(data.get("locked", false))
 	z_index = int(data.get("z_index", 0))
 	var raw_position: Variant = data.get("position", [0, 0])
@@ -81,6 +88,7 @@ func to_canvas_data() -> Dictionary:
 		"asset_ids": asset_ids.duplicate(),
 		"selected_asset_ids": selected_asset_ids.duplicate(),
 		"review_states": review_states.duplicate(true),
+		"review_filter": review_filter,
 		"label": label,
 		"position": [int(round(position.x)), int(round(position.y))],
 		"z_index": z_index,
@@ -117,18 +125,30 @@ func set_asset_ids(new_asset_ids: Array) -> void:
 		if not asset_ids.has(selected_id):
 			selected_asset_ids.erase(selected_id)
 	review_states = _review_state_map(review_states, asset_ids)
+	_prune_selected_to_visible()
 	_rebuild_thumbnails()
 	queue_redraw()
 
 
 func get_selected_asset_ids() -> Array[String]:
-	return selected_asset_ids.duplicate()
+	var visible_lookup := _visible_lookup()
+	var result: Array[String] = []
+	for asset_id in selected_asset_ids:
+		if visible_lookup.has(asset_id):
+			result.append(asset_id)
+	return result
 
 
 func get_selected_or_all_asset_ids() -> Array[String]:
+	var visible_ids := get_visible_asset_ids()
 	if selected_asset_ids.is_empty():
-		return asset_ids.duplicate()
-	return selected_asset_ids.duplicate()
+		return visible_ids
+	var visible_lookup := _lookup(visible_ids)
+	var result: Array[String] = []
+	for selected_id in selected_asset_ids:
+		if visible_lookup.has(selected_id):
+			result.append(selected_id)
+	return result
 
 
 func get_marked_asset_ids(review_state: String) -> Array[String]:
@@ -140,20 +160,48 @@ func get_marked_asset_ids(review_state: String) -> Array[String]:
 	return result
 
 
+func get_visible_asset_ids() -> Array[String]:
+	var result: Array[String] = []
+	match review_filter:
+		FILTER_ALL:
+			return asset_ids.duplicate()
+		FILTER_PENDING:
+			for asset_id in asset_ids:
+				if not review_states.has(asset_id):
+					result.append(asset_id)
+		REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
+			for asset_id in asset_ids:
+				if String(review_states.get(asset_id, REVIEW_NONE)) == review_filter:
+					result.append(asset_id)
+	return result
+
+
 func get_review_states() -> Dictionary:
 	return review_states.duplicate(true)
 
 
 func set_review_states(new_review_states: Dictionary) -> void:
 	review_states = _review_state_map(new_review_states, asset_ids)
+	_prune_selected_to_visible()
+	queue_redraw()
+
+
+func get_review_filter() -> String:
+	return review_filter
+
+
+func set_review_filter(new_review_filter: String) -> void:
+	review_filter = _normalize_review_filter(new_review_filter)
+	_prune_selected_to_visible()
 	queue_redraw()
 
 
 func toggle_asset_at_world(world_position: Vector2) -> bool:
 	var index := asset_index_at_world(world_position)
-	if index < 0 or index >= asset_ids.size():
+	var visible_ids := get_visible_asset_ids()
+	if index < 0 or index >= visible_ids.size():
 		return false
-	var asset_id := asset_ids[index]
+	var asset_id := visible_ids[index]
 	if selected_asset_ids.has(asset_id):
 		selected_asset_ids.erase(asset_id)
 	else:
@@ -167,7 +215,8 @@ func asset_index_at_world(world_position: Vector2) -> int:
 	if local.y < HEADER_HEIGHT:
 		return -1
 	var columns := _columns()
-	for index in range(asset_ids.size()):
+	var visible_ids := get_visible_asset_ids()
+	for index in range(visible_ids.size()):
 		var rect := _thumb_rect(index, columns)
 		if rect.has_point(local):
 			return index
@@ -183,10 +232,14 @@ func _draw() -> void:
 		Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, HEADER_HEIGHT)), Color(0.21, 0.22, 0.24, 1.0), true
 	)
 	if _font != null:
+		var visible_count := get_visible_asset_ids().size()
+		var title := "%s (%d)" % [label, asset_ids.size()]
+		if visible_count != asset_ids.size():
+			title = "%s (%d/%d)" % [label, visible_count, asset_ids.size()]
 		draw_string(
 			_font,
 			Vector2(PADDING, 28),
-			"%s (%d)" % [label, asset_ids.size()],
+			title,
 			HORIZONTAL_ALIGNMENT_LEFT,
 			CARD_WIDTH - PADDING * 2,
 			18,
@@ -194,14 +247,14 @@ func _draw() -> void:
 		)
 
 	var columns := _columns()
-	for index in range(asset_ids.size()):
-		_draw_thumbnail(index, _thumb_rect(index, columns))
+	var visible_ids := get_visible_asset_ids()
+	for index in range(visible_ids.size()):
+		_draw_thumbnail(visible_ids[index], _thumb_rect(index, columns))
 	if has_graph_binding():
 		_draw_graph_ports()
 
 
-func _draw_thumbnail(index: int, rect: Rect2) -> void:
-	var asset_id := asset_ids[index]
+func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
 	draw_rect(rect, THUMB_BACKGROUND, true)
 	var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
 	if texture != null:
@@ -253,9 +306,10 @@ func _thumb_rect(index: int, columns: int) -> Rect2:
 
 
 func _card_height() -> int:
-	if asset_ids.is_empty():
+	var visible_count := get_visible_asset_ids().size()
+	if visible_count <= 0:
 		return MIN_CARD_HEIGHT
-	var rows := int(ceil(float(asset_ids.size()) / float(_columns())))
+	var rows := int(ceil(float(visible_count) / float(_columns())))
 	return maxi(
 		MIN_CARD_HEIGHT, HEADER_HEIGHT + PADDING * 2 + rows * THUMB_SIZE + (rows - 1) * THUMB_GAP
 	)
@@ -346,3 +400,29 @@ func _normalize_review_state(review_state: String) -> String:
 			return review_state
 		_:
 			return REVIEW_NONE
+
+
+func _normalize_review_filter(value: String) -> String:
+	match value:
+		FILTER_ALL, FILTER_PENDING, REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
+			return value
+		_:
+			return FILTER_ALL
+
+
+func _prune_selected_to_visible() -> void:
+	var visible_lookup := _visible_lookup()
+	for selected_id in selected_asset_ids.duplicate():
+		if not visible_lookup.has(selected_id):
+			selected_asset_ids.erase(selected_id)
+
+
+func _visible_lookup() -> Dictionary:
+	return _lookup(get_visible_asset_ids())
+
+
+func _lookup(values: Array[String]) -> Dictionary:
+	var result := {}
+	for value in values:
+		result[value] = true
+	return result
diff --git a/pixel/ui/canvas/canvas_batch_ops.gd b/pixel/ui/canvas/canvas_batch_ops.gd
index 99403b0..a174ed5 100644
--- a/pixel/ui/canvas/canvas_batch_ops.gd
+++ b/pixel/ui/canvas/canvas_batch_ops.gd
@@ -49,20 +49,26 @@ static func replace_asset_ids(
 		return
 	var before: Array = item.asset_ids.duplicate()
 	var before_review_states: Dictionary = item.get_review_states()
+	var before_review_filter: String = item.get_review_filter()
 	var after := new_asset_ids.duplicate()
 	var after_review_states := {}
+	var after_review_filter := CanvasBatchCardScript.FILTER_ALL
 	var do_replace := func() -> void:
 		GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
 		_apply_review_states(item, after_review_states)
+		_apply_review_filter(item, after_review_filter)
 		GraphItemBridge.sync_batch_node_asset_ids(item, after)
 		GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
+		GraphItemBridge.sync_batch_node_review_filter(item, after_review_filter)
 		select_only.call([card_id])
 		emit_changed.call()
 	var undo_replace := func() -> void:
 		GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
 		_apply_review_states(item, before_review_states)
+		_apply_review_filter(item, before_review_filter)
 		GraphItemBridge.sync_batch_node_asset_ids(item, before)
 		GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
+		GraphItemBridge.sync_batch_node_review_filter(item, before_review_filter)
 		select_only.call([card_id])
 		emit_changed.call()
 	if record_undo:
@@ -114,6 +120,40 @@ static func set_review_state(
 	return target_ids.size()
 
 
+static func set_review_filter(
+	items_by_id: Dictionary,
+	card_id: String,
+	review_filter: String,
+	record_undo: bool,
+	select_only: Callable,
+	emit_changed: Callable
+) -> bool:
+	var item := _batch_item(items_by_id, card_id)
+	if item == null:
+		return false
+	var before: String = item.get_review_filter()
+	var after := _normalize_review_filter(review_filter)
+	if before == after:
+		return true
+
+	var do_filter := func() -> void:
+		_apply_review_filter(item, after)
+		GraphItemBridge.sync_batch_node_review_filter(item, after)
+		select_only.call([card_id])
+		emit_changed.call()
+	var undo_filter := func() -> void:
+		_apply_review_filter(item, before)
+		GraphItemBridge.sync_batch_node_review_filter(item, before)
+		select_only.call([card_id])
+		emit_changed.call()
+
+	if record_undo:
+		UndoService.perform_action("Set batch review filter", do_filter, undo_filter)
+	else:
+		do_filter.call()
+	return true
+
+
 static func split_selection_spec(items_by_id: Dictionary, card_id: String) -> Dictionary:
 	var item := _batch_item(items_by_id, card_id)
 	if item == null:
@@ -162,6 +202,10 @@ static func _apply_review_states(item: Node, review_states: Dictionary) -> void:
 	item.set_review_states(review_states)
 
 
+static func _apply_review_filter(item: Node, review_filter: String) -> void:
+	item.set_review_filter(review_filter)
+
+
 static func _normalize_review_state(review_state: String) -> String:
 	if (
 		review_state
@@ -173,3 +217,18 @@ static func _normalize_review_state(review_state: String) -> String:
 	):
 		return review_state
 	return CanvasBatchCardScript.REVIEW_NONE
+
+
+static func _normalize_review_filter(review_filter: String) -> String:
+	if (
+		review_filter
+		in [
+			CanvasBatchCardScript.FILTER_ALL,
+			CanvasBatchCardScript.FILTER_PENDING,
+			CanvasBatchCardScript.REVIEW_KEEP,
+			CanvasBatchCardScript.REVIEW_REJECT,
+			CanvasBatchCardScript.REVIEW_FLAG,
+		]
+	):
+		return review_filter
+	return CanvasBatchCardScript.FILTER_ALL
diff --git a/pixel/ui/canvas/canvas_graph_item_bridge.gd b/pixel/ui/canvas/canvas_graph_item_bridge.gd
index 5371ed5..1c43497 100644
--- a/pixel/ui/canvas/canvas_graph_item_bridge.gd
+++ b/pixel/ui/canvas/canvas_graph_item_bridge.gd
@@ -4,6 +4,8 @@ extends RefCounted
 ## Graph 节点引用与画布卡片之间的桥接 helper。
 ## contract: 02-contracts/PROJECT-FORMAT.md §4；canvas 只存 node 引用，batch 队列回写 graph params。
 
+const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
+
 
 static func is_graph_batch_node_data(item_data: Dictionary) -> bool:
 	if String(item_data.get("type", "")) != "node":
@@ -53,6 +55,7 @@ static func sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
 			var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
 			params["asset_ids"] = _string_array(asset_ids)
 			params["review_states"] = _review_state_map(params.get("review_states", {}), asset_ids)
+			params["review_filter"] = _review_filter(params.get("review_filter", "all"))
 			node_data["params"] = params
 			changed = true
 		nodes.append(node_data)
@@ -92,6 +95,36 @@ static func sync_batch_node_review_states(item: Node, review_states: Dictionary)
 		ProjectService.set_graph_data(item.graph_id, graph_data, true)
 
 
+static func sync_batch_node_review_filter(item: Node, review_filter: String) -> void:
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
+			params["review_filter"] = _review_filter(review_filter)
+			node_data["params"] = params
+			changed = true
+		nodes.append(node_data)
+
+	if changed:
+		graph_data["nodes"] = nodes
+		ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
 static func _string_array(value: Variant) -> Array[String]:
 	var result: Array[String] = []
 	if value is Array:
@@ -118,3 +151,19 @@ static func _review_state_map(value: Variant, valid_asset_ids: Variant) -> Dicti
 		if review_state in ["keep", "reject", "flag"]:
 			result[asset_id] = review_state
 	return result
+
+
+static func _review_filter(value: Variant) -> String:
+	var filter := String(value)
+	if (
+		filter
+		in [
+			CanvasBatchCardScript.FILTER_ALL,
+			CanvasBatchCardScript.FILTER_PENDING,
+			CanvasBatchCardScript.REVIEW_KEEP,
+			CanvasBatchCardScript.REVIEW_REJECT,
+			CanvasBatchCardScript.REVIEW_FLAG,
+		]
+	):
+		return filter
+	return CanvasBatchCardScript.FILTER_ALL
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 0a76239..b81dd3f 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -492,6 +492,14 @@ func _get_batch_marked_asset_ids(card_id: String, review_state: String) -> Array
 	return BatchOps.get_marked_asset_ids(_items_by_id, card_id, review_state)
 
 
+func _set_batch_review_filter(
+	card_id: String, review_filter: String, record_undo: bool = true
+) -> bool:
+	return BatchOps.set_review_filter(
+		_items_by_id, card_id, review_filter, record_undo, _select_only, _emit_canvas_changed
+	)
+
+
 func _replace_batch_asset_ids(
 	card_id: String, new_asset_ids: Array, record_undo: bool = true
 ) -> void:
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index fd0cf59..b61aee0 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -48,6 +48,11 @@ const BATCH_MENU_MARK_REJECT := 6
 const BATCH_MENU_MARK_FLAG := 7
 const BATCH_MENU_CLEAR_MARK := 8
 const BATCH_MENU_SPLIT_KEEP := 9
+const BATCH_MENU_FILTER_ALL := 10
+const BATCH_MENU_FILTER_KEEP := 11
+const BATCH_MENU_FILTER_PENDING := 12
+const BATCH_MENU_FILTER_REJECT := 13
+const BATCH_MENU_FILTER_FLAG := 14
 const SELECTION_TOOLS_VISIBLE := false
 
 var _canvas: Control = null
@@ -303,6 +308,12 @@ func _create_batch_menu() -> void:
 	_batch_menu.add_item(Strings.BATCH_ACTION_MARK_FLAG, BATCH_MENU_MARK_FLAG)
 	_batch_menu.add_item(Strings.BATCH_ACTION_CLEAR_MARK, BATCH_MENU_CLEAR_MARK)
 	_batch_menu.add_separator()
+	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_ALL, BATCH_MENU_FILTER_ALL)
+	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_KEEP, BATCH_MENU_FILTER_KEEP)
+	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_PENDING, BATCH_MENU_FILTER_PENDING)
+	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_REJECT, BATCH_MENU_FILTER_REJECT)
+	_batch_menu.add_item(Strings.BATCH_ACTION_SHOW_FLAG, BATCH_MENU_FILTER_FLAG)
+	_batch_menu.add_separator()
 	_batch_menu.add_item(Strings.BATCH_ACTION_SPLIT_KEEP, BATCH_MENU_SPLIT_KEEP)
 	_batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
 	_batch_menu.add_separator()
@@ -424,6 +435,26 @@ func _on_batch_menu_id_pressed(id: int) -> void:
 			_mark_batch_review_state(
 				CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
 			)
+		BATCH_MENU_FILTER_ALL:
+			_set_batch_review_filter(
+				CanvasBatchCardScript.FILTER_ALL, Strings.STATUS_BATCH_SHOW_ALL
+			)
+		BATCH_MENU_FILTER_KEEP:
+			_set_batch_review_filter(
+				CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_SHOW_KEEP
+			)
+		BATCH_MENU_FILTER_PENDING:
+			_set_batch_review_filter(
+				CanvasBatchCardScript.FILTER_PENDING, Strings.STATUS_BATCH_SHOW_PENDING
+			)
+		BATCH_MENU_FILTER_REJECT:
+			_set_batch_review_filter(
+				CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_SHOW_REJECT
+			)
+		BATCH_MENU_FILTER_FLAG:
+			_set_batch_review_filter(
+				CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_SHOW_FLAG
+			)
 		BATCH_MENU_SPLIT_KEEP:
 			var new_keep_card: Variant = _canvas._split_batch_marked(
 				_batch_menu_card_id,
@@ -458,6 +489,13 @@ func _mark_batch_review_state(review_state: String, status_format: String) -> vo
 	_status_label.text = status_format % marked_count
 
 
+func _set_batch_review_filter(review_filter: String, status_text: String) -> void:
+	if not _canvas._set_batch_review_filter(_batch_menu_card_id, review_filter, true):
+		_status_label.text = Strings.STATUS_BATCH_FILTER_FAILED
+		return
+	_status_label.text = status_text
+
+
 func _emit_batch_export(asset_ids: Array) -> void:
 	var snapshots := []
 	for asset_id in asset_ids:
diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index 115cf3a..6b00e04 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -50,6 +50,12 @@ const STATUS_BATCH_MARK_KEEP := "%d thumbnails marked keep"
 const STATUS_BATCH_MARK_REJECT := "%d thumbnails marked reject"
 const STATUS_BATCH_MARK_FLAG := "%d thumbnails flagged"
 const STATUS_BATCH_MARK_CLEAR := "%d thumbnail marks cleared"
+const STATUS_BATCH_SHOW_ALL := "Showing all thumbnails"
+const STATUS_BATCH_SHOW_KEEP := "Showing kept thumbnails"
+const STATUS_BATCH_SHOW_PENDING := "Showing pending thumbnails"
+const STATUS_BATCH_SHOW_REJECT := "Showing rejected thumbnails"
+const STATUS_BATCH_SHOW_FLAG := "Showing flagged thumbnails"
+const STATUS_BATCH_FILTER_FAILED := "Batch filter failed"
 const STATUS_MOCK_GENERATE_DONE := "Mock batch generated: %d sprites"
 const STATUS_MOCK_GENERATE_FAILED := "Mock batch generation failed"
 const STATUS_GRAPH_RUN_DONE := "Graph run complete: %d sprites"
@@ -141,6 +147,11 @@ const BATCH_ACTION_MARK_KEEP := "Mark Keep"
 const BATCH_ACTION_MARK_REJECT := "Mark Reject"
 const BATCH_ACTION_MARK_FLAG := "Flag"
 const BATCH_ACTION_CLEAR_MARK := "Clear Mark"
+const BATCH_ACTION_SHOW_ALL := "Show All"
+const BATCH_ACTION_SHOW_KEEP := "Show Keep"
+const BATCH_ACTION_SHOW_PENDING := "Show Pending"
+const BATCH_ACTION_SHOW_REJECT := "Show Reject"
+const BATCH_ACTION_SHOW_FLAG := "Show Flagged"
 const BATCH_ACTION_SPLIT_KEEP := "Split Kept"
 const BATCH_ACTION_SPLIT := "Split Selected"
 const BATCH_ACTION_EXPORT := "Export Batch"
diff --git a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
index 529975e..5f675ae 100644
--- a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
+++ b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
@@ -127,7 +127,7 @@ func get_canvas_actions() -> Array[Dictionary]
 新概念，本模型的核心。装一个批次的图片队列，是「AI 输出自由」与「批量加工」的落脚点。
 
 - **双身份**：① 图节点（`type=batch`，`category=container`，`is_canvas_resident()=true`）；② 画布卡（PROJECT-FORMAT canvas.json 的 `node` 引用，特化渲染为容器卡）。
-- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），随 `asset_ids` 过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
+- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），可选 `review_filter` 记录当前审阅过滤器（`all|pending|keep|reject|flag`），二者均随 `asset_ids` 过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
 - **整批菜单**（`get_canvas_actions()` 声明，边框弹出）：整批清洗 / 整批抠图 / 整批描边 / 整批量化 / 导出整批 / 拆小批次 / 逐张发送到编辑器。均调 core，记 undo + provenance（§4.7）。
 - **拆小批次**：勾选子集 → 生成子 `batch`（新卡，引用子集 asset_id），可独立处理；复用 `select` 语义。
 - **分离单图**：把某张拖出批次卡 → 成为独立 sprite 卡（仍在同一画布，见 PROJECT-FORMAT §4 `sprite`）。
diff --git a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
index 9bf2899..2a78aa8 100644
--- a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
+++ b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
@@ -108,6 +108,8 @@ my_project.pxproj (ZIP)
       "type": "batch_card",        // M2.1 临时批次卡；M3 后升级为 type=node + graphs batch
       "asset_ids": ["uuid-a", "uuid-b"],
       "selected_asset_ids": [],
+      "review_states": { "uuid-a": "keep" },
+      "review_filter": "all",
      "label": "Batch",
      "position": [320, 64],
      "z_index": 1,
```

## 2026-06-18 M3 UX-5 批次审阅快捷键

### 本轮实现说明

- 在 `PFM21UiController.handle_shortcut()` 中接入批次审阅快捷键：选中批次卡内缩略图后，`K` 标记 keep，`R` 标记 reject，`F` 标记 flag，`C` 清除标记。
- 右键菜单与键盘入口复用同一个 `_mark_batch_review_state_for_card()` 写入路径，继续通过 canvas batch ops 同步到 graph batch node params 的 `review_states`。
- 新增 smoke 测试覆盖 mock batch 生成、选择缩略图、按 `K/R` 快捷键、验证 graph params 写回。

### 验证结果

- `./pixel/scripts/lint.sh`：通过，105 files would be left unchanged，gdlint 无问题。
- `./pixel/scripts/run_tests.sh`：通过，140/140 tests passed，1152 asserts。
- `./pixel/scripts/verify_m3_ux5.sh`：通过，含 lint、完整测试、`check_ui_scaling: ok` 与 headless startup gate。

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`。
2. 在 Mock Batch 卡中单击一个或多个缩略图，确认缩略图出现选中边框。
3. 按 `K`，确认选中缩略图出现 keep 绿色标记，状态栏显示 marked keep。
4. 对同一缩略图按 `R`，确认标记切换为 reject 红色叉。
5. 按 `F`，确认标记切换为 flag 黄色角标。
6. 按 `C`，确认标记被清除。
7. 可继续用右键菜单的 Show Keep / Show Reject / Show Flagged 检查快捷键写入的标记可被过滤器识别。

### 本轮完整 diff

```diff
diff --git a/pixel/tests/smoke/test_main_window_ui.gd b/pixel/tests/smoke/test_main_window_ui.gd
index 16b1d28..26565e3 100644
--- a/pixel/tests/smoke/test_main_window_ui.gd
+++ b/pixel/tests/smoke/test_main_window_ui.gd
@@ -259,6 +259,39 @@ func test_mock_generate_menu_action_creates_visible_batch_and_graph() -> void:
 	assert_eq(canvas._get_batch_asset_ids(batch_item_id), rerun_asset_ids)
 
 
+func test_batch_review_shortcuts_mark_selected_mock_thumbnail() -> void:
+	ProjectService.new_project("Batch Shortcut UI")
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
+	var graph_id := String(ProjectService.current_project.graphs.keys()[0])
+	var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
+	var batch_node: Dictionary = graph_data["nodes"][3]
+	var first_asset_id := String(batch_node["params"]["asset_ids"][0])
+	var batch_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], "batch_1")
+	var batch_card: Node = canvas._items_by_id[batch_item_id]
+
+	canvas.select_ids([batch_item_id])
+	assert_true(batch_card.toggle_asset_at_world(batch_card.position + Vector2(20, 60)))
+	assert_true(_send_key(controller, KEY_K))
+
+	graph_data = ProjectService.current_project.graphs[graph_id]
+	batch_node = graph_data["nodes"][3]
+	assert_eq(batch_node["params"]["review_states"][first_asset_id], "keep")
+
+	assert_true(_send_key(controller, KEY_R))
+	graph_data = ProjectService.current_project.graphs[graph_id]
+	batch_node = graph_data["nodes"][3]
+	assert_eq(batch_node["params"]["review_states"][first_asset_id], "reject")
+
+
 func _node_ids_from_canvas_items(items: Array) -> Array:
 	var node_ids := []
 	for item in items:
@@ -272,3 +305,10 @@ func _item_id_for_node(items: Array, node_id: String) -> String:
 		if String(data.get("node_id", "")) == node_id:
 			return String(data.get("id", ""))
 	return ""
+
+
+func _send_key(controller: Node, keycode: Key) -> bool:
+	var event := InputEventKey.new()
+	event.keycode = keycode
+	event.pressed = true
+	return controller.handle_shortcut(event)
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index b61aee0..0aa0545 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -146,6 +146,8 @@ func handle_shortcut(event: InputEventKey) -> bool:
 	if event.keycode == KEY_ESCAPE and not _tool_manager.get_active_tool_id().is_empty():
 		_tool_manager.clear_active_tool()
 		return true
+	if _handle_batch_review_shortcut(event):
+		return true
 	if not SELECTION_TOOLS_VISIBLE:
 		return false
 	return _tool_manager.handle_shortcut(event.keycode)
@@ -476,17 +478,64 @@ func _on_batch_menu_id_pressed(id: int) -> void:
 
 
 func _mark_batch_review_state(review_state: String, status_format: String) -> void:
-	var selected_ids: Array = _canvas._get_batch_selected_asset_ids(_batch_menu_card_id)
+	_mark_batch_review_state_for_card(_batch_menu_card_id, review_state, status_format)
+
+
+func _mark_batch_review_state_for_card(
+	card_id: String, review_state: String, status_format: String
+) -> bool:
+	var selected_ids: Array = _canvas._get_batch_selected_asset_ids(card_id)
 	if selected_ids.is_empty():
 		_status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
-		return
+		return false
 	var marked_count: int = _canvas._set_batch_review_state(
-		_batch_menu_card_id, selected_ids, review_state, true
+		card_id, selected_ids, review_state, true
 	)
 	if marked_count <= 0:
 		_status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
-		return
+		return false
 	_status_label.text = status_format % marked_count
+	return true
+
+
+func _handle_batch_review_shortcut(event: InputEventKey) -> bool:
+	if event.is_command_or_control_pressed() or event.alt_pressed:
+		return false
+	var card_id := _selected_batch_card_id()
+	match event.keycode:
+		KEY_K:
+			_mark_batch_review_state_for_card(
+				card_id, CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_MARK_KEEP
+			)
+			return true
+		KEY_R:
+			_mark_batch_review_state_for_card(
+				card_id, CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_MARK_REJECT
+			)
+			return true
+		KEY_F:
+			_mark_batch_review_state_for_card(
+				card_id, CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_MARK_FLAG
+			)
+			return true
+		KEY_C:
+			_mark_batch_review_state_for_card(
+				card_id, CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
+			)
+			return true
+	return false
+
+
+func _selected_batch_card_id() -> String:
+	var selected_ids: Array = _canvas.get_selected_ids()
+	if selected_ids.is_empty():
+		return ""
+	for item in _canvas.export_canvas_data()["items"]:
+		var item_data: Dictionary = item
+		var item_id := String(item_data.get("id", ""))
+		if selected_ids.has(item_id) and not _canvas._get_batch_asset_ids(item_id).is_empty():
+			return item_id
+	return ""
 
 
 func _set_batch_review_filter(review_filter: String, status_text: String) -> void:
```
