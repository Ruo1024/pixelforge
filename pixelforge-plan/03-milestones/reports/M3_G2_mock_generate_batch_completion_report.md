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
