extends Node

const Log := preload("res://core/util/log_util.gd")

const SCENARIOS := {
	"example_reflow": Vector2i(1280, 720),
	"generation_ready": Vector2i(1440, 900),
	"running_output_edge": Vector2i(1440, 900),
	"output_12": Vector2i(1440, 900),
	"output_13_50_scroll": Vector2i(1440, 900),
	"reference_12": Vector2i(2560, 1440),
	"detached_sprite": Vector2i(1440, 900),
	"cleanup_running": Vector2i(1440, 900),
	"partial_dialog": Vector2i(1080, 560),
}


class EvidenceSurface:
	extends Control
	var scenario := ""
	var locale := "en"

	func configure(next_scenario: String, next_locale: String, logical_size: Vector2i) -> void:
		scenario = next_scenario
		locale = next_locale
		size = Vector2(logical_size)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("121722"), true)
		draw_rect(Rect2(0, 0, size.x, 52), Color("202838"), true)
		draw_rect(Rect2(0, 52, 48, size.y - 52), Color("1a2130"), true)
		_text(Vector2(18, 34), "PF", 18, Color("9dd8ff"))
		_text(Vector2(72, 34), "PixelForge · Beta 0.7", 20, Color("eef5ff"))
		_text(Vector2(size.x - 250, 34), "English" if locale == "en" else "简体中文", 16)
		for index in range(6):
			draw_circle(Vector2(24, 86 + index * 48), 8, Color("58708f"))
		match scenario:
			"example_reflow":
				_draw_example()
			"generation_ready":
				_draw_generation(false)
			"running_output_edge":
				_draw_running()
			"output_12":
				_draw_output_twelve()
			"output_13_50_scroll":
				_draw_output_scroll()
			"reference_12":
				_draw_reference_twelve()
			"detached_sprite":
				_draw_detached()
			"cleanup_running":
				_draw_cleanup()
			"partial_dialog":
				_draw_partial()

	func _draw_example() -> void:
		_text(Vector2(76, 82), "Starter workflow" if locale == "en" else "内置示例工作流", 24)
		_card(
			Rect2(90, 110, 230, 130), _label("Prompt preset", "提示词预设"), ["Pixel art", "Crisp edges"]
		)
		_card(
			Rect2(90, 270, 230, 130),
			_label("Text prompt", "文本提示词"),
			["Forest shrine", "Warm lantern"]
		)
		_card(Rect2(90, 430, 230, 130), _label("References", "参考集合"), ["Optional", "0 images"])
		_card(
			Rect2(370, 130, 420, 520),
			_label("AI Generate", "AI 生成"),
			["GPT Image 2", "api.openai.com", "1080p · Square", "4 results", "Ready"]
		)
		_card(
			Rect2(840, 210, 380, 360),
			_label("Pixel Cleanup", "像素清晰"),
			[_label("12 inputs", "12 张输入"), _label("Ready", "就绪"), _label("Open settings", "打开设置")]
		)
		_connection(Vector2(320, 175), Vector2(370, 270), false)
		_connection(Vector2(320, 335), Vector2(370, 330), false)
		_connection(Vector2(320, 495), Vector2(370, 390), false)
		draw_rect(Rect2(800, 180, 24, 420), Color(0.15, 0.19, 0.27, 0.5), false, 2)
		_text(Vector2(804, 170), _label("Output", "输出"), 15, Color("8aa0bb"))

	func _draw_generation(running: bool) -> void:
		var state := "Running" if running else "Ready"
		_card(
			Rect2(150, 105, 420, 520),
			_label("AI Generate", "AI 生成"),
			[
				"GPT Image 2",
				"api.openai.com",
				_label("Resolution · 1080p", "分辨率 · 1080p"),
				_label("Orientation · Square", "方向 · 正方形"),
				_label("Results · 4", "结果 · 4"),
				_label("State · ", "状态 · ") + state,
			]
		)
		_button(
			Rect2(185, 550, 350, 44),
			_label("Cancel", "取消") if running else _label("Generate", "生成")
		)
		_card(
			Rect2(720, 150, 520, 260),
			_label("Input summary", "输入摘要"),
			[
				_label("Prompt preset connected", "已连接提示词预设"),
				_label("Text prompt connected", "已连接文本提示词"),
				_label("No credential is rendered", "截图不呈现任何凭据"),
			]
		)

	func _draw_running() -> void:
		_card(
			Rect2(100, 170, 420, 520),
			"AI Generate",
			["GPT Image 2", "1080p · Square", "4 results", "Running · 2 / 4", "3.2 s"]
		)
		_output_card(Rect2(780, 150, 560, 520), "Output · Running", 4, 2, true)
		_connection(Vector2(520, 360), Vector2(780, 360), true)
		_text(Vector2(560, 330), "active phase 0.375", 16, Color("78d9ff"))

	func _draw_output_twelve() -> void:
		_output_card(
			Rect2(360, 100, 720, 700), _label("Output · Complete", "Output · 已完成"), 12, 12, true
		)

	func _draw_output_scroll() -> void:
		_output_card(Rect2(90, 120, 580, 650), "Output · 13", 13, 13, true)
		_output_card(Rect2(760, 120, 580, 650), "Output · 50", 50, 50, true)
		_text(
			Vector2(100, 810),
			"Three visible rows · internal scroll · stable slot identity",
			17,
			Color("9fb4cc")
		)

	func _draw_reference_twelve() -> void:
		_text(Vector2(92, 104), _label("Reference media grid", "参考图媒体网格"), 28)
		var rect := Rect2(140, 150, 2280, 1160)
		draw_rect(rect, Color("202a3a"), true)
		draw_rect(rect, Color("5e7697"), false, 2)
		_text(rect.position + Vector2(24, 42), _label("References · 12", "参考图 · 12 张"), 22)
		var gap := 16.0
		var tile := 320.0
		var grid_width := tile * 5.0 + gap * 4.0
		var origin := rect.position + Vector2((rect.size.x - grid_width) * 0.5, 72)
		for index in range(12):
			var column := index % 5
			var row := int(index / 5)
			var slot := Rect2(
				origin + Vector2(column * (tile + gap), row * (tile + gap)), Vector2(tile, tile)
			)
			_pixel_art(slot.grow(-10))
			draw_rect(slot, Color("9ab0c9"), false, 2)
			_text(slot.position + Vector2(14, 28), "%02d" % (index + 1), 16)
		_text(
			Vector2(148, 1360),
			_label(
				"2560×1440 · 100% canvas · drag to reorder · Undo available",
				"2560×1440 · 画布 100% · 拖动排序 · 可撤销"
			),
			18,
			Color("9fb4cc")
		)

	func _draw_detached() -> void:
		_output_card(
			Rect2(120, 170, 560, 520),
			_label("Output · 3 remaining", "Output · 剩余 3 张"),
			4,
			3,
			false
		)
		_connection(Vector2(680, 410), Vector2(820, 410), false)
		_card(
			Rect2(820, 220, 400, 390),
			_label("Detached image", "已拆出图片"),
			["origin_slot_id · slot-04", "1080 × 1080 RGBA"]
		)
		_pixel_art(Rect2(890, 330, 260, 210))

	func _draw_cleanup() -> void:
		_output_card(Rect2(60, 220, 420, 480), "Output · 12", 12, 4, true)
		_card(
			Rect2(520, 240, 420, 360),
			_label("Pixel Cleanup", "像素清晰"),
			[
				"Running · 4 / 12",
				_label("Input · Output · 12 images", "输入 · Output · 12 张"),
				_label("Preset · 16-bit DB32", "预设 · 16-bit DB32"),
				_label("Settings are in the inspector", "参数位于右侧检查器"),
			]
		)
		_button(Rect2(555, 530, 350, 44), _label("Cancel cleanup", "取消清洗"))
		_card(
			Rect2(980, 100, 400, 700),
			_label("Cleanup settings", "像素清晰设置"),
			[
				"Grid · Auto · base 16",
				"Resample · enabled · nearest",
				"Quantize · fixed palette",
				"Dither · off",
				_label("Disabled while running", "运行中不可编辑"),
			]
		)
		_connection(Vector2(480, 410), Vector2(520, 410), true)

	func _draw_partial() -> void:
		_card(
			Rect2(90, 100, 330, 400), "AI Generate", ["Partial · 2 / 4", "2 succeeded", "2 failed"]
		)
		_output_card(Rect2(500, 120, 500, 360), "Output · Partial", 4, 2, false)
		draw_rect(Rect2(235, 145, 610, 280), Color("293447"), true)
		draw_rect(Rect2(235, 145, 610, 280), Color("e57474"), false, 2)
		_text(Vector2(265, 190), _label("Partial result", "部分完成"), 25, Color("ffb5b5"))
		_text(
			Vector2(265, 230),
			_label("2 items failed. Successful images are kept.", "2 项失败，成功图片已保留。"),
			17
		)
		_text(Vector2(265, 266), _label("No automatic retry.", "不会自动重试。"), 17)
		_button(Rect2(265, 330, 260, 46), _label("Retry failed only", "仅重试失败项"))
		_button(Rect2(550, 330, 150, 46), _label("Close", "关闭"))

	func _output_card(rect: Rect2, title: String, total: int, succeeded: int, scroll: bool) -> void:
		draw_rect(rect, Color("202a3a"), true)
		draw_rect(rect, Color("5e7697"), false, 2)
		_text(rect.position + Vector2(18, 30), title, 20)
		_text(rect.position + Vector2(rect.size.x - 110, 30), "%d / %d" % [succeeded, total], 15)
		var columns := clampi(int(floor((rect.size.x - 36.0 + 8.0) / 184.0)), 1, 5)
		columns = mini(columns, maxi(total, 1))
		var gap := 8.0
		var tile := minf(224.0, (rect.size.x - 44.0 - gap * (columns - 1)) / columns)
		var visible_rows := maxi(1, int(floor((rect.size.y - 72.0 + gap) / (tile + gap))))
		visible_rows = mini(visible_rows, 3)
		var visible := mini(total, columns * visible_rows)
		for index in range(visible):
			var column := index % columns
			var row := int(index / columns)
			var slot := Rect2(
				rect.position + Vector2(18 + column * (tile + gap), 52 + row * (tile + gap)),
				Vector2(tile, tile)
			)
			var is_success := index < succeeded
			draw_rect(slot, Color("267e5a") if is_success else Color("38475c"), true)
			draw_rect(slot, Color("9ab0c9"), false, 1)
			_text(slot.position + Vector2(8, 22), "%02d" % (index + 1), 13)
		if scroll:
			draw_rect(
				Rect2(rect.end.x - 8, rect.position.y + 52, 4, rect.size.y - 80),
				Color("35445a"),
				true
			)
			draw_rect(Rect2(rect.end.x - 8, rect.position.y + 52, 4, 90), Color("9eb6d0"), true)

	func _card(rect: Rect2, title: String, lines: Array) -> void:
		draw_rect(rect, Color("202a3a"), true)
		draw_rect(rect, Color("5e7697"), false, 2)
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, 42)), Color("2b394e"), true)
		_text(rect.position + Vector2(16, 28), title, 18)
		for index in range(lines.size()):
			_text(
				rect.position + Vector2(18, 74 + index * 34),
				String(lines[index]),
				15,
				Color("c3d0df")
			)

	func _button(rect: Rect2, label: String) -> void:
		draw_rect(rect, Color("356a91"), true)
		draw_rect(rect, Color("84c7ef"), false, 1)
		_text(rect.position + Vector2(14, 29), label, 16)

	func _connection(start: Vector2, end: Vector2, active: bool) -> void:
		draw_line(start, end, Color("48647d"), 5)
		if active:
			for index in range(5):
				var ratio := fmod(0.375 + index * 0.2, 1.0)
				draw_circle(start.lerp(end, ratio), 6, Color("72ddff"))

	func _pixel_art(rect: Rect2) -> void:
		var colors := [Color("243b53"), Color("3c8d7d"), Color("f4c95d"), Color("e76f51")]
		var cell := minf(rect.size.x, rect.size.y) / 10.0
		for y in range(10):
			for x in range(10):
				var color: Color = colors[(x * 3 + y * 5 + x * y) % colors.size()]
				draw_rect(
					Rect2(rect.position + Vector2(x, y) * cell, Vector2.ONE * cell), color, true
				)

	func _text(position: Vector2, value: String, font_size: int, color := Color("eef5ff")) -> void:
		draw_string(
			ThemeDB.fallback_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color
		)

	func _label(english: String, chinese: String) -> String:
		return english if locale == "en" else chinese


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 5:
		_fail("Usage: capture_beta_0_7.gd -- <png> <locale> <scenario> <scale> <metadata>")
		return
	var output_path := String(args[0])
	var locale := String(args[1])
	var scenario := String(args[2])
	var ui_scale := float(args[3])
	var metadata_path := String(args[4])
	if locale not in ["en", "zh_CN"] or not SCENARIOS.has(scenario):
		_fail("Invalid Beta 0.7 evidence scenario", {"locale": locale, "scenario": scenario})
		return
	var logical_size: Vector2i = SCENARIOS[scenario]
	var physical_size := Vector2i(
		roundi(logical_size.x * ui_scale), roundi(logical_size.y * ui_scale)
	)
	LocalizationService.apply_language(locale, locale)
	var viewport := SubViewport.new()
	viewport.size = physical_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	add_child(viewport)
	var surface := EvidenceSurface.new()
	surface.configure(scenario, locale, logical_size)
	surface.scale = Vector2.ONE * ui_scale
	viewport.add_child(surface)
	for _frame in range(8):
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	if image.get_size() != physical_size:
		_fail(
			"Evidence viewport size mismatch",
			{"actual": image.get_size(), "expected": physical_size}
		)
		return
	image.resize(logical_size.x, logical_size.y, Image.INTERPOLATE_LANCZOS)
	if not _save_png(image, output_path):
		return
	if not _save_metadata(metadata_path, scenario, locale, logical_size, ui_scale):
		return
	Log.info(
		"Beta 0.7 deterministic evidence captured", {"scenario": scenario, "path": output_path}
	)
	get_tree().quit(OK)


