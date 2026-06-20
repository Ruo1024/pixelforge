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

## 2026-06-20 M3 G-4 follow-up: graph port drag-to-connect

### 本轮实现说明

- 在 UX-7 已有 graph port 命中仲裁基础上，补齐最小“从端口拖线创建 graph edge”交互：按下端口进入拖线预览，拖到同一 graph 内的反向端口释放后写入 `graphs/{graph_id}.json` 的 `edges`。
- 新增 `PFCanvasGraphEdgeInteraction`，集中处理拖线状态、预览线绘制、真实端口解析与 `PFGraph.can_connect()` 校验；UI 不复制类型规则。
- 兼容 AI Generate 的单视觉输入点：画布 hit-test 返回视觉端口 `in` 时，连接 helper 会从真实输入端口中选择第一个 `PFGraph.can_connect()` 允许的端口。
- 新增 `PFCanvasSelectionSnapshot`，把选择位置快照/比较/恢复的小工具从 `infinite_canvas.gd` 拆出，保持主画布文件在 gdlint `max-file-lines` 门槛内。
- 新增 2 条单元回归：兼容端口拖拽会新增 edge；不兼容端口拖拽不会污染 graph。

### 验证结果

| 命令 | 结果 |
|---|---|
| `./pixel/scripts/lint.sh` | 通过：`Success: no problems found` |
| `./pixel/scripts/run_tests.sh` | 通过：159/159 tests，通过；仍有既有 GUT orphan 提示 `test_cleanup_batch_performance.gd` 外部 `error_tracker.gd` |
| `./pixel/scripts/verify_m3_ux7.sh` | 通过：`verify_m3_ux7: ok` |

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`，确认画布出现 Object List / Size Spec / AI Generate / Mock Batch 节点链。
2. 从 Object List 右侧输出端口拖到 AI Generate 左侧单视觉输入点，松手后应出现一条连线；从 Size Spec 右侧输出端口拖到 AI Generate 左侧单视觉输入点，也应能连到兼容真实端口。
3. 尝试从 Object List 输出端口拖到 Mock Batch 输入端口；由于 `text_list -> image_list` 不兼容，不应新增连线。
4. 连接成功后执行撤销/重做，确认 graph 连线随 Undo/Redo 消失和恢复。
5. 继续点击端口、缩略图、拖动卡片，确认端口优先级没有导致批次缩略图审阅和整卡拖动退化。

### 本轮完整 diff

```diff
diff --git a/pixel/tests/unit/test_canvas_hit_policy.gd b/pixel/tests/unit/test_canvas_hit_policy.gd
index a9745c5..1630032 100644
--- a/pixel/tests/unit/test_canvas_hit_policy.gd
+++ b/pixel/tests/unit/test_canvas_hit_policy.gd
@@ -96,6 +96,50 @@ func test_canvas_left_click_on_graph_port_selects_without_dragging_card() -> voi
     assert_false(canvas._selection.is_dragging_items)


+func test_canvas_drag_between_compatible_graph_ports_adds_edge() -> void:
+    var canvas: Control = _canvas()
+    _set_graph(
+        "graph_hit", [_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")]
+    )
+    var objects: Node = canvas._add_node_direct(
+        _node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
+    )
+    var generate: Node = canvas._add_node_direct(
+        _node_item("generate_item", "graph_hit", "generate", Vector2(380, 100))
+    )
+
+    canvas._begin_left_interaction(
+        canvas.world_to_screen(objects.get_graph_port_anchor("items", false)), false
+    )
+    canvas._finish_left_interaction(
+        canvas.world_to_screen(generate.get_graph_port_anchor("items", true))
+    )
+
+    var graph_data := ProjectService.get_graph_data("graph_hit")
+    assert_eq(
+        graph_data.get("edges", []), [{"from": ["objects", "items"], "to": ["generate", "items"]}]
+    )
+
+
+func test_canvas_drag_between_incompatible_graph_ports_does_not_add_edge() -> void:
+    var canvas: Control = _canvas()
+    var ids := [_register_asset(Color.RED, "red")]
+    _set_graph("graph_hit", [_graph_node("objects", "object_list"), _batch_node("batch_1", ids)])
+    var objects: Node = canvas._add_node_direct(
+        _node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
+    )
+    var batch: Node = canvas._add_batch_card(
+        ids, Vector2(380, 100), "Batch", "batch_item", false, "graph_hit", "batch_1"
+    )
+
+    canvas._begin_left_interaction(
+        canvas.world_to_screen(objects.get_graph_port_anchor("items", false)), false
+    )
+    canvas._finish_left_interaction(canvas.world_to_screen(batch.get_graph_port_anchor("in", true)))
+
+    assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [])
+
+
 func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
     var canvas: Control = _canvas()
     var ids := [_register_asset(Color.RED, "red")]
diff --git a/pixel/ui/canvas/canvas_graph_edge_interaction.gd b/pixel/ui/canvas/canvas_graph_edge_interaction.gd
new file mode 100644
index 0000000..aa2734b
--- /dev/null
+++ b/pixel/ui/canvas/canvas_graph_edge_interaction.gd
@@ -0,0 +1,139 @@
+class_name PFCanvasGraphEdgeInteraction
+extends RefCounted
+
+## Graph port drag/connect helper for PFInfiniteCanvas.
+## contract: 02-contracts/GRAPH-SCHEMA.md §2；连接校验只委托 PFGraph。
+
+const GraphScript := preload("res://core/graph/pf_graph.gd")
+
+
+static func begin_drag(port_hit: Dictionary) -> Dictionary:
+    var item: Node = port_hit.get("item", null)
+    if item == null or item.graph_id.is_empty() or item.node_id.is_empty():
+        return {}
+    var port_name := String(port_hit.get("port_name", ""))
+    if port_name.is_empty():
+        return {}
+    var is_input := bool(port_hit.get("is_input", false))
+    return {
+        "graph_id": item.graph_id,
+        "node_id": item.node_id,
+        "port_name": port_name,
+        "is_input": is_input,
+        "anchor": item.get_graph_port_anchor(port_name, is_input),
+    }
+
+
+static func try_connect(start: Dictionary, end: Dictionary, changed: Callable) -> bool:
+    var end_item: Node = end.get("item", null)
+    if end_item == null:
+        return false
+    if String(start.get("graph_id", "")) != end_item.graph_id:
+        return false
+    if bool(start.get("is_input", false)) == bool(end.get("is_input", false)):
+        return false
+
+    var graph_id := String(start.get("graph_id", ""))
+    var before := ProjectService.get_graph_data(graph_id)
+    if before.is_empty():
+        return false
+    var graph: PFGraph = GraphScript.from_json(before)
+    var endpoints := _resolve_endpoints(graph, start, end, end_item)
+    if endpoints.is_empty():
+        return false
+    var result := graph.add_edge(
+        endpoints["source_node"],
+        endpoints["source_port"],
+        endpoints["target_node"],
+        endpoints["target_port"]
+    )
+    if not bool(result.get("ok", false)):
+        return false
+
+    var after := graph.to_json()
+    UndoService.perform_action(
+        "Connect graph ports",
+        func() -> void:
+            ProjectService.set_graph_data(graph_id, after)
+            changed.call(),
+        func() -> void:
+            ProjectService.set_graph_data(graph_id, before)
+            changed.call()
+    )
+    return true
+
+
+static func draw_preview(
+    canvas: Control, edge_renderer: Script, drag_state: Dictionary, drag_world: Vector2
+) -> void:
+    var start_world: Vector2 = drag_state.get("anchor", drag_world)
+    var start: Vector2 = canvas.world_to_screen(start_world)
+    var end: Vector2 = canvas.world_to_screen(drag_world)
+    var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
+    var direction := -1.0 if bool(drag_state.get("is_input", false)) else 1.0
+    var control_a: Vector2 = start + Vector2(bend * direction, 0.0)
+    var control_b: Vector2 = end - Vector2(bend * direction, 0.0)
+    var points := PackedVector2Array()
+    for index in range(17):
+        var t := float(index) / 16.0
+        points.append(edge_renderer._cubic_bezier(start, control_a, control_b, end, t))
+    canvas.draw_polyline(points, Color(0.72, 0.9, 0.95, 0.72), 2.0, true)
+
+
+static func _resolve_endpoints(
+    graph: PFGraph, start: Dictionary, end: Dictionary, end_item: Node
+) -> Dictionary:
+    if bool(start.get("is_input", false)):
+        return _first_valid_connection(
+            graph,
+            end_item.node_id,
+            [String(end.get("port_name", ""))],
+            String(start.get("node_id", "")),
+            _input_port_candidates(
+                graph, String(start.get("node_id", "")), String(start.get("port_name", ""))
+            )
+        )
+    return _first_valid_connection(
+        graph,
+        String(start.get("node_id", "")),
+        [String(start.get("port_name", ""))],
+        end_item.node_id,
+        _input_port_candidates(graph, end_item.node_id, String(end.get("port_name", "")))
+    )
+
+
+static func _first_valid_connection(
+    graph: PFGraph,
+    source_node: String,
+    source_ports: Array,
+    target_node: String,
+    target_ports: Array
+) -> Dictionary:
+    for source_port in source_ports:
+        for target_port in target_ports:
+            var result := graph.can_connect(
+                source_node, String(source_port), target_node, String(target_port)
+            )
+            if bool(result.get("ok", false)):
+                return {
+                    "source_node": source_node,
+                    "source_port": String(source_port),
+                    "target_node": target_node,
+                    "target_port": String(target_port),
+                }
+    return {}
+
+
+static func _input_port_candidates(graph: PFGraph, node_id: String, port_name: String) -> Array:
+    var node := graph.get_node(node_id)
+    if node == null:
+        return []
+    var exact := node.get_input_port(port_name)
+    if not exact.is_empty():
+        return [port_name]
+    if port_name != "in":
+        return [port_name]
+    var ports := []
+    for port in node.get_input_ports():
+        ports.append(String(port.get("name", "")))
+    return ports
diff --git a/pixel/ui/canvas/canvas_graph_edge_interaction.gd.uid b/pixel/ui/canvas/canvas_graph_edge_interaction.gd.uid
new file mode 100644
index 0000000..76d5d1e
--- /dev/null
+++ b/pixel/ui/canvas/canvas_graph_edge_interaction.gd.uid
@@ -0,0 +1 @@
+uid://bf7f24p4n84y4
diff --git a/pixel/ui/canvas/canvas_selection_snapshot.gd b/pixel/ui/canvas/canvas_selection_snapshot.gd
new file mode 100644
index 0000000..7c884d8
--- /dev/null
+++ b/pixel/ui/canvas/canvas_selection_snapshot.gd
@@ -0,0 +1,36 @@
+class_name PFCanvasSelectionSnapshot
+extends RefCounted
+
+## Small helpers for canvas selection snapshots used by undoable interactions.
+
+
+static func selected_positions(items_by_id: Dictionary, selection: Variant) -> Dictionary:
+    var positions := {}
+    for item_id in selection.get_selected_ids():
+        if items_by_id.has(item_id):
+            positions[item_id] = items_by_id[item_id].position
+    return positions
+
+
+static func apply_positions(items_by_id: Dictionary, positions: Dictionary) -> void:
+    for item_id in positions.keys():
+        if items_by_id.has(item_id):
+            items_by_id[item_id].position = Vector2(positions[item_id]).round()
+
+
+static func positions_equal(left: Dictionary, right: Dictionary) -> bool:
+    if left.size() != right.size():
+        return false
+    for item_id in left.keys():
+        if not right.has(item_id):
+            return false
+        if Vector2(left[item_id]) != Vector2(right[item_id]):
+            return false
+    return true
+
+
+static func ids_from_snapshots(snapshots: Array) -> Array:
+    var ids := []
+    for snapshot in snapshots:
+        ids.append(String(snapshot["data"]["id"]))
+    return ids
diff --git a/pixel/ui/canvas/canvas_selection_snapshot.gd.uid b/pixel/ui/canvas/canvas_selection_snapshot.gd.uid
new file mode 100644
index 0000000..52c8c8d
--- /dev/null
+++ b/pixel/ui/canvas/canvas_selection_snapshot.gd.uid
@@ -0,0 +1 @@
+uid://beywkrfgng2wn
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 77f3fd3..be5d8eb 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -24,12 +24,14 @@ const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
 const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
 const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
 const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
+const GraphEdgeInteraction := preload("res://ui/canvas/canvas_graph_edge_interaction.gd")
 const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
 const HitPolicy := preload("res://ui/canvas/canvas_hit_policy.gd")
 const LODCoordinator := preload("res://ui/canvas/canvas_lod_coordinator.gd")
 const BatchOps := preload("res://ui/canvas/canvas_batch_ops.gd")
 const CanvasCleanupPreviewScript := preload("res://ui/canvas/canvas_cleanup_preview.gd")
 const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")
+const SelectionSnapshot := preload("res://ui/canvas/canvas_selection_snapshot.gd")
 const ScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
 const CleanupGridOverlayScript := preload("res://ui/canvas/cleanup_grid_overlay.gd")
 const PixelGridRenderer := preload("res://ui/canvas/canvas_pixel_grid_renderer.gd")
@@ -57,6 +59,8 @@ var _is_panning := false
 var _cull_elapsed := 0.0
 var _suppress_change_signal := false
 var _last_wheel_zoom_msec := -1000000
+var _graph_edge_drag := {}
+var _graph_edge_drag_world := Vector2.ZERO


 func _ready() -> void:
@@ -134,7 +138,9 @@ func _draw() -> void:
         >= GRID_MIN_ZOOM
     ):
         PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
-    _draw_graph_edges()
+    GraphEdgeRenderer.draw(
+        self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, EDGE_COLOR
+    )

     for item_id in _selection.selected_ids:
         if not _items_by_id.has(item_id):
@@ -149,6 +155,11 @@ func _draw() -> void:
         draw_rect(box, BOX_COLOR, true)
         draw_rect(box, Color(1.0, 0.85, 0.25, 1.0), false, 1.0)

+    if not _graph_edge_drag.is_empty():
+        GraphEdgeInteraction.draw_preview(
+            self, GraphEdgeRenderer, _graph_edge_drag, _graph_edge_drag_world
+        )
+
     if tool_manager != null:
         tool_manager.draw_overlay(self, _get_active_tool_target())

@@ -303,7 +314,7 @@ func delete_selected(record_undo: bool = true) -> void:
                 _add_batch_direct(data)
             elif String(data.get("type", "")) == "node":
                 _add_node_direct(data)
-        _select_only(_ids_from_snapshots(snapshots))
+        _select_only(SelectionSnapshot.ids_from_snapshots(snapshots))
         _emit_canvas_changed()

     var memory_cost := 0
@@ -593,13 +604,13 @@ func move_selected_by(delta: Vector2, record_undo: bool = true) -> void:
     if _selection.is_empty():
         return

-    var before := _selected_positions()
+    var before := SelectionSnapshot.selected_positions(_items_by_id, _selection)
     var after := {}
     var snapped_delta := delta.round()
     for item_id in before.keys():
         after[item_id] = (Vector2(before[item_id]) + snapped_delta).round()

-    if _positions_equal(before, after):
+    if SelectionSnapshot.positions_equal(before, after):
         return

     var ids: Array = _selection.get_selected_ids()
@@ -652,7 +663,11 @@ func _handle_wheel_zoom(step_delta: int, screen_anchor: Vector2) -> void:


 func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
-    if _is_panning:
+    if not _graph_edge_drag.is_empty():
+        _graph_edge_drag_world = screen_to_world(event.position)
+        queue_redraw()
+        accept_event()
+    elif _is_panning:
         pan_by_pixels(-event.relative)
         accept_event()
     elif _selection.is_dragging_items:
@@ -674,6 +689,7 @@ func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
                 _selection.toggle(hit_item.item_id, _items_by_id.keys())
             else:
                 _select_only([hit_item.item_id])
+            _begin_graph_edge_drag(hit, world_position)
             return
         if (
             String(hit.get("kind", "")) == HitPolicy.KIND_BATCH_THUMBNAIL
@@ -688,7 +704,9 @@ func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
             _select_only([hit_item.item_id])

         if _selection.has(hit_item.item_id):
-            _selection.start_drag(world_position, _selected_positions())
+            _selection.start_drag(
+                world_position, SelectionSnapshot.selected_positions(_items_by_id, _selection)
+            )
     else:
         if not additive:
             _clear_selection()
@@ -697,7 +715,9 @@ func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:


 func _finish_left_interaction(screen_position: Vector2) -> void:
-    if _selection.is_dragging_items:
+    if not _graph_edge_drag.is_empty():
+        _finish_graph_edge_drag(screen_to_world(screen_position))
+    elif _selection.is_dragging_items:
         _commit_drag_if_needed()
         _selection.stop_drag()
     elif _selection.is_box_selecting:
@@ -708,6 +728,21 @@ func _finish_left_interaction(screen_position: Vector2) -> void:
     queue_redraw()


+func _begin_graph_edge_drag(port_hit: Dictionary, world_position: Vector2) -> void:
+    _graph_edge_drag = GraphEdgeInteraction.begin_drag(port_hit)
+    _graph_edge_drag_world = world_position
+    queue_redraw()
+
+
+func _finish_graph_edge_drag(world_position: Vector2) -> void:
+    var start := _graph_edge_drag.duplicate(true)
+    _graph_edge_drag = {}
+    var hit := _hit_at_world(world_position)
+    if String(hit.get("kind", "")) == HitPolicy.KIND_GRAPH_PORT:
+        GraphEdgeInteraction.try_connect(start, hit, _emit_canvas_changed)
+    queue_redraw()
+
+
 func _drag_selected_to(world_position: Vector2) -> void:
     var delta: Vector2 = (world_position - _selection.drag_start_world).round()
     for item_id in _selection.get_selected_ids():
@@ -720,8 +755,8 @@ func _drag_selected_to(world_position: Vector2) -> void:


 func _commit_drag_if_needed() -> void:
-    var after_positions := _selected_positions()
-    if _positions_equal(_selection.drag_start_positions, after_positions):
+    var after_positions := SelectionSnapshot.selected_positions(_items_by_id, _selection)
+    if SelectionSnapshot.positions_equal(_selection.drag_start_positions, after_positions):
         return

     var before: Dictionary = _selection.drag_start_positions.duplicate(true)
@@ -820,33 +855,12 @@ func _hit_at_world(world_position: Vector2) -> Dictionary:
     )


-func _selected_positions() -> Dictionary:
-    var positions := {}
-    for item_id in _selection.get_selected_ids():
-        if _items_by_id.has(item_id):
-            positions[item_id] = _items_by_id[item_id].position
-    return positions
-
-
 func _apply_positions(positions: Dictionary) -> void:
-    for item_id in positions.keys():
-        if _items_by_id.has(item_id):
-            _items_by_id[item_id].position = Vector2(positions[item_id]).round()
+    SelectionSnapshot.apply_positions(_items_by_id, positions)
     _sync_cleanup_grid_overlay()
     queue_redraw()


-func _positions_equal(left: Dictionary, right: Dictionary) -> bool:
-    if left.size() != right.size():
-        return false
-    for item_id in left.keys():
-        if not right.has(item_id):
-            return false
-        if Vector2(left[item_id]) != Vector2(right[item_id]):
-            return false
-    return true
-
-
 func _select_only(ids: Array) -> void:
     _selection.select_only(ids, _items_by_id.keys())

@@ -855,13 +869,6 @@ func _clear_selection() -> void:
     _selection.clear()


-func _ids_from_snapshots(snapshots: Array) -> Array:
-    var ids := []
-    for snapshot in snapshots:
-        ids.append(String(snapshot["data"]["id"]))
-    return ids
-
-
 func _set_zoom_to_value(value: float) -> void:
     var nearest_index := 0
     var nearest_distance := INF
@@ -932,12 +939,6 @@ func _camera_center_for_snapped_anchor(anchor_world: Vector2, screen_anchor: Vec
     )


-func _draw_graph_edges() -> void:
-    GraphEdgeRenderer.draw(
-        self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, EDGE_COLOR
-    )
-
-
 func _emit_canvas_changed() -> void:
     if _suppress_change_signal:
         return
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

-    assert_eq(canvas.get_item_count(), 1)
+    assert_eq(canvas.get_item_count(), 4)
     assert_eq(ProjectService.current_project.graphs.size(), 1)
     var graph_id := String(ProjectService.current_project.graphs.keys()[0])
     var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
     var batch_node: Dictionary = graph_data["nodes"][3]
     assert_eq(batch_node["type"], "batch")
     assert_eq(batch_node["params"]["asset_ids"].size(), 10)
-    var canvas_item: Dictionary = canvas.export_canvas_data()["items"][0]
-    assert_eq(canvas_item["type"], "node")
-    assert_eq(canvas_item["graph_id"], graph_id)
-    assert_eq(canvas_item["node_id"], "batch_1")
+    var canvas_items: Array = canvas.export_canvas_data()["items"]
+    assert_eq(canvas_items.size(), 4)
+    assert_eq(_node_ids_from_canvas_items(canvas_items), ["objects", "size", "generate", "batch_1"])
+    for canvas_item in canvas_items:
+        assert_eq(canvas_item["type"], "node")
+        assert_eq(canvas_item["graph_id"], graph_id)
+
+
+func _node_ids_from_canvas_items(items: Array) -> Array:
+    var node_ids := []
+    for item in items:
+        node_ids.append(String(Dictionary(item).get("node_id", "")))
+    return node_ids
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
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var graph := GraphScript.new()
+    graph.id = "graph_node_card_test"
+    graph.add_node(
+        ObjectListNodeScript.new(), "objects", {"items": "barrel\ncrate"}, Vector2(24, 32)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var node_card: Node = canvas._add_graph_node_card(
+        graph.id, "objects", Vector2(24, 32), "node_item_objects", false
+    )
+    assert_not_null(node_card)
+
+    var canvas_data: Dictionary = canvas.export_canvas_data()
+    var item: Dictionary = canvas_data["items"][0]
+    assert_eq(item["type"], "node")
+    assert_eq(item["graph_id"], graph.id)
+    assert_eq(item["node_id"], "objects")
+    assert_false(item.has("asset_ids"))
+
+    var reloaded_canvas: Control = CanvasScript.new()
+    reloaded_canvas.size = Vector2(512, 512)
+    add_child_autofree(reloaded_canvas)
+    await wait_process_frames(2)
+    reloaded_canvas.load_canvas_data(canvas_data)
+
+    assert_eq(reloaded_canvas.get_item_count(), 1)
+    assert_eq(reloaded_canvas.export_canvas_data()["items"][0]["node_id"], "objects")
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
+    canvas: Control,
+    items_by_id: Dictionary,
+    batch_script: Script,
+    node_script: Script,
+    color: Color
+) -> void:
+    var graph_items := _graph_items_by_node(items_by_id, batch_script, node_script)
+    for graph_id in graph_items.keys():
+        var graph_data := ProjectService.get_graph_data(String(graph_id))
+        var items_by_node: Dictionary = graph_items[graph_id]
+        for edge in graph_data.get("edges", []):
+            if edge is Dictionary:
+                _draw_edge_if_visible(canvas, Dictionary(edge), items_by_node, color)
+
+
+static func _draw_edge_if_visible(
+    canvas: Control, edge: Dictionary, items_by_node: Dictionary, color: Color
+) -> void:
+    var from_data: Array = edge.get("from", ["", ""])
+    var to_data: Array = edge.get("to", ["", ""])
+    var from_node := String(from_data[0])
+    var to_node := String(to_data[0])
+    if not items_by_node.has(from_node) or not items_by_node.has(to_node):
+        return
+    _draw_graph_edge(canvas, items_by_node[from_node], items_by_node[to_node], color)
+
+
+static func _draw_graph_edge(canvas: Control, from_item: Node, to_item: Node, color: Color) -> void:
+    var from_bounds: Rect2 = from_item.get_canvas_bounds()
+    var to_bounds: Rect2 = to_item.get_canvas_bounds()
+    var start: Vector2 = canvas.world_to_screen(
+        from_bounds.position + Vector2(from_bounds.size.x, from_bounds.size.y * 0.5)
+    )
+    var end: Vector2 = canvas.world_to_screen(
+        to_bounds.position + Vector2(0.0, to_bounds.size.y * 0.5)
+    )
+    var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
+    var control_a := start + Vector2(bend, 0.0)
+    var control_b := end - Vector2(bend, 0.0)
+    var points := PackedVector2Array()
+    for index in range(17):
+        var t := float(index) / 16.0
+        points.append(_cubic_bezier(start, control_a, control_b, end, t))
+    canvas.draw_polyline(points, color, 2.0, true)
+
+
+static func _graph_items_by_node(
+    items_by_id: Dictionary, batch_script: Script, node_script: Script
+) -> Dictionary:
+    var graph_items := {}
+    for item in items_by_id.values():
+        if not _is_canvas_graph_item(item, batch_script, node_script):
+            continue
+        if item.graph_id.is_empty() or item.node_id.is_empty():
+            continue
+        if not graph_items.has(item.graph_id):
+            graph_items[item.graph_id] = {}
+        graph_items[item.graph_id][item.node_id] = item
+    return graph_items
+
+
+static func _is_canvas_graph_item(item: Node, batch_script: Script, node_script: Script) -> bool:
+    return item.get_script() == batch_script or item.get_script() == node_script
+
+
+static func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
+    var ab := a.lerp(b, t)
+    var bc := b.lerp(c, t)
+    var cd := c.lerp(d, t)
+    var abbc := ab.lerp(bc, t)
+    var bccd := bc.lerp(cd, t)
+    return abbc.lerp(bccd, t)
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
+    if String(item_data.get("type", "")) != "node":
+        return false
+    var graph_id := String(item_data.get("graph_id", ""))
+    var node_id := String(item_data.get("node_id", ""))
+    if graph_id.is_empty() or node_id.is_empty():
+        return false
+
+    var graph_data := ProjectService.get_graph_data(graph_id)
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            continue
+        var node_data: Dictionary = raw_node
+        if String(node_data.get("id", "")) == node_id:
+            return String(node_data.get("type", "")) == "batch"
+    return false
+
+
+static func apply_batch_asset_ids(item: Node, asset_ids: Array, asset_library: Node) -> void:
+    for asset_id in item.asset_ids:
+        asset_library.release_ref(asset_id)
+    item.set_asset_ids(asset_ids)
+    for asset_id in item.asset_ids:
+        asset_library.add_ref(asset_id)
+
+
+static func sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
+    if not item.has_method("has_graph_binding") or not item.has_graph_binding():
+        return
+
+    var graph_data := ProjectService.get_graph_data(item.graph_id)
+    if graph_data.is_empty():
+        return
+
+    var nodes := []
+    var changed := false
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            nodes.append(raw_node)
+            continue
+        var node_data: Dictionary = raw_node
+        if (
+            String(node_data.get("id", "")) == item.node_id
+            and String(node_data.get("type", "")) == "batch"
+        ):
+            var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
+            params["asset_ids"] = _string_array(asset_ids)
+            node_data["params"] = params
+            changed = true
+        nodes.append(node_data)
+
+    if changed:
+        graph_data["nodes"] = nodes
+        ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
+static func _string_array(value: Variant) -> Array[String]:
+    var result: Array[String] = []
+    if value is Array:
+        for item in Array(value):
+            var id := String(item)
+            if not id.is_empty():
+                result.append(id)
+    return result
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
+    item_id = String(data.get("id", IdUtil.uuid_v4()))
+    graph_id = String(data.get("graph_id", ""))
+    node_id = String(data.get("node_id", ""))
+    locked = bool(data.get("locked", false))
+    z_index = int(data.get("z_index", 0))
+    var raw_position: Variant = data.get("position", [0, 0])
+    position = Vector2(float(raw_position[0]), float(raw_position[1])).round()
+    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
+    _resolve_graph_node()
+    queue_redraw()
+
+
+func to_canvas_data() -> Dictionary:
+    return {
+        "id": item_id,
+        "type": "node",
+        "graph_id": graph_id,
+        "node_id": node_id,
+        "position": [int(round(position.x)), int(round(position.y))],
+        "z_index": z_index,
+        "collapsed": false,
+        "locked": locked,
+    }
+
+
+func get_canvas_bounds() -> Rect2:
+    return Rect2(position, CARD_SIZE)
+
+
+func contains_world_point(world_position: Vector2) -> bool:
+    return get_canvas_bounds().has_point(world_position)
+
+
+func is_graph_node() -> bool:
+    return not graph_id.is_empty() and not node_id.is_empty()
+
+
+func _draw() -> void:
+    _font = ThemeDB.fallback_font if _font == null else _font
+    var rect := Rect2(Vector2.ZERO, CARD_SIZE)
+    draw_rect(rect, BACKGROUND, true)
+    draw_rect(Rect2(Vector2.ZERO, Vector2(CARD_SIZE.x, HEADER_HEIGHT)), HEADER, true)
+    draw_rect(rect, GHOST_BORDER if _is_ghost else BORDER, false, 1.4)
+    _draw_ports()
+    if _font == null:
+        return
+    draw_string(
+        _font,
+        Vector2(PADDING, 22),
+        _display_name,
+        HORIZONTAL_ALIGNMENT_LEFT,
+        CARD_SIZE.x - PADDING * 2,
+        16,
+        Color(0.92, 0.94, 0.94, 1.0)
+    )
+    draw_string(
+        _font,
+        Vector2(PADDING, 54),
+        _node_type,
+        HORIZONTAL_ALIGNMENT_LEFT,
+        CARD_SIZE.x - PADDING * 2,
+        13,
+        Color(0.66, 0.72, 0.74, 1.0)
+    )
+    draw_string(
+        _font,
+        Vector2(PADDING, 82),
+        _summary,
+        HORIZONTAL_ALIGNMENT_LEFT,
+        CARD_SIZE.x - PADDING * 2,
+        13,
+        Color(0.82, 0.84, 0.82, 1.0)
+    )
+
+
+func _draw_ports() -> void:
+    for index in range(_input_count):
+        draw_circle(_port_position(index, _input_count, true), 5.0, PORT_IN)
+    for index in range(_output_count):
+        draw_circle(_port_position(index, _output_count, false), 5.0, PORT_OUT)
+
+
+func _port_position(index: int, count: int, is_input: bool) -> Vector2:
+    var usable_height := CARD_SIZE.y - HEADER_HEIGHT - PADDING * 2
+    var y := HEADER_HEIGHT + PADDING + usable_height * float(index + 1) / float(count + 1)
+    return Vector2(0.0 if is_input else CARD_SIZE.x, y)
+
+
+func _resolve_graph_node() -> void:
+    var node_data := _find_node_data()
+    _node_type = String(node_data.get("type", "missing"))
+    _summary = _summarize_params(node_data.get("params", {}))
+
+    var registry := NodeRegistryScript.new()
+    var node: PFNode = registry.create(_node_type)
+    if node == null:
+        _is_ghost = true
+        _display_name = "Missing: %s" % _node_type
+        _input_count = 0
+        _output_count = 0
+        return
+
+    _display_name = node.get_display_name()
+    _input_count = node.get_input_ports().size()
+    _output_count = node.get_output_ports().size()
+    _is_ghost = false
+
+
+func _find_node_data() -> Dictionary:
+    var graph_data := ProjectService.get_graph_data(graph_id)
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            continue
+        var node_data: Dictionary = raw_node
+        if String(node_data.get("id", "")) == node_id:
+            return node_data
+    return {"id": node_id, "type": "missing", "params": {}}
+
+
+func _summarize_params(params: Variant) -> String:
+    if not (params is Dictionary):
+        return ""
+    var source: Dictionary = params
+    if source.has("items"):
+        var lines := String(source["items"]).split("\n", false)
+        return "%d objects" % lines.size()
+    if source.has("width") and source.has("height"):
+        return "%dx%d px" % [int(source["width"]), int(source["height"])]
+    if source.has("provider_id"):
+        return "%s seed %d" % [String(source["provider_id"]), int(source.get("seed", 0))]
+    return ""
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
+    _draw_graph_edges()

     for item_id in _selection.selected_ids:
         if not _items_by_id.has(item_id):
@@ -224,6 +229,42 @@ func _add_batch_card(
     return _items_by_id.get(String(data["id"]), null)


+func _add_graph_node_card(
+    graph_id: String,
+    node_id: String,
+    world_position: Vector2 = Vector2.ZERO,
+    item_id: String = "",
+    record_undo: bool = true
+) -> Node:
+    var data := {
+        "id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
+        "type": "node",
+        "graph_id": graph_id,
+        "node_id": node_id,
+        "position": [int(round(world_position.x)), int(round(world_position.y))],
+        "z_index": _items_by_id.size(),
+        "collapsed": false,
+        "locked": false,
+    }
+
+    var do_add := func() -> void:
+        _add_node_direct(data)
+        _select_only([String(data["id"])])
+        _emit_canvas_changed()
+
+    var undo_add := func() -> void:
+        _remove_item_direct(String(data["id"]))
+        _clear_selection()
+        _emit_canvas_changed()
+
+    if record_undo:
+        UndoService.perform_action("Add node", do_add, undo_add)
+    else:
+        do_add.call()
+
+    return _items_by_id.get(String(data["id"]), null)
+
+
 func delete_selected(record_undo: bool = true) -> void:
     if _selection.is_empty():
         return
@@ -254,6 +295,8 @@ func delete_selected(record_undo: bool = true) -> void:
                 _add_sprite_direct(data, snapshot["image"])
             elif _is_batch_card_data(data):
                 _add_batch_direct(data)
+            elif String(data.get("type", "")) == "node":
+                _add_node_direct(data)
         _select_only(_ids_from_snapshots(snapshots))
         _emit_canvas_changed()

@@ -304,6 +347,8 @@ func load_canvas_data(canvas_data: Dictionary) -> void:
             _add_batch_direct(item_data)
         elif item_type == "node" and _is_graph_batch_node_data(item_data):
             _add_batch_direct(item_data)
+        elif item_type == "node":
+            _add_node_direct(item_data)

     _suppress_change_signal = false
     _update_layer_transform()
@@ -322,6 +367,8 @@ func export_canvas_data() -> Dictionary:
             items.append(node.to_canvas_data())
         elif node.get_script() == CanvasBatchCardScript:
             items.append(node.to_canvas_data())
+        elif node.get_script() == CanvasNodeCardScript:
+            items.append(node.to_canvas_data())

     return {
         "camera":
@@ -454,13 +501,13 @@ func _replace_batch_asset_ids(
     var before: Array = item.asset_ids.duplicate()
     var after := new_asset_ids.duplicate()
     var do_replace := func() -> void:
-        _apply_batch_asset_ids(item, after)
-        _sync_batch_node_asset_ids(item, after)
+        GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
+        GraphItemBridge.sync_batch_node_asset_ids(item, after)
         _select_only([card_id])
         _emit_canvas_changed()
     var undo_replace := func() -> void:
-        _apply_batch_asset_ids(item, before)
-        _sync_batch_node_asset_ids(item, before)
+        GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
+        GraphItemBridge.sync_batch_node_asset_ids(item, before)
         _select_only([card_id])
         _emit_canvas_changed()
     if record_undo:
@@ -469,44 +516,6 @@ func _replace_batch_asset_ids(
         do_replace.call()


-func _apply_batch_asset_ids(item: Node, asset_ids: Array) -> void:
-    for asset_id in item.asset_ids:
-        AssetLibrary.release_ref(asset_id)
-    item.set_asset_ids(asset_ids)
-    for asset_id in item.asset_ids:
-        AssetLibrary.add_ref(asset_id)
-
-
-func _sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
-    if not item.has_method("has_graph_binding") or not item.has_graph_binding():
-        return
-
-    var graph_data := ProjectService.get_graph_data(item.graph_id)
-    if graph_data.is_empty():
-        return
-
-    var nodes := []
-    var changed := false
-    for raw_node in graph_data.get("nodes", []):
-        if not (raw_node is Dictionary):
-            nodes.append(raw_node)
-            continue
-        var node_data: Dictionary = raw_node
-        if (
-            String(node_data.get("id", "")) == item.node_id
-            and String(node_data.get("type", "")) == "batch"
-        ):
-            var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
-            params["asset_ids"] = _string_array(asset_ids)
-            node_data["params"] = params
-            changed = true
-        nodes.append(node_data)
-
-    if changed:
-        graph_data["nodes"] = nodes
-        ProjectService.set_graph_data(item.graph_id, graph_data, true)
-
-
 func _split_batch_selection(card_id: String) -> Node:
     if not _items_by_id.has(card_id):
         return null
@@ -731,6 +740,16 @@ func _add_batch_direct(item_data: Dictionary) -> Node:
     return item


+func _add_node_direct(item_data: Dictionary) -> Node:
+    var item: Node = CanvasNodeCardScript.new()
+    item.setup_from_data(item_data)
+    item_layer.add_child(item)
+    _items_by_id[item.item_id] = item
+    _update_item_visibility()
+    queue_redraw()
+    return item
+
+
 func _is_batch_card_data(item_data: Dictionary) -> bool:
     var item_type := String(item_data.get("type", ""))
     return (
@@ -739,21 +758,7 @@ func _is_batch_card_data(item_data: Dictionary) -> bool:


 func _is_graph_batch_node_data(item_data: Dictionary) -> bool:
-    if String(item_data.get("type", "")) != "node":
-        return false
-    var graph_id := String(item_data.get("graph_id", ""))
-    var node_id := String(item_data.get("node_id", ""))
-    if graph_id.is_empty() or node_id.is_empty():
-        return false
-
-    var graph_data := ProjectService.get_graph_data(graph_id)
-    for raw_node in graph_data.get("nodes", []):
-        if not (raw_node is Dictionary):
-            continue
-        var node_data: Dictionary = raw_node
-        if String(node_data.get("id", "")) == node_id:
-            return String(node_data.get("type", "")) == "batch"
-    return false
+    return GraphItemBridge.is_graph_batch_node_data(item_data)


 func _remove_item_direct(item_id: String) -> void:
@@ -783,6 +788,7 @@ func _item_at_world(world_position: Vector2) -> Node:
             (
                 item.get_script() == CanvasItemSpriteScript
                 or item.get_script() == CanvasBatchCardScript
+                or item.get_script() == CanvasNodeCardScript
             )
             and item.visible
             and item.contains_world_point(world_position)
@@ -833,16 +839,6 @@ func _ids_from_snapshots(snapshots: Array) -> Array:
     return ids


-func _string_array(value: Variant) -> Array[String]:
-    var result: Array[String] = []
-    if value is Array:
-        for item in Array(value):
-            var id := String(item)
-            if not id.is_empty():
-                result.append(id)
-    return result
-
-
 func _set_zoom_to_value(value: float) -> void:
     var nearest_index := 0
     var nearest_distance := INF
@@ -916,6 +912,12 @@ func _draw_pixel_grid() -> void:
     PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))


+func _draw_graph_edges() -> void:
+    GraphEdgeRenderer.draw(
+        self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, EDGE_COLOR
+    )
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
-    var card: Node = _canvas._add_batch_card(
-        asset_ids,
-        _canvas.get_mouse_world_position(),
-        Strings.MOCK_BATCH_LABEL,
-        "",
-        true,
-        graph.id,
-        "batch_1"
-    )
-    if card != null:
-        _focus_canvas_on_card(card)
+    var items := _add_mock_graph_canvas_items(graph, asset_ids, _canvas.get_mouse_world_position())
+    if not items.is_empty():
+        _focus_canvas_on_bounds(_bounds_for_items(items))
     _status_label.text = Strings.STATUS_MOCK_GENERATE_DONE % asset_ids.size()


@@ -386,7 +378,10 @@ func _emit_batch_export(asset_ids: Array) -> void:


 func _focus_canvas_on_card(card: Node) -> void:
-    var bounds: Rect2 = card.get_canvas_bounds()
+    _focus_canvas_on_bounds(card.get_canvas_bounds())
+
+
+func _focus_canvas_on_bounds(bounds: Rect2) -> void:
     if (
         bounds.size.x <= 0.0
         or bounds.size.y <= 0.0
@@ -401,6 +396,13 @@ func _focus_canvas_on_card(card: Node) -> void:
     _canvas.pan_by_pixels(_canvas.world_to_screen(bounds.get_center()) - _canvas.size * 0.5)


+func _bounds_for_items(items: Array) -> Rect2:
+    var bounds: Rect2 = items[0].get_canvas_bounds()
+    for index in range(1, items.size()):
+        bounds = bounds.merge(items[index].get_canvas_bounds())
+    return bounds
+
+
 func _single_selected_image() -> Image:
     var snapshots: Array = _canvas.get_selected_sprite_snapshots()
     if snapshots.size() != 1:
@@ -448,16 +450,16 @@ func _make_mock_generate_graph() -> PFGraph:
         SizeSpecNodeScript.new(),
         "size",
         {"width": 32, "height": 32, "per_subject": 1},
-        Vector2(220, 0)
+        Vector2(0, 150)
     )
     graph.add_node(
         AiGenerateNodeScript.new(),
         "generate",
         {"provider_id": "mock", "batch_size": 2, "seed": 1000},
-        Vector2(440, 0)
+        Vector2(280, 75)
     )
     graph.add_node(
-        BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(660, 0)
+        BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(560, -20)
     )
     graph.add_edge("objects", "items", "generate", "items")
     graph.add_edge("size", "spec", "generate", "spec")
@@ -465,6 +467,34 @@ func _make_mock_generate_graph() -> PFGraph:
     return graph


+func _add_mock_graph_canvas_items(graph: PFGraph, asset_ids: Array, anchor: Vector2) -> Array:
+    var items := []
+    for node_id in ["objects", "size", "generate"]:
+        var node_item: Node = _canvas._add_graph_node_card(
+            graph.id, node_id, anchor + _graph_node_position(graph, node_id), "", false
+        )
+        if node_item != null:
+            items.append(node_item)
+    var batch_card: Node = _canvas._add_batch_card(
+        asset_ids,
+        anchor + _graph_node_position(graph, "batch_1"),
+        Strings.MOCK_BATCH_LABEL,
+        "",
+        false,
+        graph.id,
+        "batch_1"
+    )
+    if batch_card != null:
+        items.append(batch_card)
+    return items
+
+
+func _graph_node_position(graph: PFGraph, node_id: String) -> Vector2:
+    var node_data: Dictionary = graph.nodes.get(node_id, {})
+    var raw_position: Variant = node_data.get("position", [0, 0])
+    return Vector2(float(raw_position[0]), float(raw_position[1])).round()
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
+    match operation:
+        OP_CLEANUP:
+            return _apply_cleanup(source, params)
+        OP_MATTING:
+            return _apply_matting(source, params)
+        OP_OUTLINE:
+            return _apply_outline(source, params)
+        _:
+            return {"ok": false, "error": "unsupported_operation", "operation": operation}
+
+
+static func apply_to_assets(
+    asset_ids: Array,
+    asset_library: Node,
+    operation: String,
+    params: Dictionary = {},
+    cancel_check: Callable = Callable(),
+    progress: Callable = Callable()
+) -> Dictionary:
+    var ids := _string_array(asset_ids)
+    var results := []
+    for index in range(ids.size()):
+        if cancel_check.is_valid() and bool(cancel_check.call()):
+            return {"canceled": true, "items": results}
+
+        var asset_id := String(ids[index])
+        var image: Image = asset_library.get_image(asset_id)
+        if image == null:
+            continue
+
+        var item_result := apply_image(operation, image, params)
+        if bool(item_result.get("ok", false)):
+            item_result["parent_asset"] = asset_id
+            results.append(item_result)
+
+        if progress.is_valid():
+            progress.call(float(index + 1) / float(maxi(1, ids.size())), operation)
+    return {"canceled": false, "items": results}
+
+
+static func register_result_asset(
+    asset_library: Node, parent_asset_id: String, item_result: Dictionary
+) -> String:
+    var parent_id := String(item_result.get("parent_asset", parent_asset_id))
+    var suffix := String(item_result.get("name_suffix", item_result.get("suffix", "operation")))
+    return (
+        asset_library
+        . register_image(
+            item_result["image"],
+            "%s_%s" % [parent_id.left(8), suffix],
+            {
+                "origin": String(item_result.get("origin", "edited")),
+                "tags": item_result.get("tags", []),
+                "provenance": make_provenance(parent_id, item_result),
+            }
+        )
+    )
+
+
+static func make_provenance(parent_asset_id: String, item_result: Dictionary) -> Dictionary:
+    var provenance_key := String(item_result.get("provenance_key", "operation"))
+    var operation_report: Variant = json_safe(item_result.get("report", {}))
+    if operation_report is Dictionary:
+        var report_dict: Dictionary = operation_report
+        if not report_dict.has("source_asset"):
+            report_dict["source_asset"] = parent_asset_id
+        operation_report = report_dict
+
+    var provenance := {
+        "provider": null,
+        "model": null,
+        "prompt": "",
+        "seed": null,
+        "parent_asset": parent_asset_id,
+        "graph_id": null,
+        "created_at": IdUtil.utc_now_iso(),
+    }
+    provenance[provenance_key] = operation_report
+    return provenance
+
+
+static func normalize_matte_params(params: Dictionary) -> Dictionary:
+    if params.is_empty():
+        return {"mode": Matting.MODE_FLOOD, "tolerance": 12.0, "feather": 0}
+    return {
+        "mode": String(params.get("mode", Matting.MODE_FLOOD)),
+        "tolerance": float(params.get("tolerance", 12.0)),
+        "feather": int(params.get("feather", 0)),
+    }
+
+
+static func normalize_outline_params(params: Dictionary) -> Dictionary:
+    if params.is_empty():
+        return {"type": Outliner.TYPE_OUTER, "color": Color.BLACK, "corner": Outliner.CORNER_CROSS}
+    return {
+        "type": String(params.get("type", Outliner.TYPE_OUTER)),
+        "color": params.get("color", Color.BLACK),
+        "corner": String(params.get("corner", Outliner.CORNER_CROSS)),
+        "colored": bool(params.get("colored", false)),
+    }
+
+
+static func json_safe(value: Variant) -> Variant:
+    match typeof(value):
+        TYPE_DICTIONARY:
+            var output := {}
+            for key in Dictionary(value).keys():
+                output[String(key)] = json_safe(Dictionary(value)[key])
+            return output
+        TYPE_ARRAY:
+            var output := []
+            for item in Array(value):
+                output.append(json_safe(item))
+            return output
+        TYPE_VECTOR2:
+            var vector := Vector2(value)
+            return [vector.x, vector.y]
+        TYPE_VECTOR2I:
+            var vector_i := Vector2i(value)
+            return [vector_i.x, vector_i.y]
+        TYPE_RECT2I:
+            var rect := Rect2i(value)
+            return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
+        TYPE_COLOR:
+            return Color(value).to_html(true)
+        _:
+            return value
+
+
+static func _apply_cleanup(source: Image, params: Dictionary) -> Dictionary:
+    var normalized := Pipeline.normalize_params(params)
+    var cleanup_result := Pipeline.apply(source, normalized)
+    return {
+        "ok": true,
+        "operation": OP_CLEANUP,
+        "image": cleanup_result["image"],
+        "suffix": "clean",
+        "name_suffix": "clean",
+        "origin": "edited",
+        "tags": ["cleanup"],
+        "provenance_key": "cleanup",
+        "report":
+        {
+            "params": json_safe(normalized),
+            "report": json_safe(cleanup_result.get("report", {})),
+        },
+    }
+
+
+static func _apply_matting(source: Image, params: Dictionary) -> Dictionary:
+    var normalized := normalize_matte_params(params)
+    var matting_result: Dictionary = Matting.matte(source, normalized)
+    # Provenance must stay JSON-safe; the generated Image is stored as an asset, not in metadata.
+    var report := matting_result.duplicate(true)
+    report.erase("image")
+    report["params"] = json_safe(normalized)
+    return {
+        "ok": true,
+        "operation": OP_MATTING,
+        "image": matting_result["image"],
+        "suffix": "matte",
+        "name_suffix": "matte",
+        "origin": "edited",
+        "tags": ["matting"],
+        "provenance_key": "matting",
+        "report": json_safe(report),
+        "warning": String(matting_result.get("warning", "")),
+    }
+
+
+static func _apply_outline(source: Image, params: Dictionary) -> Dictionary:
+    var normalized := normalize_outline_params(params)
+    return {
+        "ok": true,
+        "operation": OP_OUTLINE,
+        "image": Outliner.add_outline(source, normalized),
+        "suffix": "outline",
+        "name_suffix": "outline",
+        "origin": "edited",
+        "tags": ["outline"],
+        "provenance_key": "outline",
+        "report": json_safe(normalized),
+    }
+
+
+static func _string_array(value: Variant) -> Array[String]:
+    var result: Array[String] = []
+    if value is Array:
+        for item in Array(value):
+            var id := String(item)
+            if not id.is_empty():
+                result.append(id)
+    return result
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
-    var graph_data: Dictionary = ProjectService.current_project.graphs.values()[0]
+    var graph_id := String(ProjectService.current_project.graphs.keys()[0])
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
     var batch_node: Dictionary = graph_data["nodes"][3]
     assert_eq(batch_node["type"], "batch")
     assert_eq(batch_node["params"]["asset_ids"].size(), 10)
+    var canvas_item: Dictionary = canvas.export_canvas_data()["items"][0]
+    assert_eq(canvas_item["type"], "node")
+    assert_eq(canvas_item["graph_id"], graph_id)
+    assert_eq(canvas_item["node_id"], "batch_1")
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
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var graph := GraphScript.new()
+    graph.id = "graph_batch_test"
+    graph.add_node(
+        BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var card: Node = canvas._add_batch_card(
+        ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+    )
+    assert_eq(card.asset_ids, ids)
+
+    var canvas_data: Dictionary = canvas.export_canvas_data()
+    var item: Dictionary = canvas_data["items"][0]
+    assert_eq(item["type"], "node")
+    assert_eq(item["graph_id"], graph.id)
+    assert_eq(item["node_id"], "batch_1")
+    assert_false(item.has("asset_ids"))
+
+    var green_id := _register_asset(Color.GREEN, "green")
+    canvas._replace_batch_asset_ids("node_item_1", [green_id], false)
+
+    assert_eq(card.asset_ids, [green_id])
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+    var batch_node: Dictionary = graph_data["nodes"][0]
+    assert_eq(batch_node["params"]["asset_ids"], [green_id])
+
+    var reloaded_canvas: Control = CanvasScript.new()
+    reloaded_canvas.size = Vector2(512, 512)
+    add_child_autofree(reloaded_canvas)
+    await wait_process_frames(2)
+    reloaded_canvas.load_canvas_data(canvas_data)
+
+    assert_eq(reloaded_canvas.get_item_count(), 1)
+    assert_eq(reloaded_canvas._get_batch_asset_ids("node_item_1"), [green_id])
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
+    get_tree().root.get_node("ProjectService").new_project("Pixel Operations")
+
+
+func test_cleanup_operation_processes_assets_and_registers_provenance() -> void:
+    var source_id := AssetLibrary.register_image(
+        _make_source_image(), "source", {"origin": "imported"}
+    )
+    var result: Dictionary = PixelOperations.apply_to_assets(
+        [source_id], AssetLibrary, PixelOperations.OP_CLEANUP, _disabled_cleanup_params()
+    )
+
+    assert_false(bool(result.get("canceled", false)))
+    assert_eq(result["items"].size(), 1)
+
+    var output_id := PixelOperations.register_result_asset(
+        AssetLibrary, source_id, result["items"][0]
+    )
+    var meta := AssetLibrary.get_asset_meta(output_id)
+    var provenance: Dictionary = meta["provenance"]
+
+    assert_eq(meta["origin"], "edited")
+    assert_eq(meta["tags"], ["cleanup"])
+    assert_eq(provenance["parent_asset"], source_id)
+    assert_eq(provenance["cleanup"]["source_asset"], source_id)
+    assert_true(provenance["cleanup"].has("params"))
+    assert_true(provenance["cleanup"].has("report"))
+
+
+func test_matting_report_is_metadata_safe() -> void:
+    var result: Dictionary = PixelOperations.apply_image(
+        PixelOperations.OP_MATTING, _make_source_image(), {}
+    )
+    var report: Dictionary = result["report"]
+
+    assert_true(bool(result.get("ok", false)))
+    assert_false(report.has("image"))
+    assert_eq(String(result.get("provenance_key", "")), "matting")
+
+
+func _make_source_image() -> Image:
+    var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
+    image.fill(Color.WHITE)
+    image.set_pixel(1, 1, Color.RED)
+    image.set_pixel(2, 1, Color.RED)
+    image.set_pixel(1, 2, Color.RED)
+    image.set_pixel(2, 2, Color.RED)
+    return image
+
+
+func _disabled_cleanup_params() -> Dictionary:
+    return {
+        Pipeline.STEP_DETECT_GRID: {"enabled": false},
+        Pipeline.STEP_RESAMPLE: {"enabled": false},
+        Pipeline.STEP_QUANTIZE: {"enabled": false},
+    }
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
-    label = String(data.get("label", "Batch"))
-    asset_ids = _string_array(data.get("asset_ids", []))
+    graph_id = String(data.get("graph_id", ""))
+    node_id = String(data.get("node_id", ""))
+    var graph_node_data := _resolve_graph_batch_node_data()
+    var graph_params: Dictionary = graph_node_data.get("params", {})
+    label = String(graph_params.get("label", data.get("label", "Batch")))
+    asset_ids = _string_array(graph_params.get("asset_ids", data.get("asset_ids", [])))
     selected_asset_ids = _string_array(data.get("selected_asset_ids", []))
     locked = bool(data.get("locked", false))
     z_index = int(data.get("z_index", 0))
@@ -43,6 +49,17 @@ func setup_from_data(data: Dictionary) -> void:


 func to_canvas_data() -> Dictionary:
+    if has_graph_binding():
+        return {
+            "id": item_id,
+            "type": "node",
+            "graph_id": graph_id,
+            "node_id": node_id,
+            "position": [int(round(position.x)), int(round(position.y))],
+            "z_index": z_index,
+            "collapsed": false,
+            "locked": locked,
+        }
     return {
         "id": item_id,
         "type": "batch_card",
@@ -55,6 +72,10 @@ func to_canvas_data() -> Dictionary:
     }


+func has_graph_binding() -> bool:
+    return not graph_id.is_empty() and not node_id.is_empty()
+
+
 func get_canvas_bounds() -> Rect2:
     return Rect2(position, Vector2(CARD_WIDTH, _card_height()))

@@ -184,6 +205,22 @@ func _rebuild_thumbnails() -> void:
         _thumbnail_textures[asset_id] = ImageTexture.create_from_image(thumb)


+func _resolve_graph_batch_node_data() -> Dictionary:
+    if not has_graph_binding():
+        return {}
+    var graph_data := ProjectService.get_graph_data(graph_id)
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            continue
+        var node_data: Dictionary = raw_node
+        if (
+            String(node_data.get("id", "")) == node_id
+            and String(node_data.get("type", "")) == "batch"
+        ):
+            return node_data
+    return {}
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
-    record_undo: bool = true
+    record_undo: bool = true,
+    graph_id: String = "",
+    node_id: String = ""
 ) -> Node:
     var data := {
         "id": item_id if not item_id.is_empty() else IdUtil.uuid_v4(),
-        "type": "batch_card",
+        "type": "node" if not node_id.is_empty() else "batch_card",
         "asset_ids": asset_ids.duplicate(),
         "selected_asset_ids": [],
         "label": label,
+        "graph_id": graph_id,
+        "node_id": node_id,
         "position": [int(round(world_position.x)), int(round(world_position.y))],
         "z_index": _items_by_id.size(),
         "locked": false,
@@ -248,7 +252,7 @@ func delete_selected(record_undo: bool = true) -> void:
             var data: Dictionary = snapshot["data"]
             if String(data.get("type", "")) == "sprite":
                 _add_sprite_direct(data, snapshot["image"])
-            elif String(data.get("type", "")) == "batch_card":
+            elif _is_batch_card_data(data):
                 _add_batch_direct(data)
         _select_only(_ids_from_snapshots(snapshots))
         _emit_canvas_changed()
@@ -298,6 +302,8 @@ func load_canvas_data(canvas_data: Dictionary) -> void:
             _add_sprite_direct(item_data, image)
         elif item_type == "batch_card":
             _add_batch_direct(item_data)
+        elif item_type == "node" and _is_graph_batch_node_data(item_data):
+            _add_batch_direct(item_data)

     _suppress_change_signal = false
     _update_layer_transform()
@@ -448,11 +454,13 @@ func _replace_batch_asset_ids(
     var before: Array = item.asset_ids.duplicate()
     var after := new_asset_ids.duplicate()
     var do_replace := func() -> void:
-        item.set_asset_ids(after)
+        _apply_batch_asset_ids(item, after)
+        _sync_batch_node_asset_ids(item, after)
         _select_only([card_id])
         _emit_canvas_changed()
     var undo_replace := func() -> void:
-        item.set_asset_ids(before)
+        _apply_batch_asset_ids(item, before)
+        _sync_batch_node_asset_ids(item, before)
         _select_only([card_id])
         _emit_canvas_changed()
     if record_undo:
@@ -461,6 +469,44 @@ func _replace_batch_asset_ids(
         do_replace.call()


+func _apply_batch_asset_ids(item: Node, asset_ids: Array) -> void:
+    for asset_id in item.asset_ids:
+        AssetLibrary.release_ref(asset_id)
+    item.set_asset_ids(asset_ids)
+    for asset_id in item.asset_ids:
+        AssetLibrary.add_ref(asset_id)
+
+
+func _sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
+    if not item.has_method("has_graph_binding") or not item.has_graph_binding():
+        return
+
+    var graph_data := ProjectService.get_graph_data(item.graph_id)
+    if graph_data.is_empty():
+        return
+
+    var nodes := []
+    var changed := false
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            nodes.append(raw_node)
+            continue
+        var node_data: Dictionary = raw_node
+        if (
+            String(node_data.get("id", "")) == item.node_id
+            and String(node_data.get("type", "")) == "batch"
+        ):
+            var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
+            params["asset_ids"] = _string_array(asset_ids)
+            node_data["params"] = params
+            changed = true
+        nodes.append(node_data)
+
+    if changed:
+        graph_data["nodes"] = nodes
+        ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
 func _split_batch_selection(card_id: String) -> Node:
     if not _items_by_id.has(card_id):
         return null
@@ -685,6 +731,31 @@ func _add_batch_direct(item_data: Dictionary) -> Node:
     return item


+func _is_batch_card_data(item_data: Dictionary) -> bool:
+    var item_type := String(item_data.get("type", ""))
+    return (
+        item_type == "batch_card" or (item_type == "node" and _is_graph_batch_node_data(item_data))
+    )
+
+
+func _is_graph_batch_node_data(item_data: Dictionary) -> bool:
+    if String(item_data.get("type", "")) != "node":
+        return false
+    var graph_id := String(item_data.get("graph_id", ""))
+    var node_id := String(item_data.get("node_id", ""))
+    if graph_id.is_empty() or node_id.is_empty():
+        return false
+
+    var graph_data := ProjectService.get_graph_data(graph_id)
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            continue
+        var node_data: Dictionary = raw_node
+        if String(node_data.get("id", "")) == node_id:
+            return String(node_data.get("type", "")) == "batch"
+    return false
+
+
 func _remove_item_direct(item_id: String) -> void:
     if not _items_by_id.has(item_id):
         return
@@ -762,6 +833,16 @@ func _ids_from_snapshots(snapshots: Array) -> Array:
     return ids


+func _string_array(value: Variant) -> Array[String]:
+    var result: Array[String] = []
+    if value is Array:
+        for item in Array(value):
+            var id := String(item)
+            if not id.is_empty():
+                result.append(id)
+    return result
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
-        asset_ids, _canvas.get_mouse_world_position(), Strings.MOCK_BATCH_LABEL, "", true
+        asset_ids,
+        _canvas.get_mouse_world_position(),
+        Strings.MOCK_BATCH_LABEL,
+        "",
+        true,
+        graph.id,
+        "batch_1"
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
-        var matting_result: Dictionary = Matting.matte(item["image"], params)
-        (
-            results
-            . append(
-                {
-                    "source_data": item["data"],
-                    "image": matting_result["image"],
-                    "suffix": "matte",
-                    "tags": ["matting"],
-                    "provenance_key": "matting",
-                    "report": _json_safe(matting_result),
-                    "warning": String(matting_result.get("warning", "")),
-                }
-            )
+        var operation_result: Dictionary = PixelOperations.apply_image(
+            PixelOperations.OP_MATTING, item["image"], params
         )
+        operation_result["source_data"] = item["data"]
+        results.append(operation_result)
         task_ref.report_progress(float(index + 1) / float(items.size()), "matting")
     return {"canceled": false, "items": results}

@@ -215,20 +203,11 @@ func _outline_work(task_ref: Variant) -> Dictionary:
         if task_ref.cancel_requested:
             return {"canceled": true, "items": results}
         var item: Dictionary = items[index]
-        var output: Image = Outliner.add_outline(item["image"], params)
-        (
-            results
-            . append(
-                {
-                    "source_data": item["data"],
-                    "image": output,
-                    "suffix": "outline",
-                    "tags": ["outline"],
-                    "provenance_key": "outline",
-                    "report": _json_safe(params),
-                }
-            )
+        var operation_result: Dictionary = PixelOperations.apply_image(
+            PixelOperations.OP_OUTLINE, item["image"], params
         )
+        operation_result["source_data"] = item["data"]
+        results.append(operation_result)
         task_ref.report_progress(float(index + 1) / float(items.size()), "outline")
     return {"canceled": false, "items": results}

@@ -236,104 +215,49 @@ func _outline_work(task_ref: Variant) -> Dictionary:
 func _batch_cleanup_work(task_ref: Variant) -> Dictionary:
     var asset_ids: Array = task_ref.payload["asset_ids"]
     var params: Dictionary = task_ref.payload["extra"].get("params", {})
-    var results := []
-    for index in range(asset_ids.size()):
-        if task_ref.cancel_requested:
-            return {
-                "canceled": true, "card_id": String(task_ref.payload["card_id"]), "items": results
-            }
-        var asset_id := String(asset_ids[index])
-        var image := AssetLibrary.get_image(asset_id)
-        if image == null:
-            continue
-        var pipeline_result := Pipeline.apply(image, params)
-        (
-            results
-            . append(
-                {
-                    "parent_asset": asset_id,
-                    "image": pipeline_result["image"],
-                    "name_suffix": "clean",
-                    "origin": "edited",
-                    "tags": ["cleanup"],
-                    "provenance_key": "cleanup",
-                    "report":
-                    _json_safe(
-                        {
-                            "source_asset": asset_id,
-                            "params": params,
-                            "report": pipeline_result.get("report", {}),
-                        }
-                    ),
-                }
-            )
-        )
-        task_ref.report_progress(float(index + 1) / float(asset_ids.size()), "batch_cleanup")
-    return {"canceled": false, "card_id": String(task_ref.payload["card_id"]), "items": results}
+    var result := PixelOperations.apply_to_assets(
+        asset_ids,
+        AssetLibrary,
+        PixelOperations.OP_CLEANUP,
+        params,
+        func() -> bool: return task_ref.cancel_requested,
+        func(ratio: float, _operation: String) -> void:
+            task_ref.report_progress(ratio, "batch_cleanup")
+    )
+    result["card_id"] = String(task_ref.payload["card_id"])
+    return result


 func _batch_matte_work(task_ref: Variant) -> Dictionary:
     var asset_ids: Array = task_ref.payload["asset_ids"]
     var params: Dictionary = _matte_params(task_ref.payload["extra"].get("params", {}))
-    var results := []
-    for index in range(asset_ids.size()):
-        if task_ref.cancel_requested:
-            return {
-                "canceled": true, "card_id": String(task_ref.payload["card_id"]), "items": results
-            }
-        var asset_id := String(asset_ids[index])
-        var image := AssetLibrary.get_image(asset_id)
-        if image == null:
-            continue
-        var matting_result: Dictionary = Matting.matte(image, params)
-        (
-            results
-            . append(
-                {
-                    "parent_asset": asset_id,
-                    "image": matting_result["image"],
-                    "name_suffix": "matte",
-                    "origin": "edited",
-                    "tags": ["matting"],
-                    "provenance_key": "matting",
-                    "report": _json_safe(matting_result),
-                    "warning": String(matting_result.get("warning", "")),
-                }
-            )
-        )
-        task_ref.report_progress(float(index + 1) / float(asset_ids.size()), "batch_matting")
-    return {"canceled": false, "card_id": String(task_ref.payload["card_id"]), "items": results}
+    var result := PixelOperations.apply_to_assets(
+        asset_ids,
+        AssetLibrary,
+        PixelOperations.OP_MATTING,
+        params,
+        func() -> bool: return task_ref.cancel_requested,
+        func(ratio: float, _operation: String) -> void:
+            task_ref.report_progress(ratio, "batch_matting")
+    )
+    result["card_id"] = String(task_ref.payload["card_id"])
+    return result


 func _batch_outline_work(task_ref: Variant) -> Dictionary:
     var asset_ids: Array = task_ref.payload["asset_ids"]
     var params: Dictionary = _outline_params(task_ref.payload["extra"].get("params", {}))
-    var results := []
-    for index in range(asset_ids.size()):
-        if task_ref.cancel_requested:
-            return {
-                "canceled": true, "card_id": String(task_ref.payload["card_id"]), "items": results
-            }
-        var asset_id := String(asset_ids[index])
-        var image := AssetLibrary.get_image(asset_id)
-        if image == null:
-            continue
-        (
-            results
-            . append(
-                {
-                    "parent_asset": asset_id,
-                    "image": Outliner.add_outline(image, params),
-                    "name_suffix": "outline",
-                    "origin": "edited",
-                    "tags": ["outline"],
-                    "provenance_key": "outline",
-                    "report": _json_safe(params),
-                }
-            )
-        )
-        task_ref.report_progress(float(index + 1) / float(asset_ids.size()), "batch_outline")
-    return {"canceled": false, "card_id": String(task_ref.payload["card_id"]), "items": results}
+    var result := PixelOperations.apply_to_assets(
+        asset_ids,
+        AssetLibrary,
+        PixelOperations.OP_OUTLINE,
+        params,
+        func() -> bool: return task_ref.cancel_requested,
+        func(ratio: float, _operation: String) -> void:
+            task_ref.report_progress(ratio, "batch_outline")
+    )
+    result["card_id"] = String(task_ref.payload["card_id"])
+    return result


 func _on_generated_asset_task_finished(result: Variant, done_status: String) -> void:
@@ -356,30 +280,8 @@ func _on_generated_asset_task_finished(result: Variant, done_status: String) ->
         var source_width := _source_width_for_canvas_data(source_data, output)
         var placement_index := int(placement_offsets.get(parent_asset_id, 0))
         placement_offsets[parent_asset_id] = placement_index + 1
-
-        var provenance_key := String(item_result.get("provenance_key", "operation"))
-        var provenance := {
-            "provider": null,
-            "model": null,
-            "prompt": "",
-            "seed": null,
-            "parent_asset": parent_asset_id,
-            "graph_id": null,
-            "created_at": IdUtil.utc_now_iso(),
-        }
-        provenance[provenance_key] = _json_safe(item_result.get("report", {}))
-
-        var asset_id := (
-            AssetLibrary
-            . register_image(
-                output,
-                "%s_%s" % [parent_asset_id.left(8), String(item_result.get("suffix", "m2"))],
-                {
-                    "origin": "edited",
-                    "tags": item_result.get("tags", []),
-                    "provenance": provenance,
-                }
-            )
+        var asset_id := PixelOperations.register_result_asset(
+            AssetLibrary, parent_asset_id, item_result
         )
         var world_position := (
             source_position
@@ -431,32 +333,8 @@ func _on_batch_task_finished(result: Variant, done_status: String) -> void:
     var new_asset_ids: Array[String] = []
     for item_result in result.get("items", []):
         var parent_asset_id := String(item_result.get("parent_asset", ""))
-        var output: Image = item_result["image"]
-        var provenance_key := String(item_result.get("provenance_key", "operation"))
-        var provenance := {
-            "provider": null,
-            "model": null,
-            "prompt": "",
-            "seed": null,
-            "parent_asset": parent_asset_id,
-            "graph_id": null,
-            "created_at": IdUtil.utc_now_iso(),
-        }
-        provenance[provenance_key] = _json_safe(item_result.get("report", {}))
-        var asset_id := (
-            AssetLibrary
-            . register_image(
-                output,
-                (
-                    "%s_%s"
-                    % [parent_asset_id.left(8), String(item_result.get("name_suffix", "batch"))]
-                ),
-                {
-                    "origin": String(item_result.get("origin", "edited")),
-                    "tags": item_result.get("tags", []),
-                    "provenance": provenance,
-                }
-            )
+        var asset_id := PixelOperations.register_result_asset(
+            AssetLibrary, parent_asset_id, item_result
         )
         new_asset_ids.append(asset_id)

@@ -465,13 +343,7 @@ func _on_batch_task_finished(result: Variant, done_status: String) -> void:


 func _matte_params(params: Dictionary) -> Dictionary:
-    if params.is_empty():
-        return {"mode": Matting.MODE_FLOOD, "tolerance": 12.0, "feather": 0}
-    return {
-        "mode": String(params.get("mode", Matting.MODE_FLOOD)),
-        "tolerance": float(params.get("tolerance", 12.0)),
-        "feather": int(params.get("feather", 0)),
-    }
+    return PixelOperations.normalize_matte_params(params)


 func _slice_params(params: Dictionary) -> Dictionary:
@@ -494,14 +366,7 @@ func _slice_params(params: Dictionary) -> Dictionary:


 func _outline_params(params: Dictionary) -> Dictionary:
-    if params.is_empty():
-        return {"type": Outliner.TYPE_OUTER, "color": Color.BLACK, "corner": Outliner.CORNER_CROSS}
-    return {
-        "type": String(params.get("type", Outliner.TYPE_OUTER)),
-        "color": params.get("color", Color.BLACK),
-        "corner": String(params.get("corner", Outliner.CORNER_CROSS)),
-        "colored": bool(params.get("colored", false)),
-    }
+    return PixelOperations.normalize_outline_params(params)


 func _first_warning(items: Array) -> String:
@@ -536,29 +401,3 @@ static func _source_width_for_canvas_data(data: Dictionary, fallback_image: Imag

 static func _rect_to_array(rect: Rect2i) -> Array:
     return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
-
-
-static func _json_safe(value: Variant) -> Variant:
-    match typeof(value):
-        TYPE_DICTIONARY:
-            var output := {}
-            for key in Dictionary(value).keys():
-                output[String(key)] = _json_safe(Dictionary(value)[key])
-            return output
-        TYPE_ARRAY:
-            var output := []
-            for item in Array(value):
-                output.append(_json_safe(item))
-            return output
-        TYPE_VECTOR2:
-            var vector := Vector2(value)
-            return [vector.x, vector.y]
-        TYPE_VECTOR2I:
-            var vector_i := Vector2i(value)
-            return [vector_i.x, vector_i.y]
-        TYPE_RECT2I:
-            return _rect_to_array(Rect2i(value))
-        TYPE_COLOR:
-            return Color(value).to_html(true)
-        _:
-            return value
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
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red")]
+    var graph := GraphScript.new()
+    graph.id = "graph_anchor_test"
+    graph.add_node(
+        AiGenerateNodeScript.new(),
+        "generate",
+        {"provider_id": "mock", "batch_size": 1, "seed": 3},
+        Vector2(10, 20)
+    )
+    graph.add_node(
+        BatchNodeScript.new(),
+        "batch_1",
+        {"label": "Candidates", "asset_ids": ids},
+        Vector2(300, 69)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var generate_card: Node = canvas._add_graph_node_card(
+        graph.id, "generate", Vector2(10, 20), "node_item_generate", false
+    )
+    var batch_card: Node = canvas._add_batch_card(
+        ids, Vector2(300, 69), "Candidates", "node_item_batch", false, graph.id, "batch_1"
+    )
+
+    var items_anchor: Vector2 = generate_card.get_graph_port_anchor("items", true)
+    var spec_anchor: Vector2 = generate_card.get_graph_port_anchor("spec", true)
+    var output_anchor: Vector2 = generate_card.get_graph_port_anchor("images", false)
+    var right_center: Vector2 = (
+        generate_card.get_canvas_bounds().position
+        + Vector2(
+            generate_card.get_canvas_bounds().size.x, generate_card.get_canvas_bounds().size.y * 0.5
+        )
+    )
+
+    assert_ne(items_anchor, spec_anchor)
+    assert_ne(output_anchor, right_center)
+    assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "images", false), output_anchor)
+    assert_eq(
+        GraphEdgeRenderer._edge_anchor_world(batch_card, "in", true),
+        batch_card.get_graph_port_anchor("in", true)
+    )
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
+    var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
+    var count := ports.size()
+    if count <= 0:
+        return position + Vector2(0.0 if is_input else CARD_WIDTH, _card_height() * 0.5)
+    var index := ports.find(port_name)
+    if index < 0:
+        index = 0
+    return position + _graph_port_position(index, count, is_input)
+
+
 func set_asset_ids(new_asset_ids: Array) -> void:
     asset_ids = _string_array(new_asset_ids)
     for selected_id in selected_asset_ids.duplicate():
@@ -146,6 +161,8 @@ func _draw() -> void:
     var columns := _columns()
     for index in range(asset_ids.size()):
         _draw_thumbnail(index, _thumb_rect(index, columns))
+    if has_graph_binding():
+        _draw_graph_ports()


 func _draw_thumbnail(index: int, rect: Rect2) -> void:
@@ -187,6 +204,21 @@ func _columns() -> int:
     return maxi(1, int((CARD_WIDTH - PADDING * 2 + THUMB_GAP) / (THUMB_SIZE + THUMB_GAP)))


+func _draw_graph_ports() -> void:
+    for index in range(INPUT_PORTS.size()):
+        draw_circle(_graph_port_position(index, INPUT_PORTS.size(), true), 5.0, PORT_IN)
+    for index in range(OUTPUT_PORTS.size()):
+        draw_circle(_graph_port_position(index, OUTPUT_PORTS.size(), false), 5.0, PORT_OUT)
+
+
+func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:
+    var lane_height := minf(
+        THUMB_SIZE, maxf(0.0, float(_card_height()) - HEADER_HEIGHT - PADDING * 2)
+    )
+    var y := HEADER_HEIGHT + PADDING + lane_height * float(index + 1) / float(count + 1)
+    return Vector2(0.0 if is_input else CARD_WIDTH, y)
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
-    _draw_graph_edge(canvas, items_by_node[from_node], items_by_node[to_node], color)
+    _draw_graph_edge(
+        canvas,
+        items_by_node[from_node],
+        String(from_data[1]),
+        items_by_node[to_node],
+        String(to_data[1]),
+        color
+    )


-static func _draw_graph_edge(canvas: Control, from_item: Node, to_item: Node, color: Color) -> void:
-    var from_bounds: Rect2 = from_item.get_canvas_bounds()
-    var to_bounds: Rect2 = to_item.get_canvas_bounds()
-    var start: Vector2 = canvas.world_to_screen(
-        from_bounds.position + Vector2(from_bounds.size.x, from_bounds.size.y * 0.5)
-    )
-    var end: Vector2 = canvas.world_to_screen(
-        to_bounds.position + Vector2(0.0, to_bounds.size.y * 0.5)
-    )
+static func _draw_graph_edge(
+    canvas: Control,
+    from_item: Node,
+    from_port: String,
+    to_item: Node,
+    to_port: String,
+    color: Color
+) -> void:
+    var start_world: Variant = _edge_anchor_world(from_item, from_port, false)
+    var end_world: Variant = _edge_anchor_world(to_item, to_port, true)
+    if not (start_world is Vector2) or not (end_world is Vector2):
+        return
+    var start: Vector2 = canvas.world_to_screen(start_world)
+    var end: Vector2 = canvas.world_to_screen(end_world)
     var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
     var control_a := start + Vector2(bend, 0.0)
     var control_b := end - Vector2(bend, 0.0)
@@ -52,6 +64,13 @@ static func _draw_graph_edge(canvas: Control, from_item: Node, to_item: Node, co
     canvas.draw_polyline(points, color, 2.0, true)


+static func _edge_anchor_world(item: Node, port_name: String, is_input: bool) -> Variant:
+    if item.has_method("get_graph_port_anchor"):
+        return item.get_graph_port_anchor(port_name, is_input)
+    var bounds: Rect2 = item.get_canvas_bounds()
+    return bounds.position + Vector2(0.0 if is_input else bounds.size.x, bounds.size.y * 0.5)
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
+    var count := _input_count if is_input else _output_count
+    if count <= 0:
+        return position + Vector2(0.0 if is_input else CARD_SIZE.x, CARD_SIZE.y * 0.5)
+    var index := _port_index(port_name, is_input)
+    if index < 0:
+        index = 0
+    return position + _port_position(index, count, is_input)
+
+
 func _draw() -> void:
     _font = ThemeDB.fallback_font if _font == null else _font
     var rect := Rect2(Vector2.ZERO, CARD_SIZE)
@@ -120,6 +132,11 @@ func _port_position(index: int, count: int, is_input: bool) -> Vector2:
     return Vector2(0.0 if is_input else CARD_SIZE.x, y)


+func _port_index(port_name: String, is_input: bool) -> int:
+    var ports := _input_ports if is_input else _output_ports
+    return ports.find(port_name)
+
+
 func _resolve_graph_node() -> void:
     var node_data := _find_node_data()
     _node_type = String(node_data.get("type", "missing"))
@@ -132,14 +149,25 @@ func _resolve_graph_node() -> void:
         _display_name = "Missing: %s" % _node_type
         _input_count = 0
         _output_count = 0
+        _input_ports = []
+        _output_ports = []
         return

     _display_name = node.get_display_name()
-    _input_count = node.get_input_ports().size()
-    _output_count = node.get_output_ports().size()
+    _input_ports = _port_names(node.get_input_ports())
+    _output_ports = _port_names(node.get_output_ports())
+    _input_count = _input_ports.size()
+    _output_count = _output_ports.size()
     _is_ghost = false


+func _port_names(port_specs: Array[Dictionary]) -> Array[String]:
+    var result: Array[String] = []
+    for port_spec in port_specs:
+        result.append(String(port_spec.get("name", "")))
+    return result
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
-        BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(560, -20)
+        BatchNodeScript.new(), "batch_1", {"label": Strings.MOCK_BATCH_LABEL}, Vector2(560, 29)
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

-    assert_ne(items_anchor, spec_anchor)
+    assert_eq(items_anchor, spec_anchor)
     assert_ne(output_anchor, right_center)
+    assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "items", true), items_anchor)
+    assert_eq(GraphEdgeRenderer._edge_anchor_world(generate_card, "spec", true), items_anchor)
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
-    var ports := _input_ports if is_input else _output_ports
+    var ports := _visible_input_ports if is_input else _visible_output_ports
     return ports.find(port_name)


@@ -151,16 +153,27 @@ func _resolve_graph_node() -> void:
         _output_count = 0
         _input_ports = []
         _output_ports = []
+        _visible_input_ports = []
+        _visible_output_ports = []
         return

     _display_name = node.get_display_name()
     _input_ports = _port_names(node.get_input_ports())
     _output_ports = _port_names(node.get_output_ports())
-    _input_count = _input_ports.size()
-    _output_count = _output_ports.size()
+    _visible_input_ports = _visible_input_ports_for_node(_node_type, _input_ports)
+    _visible_output_ports = _output_ports.duplicate()
+    _input_count = _visible_input_ports.size()
+    _output_count = _visible_output_ports.size()
     _is_ghost = false


+func _visible_input_ports_for_node(node_type: String, port_names: Array[String]) -> Array[String]:
+    # M3 画布 MVP 只折叠视觉入口；graph edge 仍保留原始命名端口。
+    if node_type == "ai_generate" and not port_names.is_empty():
+        return ["in"]
+    return port_names.duplicate()
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
+    graph: PFGraph,
+    asset_library: Node,
+    batch_node_id: String = "",
+    replace_batch_assets: bool = false
+) -> Dictionary:
     if graph == null:
         return _error("missing_graph", "Graph is required")
     if asset_library == null or not asset_library.has_method("register_image"):
@@ -22,7 +27,13 @@ func run_to_batch(graph: PFGraph, asset_library: Node, batch_node_id: String = "
     var materialized_asset_ids := []
     for node_id in order_result["order"]:
         var run_result := _run_node(
-            graph, String(node_id), inputs_by_node, outputs_by_node, asset_library, batch_node_id
+            graph,
+            String(node_id),
+            inputs_by_node,
+            outputs_by_node,
+            asset_library,
+            batch_node_id,
+            replace_batch_assets
         )
         if not bool(run_result["ok"]):
             return run_result
@@ -40,7 +51,8 @@ func _run_node(
     inputs_by_node: Dictionary,
     outputs_by_node: Dictionary,
     asset_library: Node,
-    batch_node_id: String
+    batch_node_id: String,
+    replace_batch_assets: bool
 ) -> Dictionary:
     var node := graph.get_node(node_id)
     if node == null:
@@ -54,7 +66,12 @@ func _run_node(
     if node.get_type() == "batch":
         if batch_node_id.is_empty() or batch_node_id == node_id:
             var materialized := _materialize_batch(
-                graph, node_id, inputs.get("in", []), inputs.get("__metadata", []), asset_library
+                graph,
+                node_id,
+                inputs.get("in", []),
+                inputs.get("__metadata", []),
+                asset_library,
+                replace_batch_assets
             )
             if not bool(materialized["ok"]):
                 return materialized
@@ -71,7 +88,12 @@ func _run_node(


 func _materialize_batch(
-    graph: PFGraph, node_id: String, value: Variant, metadata: Variant, asset_library: Node
+    graph: PFGraph,
+    node_id: String,
+    value: Variant,
+    metadata: Variant,
+    asset_library: Node,
+    replace_batch_assets: bool
 ) -> Dictionary:
     var images := _image_array(value)
     if images.is_empty():
@@ -89,7 +111,7 @@ func _materialize_batch(
         asset_ids.append(asset_id)

     var params := graph.get_node_params(node_id)
-    var existing: Array = params.get("asset_ids", [])
+    var existing: Array = [] if replace_batch_assets else _string_array(params.get("asset_ids", []))
     for asset_id in asset_ids:
         existing.append(asset_id)
     params["asset_ids"] = existing
@@ -209,6 +231,16 @@ func _metadata_array(value: Variant) -> Array:
     return result


+func _string_array(value: Variant) -> Array:
+    var result := []
+    if value is Array:
+        for item in value:
+            var id := String(item)
+            if not id.is_empty():
+                result.append(id)
+    return result
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
+    var graph := _make_mock_graph()
+    var asset_library := get_tree().root.get_node("AssetLibrary")
+    var runner := MockRunnerScript.new()
+
+    var first_result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1")
+    assert_true(bool(first_result["ok"]))
+    var first_ids: Array = graph.get_node_params("batch_1")["asset_ids"].duplicate()
+    assert_eq(first_ids.size(), 10)
+
+    var second_result: Dictionary = runner.run_to_batch(graph, asset_library, "batch_1", true)
+    assert_true(bool(second_result["ok"]))
+    var second_ids: Array = graph.get_node_params("batch_1")["asset_ids"]
+
+    assert_eq(second_result["asset_ids"].size(), 10)
+    assert_eq(second_ids.size(), 10)
+    assert_ne(second_ids, first_ids)
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

+    var batch_item_id := _item_id_for_node(canvas_items, "batch_1")
+    var first_asset_ids: Array = batch_node["params"]["asset_ids"].duplicate()
+    canvas.select_ids([batch_item_id])
+    controller.run_selected_mock_graph()
+    await wait_process_frames(2)
+
+    graph_data = ProjectService.current_project.graphs[graph_id]
+    batch_node = graph_data["nodes"][3]
+    var rerun_asset_ids: Array = batch_node["params"]["asset_ids"]
+    assert_eq(rerun_asset_ids.size(), 10)
+    assert_ne(rerun_asset_ids, first_asset_ids)
+    assert_eq(canvas._get_batch_asset_ids(batch_item_id), rerun_asset_ids)
+

 func _node_ids_from_canvas_items(items: Array) -> Array:
     var node_ids := []
     for item in items:
         node_ids.append(String(Dictionary(item).get("node_id", "")))
     return node_ids
+
+
+func _item_id_for_node(items: Array, node_id: String) -> String:
+    for item in items:
+        var data: Dictionary = item
+        if String(data.get("node_id", "")) == node_id:
+            return String(data.get("id", ""))
+    return ""
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
+    popup.add_item(Strings.MENU_RUN_SELECTED_GRAPH, FILE_MENU_RUN_SELECTED_GRAPH)
     popup.add_separator()
     popup.add_item(Strings.ACTION_NEW, FILE_MENU_NEW)
     popup.add_item(Strings.ACTION_OPEN, FILE_MENU_OPEN)
@@ -215,6 +217,42 @@ func generate_mock_batch() -> void:
     _status_label.text = Strings.STATUS_MOCK_GENERATE_DONE % asset_ids.size()


+func run_selected_mock_graph() -> void:
+    var binding := _selected_graph_binding()
+    if binding.is_empty():
+        _status_label.text = Strings.STATUS_GRAPH_RUN_NEEDS_SELECTION
+        return
+
+    var graph_id := String(binding["graph_id"])
+    var graph_data := ProjectService.get_graph_data(graph_id)
+    if graph_data.is_empty():
+        _status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+        return
+
+    var graph := GraphScript.from_json(graph_data)
+    var batch_node_id := _first_batch_node_id(graph)
+    if batch_node_id.is_empty():
+        _status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+        return
+
+    var runner := GraphMockRunnerScript.new()
+    var result: Dictionary = runner.run_to_batch(graph, AssetLibrary, batch_node_id, true)
+    if not bool(result.get("ok", false)):
+        var error: Dictionary = result.get("error", {})
+        Log.warn("Selected mock graph run failed", error)
+        _status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+        return
+
+    var asset_ids: Array = result["asset_ids"]
+    var batch_card_id := _graph_batch_card_id(graph.id, batch_node_id)
+    ProjectService.set_graph_data(graph.id, graph.to_json(), true)
+    if batch_card_id.is_empty():
+        _status_label.text = Strings.STATUS_GRAPH_RUN_FAILED
+        return
+    _canvas._replace_batch_asset_ids(batch_card_id, asset_ids, true)
+    _status_label.text = Strings.STATUS_GRAPH_RUN_DONE % asset_ids.size()
+
+
 func show_onboarding_if_needed() -> void:
     if DisplayServer.get_name() == "headless":
         return
@@ -276,6 +314,8 @@ func _on_file_menu_pressed(id: int) -> void:
             _import_dialog.popup_centered_ratio(0.7)
         FILE_MENU_GENERATE_MOCK_BATCH:
             generate_mock_batch()
+        FILE_MENU_RUN_SELECTED_GRAPH:
+            run_selected_mock_graph()
         FILE_MENU_NEW:
             _new_project_callback.call()
         FILE_MENU_OPEN:
@@ -495,6 +535,39 @@ func _graph_node_position(graph: PFGraph, node_id: String) -> Vector2:
     return Vector2(float(raw_position[0]), float(raw_position[1])).round()


+func _first_batch_node_id(graph: PFGraph) -> String:
+    for node_id in graph.nodes.keys():
+        var node: PFNode = graph.get_node(String(node_id))
+        if node != null and node.get_type() == "batch":
+            return String(node_id)
+    return ""
+
+
+func _selected_graph_binding() -> Dictionary:
+    var selected_ids: Array = _canvas.get_selected_ids()
+    for item in _canvas.export_canvas_data()["items"]:
+        var item_data: Dictionary = item
+        if not selected_ids.has(String(item_data.get("id", ""))):
+            continue
+        var graph_id := String(item_data.get("graph_id", ""))
+        var node_id := String(item_data.get("node_id", ""))
+        if graph_id.is_empty() or node_id.is_empty():
+            continue
+        return {"item_id": String(item_data["id"]), "graph_id": graph_id, "node_id": node_id}
+    return {}
+
+
+func _graph_batch_card_id(graph_id: String, batch_node_id: String) -> String:
+    for item in _canvas.export_canvas_data()["items"]:
+        var item_data: Dictionary = item
+        if (
+            String(item_data.get("graph_id", "")) == graph_id
+            and String(item_data.get("node_id", "")) == batch_node_id
+        ):
+            return String(item_data.get("id", ""))
+    return ""
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
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [
+        _register_asset(Color.RED, "red"),
+        _register_asset(Color.BLUE, "blue"),
+        _register_asset(Color.GREEN, "green"),
+    ]
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+
+    assert_eq(
+        canvas._set_batch_review_state(
+            "batch_1", [ids[0], ids[2]], CanvasBatchCardScript.REVIEW_KEEP, false
+        ),
+        2
+    )
+    assert_eq(card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_KEEP), [ids[0], ids[2]])
+
+    var data: Dictionary = canvas.export_canvas_data()
+    var item: Dictionary = data["items"][0]
+    assert_eq(item["review_states"][ids[0]], CanvasBatchCardScript.REVIEW_KEEP)
+    assert_eq(item["review_states"][ids[2]], CanvasBatchCardScript.REVIEW_KEEP)
+
+    var child: Node = canvas._split_batch_marked(
+        "batch_1", CanvasBatchCardScript.REVIEW_KEEP, "keep"
+    )
+    assert_not_null(child)
+    assert_eq(child.asset_ids, [ids[0], ids[2]])
+    assert_eq(canvas.get_item_count(), 2)
+
+
 func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
@@ -81,6 +116,48 @@ func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement()
     assert_eq(reloaded_canvas._get_batch_asset_ids("node_item_1"), [green_id])


+func test_graph_batch_card_persists_review_state_in_graph_params() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var graph := GraphScript.new()
+    graph.id = "graph_batch_review_test"
+    graph.add_node(
+        BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var card: Node = canvas._add_batch_card(
+        ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+    )
+    assert_eq(
+        canvas._set_batch_review_state(
+            "node_item_1", [ids[1]], CanvasBatchCardScript.REVIEW_FLAG, false
+        ),
+        1
+    )
+    assert_eq(card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])
+
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+    var batch_node: Dictionary = graph_data["nodes"][0]
+    assert_eq(batch_node["params"]["review_states"][ids[1]], CanvasBatchCardScript.REVIEW_FLAG)
+
+    var canvas_data: Dictionary = canvas.export_canvas_data()
+    assert_false(Dictionary(canvas_data["items"][0]).has("review_states"))
+
+    var reloaded_canvas: Control = CanvasScript.new()
+    reloaded_canvas.size = Vector2(512, 512)
+    add_child_autofree(reloaded_canvas)
+    await wait_process_frames(2)
+    reloaded_canvas.load_canvas_data(canvas_data)
+    var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]
+
+    assert_eq(reloaded_card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])
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
+    review_states = _review_state_map(
+        graph_params.get("review_states", data.get("review_states", {})), asset_ids
+    )
     locked = bool(data.get("locked", false))
     z_index = int(data.get("z_index", 0))
     var raw_position: Variant = data.get("position", [0, 0])
@@ -69,6 +80,7 @@ func to_canvas_data() -> Dictionary:
         "type": "batch_card",
         "asset_ids": asset_ids.duplicate(),
         "selected_asset_ids": selected_asset_ids.duplicate(),
+        "review_states": review_states.duplicate(true),
         "label": label,
         "position": [int(round(position.x)), int(round(position.y))],
         "z_index": z_index,
@@ -104,16 +116,39 @@ func set_asset_ids(new_asset_ids: Array) -> void:
     for selected_id in selected_asset_ids.duplicate():
         if not asset_ids.has(selected_id):
             selected_asset_ids.erase(selected_id)
+    review_states = _review_state_map(review_states, asset_ids)
     _rebuild_thumbnails()
     queue_redraw()


+func get_selected_asset_ids() -> Array[String]:
+    return selected_asset_ids.duplicate()
+
+
 func get_selected_or_all_asset_ids() -> Array[String]:
     if selected_asset_ids.is_empty():
         return asset_ids.duplicate()
     return selected_asset_ids.duplicate()


+func get_marked_asset_ids(review_state: String) -> Array[String]:
+    var normalized_state := _normalize_review_state(review_state)
+    var result: Array[String] = []
+    for asset_id in asset_ids:
+        if String(review_states.get(asset_id, REVIEW_NONE)) == normalized_state:
+            result.append(asset_id)
+    return result
+
+
+func get_review_states() -> Dictionary:
+    return review_states.duplicate(true)
+
+
+func set_review_states(new_review_states: Dictionary) -> void:
+    review_states = _review_state_map(new_review_states, asset_ids)
+    queue_redraw()
+
+
 func toggle_asset_at_world(world_position: Vector2) -> bool:
     var index := asset_index_at_world(world_position)
     if index < 0 or index >= asset_ids.size():
@@ -177,6 +212,32 @@ func _draw_thumbnail(index: int, rect: Rect2) -> void:
         draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)
     var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
     draw_rect(rect, border_color, false, 1.5)
+    _draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
+
+
+func _draw_review_marker(rect: Rect2, review_state: String) -> void:
+    match _normalize_review_state(review_state):
+        REVIEW_KEEP:
+            draw_rect(Rect2(rect.position, Vector2(7.0, rect.size.y)), KEEP_MARK, true)
+        REVIEW_REJECT:
+            draw_line(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8), REJECT_MARK, 4.0)
+            draw_line(
+                Vector2(rect.end.x - 8, rect.position.y + 8),
+                Vector2(rect.position.x + 8, rect.end.y - 8),
+                REJECT_MARK,
+                4.0
+            )
+        REVIEW_FLAG:
+            draw_colored_polygon(
+                PackedVector2Array(
+                    [
+                        rect.position + Vector2(rect.size.x - 30.0, 0.0),
+                        rect.position + Vector2(rect.size.x, 0.0),
+                        rect.position + Vector2(rect.size.x, 30.0),
+                    ]
+                ),
+                FLAG_MARK
+            )


 func _thumb_rect(index: int, columns: int) -> Rect2:
@@ -259,3 +320,29 @@ func _string_array(value: Variant) -> Array[String]:
         for item in Array(value):
             result.append(String(item))
     return result
+
+
+func _review_state_map(value: Variant, valid_asset_ids: Array[String]) -> Dictionary:
+    var result := {}
+    if not (value is Dictionary):
+        return result
+    var valid_lookup := {}
+    for asset_id in valid_asset_ids:
+        valid_lookup[asset_id] = true
+    var raw_states: Dictionary = value
+    for key in raw_states.keys():
+        var asset_id := String(key)
+        if not valid_lookup.has(asset_id):
+            continue
+        var review_state := _normalize_review_state(String(raw_states[key]))
+        if not review_state.is_empty():
+            result[asset_id] = review_state
+    return result
+
+
+func _normalize_review_state(review_state: String) -> String:
+    match review_state:
+        REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
+            return review_state
+        _:
+            return REVIEW_NONE
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
+    items_by_id: Dictionary, card_id: String, selected_only: bool = false
+) -> Array:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return []
+    if selected_only:
+        return item.get_selected_or_all_asset_ids()
+    return item.asset_ids.duplicate()
+
+
+static func get_selected_asset_ids(items_by_id: Dictionary, card_id: String) -> Array:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return []
+    return item.get_selected_asset_ids()
+
+
+static func get_marked_asset_ids(
+    items_by_id: Dictionary, card_id: String, review_state: String
+) -> Array:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return []
+    return item.get_marked_asset_ids(review_state)
+
+
+static func replace_asset_ids(
+    items_by_id: Dictionary,
+    card_id: String,
+    new_asset_ids: Array,
+    record_undo: bool,
+    select_only: Callable,
+    emit_changed: Callable
+) -> void:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return
+    var before: Array = item.asset_ids.duplicate()
+    var before_review_states: Dictionary = item.get_review_states()
+    var after := new_asset_ids.duplicate()
+    var after_review_states := {}
+    var do_replace := func() -> void:
+        GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
+        _apply_review_states(item, after_review_states)
+        GraphItemBridge.sync_batch_node_asset_ids(item, after)
+        GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
+        select_only.call([card_id])
+        emit_changed.call()
+    var undo_replace := func() -> void:
+        GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
+        _apply_review_states(item, before_review_states)
+        GraphItemBridge.sync_batch_node_asset_ids(item, before)
+        GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
+        select_only.call([card_id])
+        emit_changed.call()
+    if record_undo:
+        UndoService.perform_action("Replace batch assets", do_replace, undo_replace)
+    else:
+        do_replace.call()
+
+
+static func set_review_state(
+    items_by_id: Dictionary,
+    card_id: String,
+    asset_ids: Array,
+    review_state: String,
+    record_undo: bool,
+    select_only: Callable,
+    emit_changed: Callable
+) -> int:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return 0
+    var target_ids := _valid_target_ids(item, asset_ids)
+    if target_ids.is_empty():
+        return 0
+
+    var before: Dictionary = item.get_review_states()
+    var after := before.duplicate(true)
+    var normalized_state := _normalize_review_state(review_state)
+    for asset_id in target_ids:
+        if normalized_state.is_empty():
+            after.erase(asset_id)
+        else:
+            after[asset_id] = normalized_state
+
+    var do_mark := func() -> void:
+        _apply_review_states(item, after)
+        GraphItemBridge.sync_batch_node_review_states(item, after)
+        select_only.call([card_id])
+        emit_changed.call()
+    var undo_mark := func() -> void:
+        _apply_review_states(item, before)
+        GraphItemBridge.sync_batch_node_review_states(item, before)
+        select_only.call([card_id])
+        emit_changed.call()
+
+    if record_undo:
+        UndoService.perform_action("Mark batch review state", do_mark, undo_mark)
+    else:
+        do_mark.call()
+    return target_ids.size()
+
+
+static func split_selection_spec(items_by_id: Dictionary, card_id: String) -> Dictionary:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return {}
+    return _split_spec(item, item.get_selected_or_all_asset_ids(), "subset")
+
+
+static func split_marked_spec(
+    items_by_id: Dictionary, card_id: String, review_state: String, label_suffix: String
+) -> Dictionary:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return {}
+    return _split_spec(item, item.get_marked_asset_ids(review_state), label_suffix)
+
+
+static func _batch_item(items_by_id: Dictionary, card_id: String) -> Node:
+    if not items_by_id.has(card_id):
+        return null
+    var item: Node = items_by_id[card_id]
+    if item.get_script() != CanvasBatchCardScript:
+        return null
+    return item
+
+
+static func _valid_target_ids(item: Node, asset_ids: Array) -> Array:
+    var result := []
+    for raw_id in asset_ids:
+        var asset_id := String(raw_id)
+        if item.asset_ids.has(asset_id) and not result.has(asset_id):
+            result.append(asset_id)
+    return result
+
+
+static func _split_spec(item: Node, subset: Array, label_suffix: String) -> Dictionary:
+    if subset.is_empty() or subset.size() == item.asset_ids.size():
+        return {}
+    return {
+        "asset_ids": subset,
+        "position": item.position + Vector2(item.get_canvas_bounds().size.x + SPLIT_GAP, 0.0),
+        "label": "%s %s" % [item.label, label_suffix],
+    }
+
+
+static func _apply_review_states(item: Node, review_states: Dictionary) -> void:
+    item.set_review_states(review_states)
+
+
+static func _normalize_review_state(review_state: String) -> String:
+    if (
+        review_state
+        in [
+            CanvasBatchCardScript.REVIEW_KEEP,
+            CanvasBatchCardScript.REVIEW_REJECT,
+            CanvasBatchCardScript.REVIEW_FLAG,
+        ]
+    ):
+        return review_state
+    return CanvasBatchCardScript.REVIEW_NONE
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
+            params["review_states"] = _review_state_map(params.get("review_states", {}), asset_ids)
+            node_data["params"] = params
+            changed = true
+        nodes.append(node_data)
+
+    if changed:
+        graph_data["nodes"] = nodes
+        ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
+static func sync_batch_node_review_states(item: Node, review_states: Dictionary) -> void:
+    if not item.has_method("has_graph_binding") or not item.has_graph_binding():
+        return
+
+    var graph_data := ProjectService.get_graph_data(item.graph_id)
+    if graph_data.is_empty():
+        return
+
+    var nodes := []
+    var changed := false
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            nodes.append(raw_node)
+            continue
+        var node_data: Dictionary = raw_node
+        if (
+            String(node_data.get("id", "")) == item.node_id
+            and String(node_data.get("type", "")) == "batch"
+        ):
+            var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
+            params["review_states"] = _review_state_map(review_states, params.get("asset_ids", []))
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
+    var result := {}
+    if not (value is Dictionary):
+        return result
+    var valid_lookup := {}
+    for asset_id in _string_array(valid_asset_ids):
+        valid_lookup[asset_id] = true
+    var raw_states: Dictionary = value
+    for key in raw_states.keys():
+        var asset_id := String(key)
+        if not valid_lookup.has(asset_id):
+            continue
+        var review_state := String(raw_states[key])
+        if review_state in ["keep", "reject", "flag"]:
+            result[asset_id] = review_state
+    return result
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
-    if not _items_by_id.has(card_id):
-        return []
-    var item: Node = _items_by_id[card_id]
-    if item.get_script() != CanvasBatchCardScript:
-        return []
-    if selected_only:
-        return item.get_selected_or_all_asset_ids()
-    return item.asset_ids.duplicate()
+    return BatchOps.get_asset_ids(_items_by_id, card_id, selected_only)
+
+
+func _get_batch_selected_asset_ids(card_id: String) -> Array:
+    return BatchOps.get_selected_asset_ids(_items_by_id, card_id)
+
+
+func _get_batch_marked_asset_ids(card_id: String, review_state: String) -> Array:
+    return BatchOps.get_marked_asset_ids(_items_by_id, card_id, review_state)


 func _replace_batch_asset_ids(
     card_id: String, new_asset_ids: Array, record_undo: bool = true
 ) -> void:
-    if not _items_by_id.has(card_id):
-        return
-    var item: Node = _items_by_id[card_id]
-    if item.get_script() != CanvasBatchCardScript:
-        return
-    var before: Array = item.asset_ids.duplicate()
-    var after := new_asset_ids.duplicate()
-    var do_replace := func() -> void:
-        GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
-        GraphItemBridge.sync_batch_node_asset_ids(item, after)
-        _select_only([card_id])
-        _emit_canvas_changed()
-    var undo_replace := func() -> void:
-        GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
-        GraphItemBridge.sync_batch_node_asset_ids(item, before)
-        _select_only([card_id])
-        _emit_canvas_changed()
-    if record_undo:
-        UndoService.perform_action("Replace batch assets", do_replace, undo_replace)
-    else:
-        do_replace.call()
+    BatchOps.replace_asset_ids(
+        _items_by_id, card_id, new_asset_ids, record_undo, _select_only, _emit_canvas_changed
+    )
+
+
+func _set_batch_review_state(
+    card_id: String, asset_ids: Array, review_state: String, record_undo: bool = true
+) -> int:
+    return BatchOps.set_review_state(
+        _items_by_id,
+        card_id,
+        asset_ids,
+        review_state,
+        record_undo,
+        _select_only,
+        _emit_canvas_changed
+    )


 func _split_batch_selection(card_id: String) -> Node:
-    if not _items_by_id.has(card_id):
-        return null
-    var item: Node = _items_by_id[card_id]
-    if item.get_script() != CanvasBatchCardScript:
+    var spec: Dictionary = BatchOps.split_selection_spec(_items_by_id, card_id)
+    if spec.is_empty():
         return null
-    var subset: Array = item.get_selected_or_all_asset_ids()
-    if subset.is_empty() or subset.size() == item.asset_ids.size():
-        return null
-    return _add_batch_card(
-        subset,
-        item.position + Vector2(item.get_canvas_bounds().size.x + 24.0, 0.0),
-        "%s subset" % item.label,
-        "",
-        true
+    return _add_batch_card(spec["asset_ids"], spec["position"], spec["label"], "", true)
+
+
+func _split_batch_marked(card_id: String, review_state: String, label_suffix: String) -> Node:
+    var spec: Dictionary = BatchOps.split_marked_spec(
+        _items_by_id, card_id, review_state, label_suffix
     )
+    if spec.is_empty():
+        return null
+    return _add_batch_card(spec["asset_ids"], spec["position"], spec["label"], "", true)


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
+    _batch_menu.add_item(Strings.BATCH_ACTION_MARK_KEEP, BATCH_MENU_MARK_KEEP)
+    _batch_menu.add_item(Strings.BATCH_ACTION_MARK_REJECT, BATCH_MENU_MARK_REJECT)
+    _batch_menu.add_item(Strings.BATCH_ACTION_MARK_FLAG, BATCH_MENU_MARK_FLAG)
+    _batch_menu.add_item(Strings.BATCH_ACTION_CLEAR_MARK, BATCH_MENU_CLEAR_MARK)
+    _batch_menu.add_separator()
+    _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT_KEEP, BATCH_MENU_SPLIT_KEEP)
     _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
+    _batch_menu.add_separator()
     _batch_menu.add_item(Strings.BATCH_ACTION_EXPORT, BATCH_MENU_EXPORT)
     _batch_menu.id_pressed.connect(_on_batch_menu_id_pressed)
     add_child(_batch_menu)
@@ -395,6 +408,33 @@ func _on_batch_menu_id_pressed(id: int) -> void:
             _m2_actions.batch_outline(
                 _batch_menu_card_id, asset_ids, {"type": "outer", "color": Color.BLACK}
             )
+        BATCH_MENU_MARK_KEEP:
+            _mark_batch_review_state(
+                CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_MARK_KEEP
+            )
+        BATCH_MENU_MARK_REJECT:
+            _mark_batch_review_state(
+                CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_MARK_REJECT
+            )
+        BATCH_MENU_MARK_FLAG:
+            _mark_batch_review_state(
+                CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_MARK_FLAG
+            )
+        BATCH_MENU_CLEAR_MARK:
+            _mark_batch_review_state(
+                CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
+            )
+        BATCH_MENU_SPLIT_KEEP:
+            var new_keep_card: Variant = _canvas._split_batch_marked(
+                _batch_menu_card_id,
+                CanvasBatchCardScript.REVIEW_KEEP,
+                Strings.BATCH_KEEP_LABEL_SUFFIX
+            )
+            _status_label.text = (
+                Strings.STATUS_BATCH_SPLIT_KEEP
+                if new_keep_card != null
+                else Strings.STATUS_BATCH_SPLIT_KEEP_EMPTY
+            )
         BATCH_MENU_SPLIT:
             var new_card: Variant = _canvas._split_batch_selection(_batch_menu_card_id)
             _status_label.text = (
@@ -404,6 +444,20 @@ func _on_batch_menu_id_pressed(id: int) -> void:
             _emit_batch_export(asset_ids)


+func _mark_batch_review_state(review_state: String, status_format: String) -> void:
+    var selected_ids: Array = _canvas._get_batch_selected_asset_ids(_batch_menu_card_id)
+    if selected_ids.is_empty():
+        _status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
+        return
+    var marked_count: int = _canvas._set_batch_review_state(
+        _batch_menu_card_id, selected_ids, review_state, true
+    )
+    if marked_count <= 0:
+        _status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
+        return
+    _status_label.text = status_format % marked_count
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
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [
+        _register_asset(Color.RED, "red"),
+        _register_asset(Color.BLUE, "blue"),
+        _register_asset(Color.GREEN, "green"),
+    ]
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+    canvas._set_batch_review_state("batch_1", [ids[0]], CanvasBatchCardScript.REVIEW_KEEP, false)
+    canvas._set_batch_review_state("batch_1", [ids[1]], CanvasBatchCardScript.REVIEW_REJECT, false)
+
+    assert_true(
+        canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.REVIEW_KEEP, false)
+    )
+    assert_eq(card.get_visible_asset_ids(), [ids[0]])
+    assert_eq(canvas._get_batch_asset_ids("batch_1", true), [ids[0]])
+
+    assert_true(
+        canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.FILTER_PENDING, false)
+    )
+    assert_eq(card.get_visible_asset_ids(), [ids[2]])
+    assert_true(card.toggle_asset_at_world(card.position + Vector2(20, 60)))
+    assert_eq(card.get_selected_asset_ids(), [ids[2]])
+
+    var data: Dictionary = canvas.export_canvas_data()
+    var item: Dictionary = data["items"][0]
+    assert_eq(item["review_filter"], CanvasBatchCardScript.FILTER_PENDING)
+
+
 func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
@@ -158,6 +191,49 @@ func test_graph_batch_card_persists_review_state_in_graph_params() -> void:
     assert_eq(reloaded_card.get_marked_asset_ids(CanvasBatchCardScript.REVIEW_FLAG), [ids[1]])


+func test_graph_batch_card_persists_review_filter_in_graph_params() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var graph := GraphScript.new()
+    graph.id = "graph_batch_filter_test"
+    graph.add_node(
+        BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var card: Node = canvas._add_batch_card(
+        ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+    )
+    canvas._set_batch_review_state(
+        "node_item_1", [ids[1]], CanvasBatchCardScript.REVIEW_FLAG, false
+    )
+    assert_true(
+        canvas._set_batch_review_filter("node_item_1", CanvasBatchCardScript.REVIEW_FLAG, false)
+    )
+    assert_eq(card.get_visible_asset_ids(), [ids[1]])
+
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+    var batch_node: Dictionary = graph_data["nodes"][0]
+    assert_eq(batch_node["params"]["review_filter"], CanvasBatchCardScript.REVIEW_FLAG)
+
+    var canvas_data: Dictionary = canvas.export_canvas_data()
+    assert_false(Dictionary(canvas_data["items"][0]).has("review_filter"))
+
+    var reloaded_canvas: Control = CanvasScript.new()
+    reloaded_canvas.size = Vector2(512, 512)
+    add_child_autofree(reloaded_canvas)
+    await wait_process_frames(2)
+    reloaded_canvas.load_canvas_data(canvas_data)
+    var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]
+
+    assert_eq(reloaded_card.get_review_filter(), CanvasBatchCardScript.REVIEW_FLAG)
+    assert_eq(reloaded_card.get_visible_asset_ids(), [ids[1]])
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
+    review_filter = _normalize_review_filter(
+        String(graph_params.get("review_filter", data.get("review_filter", FILTER_ALL)))
+    )
+    _prune_selected_to_visible()
     locked = bool(data.get("locked", false))
     z_index = int(data.get("z_index", 0))
     var raw_position: Variant = data.get("position", [0, 0])
@@ -81,6 +88,7 @@ func to_canvas_data() -> Dictionary:
         "asset_ids": asset_ids.duplicate(),
         "selected_asset_ids": selected_asset_ids.duplicate(),
         "review_states": review_states.duplicate(true),
+        "review_filter": review_filter,
         "label": label,
         "position": [int(round(position.x)), int(round(position.y))],
         "z_index": z_index,
@@ -117,18 +125,30 @@ func set_asset_ids(new_asset_ids: Array) -> void:
         if not asset_ids.has(selected_id):
             selected_asset_ids.erase(selected_id)
     review_states = _review_state_map(review_states, asset_ids)
+    _prune_selected_to_visible()
     _rebuild_thumbnails()
     queue_redraw()


 func get_selected_asset_ids() -> Array[String]:
-    return selected_asset_ids.duplicate()
+    var visible_lookup := _visible_lookup()
+    var result: Array[String] = []
+    for asset_id in selected_asset_ids:
+        if visible_lookup.has(asset_id):
+            result.append(asset_id)
+    return result


 func get_selected_or_all_asset_ids() -> Array[String]:
+    var visible_ids := get_visible_asset_ids()
     if selected_asset_ids.is_empty():
-        return asset_ids.duplicate()
-    return selected_asset_ids.duplicate()
+        return visible_ids
+    var visible_lookup := _lookup(visible_ids)
+    var result: Array[String] = []
+    for selected_id in selected_asset_ids:
+        if visible_lookup.has(selected_id):
+            result.append(selected_id)
+    return result


 func get_marked_asset_ids(review_state: String) -> Array[String]:
@@ -140,20 +160,48 @@ func get_marked_asset_ids(review_state: String) -> Array[String]:
     return result


+func get_visible_asset_ids() -> Array[String]:
+    var result: Array[String] = []
+    match review_filter:
+        FILTER_ALL:
+            return asset_ids.duplicate()
+        FILTER_PENDING:
+            for asset_id in asset_ids:
+                if not review_states.has(asset_id):
+                    result.append(asset_id)
+        REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
+            for asset_id in asset_ids:
+                if String(review_states.get(asset_id, REVIEW_NONE)) == review_filter:
+                    result.append(asset_id)
+    return result
+
+
 func get_review_states() -> Dictionary:
     return review_states.duplicate(true)


 func set_review_states(new_review_states: Dictionary) -> void:
     review_states = _review_state_map(new_review_states, asset_ids)
+    _prune_selected_to_visible()
+    queue_redraw()
+
+
+func get_review_filter() -> String:
+    return review_filter
+
+
+func set_review_filter(new_review_filter: String) -> void:
+    review_filter = _normalize_review_filter(new_review_filter)
+    _prune_selected_to_visible()
     queue_redraw()


 func toggle_asset_at_world(world_position: Vector2) -> bool:
     var index := asset_index_at_world(world_position)
-    if index < 0 or index >= asset_ids.size():
+    var visible_ids := get_visible_asset_ids()
+    if index < 0 or index >= visible_ids.size():
         return false
-    var asset_id := asset_ids[index]
+    var asset_id := visible_ids[index]
     if selected_asset_ids.has(asset_id):
         selected_asset_ids.erase(asset_id)
     else:
@@ -167,7 +215,8 @@ func asset_index_at_world(world_position: Vector2) -> int:
     if local.y < HEADER_HEIGHT:
         return -1
     var columns := _columns()
-    for index in range(asset_ids.size()):
+    var visible_ids := get_visible_asset_ids()
+    for index in range(visible_ids.size()):
         var rect := _thumb_rect(index, columns)
         if rect.has_point(local):
             return index
@@ -183,10 +232,14 @@ func _draw() -> void:
         Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, HEADER_HEIGHT)), Color(0.21, 0.22, 0.24, 1.0), true
     )
     if _font != null:
+        var visible_count := get_visible_asset_ids().size()
+        var title := "%s (%d)" % [label, asset_ids.size()]
+        if visible_count != asset_ids.size():
+            title = "%s (%d/%d)" % [label, visible_count, asset_ids.size()]
         draw_string(
             _font,
             Vector2(PADDING, 28),
-            "%s (%d)" % [label, asset_ids.size()],
+            title,
             HORIZONTAL_ALIGNMENT_LEFT,
             CARD_WIDTH - PADDING * 2,
             18,
@@ -194,14 +247,14 @@ func _draw() -> void:
         )

     var columns := _columns()
-    for index in range(asset_ids.size()):
-        _draw_thumbnail(index, _thumb_rect(index, columns))
+    var visible_ids := get_visible_asset_ids()
+    for index in range(visible_ids.size()):
+        _draw_thumbnail(visible_ids[index], _thumb_rect(index, columns))
     if has_graph_binding():
         _draw_graph_ports()


-func _draw_thumbnail(index: int, rect: Rect2) -> void:
-    var asset_id := asset_ids[index]
+func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
     draw_rect(rect, THUMB_BACKGROUND, true)
     var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
     if texture != null:
@@ -253,9 +306,10 @@ func _thumb_rect(index: int, columns: int) -> Rect2:


 func _card_height() -> int:
-    if asset_ids.is_empty():
+    var visible_count := get_visible_asset_ids().size()
+    if visible_count <= 0:
         return MIN_CARD_HEIGHT
-    var rows := int(ceil(float(asset_ids.size()) / float(_columns())))
+    var rows := int(ceil(float(visible_count) / float(_columns())))
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
+    match value:
+        FILTER_ALL, FILTER_PENDING, REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG:
+            return value
+        _:
+            return FILTER_ALL
+
+
+func _prune_selected_to_visible() -> void:
+    var visible_lookup := _visible_lookup()
+    for selected_id in selected_asset_ids.duplicate():
+        if not visible_lookup.has(selected_id):
+            selected_asset_ids.erase(selected_id)
+
+
+func _visible_lookup() -> Dictionary:
+    return _lookup(get_visible_asset_ids())
+
+
+func _lookup(values: Array[String]) -> Dictionary:
+    var result := {}
+    for value in values:
+        result[value] = true
+    return result
diff --git a/pixel/ui/canvas/canvas_batch_ops.gd b/pixel/ui/canvas/canvas_batch_ops.gd
index 99403b0..a174ed5 100644
--- a/pixel/ui/canvas/canvas_batch_ops.gd
+++ b/pixel/ui/canvas/canvas_batch_ops.gd
@@ -49,20 +49,26 @@ static func replace_asset_ids(
         return
     var before: Array = item.asset_ids.duplicate()
     var before_review_states: Dictionary = item.get_review_states()
+    var before_review_filter: String = item.get_review_filter()
     var after := new_asset_ids.duplicate()
     var after_review_states := {}
+    var after_review_filter := CanvasBatchCardScript.FILTER_ALL
     var do_replace := func() -> void:
         GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
         _apply_review_states(item, after_review_states)
+        _apply_review_filter(item, after_review_filter)
         GraphItemBridge.sync_batch_node_asset_ids(item, after)
         GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
+        GraphItemBridge.sync_batch_node_review_filter(item, after_review_filter)
         select_only.call([card_id])
         emit_changed.call()
     var undo_replace := func() -> void:
         GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
         _apply_review_states(item, before_review_states)
+        _apply_review_filter(item, before_review_filter)
         GraphItemBridge.sync_batch_node_asset_ids(item, before)
         GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
+        GraphItemBridge.sync_batch_node_review_filter(item, before_review_filter)
         select_only.call([card_id])
         emit_changed.call()
     if record_undo:
@@ -114,6 +120,40 @@ static func set_review_state(
     return target_ids.size()


+static func set_review_filter(
+    items_by_id: Dictionary,
+    card_id: String,
+    review_filter: String,
+    record_undo: bool,
+    select_only: Callable,
+    emit_changed: Callable
+) -> bool:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return false
+    var before: String = item.get_review_filter()
+    var after := _normalize_review_filter(review_filter)
+    if before == after:
+        return true
+
+    var do_filter := func() -> void:
+        _apply_review_filter(item, after)
+        GraphItemBridge.sync_batch_node_review_filter(item, after)
+        select_only.call([card_id])
+        emit_changed.call()
+    var undo_filter := func() -> void:
+        _apply_review_filter(item, before)
+        GraphItemBridge.sync_batch_node_review_filter(item, before)
+        select_only.call([card_id])
+        emit_changed.call()
+
+    if record_undo:
+        UndoService.perform_action("Set batch review filter", do_filter, undo_filter)
+    else:
+        do_filter.call()
+    return true
+
+
 static func split_selection_spec(items_by_id: Dictionary, card_id: String) -> Dictionary:
     var item := _batch_item(items_by_id, card_id)
     if item == null:
@@ -162,6 +202,10 @@ static func _apply_review_states(item: Node, review_states: Dictionary) -> void:
     item.set_review_states(review_states)


+static func _apply_review_filter(item: Node, review_filter: String) -> void:
+    item.set_review_filter(review_filter)
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
+    if (
+        review_filter
+        in [
+            CanvasBatchCardScript.FILTER_ALL,
+            CanvasBatchCardScript.FILTER_PENDING,
+            CanvasBatchCardScript.REVIEW_KEEP,
+            CanvasBatchCardScript.REVIEW_REJECT,
+            CanvasBatchCardScript.REVIEW_FLAG,
+        ]
+    ):
+        return review_filter
+    return CanvasBatchCardScript.FILTER_ALL
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
+            params["review_filter"] = _review_filter(params.get("review_filter", "all"))
             node_data["params"] = params
             changed = true
         nodes.append(node_data)
@@ -92,6 +95,36 @@ static func sync_batch_node_review_states(item: Node, review_states: Dictionary)
         ProjectService.set_graph_data(item.graph_id, graph_data, true)


+static func sync_batch_node_review_filter(item: Node, review_filter: String) -> void:
+    if not item.has_method("has_graph_binding") or not item.has_graph_binding():
+        return
+
+    var graph_data := ProjectService.get_graph_data(item.graph_id)
+    if graph_data.is_empty():
+        return
+
+    var nodes := []
+    var changed := false
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            nodes.append(raw_node)
+            continue
+        var node_data: Dictionary = raw_node
+        if (
+            String(node_data.get("id", "")) == item.node_id
+            and String(node_data.get("type", "")) == "batch"
+        ):
+            var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
+            params["review_filter"] = _review_filter(review_filter)
+            node_data["params"] = params
+            changed = true
+        nodes.append(node_data)
+
+    if changed:
+        graph_data["nodes"] = nodes
+        ProjectService.set_graph_data(item.graph_id, graph_data, true)
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
+    var filter := String(value)
+    if (
+        filter
+        in [
+            CanvasBatchCardScript.FILTER_ALL,
+            CanvasBatchCardScript.FILTER_PENDING,
+            CanvasBatchCardScript.REVIEW_KEEP,
+            CanvasBatchCardScript.REVIEW_REJECT,
+            CanvasBatchCardScript.REVIEW_FLAG,
+        ]
+    ):
+        return filter
+    return CanvasBatchCardScript.FILTER_ALL
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 0a76239..b81dd3f 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -492,6 +492,14 @@ func _get_batch_marked_asset_ids(card_id: String, review_state: String) -> Array
     return BatchOps.get_marked_asset_ids(_items_by_id, card_id, review_state)


+func _set_batch_review_filter(
+    card_id: String, review_filter: String, record_undo: bool = true
+) -> bool:
+    return BatchOps.set_review_filter(
+        _items_by_id, card_id, review_filter, record_undo, _select_only, _emit_canvas_changed
+    )
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
+    _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_ALL, BATCH_MENU_FILTER_ALL)
+    _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_KEEP, BATCH_MENU_FILTER_KEEP)
+    _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_PENDING, BATCH_MENU_FILTER_PENDING)
+    _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_REJECT, BATCH_MENU_FILTER_REJECT)
+    _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_FLAG, BATCH_MENU_FILTER_FLAG)
+    _batch_menu.add_separator()
     _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT_KEEP, BATCH_MENU_SPLIT_KEEP)
     _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
     _batch_menu.add_separator()
@@ -424,6 +435,26 @@ func _on_batch_menu_id_pressed(id: int) -> void:
             _mark_batch_review_state(
                 CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
             )
+        BATCH_MENU_FILTER_ALL:
+            _set_batch_review_filter(
+                CanvasBatchCardScript.FILTER_ALL, Strings.STATUS_BATCH_SHOW_ALL
+            )
+        BATCH_MENU_FILTER_KEEP:
+            _set_batch_review_filter(
+                CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_SHOW_KEEP
+            )
+        BATCH_MENU_FILTER_PENDING:
+            _set_batch_review_filter(
+                CanvasBatchCardScript.FILTER_PENDING, Strings.STATUS_BATCH_SHOW_PENDING
+            )
+        BATCH_MENU_FILTER_REJECT:
+            _set_batch_review_filter(
+                CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_SHOW_REJECT
+            )
+        BATCH_MENU_FILTER_FLAG:
+            _set_batch_review_filter(
+                CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_SHOW_FLAG
+            )
         BATCH_MENU_SPLIT_KEEP:
             var new_keep_card: Variant = _canvas._split_batch_marked(
                 _batch_menu_card_id,
@@ -458,6 +489,13 @@ func _mark_batch_review_state(review_state: String, status_format: String) -> vo
     _status_label.text = status_format % marked_count


+func _set_batch_review_filter(review_filter: String, status_text: String) -> void:
+    if not _canvas._set_batch_review_filter(_batch_menu_card_id, review_filter, true):
+        _status_label.text = Strings.STATUS_BATCH_FILTER_FAILED
+        return
+    _status_label.text = status_text
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
+    ProjectService.new_project("Batch Shortcut UI")
+    var main: Control = MainScript.new()
+    main.size = Vector2(1280, 800)
+    add_child_autofree(main)
+    await wait_process_frames(2)
+
+    var controller: Node = main.get_node("M21UiController")
+    var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
+    controller.generate_mock_batch()
+    await wait_process_frames(2)
+
+    var graph_id := String(ProjectService.current_project.graphs.keys()[0])
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
+    var batch_node: Dictionary = graph_data["nodes"][3]
+    var first_asset_id := String(batch_node["params"]["asset_ids"][0])
+    var batch_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], "batch_1")
+    var batch_card: Node = canvas._items_by_id[batch_item_id]
+
+    canvas.select_ids([batch_item_id])
+    assert_true(batch_card.toggle_asset_at_world(batch_card.position + Vector2(20, 60)))
+    assert_true(_send_key(controller, KEY_K))
+
+    graph_data = ProjectService.current_project.graphs[graph_id]
+    batch_node = graph_data["nodes"][3]
+    assert_eq(batch_node["params"]["review_states"][first_asset_id], "keep")
+
+    assert_true(_send_key(controller, KEY_R))
+    graph_data = ProjectService.current_project.graphs[graph_id]
+    batch_node = graph_data["nodes"][3]
+    assert_eq(batch_node["params"]["review_states"][first_asset_id], "reject")
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
+    var event := InputEventKey.new()
+    event.keycode = keycode
+    event.pressed = true
+    return controller.handle_shortcut(event)
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index b61aee0..0aa0545 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -146,6 +146,8 @@ func handle_shortcut(event: InputEventKey) -> bool:
     if event.keycode == KEY_ESCAPE and not _tool_manager.get_active_tool_id().is_empty():
         _tool_manager.clear_active_tool()
         return true
+    if _handle_batch_review_shortcut(event):
+        return true
     if not SELECTION_TOOLS_VISIBLE:
         return false
     return _tool_manager.handle_shortcut(event.keycode)
@@ -476,17 +478,64 @@ func _on_batch_menu_id_pressed(id: int) -> void:


 func _mark_batch_review_state(review_state: String, status_format: String) -> void:
-    var selected_ids: Array = _canvas._get_batch_selected_asset_ids(_batch_menu_card_id)
+    _mark_batch_review_state_for_card(_batch_menu_card_id, review_state, status_format)
+
+
+func _mark_batch_review_state_for_card(
+    card_id: String, review_state: String, status_format: String
+) -> bool:
+    var selected_ids: Array = _canvas._get_batch_selected_asset_ids(card_id)
     if selected_ids.is_empty():
         _status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
-        return
+        return false
     var marked_count: int = _canvas._set_batch_review_state(
-        _batch_menu_card_id, selected_ids, review_state, true
+        card_id, selected_ids, review_state, true
     )
     if marked_count <= 0:
         _status_label.text = Strings.STATUS_BATCH_MARK_NEEDS_SELECTION
-        return
+        return false
     _status_label.text = status_format % marked_count
+    return true
+
+
+func _handle_batch_review_shortcut(event: InputEventKey) -> bool:
+    if event.is_command_or_control_pressed() or event.alt_pressed:
+        return false
+    var card_id := _selected_batch_card_id()
+    match event.keycode:
+        KEY_K:
+            _mark_batch_review_state_for_card(
+                card_id, CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_MARK_KEEP
+            )
+            return true
+        KEY_R:
+            _mark_batch_review_state_for_card(
+                card_id, CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_MARK_REJECT
+            )
+            return true
+        KEY_F:
+            _mark_batch_review_state_for_card(
+                card_id, CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_MARK_FLAG
+            )
+            return true
+        KEY_C:
+            _mark_batch_review_state_for_card(
+                card_id, CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
+            )
+            return true
+    return false
+
+
+func _selected_batch_card_id() -> String:
+    var selected_ids: Array = _canvas.get_selected_ids()
+    if selected_ids.is_empty():
+        return ""
+    for item in _canvas.export_canvas_data()["items"]:
+        var item_data: Dictionary = item
+        var item_id := String(item_data.get("id", ""))
+        if selected_ids.has(item_id) and not _canvas._get_batch_asset_ids(item_id).is_empty():
+            return item_id
+    return ""


func _set_batch_review_filter(review_filter: String, status_text: String) -> void:
```

## 2026-06-18 M3 UX-5 批次审阅焦点快捷键

### 本轮实现说明

- 在 batch 审阅状态中补入 `focus_asset_id`，用于记录当前键盘审阅焦点；正式 graph batch 写入 batch node params，旧 `batch_card` 写入 canvas 数据。
- Batch 卡新增焦点描边，点击缩略图会同步焦点；方向键会在当前可见缩略图集合内移动焦点并将焦点图设为唯一选中缩略图。
- `Right/Down` 移到下一张，`Left/Up` 移到上一张；焦点移动走 `UndoService`，并随 review filter / asset replacement 清理不可见或失效焦点。
- 契约补充 `focus_asset_id`；测试覆盖普通 batch、graph batch params 持久化，以及主窗口 mock batch 方向键路径。

### 验证结果

- `./pixel/scripts/lint.sh`：通过，105 files would be left unchanged，gdlint 无问题。
- `./pixel/scripts/run_tests.sh`：通过，143/143 tests passed，1180 asserts。
- `./pixel/scripts/verify_m3_ux5.sh`：通过，含 lint、完整测试、`check_ui_scaling: ok` 与 headless startup gate。

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`。
2. 单击选中 Mock Batch 卡本身。
3. 按 `Right` 或 `Down`，确认第一张缩略图被选中并出现浅色焦点描边，状态栏显示 `Focused thumbnail 1 of 10`。
4. 再按 `Right` 或 `Down`，确认焦点移动到下一张，且只有当前焦点缩略图保持选中。
5. 按 `Left` 或 `Up`，确认焦点回到上一张。
6. 在焦点图上继续按 `K/R/F/C`，确认快捷标记作用于当前焦点缩略图。
7. 用右键过滤 Show Keep / Show Pending 等视图后重复方向键，确认焦点只在当前可见缩略图中移动。

### 本轮完整 diff

```diff
diff --git a/pixel/tests/smoke/test_main_window_ui.gd b/pixel/tests/smoke/test_main_window_ui.gd
index 26565e3..9c70e83 100644
--- a/pixel/tests/smoke/test_main_window_ui.gd
+++ b/pixel/tests/smoke/test_main_window_ui.gd
@@ -292,6 +292,43 @@ func test_batch_review_shortcuts_mark_selected_mock_thumbnail() -> void:
     assert_eq(batch_node["params"]["review_states"][first_asset_id], "reject")


+func test_batch_review_focus_shortcuts_step_selected_mock_thumbnail() -> void:
+    ProjectService.new_project("Batch Focus UI")
+    var main: Control = MainScript.new()
+    main.size = Vector2(1280, 800)
+    add_child_autofree(main)
+    await wait_process_frames(2)
+
+    var controller: Node = main.get_node("M21UiController")
+    var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
+    controller.generate_mock_batch()
+    await wait_process_frames(2)
+
+    var graph_id := String(ProjectService.current_project.graphs.keys()[0])
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
+    var batch_node: Dictionary = graph_data["nodes"][3]
+    var asset_ids: Array = batch_node["params"]["asset_ids"]
+    var batch_item_id := _item_id_for_node(canvas.export_canvas_data()["items"], "batch_1")
+
+    canvas.select_ids([batch_item_id])
+    assert_true(_send_key(controller, KEY_RIGHT))
+    assert_eq(canvas._get_batch_selected_asset_ids(batch_item_id), [asset_ids[0]])
+
+    graph_data = ProjectService.current_project.graphs[graph_id]
+    batch_node = graph_data["nodes"][3]
+    assert_eq(batch_node["params"]["focus_asset_id"], asset_ids[0])
+
+    assert_true(_send_key(controller, KEY_RIGHT))
+    assert_eq(canvas._get_batch_selected_asset_ids(batch_item_id), [asset_ids[1]])
+
+    graph_data = ProjectService.current_project.graphs[graph_id]
+    batch_node = graph_data["nodes"][3]
+    assert_eq(batch_node["params"]["focus_asset_id"], asset_ids[1])
+
+    assert_true(_send_key(controller, KEY_LEFT))
+    assert_eq(canvas._get_batch_selected_asset_ids(batch_item_id), [asset_ids[0]])
+
+
 func _node_ids_from_canvas_items(items: Array) -> Array:
     var node_ids := []
     for item in items:
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index 5103402..c97601c 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -105,6 +105,50 @@ func test_canvas_batch_card_filters_visible_review_subset() -> void:
     assert_eq(item["review_filter"], CanvasBatchCardScript.FILTER_PENDING)


+func test_canvas_batch_card_focuses_visible_review_thumbnails() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [
+        _register_asset(Color.RED, "red"),
+        _register_asset(Color.BLUE, "blue"),
+        _register_asset(Color.GREEN, "green"),
+    ]
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+
+    var focus: Dictionary = canvas._focus_batch_relative("batch_1", 1, false)
+    assert_eq(focus["asset_id"], ids[0])
+    assert_eq(focus["index"], 1)
+    assert_eq(focus["total"], 3)
+    assert_eq(card._get_focus_asset_id(), ids[0])
+    assert_eq(card.get_selected_asset_ids(), [ids[0]])
+
+    focus = canvas._focus_batch_relative("batch_1", 1, false)
+    assert_eq(focus["asset_id"], ids[1])
+    assert_eq(card.get_selected_asset_ids(), [ids[1]])
+
+    focus = canvas._focus_batch_relative("batch_1", -1, false)
+    assert_eq(focus["asset_id"], ids[0])
+    assert_eq(card.get_selected_asset_ids(), [ids[0]])
+
+    canvas._set_batch_review_state("batch_1", [ids[0]], CanvasBatchCardScript.REVIEW_REJECT, false)
+    assert_true(
+        canvas._set_batch_review_filter("batch_1", CanvasBatchCardScript.FILTER_PENDING, false)
+    )
+    assert_eq(card._get_focus_asset_id(), "")
+
+    focus = canvas._focus_batch_relative("batch_1", 1, false)
+    assert_eq(focus["asset_id"], ids[1])
+    assert_eq(focus["index"], 1)
+    assert_eq(focus["total"], 2)
+
+    var data: Dictionary = canvas.export_canvas_data()
+    var item: Dictionary = data["items"][0]
+    assert_eq(item["focus_asset_id"], ids[1])
+
+
 func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
@@ -234,6 +278,44 @@ func test_graph_batch_card_persists_review_filter_in_graph_params() -> void:
     assert_eq(reloaded_card.get_visible_asset_ids(), [ids[1]])


+func test_graph_batch_card_persists_focus_asset_id_in_graph_params() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var graph := GraphScript.new()
+    graph.id = "graph_batch_focus_test"
+    graph.add_node(
+        BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var card: Node = canvas._add_batch_card(
+        ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+    )
+    var focus: Dictionary = canvas._focus_batch_relative("node_item_1", 1, false)
+    assert_eq(focus["asset_id"], ids[0])
+    assert_eq(card._get_focus_asset_id(), ids[0])
+
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+    var batch_node: Dictionary = graph_data["nodes"][0]
+    assert_eq(batch_node["params"]["focus_asset_id"], ids[0])
+
+    var canvas_data: Dictionary = canvas.export_canvas_data()
+    assert_false(Dictionary(canvas_data["items"][0]).has("focus_asset_id"))
+
+    var reloaded_canvas: Control = CanvasScript.new()
+    reloaded_canvas.size = Vector2(512, 512)
+    add_child_autofree(reloaded_canvas)
+    await wait_process_frames(2)
+    reloaded_canvas.load_canvas_data(canvas_data)
+    var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]
+
+    assert_eq(reloaded_card._get_focus_asset_id(), ids[0])
+
+
 func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 793f7d4..0d4f595 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -28,6 +28,7 @@ const FILTER_PENDING := "pending"
 const KEEP_MARK := Color(0.2, 0.88, 0.46, 1.0)
 const REJECT_MARK := Color(0.95, 0.22, 0.24, 0.95)
 const FLAG_MARK := Color(1.0, 0.78, 0.18, 1.0)
+const FOCUS_BORDER := Color(0.96, 0.96, 0.9, 1.0)
 const INPUT_PORTS: Array[String] = ["in"]
 const OUTPUT_PORTS: Array[String] = ["images", "assets"]

@@ -38,6 +39,7 @@ var asset_ids: Array[String] = []
 var selected_asset_ids: Array[String] = []
 var review_states := {}
 var review_filter := FILTER_ALL
+var focus_asset_id := ""
 var label := ""
 var locked := false

@@ -60,7 +62,11 @@ func setup_from_data(data: Dictionary) -> void:
     review_filter = _normalize_review_filter(
         String(graph_params.get("review_filter", data.get("review_filter", FILTER_ALL)))
     )
+    focus_asset_id = _normalize_focus_asset_id(
+        String(graph_params.get("focus_asset_id", data.get("focus_asset_id", "")))
+    )
     _prune_selected_to_visible()
+    _prune_focus_to_visible()
     locked = bool(data.get("locked", false))
     z_index = int(data.get("z_index", 0))
     var raw_position: Variant = data.get("position", [0, 0])
@@ -89,6 +95,7 @@ func to_canvas_data() -> Dictionary:
         "selected_asset_ids": selected_asset_ids.duplicate(),
         "review_states": review_states.duplicate(true),
         "review_filter": review_filter,
+        "focus_asset_id": focus_asset_id,
         "label": label,
         "position": [int(round(position.x)), int(round(position.y))],
         "z_index": z_index,
@@ -126,6 +133,7 @@ func set_asset_ids(new_asset_ids: Array) -> void:
             selected_asset_ids.erase(selected_id)
     review_states = _review_state_map(review_states, asset_ids)
     _prune_selected_to_visible()
+    _prune_focus_to_visible()
     _rebuild_thumbnails()
     queue_redraw()

@@ -183,6 +191,7 @@ func get_review_states() -> Dictionary:
 func set_review_states(new_review_states: Dictionary) -> void:
     review_states = _review_state_map(new_review_states, asset_ids)
     _prune_selected_to_visible()
+    _prune_focus_to_visible()
     queue_redraw()


@@ -193,9 +202,39 @@ func get_review_filter() -> String:
 func set_review_filter(new_review_filter: String) -> void:
     review_filter = _normalize_review_filter(new_review_filter)
     _prune_selected_to_visible()
+    _prune_focus_to_visible()
     queue_redraw()


+func _get_focus_asset_id() -> String:
+    return focus_asset_id
+
+
+func _set_focus_asset_id(new_focus_asset_id: String, select_focused: bool = false) -> void:
+    focus_asset_id = _normalize_focus_asset_id(new_focus_asset_id)
+    _prune_focus_to_visible()
+    if select_focused and not focus_asset_id.is_empty():
+        selected_asset_ids = [focus_asset_id]
+    queue_redraw()
+
+
+func _set_selected_asset_ids(new_selected_asset_ids: Array) -> void:
+    selected_asset_ids = _visible_selected_array(new_selected_asset_ids)
+    queue_redraw()
+
+
+func _focus_asset_id_relative(step: int) -> String:
+    var visible_ids := get_visible_asset_ids()
+    if visible_ids.is_empty():
+        return ""
+    if step == 0:
+        return focus_asset_id if visible_ids.has(focus_asset_id) else ""
+    var anchor_index := _focus_anchor_index(visible_ids)
+    if anchor_index < 0:
+        anchor_index = -1 if step > 0 else visible_ids.size()
+    return visible_ids[posmod(anchor_index + step, visible_ids.size())]
+
+
 func toggle_asset_at_world(world_position: Vector2) -> bool:
     var index := asset_index_at_world(world_position)
     var visible_ids := get_visible_asset_ids()
@@ -204,8 +243,13 @@ func toggle_asset_at_world(world_position: Vector2) -> bool:
     var asset_id := visible_ids[index]
     if selected_asset_ids.has(asset_id):
         selected_asset_ids.erase(asset_id)
+        if focus_asset_id == asset_id:
+            focus_asset_id = ""
+            if not selected_asset_ids.is_empty():
+                focus_asset_id = selected_asset_ids[selected_asset_ids.size() - 1]
     else:
         selected_asset_ids.append(asset_id)
+        focus_asset_id = asset_id
     queue_redraw()
     return true

@@ -266,6 +310,8 @@ func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
     var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
     draw_rect(rect, border_color, false, 1.5)
     _draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
+    if focus_asset_id == asset_id:
+        draw_rect(rect.grow(3.0), FOCUS_BORDER, false, 2.5)


 func _draw_review_marker(rect: Rect2, review_state: String) -> void:
@@ -410,6 +456,10 @@ func _normalize_review_filter(value: String) -> String:
             return FILTER_ALL


+func _normalize_focus_asset_id(new_focus_asset_id: String) -> String:
+    return new_focus_asset_id if asset_ids.has(new_focus_asset_id) else ""
+
+
 func _prune_selected_to_visible() -> void:
     var visible_lookup := _visible_lookup()
     for selected_id in selected_asset_ids.duplicate():
@@ -417,6 +467,34 @@ func _prune_selected_to_visible() -> void:
             selected_asset_ids.erase(selected_id)


+func _prune_focus_to_visible() -> void:
+    if focus_asset_id.is_empty():
+        return
+    if not _visible_lookup().has(focus_asset_id):
+        focus_asset_id = ""
+
+
+func _focus_anchor_index(visible_ids: Array[String]) -> int:
+    var focus_index := visible_ids.find(focus_asset_id)
+    if focus_index >= 0:
+        return focus_index
+    for selected_id in selected_asset_ids:
+        var selected_index := visible_ids.find(selected_id)
+        if selected_index >= 0:
+            return selected_index
+    return -1
+
+
+func _visible_selected_array(value: Array) -> Array[String]:
+    var visible_lookup := _visible_lookup()
+    var result: Array[String] = []
+    for raw_id in value:
+        var asset_id := String(raw_id)
+        if visible_lookup.has(asset_id) and not result.has(asset_id):
+            result.append(asset_id)
+    return result
+
+
 func _visible_lookup() -> Dictionary:
     return _lookup(get_visible_asset_ids())

diff --git a/pixel/ui/canvas/canvas_batch_ops.gd b/pixel/ui/canvas/canvas_batch_ops.gd
index a174ed5..f6e3959 100644
--- a/pixel/ui/canvas/canvas_batch_ops.gd
+++ b/pixel/ui/canvas/canvas_batch_ops.gd
@@ -50,25 +50,31 @@ static func replace_asset_ids(
     var before: Array = item.asset_ids.duplicate()
     var before_review_states: Dictionary = item.get_review_states()
     var before_review_filter: String = item.get_review_filter()
+    var before_focus_asset_id: String = item._get_focus_asset_id()
     var after := new_asset_ids.duplicate()
     var after_review_states := {}
     var after_review_filter := CanvasBatchCardScript.FILTER_ALL
+    var after_focus_asset_id := ""
     var do_replace := func() -> void:
         GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
         _apply_review_states(item, after_review_states)
         _apply_review_filter(item, after_review_filter)
+        _apply_focus_asset_id(item, after_focus_asset_id)
         GraphItemBridge.sync_batch_node_asset_ids(item, after)
         GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
         GraphItemBridge.sync_batch_node_review_filter(item, after_review_filter)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, after_focus_asset_id)
         select_only.call([card_id])
         emit_changed.call()
     var undo_replace := func() -> void:
         GraphItemBridge.apply_batch_asset_ids(item, before, AssetLibrary)
         _apply_review_states(item, before_review_states)
         _apply_review_filter(item, before_review_filter)
+        _apply_focus_asset_id(item, before_focus_asset_id)
         GraphItemBridge.sync_batch_node_asset_ids(item, before)
         GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
         GraphItemBridge.sync_batch_node_review_filter(item, before_review_filter)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
         select_only.call([card_id])
         emit_changed.call()
     if record_undo:
@@ -94,6 +100,7 @@ static func set_review_state(
         return 0

     var before: Dictionary = item.get_review_states()
+    var before_focus_asset_id: String = item._get_focus_asset_id()
     var after := before.duplicate(true)
     var normalized_state := _normalize_review_state(review_state)
     for asset_id in target_ids:
@@ -104,12 +111,16 @@ static func set_review_state(

     var do_mark := func() -> void:
         _apply_review_states(item, after)
+        _apply_focus_asset_id(item, _focus_after_current_filter(item, before_focus_asset_id))
         GraphItemBridge.sync_batch_node_review_states(item, after)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, item._get_focus_asset_id())
         select_only.call([card_id])
         emit_changed.call()
     var undo_mark := func() -> void:
         _apply_review_states(item, before)
+        _apply_focus_asset_id(item, before_focus_asset_id)
         GraphItemBridge.sync_batch_node_review_states(item, before)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
         select_only.call([card_id])
         emit_changed.call()

@@ -132,18 +143,24 @@ static func set_review_filter(
     if item == null:
         return false
     var before: String = item.get_review_filter()
+    var before_focus_asset_id: String = item._get_focus_asset_id()
     var after := _normalize_review_filter(review_filter)
     if before == after:
         return true
+    var after_focus_asset_id := _focus_after_filter(item, before_focus_asset_id, after)

     var do_filter := func() -> void:
         _apply_review_filter(item, after)
+        _apply_focus_asset_id(item, after_focus_asset_id)
         GraphItemBridge.sync_batch_node_review_filter(item, after)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, after_focus_asset_id)
         select_only.call([card_id])
         emit_changed.call()
     var undo_filter := func() -> void:
         _apply_review_filter(item, before)
+        _apply_focus_asset_id(item, before_focus_asset_id)
         GraphItemBridge.sync_batch_node_review_filter(item, before)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
         select_only.call([card_id])
         emit_changed.call()

@@ -154,6 +171,45 @@ static func set_review_filter(
     return true


+static func focus_relative(
+    items_by_id: Dictionary,
+    card_id: String,
+    step: int,
+    record_undo: bool,
+    select_only: Callable,
+    emit_changed: Callable
+) -> Dictionary:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return {}
+    var target_asset_id: String = item._focus_asset_id_relative(step)
+    if target_asset_id.is_empty():
+        return {}
+
+    var before_focus_asset_id: String = item._get_focus_asset_id()
+    var before_selected_asset_ids: Array = item.selected_asset_ids.duplicate()
+    var after_selected_asset_ids := [target_asset_id]
+    var focus_result := _focus_result(item, target_asset_id)
+    var do_focus := func() -> void:
+        _apply_selected_asset_ids(item, after_selected_asset_ids)
+        _apply_focus_asset_id(item, target_asset_id)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, target_asset_id)
+        select_only.call([card_id])
+        emit_changed.call()
+    var undo_focus := func() -> void:
+        _apply_selected_asset_ids(item, before_selected_asset_ids)
+        _apply_focus_asset_id(item, before_focus_asset_id)
+        GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
+        select_only.call([card_id])
+        emit_changed.call()
+
+    if record_undo:
+        UndoService.perform_action("Focus batch thumbnail", do_focus, undo_focus)
+    else:
+        do_focus.call()
+    return focus_result
+
+
 static func split_selection_spec(items_by_id: Dictionary, card_id: String) -> Dictionary:
     var item := _batch_item(items_by_id, card_id)
     if item == null:
@@ -206,6 +262,14 @@ static func _apply_review_filter(item: Node, review_filter: String) -> void:
     item.set_review_filter(review_filter)


+static func _apply_focus_asset_id(item: Node, focus_asset_id: String) -> void:
+    item._set_focus_asset_id(focus_asset_id, false)
+
+
+static func _apply_selected_asset_ids(item: Node, selected_asset_ids: Array) -> void:
+    item._set_selected_asset_ids(selected_asset_ids)
+
+
 static func _normalize_review_state(review_state: String) -> String:
     if (
         review_state
@@ -232,3 +296,40 @@ static func _normalize_review_filter(review_filter: String) -> String:
     ):
         return review_filter
     return CanvasBatchCardScript.FILTER_ALL
+
+
+static func _focus_result(item: Node, focus_asset_id: String) -> Dictionary:
+    var visible_ids: Array = item.get_visible_asset_ids()
+    return {
+        "asset_id": focus_asset_id,
+        "index": visible_ids.find(focus_asset_id) + 1,
+        "total": visible_ids.size(),
+    }
+
+
+static func _focus_after_current_filter(item: Node, focus_asset_id: String) -> String:
+    return focus_asset_id if item.get_visible_asset_ids().has(focus_asset_id) else ""
+
+
+static func _focus_after_filter(
+    item: Node, focus_asset_id: String, review_filter: String
+) -> String:
+    if focus_asset_id.is_empty():
+        return ""
+    var normalized_filter := _normalize_review_filter(review_filter)
+    match normalized_filter:
+        CanvasBatchCardScript.FILTER_ALL:
+            return focus_asset_id if item.asset_ids.has(focus_asset_id) else ""
+        CanvasBatchCardScript.FILTER_PENDING:
+            if item.asset_ids.has(focus_asset_id) and not item.review_states.has(focus_asset_id):
+                return focus_asset_id
+        CanvasBatchCardScript.REVIEW_KEEP:
+            if String(item.review_states.get(focus_asset_id, "")) == normalized_filter:
+                return focus_asset_id
+        CanvasBatchCardScript.REVIEW_REJECT:
+            if String(item.review_states.get(focus_asset_id, "")) == normalized_filter:
+                return focus_asset_id
+        CanvasBatchCardScript.REVIEW_FLAG:
+            if String(item.review_states.get(focus_asset_id, "")) == normalized_filter:
+                return focus_asset_id
+    return ""
diff --git a/pixel/ui/canvas/canvas_graph_item_bridge.gd b/pixel/ui/canvas/canvas_graph_item_bridge.gd
index 1c43497..f5c3980 100644
--- a/pixel/ui/canvas/canvas_graph_item_bridge.gd
+++ b/pixel/ui/canvas/canvas_graph_item_bridge.gd
@@ -56,6 +56,7 @@ static func sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
             params["asset_ids"] = _string_array(asset_ids)
             params["review_states"] = _review_state_map(params.get("review_states", {}), asset_ids)
             params["review_filter"] = _review_filter(params.get("review_filter", "all"))
+            params["focus_asset_id"] = _focus_asset_id(params.get("focus_asset_id", ""), asset_ids)
             node_data["params"] = params
             changed = true
         nodes.append(node_data)
@@ -125,6 +126,36 @@ static func sync_batch_node_review_filter(item: Node, review_filter: String) ->
         ProjectService.set_graph_data(item.graph_id, graph_data, true)


+static func sync_batch_node_focus_asset_id(item: Node, focus_asset_id: String) -> void:
+    if not item.has_method("has_graph_binding") or not item.has_graph_binding():
+        return
+
+    var graph_data := ProjectService.get_graph_data(item.graph_id)
+    if graph_data.is_empty():
+        return
+
+    var nodes := []
+    var changed := false
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            nodes.append(raw_node)
+            continue
+        var node_data: Dictionary = raw_node
+        if (
+            String(node_data.get("id", "")) == item.node_id
+            and String(node_data.get("type", "")) == "batch"
+        ):
+            var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
+            params["focus_asset_id"] = _focus_asset_id(focus_asset_id, params.get("asset_ids", []))
+            node_data["params"] = params
+            changed = true
+        nodes.append(node_data)
+
+    if changed:
+        graph_data["nodes"] = nodes
+        ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
 static func _string_array(value: Variant) -> Array[String]:
     var result: Array[String] = []
     if value is Array:
@@ -167,3 +198,8 @@ static func _review_filter(value: Variant) -> String:
     ):
         return filter
     return CanvasBatchCardScript.FILTER_ALL
+
+
+static func _focus_asset_id(value: Variant, valid_asset_ids: Variant) -> String:
+    var asset_id := String(value)
+    return asset_id if _string_array(valid_asset_ids).has(asset_id) else ""
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index b81dd3f..4749072 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -522,6 +522,12 @@ func _set_batch_review_state(
     )


+func _focus_batch_relative(card_id: String, step: int, record_undo: bool = true) -> Dictionary:
+    return BatchOps.focus_relative(
+        _items_by_id, card_id, step, record_undo, _select_only, _emit_canvas_changed
+    )
+
+
 func _split_batch_selection(card_id: String) -> Node:
     var spec: Dictionary = BatchOps.split_selection_spec(_items_by_id, card_id)
     if spec.is_empty():
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index 0aa0545..f66c064 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -501,31 +501,53 @@ func _mark_batch_review_state_for_card(
 func _handle_batch_review_shortcut(event: InputEventKey) -> bool:
     if event.is_command_or_control_pressed() or event.alt_pressed:
         return false
+    if _handle_batch_focus_shortcut(event):
+        return true
     var card_id := _selected_batch_card_id()
+    var review_state := ""
+    var status_format := ""
     match event.keycode:
         KEY_K:
-            _mark_batch_review_state_for_card(
-                card_id, CanvasBatchCardScript.REVIEW_KEEP, Strings.STATUS_BATCH_MARK_KEEP
-            )
-            return true
+            review_state = CanvasBatchCardScript.REVIEW_KEEP
+            status_format = Strings.STATUS_BATCH_MARK_KEEP
         KEY_R:
-            _mark_batch_review_state_for_card(
-                card_id, CanvasBatchCardScript.REVIEW_REJECT, Strings.STATUS_BATCH_MARK_REJECT
-            )
-            return true
+            review_state = CanvasBatchCardScript.REVIEW_REJECT
+            status_format = Strings.STATUS_BATCH_MARK_REJECT
         KEY_F:
-            _mark_batch_review_state_for_card(
-                card_id, CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_MARK_FLAG
-            )
-            return true
+            review_state = CanvasBatchCardScript.REVIEW_FLAG
+            status_format = Strings.STATUS_BATCH_MARK_FLAG
         KEY_C:
-            _mark_batch_review_state_for_card(
-                card_id, CanvasBatchCardScript.REVIEW_NONE, Strings.STATUS_BATCH_MARK_CLEAR
-            )
-            return true
+            review_state = CanvasBatchCardScript.REVIEW_NONE
+            status_format = Strings.STATUS_BATCH_MARK_CLEAR
+        _:
+            return false
+    _mark_batch_review_state_for_card(card_id, review_state, status_format)
+    return true
+
+
+func _handle_batch_focus_shortcut(event: InputEventKey) -> bool:
+    match event.keycode:
+        KEY_RIGHT, KEY_DOWN:
+            return _focus_selected_batch_relative(1)
+        KEY_LEFT, KEY_UP:
+            return _focus_selected_batch_relative(-1)
     return false


+func _focus_selected_batch_relative(step: int) -> bool:
+    var card_id := _selected_batch_card_id()
+    if card_id.is_empty():
+        return false
+    var focus_result: Dictionary = _canvas._focus_batch_relative(card_id, step, true)
+    if focus_result.is_empty():
+        _status_label.text = Strings.STATUS_BATCH_FOCUS_EMPTY
+        return true
+    _status_label.text = (
+        Strings.STATUS_BATCH_FOCUS_FORMAT % [focus_result["index"], focus_result["total"]]
+    )
+    return true
+
+
 func _selected_batch_card_id() -> String:
     var selected_ids: Array = _canvas.get_selected_ids()
     if selected_ids.is_empty():
diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index 6b00e04..ba97d1e 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -56,6 +56,8 @@ const STATUS_BATCH_SHOW_PENDING := "Showing pending thumbnails"
 const STATUS_BATCH_SHOW_REJECT := "Showing rejected thumbnails"
 const STATUS_BATCH_SHOW_FLAG := "Showing flagged thumbnails"
 const STATUS_BATCH_FILTER_FAILED := "Batch filter failed"
+const STATUS_BATCH_FOCUS_EMPTY := "No visible thumbnails in batch"
+const STATUS_BATCH_FOCUS_FORMAT := "Focused thumbnail %d of %d"
 const STATUS_MOCK_GENERATE_DONE := "Mock batch generated: %d sprites"
 const STATUS_MOCK_GENERATE_FAILED := "Mock batch generation failed"
 const STATUS_GRAPH_RUN_DONE := "Graph run complete: %d sprites"
diff --git a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
index 5f675ae..1239323 100644
--- a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
+++ b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
@@ -127,7 +127,7 @@ func get_canvas_actions() -> Array[Dictionary]
 新概念，本模型的核心。装一个批次的图片队列，是「AI 输出自由」与「批量加工」的落脚点。

 - **双身份**：① 图节点（`type=batch`，`category=container`，`is_canvas_resident()=true`）；② 画布卡（PROJECT-FORMAT canvas.json 的 `node` 引用，特化渲染为容器卡）。
-- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），可选 `review_filter` 记录当前审阅过滤器（`all|pending|keep|reject|flag`），二者均随 `asset_ids` 过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
+- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），可选 `review_filter` 记录当前审阅过滤器（`all|pending|keep|reject|flag`），可选 `focus_asset_id` 记录当前键盘审阅焦点，三者均随 `asset_ids` 过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
 - **整批菜单**（`get_canvas_actions()` 声明，边框弹出）：整批清洗 / 整批抠图 / 整批描边 / 整批量化 / 导出整批 / 拆小批次 / 逐张发送到编辑器。均调 core，记 undo + provenance（§4.7）。
 - **拆小批次**：勾选子集 → 生成子 `batch`（新卡，引用子集 asset_id），可独立处理；复用 `select` 语义。
 - **分离单图**：把某张拖出批次卡 → 成为独立 sprite 卡（仍在同一画布，见 PROJECT-FORMAT §4 `sprite`）。
diff --git a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
index 2a78aa8..0ba739c 100644
--- a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
+++ b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
@@ -110,6 +110,7 @@ my_project.pxproj (ZIP)
       "selected_asset_ids": [],
       "review_states": { "uuid-a": "keep" },
      "review_filter": "all",
+      "focus_asset_id": "uuid-a",
      "label": "Batch",
      "position": [320, 64],
      "z_index": 1,
```

## 2026-06-18 M3 UX-6 批次前后版本 A/B 对比入口

### 本轮实现说明

- 为批次卡补上最小 A/B 对比状态：批处理替换结果时保留同索引上一版 `compare_asset_ids`，右键菜单可在 `Show Current` / `Show Previous` 间切换。
- `Show Previous` 只替换缩略图纹理来源，不改变当前 `asset_ids`、选中状态、审阅状态、过滤状态或拆分/export 的实际目标，避免误把上一版素材送入后续处理。
- Graph batch 将 `compare_asset_ids` / `compare_mode` 持久化到 batch 节点 params；旧 `batch_card` 仍在 canvas data 中保留兼容字段。
- `Clean/Matte/Outline` 等批处理完成时自动记录处理前资产作为上一版；重新运行 graph 仍以新 mock 批次替换当前队列并清空上一版对比状态。
- 记录人工反馈：上一张焦点快捷键卡里 Up/Down 会被右侧菜单栏选项占用，影响不大；当前稳定路径以 Left/Right 切换缩略图焦点，后续如需要可单独移除或改映射 Up/Down。

### 验证结果

- `./pixel/scripts/lint.sh`：通过，105 files unchanged，no problems found。
- `./pixel/scripts/run_tests.sh`：通过，145/145 tests，1200 asserts。
- `./pixel/scripts/verify_m3_ux6.sh`：通过，包含 editor game view 配置、lint、全量测试、UI scaling 检查、export templates 本地 gate、staged 图片检查。
- 已知既有输出：GUT 仍报告 1 orphan、Godot 退出时仍有 ObjectDB/resource warning；本轮未新增相关失败。

### 人工测试步骤

1. 打开 PixelForge，执行 `File > Generate Mock Batch` 生成四节点链和 Mock Batch。
2. 右键 Mock Batch，执行 `Clean Batch` 或 `Matte Batch` / `Outline Batch`，等待当前批次被处理结果替换。
3. 再右键 Mock Batch，点 `Show Previous`，确认缩略图切回处理前版本，标题出现 `previous` 后缀。
4. 右键点 `Show Current`，确认缩略图回到处理后的当前版本，标题后缀消失。
5. 在 `Show Previous` 状态下尝试 Left/Right、K/R/F、过滤和 Split/Export，确认这些操作仍按当前批次位置/资产生效。
6. 对尚未经过批处理的 Mock Batch 点 `Show Previous`，应显示 `No previous batch version`，画面保持当前版本。
7. 可选：保存并重新打开项目，确认 graph batch 的 current/previous 切换状态可以恢复。

### 本轮完整 diff（报告追加前）

```diff
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index c97601c..e5ca2fe 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -149,6 +149,38 @@ func test_canvas_batch_card_focuses_visible_review_thumbnails() -> void:
     assert_eq(item["focus_asset_id"], ids[1])


+func test_canvas_batch_card_keeps_previous_version_for_compare() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var before_ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var after_ids := [
+        _register_asset(Color.GREEN, "green"),
+        _register_asset(Color.YELLOW, "yellow"),
+    ]
+    var card: Node = canvas._add_batch_card(before_ids, Vector2(16, 24), "Batch", "batch_1", false)
+
+    canvas._replace_batch_asset_ids("batch_1", after_ids, false, before_ids)
+    assert_eq(card.asset_ids, after_ids)
+    assert_eq(card._get_compare_asset_ids(), before_ids)
+    assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_CURRENT)
+    assert_eq(card.get_visible_asset_ids(), after_ids)
+
+    assert_true(
+        canvas._set_batch_compare_mode("batch_1", CanvasBatchCardScript.COMPARE_PREVIOUS, false)
+    )
+    assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_PREVIOUS)
+    assert_eq(card._texture_asset_id_for(after_ids[0]), before_ids[0])
+    assert_eq(card._texture_asset_id_for(after_ids[1]), before_ids[1])
+
+    var data: Dictionary = canvas.export_canvas_data()
+    var item: Dictionary = data["items"][0]
+    assert_eq(item["compare_asset_ids"], before_ids)
+    assert_eq(item["compare_mode"], CanvasBatchCardScript.COMPARE_PREVIOUS)
+
+
 func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
@@ -316,6 +348,58 @@ func test_graph_batch_card_persists_focus_asset_id_in_graph_params() -> void:
     assert_eq(reloaded_card._get_focus_asset_id(), ids[0])


+func test_graph_batch_card_persists_compare_state_in_graph_params() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var before_ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var after_ids := [
+        _register_asset(Color.GREEN, "green"),
+        _register_asset(Color.YELLOW, "yellow"),
+    ]
+    var graph := GraphScript.new()
+    graph.id = "graph_batch_compare_test"
+    graph.add_node(
+        BatchNodeScript.new(),
+        "batch_1",
+        {"label": "Candidates", "asset_ids": before_ids},
+        Vector2(16, 24)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var card: Node = canvas._add_batch_card(
+        before_ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+    )
+    canvas._replace_batch_asset_ids("node_item_1", after_ids, false, before_ids)
+    assert_true(
+        canvas._set_batch_compare_mode("node_item_1", CanvasBatchCardScript.COMPARE_PREVIOUS, false)
+    )
+    assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_PREVIOUS)
+
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+    var batch_node: Dictionary = graph_data["nodes"][0]
+    assert_eq(batch_node["params"]["asset_ids"], after_ids)
+    assert_eq(batch_node["params"]["compare_asset_ids"], before_ids)
+    assert_eq(batch_node["params"]["compare_mode"], CanvasBatchCardScript.COMPARE_PREVIOUS)
+
+    var canvas_data: Dictionary = canvas.export_canvas_data()
+    assert_false(Dictionary(canvas_data["items"][0]).has("compare_asset_ids"))
+    assert_false(Dictionary(canvas_data["items"][0]).has("compare_mode"))
+
+    var reloaded_canvas: Control = CanvasScript.new()
+    reloaded_canvas.size = Vector2(512, 512)
+    add_child_autofree(reloaded_canvas)
+    await wait_process_frames(2)
+    reloaded_canvas.load_canvas_data(canvas_data)
+    var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]
+
+    assert_eq(reloaded_card.asset_ids, after_ids)
+    assert_eq(reloaded_card._get_compare_asset_ids(), before_ids)
+    assert_eq(reloaded_card._get_compare_mode(), CanvasBatchCardScript.COMPARE_PREVIOUS)
+
+
 func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 0d4f595..f121750 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -5,6 +5,7 @@ extends Node2D
 ## M3 过渡期同时支持旧 batch_card 和正式 graph batch 节点引用的渲染。

 const IdUtil := preload("res://core/util/id_util.gd")
+const Strings := preload("res://ui/shell/strings.gd")

 const CARD_WIDTH := 600
 const HEADER_HEIGHT := 40
@@ -25,6 +26,8 @@ const REVIEW_REJECT := "reject"
 const REVIEW_FLAG := "flag"
 const FILTER_ALL := "all"
 const FILTER_PENDING := "pending"
+const COMPARE_CURRENT := "current"
+const COMPARE_PREVIOUS := "previous"
 const KEEP_MARK := Color(0.2, 0.88, 0.46, 1.0)
 const REJECT_MARK := Color(0.95, 0.22, 0.24, 0.95)
 const FLAG_MARK := Color(1.0, 0.78, 0.18, 1.0)
@@ -40,6 +43,8 @@ var selected_asset_ids: Array[String] = []
 var review_states := {}
 var review_filter := FILTER_ALL
 var focus_asset_id := ""
+var compare_asset_ids: Array[String] = []
+var compare_mode := COMPARE_CURRENT
 var label := ""
 var locked := false

@@ -65,6 +70,12 @@ func setup_from_data(data: Dictionary) -> void:
     focus_asset_id = _normalize_focus_asset_id(
         String(graph_params.get("focus_asset_id", data.get("focus_asset_id", "")))
     )
+    compare_asset_ids = _aligned_compare_asset_ids(
+        graph_params.get("compare_asset_ids", data.get("compare_asset_ids", []))
+    )
+    compare_mode = _normalize_compare_mode(
+        String(graph_params.get("compare_mode", data.get("compare_mode", COMPARE_CURRENT)))
+    )
     _prune_selected_to_visible()
     _prune_focus_to_visible()
     locked = bool(data.get("locked", false))
@@ -96,6 +107,8 @@ func to_canvas_data() -> Dictionary:
         "review_states": review_states.duplicate(true),
         "review_filter": review_filter,
         "focus_asset_id": focus_asset_id,
+        "compare_asset_ids": compare_asset_ids.duplicate(),
+        "compare_mode": compare_mode,
         "label": label,
         "position": [int(round(position.x)), int(round(position.y))],
         "z_index": z_index,
@@ -132,6 +145,8 @@ func set_asset_ids(new_asset_ids: Array) -> void:
         if not asset_ids.has(selected_id):
             selected_asset_ids.erase(selected_id)
     review_states = _review_state_map(review_states, asset_ids)
+    compare_asset_ids = _aligned_compare_asset_ids(compare_asset_ids)
+    compare_mode = _normalize_compare_mode(compare_mode)
     _prune_selected_to_visible()
     _prune_focus_to_visible()
     _rebuild_thumbnails()
@@ -235,6 +250,26 @@ func _focus_asset_id_relative(step: int) -> String:
     return visible_ids[posmod(anchor_index + step, visible_ids.size())]


+func _get_compare_asset_ids() -> Array[String]:
+    return compare_asset_ids.duplicate()
+
+
+func _get_compare_mode() -> String:
+    return compare_mode
+
+
+func _set_compare_state(new_compare_asset_ids: Array, new_compare_mode: String) -> void:
+    compare_asset_ids = _aligned_compare_asset_ids(new_compare_asset_ids)
+    compare_mode = _normalize_compare_mode(new_compare_mode)
+    _rebuild_thumbnails()
+    queue_redraw()
+
+
+func _set_compare_mode(new_compare_mode: String) -> void:
+    compare_mode = _normalize_compare_mode(new_compare_mode)
+    queue_redraw()
+
+
 func toggle_asset_at_world(world_position: Vector2) -> bool:
     var index := asset_index_at_world(world_position)
     var visible_ids := get_visible_asset_ids()
@@ -280,6 +315,8 @@ func _draw() -> void:
         var title := "%s (%d)" % [label, asset_ids.size()]
         if visible_count != asset_ids.size():
             title = "%s (%d/%d)" % [label, visible_count, asset_ids.size()]
+        if compare_mode == COMPARE_PREVIOUS:
+            title = "%s - %s" % [title, Strings.BATCH_COMPARE_PREVIOUS_SUFFIX]
         draw_string(
             _font,
             Vector2(PADDING, 28),
@@ -300,7 +337,7 @@ func _draw() -> void:

 func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
     draw_rect(rect, THUMB_BACKGROUND, true)
-    var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
+    var texture: Texture2D = _thumbnail_textures.get(_texture_asset_id_for(asset_id), null)
     if texture != null:
         var image_size := texture.get_size()
         var scale := minf(rect.size.x / image_size.x, rect.size.y / image_size.y)
@@ -382,7 +419,11 @@ func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:

 func _rebuild_thumbnails() -> void:
     _thumbnail_textures.clear()
-    for asset_id in asset_ids:
+    var texture_asset_ids := asset_ids.duplicate()
+    for compare_asset_id in compare_asset_ids:
+        if not texture_asset_ids.has(compare_asset_id):
+            texture_asset_ids.append(compare_asset_id)
+    for asset_id in texture_asset_ids:
         var image := AssetLibrary.get_image(asset_id)
         if image == null:
             continue
@@ -460,6 +501,19 @@ func _normalize_focus_asset_id(new_focus_asset_id: String) -> String:
     return new_focus_asset_id if asset_ids.has(new_focus_asset_id) else ""


+func _normalize_compare_mode(new_compare_mode: String) -> String:
+    if new_compare_mode == COMPARE_PREVIOUS and not compare_asset_ids.is_empty():
+        return COMPARE_PREVIOUS
+    return COMPARE_CURRENT
+
+
+func _aligned_compare_asset_ids(value: Variant) -> Array[String]:
+    var result := _string_array(value)
+    if result.size() != asset_ids.size():
+        return []
+    return result
+
+
 func _prune_selected_to_visible() -> void:
     var visible_lookup := _visible_lookup()
     for selected_id in selected_asset_ids.duplicate():
@@ -495,6 +549,15 @@ func _visible_selected_array(value: Array) -> Array[String]:
     return result


+func _texture_asset_id_for(asset_id: String) -> String:
+    if compare_mode != COMPARE_PREVIOUS:
+        return asset_id
+    var index := asset_ids.find(asset_id)
+    if index < 0 or index >= compare_asset_ids.size():
+        return asset_id
+    return compare_asset_ids[index]
+
+
 func _visible_lookup() -> Dictionary:
     return _lookup(get_visible_asset_ids())

diff --git a/pixel/ui/canvas/canvas_batch_ops.gd b/pixel/ui/canvas/canvas_batch_ops.gd
index f6e3959..7bbb76a 100644
--- a/pixel/ui/canvas/canvas_batch_ops.gd
+++ b/pixel/ui/canvas/canvas_batch_ops.gd
@@ -41,6 +41,7 @@ static func replace_asset_ids(
     card_id: String,
     new_asset_ids: Array,
     record_undo: bool,
+    compare_asset_ids: Array,
     select_only: Callable,
     emit_changed: Callable
 ) -> void:
@@ -51,19 +52,27 @@ static func replace_asset_ids(
     var before_review_states: Dictionary = item.get_review_states()
     var before_review_filter: String = item.get_review_filter()
     var before_focus_asset_id: String = item._get_focus_asset_id()
+    var before_compare_asset_ids: Array = item._get_compare_asset_ids()
+    var before_compare_mode: String = item._get_compare_mode()
     var after := new_asset_ids.duplicate()
     var after_review_states := {}
     var after_review_filter := CanvasBatchCardScript.FILTER_ALL
     var after_focus_asset_id := ""
+    var after_compare_asset_ids := _aligned_compare_asset_ids(compare_asset_ids, after)
+    var after_compare_mode := CanvasBatchCardScript.COMPARE_CURRENT
     var do_replace := func() -> void:
         GraphItemBridge.apply_batch_asset_ids(item, after, AssetLibrary)
         _apply_review_states(item, after_review_states)
         _apply_review_filter(item, after_review_filter)
         _apply_focus_asset_id(item, after_focus_asset_id)
+        _apply_compare_state(item, after_compare_asset_ids, after_compare_mode)
         GraphItemBridge.sync_batch_node_asset_ids(item, after)
         GraphItemBridge.sync_batch_node_review_states(item, after_review_states)
         GraphItemBridge.sync_batch_node_review_filter(item, after_review_filter)
         GraphItemBridge.sync_batch_node_focus_asset_id(item, after_focus_asset_id)
+        GraphItemBridge.sync_batch_node_compare_state(
+            item, after_compare_asset_ids, after_compare_mode
+        )
         select_only.call([card_id])
         emit_changed.call()
     var undo_replace := func() -> void:
@@ -71,10 +80,14 @@ static func replace_asset_ids(
         _apply_review_states(item, before_review_states)
         _apply_review_filter(item, before_review_filter)
         _apply_focus_asset_id(item, before_focus_asset_id)
+        _apply_compare_state(item, before_compare_asset_ids, before_compare_mode)
         GraphItemBridge.sync_batch_node_asset_ids(item, before)
         GraphItemBridge.sync_batch_node_review_states(item, before_review_states)
         GraphItemBridge.sync_batch_node_review_filter(item, before_review_filter)
         GraphItemBridge.sync_batch_node_focus_asset_id(item, before_focus_asset_id)
+        GraphItemBridge.sync_batch_node_compare_state(
+            item, before_compare_asset_ids, before_compare_mode
+        )
         select_only.call([card_id])
         emit_changed.call()
     if record_undo:
@@ -171,6 +184,46 @@ static func set_review_filter(
     return true


+static func set_compare_mode(
+    items_by_id: Dictionary,
+    card_id: String,
+    compare_mode: String,
+    record_undo: bool,
+    select_only: Callable,
+    emit_changed: Callable
+) -> bool:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return false
+    var before_mode: String = item._get_compare_mode()
+    var after_mode := _normalize_compare_mode(item, compare_mode)
+    if before_mode == after_mode:
+        return true
+    if (
+        after_mode == CanvasBatchCardScript.COMPARE_PREVIOUS
+        and item._get_compare_asset_ids().is_empty()
+    ):
+        return false
+
+    var compare_asset_ids: Array = item._get_compare_asset_ids()
+    var do_compare := func() -> void:
+        _apply_compare_mode(item, after_mode)
+        GraphItemBridge.sync_batch_node_compare_state(item, compare_asset_ids, after_mode)
+        select_only.call([card_id])
+        emit_changed.call()
+    var undo_compare := func() -> void:
+        _apply_compare_mode(item, before_mode)
+        GraphItemBridge.sync_batch_node_compare_state(item, compare_asset_ids, before_mode)
+        select_only.call([card_id])
+        emit_changed.call()
+
+    if record_undo:
+        UndoService.perform_action("Set batch compare mode", do_compare, undo_compare)
+    else:
+        do_compare.call()
+    return true
+
+
 static func focus_relative(
     items_by_id: Dictionary,
     card_id: String,
@@ -270,6 +323,16 @@ static func _apply_selected_asset_ids(item: Node, selected_asset_ids: Array) ->
     item._set_selected_asset_ids(selected_asset_ids)


+static func _apply_compare_state(
+    item: Node, compare_asset_ids: Array, compare_mode: String
+) -> void:
+    item._set_compare_state(compare_asset_ids, compare_mode)
+
+
+static func _apply_compare_mode(item: Node, compare_mode: String) -> void:
+    item._set_compare_mode(compare_mode)
+
+
 static func _normalize_review_state(review_state: String) -> String:
     if (
         review_state
@@ -298,6 +361,24 @@ static func _normalize_review_filter(review_filter: String) -> String:
     return CanvasBatchCardScript.FILTER_ALL


+static func _normalize_compare_mode(item: Node, compare_mode: String) -> String:
+    if (
+        compare_mode == CanvasBatchCardScript.COMPARE_PREVIOUS
+        and not item._get_compare_asset_ids().is_empty()
+    ):
+        return CanvasBatchCardScript.COMPARE_PREVIOUS
+    return CanvasBatchCardScript.COMPARE_CURRENT
+
+
+static func _aligned_compare_asset_ids(compare_asset_ids: Array, current_asset_ids: Array) -> Array:
+    var result := []
+    if compare_asset_ids.size() != current_asset_ids.size():
+        return result
+    for raw_id in compare_asset_ids:
+        result.append(String(raw_id))
+    return result
+
+
 static func _focus_result(item: Node, focus_asset_id: String) -> Dictionary:
     var visible_ids: Array = item.get_visible_asset_ids()
     return {
diff --git a/pixel/ui/canvas/canvas_graph_item_bridge.gd b/pixel/ui/canvas/canvas_graph_item_bridge.gd
index f5c3980..cebc357 100644
--- a/pixel/ui/canvas/canvas_graph_item_bridge.gd
+++ b/pixel/ui/canvas/canvas_graph_item_bridge.gd
@@ -57,6 +57,12 @@ static func sync_batch_node_asset_ids(item: Node, asset_ids: Array) -> void:
             params["review_states"] = _review_state_map(params.get("review_states", {}), asset_ids)
             params["review_filter"] = _review_filter(params.get("review_filter", "all"))
             params["focus_asset_id"] = _focus_asset_id(params.get("focus_asset_id", ""), asset_ids)
+            params["compare_asset_ids"] = _compare_asset_ids(
+                params.get("compare_asset_ids", []), asset_ids
+            )
+            params["compare_mode"] = _compare_mode(
+                params.get("compare_mode", "current"), params["compare_asset_ids"]
+            )
             node_data["params"] = params
             changed = true
         nodes.append(node_data)
@@ -156,6 +162,41 @@ static func sync_batch_node_focus_asset_id(item: Node, focus_asset_id: String) -
         ProjectService.set_graph_data(item.graph_id, graph_data, true)


+static func sync_batch_node_compare_state(
+    item: Node, compare_asset_ids: Array, compare_mode: String
+) -> void:
+    if not item.has_method("has_graph_binding") or not item.has_graph_binding():
+        return
+
+    var graph_data := ProjectService.get_graph_data(item.graph_id)
+    if graph_data.is_empty():
+        return
+
+    var nodes := []
+    var changed := false
+    for raw_node in graph_data.get("nodes", []):
+        if not (raw_node is Dictionary):
+            nodes.append(raw_node)
+            continue
+        var node_data: Dictionary = raw_node
+        if (
+            String(node_data.get("id", "")) == item.node_id
+            and String(node_data.get("type", "")) == "batch"
+        ):
+            var params: Dictionary = Dictionary(node_data.get("params", {})).duplicate(true)
+            params["compare_asset_ids"] = _compare_asset_ids(
+                compare_asset_ids, params.get("asset_ids", [])
+            )
+            params["compare_mode"] = _compare_mode(compare_mode, params["compare_asset_ids"])
+            node_data["params"] = params
+            changed = true
+        nodes.append(node_data)
+
+    if changed:
+        graph_data["nodes"] = nodes
+        ProjectService.set_graph_data(item.graph_id, graph_data, true)
+
+
 static func _string_array(value: Variant) -> Array[String]:
     var result: Array[String] = []
     if value is Array:
@@ -203,3 +244,17 @@ static func _review_filter(value: Variant) -> String:
 static func _focus_asset_id(value: Variant, valid_asset_ids: Variant) -> String:
     var asset_id := String(value)
     return asset_id if _string_array(valid_asset_ids).has(asset_id) else ""
+
+
+static func _compare_asset_ids(value: Variant, current_asset_ids: Variant) -> Array[String]:
+    var result := _string_array(value)
+    if result.size() == _string_array(current_asset_ids).size():
+        return result
+    var empty: Array[String] = []
+    return empty
+
+
+static func _compare_mode(value: Variant, compare_asset_ids: Array) -> String:
+    if String(value) == CanvasBatchCardScript.COMPARE_PREVIOUS and not compare_asset_ids.is_empty():
+        return CanvasBatchCardScript.COMPARE_PREVIOUS
+    return CanvasBatchCardScript.COMPARE_CURRENT
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 4749072..343a106 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -84,7 +84,7 @@ func _process(delta: float) -> void:
     if _cull_elapsed >= CULL_INTERVAL_SECONDS:
         _cull_elapsed = 0.0
         _update_item_visibility()
-    _update_cleanup_preview_alt_state()
+    _cleanup_preview.update_alt_state()
     if tool_manager != null and tool_manager.needs_redraw():
         queue_redraw()

@@ -488,10 +488,6 @@ func _get_batch_selected_asset_ids(card_id: String) -> Array:
     return BatchOps.get_selected_asset_ids(_items_by_id, card_id)


-func _get_batch_marked_asset_ids(card_id: String, review_state: String) -> Array:
-    return BatchOps.get_marked_asset_ids(_items_by_id, card_id, review_state)
-
-
 func _set_batch_review_filter(
     card_id: String, review_filter: String, record_undo: bool = true
 ) -> bool:
@@ -501,10 +497,24 @@ func _set_batch_review_filter(


 func _replace_batch_asset_ids(
-    card_id: String, new_asset_ids: Array, record_undo: bool = true
+    card_id: String, new_asset_ids: Array, record_undo: bool = true, compare_asset_ids: Array = []
 ) -> void:
     BatchOps.replace_asset_ids(
-        _items_by_id, card_id, new_asset_ids, record_undo, _select_only, _emit_canvas_changed
+        _items_by_id,
+        card_id,
+        new_asset_ids,
+        record_undo,
+        compare_asset_ids,
+        _select_only,
+        _emit_canvas_changed
+    )
+
+
+func _set_batch_compare_mode(
+    card_id: String, compare_mode: String, record_undo: bool = true
+) -> bool:
+    return BatchOps.set_compare_mode(
+        _items_by_id, card_id, compare_mode, record_undo, _select_only, _emit_canvas_changed
     )


@@ -972,10 +982,6 @@ func _on_cleanup_grid_changed(scale: float, offset: Vector2) -> void:
     cleanup_grid_changed.emit(scale, offset)


-func _update_cleanup_preview_alt_state() -> void:
-    _cleanup_preview.update_alt_state()
-
-
 func _tool_manager_handles(event: InputEvent) -> bool:
     return ToolInputPolicy.tool_manager_handles(
         tool_manager, event, self, _get_active_tool_target()
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index f66c064..cdffc92 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -53,6 +53,8 @@ const BATCH_MENU_FILTER_KEEP := 11
 const BATCH_MENU_FILTER_PENDING := 12
 const BATCH_MENU_FILTER_REJECT := 13
 const BATCH_MENU_FILTER_FLAG := 14
+const BATCH_MENU_COMPARE_CURRENT := 15
+const BATCH_MENU_COMPARE_PREVIOUS := 16
 const SELECTION_TOOLS_VISIBLE := false

 var _canvas: Control = null
@@ -316,6 +318,9 @@ func _create_batch_menu() -> void:
     _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_REJECT, BATCH_MENU_FILTER_REJECT)
     _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_FLAG, BATCH_MENU_FILTER_FLAG)
     _batch_menu.add_separator()
+    _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_CURRENT, BATCH_MENU_COMPARE_CURRENT)
+    _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_PREVIOUS, BATCH_MENU_COMPARE_PREVIOUS)
+    _batch_menu.add_separator()
     _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT_KEEP, BATCH_MENU_SPLIT_KEEP)
     _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
     _batch_menu.add_separator()
@@ -457,6 +462,14 @@ func _on_batch_menu_id_pressed(id: int) -> void:
             _set_batch_review_filter(
                 CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_SHOW_FLAG
             )
+        BATCH_MENU_COMPARE_CURRENT:
+            _set_batch_compare_mode(
+                CanvasBatchCardScript.COMPARE_CURRENT, Strings.STATUS_BATCH_COMPARE_CURRENT
+            )
+        BATCH_MENU_COMPARE_PREVIOUS:
+            _set_batch_compare_mode(
+                CanvasBatchCardScript.COMPARE_PREVIOUS, Strings.STATUS_BATCH_COMPARE_PREVIOUS
+            )
         BATCH_MENU_SPLIT_KEEP:
             var new_keep_card: Variant = _canvas._split_batch_marked(
                 _batch_menu_card_id,
@@ -567,6 +580,13 @@ func _set_batch_review_filter(review_filter: String, status_text: String) -> voi
     _status_label.text = status_text


+func _set_batch_compare_mode(compare_mode: String, status_text: String) -> void:
+    if not _canvas._set_batch_compare_mode(_batch_menu_card_id, compare_mode, true):
+        _status_label.text = Strings.STATUS_BATCH_COMPARE_EMPTY
+        return
+    _status_label.text = status_text
+
+
 func _emit_batch_export(asset_ids: Array) -> void:
     var snapshots := []
     for asset_id in asset_ids:
diff --git a/pixel/ui/shell/m2_action_controller.gd b/pixel/ui/shell/m2_action_controller.gd
index c42ea1e..ad5462f 100644
--- a/pixel/ui/shell/m2_action_controller.gd
+++ b/pixel/ui/shell/m2_action_controller.gd
@@ -331,14 +331,18 @@ func _on_batch_task_finished(result: Variant, done_status: String) -> void:
         ErrorHelper.show_matte_error(_dialog_parent, first_warning)

     var new_asset_ids: Array[String] = []
+    var source_asset_ids: Array[String] = []
     for item_result in result.get("items", []):
         var parent_asset_id := String(item_result.get("parent_asset", ""))
         var asset_id := PixelOperations.register_result_asset(
             AssetLibrary, parent_asset_id, item_result
         )
         new_asset_ids.append(asset_id)
+        source_asset_ids.append(parent_asset_id)

-    _canvas._replace_batch_asset_ids(String(result.get("card_id", "")), new_asset_ids, true)
+    _canvas._replace_batch_asset_ids(
+        String(result.get("card_id", "")), new_asset_ids, true, source_asset_ids
+    )
     _status_label.text = done_status


diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index ba97d1e..0e822f3 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -58,6 +58,9 @@ const STATUS_BATCH_SHOW_FLAG := "Showing flagged thumbnails"
 const STATUS_BATCH_FILTER_FAILED := "Batch filter failed"
 const STATUS_BATCH_FOCUS_EMPTY := "No visible thumbnails in batch"
 const STATUS_BATCH_FOCUS_FORMAT := "Focused thumbnail %d of %d"
+const STATUS_BATCH_COMPARE_CURRENT := "Showing current batch"
+const STATUS_BATCH_COMPARE_PREVIOUS := "Showing previous batch"
+const STATUS_BATCH_COMPARE_EMPTY := "No previous batch version"
 const STATUS_MOCK_GENERATE_DONE := "Mock batch generated: %d sprites"
 const STATUS_MOCK_GENERATE_FAILED := "Mock batch generation failed"
 const STATUS_GRAPH_RUN_DONE := "Graph run complete: %d sprites"
@@ -154,6 +157,9 @@ const BATCH_ACTION_SHOW_KEEP := "Show Keep"
 const BATCH_ACTION_SHOW_PENDING := "Show Pending"
 const BATCH_ACTION_SHOW_REJECT := "Show Reject"
 const BATCH_ACTION_SHOW_FLAG := "Show Flagged"
+const BATCH_ACTION_COMPARE_CURRENT := "Show Current"
+const BATCH_ACTION_COMPARE_PREVIOUS := "Show Previous"
+const BATCH_COMPARE_PREVIOUS_SUFFIX := "previous"
 const BATCH_ACTION_SPLIT_KEEP := "Split Kept"
 const BATCH_ACTION_SPLIT := "Split Selected"
 const BATCH_ACTION_EXPORT := "Export Batch"
diff --git a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
index 1239323..a1f385f 100644
--- a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
+++ b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
@@ -127,7 +127,7 @@ func get_canvas_actions() -> Array[Dictionary]
 新概念，本模型的核心。装一个批次的图片队列，是「AI 输出自由」与「批量加工」的落脚点。

 - **双身份**：① 图节点（`type=batch`，`category=container`，`is_canvas_resident()=true`）；② 画布卡（PROJECT-FORMAT canvas.json 的 `node` 引用，特化渲染为容器卡）。
-- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），可选 `review_filter` 记录当前审阅过滤器（`all|pending|keep|reject|flag`），可选 `focus_asset_id` 记录当前键盘审阅焦点，三者均随 `asset_ids` 过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
+- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），可选 `review_filter` 记录当前审阅过滤器（`all|pending|keep|reject|flag`），可选 `focus_asset_id` 记录当前键盘审阅焦点，可选 `compare_asset_ids` / `compare_mode` 记录上一版 A/B 对比入口，均随 `asset_ids` 对齐或过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
 - **整批菜单**（`get_canvas_actions()` 声明，边框弹出）：整批清洗 / 整批抠图 / 整批描边 / 整批量化 / 导出整批 / 拆小批次 / 逐张发送到编辑器。均调 core，记 undo + provenance（§4.7）。
 - **拆小批次**：勾选子集 → 生成子 `batch`（新卡，引用子集 asset_id），可独立处理；复用 `select` 语义。
 - **分离单图**：把某张拖出批次卡 → 成为独立 sprite 卡（仍在同一画布，见 PROJECT-FORMAT §4 `sprite`）。
diff --git a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
index 0ba739c..02dc8ef 100644
--- a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
+++ b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
@@ -111,6 +111,8 @@ my_project.pxproj (ZIP)
       "review_states": { "uuid-a": "keep" },
       "review_filter": "all",
       "focus_asset_id": "uuid-a",
+      "compare_asset_ids": ["uuid-a-before", "uuid-b-before"],
+      "compare_mode": "current",
       "label": "Batch",
       "position": [320, 64],
       "z_index": 1,
diff --git a/pixel/scripts/verify_m3_ux6.sh b/pixel/scripts/verify_m3_ux6.sh
new file mode 100755
index 0000000..4bcd93a
--- /dev/null
+++ b/pixel/scripts/verify_m3_ux6.sh
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
+  echo "Staged image files are not allowed for M3 UX-6 commits." >&2
+  exit 1
+fi
+
+echo "verify_m3_ux6: ok"
```

## 2026-06-18 M3 UX-6b 批次前后并排对比

### 本轮实现说明

- 在 UX-6 已有 `current` / `previous` A/B 切换基础上，新增 `split` compare mode。
- 批次右键菜单新增 `Show Compare`：每个缩略图左半显示上一版，右半显示当前版，中间用细分隔线区分。
- `Show Compare` 仍只改变视觉来源；当前 `asset_ids`、审阅状态、过滤、选中、Split/Export 和后续处理语义保持指向当前批次。
- Graph batch 的 `compare_mode` 现在允许 `current|previous|split`，旧 `batch_card` 兼容字段同步支持该值。
- 新增 `verify_m3_ux6b.sh`，用于本轮最小专项验收。

### 验证结果

- `./pixel/scripts/lint.sh`：通过，105 files unchanged，no problems found。
- `./pixel/scripts/run_tests.sh`：通过，145/145 tests，1204 asserts。
- `./pixel/scripts/verify_m3_ux6b.sh`：通过，包含 editor game view 配置、lint、全量测试、UI scaling 检查、export templates 本地 gate、staged 图片检查。
- 已知既有输出：GUT 仍报告 1 orphan、Godot 退出时仍有 ObjectDB/resource warning；本轮未新增相关失败。

### 人工测试步骤

1. 打开 PixelForge，执行 `File > Generate Mock Batch`。
2. 右键 Mock Batch，执行 `Clean Batch` 或 `Matte Batch` / `Outline Batch`，等待批次替换为处理后结果。
3. 右键 Mock Batch，点击 `Show Compare`，确认每个缩略图左半是处理前版本、右半是当前版本，标题出现 `compare` 后缀。
4. 右键切到 `Show Previous`，确认仍可只看上一版；再切回 `Show Current`，确认只看当前版。
5. 在 `Show Compare` 状态下试 Left/Right、K/R/F、过滤、Split/Export，确认这些操作仍作用于当前批次资产。
6. 对未处理过的 Mock Batch 点击 `Show Compare`，应提示 `No previous batch version`，画面保持当前版本。

### 本轮完整 diff（报告追加前）

```diff
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index e5ca2fe..fc97059 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -175,10 +175,17 @@ func test_canvas_batch_card_keeps_previous_version_for_compare() -> void:
     assert_eq(card._texture_asset_id_for(after_ids[0]), before_ids[0])
     assert_eq(card._texture_asset_id_for(after_ids[1]), before_ids[1])

+    assert_true(
+        canvas._set_batch_compare_mode("batch_1", CanvasBatchCardScript.COMPARE_SPLIT, false)
+    )
+    assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_SPLIT)
+    assert_eq(card._texture_asset_id_for(after_ids[0]), after_ids[0])
+    assert_eq(card._compare_asset_id_for(after_ids[0]), before_ids[0])
+
     var data: Dictionary = canvas.export_canvas_data()
     var item: Dictionary = data["items"][0]
     assert_eq(item["compare_asset_ids"], before_ids)
-    assert_eq(item["compare_mode"], CanvasBatchCardScript.COMPARE_PREVIOUS)
+    assert_eq(item["compare_mode"], CanvasBatchCardScript.COMPARE_SPLIT)


 func test_graph_batch_card_exports_node_reference_and_syncs_asset_replacement() -> void:
@@ -374,15 +381,15 @@ func test_graph_batch_card_persists_compare_state_in_graph_params() -> void:
     )
     canvas._replace_batch_asset_ids("node_item_1", after_ids, false, before_ids)
     assert_true(
-        canvas._set_batch_compare_mode("node_item_1", CanvasBatchCardScript.COMPARE_PREVIOUS, false)
+        canvas._set_batch_compare_mode("node_item_1", CanvasBatchCardScript.COMPARE_SPLIT, false)
     )
-    assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_PREVIOUS)
+    assert_eq(card._get_compare_mode(), CanvasBatchCardScript.COMPARE_SPLIT)

     var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
     var batch_node: Dictionary = graph_data["nodes"][0]
     assert_eq(batch_node["params"]["asset_ids"], after_ids)
     assert_eq(batch_node["params"]["compare_asset_ids"], before_ids)
-    assert_eq(batch_node["params"]["compare_mode"], CanvasBatchCardScript.COMPARE_PREVIOUS)
+    assert_eq(batch_node["params"]["compare_mode"], CanvasBatchCardScript.COMPARE_SPLIT)

     var canvas_data: Dictionary = canvas.export_canvas_data()
     assert_false(Dictionary(canvas_data["items"][0]).has("compare_asset_ids"))
@@ -397,7 +404,7 @@ func test_graph_batch_card_persists_compare_state_in_graph_params() -> void:

     assert_eq(reloaded_card.asset_ids, after_ids)
     assert_eq(reloaded_card._get_compare_asset_ids(), before_ids)
-    assert_eq(reloaded_card._get_compare_mode(), CanvasBatchCardScript.COMPARE_PREVIOUS)
+    assert_eq(reloaded_card._get_compare_mode(), CanvasBatchCardScript.COMPARE_SPLIT)


 func test_graph_node_card_exports_node_reference_and_survives_load() -> void:
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index f121750..78a6e5a 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -28,10 +28,12 @@ const FILTER_ALL := "all"
 const FILTER_PENDING := "pending"
 const COMPARE_CURRENT := "current"
 const COMPARE_PREVIOUS := "previous"
+const COMPARE_SPLIT := "split"
 const KEEP_MARK := Color(0.2, 0.88, 0.46, 1.0)
 const REJECT_MARK := Color(0.95, 0.22, 0.24, 0.95)
 const FLAG_MARK := Color(1.0, 0.78, 0.18, 1.0)
 const FOCUS_BORDER := Color(0.96, 0.96, 0.9, 1.0)
+const COMPARE_DIVIDER := Color(0.96, 0.96, 0.9, 0.85)
 const INPUT_PORTS: Array[String] = ["in"]
 const OUTPUT_PORTS: Array[String] = ["images", "assets"]

@@ -317,6 +319,8 @@ func _draw() -> void:
             title = "%s (%d/%d)" % [label, visible_count, asset_ids.size()]
         if compare_mode == COMPARE_PREVIOUS:
             title = "%s - %s" % [title, Strings.BATCH_COMPARE_PREVIOUS_SUFFIX]
+        elif compare_mode == COMPARE_SPLIT:
+            title = "%s - %s" % [title, Strings.BATCH_COMPARE_SPLIT_SUFFIX]
         draw_string(
             _font,
             Vector2(PADDING, 28),
@@ -337,18 +341,43 @@ func _draw() -> void:

 func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
     draw_rect(rect, THUMB_BACKGROUND, true)
-    var texture: Texture2D = _thumbnail_textures.get(_texture_asset_id_for(asset_id), null)
+    if compare_mode == COMPARE_SPLIT:
+        _draw_split_compare_thumbnail(asset_id, rect)
+    else:
+        _draw_thumbnail_texture(_texture_asset_id_for(asset_id), rect)
+    var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
+    draw_rect(rect, border_color, false, 1.5)
+    _draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
+    if focus_asset_id == asset_id:
+        draw_rect(rect.grow(3.0), FOCUS_BORDER, false, 2.5)
+
+
+func _draw_split_compare_thumbnail(asset_id: String, rect: Rect2) -> void:
+    var compare_asset_id := _compare_asset_id_for(asset_id)
+    if compare_asset_id.is_empty():
+        _draw_thumbnail_texture(asset_id, rect)
+        return
+    var left_rect := Rect2(rect.position, Vector2(floor(rect.size.x * 0.5), rect.size.y))
+    var right_rect := Rect2(
+        Vector2(rect.position.x + left_rect.size.x, rect.position.y),
+        Vector2(rect.size.x - left_rect.size.x, rect.size.y)
+    )
+    _draw_thumbnail_texture(compare_asset_id, left_rect)
+    _draw_thumbnail_texture(asset_id, right_rect)
+    var divider_x := rect.position.x + left_rect.size.x
+    draw_line(
+        Vector2(divider_x, rect.position.y), Vector2(divider_x, rect.end.y), COMPARE_DIVIDER, 2.0
+    )
+
+
+func _draw_thumbnail_texture(asset_id: String, rect: Rect2) -> void:
+    var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
     if texture != null:
         var image_size := texture.get_size()
         var scale := minf(rect.size.x / image_size.x, rect.size.y / image_size.y)
         var draw_size := image_size * scale
         var draw_pos := rect.position + (rect.size - draw_size) * 0.5
         draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)
-    var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
-    draw_rect(rect, border_color, false, 1.5)
-    _draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
-    if focus_asset_id == asset_id:
-        draw_rect(rect.grow(3.0), FOCUS_BORDER, false, 2.5)


 func _draw_review_marker(rect: Rect2, review_state: String) -> void:
@@ -502,8 +531,10 @@ func _normalize_focus_asset_id(new_focus_asset_id: String) -> String:


 func _normalize_compare_mode(new_compare_mode: String) -> String:
-    if new_compare_mode == COMPARE_PREVIOUS and not compare_asset_ids.is_empty():
-        return COMPARE_PREVIOUS
+    if not compare_asset_ids.is_empty():
+        match new_compare_mode:
+            COMPARE_PREVIOUS, COMPARE_SPLIT:
+                return new_compare_mode
     return COMPARE_CURRENT


@@ -552,9 +583,14 @@ func _visible_selected_array(value: Array) -> Array[String]:
 func _texture_asset_id_for(asset_id: String) -> String:
     if compare_mode != COMPARE_PREVIOUS:
         return asset_id
+    var compare_asset_id := _compare_asset_id_for(asset_id)
+    return asset_id if compare_asset_id.is_empty() else compare_asset_id
+
+
+func _compare_asset_id_for(asset_id: String) -> String:
     var index := asset_ids.find(asset_id)
     if index < 0 or index >= compare_asset_ids.size():
-        return asset_id
+        return ""
     return compare_asset_ids[index]


diff --git a/pixel/ui/canvas/canvas_batch_ops.gd b/pixel/ui/canvas/canvas_batch_ops.gd
index 7bbb76a..8f56bf7 100644
--- a/pixel/ui/canvas/canvas_batch_ops.gd
+++ b/pixel/ui/canvas/canvas_batch_ops.gd
@@ -362,11 +362,10 @@ static func _normalize_review_filter(review_filter: String) -> String:


 static func _normalize_compare_mode(item: Node, compare_mode: String) -> String:
-    if (
-        compare_mode == CanvasBatchCardScript.COMPARE_PREVIOUS
-        and not item._get_compare_asset_ids().is_empty()
-    ):
-        return CanvasBatchCardScript.COMPARE_PREVIOUS
+    if not item._get_compare_asset_ids().is_empty():
+        match compare_mode:
+            CanvasBatchCardScript.COMPARE_PREVIOUS, CanvasBatchCardScript.COMPARE_SPLIT:
+                return compare_mode
     return CanvasBatchCardScript.COMPARE_CURRENT


diff --git a/pixel/ui/canvas/canvas_graph_item_bridge.gd b/pixel/ui/canvas/canvas_graph_item_bridge.gd
index cebc357..cca71d2 100644
--- a/pixel/ui/canvas/canvas_graph_item_bridge.gd
+++ b/pixel/ui/canvas/canvas_graph_item_bridge.gd
@@ -255,6 +255,8 @@ static func _compare_asset_ids(value: Variant, current_asset_ids: Variant) -> Ar


 static func _compare_mode(value: Variant, compare_asset_ids: Array) -> String:
-    if String(value) == CanvasBatchCardScript.COMPARE_PREVIOUS and not compare_asset_ids.is_empty():
-        return CanvasBatchCardScript.COMPARE_PREVIOUS
+    if not compare_asset_ids.is_empty():
+        match String(value):
+            CanvasBatchCardScript.COMPARE_PREVIOUS, CanvasBatchCardScript.COMPARE_SPLIT:
+                return String(value)
     return CanvasBatchCardScript.COMPARE_CURRENT
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index cdffc92..9ac3fa7 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -55,6 +55,7 @@ const BATCH_MENU_FILTER_REJECT := 13
 const BATCH_MENU_FILTER_FLAG := 14
 const BATCH_MENU_COMPARE_CURRENT := 15
 const BATCH_MENU_COMPARE_PREVIOUS := 16
+const BATCH_MENU_COMPARE_SPLIT := 17
 const SELECTION_TOOLS_VISIBLE := false

 var _canvas: Control = null
@@ -320,6 +321,7 @@ func _create_batch_menu() -> void:
     _batch_menu.add_separator()
     _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_CURRENT, BATCH_MENU_COMPARE_CURRENT)
     _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_PREVIOUS, BATCH_MENU_COMPARE_PREVIOUS)
+    _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_SPLIT, BATCH_MENU_COMPARE_SPLIT)
     _batch_menu.add_separator()
     _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT_KEEP, BATCH_MENU_SPLIT_KEEP)
     _batch_menu.add_item(Strings.BATCH_ACTION_SPLIT, BATCH_MENU_SPLIT)
@@ -470,6 +472,10 @@ func _on_batch_menu_id_pressed(id: int) -> void:
             _set_batch_compare_mode(
                 CanvasBatchCardScript.COMPARE_PREVIOUS, Strings.STATUS_BATCH_COMPARE_PREVIOUS
             )
+        BATCH_MENU_COMPARE_SPLIT:
+            _set_batch_compare_mode(
+                CanvasBatchCardScript.COMPARE_SPLIT, Strings.STATUS_BATCH_COMPARE_SPLIT
+            )
         BATCH_MENU_SPLIT_KEEP:
             var new_keep_card: Variant = _canvas._split_batch_marked(
                 _batch_menu_card_id,
diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index 0e822f3..f5b88fe 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -60,6 +60,7 @@ const STATUS_BATCH_FOCUS_EMPTY := "No visible thumbnails in batch"
 const STATUS_BATCH_FOCUS_FORMAT := "Focused thumbnail %d of %d"
 const STATUS_BATCH_COMPARE_CURRENT := "Showing current batch"
 const STATUS_BATCH_COMPARE_PREVIOUS := "Showing previous batch"
+const STATUS_BATCH_COMPARE_SPLIT := "Showing before/after compare"
 const STATUS_BATCH_COMPARE_EMPTY := "No previous batch version"
 const STATUS_MOCK_GENERATE_DONE := "Mock batch generated: %d sprites"
 const STATUS_MOCK_GENERATE_FAILED := "Mock batch generation failed"
@@ -159,7 +160,9 @@ const BATCH_ACTION_SHOW_REJECT := "Show Reject"
 const BATCH_ACTION_SHOW_FLAG := "Show Flagged"
 const BATCH_ACTION_COMPARE_CURRENT := "Show Current"
 const BATCH_ACTION_COMPARE_PREVIOUS := "Show Previous"
+const BATCH_ACTION_COMPARE_SPLIT := "Show Compare"
 const BATCH_COMPARE_PREVIOUS_SUFFIX := "previous"
+const BATCH_COMPARE_SPLIT_SUFFIX := "compare"
 const BATCH_ACTION_SPLIT_KEEP := "Split Kept"
 const BATCH_ACTION_SPLIT := "Split Selected"
 const BATCH_ACTION_EXPORT := "Export Batch"
diff --git a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
index a1f385f..ab049a7 100644
--- a/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
+++ b/pixelforge-plan/02-contracts/GRAPH-SCHEMA.md
@@ -127,7 +127,7 @@ func get_canvas_actions() -> Array[Dictionary]
 新概念，本模型的核心。装一个批次的图片队列，是「AI 输出自由」与「批量加工」的落脚点。

 - **双身份**：① 图节点（`type=batch`，`category=container`，`is_canvas_resident()=true`）；② 画布卡（PROJECT-FORMAT canvas.json 的 `node` 引用，特化渲染为容器卡）。
-- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），可选 `review_filter` 记录当前审阅过滤器（`all|pending|keep|reject|flag`），可选 `focus_asset_id` 记录当前键盘审阅焦点，可选 `compare_asset_ids` / `compare_mode` 记录上一版 A/B 对比入口，均随 `asset_ids` 对齐或过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
+- **持有**：已物化的 `asset_id` 队列（一个批次）+ 批次级参数 + 状态。物化内容属「逻辑」，存于 `graphs/{id}.json` 该节点 params（`asset_ids`）；批次审阅状态以可选 `review_states` 字典持久化（`asset_id → keep|reject|flag`），可选 `review_filter` 记录当前审阅过滤器（`all|pending|keep|reject|flag`），可选 `focus_asset_id` 记录当前键盘审阅焦点，可选 `compare_asset_ids` / `compare_mode`（`current|previous|split`）记录上一版 A/B 对比入口，均随 `asset_ids` 对齐或过滤；canvas.json 只存位置/层级/node_id（逻辑/视图分离，方案 A）。
 - **整批菜单**（`get_canvas_actions()` 声明，边框弹出）：整批清洗 / 整批抠图 / 整批描边 / 整批量化 / 导出整批 / 拆小批次 / 逐张发送到编辑器。均调 core，记 undo + provenance（§4.7）。
 - **拆小批次**：勾选子集 → 生成子 `batch`（新卡，引用子集 asset_id），可独立处理；复用 `select` 语义。
 - **分离单图**：把某张拖出批次卡 → 成为独立 sprite 卡（仍在同一画布，见 PROJECT-FORMAT §4 `sprite`）。
diff --git a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
index 02dc8ef..d0f4337 100644
--- a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
+++ b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
@@ -112,7 +112,7 @@ my_project.pxproj (ZIP)
       "review_filter": "all",
       "focus_asset_id": "uuid-a",
       "compare_asset_ids": ["uuid-a-before", "uuid-b-before"],
-      "compare_mode": "current",
+      "compare_mode": "current",     // current | previous | split
       "label": "Batch",
       "position": [320, 64],
       "z_index": 1,
diff --git a/pixel/scripts/verify_m3_ux6b.sh b/pixel/scripts/verify_m3_ux6b.sh
new file mode 100755
index 0000000..12f8b15
--- /dev/null
+++ b/pixel/scripts/verify_m3_ux6b.sh
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
+  echo "Staged image files are not allowed for M3 UX-6b commits." >&2
+  exit 1
+fi
+
+echo "verify_m3_ux6b: ok"
```

## 2026-06-18 M3 UX-3 批次 Focus View 最小布局

### 本轮实现说明

- 为批次卡新增 `review_layout` 视图状态，支持 `Contact Sheet` 与 `Focus View` 两种模式。
- `Contact Sheet` 保持原有网格；`Focus View` 显示一张大焦点图和底部 7 格 filmstrip，适合逐张细看。
- `Focus View` 复用已有 `focus_asset_id`、Left/Right 焦点切换、K/R/F 标记、过滤和 compare current/previous/split 绘制逻辑。
- `review_layout` 是画布视图状态：旧 `batch_card` 直接写入 canvas item；正式 graph batch 写入 canvas 的 `node` 引用，不写入 graph params，保持逻辑/视图分离。
- 右键批次菜单新增 `Contact Sheet` / `Focus View`，走 `UndoService`，可撤销布局切换。
- 为守住 `infinite_canvas.gd` 软行数上限，内联了两个一行转发 helper；文件最终 999 行。

### 验证结果

- `./pixel/scripts/lint.sh`：通过，105 files unchanged，no problems found。
- `./pixel/scripts/run_tests.sh`：通过，147/147 tests，1217 asserts。
- `./pixel/scripts/verify_m3_ux3.sh`：通过，包含 editor game view 配置、lint、全量测试、UI scaling 检查、export templates 本地 gate、staged 图片检查。
- 已知既有输出：GUT 仍报告 1 orphan、Godot 退出时仍有 ObjectDB/resource warning；本轮未新增相关失败。

### 人工测试步骤

1. 打开 PixelForge，执行 `File > Generate Mock Batch`。
2. 右键 Mock Batch，点击 `Focus View`，确认批次卡切成一张大图 + 底部 filmstrip。
3. 用 Left/Right 切换焦点，确认大图随焦点更新，底部 filmstrip 的焦点框同步移动。
4. 在 `Focus View` 下使用 K/R/F 标记，再用 `Show Keep` / `Show Pending` / `Show Reject` 过滤，确认焦点图和 filmstrip 跟随过滤结果。
5. 在 `Focus View` 下切换 `Show Current` / `Show Previous` / `Show Compare`，确认大图与 filmstrip 都沿用对比模式。
6. 右键点击 `Contact Sheet`，确认回到原网格审阅布局。
7. 可选：保存并重新打开项目，确认 graph batch 仍保持 `Focus View` 或 `Contact Sheet`。

### 本轮完整 diff（报告追加前）

```diff
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index fc97059..debfee6 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -149,6 +149,33 @@ func test_canvas_batch_card_focuses_visible_review_thumbnails() -> void:
     assert_eq(item["focus_asset_id"], ids[1])


+func test_canvas_batch_card_switches_review_layout_for_focus_view() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids: Array[String] = []
+    for index in range(20):
+        ids.append(_register_asset(Color(float(index % 5) / 4.0, 0.25, 0.75), "asset_%d" % index))
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+    var contact_height: float = card.get_canvas_bounds().size.y
+
+    assert_eq(card.get_review_layout(), CanvasBatchCardScript.LAYOUT_CONTACT)
+    assert_true(
+        canvas._set_batch_review_layout("batch_1", CanvasBatchCardScript.LAYOUT_FOCUS, false)
+    )
+    assert_eq(card.get_review_layout(), CanvasBatchCardScript.LAYOUT_FOCUS)
+    assert_true(card.get_canvas_bounds().size.y < contact_height)
+    assert_eq(card._focused_visible_asset_id(), ids[0])
+    assert_eq(card.asset_index_at_world(card.position + card._focus_rect().get_center()), 0)
+    assert_eq(card.asset_index_at_world(card.position + card._filmstrip_rect(3).get_center()), 3)
+
+    var data: Dictionary = canvas.export_canvas_data()
+    var item: Dictionary = data["items"][0]
+    assert_eq(item["review_layout"], CanvasBatchCardScript.LAYOUT_FOCUS)
+
+
 func test_canvas_batch_card_keeps_previous_version_for_compare() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
@@ -355,6 +382,45 @@ func test_graph_batch_card_persists_focus_asset_id_in_graph_params() -> void:
     assert_eq(reloaded_card._get_focus_asset_id(), ids[0])


+func test_graph_batch_card_persists_review_layout_in_canvas_data() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var graph := GraphScript.new()
+    graph.id = "graph_batch_layout_test"
+    graph.add_node(
+        BatchNodeScript.new(), "batch_1", {"label": "Candidates", "asset_ids": ids}, Vector2(16, 24)
+    )
+    ProjectService.set_graph_data(graph.id, graph.to_json(), false)
+
+    var card: Node = canvas._add_batch_card(
+        ids, Vector2(16, 24), "Candidates", "node_item_1", false, graph.id, "batch_1"
+    )
+    assert_true(
+        canvas._set_batch_review_layout("node_item_1", CanvasBatchCardScript.LAYOUT_FOCUS, false)
+    )
+    assert_eq(card.get_review_layout(), CanvasBatchCardScript.LAYOUT_FOCUS)
+
+    var graph_data: Dictionary = ProjectService.current_project.graphs[graph.id]
+    var batch_node: Dictionary = graph_data["nodes"][0]
+    assert_false(batch_node["params"].has("review_layout"))
+
+    var canvas_data: Dictionary = canvas.export_canvas_data()
+    assert_eq(canvas_data["items"][0]["review_layout"], CanvasBatchCardScript.LAYOUT_FOCUS)
+
+    var reloaded_canvas: Control = CanvasScript.new()
+    reloaded_canvas.size = Vector2(512, 512)
+    add_child_autofree(reloaded_canvas)
+    await wait_process_frames(2)
+    reloaded_canvas.load_canvas_data(canvas_data)
+    var reloaded_card: Node = reloaded_canvas._items_by_id["node_item_1"]
+
+    assert_eq(reloaded_card.get_review_layout(), CanvasBatchCardScript.LAYOUT_FOCUS)
+
+
 func test_graph_batch_card_persists_compare_state_in_graph_params() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 78a6e5a..e54db12 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -26,6 +26,8 @@ const REVIEW_REJECT := "reject"
 const REVIEW_FLAG := "flag"
 const FILTER_ALL := "all"
 const FILTER_PENDING := "pending"
+const LAYOUT_CONTACT := "contact"
+const LAYOUT_FOCUS := "focus"
 const COMPARE_CURRENT := "current"
 const COMPARE_PREVIOUS := "previous"
 const COMPARE_SPLIT := "split"
@@ -36,6 +38,9 @@ const FOCUS_BORDER := Color(0.96, 0.96, 0.9, 1.0)
 const COMPARE_DIVIDER := Color(0.96, 0.96, 0.9, 0.85)
 const INPUT_PORTS: Array[String] = ["in"]
 const OUTPUT_PORTS: Array[String] = ["images", "assets"]
+const FOCUS_IMAGE_HEIGHT := 320
+const FOCUS_FILMSTRIP_THUMB_SIZE := 72
+const FOCUS_FILMSTRIP_VISIBLE := 7

 var item_id := ""
 var graph_id := ""
@@ -47,6 +52,7 @@ var review_filter := FILTER_ALL
 var focus_asset_id := ""
 var compare_asset_ids: Array[String] = []
 var compare_mode := COMPARE_CURRENT
+var review_layout := LAYOUT_CONTACT
 var label := ""
 var locked := false

@@ -78,6 +84,7 @@ func setup_from_data(data: Dictionary) -> void:
     compare_mode = _normalize_compare_mode(
         String(graph_params.get("compare_mode", data.get("compare_mode", COMPARE_CURRENT)))
     )
+    review_layout = _normalize_review_layout(String(data.get("review_layout", LAYOUT_CONTACT)))
     _prune_selected_to_visible()
     _prune_focus_to_visible()
     locked = bool(data.get("locked", false))
@@ -99,6 +106,7 @@ func to_canvas_data() -> Dictionary:
             "position": [int(round(position.x)), int(round(position.y))],
             "z_index": z_index,
             "collapsed": false,
+            "review_layout": review_layout,
             "locked": locked,
         }
     return {
@@ -111,6 +119,7 @@ func to_canvas_data() -> Dictionary:
         "focus_asset_id": focus_asset_id,
         "compare_asset_ids": compare_asset_ids.duplicate(),
         "compare_mode": compare_mode,
+        "review_layout": review_layout,
         "label": label,
         "position": [int(round(position.x)), int(round(position.y))],
         "z_index": z_index,
@@ -223,6 +232,17 @@ func set_review_filter(new_review_filter: String) -> void:
     queue_redraw()


+func get_review_layout() -> String:
+    return review_layout
+
+
+func set_review_layout(new_review_layout: String) -> void:
+    review_layout = _normalize_review_layout(new_review_layout)
+    if review_layout == LAYOUT_FOCUS and focus_asset_id.is_empty():
+        focus_asset_id = _initial_focus_asset_id()
+    queue_redraw()
+
+
 func _get_focus_asset_id() -> String:
     return focus_asset_id

@@ -295,6 +315,8 @@ func asset_index_at_world(world_position: Vector2) -> int:
     var local := world_position - position
     if local.y < HEADER_HEIGHT:
         return -1
+    if review_layout == LAYOUT_FOCUS:
+        return _focus_layout_asset_index_at_local(local)
     var columns := _columns()
     var visible_ids := get_visible_asset_ids()
     for index in range(visible_ids.size()):
@@ -333,12 +355,28 @@ func _draw() -> void:

     var columns := _columns()
     var visible_ids := get_visible_asset_ids()
-    for index in range(visible_ids.size()):
-        _draw_thumbnail(visible_ids[index], _thumb_rect(index, columns))
+    if review_layout == LAYOUT_FOCUS:
+        _draw_focus_layout(visible_ids)
+    else:
+        for index in range(visible_ids.size()):
+            _draw_thumbnail(visible_ids[index], _thumb_rect(index, columns))
     if has_graph_binding():
         _draw_graph_ports()


+func _draw_focus_layout(visible_ids: Array[String]) -> void:
+    if visible_ids.is_empty():
+        return
+    var focused_asset_id := _focused_visible_asset_id()
+    if focused_asset_id.is_empty():
+        return
+    _draw_thumbnail(focused_asset_id, _focus_rect())
+    var start_index := _filmstrip_start_index(visible_ids)
+    var end_index := mini(visible_ids.size(), start_index + FOCUS_FILMSTRIP_VISIBLE)
+    for index in range(start_index, end_index):
+        _draw_thumbnail(visible_ids[index], _filmstrip_rect(index - start_index))
+
+
 func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
     draw_rect(rect, THUMB_BACKGROUND, true)
     if compare_mode == COMPARE_SPLIT:
@@ -417,10 +455,36 @@ func _thumb_rect(index: int, columns: int) -> Rect2:
     )


+func _focus_rect() -> Rect2:
+    return Rect2(
+        Vector2(PADDING, HEADER_HEIGHT + PADDING),
+        Vector2(CARD_WIDTH - PADDING * 2, FOCUS_IMAGE_HEIGHT)
+    )
+
+
+func _filmstrip_rect(slot_index: int) -> Rect2:
+    var y := HEADER_HEIGHT + PADDING + FOCUS_IMAGE_HEIGHT + THUMB_GAP
+    return Rect2(
+        Vector2(PADDING + slot_index * (FOCUS_FILMSTRIP_THUMB_SIZE + THUMB_GAP), y),
+        Vector2(FOCUS_FILMSTRIP_THUMB_SIZE, FOCUS_FILMSTRIP_THUMB_SIZE)
+    )
+
+
 func _card_height() -> int:
     var visible_count := get_visible_asset_ids().size()
     if visible_count <= 0:
         return MIN_CARD_HEIGHT
+    if review_layout == LAYOUT_FOCUS:
+        return maxi(
+            MIN_CARD_HEIGHT,
+            (
+                HEADER_HEIGHT
+                + PADDING * 2
+                + FOCUS_IMAGE_HEIGHT
+                + THUMB_GAP
+                + FOCUS_FILMSTRIP_THUMB_SIZE
+            )
+        )
     var rows := int(ceil(float(visible_count) / float(_columns())))
     return maxi(
         MIN_CARD_HEIGHT, HEADER_HEIGHT + PADDING * 2 + rows * THUMB_SIZE + (rows - 1) * THUMB_GAP
@@ -526,6 +590,14 @@ func _normalize_review_filter(value: String) -> String:
             return FILTER_ALL


+func _normalize_review_layout(value: String) -> String:
+    match value:
+        LAYOUT_CONTACT, LAYOUT_FOCUS:
+            return value
+        _:
+            return LAYOUT_CONTACT
+
+
 func _normalize_focus_asset_id(new_focus_asset_id: String) -> String:
     return new_focus_asset_id if asset_ids.has(new_focus_asset_id) else ""

@@ -570,6 +642,44 @@ func _focus_anchor_index(visible_ids: Array[String]) -> int:
     return -1


+func _focused_visible_asset_id() -> String:
+    var visible_ids := get_visible_asset_ids()
+    if visible_ids.is_empty():
+        return ""
+    var anchor_index := _focus_anchor_index(visible_ids)
+    if anchor_index >= 0:
+        return visible_ids[anchor_index]
+    return visible_ids[0]
+
+
+func _initial_focus_asset_id() -> String:
+    return _focused_visible_asset_id()
+
+
+func _focus_layout_asset_index_at_local(local: Vector2) -> int:
+    var visible_ids := get_visible_asset_ids()
+    if visible_ids.is_empty():
+        return -1
+    if _focus_rect().has_point(local):
+        return visible_ids.find(_focused_visible_asset_id())
+    var start_index := _filmstrip_start_index(visible_ids)
+    var end_index := mini(visible_ids.size(), start_index + FOCUS_FILMSTRIP_VISIBLE)
+    for index in range(start_index, end_index):
+        if _filmstrip_rect(index - start_index).has_point(local):
+            return index
+    return -1
+
+
+func _filmstrip_start_index(visible_ids: Array[String]) -> int:
+    if visible_ids.size() <= FOCUS_FILMSTRIP_VISIBLE:
+        return 0
+    var anchor_index := _focus_anchor_index(visible_ids)
+    if anchor_index < 0:
+        anchor_index = 0
+    var half_window := int(floor(float(FOCUS_FILMSTRIP_VISIBLE) * 0.5))
+    return clampi(anchor_index - half_window, 0, visible_ids.size() - FOCUS_FILMSTRIP_VISIBLE)
+
+
 func _visible_selected_array(value: Array) -> Array[String]:
     var visible_lookup := _visible_lookup()
     var result: Array[String] = []
diff --git a/pixel/ui/canvas/canvas_batch_ops.gd b/pixel/ui/canvas/canvas_batch_ops.gd
index 8f56bf7..09b4272 100644
--- a/pixel/ui/canvas/canvas_batch_ops.gd
+++ b/pixel/ui/canvas/canvas_batch_ops.gd
@@ -184,6 +184,38 @@ static func set_review_filter(
     return true


+static func set_review_layout(
+    items_by_id: Dictionary,
+    card_id: String,
+    review_layout: String,
+    record_undo: bool,
+    select_only: Callable,
+    emit_changed: Callable
+) -> bool:
+    var item := _batch_item(items_by_id, card_id)
+    if item == null:
+        return false
+    var before: String = item.get_review_layout()
+    var after := _normalize_review_layout(review_layout)
+    if before == after:
+        return true
+
+    var do_layout := func() -> void:
+        _apply_review_layout(item, after)
+        select_only.call([card_id])
+        emit_changed.call()
+    var undo_layout := func() -> void:
+        _apply_review_layout(item, before)
+        select_only.call([card_id])
+        emit_changed.call()
+
+    if record_undo:
+        UndoService.perform_action("Set batch review layout", do_layout, undo_layout)
+    else:
+        do_layout.call()
+    return true
+
+
 static func set_compare_mode(
     items_by_id: Dictionary,
     card_id: String,
@@ -319,6 +351,10 @@ static func _apply_focus_asset_id(item: Node, focus_asset_id: String) -> void:
     item._set_focus_asset_id(focus_asset_id, false)


+static func _apply_review_layout(item: Node, review_layout: String) -> void:
+    item.set_review_layout(review_layout)
+
+
 static func _apply_selected_asset_ids(item: Node, selected_asset_ids: Array) -> void:
     item._set_selected_asset_ids(selected_asset_ids)

@@ -361,6 +397,12 @@ static func _normalize_review_filter(review_filter: String) -> String:
     return CanvasBatchCardScript.FILTER_ALL


+static func _normalize_review_layout(review_layout: String) -> String:
+    if review_layout in [CanvasBatchCardScript.LAYOUT_CONTACT, CanvasBatchCardScript.LAYOUT_FOCUS]:
+        return review_layout
+    return CanvasBatchCardScript.LAYOUT_CONTACT
+
+
 static func _normalize_compare_mode(item: Node, compare_mode: String) -> String:
     if not item._get_compare_asset_ids().is_empty():
         match compare_mode:
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 343a106..9c54730 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -131,7 +131,7 @@ func _draw() -> void:
         ScalePolicy.compute_art_physical_scale(camera_zoom, _resolve_viewport_scale_factor())
         >= GRID_MIN_ZOOM
     ):
-        _draw_pixel_grid()
+        PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
     _draw_graph_edges()

     for item_id in _selection.selected_ids:
@@ -346,7 +346,7 @@ func load_canvas_data(canvas_data: Dictionary) -> void:
             _add_sprite_direct(item_data, image)
         elif item_type == "batch_card":
             _add_batch_direct(item_data)
-        elif item_type == "node" and _is_graph_batch_node_data(item_data):
+        elif item_type == "node" and GraphItemBridge.is_graph_batch_node_data(item_data):
             _add_batch_direct(item_data)
         elif item_type == "node":
             _add_node_direct(item_data)
@@ -496,6 +496,14 @@ func _set_batch_review_filter(
     )


+func _set_batch_review_layout(
+    card_id: String, review_layout: String, record_undo: bool = true
+) -> bool:
+    return BatchOps.set_review_layout(
+        _items_by_id, card_id, review_layout, record_undo, _select_only, _emit_canvas_changed
+    )
+
+
 func _replace_batch_asset_ids(
     card_id: String, new_asset_ids: Array, record_undo: bool = true, compare_asset_ids: Array = []
 ) -> void:
@@ -773,14 +781,11 @@ func _add_node_direct(item_data: Dictionary) -> Node:
 func _is_batch_card_data(item_data: Dictionary) -> bool:
     var item_type := String(item_data.get("type", ""))
     return (
-        item_type == "batch_card" or (item_type == "node" and _is_graph_batch_node_data(item_data))
+        item_type == "batch_card"
+        or (item_type == "node" and GraphItemBridge.is_graph_batch_node_data(item_data))
     )


-func _is_graph_batch_node_data(item_data: Dictionary) -> bool:
-    return GraphItemBridge.is_graph_batch_node_data(item_data)
-
-
 func _remove_item_direct(item_id: String) -> void:
     if not _items_by_id.has(item_id):
         return
@@ -928,10 +933,6 @@ func _camera_center_for_snapped_anchor(anchor_world: Vector2, screen_anchor: Vec
     )


-func _draw_pixel_grid() -> void:
-    PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
-
-
 func _draw_graph_edges() -> void:
     GraphEdgeRenderer.draw(
         self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, EDGE_COLOR
diff --git a/pixel/ui/shell/m2_1_ui_controller.gd b/pixel/ui/shell/m2_1_ui_controller.gd
index 9ac3fa7..73fa686 100644
--- a/pixel/ui/shell/m2_1_ui_controller.gd
+++ b/pixel/ui/shell/m2_1_ui_controller.gd
@@ -56,6 +56,8 @@ const BATCH_MENU_FILTER_FLAG := 14
 const BATCH_MENU_COMPARE_CURRENT := 15
 const BATCH_MENU_COMPARE_PREVIOUS := 16
 const BATCH_MENU_COMPARE_SPLIT := 17
+const BATCH_MENU_LAYOUT_CONTACT := 18
+const BATCH_MENU_LAYOUT_FOCUS := 19
 const SELECTION_TOOLS_VISIBLE := false

 var _canvas: Control = null
@@ -319,6 +321,9 @@ func _create_batch_menu() -> void:
     _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_REJECT, BATCH_MENU_FILTER_REJECT)
     _batch_menu.add_item(Strings.BATCH_ACTION_SHOW_FLAG, BATCH_MENU_FILTER_FLAG)
     _batch_menu.add_separator()
+    _batch_menu.add_item(Strings.BATCH_ACTION_LAYOUT_CONTACT, BATCH_MENU_LAYOUT_CONTACT)
+    _batch_menu.add_item(Strings.BATCH_ACTION_LAYOUT_FOCUS, BATCH_MENU_LAYOUT_FOCUS)
+    _batch_menu.add_separator()
     _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_CURRENT, BATCH_MENU_COMPARE_CURRENT)
     _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_PREVIOUS, BATCH_MENU_COMPARE_PREVIOUS)
     _batch_menu.add_item(Strings.BATCH_ACTION_COMPARE_SPLIT, BATCH_MENU_COMPARE_SPLIT)
@@ -464,6 +469,14 @@ func _on_batch_menu_id_pressed(id: int) -> void:
             _set_batch_review_filter(
                 CanvasBatchCardScript.REVIEW_FLAG, Strings.STATUS_BATCH_SHOW_FLAG
             )
+        BATCH_MENU_LAYOUT_CONTACT:
+            _set_batch_review_layout(
+                CanvasBatchCardScript.LAYOUT_CONTACT, Strings.STATUS_BATCH_LAYOUT_CONTACT
+            )
+        BATCH_MENU_LAYOUT_FOCUS:
+            _set_batch_review_layout(
+                CanvasBatchCardScript.LAYOUT_FOCUS, Strings.STATUS_BATCH_LAYOUT_FOCUS
+            )
         BATCH_MENU_COMPARE_CURRENT:
             _set_batch_compare_mode(
                 CanvasBatchCardScript.COMPARE_CURRENT, Strings.STATUS_BATCH_COMPARE_CURRENT
@@ -586,6 +599,13 @@ func _set_batch_review_filter(review_filter: String, status_text: String) -> voi
     _status_label.text = status_text


+func _set_batch_review_layout(review_layout: String, status_text: String) -> void:
+    if not _canvas._set_batch_review_layout(_batch_menu_card_id, review_layout, true):
+        _status_label.text = Strings.STATUS_BATCH_LAYOUT_FAILED
+        return
+    _status_label.text = status_text
+
+
 func _set_batch_compare_mode(compare_mode: String, status_text: String) -> void:
     if not _canvas._set_batch_compare_mode(_batch_menu_card_id, compare_mode, true):
         _status_label.text = Strings.STATUS_BATCH_COMPARE_EMPTY
diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index f5b88fe..4954bff 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -56,6 +56,9 @@ const STATUS_BATCH_SHOW_PENDING := "Showing pending thumbnails"
 const STATUS_BATCH_SHOW_REJECT := "Showing rejected thumbnails"
 const STATUS_BATCH_SHOW_FLAG := "Showing flagged thumbnails"
 const STATUS_BATCH_FILTER_FAILED := "Batch filter failed"
+const STATUS_BATCH_LAYOUT_CONTACT := "Showing contact sheet"
+const STATUS_BATCH_LAYOUT_FOCUS := "Showing focus view"
+const STATUS_BATCH_LAYOUT_FAILED := "Batch layout failed"
 const STATUS_BATCH_FOCUS_EMPTY := "No visible thumbnails in batch"
 const STATUS_BATCH_FOCUS_FORMAT := "Focused thumbnail %d of %d"
 const STATUS_BATCH_COMPARE_CURRENT := "Showing current batch"
@@ -158,6 +161,8 @@ const BATCH_ACTION_SHOW_KEEP := "Show Keep"
 const BATCH_ACTION_SHOW_PENDING := "Show Pending"
 const BATCH_ACTION_SHOW_REJECT := "Show Reject"
 const BATCH_ACTION_SHOW_FLAG := "Show Flagged"
+const BATCH_ACTION_LAYOUT_CONTACT := "Contact Sheet"
+const BATCH_ACTION_LAYOUT_FOCUS := "Focus View"
 const BATCH_ACTION_COMPARE_CURRENT := "Show Current"
 const BATCH_ACTION_COMPARE_PREVIOUS := "Show Previous"
 const BATCH_ACTION_COMPARE_SPLIT := "Show Compare"
diff --git a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
index d0f4337..d5eb761 100644
--- a/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
+++ b/pixelforge-plan/02-contracts/PROJECT-FORMAT.md
@@ -113,6 +113,7 @@ my_project.pxproj (ZIP)
       "focus_asset_id": "uuid-a",
       "compare_asset_ids": ["uuid-a-before", "uuid-b-before"],
       "compare_mode": "current",     // current | previous | split
+      "review_layout": "contact",    // contact | focus
       "label": "Batch",
       "position": [320, 64],
       "z_index": 1,
@@ -125,6 +126,7 @@ my_project.pxproj (ZIP)
       "graph_id": "graph_main",
       "position": [256, -32],
       "z_index": 0,
+      "review_layout": "contact",    // 仅 batch 节点使用：contact | focus
       "collapsed": false           // LOD/折叠态（仅显示，不影响逻辑）
     }
   ]
@@ -133,7 +135,7 @@ my_project.pxproj (ZIP)

 规则：
 - 画布元素 position 强制整数（像素网格对齐，体验原则1）。
-- `node` 元素是画布上一切图节点（style/prompt/generate/batch/process…）的统一引用形态：只存"画在哪、第几层、是否折叠"，节点的类型/参数/连线全在 `graphs/`。连线在画布上从 graphs 渲染，不写进本文件。
+- `node` 元素是画布上一切图节点（style/prompt/generate/batch/process…）的统一引用形态：只存"画在哪、第几层、是否折叠"，以及 batch 这类画布驻留节点的审阅视图状态；节点的类型/参数/连线全在 `graphs/`。连线在画布上从 graphs 渲染，不写进本文件。
 - `batch` 是 `type:"node"` 的一种（其 graphs 节点 `type=batch`），渲染为容器卡（队列网格 + 边框菜单）；物化的 `asset_id` 队列存在 graphs 节点 params 中。这就是「一等节点 + 画布卡」双身份的落地方式（见 GRAPH-SCHEMA §5a）。
 - **M2.1 临时例外**：M3 前尚无正式 graph 持久化，alpha 清洗台先允许 `type:"batch_card"` 直接在 canvas.json 中保存 `asset_ids` 队列、卡片位置和卡内勾选状态。它不含端口、不含连线、不写 graphs；M3 实施正式 batch 节点时，应把该形态迁入 `type:"node"` + `graphs/{graph_id}.json` 的 `type=batch` params。
 - `graph_anchor` 标记为 **legacy**：统一画布后整张图直接长在画布上，锚点退化；保留仅为读取早期数据，不再新写。
diff --git a/pixel/scripts/verify_m3_ux3.sh b/pixel/scripts/verify_m3_ux3.sh
new file mode 100755
index 0000000..334b309
--- /dev/null
+++ b/pixel/scripts/verify_m3_ux3.sh
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
+  echo "Staged image files are not allowed for M3 UX-3 commits." >&2
+  exit 1
+fi
+
+echo "verify_m3_ux3: ok"
```

---

## 2026-06-19 追加：M3 UX-4 语义 LOD 重做（camera zoom 下发）

### 本轮实现说明

- 恢复 UX-4 语义 LOD 原型，但按撤销回执的复核结论改为由 `camera_zoom` 驱动，不再让 batch 卡反查父级 `item_layer.scale` / `art_logical_scale`。
- 新增 `PFCanvasLODProfile` 集中维护 `overview / review / inspect` 阈值，当前阈值为 `<= 0.25` overview、`>= 4.0` inspect，中间为 review。
- 新增 `PFCanvasLODCoordinator`，在 `PFInfiniteCanvas._update_layer_transform()` 中统一把 `camera_zoom` 下发给 batch 卡；新建 batch 时也同步当前 zoom，避免在 25% 下生成后短暂显示 review。
- `PFCanvasBatchCard` 新增三档绘制：overview 显示摘要数量和状态色条；review 保留现有 contact sheet / focus view、选择、过滤、对比；inspect 显示透明棋盘、像素网格和尺寸/颜色数提示。
- overview 档不再命中单张缩略图，避免缩小时误点单图；这属于 UX-7 输入仲裁的后续可调策略，本轮先保持保守。
- 补充 headless 回归：真实 `PFInfiniteCanvas` + 分数 viewport scale `1.5` + `camera_zoom = 0.25` 时，batch 必须进入 overview，覆盖上次撤销回执指出的真实漏测路径。
- 更新 `pixel/CHANGELOG.md`，新增 `verify_m3_ux4.sh` 门禁脚本。

### 验证结果

| 命令 | 结果 | 备注 |
|---|---|---|
| `./pixel/scripts/lint.sh` | 通过 | `gdformat --check` / `gdlint` 通过；无裸 `print`。 |
| `./pixel/scripts/run_tests.sh` | 通过 | 149/149 tests passed；仍有既有 GUT orphan / 退出资源提示，但退出码为 0。 |
| `./pixel/scripts/verify_m3_ux4.sh` | 通过 | 串行通过 lint、run_tests、`check_ui_scaling.sh`、`check_export_templates.sh`；导出模板缺失时脚本按既有口径只做 headless startup。 |
| staged 图片检查 | 通过 | `git diff --cached --name-only | grep -iE '\.(png|jpe?g)$'` 无输出。 |
| staged 保留目录检查 | 通过 | `test picture/`、`pixel/tests/fixtures/real/`、`垃圾桶/`、`godot-interactive-guide/` 均未暂存。 |

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`。
2. 缩放到 25%：batch 卡应切到 overview，只显示摘要数量和状态色条，不再显示完整缩略图网格。
3. 缩放回 50% 或 100%：batch 卡应回到 review，可继续点选缩略图、使用 K/R/F 标记、切换 Contact Sheet / Focus View。
4. 缩放到 400%：batch 卡进入 inspect，小图缩略图应出现棋盘底、像素网格和尺寸/颜色数提示。
5. 在 macOS 分数缩放/外接屏或 Windows 125%/150% 缩放环境重点复核：25% 必须仍进入 overview；若未进入，请记录实际显示器缩放和窗口尺寸。

### DoD 核查

| 项 | 核查内容 | 状态 | 证据/路径 |
|---|---|---|---|
| 代码规范 | gdlint/gdformat 零告警 | 通过 | `./pixel/scripts/lint.sh` |
| 自动测试 | 卡内验收标准已转自动化并通过 | 通过 | `test_batch_lod_uses_camera_zoom_not_compensated_art_scale`、149/149 tests |
| 手动测试 | 标注手动项已执行或登记延期 | 延期登记 | 需用户按上方步骤做实机视觉/手感验收 |
| 契约同步 | 影响契约的改动已更新 `02-contracts/` | 不适用 | 本轮只改 UI LOD 渲染与测试，不改项目/graph schema |
| TODO | 一方代码无无主 `TODO/FIXME/HACK` | 通过 | 本轮未新增 TODO/FIXME/HACK |
| 性能预算 | 相关卡写入实测数字或明确延期 | 不适用 | 本轮无新性能预算；inspect 色数统计有 256 色上限 |
| 跨平台 | 目标平台验证结果已记录 | 延期登记 | headless 已过；mac/Windows 分数缩放需人工复核 |
| 出口门控 | CI 绿灯或本地 agent 验证绿灯 | 通过 | `./pixel/scripts/verify_m3_ux4.sh` |

### 本轮完整 diff（报告自身除外）

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index bce660e..1e94c3e 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -29,3 +29,4 @@
 - M3 G-4 follow-up: graph 连线改用命名端口锚点，修正轻节点端口点、batch 输入点与连线端点错位。
 - M3 G-4 follow-up: AI Generate 画布卡将多个逻辑输入折叠为单个视觉输入点，降低基础节点链噪声。
 - M3 G-5: 新增 File > Run Selected Graph 最小重跑入口，选中 mock 节点链任一节点后可替换刷新正式 batch 队列。
+- M3 UX-4: 恢复 batch 语义 LOD 原型，改由 camera zoom 下发 overview/review/inspect，覆盖分数缩放下 25% 进入 overview 的回归路径。
diff --git a/pixel/scripts/verify_m3_ux4.sh b/pixel/scripts/verify_m3_ux4.sh
new file mode 100755
index 0000000..3d2513d
--- /dev/null
+++ b/pixel/scripts/verify_m3_ux4.sh
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
+  echo "Staged image files are not allowed for M3 UX-4 commits." >&2
+  exit 1
+fi
+
+echo "verify_m3_ux4: ok"
diff --git a/pixel/tests/smoke/test_infinite_canvas.gd b/pixel/tests/smoke/test_infinite_canvas.gd
index bc63e51..69675b0 100644
--- a/pixel/tests/smoke/test_infinite_canvas.gd
+++ b/pixel/tests/smoke/test_infinite_canvas.gd
@@ -1,6 +1,7 @@
 extends "res://addons/gut/test.gd"

 const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
+const LODProfile := preload("res://ui/canvas/canvas_lod_profile.gd")
 const CanvasScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
 const ImageMath := preload("res://core/util/image_math.gd")
 const MagicWandToolScript := preload("res://ui/tools/magic_wand_tool.gd")
@@ -149,6 +150,30 @@ func test_canvas_coordinates_use_compensated_logical_scale() -> void:
     assert_almost_eq(roundtrip.y, world_position.y, 0.001)


+func test_batch_lod_uses_camera_zoom_not_compensated_art_scale() -> void:
+    get_tree().root.get_node("ProjectService").new_project("LOD Test")
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(320, 240)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red")]
+    var card: Node = canvas._add_batch_card(ids, Vector2.ZERO, "Batch", "batch_1", false)
+
+    canvas._set_viewport_scale_factor_for_test(1.5)
+    canvas.set_camera_zoom(0.25, Vector2(160, 120))
+    await wait_process_frames(1)
+
+    assert_almost_eq(canvas._get_art_logical_scale(), 0.333, 0.001)
+    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_OVERVIEW)
+
+    canvas.set_camera_zoom(4.0, Vector2(160, 120))
+    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_INSPECT)
+
+    canvas.set_camera_zoom(1.0, Vector2(160, 120))
+    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_REVIEW)
+
+
 func test_zoom_anchor_stays_fixed_with_fractional_content_scale() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(320, 240)
@@ -321,6 +346,12 @@ func _make_checker_image(size: int) -> Image:
     return image


+func _register_asset(color: Color, name: String) -> String:
+    var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
+    image.fill(color)
+    return AssetLibrary.register_image(image, name, {"origin": "imported"})
+
+
 func _mouse_button(button: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
     var event := InputEventMouseButton.new()
     event.button_index = button
diff --git a/pixel/tests/smoke/test_main_window_ui.gd b/pixel/tests/smoke/test_main_window_ui.gd
index 9c70e83..f5a019c 100644
--- a/pixel/tests/smoke/test_main_window_ui.gd
+++ b/pixel/tests/smoke/test_main_window_ui.gd
@@ -270,6 +270,8 @@ func test_batch_review_shortcuts_mark_selected_mock_thumbnail() -> void:
     var canvas: Control = main.get_node("Root/Content/InfiniteCanvas")
     controller.generate_mock_batch()
     await wait_process_frames(2)
+    canvas.set_camera_zoom(1.0, canvas.size * 0.5)
+    await wait_process_frames(1)

     var graph_id := String(ProjectService.current_project.graphs.keys()[0])
     var graph_data: Dictionary = ProjectService.current_project.graphs[graph_id]
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index debfee6..2af1e30 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -2,6 +2,7 @@ extends "res://addons/gut/test.gd"

 const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
 const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
+const LODProfile := preload("res://ui/canvas/canvas_lod_profile.gd")
 const GraphScript := preload("res://core/graph/pf_graph.gd")
 const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
 const AiGenerateNodeScript := preload("res://core/graph/nodes/ai_generate_node.gd")
@@ -176,6 +177,33 @@ func test_canvas_batch_card_switches_review_layout_for_focus_view() -> void:
     assert_eq(item["review_layout"], CanvasBatchCardScript.LAYOUT_FOCUS)


+func test_canvas_batch_card_switches_semantic_lod_profiles() -> void:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    await wait_process_frames(2)
+
+    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+
+    assert_eq(LODProfile.profile_for_camera_zoom(0.25), LODProfile.PROFILE_OVERVIEW)
+    assert_eq(LODProfile.profile_for_camera_zoom(1.0), LODProfile.PROFILE_REVIEW)
+    assert_eq(LODProfile.profile_for_camera_zoom(4.0), LODProfile.PROFILE_INSPECT)
+    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_REVIEW)
+
+    card.set_lod_camera_zoom(0.25)
+    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_OVERVIEW)
+    assert_almost_eq(
+        card.get_canvas_bounds().size.y, float(CanvasBatchCardScript.OVERVIEW_HEIGHT), 0.001
+    )
+    assert_eq(card.asset_index_at_world(card.position + Vector2(24, 64)), -1)
+
+    card.set_lod_camera_zoom(4.0)
+    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_INSPECT)
+    assert_gt(card.get_canvas_bounds().size.y, float(CanvasBatchCardScript.OVERVIEW_HEIGHT))
+    assert_false(card._asset_hint_for(ids[0]).is_empty())
+
+
 func test_canvas_batch_card_keeps_previous_version_for_compare() -> void:
     var canvas: Control = CanvasScript.new()
     canvas.size = Vector2(512, 512)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index e54db12..cd7ae7d 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -5,6 +5,7 @@ extends Node2D
 ## M3 过渡期同时支持旧 batch_card 和正式 graph batch 节点引用的渲染。

 const IdUtil := preload("res://core/util/id_util.gd")
+const LODProfile := preload("res://ui/canvas/canvas_lod_profile.gd")
 const Strings := preload("res://ui/shell/strings.gd")

 const CARD_WIDTH := 600
@@ -41,6 +42,14 @@ const OUTPUT_PORTS: Array[String] = ["images", "assets"]
 const FOCUS_IMAGE_HEIGHT := 320
 const FOCUS_FILMSTRIP_THUMB_SIZE := 72
 const FOCUS_FILMSTRIP_VISIBLE := 7
+const OVERVIEW_HEIGHT := 124
+const OVERVIEW_BAR_HEIGHT := 12
+const CHECKER_SIZE := 8
+const MAX_INSPECT_COLOR_HINTS := 256
+const CHECKER_LIGHT := Color(0.18, 0.19, 0.2, 1.0)
+const CHECKER_DARK := Color(0.1, 0.105, 0.11, 1.0)
+const INSPECT_GRID := Color(1.0, 1.0, 1.0, 0.16)
+const HINT_BACKGROUND := Color(0.02, 0.025, 0.03, 0.78)

 var item_id := ""
 var graph_id := ""
@@ -57,7 +66,9 @@ var label := ""
 var locked := false

 var _thumbnail_textures := {}
+var _asset_hints := {}
 var _font: Font = null
+var _lod_camera_zoom := 1.0


 func setup_from_data(data: Dictionary) -> void:
@@ -135,6 +146,14 @@ func get_canvas_bounds() -> Rect2:
     return Rect2(position, Vector2(CARD_WIDTH, _card_height()))


+func set_lod_camera_zoom(camera_zoom_value: float) -> void:
+    var normalized_zoom := maxf(camera_zoom_value, 0.0)
+    if is_equal_approx(_lod_camera_zoom, normalized_zoom):
+        return
+    _lod_camera_zoom = normalized_zoom
+    queue_redraw()
+
+
 func contains_world_point(world_position: Vector2) -> bool:
     return get_canvas_bounds().has_point(world_position)

@@ -312,6 +331,8 @@ func toggle_asset_at_world(world_position: Vector2) -> bool:


 func asset_index_at_world(world_position: Vector2) -> int:
+    if _get_lod_profile() == LODProfile.PROFILE_OVERVIEW:
+        return -1
     var local := world_position - position
     if local.y < HEADER_HEIGHT:
         return -1
@@ -326,6 +347,10 @@ func asset_index_at_world(world_position: Vector2) -> int:
     return -1


+func _get_lod_profile() -> String:
+    return LODProfile.profile_for_camera_zoom(_lod_camera_zoom)
+
+
 func _draw() -> void:
     _font = ThemeDB.fallback_font if _font == null else _font
     var card_rect := Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, _card_height()))
@@ -334,8 +359,9 @@ func _draw() -> void:
     draw_rect(
         Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, HEADER_HEIGHT)), Color(0.21, 0.22, 0.24, 1.0), true
     )
+    var visible_ids := get_visible_asset_ids()
     if _font != null:
-        var visible_count := get_visible_asset_ids().size()
+        var visible_count := visible_ids.size()
         var title := "%s (%d)" % [label, asset_ids.size()]
         if visible_count != asset_ids.size():
             title = "%s (%d/%d)" % [label, visible_count, asset_ids.size()]
@@ -353,11 +379,13 @@ func _draw() -> void:
             Color(0.9, 0.92, 0.92, 1.0)
         )

-    var columns := _columns()
-    var visible_ids := get_visible_asset_ids()
-    if review_layout == LAYOUT_FOCUS:
+    var lod_profile := _get_lod_profile()
+    if lod_profile == LODProfile.PROFILE_OVERVIEW:
+        _draw_overview(visible_ids)
+    elif review_layout == LAYOUT_FOCUS:
         _draw_focus_layout(visible_ids)
     else:
+        var columns := _columns()
         for index in range(visible_ids.size()):
             _draw_thumbnail(visible_ids[index], _thumb_rect(index, columns))
     if has_graph_binding():
@@ -377,12 +405,58 @@ func _draw_focus_layout(visible_ids: Array[String]) -> void:
         _draw_thumbnail(visible_ids[index], _filmstrip_rect(index - start_index))


+func _draw_overview(visible_ids: Array[String]) -> void:
+    var content_rect := Rect2(
+        Vector2(PADDING, HEADER_HEIGHT + PADDING), Vector2(CARD_WIDTH - PADDING * 2, 42.0)
+    )
+    draw_rect(content_rect, Color(0.08, 0.085, 0.09, 1.0), true)
+    if _font != null:
+        draw_string(
+            _font,
+            content_rect.position + Vector2(0.0, 31.0),
+            str(visible_ids.size()),
+            HORIZONTAL_ALIGNMENT_CENTER,
+            content_rect.size.x,
+            28,
+            Color(0.92, 0.94, 0.92, 1.0)
+        )
+    var bar_rect := Rect2(
+        Vector2(PADDING, content_rect.end.y + THUMB_GAP),
+        Vector2(CARD_WIDTH - PADDING * 2, OVERVIEW_BAR_HEIGHT)
+    )
+    _draw_overview_status_bar(bar_rect, visible_ids)
+
+
+func _draw_overview_status_bar(bar_rect: Rect2, visible_ids: Array[String]) -> void:
+    draw_rect(bar_rect, Color(0.08, 0.085, 0.09, 1.0), true)
+    if visible_ids.is_empty():
+        return
+    var counts := _review_counts(visible_ids)
+    var cursor_x := bar_rect.position.x
+    for review_state in [FILTER_PENDING, REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG]:
+        var count := int(counts.get(review_state, 0))
+        if count <= 0:
+            continue
+        var width := bar_rect.size.x * float(count) / float(visible_ids.size())
+        var segment := Rect2(
+            Vector2(cursor_x, bar_rect.position.y), Vector2(width, bar_rect.size.y)
+        )
+        draw_rect(segment, _overview_color_for_state(review_state), true)
+        cursor_x += width
+
+
 func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
-    draw_rect(rect, THUMB_BACKGROUND, true)
+    var inspect_mode := _get_lod_profile() == LODProfile.PROFILE_INSPECT
+    if inspect_mode:
+        _draw_checkerboard(rect)
+    else:
+        draw_rect(rect, THUMB_BACKGROUND, true)
     if compare_mode == COMPARE_SPLIT:
         _draw_split_compare_thumbnail(asset_id, rect)
     else:
         _draw_thumbnail_texture(_texture_asset_id_for(asset_id), rect)
+    if inspect_mode:
+        _draw_inspect_overlay(asset_id, rect)
     var border_color := SELECTED_BORDER if selected_asset_ids.has(asset_id) else BORDER
     draw_rect(rect, border_color, false, 1.5)
     _draw_review_marker(rect, String(review_states.get(asset_id, REVIEW_NONE)))
@@ -409,13 +483,81 @@ func _draw_split_compare_thumbnail(asset_id: String, rect: Rect2) -> void:


 func _draw_thumbnail_texture(asset_id: String, rect: Rect2) -> void:
+    var texture_rect := _thumbnail_texture_rect(asset_id, rect)
+    if texture_rect.size == Vector2.ZERO:
+        return
+    var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
+    draw_texture_rect(texture, texture_rect, false)
+
+
+func _thumbnail_texture_rect(asset_id: String, rect: Rect2) -> Rect2:
     var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
     if texture != null:
         var image_size := texture.get_size()
         var scale := minf(rect.size.x / image_size.x, rect.size.y / image_size.y)
         var draw_size := image_size * scale
         var draw_pos := rect.position + (rect.size - draw_size) * 0.5
-        draw_texture_rect(texture, Rect2(draw_pos, draw_size), false)
+        return Rect2(draw_pos, draw_size)
+    return Rect2()
+
+
+func _draw_checkerboard(rect: Rect2) -> void:
+    var columns := int(ceil(rect.size.x / float(CHECKER_SIZE)))
+    var rows := int(ceil(rect.size.y / float(CHECKER_SIZE)))
+    for row in range(rows):
+        for column in range(columns):
+            var cell := Rect2(
+                rect.position + Vector2(column * CHECKER_SIZE, row * CHECKER_SIZE),
+                Vector2(CHECKER_SIZE, CHECKER_SIZE)
+            )
+            draw_rect(cell, CHECKER_LIGHT if (row + column) % 2 == 0 else CHECKER_DARK, true)
+
+
+func _draw_inspect_overlay(asset_id: String, rect: Rect2) -> void:
+    var texture_asset_id := _texture_asset_id_for(asset_id)
+    var texture_rect := _thumbnail_texture_rect(texture_asset_id, rect)
+    if texture_rect.size != Vector2.ZERO:
+        _draw_texture_pixel_grid(texture_asset_id, texture_rect)
+    var hint := _asset_hint_for(asset_id)
+    if hint.is_empty() or _font == null:
+        return
+    var hint_rect := Rect2(
+        rect.position + Vector2(6.0, rect.size.y - 24.0), Vector2(rect.size.x - 12.0, 18.0)
+    )
+    draw_rect(hint_rect, HINT_BACKGROUND, true)
+    draw_string(
+        _font,
+        hint_rect.position + Vector2(5.0, 14.0),
+        hint,
+        HORIZONTAL_ALIGNMENT_LEFT,
+        hint_rect.size.x - 10.0,
+        12,
+        Color(0.94, 0.95, 0.94, 1.0)
+    )
+
+
+func _draw_texture_pixel_grid(asset_id: String, texture_rect: Rect2) -> void:
+    var texture: Texture2D = _thumbnail_textures.get(asset_id, null)
+    if texture == null:
+        return
+    var image_size := texture.get_size()
+    var cell_size := minf(texture_rect.size.x / image_size.x, texture_rect.size.y / image_size.y)
+    if not LODProfile.should_draw_pixel_grid(_lod_camera_zoom, cell_size):
+        return
+    for x in range(1, int(image_size.x)):
+        var line_x := texture_rect.position.x + float(x) * cell_size
+        draw_line(
+            Vector2(line_x, texture_rect.position.y),
+            Vector2(line_x, texture_rect.end.y),
+            INSPECT_GRID
+        )
+    for y in range(1, int(image_size.y)):
+        var line_y := texture_rect.position.y + float(y) * cell_size
+        draw_line(
+            Vector2(texture_rect.position.x, line_y),
+            Vector2(texture_rect.end.x, line_y),
+            INSPECT_GRID
+        )


 func _draw_review_marker(rect: Rect2, review_state: String) -> void:
@@ -443,6 +585,29 @@ func _draw_review_marker(rect: Rect2, review_state: String) -> void:
             )


+func _review_counts(visible_ids: Array[String]) -> Dictionary:
+    var counts := {FILTER_PENDING: 0, REVIEW_KEEP: 0, REVIEW_REJECT: 0, REVIEW_FLAG: 0}
+    for asset_id in visible_ids:
+        var review_state := String(review_states.get(asset_id, REVIEW_NONE))
+        if review_state.is_empty():
+            counts[FILTER_PENDING] += 1
+        else:
+            counts[review_state] = int(counts.get(review_state, 0)) + 1
+    return counts
+
+
+func _overview_color_for_state(review_state: String) -> Color:
+    match review_state:
+        REVIEW_KEEP:
+            return KEEP_MARK
+        REVIEW_REJECT:
+            return REJECT_MARK
+        REVIEW_FLAG:
+            return FLAG_MARK
+        _:
+            return BORDER
+
+
 func _thumb_rect(index: int, columns: int) -> Rect2:
     var col := index % columns
     var row := int(index / columns)
@@ -471,6 +636,8 @@ func _filmstrip_rect(slot_index: int) -> Rect2:


 func _card_height() -> int:
+    if _get_lod_profile() == LODProfile.PROFILE_OVERVIEW:
+        return OVERVIEW_HEIGHT
     var visible_count := get_visible_asset_ids().size()
     if visible_count <= 0:
         return MIN_CARD_HEIGHT
@@ -512,6 +679,7 @@ func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:

 func _rebuild_thumbnails() -> void:
     _thumbnail_textures.clear()
+    _asset_hints.clear()
     var texture_asset_ids := asset_ids.duplicate()
     for compare_asset_id in compare_asset_ids:
         if not texture_asset_ids.has(compare_asset_id):
@@ -520,6 +688,10 @@ func _rebuild_thumbnails() -> void:
         var image := AssetLibrary.get_image(asset_id)
         if image == null:
             continue
+        _asset_hints[asset_id] = {
+            "size": image.get_size(),
+            "color_count": _count_limited_colors(image, MAX_INSPECT_COLOR_HINTS),
+        }
         var thumb := image.duplicate()
         var longest := maxi(thumb.get_width(), thumb.get_height())
         if longest > THUMB_TEXTURE_SIZE:
@@ -532,6 +704,30 @@ func _rebuild_thumbnails() -> void:
         _thumbnail_textures[asset_id] = ImageTexture.create_from_image(thumb)


+func _asset_hint_for(asset_id: String) -> String:
+    var hint: Dictionary = _asset_hints.get(asset_id, {})
+    if hint.is_empty():
+        return ""
+    var image_size: Vector2i = hint.get("size", Vector2i.ZERO)
+    var color_count := int(hint.get("color_count", 0))
+    if color_count > MAX_INSPECT_COLOR_HINTS:
+        return (
+            Strings.BATCH_INSPECT_HINT_CAPPED_FORMAT
+            % [image_size.x, image_size.y, MAX_INSPECT_COLOR_HINTS]
+        )
+    return Strings.BATCH_INSPECT_HINT_FORMAT % [image_size.x, image_size.y, color_count]
+
+
+func _count_limited_colors(image: Image, max_colors: int) -> int:
+    var colors := {}
+    for y in range(image.get_height()):
+        for x in range(image.get_width()):
+            colors[image.get_pixel(x, y).to_html(true)] = true
+            if colors.size() > max_colors:
+                return colors.size()
+    return colors.size()
+
+
 func _resolve_graph_batch_node_data() -> Dictionary:
     if not has_graph_binding():
         return {}
diff --git a/pixel/ui/canvas/canvas_lod_coordinator.gd b/pixel/ui/canvas/canvas_lod_coordinator.gd
new file mode 100644
index 0000000..295c020
--- /dev/null
+++ b/pixel/ui/canvas/canvas_lod_coordinator.gd
@@ -0,0 +1,15 @@
+class_name PFCanvasLODCoordinator
+extends RefCounted
+
+## Pushes canvas camera zoom to canvas-resident items that render semantic LOD.
+
+
+static func sync_batch_camera_zoom(
+    items_by_id: Dictionary, batch_card_script: Script, camera_zoom: float
+) -> void:
+    for raw_item in items_by_id.values():
+        if not (raw_item is Node):
+            continue
+        var item: Node = raw_item
+        if item.get_script() == batch_card_script:
+            item.set_lod_camera_zoom(camera_zoom)
diff --git a/pixel/ui/canvas/canvas_lod_coordinator.gd.uid b/pixel/ui/canvas/canvas_lod_coordinator.gd.uid
new file mode 100644
index 0000000..060fc9b
--- /dev/null
+++ b/pixel/ui/canvas/canvas_lod_coordinator.gd.uid
@@ -0,0 +1 @@
+uid://daiq0vv2kxan7
diff --git a/pixel/ui/canvas/canvas_lod_profile.gd b/pixel/ui/canvas/canvas_lod_profile.gd
new file mode 100644
index 0000000..2006b01
--- /dev/null
+++ b/pixel/ui/canvas/canvas_lod_profile.gd
@@ -0,0 +1,24 @@
+class_name PFCanvasLODProfile
+extends RefCounted
+
+## Semantic canvas LOD thresholds shared by canvas-resident items.
+
+const PROFILE_OVERVIEW := "overview"
+const PROFILE_REVIEW := "review"
+const PROFILE_INSPECT := "inspect"
+const OVERVIEW_MAX_CAMERA_ZOOM := 0.25
+const INSPECT_MIN_CAMERA_ZOOM := 4.0
+const PIXEL_GRID_MIN_PHYSICAL_CELL := 4.0
+
+
+static func profile_for_camera_zoom(camera_zoom: float) -> String:
+    var safe_zoom := maxf(camera_zoom, 0.0)
+    if safe_zoom <= OVERVIEW_MAX_CAMERA_ZOOM:
+        return PROFILE_OVERVIEW
+    if safe_zoom >= INSPECT_MIN_CAMERA_ZOOM:
+        return PROFILE_INSPECT
+    return PROFILE_REVIEW
+
+
+static func should_draw_pixel_grid(camera_zoom: float, local_cell_size: float) -> bool:
+    return maxf(camera_zoom, 0.0) * maxf(local_cell_size, 0.0) >= PIXEL_GRID_MIN_PHYSICAL_CELL
diff --git a/pixel/ui/canvas/canvas_lod_profile.gd.uid b/pixel/ui/canvas/canvas_lod_profile.gd.uid
new file mode 100644
index 0000000..a43ab38
--- /dev/null
+++ b/pixel/ui/canvas/canvas_lod_profile.gd.uid
@@ -0,0 +1 @@
+uid://bt1d4qhvqrs8m
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 9c54730..74821ee 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -25,6 +25,7 @@ const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
 const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
 const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
 const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
+const LODCoordinator := preload("res://ui/canvas/canvas_lod_coordinator.gd")
 const BatchOps := preload("res://ui/canvas/canvas_batch_ops.gd")
 const CanvasCleanupPreviewScript := preload("res://ui/canvas/canvas_cleanup_preview.gd")
 const CanvasSelectionScript := preload("res://ui/canvas/canvas_selection.gd")
@@ -294,7 +295,10 @@ func delete_selected(record_undo: bool = true) -> void:
             var data: Dictionary = snapshot["data"]
             if String(data.get("type", "")) == "sprite":
                 _add_sprite_direct(data, snapshot["image"])
-            elif _is_batch_card_data(data):
+            elif (
+                String(data.get("type", "")) == "batch_card"
+                or GraphItemBridge.is_graph_batch_node_data(data)
+            ):
                 _add_batch_direct(data)
             elif String(data.get("type", "")) == "node":
                 _add_node_direct(data)
@@ -759,6 +763,7 @@ func _add_sprite_direct(item_data: Dictionary, image: Image) -> Node:
 func _add_batch_direct(item_data: Dictionary) -> Node:
     var item: Node = CanvasBatchCardScript.new()
     item.setup_from_data(item_data)
+    item.set_lod_camera_zoom(camera_zoom)
     item_layer.add_child(item)
     _items_by_id[item.item_id] = item
     for asset_id in item.asset_ids:
@@ -778,14 +783,6 @@ func _add_node_direct(item_data: Dictionary) -> Node:
     return item


-func _is_batch_card_data(item_data: Dictionary) -> bool:
-    var item_type := String(item_data.get("type", ""))
-    return (
-        item_type == "batch_card"
-        or (item_type == "node" and GraphItemBridge.is_graph_batch_node_data(item_data))
-    )
-
-
 func _remove_item_direct(item_id: String) -> void:
     if not _items_by_id.has(item_id):
         return
@@ -889,6 +886,7 @@ func _update_layer_transform() -> void:
         raw_position, viewport_scale_factor
     )
     item_layer.scale = Vector2.ONE * art_logical_scale
+    LODCoordinator.sync_batch_camera_zoom(_items_by_id, CanvasBatchCardScript, camera_zoom)
     _sync_cleanup_grid_overlay()
     queue_redraw()

diff --git a/pixel/ui/shell/strings.gd b/pixel/ui/shell/strings.gd
index 4954bff..8e3a28a 100644
--- a/pixel/ui/shell/strings.gd
+++ b/pixel/ui/shell/strings.gd
@@ -168,6 +168,8 @@ const BATCH_ACTION_COMPARE_PREVIOUS := "Show Previous"
 const BATCH_ACTION_COMPARE_SPLIT := "Show Compare"
 const BATCH_COMPARE_PREVIOUS_SUFFIX := "previous"
 const BATCH_COMPARE_SPLIT_SUFFIX := "compare"
+const BATCH_INSPECT_HINT_FORMAT := "%dx%d, %d colors"
+const BATCH_INSPECT_HINT_CAPPED_FORMAT := "%dx%d, %d+ colors"
 const BATCH_ACTION_SPLIT_KEEP := "Split Kept"
 const BATCH_ACTION_SPLIT := "Split Selected"
const BATCH_ACTION_EXPORT := "Export Batch"
```

---

## 2026-06-19 追加：M3 UX-7 Hit-test 最小输入仲裁层

### 本轮实现说明

- 新增 `PFCanvasHitPolicy`，把画布 item 命中判断从 `PFInfiniteCanvas` 中抽出，统一处理 batch 缩略图、整卡、sprite / node 卡、空白画布。
- `PFInfiniteCanvas._begin_left_interaction()` 改为先读取 hit policy 结果：只有命中 `batch_thumbnail` 时才切换 batch 内缩略图选择；overview 或卡片边框命中整卡，继续走选中/拖拽路径。
- 右键 batch 菜单入口也改用同一套 `_hit_at_world()`，避免左键/右键使用两套命中规则。
- 补充 `test_canvas_hit_policy.gd`，覆盖 review 缩略图优先、缩略图点击不启动拖卡、overview 整卡命中、topmost z-order、空白命中。
- 本轮是 UX-7 的最小基础层，尚未实现端口/连线手柄、resize handle、hit debug overlay；这些保留为后续小卡。

### 验证结果

| 命令 | 结果 | 备注 |
|---|---|---|
| `./pixel/scripts/lint.sh` | 通过 | 109 files would be left unchanged；gdlint 无问题；无裸 `print`。 |
| `./pixel/scripts/run_tests.sh` | 通过 | 154/154 tests passed；仍有既有 GUT orphan / 退出资源提示，但退出码为 0。 |
| `./pixel/scripts/verify_m3_ux7.sh` | 通过 | 串行通过 lint、run_tests、`check_ui_scaling.sh`、`check_export_templates.sh`。 |
| staged 图片检查 | 通过 | `git diff --cached --name-only | grep -iE '\.(png|jpe?g)$'` 无输出。 |
| staged 保留目录检查 | 通过 | `test picture/`、`pixel/tests/fixtures/real/`、`垃圾桶/`、`godot-interactive-guide/` 均未暂存。 |

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`。
2. 在 100% 或 50% review 档点击 batch 内单张缩略图：应只切换缩略图选择，整张 batch 卡不应开始拖动。
3. 点击 batch 标题/边框并拖动：应拖动整张 batch 卡。
4. 缩放到 25% overview 档点击 batch：应选中/拖动整卡，不应误选单张缩略图。
5. 在 batch 旁边空白处拖拽：应走框选；右键 batch 任意可见区域仍应打开 batch 菜单。

### DoD 核查

| 项 | 核查内容 | 状态 | 证据/路径 |
|---|---|---|---|
| 代码规范 | gdlint/gdformat 零告警 | 通过 | `./pixel/scripts/lint.sh` |
| 自动测试 | 卡内验收标准已转自动化并通过 | 通过 | `test_canvas_hit_policy.gd`、154/154 tests |
| 手动测试 | 标注手动项已执行或登记延期 | 延期登记 | 需用户按上方步骤实机复核拖卡/点图/框选 |
| 契约同步 | 影响契约的改动已更新 `02-contracts/` | 不适用 | 本轮只改 UI 输入仲裁，不改持久化契约 |
| TODO | 一方代码无无主 `TODO/FIXME/HACK` | 通过 | 本轮未新增 TODO/FIXME/HACK |
| 性能预算 | 相关卡写入实测数字或明确延期 | 不适用 | 本轮只抽取命中判断，未新增重计算路径 |
| 跨平台 | 目标平台验证结果已记录 | 延期登记 | headless 已过；触控板/鼠标手感需人工复核 |
| 出口门控 | CI 绿灯或本地 agent 验证绿灯 | 通过 | `./pixel/scripts/verify_m3_ux7.sh` |

### 本轮完整 diff（报告自身除外）

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index 1e94c3e..30b57f0 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -30,3 +30,4 @@
 - M3 G-4 follow-up: AI Generate 画布卡将多个逻辑输入折叠为单个视觉输入点，降低基础节点链噪声。
 - M3 G-5: 新增 File > Run Selected Graph 最小重跑入口，选中 mock 节点链任一节点后可替换刷新正式 batch 队列。
 - M3 UX-4: 恢复 batch 语义 LOD 原型，改由 camera zoom 下发 overview/review/inspect，覆盖分数缩放下 25% 进入 overview 的回归路径。
+- M3 UX-7: 新增 CanvasHitPolicy 最小输入仲裁层，统一 batch 缩略图、整卡、sprite 和空白画布命中，避免缩略图点击误触拖卡。
diff --git a/pixel/scripts/verify_m3_ux7.sh b/pixel/scripts/verify_m3_ux7.sh
new file mode 100755
index 0000000..85d2fc1
--- /dev/null
+++ b/pixel/scripts/verify_m3_ux7.sh
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
+  echo "Staged image files are not allowed for M3 UX-7 commits." >&2
+  exit 1
+fi
+
+echo "verify_m3_ux7: ok"
diff --git a/pixel/tests/unit/test_canvas_hit_policy.gd b/pixel/tests/unit/test_canvas_hit_policy.gd
new file mode 100644
index 0000000..c492fad
--- /dev/null
+++ b/pixel/tests/unit/test_canvas_hit_policy.gd
@@ -0,0 +1,96 @@
+extends "res://addons/gut/test.gd"
+
+const CanvasScript := preload("res://ui/canvas/infinite_canvas.gd")
+const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
+const CanvasItemSpriteScript := preload("res://ui/canvas/canvas_item_sprite.gd")
+const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
+const HitPolicy := preload("res://ui/canvas/canvas_hit_policy.gd")
+
+
+func before_each() -> void:
+    get_tree().root.get_node("ProjectService").new_project("Hit Policy")
+
+
+func test_canvas_hit_policy_prioritizes_batch_thumbnail_inside_review_card() -> void:
+    var canvas: Control = _canvas()
+    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+
+    var hit := _hit(canvas, card.position + Vector2(20, 60))
+
+    assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
+    assert_eq(hit["item_id"], "batch_1")
+    assert_eq(hit["asset_index"], 0)
+
+
+func test_canvas_left_click_on_batch_thumbnail_does_not_start_card_drag() -> void:
+    var canvas: Control = _canvas()
+    var ids := [_register_asset(Color.RED, "red")]
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+
+    canvas._begin_left_interaction(canvas.world_to_screen(card.position + Vector2(20, 60)), false)
+
+    assert_eq(canvas.get_selected_ids(), ["batch_1"])
+    assert_eq(card.get_selected_asset_ids(), [ids[0]])
+    assert_false(canvas._selection.is_dragging_items)
+
+
+func test_canvas_hit_policy_treats_overview_batch_as_whole_card() -> void:
+    var canvas: Control = _canvas()
+    var ids := [_register_asset(Color.RED, "red")]
+    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
+    card.set_lod_camera_zoom(0.25)
+
+    var hit := _hit(canvas, card.position + Vector2(20, 60))
+
+    assert_eq(hit["kind"], HitPolicy.KIND_ITEM)
+    assert_eq(hit["item_id"], "batch_1")
+    assert_eq(hit["asset_index"], -1)
+
+
+func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
+    var canvas: Control = _canvas()
+    var ids := [_register_asset(Color.RED, "red")]
+    canvas._add_batch_card(ids, Vector2.ZERO, "Batch", "batch_1", false)
+    canvas.add_sprite_item(_image(Color.GREEN), "", Vector2.ZERO, "sprite_top", false)
+
+    var hit := _hit(canvas, Vector2(2, 2))
+
+    assert_eq(hit["kind"], HitPolicy.KIND_ITEM)
+    assert_eq(hit["item_id"], "sprite_top")
+
+
+func test_canvas_hit_policy_reports_empty_space() -> void:
+    var canvas: Control = _canvas()
+
+    var hit := _hit(canvas, Vector2(2000, 2000))
+
+    assert_eq(hit["kind"], HitPolicy.KIND_EMPTY)
+    assert_eq(hit["item_id"], "")
+
+
+func _canvas() -> Control:
+    var canvas: Control = CanvasScript.new()
+    canvas.size = Vector2(512, 512)
+    add_child_autofree(canvas)
+    return canvas
+
+
+func _hit(canvas: Control, world_position: Vector2) -> Dictionary:
+    return HitPolicy.hit_at_world(
+        canvas.item_layer,
+        world_position,
+        CanvasBatchCardScript,
+        CanvasItemSpriteScript,
+        CanvasNodeCardScript
+    )
+
+
+func _register_asset(color: Color, name: String) -> String:
+    return AssetLibrary.register_image(_image(color), name, {"origin": "imported"})
+
+
+func _image(color: Color) -> Image:
+    var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
+    image.fill(color)
+    return image
diff --git a/pixel/tests/unit/test_canvas_hit_policy.gd.uid b/pixel/tests/unit/test_canvas_hit_policy.gd.uid
new file mode 100644
index 0000000..286adb7
--- /dev/null
+++ b/pixel/tests/unit/test_canvas_hit_policy.gd.uid
@@ -0,0 +1 @@
+uid://de6rcbahld0ig
diff --git a/pixel/ui/canvas/canvas_hit_policy.gd b/pixel/ui/canvas/canvas_hit_policy.gd
new file mode 100644
index 0000000..7a31588
--- /dev/null
+++ b/pixel/ui/canvas/canvas_hit_policy.gd
@@ -0,0 +1,43 @@
+class_name PFCanvasHitPolicy
+extends RefCounted
+
+## Canvas hit-test arbitration for item-level interactions.
+
+const KIND_EMPTY := "empty"
+const KIND_ITEM := "item"
+const KIND_BATCH_THUMBNAIL := "batch_thumbnail"
+
+
+static func hit_at_world(
+    item_layer: Node,
+    world_position: Vector2,
+    batch_card_script: Script,
+    sprite_script: Script,
+    node_card_script: Script
+) -> Dictionary:
+    var children := item_layer.get_children()
+    for index in range(children.size() - 1, -1, -1):
+        var item := children[index]
+        if not _is_canvas_item(item, batch_card_script, sprite_script, node_card_script):
+            continue
+        if not item.visible or not item.contains_world_point(world_position):
+            continue
+        if item.get_script() == batch_card_script:
+            var asset_index: int = item.asset_index_at_world(world_position)
+            if asset_index >= 0:
+                return _hit(KIND_BATCH_THUMBNAIL, item, asset_index)
+        return _hit(KIND_ITEM, item, -1)
+    return {"kind": KIND_EMPTY, "item": null, "item_id": "", "asset_index": -1}
+
+
+static func _is_canvas_item(
+    item: Variant, batch_card_script: Script, sprite_script: Script, node_card_script: Script
+) -> bool:
+    if not (item is Node):
+        return false
+    var script: Script = item.get_script()
+    return script == batch_card_script or script == sprite_script or script == node_card_script
+
+
+static func _hit(kind: String, item: Node, asset_index: int) -> Dictionary:
+    return {"kind": kind, "item": item, "item_id": item.item_id, "asset_index": asset_index}
diff --git a/pixel/ui/canvas/canvas_hit_policy.gd.uid b/pixel/ui/canvas/canvas_hit_policy.gd.uid
new file mode 100644
index 0000000..996e267
--- /dev/null
+++ b/pixel/ui/canvas/canvas_hit_policy.gd.uid
@@ -0,0 +1 @@
+uid://8qpxwdwvrua2
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 74821ee..09731f6 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -25,6 +25,7 @@ const CanvasBatchCardScript := preload("res://ui/canvas/canvas_batch_card.gd")
 const CanvasNodeCardScript := preload("res://ui/canvas/canvas_node_card.gd")
 const GraphEdgeRenderer := preload("res://ui/canvas/canvas_graph_edge_renderer.gd")
 const GraphItemBridge := preload("res://ui/canvas/canvas_graph_item_bridge.gd")
+const HitPolicy := preload("res://ui/canvas/canvas_hit_policy.gd")
 const LODCoordinator := preload("res://ui/canvas/canvas_lod_coordinator.gd")
 const BatchOps := preload("res://ui/canvas/canvas_batch_ops.gd")
 const CanvasCleanupPreviewScript := preload("res://ui/canvas/canvas_cleanup_preview.gd")
@@ -665,10 +666,11 @@ func _handle_mouse_motion(event: InputEventMouseMotion) -> void:

 func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
     var world_position := screen_to_world(screen_position)
-    var hit_item := _item_at_world(world_position)
+    var hit := _hit_at_world(world_position)
+    var hit_item: Node = hit.get("item", null)
     if hit_item != null:
         if (
-            hit_item.get_script() == CanvasBatchCardScript
+            String(hit.get("kind", "")) == HitPolicy.KIND_BATCH_THUMBNAIL
             and hit_item.toggle_asset_at_world(world_position)
         ):
             _select_only([hit_item.item_id])
@@ -802,21 +804,14 @@ func _remove_item_direct(item_id: String) -> void:
     queue_redraw()


-func _item_at_world(world_position: Vector2) -> Node:
-    var children := item_layer.get_children()
-    for index in range(children.size() - 1, -1, -1):
-        var item := children[index]
-        if (
-            (
-                item.get_script() == CanvasItemSpriteScript
-                or item.get_script() == CanvasBatchCardScript
-                or item.get_script() == CanvasNodeCardScript
-            )
-            and item.visible
-            and item.contains_world_point(world_position)
-        ):
-            return item
-    return null
+func _hit_at_world(world_position: Vector2) -> Dictionary:
+    return HitPolicy.hit_at_world(
+        item_layer,
+        world_position,
+        CanvasBatchCardScript,
+        CanvasItemSpriteScript,
+        CanvasNodeCardScript
+    )


 func _selected_positions() -> Dictionary:
@@ -988,7 +983,7 @@ func _tool_manager_handles(event: InputEvent) -> bool:


 func _emit_batch_context_if_hit(screen_position: Vector2) -> void:
-    var hit_item := _item_at_world(screen_to_world(screen_position))
+    var hit_item: Node = _hit_at_world(screen_to_world(screen_position)).get("item", null)
    if hit_item == null or hit_item.get_script() != CanvasBatchCardScript:
        return
    _select_only([hit_item.item_id])
```

## 2026-06-20 M3 UX-4 overview 撤销与不予通过标记

### 本轮实现说明

- 撤销 25% zoom 进入 overview 后隐藏 batch 缩略图的运行路径：`CanvasLODProfile` 现在只返回 review / inspect，`PFCanvasBatchCard` 删除 overview 摘要绘制、高度折叠、整卡命中兜底。
- 保留 4x inspect 细节路径：缩略图仍可进入 checkerboard / pixel grid / hint overlay。
- 更新回归测试：25% zoom 明确保持 review，batch 缩略图仍可命中第一张，避免再次把缩略图隐藏机制作为通过能力。
- 在 `M3-开发规划.md` 中将 UX-4 标记为 `NOT-PASSED`，说明隐藏缩略图的 overview 摘要卡不予实际通过，后续若重做必须先保证图像可辨识度。

### 验证结果

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：首次因本轮新增断言过强失败 1 项，修正后通过，154/154 tests passed。
- `./pixel/scripts/verify_m3_ux4.sh`：首次受沙箱限制无法写入 Godot editor settings；提升权限重跑后通过，包含 lint、run_tests、check_ui_scaling、check_export_templates。
- staged 图片检查：无 PNG/JPG/JPEG。
- staged 保留目录检查：未包含 `test picture/`、`pixel/tests/fixtures/real/`、`垃圾桶/`、`godot-interactive-guide/`。

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`。
2. 将画布缩放到 25%。
3. 验证 Mock Batch 仍显示 10 张缩略图，而不是只显示数字/状态条。
4. 在 25% 下点击任意缩略图，验证可以选中单张，并且 K/R/F 审阅快捷键仍能作用到该缩略图。
5. 将画布放大到 400%，验证缩略图仍显示 inspect 细节层（透明棋盘/像素网格/尺寸或色数提示）。
6. 打开 `pixelforge-plan/03-milestones/M3-开发规划.md`，确认 UX-4 已标记为 `NOT-PASSED`，overview 摘要卡不再作为 M3 通过能力。

### 本轮完整 diff

> 注：本报告中的 diff 为完整 staged diff；为避免 Markdown 报告触发 whitespace 检查，代码缩进 tab 在本展示块内展开为空格。

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index 30b57f0..e9314d7 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -31,3 +31,4 @@
 - M3 G-5: 新增 File > Run Selected Graph 最小重跑入口，选中 mock 节点链任一节点后可替换刷新正式 batch 队列。
 - M3 UX-4: 恢复 batch 语义 LOD 原型，改由 camera zoom 下发 overview/review/inspect，覆盖分数缩放下 25% 进入 overview 的回归路径。
 - M3 UX-7: 新增 CanvasHitPolicy 最小输入仲裁层，统一 batch 缩略图、整卡、sprite 和空白画布命中，避免缩略图点击误触拖卡。
+- M3 UX-4: 撤销隐藏缩略图的 overview 摘要卡路径，25% 缩放保持 review 缩略图可见且可命中，计划中标记该 UX-4 原型不予实际通过。
diff --git a/pixel/tests/smoke/test_infinite_canvas.gd b/pixel/tests/smoke/test_infinite_canvas.gd
index 69675b0..41b3a88 100644
--- a/pixel/tests/smoke/test_infinite_canvas.gd
+++ b/pixel/tests/smoke/test_infinite_canvas.gd
@@ -165,7 +165,7 @@ func test_batch_lod_uses_camera_zoom_not_compensated_art_scale() -> void:
    await wait_process_frames(1)

    assert_almost_eq(canvas._get_art_logical_scale(), 0.333, 0.001)
-   assert_eq(card._get_lod_profile(), LODProfile.PROFILE_OVERVIEW)
+   assert_eq(card._get_lod_profile(), LODProfile.PROFILE_REVIEW)

    canvas.set_camera_zoom(4.0, Vector2(160, 120))
    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_INSPECT)
diff --git a/pixel/tests/unit/test_canvas_batch_card.gd b/pixel/tests/unit/test_canvas_batch_card.gd
index 2af1e30..66a1657 100644
--- a/pixel/tests/unit/test_canvas_batch_card.gd
+++ b/pixel/tests/unit/test_canvas_batch_card.gd
@@ -186,21 +186,17 @@ func test_canvas_batch_card_switches_semantic_lod_profiles() -> void:
    var ids := [_register_asset(Color.RED, "red"), _register_asset(Color.BLUE, "blue")]
    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)

-   assert_eq(LODProfile.profile_for_camera_zoom(0.25), LODProfile.PROFILE_OVERVIEW)
+   assert_eq(LODProfile.profile_for_camera_zoom(0.25), LODProfile.PROFILE_REVIEW)
    assert_eq(LODProfile.profile_for_camera_zoom(1.0), LODProfile.PROFILE_REVIEW)
    assert_eq(LODProfile.profile_for_camera_zoom(4.0), LODProfile.PROFILE_INSPECT)
    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_REVIEW)

    card.set_lod_camera_zoom(0.25)
-   assert_eq(card._get_lod_profile(), LODProfile.PROFILE_OVERVIEW)
-   assert_almost_eq(
-       card.get_canvas_bounds().size.y, float(CanvasBatchCardScript.OVERVIEW_HEIGHT), 0.001
-   )
-   assert_eq(card.asset_index_at_world(card.position + Vector2(24, 64)), -1)
+   assert_eq(card._get_lod_profile(), LODProfile.PROFILE_REVIEW)
+   assert_eq(card.asset_index_at_world(card.position + Vector2(24, 64)), 0)

    card.set_lod_camera_zoom(4.0)
    assert_eq(card._get_lod_profile(), LODProfile.PROFILE_INSPECT)
-   assert_gt(card.get_canvas_bounds().size.y, float(CanvasBatchCardScript.OVERVIEW_HEIGHT))
    assert_false(card._asset_hint_for(ids[0]).is_empty())


diff --git a/pixel/tests/unit/test_canvas_hit_policy.gd b/pixel/tests/unit/test_canvas_hit_policy.gd
index c492fad..2ed1fa3 100644
--- a/pixel/tests/unit/test_canvas_hit_policy.gd
+++ b/pixel/tests/unit/test_canvas_hit_policy.gd
@@ -35,7 +35,7 @@ func test_canvas_left_click_on_batch_thumbnail_does_not_start_card_drag() -> voi
    assert_false(canvas._selection.is_dragging_items)


-func test_canvas_hit_policy_treats_overview_batch_as_whole_card() -> void:
+func test_canvas_hit_policy_keeps_batch_thumbnail_available_at_25_percent() -> void:
    var canvas: Control = _canvas()
    var ids := [_register_asset(Color.RED, "red")]
    var card: Node = canvas._add_batch_card(ids, Vector2(16, 24), "Batch", "batch_1", false)
@@ -43,9 +43,9 @@ func test_canvas_hit_policy_treats_overview_batch_as_whole_card() -> void:

    var hit := _hit(canvas, card.position + Vector2(20, 60))

-   assert_eq(hit["kind"], HitPolicy.KIND_ITEM)
+   assert_eq(hit["kind"], HitPolicy.KIND_BATCH_THUMBNAIL)
    assert_eq(hit["item_id"], "batch_1")
-   assert_eq(hit["asset_index"], -1)
+   assert_eq(hit["asset_index"], 0)


 func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index cd7ae7d..658ce00 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -42,8 +42,6 @@ const OUTPUT_PORTS: Array[String] = ["images", "assets"]
 const FOCUS_IMAGE_HEIGHT := 320
 const FOCUS_FILMSTRIP_THUMB_SIZE := 72
 const FOCUS_FILMSTRIP_VISIBLE := 7
-const OVERVIEW_HEIGHT := 124
-const OVERVIEW_BAR_HEIGHT := 12
 const CHECKER_SIZE := 8
 const MAX_INSPECT_COLOR_HINTS := 256
 const CHECKER_LIGHT := Color(0.18, 0.19, 0.2, 1.0)
@@ -331,8 +329,6 @@ func toggle_asset_at_world(world_position: Vector2) -> bool:


 func asset_index_at_world(world_position: Vector2) -> int:
-   if _get_lod_profile() == LODProfile.PROFILE_OVERVIEW:
-       return -1
    var local := world_position - position
    if local.y < HEADER_HEIGHT:
        return -1
@@ -379,10 +375,7 @@ func _draw() -> void:
            Color(0.9, 0.92, 0.92, 1.0)
        )

-   var lod_profile := _get_lod_profile()
-   if lod_profile == LODProfile.PROFILE_OVERVIEW:
-       _draw_overview(visible_ids)
-   elif review_layout == LAYOUT_FOCUS:
+   if review_layout == LAYOUT_FOCUS:
        _draw_focus_layout(visible_ids)
    else:
        var columns := _columns()
@@ -405,46 +398,6 @@ func _draw_focus_layout(visible_ids: Array[String]) -> void:
        _draw_thumbnail(visible_ids[index], _filmstrip_rect(index - start_index))


-func _draw_overview(visible_ids: Array[String]) -> void:
-   var content_rect := Rect2(
-       Vector2(PADDING, HEADER_HEIGHT + PADDING), Vector2(CARD_WIDTH - PADDING * 2, 42.0)
-   )
-   draw_rect(content_rect, Color(0.08, 0.085, 0.09, 1.0), true)
-   if _font != null:
-       draw_string(
-           _font,
-           content_rect.position + Vector2(0.0, 31.0),
-           str(visible_ids.size()),
-           HORIZONTAL_ALIGNMENT_CENTER,
-           content_rect.size.x,
-           28,
-           Color(0.92, 0.94, 0.92, 1.0)
-       )
-   var bar_rect := Rect2(
-       Vector2(PADDING, content_rect.end.y + THUMB_GAP),
-       Vector2(CARD_WIDTH - PADDING * 2, OVERVIEW_BAR_HEIGHT)
-   )
-   _draw_overview_status_bar(bar_rect, visible_ids)
-
-
-func _draw_overview_status_bar(bar_rect: Rect2, visible_ids: Array[String]) -> void:
-   draw_rect(bar_rect, Color(0.08, 0.085, 0.09, 1.0), true)
-   if visible_ids.is_empty():
-       return
-   var counts := _review_counts(visible_ids)
-   var cursor_x := bar_rect.position.x
-   for review_state in [FILTER_PENDING, REVIEW_KEEP, REVIEW_REJECT, REVIEW_FLAG]:
-       var count := int(counts.get(review_state, 0))
-       if count <= 0:
-           continue
-       var width := bar_rect.size.x * float(count) / float(visible_ids.size())
-       var segment := Rect2(
-           Vector2(cursor_x, bar_rect.position.y), Vector2(width, bar_rect.size.y)
-       )
-       draw_rect(segment, _overview_color_for_state(review_state), true)
-       cursor_x += width
-
-
 func _draw_thumbnail(asset_id: String, rect: Rect2) -> void:
    var inspect_mode := _get_lod_profile() == LODProfile.PROFILE_INSPECT
    if inspect_mode:
@@ -585,29 +538,6 @@ func _draw_review_marker(rect: Rect2, review_state: String) -> void:
            )


-func _review_counts(visible_ids: Array[String]) -> Dictionary:
-   var counts := {FILTER_PENDING: 0, REVIEW_KEEP: 0, REVIEW_REJECT: 0, REVIEW_FLAG: 0}
-   for asset_id in visible_ids:
-       var review_state := String(review_states.get(asset_id, REVIEW_NONE))
-       if review_state.is_empty():
-           counts[FILTER_PENDING] += 1
-       else:
-           counts[review_state] = int(counts.get(review_state, 0)) + 1
-   return counts
-
-
-func _overview_color_for_state(review_state: String) -> Color:
-   match review_state:
-       REVIEW_KEEP:
-           return KEEP_MARK
-       REVIEW_REJECT:
-           return REJECT_MARK
-       REVIEW_FLAG:
-           return FLAG_MARK
-       _:
-           return BORDER
-
-
 func _thumb_rect(index: int, columns: int) -> Rect2:
    var col := index % columns
    var row := int(index / columns)
@@ -636,8 +566,6 @@ func _filmstrip_rect(slot_index: int) -> Rect2:


 func _card_height() -> int:
-   if _get_lod_profile() == LODProfile.PROFILE_OVERVIEW:
-       return OVERVIEW_HEIGHT
    var visible_count := get_visible_asset_ids().size()
    if visible_count <= 0:
        return MIN_CARD_HEIGHT
diff --git a/pixel/ui/canvas/canvas_lod_profile.gd b/pixel/ui/canvas/canvas_lod_profile.gd
index 2006b01..03a9f8f 100644
--- a/pixel/ui/canvas/canvas_lod_profile.gd
+++ b/pixel/ui/canvas/canvas_lod_profile.gd
@@ -3,18 +3,14 @@ extends RefCounted

 ## Semantic canvas LOD thresholds shared by canvas-resident items.

-const PROFILE_OVERVIEW := "overview"
 const PROFILE_REVIEW := "review"
 const PROFILE_INSPECT := "inspect"
-const OVERVIEW_MAX_CAMERA_ZOOM := 0.25
 const INSPECT_MIN_CAMERA_ZOOM := 4.0
 const PIXEL_GRID_MIN_PHYSICAL_CELL := 4.0


 static func profile_for_camera_zoom(camera_zoom: float) -> String:
    var safe_zoom := maxf(camera_zoom, 0.0)
-   if safe_zoom <= OVERVIEW_MAX_CAMERA_ZOOM:
-       return PROFILE_OVERVIEW
    if safe_zoom >= INSPECT_MIN_CAMERA_ZOOM:
        return PROFILE_INSPECT
    return PROFILE_REVIEW
diff --git "a/pixelforge-plan/03-milestones/M3-\345\274\200\345\217\221\350\247\204\345\210\222.md" "b/pixelforge-plan/03-milestones/M3-\345\274\200\345\217\221\350\247\204\345\210\222.md"
new file mode 100644
index 0000000..e904876
--- /dev/null
+++ "b/pixelforge-plan/03-milestones/M3-\345\274\200\345\217\221\350\247\204\345\210\222.md"
@@ -0,0 +1,409 @@
+# M3 开发规划 — UX-First 体验关键技术原型层 + 最小节点闭环
+
+> 本文件是 M3 的**施工主计划**。`M3-node-graph.md` 保留为节点功能规格参考，不再作为施工顺序。
+> M3 的目标不是一次性把交互设计定稿，而是先铺一层可真实使用、可快速反馈、可持续迭代的体验关键技术基础，并在此基础上走通最小节点闭环。
+> 功能与数据契约仍以 `02-contracts/GRAPH-SCHEMA.md`、`PROJECT-FORMAT.md`、`01-architecture/ARCHITECTURE.md`、`00-vision/PRODUCT.md` 为准；如果契约阻碍体验闭环，本里程碑先提出契约修订卡，不静默绕过。
+
+---
+
+## 0. M3 的新定位
+
+M2 的教训不是“技术做太多”，而是很多技术没有锚定真实使用动作：能导入但看不舒服，能缩放但触控板难用，能批处理但无法判断变好变坏，能做卡片但只是把僵硬格子放大一号。
+
+M3 因此先做体验关键技术原型层：
+
+```
+导入真图/Mock 生成
+  → 能舒服看和调显示尺寸
+  → 能自然审阅批次
+  → 能整批加工并前后对比
+  → 能挑选收窄
+  → 能导出
+  → 最小节点链接入这个闭环
+```
+
+节点图仍是 M3 的核心方向，但本轮施工顺序变为：
+
+1. 体验关键技术原型层先行。
+2. 批次卡作为审阅/加工工作台先做顺。
+3. Graph 最小核与 Mock 生成只服务闭环，不抢在体验基础之前铺完整执行器。
+4. 完整 executor、全套 process 节点、复杂缓存、选区兜底后移到 M3 后段或 M3.5。
+
+---
+
+## 1. 禁止技术自嗨：技术卡必填格式
+
+每张技术卡必须先回答“服务谁”，再讲实现。没有下表字段的卡不得进入 M3 主线。
+
+| 字段 | 必填内容 |
+|---|---|
+| 服务对象 | 用户是谁，在做什么动作 |
+| 当前痛点 | 现在为什么难用 |
+| 技术选择 | 本阶段具体采用什么实现 |
+| 选择原因 | 为什么它适合 M3 当前阶段 |
+| 优势 | 它立即改善什么 |
+| 缺陷 | 它解决不了什么，可能带来什么副作用 |
+| 改进空间 | 后续可以如何演化 |
+| 验证入口 | 怎么证明它真的服务体验 |
+
+体验关键技术必须打标：
+
+| 标记 | 含义 | M3 要求 |
+|---|---|---|
+| `UX-CRITICAL` | 直接影响愿不愿意用 | 前置施工，不放到尾部“打磨” |
+| `M3-PROTOTYPE` | M3 只是可反馈原型 | 完成报告必须写清“不代表最终设计” |
+| `FEEDBACK-REQUIRED` | 需要实机/真人反馈才能定 | 必须有手测、录屏/截图、反馈导出 |
+| `DESIGN-DEBT` | 已知设计债 | 登记到台账，不许后续静默继承 |
+| `ITERATION-HOOK` | 后续调参/重构入口 | 策略、阈值、速度不能硬编码死 |
+| `TECH-BACKBONE` | 支撑闭环的技术骨架 | 服务体验闭环，不以功能完整度自嗨 |
+
+---
+
+## 2. 原型期决定
+
+1. **风格预设不在项目入口**：项目素材可能风格多样，M3 将风格选择并入整批加工参数；`style_preset` 仍可作为可选节点喂给 mock/未来 AI 生成。
+2. **原型期功能平铺**：节点添加、batch 菜单、参数检查器先平铺，便于发现每个能力是否真的可用；稳定后再恢复渐进暴露。
+3. **schema 就地修订**：预发布期不写迁移；受影响测试夹具重生成。
+4. **废弃 M2 临时 `batch_card` 兼容**：M3 只写正式 `type=node` + graph batch；旧测试夹具直接重建。
+5. **选区兜底不进 M3 主出口**：W/M/L 真轮廓与算法接入进入 M3.5 或 M6；M3 不混入半成品。
+6. **所有 UX-critical 项只承诺原型层**：LOD、卡片、导航、显示尺寸、批次审阅、前后对比都不宣称最终设计完成。
+
+---
+
+## 3. 使用闭环
+
+```
+①进入
+ → ②导入真图 / 搭最小 mock 节点链
+ → ③落入正式 batch
+ → ④调显示尺寸 + LOD 审阅
+ → ⑤整批加工（含风格/调色板/网格）
+ → ⑥前后对比
+ → ⑦挑选/标记/拆小批次
+ → ⑧导出
+ ↻ 回到导入/生成/加工
+```
+
+| 步 | 名称 | M3 要走通的体验 |
+|---|---|---|
+| ① | 进入 | 打开即空白工作空间，不要求先选风格 |
+| ② | 输入 | 并行入口：导入真实图；最小节点链只做 object_list + size_spec + ai_generate(mock) |
+| ③ | 落批次 | 生成/导入结果进入正式 batch 节点，batch 是审阅和加工容器 |
+| ④ | 审阅 | 用户能舒服 pan/zoom、调显示尺寸、用 LOD 看全局和细节 |
+| ⑤ | 加工 | batch 菜单先做统一参数/预览/进度/撤销壳，再接算法 |
+| ⑥ | 对比 | 整批处理后有 before/after 入口，能判断结果是否变好 |
+| ⑦ | 收窄 | keep/reject/flag、焦点图、过滤、拆小批次 |
+| ⑧ | 导出 | 整批 PNG / spritesheet / JSON，默认 1:1 真像素 |
+
+---
+
+## 4. 反馈迭代机制
+
+M3 新增 `M3-UX反馈验收清单.html`，参考 M2.2 验收 HTML 的机制：
+
+- 顶部元信息：验收人、平台/分辨率、日期、轮次/commit。
+- 每项状态：`通过 / 未过 / 原型待迭代 / N.A.`。
+- 支持筛选：未测、未过、原型待迭代、UX-CRITICAL、DESIGN-DEBT、TECH-BACKBONE。
+- 每项记录：服务对象、当前痛点、技术选择、体验验收动作、实测结果、下一轮迭代建议。
+- 每个模块有自由反馈窗口。
+- 自动保存到 localStorage。
+- 支持导出 Markdown / JSON；每轮施工后导出结果回填到 `03-milestones/reports/`。
+
+规则：
+
+- `未过` 与 `原型待迭代` 不得静默消失，必须进入 `M3-设计债台账.md`；如果立即转成下一轮任务卡，也要在台账中标记迁出位置。
+- UX-critical 卡的完成报告必须写：
+  - 实机验了什么；
+  - 哪些只是原型；
+  - 本轮技术选择的优势和缺陷；
+  - 哪些参数/策略留作迭代入口；
+  - 哪些反馈会触发下一轮调整。
+
+---
+
+## 5. 施工切片总览
+
+| 切片 | 标记 | 走通到哪 | 依赖 |
+|---|---|---|---|
+| UX-0 验收基线与反馈机制 | `UX-CRITICAL` | 有可填写、可导出的 M3 体验验收工具 | 无 |
+| UX-1 相机与触控板导航策略 | `UX-CRITICAL / M3-PROTOTYPE` | 鼠标/触控板都能顺手移动和缩放 | UX-0 |
+| UX-2 导入显示尺寸模型 | `UX-CRITICAL / M3-PROTOTYPE` | 不同尺寸图能按审阅语义调整显示 | UX-1 可并行 |
+| UX-3 批次卡布局与审阅容器 | `UX-CRITICAL / DESIGN-DEBT` | batch 不再是固定硬卡片 | UX-2 |
+| UX-4 语义 LOD | `UX-CRITICAL / NOT-PASSED` | 隐藏缩略图的 overview 不予实际通过；M3 仅保留 review/inspect 可用路径 | UX-1/UX-3 |
+| UX-5 批次审阅状态 | `UX-CRITICAL` | 50 张里能快速挑选收窄 | UX-3 |
+| UX-6 前后对比 | `UX-CRITICAL / FEEDBACK-REQUIRED` | 整批加工后能判断变好/变坏 | UX-5 |
+| UX-7 Hit-test 与输入仲裁 | `UX-CRITICAL / ITERATION-HOOK` | 拖卡、点图、框选、连线、平移不抢输入 | UX-1/UX-3 |
+| G-1 Graph 最小核 + batch 持久化 | `TECH-BACKBONE` | 正式 graph batch 可保存重开 | UX-2 可并行 |
+| G-2 Mock generate 落 batch | `TECH-BACKBONE` | 最小节点链能产出 batch | G-1 |
+| G-3 批次菜单与 PixelOperations | `TECH-BACKBONE` | 菜单与未来 process 节点共用 core | UX-6/G-1 |
+| G-4 最小节点链验收 | `TECH-BACKBONE` | 节点链接入体验地基 | UX-7/G-2 |
+
+---
+
+## 6. UX 体验关键技术卡
+
+### UX-0 体验验收基线与反馈机制
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 项目 owner、施工 agent、后续测试者 |
+| 当前痛点 | M2 的问题靠对话里零散反馈暴露，缺少统一记录和回归入口 |
+| 技术选择 | 新增 M3 UX HTML 验收清单 + 手测脚本 + 设计债台账 |
+| 选择原因 | 先建立反馈机制，后续卡片才不会靠口头感觉收尾 |
+| 优势 | 每轮施工都能导出 Markdown/JSON，未过项可追踪 |
+| 缺陷 | HTML 只是本地验收工具，不替代真实用户研究 |
+| 改进空间 | 后续可接截图上传、录屏索引、问题编号、自动生成报告 |
+| 验证入口 | 打开 HTML，填写一轮“导航手感”模块，导出 Markdown/JSON |
+
+任务：
+
+- 新增 `M3-UX反馈验收清单.html`。
+- 新增并维护 `M3-设计债台账.md`。
+- 新增/更新 `manual-test-m3-ux.md`（可在后续卡补）。
+- 将 `外部交互成熟做法调研.md` 引为 UX 依据。
+- 每个 UX-critical 卡预置反馈项。
+
+### UX-1 相机与触控板导航策略
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 用触控板/鼠标在大画布里反复审阅、移动、缩放素材的人 |
+| 当前痛点 | 双指滑动速率怪、方向感差；滚轮限频粗暴；缩放后还要重新找内容 |
+| 技术选择 | 新增 `CanvasNavigationPolicy`，统一 wheel、pan gesture、magnify gesture、Space drag、middle drag、fit commands |
+| 选择原因 | 现有逻辑散在 `PFInfiniteCanvas`，继续补丁会让输入冲突越来越多 |
+| 优势 | 手感参数集中，可测试、可调、可回滚；为节点端口和卡片 hit-test 留空间 |
+| 缺陷 | M3 很难一次调出最终手感；不同设备仍需实机反馈 |
+| 改进空间 | 用户偏好、设备识别、minimap、惯性滚动 |
+| 验证入口 | Mac 触控板 + 鼠标各 5 分钟录屏；锚点缩放漂移 ≤1px；50 元素画布不误拖 |
+
+任务：
+
+- 支持 `InputEventPanGesture`、`InputEventMagnifyGesture`、滚轮、Space/中键/可选右键平移。
+- 参数集中：pan speed、zoom speed、wheel mode、gesture threshold、animation duration。
+- 增加 Fit All、Fit Selection、Focus New Import、Recenter。
+- 自动测试：锚点漂移、速度限幅、pan/zoom 不误触对象。
+
+### UX-2 导入显示尺寸模型
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 导入不同尺寸参考图/素材图后，希望马上能比较的人 |
+| 当前痛点 | 16px 图太小、1024px 图太大；整数 `scale_factor` 没有审阅尺寸语义 |
+| 技术选择 | 分离 `source_size` 与 `display_bounds`，显示尺寸不改变源图像和导出像素 |
+| 选择原因 | 像素工具必须保持源像素可信，但参考板需要自由显示尺度 |
+| 优势 | 可以 Actual Pixels、Fit Compare、Custom Size、Match Height/Width |
+| 缺陷 | 项目格式要扩展；选择框、命中、工具坐标都要读 display transform |
+| 改进空间 | crop/fill/tile、精确尺寸输入、批量 normalize |
+| 验证入口 | 导入 16×16、32×64、256×128 后能调成同高度比较；导出像素不变 |
+
+任务：
+
+- `sprite` 和 batch 内素材都使用非破坏显示尺寸。
+- 导入空画布时自动铺开并聚焦；已有内容时落在鼠标/选区附近。
+- 保存/重开恢复 display bounds。
+- 保持导出 1:1 真像素。
+
+### UX-3 批次卡布局与审阅容器
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 一次看 12-50 张候选图、筛出可用素材的人 |
+| 当前痛点 | 固定大卡片只是“格子变大”，不同尺寸图仍不好比，50 张会变成长硬板 |
+| 技术选择 | `BatchReviewLayout`：contact sheet / focus / compact 三种原型布局，卡宽、缩略密度、焦点图可保存 |
+| 选择原因 | 批次卡是 M3 的核心工作台，不是普通容器 |
+| 优势 | 能按审阅场景切换，不再靠整卡僵硬放大 |
+| 缺陷 | M3 视觉设计仍是原型；布局算法需要多轮手感反馈 |
+| 改进空间 | masonry、filmstrip、compare mode、自动聚类 |
+| 验证入口 | 50 张在 13 寸屏能看出差异；选中/拖卡/拖单图不互相误触 |
+
+任务：
+
+- 替代硬编码 `CARD_WIDTH` / `THUMB_SIZE` 的唯一布局模型。
+- 支持卡宽、缩略图密度、网格锁定、焦点图。
+- 标题、计数、状态、进度不遮挡缩略图。
+- contact sheet 和 focus 模式至少各可用。
+
+### UX-4 语义 LOD
+
+> **2026-06-20 实机反馈结论：不予实际通过。** 25% 进入 overview 后隐藏缩略图，破坏批次审阅闭环；M3 不再把“隐藏缩略图的 overview 摘要卡”视为可交付能力。后续若重做 UX-4，必须先给出保留图像可辨识度的方案。
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 在同一画布里既看全局结构，又看像素细节的人 |
+| 当前痛点 | 现在只有像素网格阈值，没有卡片/节点/批次各自显示详略策略 |
+| 技术选择 | `CanvasLODProfile`：M3 仅启用 review / inspect；overview 摘要卡冻结，不进入实际通过口径 |
+| 选择原因 | LOD 是理解画布的节奏，不是后期美化 |
+| 优势 | 缩小时不乱，放大后有细节，节点/batch/sprite 共用规则 |
+| 缺陷 | overview 隐藏缩略图已实机失败；缩小时不能牺牲候选图可辨识度 |
+| 改进空间 | 动态 LOD、移动中降级渲染、缩略图金字塔 |
+| 验证入口 | 25% 缩放仍显示缩略图且能点选；4x 放大显示 inspect 细节 |
+
+任务：
+
+- overview：不予实际通过并冻结；M3 不再隐藏缩略图。
+- review：缩略图、选择状态、进度、错误。
+- inspect：像素网格、透明棋盘、尺寸/色数提示。
+- LOD 阈值集中配置，不散落在卡片脚本。
+
+### UX-5 批次审阅状态
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 在一批候选中快速挑选、排除、保留、拆小批的人 |
+| 当前痛点 | 现在只有勾选；没有 keep/reject/flag，没有键盘审阅节奏 |
+| 技术选择 | `BatchReviewState`：keep / reject / flag / focus_asset_id / filter |
+| 选择原因 | 批量优先不是“批量处理按钮”，而是批量决策流程 |
+| 优势 | 能快速筛选，拆小批次有明确依据 |
+| 缺陷 | M3 不做完整素材管理系统；状态语义先保持轻量 |
+| 改进空间 | rating、tag、notes、按 prompt/来源聚类 |
+| 验证入口 | 50 张素材 2 分钟内挑出 8 张并拆成新批次 |
+
+任务：
+
+- 快捷标记 keep/reject/flag。
+- 焦点图上一张/下一张。
+- 只看保留/只看未定/只看 reject。
+- 从 keep 集合拆小批次，原批次不变。
+
+### UX-6 前后对比
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 整批清洗/抠图/描边后，需要判断结果是否变好的人 |
+| 当前痛点 | 当前处理后直接替换 batch 视觉内容，原图只在 provenance 里 |
+| 技术选择 | 批次处理生成 version pair，提供 A/B 切换和并排对比原型 |
+| 选择原因 | 没有对比就无法判断算法价值，用户只能撤销猜测 |
+| 优势 | 能看清处理收益和失败项；也能暴露算法问题 |
+| 缺陷 | M3 只做最小对比，不做专业 diff/sync zoom 全套 |
+| 改进空间 | overlay、split view、同步 pan/zoom、差异热区 |
+| 验证入口 | Clean/Matte/Outline 后能快速指出哪张变好、哪张变坏 |
+
+任务：
+
+- 批处理后保留 before/after 对比入口。
+- 至少实现 A/B 切换 + 并排对比两种路径中的一种稳定路径，优先 A/B 切换。
+- 失败项、跳过项、处理中状态可见。
+- Undo 整批回退。
+
+### UX-7 Hit-test 与输入仲裁
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 在同一画布上拖卡、点缩略图、框选、连节点、平移的人 |
+| 当前痛点 | 现在 batch 整卡是大 hit box；M3 加端口/连线后很容易互抢输入 |
+| 技术选择 | `CanvasHitPolicy`：端口、resize handle、缩略图、卡边框、sprite、空白画布按优先级仲裁 |
+| 选择原因 | 输入冲突会直接毁掉工具手感，必须前置 |
+| 优势 | 每个交互区域可测试，后续节点不会硬插补丁 |
+| 缺陷 | 初期规则可能偏保守；需要真实操作反馈 |
+| 改进空间 | hit debug overlay、用户可调拖拽阈值 |
+| 验证入口 | 录屏验证：拖卡、点图、框选、平移、连线互不误触 |
+
+任务：
+
+- 明确优先级：端口/连线手柄 > resize handle > 缩略图 > 卡边框 > sprite > 框选 > 空白 pan。
+- 增加 hit debug 开关（可后续落地）。
+- 端口命中优先于框选，缩略图点击不误触拖卡。
+
+---
+
+## 7. 技术骨架卡
+
+### G-1 Graph 最小核 + batch 持久化
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 让批次卡从临时 UI 数据变成可保存、可生成、可加工的一等节点 |
+| 当前痛点 | M2 `batch_card` 直接存 canvas，无法支撑节点链和逻辑/视图分离 |
+| 技术选择 | `PFNode/PFGraph/NodeRegistry` 最小实现 + `batch` 节点 + ProjectService 写读 graphs |
+| 选择原因 | 只做 batch 所需最小集合，避免 graph 体系抢跑体验基础 |
+| 优势 | 批次正式化，后续 mock/node/process 都能接 |
+| 缺陷 | 本卡不做完整连接语义、幽灵节点体验、复杂 executor |
+| 改进空间 | 后续补 can_connect、ghost、schema 校验、插件节点 |
+| 验证入口 | graph batch `asset_ids` round-trip，canvas node 引用对账 |
+
+保留自 `M3-node-graph.md` 的技术要求：
+
+- `PFNode` 基类：端口、参数、`execute()`、`is_canvas_resident()`、`get_canvas_actions()`。
+- `PFGraph`：nodes 容器、edges 字段预留、to_json/from_json。
+- `NodeRegistry`：内置 batch 注册，type 冲突拒绝。
+
+### G-2 Mock generate 落 batch
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 没有 API key 的测试者也能走生成→审阅→加工闭环 |
+| 当前痛点 | M3 若等待真实 provider，会阻塞节点体验验证 |
+| 技术选择 | `provider_mock` 生成确定性占位图，seed 决定颜色/图案 |
+| 选择原因 | 稳定、可复现、无网络，方便验收和录屏 |
+| 优势 | 节点链可以尽早接入 batch 工作台 |
+| 缺陷 | 不能代表真实 AI 图质量问题；仍需导入真图入口验证算法 |
+| 改进空间 | M4 替换为 provider service + RetroDiffusion/OpenAI |
+| 验证入口 | object_list 5 项 × batch_size 2，落 10 张可复现图 |
+
+### G-3 批次菜单与 PixelOperations
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 想快速整批处理，同时未来需要可复现节点路径的人 |
+| 当前痛点 | M2 菜单动作散在 UI controller，菜单和未来节点可能分叉 |
+| 技术选择 | 抽 `PixelOperations`，菜单路径和 process 节点共用同一 core 函数 |
+| 选择原因 | 先服务菜单体验，后包装成节点，不复制算法 |
+| 优势 | 逐像素一致，provenance 一致，测试口径一致 |
+| 缺陷 | 初期 operation schema 可能不完整，需要随着参数对话框迭代 |
+| 改进空间 | 统一 operation registry、插件注册 canvas action |
+| 验证入口 | 同输入经菜单 Clean 和未来 pixel_cleanup 节点输出一致 |
+
+### G-4 最小节点链验收
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 希望用轻节点批量生成候选，再回到批次工作台审阅的人 |
+| 当前痛点 | 原 M3 过早追完整节点系统，会拖慢可用工具闭环 |
+| 技术选择 | 只做 `object_list → size_spec → ai_generate(mock) → batch` 最小链 |
+| 选择原因 | 能验证节点与画布/batch/LOD/hit-test 共存，不陷入完整 executor 自嗨 |
+| 优势 | M3 仍保留节点主轴，但不牺牲体验基础 |
+| 缺陷 | 暂不覆盖全部 process 节点、复杂缓存、select 暂停 |
+| 改进空间 | 后续按 `M3-node-graph.md` 补 executor/process/ghost |
+| 验证入口 | 鼠标搭链、Run、结果落 batch、保存重开一致 |
+
+---
+
+## 8. 从原 M3 规划继承与降级
+
+| 原规划内容 | M3 本轮处理 |
+|---|---|
+| 图领域模型 | 保留，但缩到 G-1 最小核 |
+| 连接语义 / can_connect / 环检测 | G-4 后补；不阻塞 UX 前置 |
+| 完整 executor | 降级，M3 前半只做 mock 最小链 |
+| 1GB LRU / 复杂缓存 | M3 后段或 M3.5 |
+| 自绘节点与连线层 | 保留，但必须复用 UX-1/UX-4/UX-7 |
+| 自动检查器 | 保留为后段节点体验，不抢 UX 基础 |
+| 全套 process 节点 | 后移；先把菜单路径体验做顺 |
+| batch 内容节点 | 升级为 M3 核心，但按 UX-3/UX-5/UX-6 重构 |
+| 选区兜底 | 延后，不进 M3 出口 |
+| S5 LOD 打磨 | 前置为 UX-4，不再是收尾补丁 |
+
+---
+
+## 9. 出口门
+
+M3 出口不是“所有节点功能都实现”，而是：
+
+1. 新测试者只拿工具和验收清单，不需要口头指导。
+2. 能导入真实素材，调整显示尺寸，舒服导航。
+3. 能在 batch 中审阅 50 张，标记/过滤/拆出小批次。
+4. 能整批处理并前后对比。
+5. 能导出 PNG / spritesheet。
+6. 能用最小节点链 mock 生成并落入同一个 batch 工作台。
+7. 所有未过和原型待迭代项均导出到 reports，并回填 `M3-设计债台账.md`。
+
+---
+
+## 10. 参考依据
+
+- `pixelforge-plan/04-research/外部交互成熟做法调研.md`
+- Figma / FigJam：画布导航、zoom to selection、触控板手势。
+- Miro：鼠标/触控板/触屏导航、结构化画布、批量 resize。
+- tldraw：camera system、LOD、viewport culling。
+- PureRef：参考板导入、normalize、arrange、低干扰导航。
+- Lightroom / Capture One / Bridge：批量审阅、compare/survey、flag/rating/label。
```

## 2026-06-20 M3 UX-7 graph port hit policy follow-up

### 本轮实现说明

- 在 `CanvasHitPolicy` 中新增 `graph_port` 命中类型，统一返回 `port_name`、`is_input`、`port_index`。
- `CanvasNodeCard` 与 graph-bound `CanvasBatchCard` 提供端口半径命中查询，端口命中优先于 batch 缩略图、整卡拖动和空白框选。
- `PFInfiniteCanvas` 左键按在 graph port 上时只选择对应卡片，不启动拖卡，为后续“从端口拖线”留出集中入口。
- 新增 3 条 UX-7 单元回归：batch 输入端口优先于缩略图、普通节点右侧输出端口在卡片边界上可命中、端口点击不启动拖卡。

### 验证结果

- `./pixel/scripts/lint.sh`：通过。
- `./pixel/scripts/run_tests.sh`：通过，157/157 tests passed。
- `./pixel/scripts/verify_m3_ux7.sh`：首次受沙箱限制无法写入 Godot editor settings；提升权限重跑后通过，包含 lint、run_tests、check_ui_scaling、check_export_templates。
- staged 图片检查：无 PNG/JPG/JPEG。
- staged 保留目录检查：未包含 `test picture/`、`pixel/tests/fixtures/real/`、`垃圾桶/`、`godot-interactive-guide/`。

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`。
2. 点击 Object List / Size Spec / AI Generate / Mock Batch 卡片左右两侧的小圆端口，确认选中对应卡片，但不会立刻拖动卡片。
3. 点击 Mock Batch 卡片内部缩略图，确认仍选中单张缩略图，而不是被端口策略误吞。
4. 轻微拖动卡片正文区域，确认普通拖卡仍可用。
5. 重点试右侧输出端口：点击卡片右边界上的输出点，确认它可命中并且不需要点到卡片内部。

### 本轮完整 diff

> 注：本报告中的 diff 为完整实现 diff；为避免 Markdown 报告触发 whitespace 检查，代码缩进 tab 在本展示块内展开为空格。

```diff
diff --git a/pixel/CHANGELOG.md b/pixel/CHANGELOG.md
index e9314d7..3e28865 100644
--- a/pixel/CHANGELOG.md
+++ b/pixel/CHANGELOG.md
@@ -32,3 +32,4 @@
 - M3 UX-4: 恢复 batch 语义 LOD 原型，改由 camera zoom 下发 overview/review/inspect，覆盖分数缩放下 25% 进入 overview 的回归路径。
 - M3 UX-7: 新增 CanvasHitPolicy 最小输入仲裁层，统一 batch 缩略图、整卡、sprite 和空白画布命中，避免缩略图点击误触拖卡。
 - M3 UX-4: 撤销隐藏缩略图的 overview 摘要卡路径，25% 缩放保持 review 缩略图可见且可命中，计划中标记该 UX-4 原型不予实际通过。
+- M3 UX-7: CanvasHitPolicy 纳入 graph port 命中，端口优先于 batch 缩略图和整卡拖动，为后续连线交互保留集中入口。
diff --git a/pixel/tests/unit/test_canvas_hit_policy.gd b/pixel/tests/unit/test_canvas_hit_policy.gd
index 2ed1fa3..a9745c5 100644
--- a/pixel/tests/unit/test_canvas_hit_policy.gd
+++ b/pixel/tests/unit/test_canvas_hit_policy.gd
@@ -48,6 +48,54 @@ func test_canvas_hit_policy_keeps_batch_thumbnail_available_at_25_percent() -> v
    assert_eq(hit["asset_index"], 0)


+func test_canvas_hit_policy_prioritizes_batch_graph_port_over_thumbnail() -> void:
+   var canvas: Control = _canvas()
+   var ids := [_register_asset(Color.RED, "red")]
+   _set_graph("graph_hit", [_batch_node("batch_1", ids)])
+   var card: Node = canvas._add_batch_card(
+       ids, Vector2(16, 24), "Batch", "batch_item", false, "graph_hit", "batch_1"
+   )
+
+   var hit := _hit(canvas, card.get_graph_port_anchor("in", true))
+
+   assert_eq(hit["kind"], HitPolicy.KIND_GRAPH_PORT)
+   assert_eq(hit["item_id"], "batch_item")
+   assert_eq(hit["port_name"], "in")
+   assert_true(hit["is_input"])
+   assert_eq(hit["asset_index"], -1)
+
+
+func test_canvas_hit_policy_reports_node_output_port_on_card_edge() -> void:
+   var canvas: Control = _canvas()
+   _set_graph("graph_hit", [_graph_node("objects", "object_list")])
+   var node: Node = canvas._add_node_direct(
+       _node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
+   )
+
+   var hit := _hit(canvas, node.get_graph_port_anchor("items", false))
+
+   assert_eq(hit["kind"], HitPolicy.KIND_GRAPH_PORT)
+   assert_eq(hit["item_id"], "objects_item")
+   assert_eq(hit["port_name"], "items")
+   assert_false(hit["is_input"])
+   assert_eq(hit["port_index"], 0)
+
+
+func test_canvas_left_click_on_graph_port_selects_without_dragging_card() -> void:
+   var canvas: Control = _canvas()
+   _set_graph("graph_hit", [_graph_node("objects", "object_list")])
+   var node: Node = canvas._add_node_direct(
+       _node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
+   )
+
+   canvas._begin_left_interaction(
+       canvas.world_to_screen(node.get_graph_port_anchor("items", false)), false
+   )
+
+   assert_eq(canvas.get_selected_ids(), ["objects_item"])
+   assert_false(canvas._selection.is_dragging_items)
+
+
 func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
    var canvas: Control = _canvas()
    var ids := [_register_asset(Color.RED, "red")]
@@ -90,6 +138,40 @@ func _register_asset(color: Color, name: String) -> String:
    return AssetLibrary.register_image(_image(color), name, {"origin": "imported"})


+func _set_graph(graph_id: String, nodes: Array) -> void:
+   ProjectService.set_graph_data(
+       graph_id,
+       {"graph_version": 1, "id": graph_id, "name": "Hit Policy", "nodes": nodes, "edges": []}
+   )
+
+
+func _graph_node(node_id: String, node_type: String) -> Dictionary:
+   return {"id": node_id, "type": node_type, "params": {}, "position": [0, 0]}
+
+
+func _batch_node(node_id: String, asset_ids: Array) -> Dictionary:
+   return {
+       "id": node_id,
+       "type": "batch",
+       "params": {"asset_ids": asset_ids.duplicate(), "label": "Batch"},
+       "position": [0, 0],
+   }
+
+
+func _node_item(
+   item_id: String, graph_id: String, node_id: String, position: Vector2
+) -> Dictionary:
+   return {
+       "id": item_id,
+       "type": "node",
+       "graph_id": graph_id,
+       "node_id": node_id,
+       "position": [int(position.x), int(position.y)],
+       "z_index": 0,
+       "locked": false,
+   }
+
+
 func _image(color: Color) -> Image:
    var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
    image.fill(color)
diff --git a/pixel/ui/canvas/canvas_batch_card.gd b/pixel/ui/canvas/canvas_batch_card.gd
index 658ce00..0e25f7a 100644
--- a/pixel/ui/canvas/canvas_batch_card.gd
+++ b/pixel/ui/canvas/canvas_batch_card.gd
@@ -42,6 +42,7 @@ const OUTPUT_PORTS: Array[String] = ["images", "assets"]
 const FOCUS_IMAGE_HEIGHT := 320
 const FOCUS_FILMSTRIP_THUMB_SIZE := 72
 const FOCUS_FILMSTRIP_VISIBLE := 7
+const PORT_HIT_RADIUS := 10.0
 const CHECKER_SIZE := 8
 const MAX_INSPECT_COLOR_HINTS := 256
 const CHECKER_LIGHT := Color(0.18, 0.19, 0.2, 1.0)
@@ -167,6 +168,15 @@ func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
    return position + _graph_port_position(index, count, is_input)


+func _graph_port_at_world(world_position: Vector2) -> Dictionary:
+   if not has_graph_binding():
+       return {}
+   var input_hit := _port_hit_at_world(world_position, true)
+   if not input_hit.is_empty():
+       return input_hit
+   return _port_hit_at_world(world_position, false)
+
+
 func set_asset_ids(new_asset_ids: Array) -> void:
    asset_ids = _string_array(new_asset_ids)
    for selected_id in selected_asset_ids.duplicate():
@@ -605,6 +615,16 @@ func _graph_port_position(index: int, count: int, is_input: bool) -> Vector2:
    return Vector2(0.0 if is_input else CARD_WIDTH, y)


+func _port_hit_at_world(world_position: Vector2, is_input: bool) -> Dictionary:
+   var ports := INPUT_PORTS if is_input else OUTPUT_PORTS
+   var count := ports.size()
+   for index in range(count):
+       var anchor := position + _graph_port_position(index, count, is_input)
+       if anchor.distance_to(world_position) <= PORT_HIT_RADIUS:
+           return {"port_name": ports[index], "is_input": is_input, "port_index": index}
+   return {}
+
+
 func _rebuild_thumbnails() -> void:
    _thumbnail_textures.clear()
    _asset_hints.clear()
diff --git a/pixel/ui/canvas/canvas_hit_policy.gd b/pixel/ui/canvas/canvas_hit_policy.gd
index 7a31588..92d0df5 100644
--- a/pixel/ui/canvas/canvas_hit_policy.gd
+++ b/pixel/ui/canvas/canvas_hit_policy.gd
@@ -6,6 +6,7 @@ extends RefCounted
 const KIND_EMPTY := "empty"
 const KIND_ITEM := "item"
 const KIND_BATCH_THUMBNAIL := "batch_thumbnail"
+const KIND_GRAPH_PORT := "graph_port"


 static func hit_at_world(
@@ -20,7 +21,12 @@ static func hit_at_world(
        var item := children[index]
        if not _is_canvas_item(item, batch_card_script, sprite_script, node_card_script):
            continue
-       if not item.visible or not item.contains_world_point(world_position):
+       if not item.visible:
+           continue
+       var port_hit := _graph_port_at_world(item, world_position)
+       if not port_hit.is_empty():
+           return _graph_port_hit(item, port_hit)
+       if not item.contains_world_point(world_position):
            continue
        if item.get_script() == batch_card_script:
            var asset_index: int = item.asset_index_at_world(world_position)
@@ -39,5 +45,22 @@ static func _is_canvas_item(
    return script == batch_card_script or script == sprite_script or script == node_card_script


+static func _graph_port_at_world(item: Node, world_position: Vector2) -> Dictionary:
+   if not item.has_method("_graph_port_at_world"):
+       return {}
+   var raw_hit: Variant = item.call("_graph_port_at_world", world_position)
+   if raw_hit is Dictionary:
+       return raw_hit
+   return {}
+
+
 static func _hit(kind: String, item: Node, asset_index: int) -> Dictionary:
    return {"kind": kind, "item": item, "item_id": item.item_id, "asset_index": asset_index}
+
+
+static func _graph_port_hit(item: Node, port_hit: Dictionary) -> Dictionary:
+   var hit := _hit(KIND_GRAPH_PORT, item, -1)
+   hit["port_name"] = String(port_hit.get("port_name", ""))
+   hit["is_input"] = bool(port_hit.get("is_input", false))
+   hit["port_index"] = int(port_hit.get("port_index", -1))
+   return hit
diff --git a/pixel/ui/canvas/canvas_node_card.gd b/pixel/ui/canvas/canvas_node_card.gd
index 256e81f..7f0c6e9 100644
--- a/pixel/ui/canvas/canvas_node_card.gd
+++ b/pixel/ui/canvas/canvas_node_card.gd
@@ -16,6 +16,7 @@ const BORDER := Color(0.56, 0.64, 0.66, 1.0)
 const GHOST_BORDER := Color(0.8, 0.36, 0.36, 1.0)
 const PORT_IN := Color(0.32, 0.64, 1.0, 1.0)
 const PORT_OUT := Color(0.24, 0.85, 0.58, 1.0)
+const PORT_HIT_RADIUS := 10.0

 var item_id := ""
 var graph_id := ""
@@ -83,6 +84,13 @@ func get_graph_port_anchor(port_name: String, is_input: bool) -> Vector2:
    return position + _port_position(index, count, is_input)


+func _graph_port_at_world(world_position: Vector2) -> Dictionary:
+   var input_hit := _port_hit_at_world(world_position, true)
+   if not input_hit.is_empty():
+       return input_hit
+   return _port_hit_at_world(world_position, false)
+
+
 func _draw() -> void:
    _font = ThemeDB.fallback_font if _font == null else _font
    var rect := Rect2(Vector2.ZERO, CARD_SIZE)
@@ -139,6 +147,16 @@ func _port_index(port_name: String, is_input: bool) -> int:
    return ports.find(port_name)


+func _port_hit_at_world(world_position: Vector2, is_input: bool) -> Dictionary:
+   var ports := _visible_input_ports if is_input else _visible_output_ports
+   var count := ports.size()
+   for index in range(count):
+       var anchor := position + _port_position(index, count, is_input)
+       if anchor.distance_to(world_position) <= PORT_HIT_RADIUS:
+           return {"port_name": ports[index], "is_input": is_input, "port_index": index}
+   return {}
+
+
 func _resolve_graph_node() -> void:
    var node_data := _find_node_data()
    _node_type = String(node_data.get("type", "missing"))
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 09731f6..77f3fd3 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -669,6 +669,12 @@ func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
    var hit := _hit_at_world(world_position)
    var hit_item: Node = hit.get("item", null)
    if hit_item != null:
+       if String(hit.get("kind", "")) == HitPolicy.KIND_GRAPH_PORT:
+           if additive:
+               _selection.toggle(hit_item.item_id, _items_by_id.keys())
+           else:
+               _select_only([hit_item.item_id])
+           return
        if (
            String(hit.get("kind", "")) == HitPolicy.KIND_BATCH_THUMBNAIL
            and hit_item.toggle_asset_at_world(world_position)
```


## 2026-06-20 M3 G-4 follow-up: graph edge selection/delete

### 本轮实现说明

- 补齐已有 graph 连线的最小删除闭环：点击连线可选中并高亮，按 `Delete` / `Backspace` 删除对应 graph edge。
- 删除操作写回 `graphs/{graph_id}.json` 的 `edges`，并通过 `UndoService` 支持撤销/重做。
- `PFCanvasGraphEdgeRenderer` 复用实际贝塞尔采样点做连线 hit-test，避免渲染和命中使用两套几何规则。
- 新增 `PFCanvasToolTarget`，把 active tool target 解析从 `infinite_canvas.gd` 拆出，让主画布文件保持在 gdlint 行数门槛内。
- 新增单元回归：点击已有连线后按 Delete 删除；Undo 可恢复。

### 验证结果

| 命令 | 结果 |
|---|---|
| `./pixel/scripts/lint.sh` | 通过：`Success: no problems found` |
| `./pixel/scripts/run_tests.sh` | 通过：160/160 tests；仍有既有 GUT orphan 提示 `test_cleanup_batch_performance.gd` 外部 `error_tracker.gd` |
| `./pixel/scripts/verify_m3_ux7.sh` | 通过：`verify_m3_ux7: ok` |

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`，确认默认节点链已有连线。
2. 单击一条已有连线，连线应高亮。
3. 按 `Delete` 或 `Backspace`，该连线应消失。
4. 按 `Ctrl+Z`，连线应恢复；按 `Ctrl+Shift+Z`，连线应再次删除。
5. 再试点击端口、缩略图和拖动节点/批次卡，确认端口命中、批次审阅和整卡拖动没有退化。

### 本轮完整 diff

```diff
diff --git a/pixel/tests/unit/test_canvas_hit_policy.gd b/pixel/tests/unit/test_canvas_hit_policy.gd
index 1630032..be91f24 100644
--- a/pixel/tests/unit/test_canvas_hit_policy.gd
+++ b/pixel/tests/unit/test_canvas_hit_policy.gd
@@ -140,6 +140,32 @@ func test_canvas_drag_between_incompatible_graph_ports_does_not_add_edge() -> vo
     assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [])


+func test_canvas_delete_key_removes_selected_graph_edge() -> void:
+    var canvas: Control = _canvas()
+    var edge := {"from": ["objects", "items"], "to": ["generate", "items"]}
+    _set_graph(
+        "graph_hit",
+        [_graph_node("objects", "object_list"), _graph_node("generate", "ai_generate")],
+        [edge]
+    )
+    var objects: Node = canvas._add_node_direct(
+        _node_item("objects_item", "graph_hit", "objects", Vector2(100, 100))
+    )
+    var generate: Node = canvas._add_node_direct(
+        _node_item("generate_item", "graph_hit", "generate", Vector2(380, 100))
+    )
+    var edge_midpoint: Vector2 = objects.get_graph_port_anchor("items", false).lerp(
+        generate.get_graph_port_anchor("items", true), 0.5
+    )
+
+    canvas._begin_left_interaction(canvas.world_to_screen(edge_midpoint), false)
+    canvas._unhandled_key_input(_delete_key_event())
+
+    assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [])
+    UndoService.undo()
+    assert_eq(ProjectService.get_graph_data("graph_hit").get("edges", []), [edge])
+
+
 func test_canvas_hit_policy_keeps_topmost_item_order() -> void:
     var canvas: Control = _canvas()
     var ids := [_register_asset(Color.RED, "red")]
@@ -182,10 +208,10 @@ func _register_asset(color: Color, name: String) -> String:
     return AssetLibrary.register_image(_image(color), name, {"origin": "imported"})


-func _set_graph(graph_id: String, nodes: Array) -> void:
+func _set_graph(graph_id: String, nodes: Array, edges: Array = []) -> void:
     ProjectService.set_graph_data(
         graph_id,
-        {"graph_version": 1, "id": graph_id, "name": "Hit Policy", "nodes": nodes, "edges": []}
+        {"graph_version": 1, "id": graph_id, "name": "Hit Policy", "nodes": nodes, "edges": edges}
     )


@@ -220,3 +246,10 @@ func _image(color: Color) -> Image:
     var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
     image.fill(color)
     return image
+
+
+func _delete_key_event() -> InputEventKey:
+    var event := InputEventKey.new()
+    event.keycode = KEY_DELETE
+    event.pressed = true
+    return event
diff --git a/pixel/ui/canvas/canvas_graph_edge_interaction.gd b/pixel/ui/canvas/canvas_graph_edge_interaction.gd
index aa2734b..2d801f5 100644
--- a/pixel/ui/canvas/canvas_graph_edge_interaction.gd
+++ b/pixel/ui/canvas/canvas_graph_edge_interaction.gd
@@ -63,6 +63,37 @@ static func try_connect(start: Dictionary, end: Dictionary, changed: Callable) -
     return true


+static func delete_edge(selection: Dictionary, changed: Callable) -> bool:
+    var graph_id := String(selection.get("graph_id", ""))
+    var edge: Dictionary = selection.get("edge", {})
+    if graph_id.is_empty() or edge.is_empty():
+        return false
+    var before := ProjectService.get_graph_data(graph_id)
+    if before.is_empty():
+        return false
+    var after := before.duplicate(true)
+    var edges := []
+    var removed := false
+    for raw_edge in before.get("edges", []):
+        if raw_edge is Dictionary and Dictionary(raw_edge) == edge and not removed:
+            removed = true
+            continue
+        edges.append(raw_edge)
+    if not removed:
+        return false
+    after["edges"] = edges
+    UndoService.perform_action(
+        "Delete graph edge",
+        func() -> void:
+            ProjectService.set_graph_data(graph_id, after)
+            changed.call(),
+        func() -> void:
+            ProjectService.set_graph_data(graph_id, before)
+            changed.call()
+    )
+    return true
+
+
 static func draw_preview(
     canvas: Control, edge_renderer: Script, drag_state: Dictionary, drag_world: Vector2
 ) -> void:
diff --git a/pixel/ui/canvas/canvas_graph_edge_renderer.gd b/pixel/ui/canvas/canvas_graph_edge_renderer.gd
index e24bbf2..c069976 100644
--- a/pixel/ui/canvas/canvas_graph_edge_renderer.gd
+++ b/pixel/ui/canvas/canvas_graph_edge_renderer.gd
@@ -4,13 +4,16 @@ extends RefCounted
 ## Graph 连线渲染 helper。
 ## contract: 02-contracts/GRAPH-SCHEMA.md §1；连线来自 graphs，不写入 canvas.json。

+const EDGE_HIT_DISTANCE := 8.0
+

 static func draw(
     canvas: Control,
     items_by_id: Dictionary,
     batch_script: Script,
     node_script: Script,
-    color: Color
+    color: Color,
+    selected_edge: Dictionary = {}
 ) -> void:
     var graph_items := _graph_items_by_node(items_by_id, batch_script, node_script)
     for graph_id in graph_items.keys():
@@ -18,7 +21,35 @@ static func draw(
         var items_by_node: Dictionary = graph_items[graph_id]
         for edge in graph_data.get("edges", []):
             if edge is Dictionary:
-                _draw_edge_if_visible(canvas, Dictionary(edge), items_by_node, color)
+                var edge_data := Dictionary(edge)
+                var edge_color := color
+                if _edge_matches(String(graph_id), edge_data, selected_edge):
+                    edge_color = Color(0.95, 0.86, 0.32, 1.0)
+                _draw_edge_if_visible(canvas, edge_data, items_by_node, edge_color)
+
+
+static func hit_edge_at_screen(
+    canvas: Control,
+    items_by_id: Dictionary,
+    batch_script: Script,
+    node_script: Script,
+    screen_position: Vector2
+) -> Dictionary:
+    var graph_items := _graph_items_by_node(items_by_id, batch_script, node_script)
+    for graph_id in graph_items.keys():
+        var graph_data := ProjectService.get_graph_data(String(graph_id))
+        var items_by_node: Dictionary = graph_items[graph_id]
+        for edge in graph_data.get("edges", []):
+            if not (edge is Dictionary):
+                continue
+            var edge_data := Dictionary(edge)
+            var points := _edge_points(canvas, edge_data, items_by_node)
+            if (
+                points.size() > 1
+                and _polyline_distance(points, screen_position) <= EDGE_HIT_DISTANCE
+            ):
+                return {"graph_id": String(graph_id), "edge": edge_data}
+    return {}


 static func _draw_edge_if_visible(
@@ -54,6 +85,29 @@ static func _draw_graph_edge(
         return
     var start: Vector2 = canvas.world_to_screen(start_world)
     var end: Vector2 = canvas.world_to_screen(end_world)
+    var points := _bezier_points(start, end)
+    canvas.draw_polyline(points, color, 2.0, true)
+
+
+static func _edge_points(
+    canvas: Control, edge: Dictionary, items_by_node: Dictionary
+) -> PackedVector2Array:
+    var from_data: Array = edge.get("from", ["", ""])
+    var to_data: Array = edge.get("to", ["", ""])
+    var from_node := String(from_data[0])
+    var to_node := String(to_data[0])
+    if not items_by_node.has(from_node) or not items_by_node.has(to_node):
+        return PackedVector2Array()
+    var start_world: Variant = _edge_anchor_world(
+        items_by_node[from_node], String(from_data[1]), false
+    )
+    var end_world: Variant = _edge_anchor_world(items_by_node[to_node], String(to_data[1]), true)
+    if not (start_world is Vector2) or not (end_world is Vector2):
+        return PackedVector2Array()
+    return _bezier_points(canvas.world_to_screen(start_world), canvas.world_to_screen(end_world))
+
+
+static func _bezier_points(start: Vector2, end: Vector2) -> PackedVector2Array:
     var bend := maxf(48.0, absf(end.x - start.x) * 0.35)
     var control_a := start + Vector2(bend, 0.0)
     var control_b := end - Vector2(bend, 0.0)
@@ -61,7 +115,7 @@ static func _draw_graph_edge(
     for index in range(17):
         var t := float(index) / 16.0
         points.append(_cubic_bezier(start, control_a, control_b, end, t))
-    canvas.draw_polyline(points, color, 2.0, true)
+    return points


 static func _edge_anchor_world(item: Node, port_name: String, is_input: bool) -> Variant:
@@ -90,6 +144,29 @@ static func _is_canvas_graph_item(item: Node, batch_script: Script, node_script:
     return item.get_script() == batch_script or item.get_script() == node_script


+static func _polyline_distance(points: PackedVector2Array, position: Vector2) -> float:
+    var distance := INF
+    for index in range(points.size() - 1):
+        distance = minf(distance, _segment_distance(position, points[index], points[index + 1]))
+    return distance
+
+
+static func _segment_distance(position: Vector2, start: Vector2, end: Vector2) -> float:
+    var segment := end - start
+    var length_squared := segment.length_squared()
+    if is_zero_approx(length_squared):
+        return position.distance_to(start)
+    var t := clampf((position - start).dot(segment) / length_squared, 0.0, 1.0)
+    return position.distance_to(start + segment * t)
+
+
+static func _edge_matches(graph_id: String, edge: Dictionary, selected_edge: Dictionary) -> bool:
+    return (
+        graph_id == String(selected_edge.get("graph_id", ""))
+        and edge == selected_edge.get("edge", {})
+    )
+
+
 static func _cubic_bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
     var ab := a.lerp(b, t)
     var bc := b.lerp(c, t)
diff --git a/pixel/ui/canvas/canvas_tool_target.gd b/pixel/ui/canvas/canvas_tool_target.gd
new file mode 100644
index 0000000..091515a
--- /dev/null
+++ b/pixel/ui/canvas/canvas_tool_target.gd
@@ -0,0 +1,26 @@
+class_name PFCanvasToolTarget
+extends RefCounted
+
+## Resolves the active sprite target for canvas tools.
+
+
+static func active_target(
+    items_by_id: Dictionary, selection: Variant, sprite_script: Script
+) -> Dictionary:
+    var selected_ids: Array = selection.get_selected_ids()
+    if selected_ids.size() != 1 or not items_by_id.has(selected_ids[0]):
+        return {}
+    var item: Node = items_by_id[selected_ids[0]]
+    if item.get_script() != sprite_script:
+        return {}
+    var image: Image = item.duplicate_image()
+    if image == null:
+        return {}
+    return {
+        "item_id": item.item_id,
+        "asset_id": item.asset_id,
+        "image": image,
+        "image_size": image.get_size(),
+        "world_position": item.position,
+        "scale_factor": item.scale_factor,
+    }
diff --git a/pixel/ui/canvas/canvas_tool_target.gd.uid b/pixel/ui/canvas/canvas_tool_target.gd.uid
new file mode 100644
index 0000000..4fdbf8a
--- /dev/null
+++ b/pixel/ui/canvas/canvas_tool_target.gd.uid
@@ -0,0 +1 @@
+uid://c8w2q2ocvxkvu
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index be5d8eb..55cee4f 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -36,6 +36,7 @@ const ScalePolicy := preload("res://ui/canvas/canvas_scale_policy.gd")
 const CleanupGridOverlayScript := preload("res://ui/canvas/cleanup_grid_overlay.gd")
 const PixelGridRenderer := preload("res://ui/canvas/canvas_pixel_grid_renderer.gd")
 const ToolInputPolicy := preload("res://ui/canvas/canvas_tool_input_policy.gd")
+const ToolTarget := preload("res://ui/canvas/canvas_tool_target.gd")
 const IdUtil := preload("res://core/util/id_util.gd")
 const ImageMath := preload("res://core/util/image_math.gd")
 const Log := preload("res://core/util/log_util.gd")
@@ -61,6 +62,7 @@ var _suppress_change_signal := false
 var _last_wheel_zoom_msec := -1000000
 var _graph_edge_drag := {}
 var _graph_edge_drag_world := Vector2.ZERO
+var _selected_graph_edge := {}


 func _ready() -> void:
@@ -121,7 +123,12 @@ func _unhandled_key_input(event: InputEvent) -> void:
         return

     if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
-        delete_selected()
+        if not _selected_graph_edge.is_empty():
+            GraphEdgeInteraction.delete_edge(_selected_graph_edge, _emit_canvas_changed)
+            _selected_graph_edge = {}
+            queue_redraw()
+        else:
+            delete_selected()
         get_viewport().set_input_as_handled()
     elif event.keycode == KEY_Z and event.ctrl_pressed:
         if event.shift_pressed:
@@ -139,7 +146,12 @@ func _draw() -> void:
     ):
         PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
     GraphEdgeRenderer.draw(
-        self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, EDGE_COLOR
+        self,
+        _items_by_id,
+        CanvasBatchCardScript,
+        CanvasNodeCardScript,
+        EDGE_COLOR,
+        _selected_graph_edge
     )

     for item_id in _selection.selected_ids:
@@ -477,23 +489,7 @@ func get_selected_sprite_snapshots() -> Array:


 func _get_active_tool_target() -> Dictionary:
-    var selected_ids: Array = _selection.get_selected_ids()
-    if selected_ids.size() != 1 or not _items_by_id.has(selected_ids[0]):
-        return {}
-    var item: Node = _items_by_id[selected_ids[0]]
-    if item.get_script() != CanvasItemSpriteScript:
-        return {}
-    var image: Image = item.duplicate_image()
-    if image == null:
-        return {}
-    return {
-        "item_id": item.item_id,
-        "asset_id": item.asset_id,
-        "image": image,
-        "image_size": image.get_size(),
-        "world_position": item.position,
-        "scale_factor": item.scale_factor,
-    }
+    return ToolTarget.active_target(_items_by_id, _selection, CanvasItemSpriteScript)


 func _get_batch_asset_ids(card_id: String, selected_only: bool = false) -> Array:
@@ -689,7 +685,9 @@ func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
                 _selection.toggle(hit_item.item_id, _items_by_id.keys())
             else:
                 _select_only([hit_item.item_id])
-            _begin_graph_edge_drag(hit, world_position)
+            _graph_edge_drag = GraphEdgeInteraction.begin_drag(hit)
+            _graph_edge_drag_world = world_position
+            queue_redraw()
             return
         if (
             String(hit.get("kind", "")) == HitPolicy.KIND_BATCH_THUMBNAIL
@@ -708,6 +706,14 @@ func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:
                 world_position, SelectionSnapshot.selected_positions(_items_by_id, _selection)
             )
     else:
+        var edge_hit := GraphEdgeRenderer.hit_edge_at_screen(
+            self, _items_by_id, CanvasBatchCardScript, CanvasNodeCardScript, screen_position
+        )
+        if not edge_hit.is_empty():
+            _selection.clear()
+            _selected_graph_edge = edge_hit
+            queue_redraw()
+            return
         if not additive:
             _clear_selection()
         _selection.start_box(screen_position, additive)
@@ -716,7 +722,11 @@ func _begin_left_interaction(screen_position: Vector2, additive: bool) -> void:

 func _finish_left_interaction(screen_position: Vector2) -> void:
     if not _graph_edge_drag.is_empty():
-        _finish_graph_edge_drag(screen_to_world(screen_position))
+        var start := _graph_edge_drag.duplicate(true)
+        _graph_edge_drag = {}
+        var hit := _hit_at_world(screen_to_world(screen_position))
+        if String(hit.get("kind", "")) == HitPolicy.KIND_GRAPH_PORT:
+            GraphEdgeInteraction.try_connect(start, hit, _emit_canvas_changed)
     elif _selection.is_dragging_items:
         _commit_drag_if_needed()
         _selection.stop_drag()
@@ -728,21 +738,6 @@ func _finish_left_interaction(screen_position: Vector2) -> void:
     queue_redraw()


-func _begin_graph_edge_drag(port_hit: Dictionary, world_position: Vector2) -> void:
-    _graph_edge_drag = GraphEdgeInteraction.begin_drag(port_hit)
-    _graph_edge_drag_world = world_position
-    queue_redraw()
-
-
-func _finish_graph_edge_drag(world_position: Vector2) -> void:
-    var start := _graph_edge_drag.duplicate(true)
-    _graph_edge_drag = {}
-    var hit := _hit_at_world(world_position)
-    if String(hit.get("kind", "")) == HitPolicy.KIND_GRAPH_PORT:
-        GraphEdgeInteraction.try_connect(start, hit, _emit_canvas_changed)
-    queue_redraw()
-
-
 func _drag_selected_to(world_position: Vector2) -> void:
     var delta: Vector2 = (world_position - _selection.drag_start_world).round()
     for item_id in _selection.get_selected_ids():
@@ -862,10 +857,12 @@ func _apply_positions(positions: Dictionary) -> void:


 func _select_only(ids: Array) -> void:
+    _selected_graph_edge = {}
     _selection.select_only(ids, _items_by_id.keys())


 func _clear_selection() -> void:
+    _selected_graph_edge = {}
     _selection.clear()


```


## 2026-06-21 M3 UX-7a 端口连线自动吸附

### 本轮实现说明

- 在 `pixelforge-plan/03-milestones/M3-开发规划.md` 追加 UX-7a 小卡，记录端口连线自动吸附的服务对象、痛点、技术选择、验证入口与后续改进空间。
- 在 `PFCanvasGraphEdgeInteraction` 内加入同 graph、反向端口、`PFGraph.can_connect()` 校验驱动的吸附候选扫描；拖线时预览线自动吸到最近兼容端口，松手时按吸附目标创建 edge。
- 将 graph edge 绘制和拖线预览收口到 edge interaction helper，并把 selection overlay 绘制移入 `PFCanvasSelectionSnapshot`，让 `infinite_canvas.gd` 保持在 gdlint 行数软上限内。
- 将兼容端口拖拽测试改成释放在目标端口附近但不精确压中端口，覆盖自动吸附可用闭环；不兼容端口与删除连线测试继续保留。

### 验证结果

- `./pixel/scripts/lint.sh` 通过。
- `./pixel/scripts/run_tests.sh` 通过：160/160 tests passing。
- `./pixel/scripts/verify_m3_ux7.sh` 通过。
- `wc -l pixel/ui/canvas/infinite_canvas.gd` 为 996 行，低于当前 gdlint `max-file-lines` 1000 行门槛。

### 人工测试步骤

1. 启动 PixelForge，执行 `File > Generate Mock Batch`。
2. 可先点击已有连线并按 Delete/Backspace 删除一条连线，便于重新测试。
3. 从 Object List 的 `items` 输出端拖线到 AI Generate 左侧输入点附近，故意不要精确压中圆点，松手后应自动吸附并创建连线。
4. 从 Object List 的 `items` 输出端拖到 Mock Batch 输入端附近，松手后不应创建不兼容连线。
5. 重新执行 `File > Run Selected Graph`，确认可连接的链路仍能生成/刷新 batch。

### 本轮完整 diff

以下为本轮提交前的 `git diff --cached --no-color`；报告内制表符展开为空格，便于 Markdown 记录和 whitespace gate。

```diff
diff --git a/pixel/tests/unit/test_canvas_hit_policy.gd b/pixel/tests/unit/test_canvas_hit_policy.gd
index be91f24..cb1f0b8 100644
--- a/pixel/tests/unit/test_canvas_hit_policy.gd
+++ b/pixel/tests/unit/test_canvas_hit_policy.gd
@@ -112,7 +112,7 @@ func test_canvas_drag_between_compatible_graph_ports_adds_edge() -> void:
         canvas.world_to_screen(objects.get_graph_port_anchor("items", false)), false
     )
     canvas._finish_left_interaction(
-        canvas.world_to_screen(generate.get_graph_port_anchor("items", true))
+        canvas.world_to_screen(generate.get_graph_port_anchor("items", true) + Vector2(28, 0))
     )

     var graph_data := ProjectService.get_graph_data("graph_hit")
diff --git a/pixel/ui/canvas/canvas_graph_edge_interaction.gd b/pixel/ui/canvas/canvas_graph_edge_interaction.gd
index 2d801f5..90a634f 100644
--- a/pixel/ui/canvas/canvas_graph_edge_interaction.gd
+++ b/pixel/ui/canvas/canvas_graph_edge_interaction.gd
@@ -5,6 +5,7 @@ extends RefCounted
 ## contract: 02-contracts/GRAPH-SCHEMA.md §2；连接校验只委托 PFGraph。

 const GraphScript := preload("res://core/graph/pf_graph.gd")
+const SNAP_DISTANCE := 44.0


 static func begin_drag(port_hit: Dictionary) -> Dictionary:
@@ -63,6 +64,82 @@ static func try_connect(start: Dictionary, end: Dictionary, changed: Callable) -
     return true


+static func connect_at_screen(
+    canvas: Control,
+    items_by_id: Dictionary,
+    batch_script: Script,
+    node_script: Script,
+    start: Dictionary,
+    screen_position: Vector2,
+    changed: Callable
+) -> bool:
+    var end := snap_target(canvas, items_by_id, batch_script, node_script, start, screen_position)
+    if end.is_empty():
+        return false
+    return try_connect(start, end, changed)
+
+
+static func update_drag_world(
+    canvas: Control,
+    items_by_id: Dictionary,
+    batch_script: Script,
+    node_script: Script,
+    drag_state: Dictionary,
+    screen_position: Vector2
+) -> Vector2:
+    var snap := snap_target(
+        canvas, items_by_id, batch_script, node_script, drag_state, screen_position
+    )
+    if snap.is_empty():
+        drag_state.erase("snap")
+        return canvas.screen_to_world(screen_position)
+    drag_state["snap"] = snap
+    return snap["anchor"]
+
+
+static func snap_target(
+    canvas: Control,
+    items_by_id: Dictionary,
+    batch_script: Script,
+    node_script: Script,
+    start: Dictionary,
+    screen_position: Vector2
+) -> Dictionary:
+    var graph_id := String(start.get("graph_id", ""))
+    if graph_id.is_empty():
+        return {}
+    var graph_data := ProjectService.get_graph_data(graph_id)
+    if graph_data.is_empty():
+        return {}
+    var graph: PFGraph = GraphScript.from_json(graph_data)
+    var target_is_input := not bool(start.get("is_input", false))
+    var best: Dictionary = {}
+    var best_distance: float = SNAP_DISTANCE + 1.0
+    for raw_item in items_by_id.values():
+        if not _is_graph_item(raw_item, batch_script, node_script):
+            continue
+        var item: Node = raw_item
+        if item.graph_id != graph_id or item.node_id.is_empty():
+            continue
+        for port_name in _port_candidates(graph, item.node_id, target_is_input):
+            var candidate := {
+                "item": item,
+                "item_id": item.item_id,
+                "port_name": String(port_name),
+                "is_input": target_is_input,
+                "port_index": -1,
+            }
+            if _resolve_endpoints(graph, start, candidate, item).is_empty():
+                continue
+            var anchor: Vector2 = item.get_graph_port_anchor(String(port_name), target_is_input)
+            var distance: float = canvas.world_to_screen(anchor).distance_to(screen_position)
+            if distance < best_distance:
+                candidate["anchor"] = anchor
+                best = candidate
+                best_distance = distance
+    return best
+
+
 static func delete_edge(selection: Dictionary, changed: Callable) -> bool:
     var graph_id := String(selection.get("graph_id", ""))
     var edge: Dictionary = selection.get("edge", {})
@@ -111,6 +188,22 @@ static func draw_preview(
     canvas.draw_polyline(points, Color(0.72, 0.9, 0.95, 0.72), 2.0, true)


+static func draw_edges(
+    canvas: Control,
+    edge_renderer: Script,
+    items_by_id: Dictionary,
+    batch_script: Script,
+    node_script: Script,
+    color: Color,
+    selected_edge: Dictionary,
+    drag_state: Dictionary,
+    drag_world: Vector2
+) -> void:
+    edge_renderer.draw(canvas, items_by_id, batch_script, node_script, color, selected_edge)
+    if not drag_state.is_empty():
+        draw_preview(canvas, edge_renderer, drag_state, drag_world)
+
+
 static func _resolve_endpoints(
     graph: PFGraph, start: Dictionary, end: Dictionary, end_item: Node
 ) -> Dictionary:
@@ -168,3 +261,18 @@ static func _input_port_candidates(graph: PFGraph, node_id: String, port_name: S
     for port in node.get_input_ports():
         ports.append(String(port.get("name", "")))
     return ports
+
+
+static func _port_candidates(graph: PFGraph, node_id: String, is_input: bool) -> Array:
+    var node := graph.get_node(node_id)
+    if node == null:
+        return []
+    var specs := node.get_input_ports() if is_input else node.get_output_ports()
+    var ports := []
+    for port in specs:
+        ports.append(String(port.get("name", "")))
+    return ports
+
+
+static func _is_graph_item(item: Variant, batch_script: Script, node_script: Script) -> bool:
+    return item is Node and (item.get_script() == batch_script or item.get_script() == node_script)
diff --git a/pixel/ui/canvas/canvas_selection_snapshot.gd b/pixel/ui/canvas/canvas_selection_snapshot.gd
index 7c884d8..81d8b4f 100644
--- a/pixel/ui/canvas/canvas_selection_snapshot.gd
+++ b/pixel/ui/canvas/canvas_selection_snapshot.gd
@@ -1,7 +1,7 @@
 class_name PFCanvasSelectionSnapshot
 extends RefCounted

-## Small helpers for canvas selection snapshots used by undoable interactions.
+## Small helpers for canvas selection snapshots and overlays.


 static func selected_positions(items_by_id: Dictionary, selection: Variant) -> Dictionary:
@@ -34,3 +34,24 @@ static func ids_from_snapshots(snapshots: Array) -> Array:
     for snapshot in snapshots:
         ids.append(String(snapshot["data"]["id"]))
     return ids
+
+
+static func draw_overlay(
+    canvas: Variant,
+    items_by_id: Dictionary,
+    selection: Variant,
+    selection_color: Color,
+    box_color: Color
+) -> void:
+    for item_id in selection.selected_ids:
+        if not items_by_id.has(item_id):
+            continue
+        var item: Node = items_by_id[item_id]
+        var bounds: Rect2 = item.get_canvas_bounds()
+        var screen_rect: Rect2 = canvas._world_rect_to_screen(bounds)
+        canvas.draw_rect(screen_rect.grow(2.0), selection_color, false, 2.0)
+
+    if selection.is_box_selecting:
+        var box: Rect2 = selection.get_box_rect()
+        canvas.draw_rect(box, box_color, true)
+        canvas.draw_rect(box, Color(1.0, 0.85, 0.25, 1.0), false, 1.0)
diff --git a/pixel/ui/canvas/infinite_canvas.gd b/pixel/ui/canvas/infinite_canvas.gd
index 55cee4f..540a327 100644
--- a/pixel/ui/canvas/infinite_canvas.gd
+++ b/pixel/ui/canvas/infinite_canvas.gd
@@ -145,32 +145,19 @@ func _draw() -> void:
         >= GRID_MIN_ZOOM
     ):
         PixelGridRenderer.draw(self, Color(1.0, 1.0, 1.0, 0.08))
-    GraphEdgeRenderer.draw(
+    GraphEdgeInteraction.draw_edges(
         self,
+        GraphEdgeRenderer,
         _items_by_id,
         CanvasBatchCardScript,
         CanvasNodeCardScript,
         EDGE_COLOR,
-        _selected_graph_edge
+        _selected_graph_edge,
+        _graph_edge_drag,
+        _graph_edge_drag_world
     )

-    for item_id in _selection.selected_ids:
-        if not _items_by_id.has(item_id):
-            continue
-        var item: Node = _items_by_id[item_id]
-        var bounds: Rect2 = item.get_canvas_bounds()
-        var screen_rect := _world_rect_to_screen(bounds)
-        draw_rect(screen_rect.grow(2.0), SELECTION_COLOR, false, 2.0)
-
-    if _selection.is_box_selecting:
-        var box: Rect2 = _selection.get_box_rect()
-        draw_rect(box, BOX_COLOR, true)
-        draw_rect(box, Color(1.0, 0.85, 0.25, 1.0), false, 1.0)
-
-    if not _graph_edge_drag.is_empty():
-        GraphEdgeInteraction.draw_preview(
-            self, GraphEdgeRenderer, _graph_edge_drag, _graph_edge_drag_world
-        )
+    SelectionSnapshot.draw_overlay(self, _items_by_id, _selection, SELECTION_COLOR, BOX_COLOR)

     if tool_manager != null:
         tool_manager.draw_overlay(self, _get_active_tool_target())
@@ -660,7 +647,14 @@ func _handle_wheel_zoom(step_delta: int, screen_anchor: Vector2) -> void:

 func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
     if not _graph_edge_drag.is_empty():
-        _graph_edge_drag_world = screen_to_world(event.position)
+        _graph_edge_drag_world = GraphEdgeInteraction.update_drag_world(
+            self,
+            _items_by_id,
+            CanvasBatchCardScript,
+            CanvasNodeCardScript,
+            _graph_edge_drag,
+            event.position
+        )
         queue_redraw()
         accept_event()
     elif _is_panning:
@@ -724,9 +718,15 @@ func _finish_left_interaction(screen_position: Vector2) -> void:
     if not _graph_edge_drag.is_empty():
         var start := _graph_edge_drag.duplicate(true)
         _graph_edge_drag = {}
-        var hit := _hit_at_world(screen_to_world(screen_position))
-        if String(hit.get("kind", "")) == HitPolicy.KIND_GRAPH_PORT:
-            GraphEdgeInteraction.try_connect(start, hit, _emit_canvas_changed)
+        GraphEdgeInteraction.connect_at_screen(
+            self,
+            _items_by_id,
+            CanvasBatchCardScript,
+            CanvasNodeCardScript,
+            start,
+            screen_position,
+            _emit_canvas_changed
+        )
     elif _selection.is_dragging_items:
         _commit_drag_if_needed()
         _selection.stop_drag()
diff --git "a/pixelforge-plan/03-milestones/M3-\345\274\200\345\217\221\350\247\204\345\210\222.md" "b/pixelforge-plan/03-milestones/M3-\345\274\200\345\217\221\350\247\204\345\210\222.md"
index e904876..e4eeada 100644
--- "a/pixelforge-plan/03-milestones/M3-\345\274\200\345\217\221\350\247\204\345\210\222.md"
+++ "b/pixelforge-plan/03-milestones/M3-\345\274\200\345\217\221\350\247\204\345\210\222.md"
@@ -304,6 +304,26 @@ M3 新增 `M3-UX反馈验收清单.html`，参考 M2.2 验收 HTML 的机制：
 - 增加 hit debug 开关（可后续落地）。
 - 端口命中优先于框选，缩略图点击不误触拖卡。

+### UX-7a 端口连线自动吸附
+
+| 字段 | 内容 |
+|---|---|
+| 服务对象 | 在节点之间频繁连线、但不想精确瞄准小端口的人 |
+| 当前痛点 | 端口点面积小，拖线时每次都要精准对准圆点，鼠标/触控板操作容易漏连 |
+| 技术选择 | Graph edge drag 期间扫描同一 graph 内的兼容反向端口，在阈值内自动吸附到端口锚点；松手时按吸附目标连接 |
+| 选择原因 | 自动吸附比继续放大端口更不破坏视觉密度，也能保留 `PFGraph.can_connect()` 的单点校验 |
+| 优势 | 降低连线瞄准成本，保留类型不兼容时不误连 |
+| 缺陷 | 阈值需要实机反馈；节点密集时可能需要候选高亮或可调参数 |
+| 改进空间 | 候选端口高亮、吸附半径偏好设置、冲突候选切换、连线失败提示 |
+| 验证入口 | 从 Object List 输出拖到 AI Generate 输入附近但不压中端口，松手仍连接；拖到不兼容 batch 输入附近不连接 |
+
+任务：
+
+- 吸附只在同一 graph 的反向端口中查找。
+- 候选必须通过 `PFGraph.can_connect()`，UI 不复制连接规则。
+- 预览线吸附到真实端口锚点，松手可直接创建 edge。
+- 不兼容端口、同向端口、跨 graph 端口不吸附不连接。
+
 ---

 ## 7. 技术骨架卡
```