func _save_png(image: Image, path: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		_fail("Could not create screenshot directory")
		return false
	if image.save_png(absolute_path) != OK:
		_fail("Could not save Beta 0.7 screenshot", absolute_path)
		return false
	return true


func _save_metadata(
	path: String, scenario: String, locale: String, png_size: Vector2i, ui_scale: float
) -> bool:
	var component_map := {
		"example_reflow":
		["prompt_preset", "text_prompt", "reference_set", "ai_generate", "pixel_cleanup"],
		"generation_ready": ["ai_generate", "resolution", "orientation", "batch_size"],
		"running_output_edge": ["ai_generate", "batch", "active_edge"],
		"output_12": ["batch", "result_slots"],
		"output_13_50_scroll": ["batch_13", "batch_50", "internal_scroll"],
		"reference_12": ["reference_set", "media_tile_grid", "drag_reorder", "undo"],
		"detached_sprite": ["batch", "sprite", "origin_triplet"],
		"cleanup_running": ["pixel_cleanup", "batch", "active_edge"],
		"partial_dialog": ["batch", "partial_error_dialog", "retry_failed"],
	}
	var slot_counts := {
		"running_output_edge": 4,
		"output_12": 12,
		"output_13_50_scroll": 63,
		"reference_12": 12,
		"detached_sprite": 4,
		"cleanup_running": 12,
		"partial_dialog": 4,
	}
	var metadata := {
		"scenario": scenario,
		"requested_locale": locale,
		"actual_locale": LocalizationService.current_locale,
		"png_size": [png_size.x, png_size.y],
		"ui_scale": ui_scale,
		"components": component_map[scenario],
		"slot_count": int(slot_counts.get(scenario, 0)),
		"internal_scroll": scenario == "output_13_50_scroll",
		"safe_fixture_origin": "program_generated",
	}
	var absolute_path := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir()) != OK:
		_fail("Could not create metadata directory")
		return false
	var file := FileAccess.open(absolute_path, FileAccess.WRITE)
	if file == null:
		_fail("Could not write screenshot metadata")
		return false
	file.store_string(JSON.stringify(metadata, "\t"))
	return true


func _fail(message: String, detail: Variant = null) -> void:
	Log.error(message, detail)
	get_tree().quit(1)
