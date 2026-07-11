class_name PFPixelEditorCanvas
extends Control

## Nearest-neighbor edit surface with checkerboard, grid, onion skin and drawing tools.

signal document_changed(dirty_rect: Rect2i)
signal color_picked(color: Color)
signal stroke_started

const Drawing := preload("res://core/editor/pixel_drawing.gd")

var document: PFEditDoc = null
var layer_index := 0
var frame_index := 0
var tool := "pencil"
var foreground := Color.WHITE
var background := Color.TRANSPARENT
var brush_size := 1
var pixel_perfect := true
var constrain_palette := true
var mirror_h := false
var mirror_v := false
var onion_skin := true
var global_fill := false
var zoom := 12.0
var selection_rect := Rect2i()
var highlight_points: Array[Vector2i] = []

var _texture: ImageTexture = null
var _onion_before: ImageTexture = null
var _onion_after: ImageTexture = null
var _drawing := false
var _start := Vector2i.ZERO
var _last := Vector2i.ZERO
var _preview_end := Vector2i.ZERO
var _moving_selection := false
var _selection_source: Image = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_document(value: PFEditDoc) -> void:
	document = value
	layer_index = 0
	frame_index = 0
	_refresh_textures()


func set_frame(index: int) -> void:
	if document == null:
		return
	frame_index = clampi(index, 0, document.frame_count() - 1)
	_refresh_textures()


func set_layer(index: int) -> void:
	if document == null:
		return
	layer_index = clampi(index, 0, document.layers.size() - 1)
	_refresh_textures()


func _draw() -> void:
	if document == null:
		return
	var draw_size := Vector2(document.size) * zoom
	var origin := (size - draw_size) * 0.5
	_draw_checker(origin, draw_size)
	if onion_skin:
		if _onion_before != null:
			draw_texture_rect(
				_onion_before, Rect2(origin, draw_size), false, Color(0.3, 0.55, 1.0, 0.3)
			)
		if _onion_after != null:
			draw_texture_rect(
				_onion_after, Rect2(origin, draw_size), false, Color(1.0, 0.3, 0.3, 0.3)
			)
	if _texture != null:
		draw_texture_rect(_texture, Rect2(origin, draw_size), false)
	if zoom >= 8.0:
		for x in range(document.size.x + 1):
			draw_line(
				origin + Vector2(x * zoom, 0),
				origin + Vector2(x * zoom, draw_size.y),
				Color(1, 1, 1, 0.08)
			)
		for y in range(document.size.y + 1):
			draw_line(
				origin + Vector2(0, y * zoom),
				origin + Vector2(draw_size.x, y * zoom),
				Color(1, 1, 1, 0.08)
			)
	if _drawing and tool in ["line", "rectangle", "ellipse"]:
		var a := origin + Vector2(_start) * zoom
		var b := origin + Vector2(_preview_end + Vector2i.ONE) * zoom
		draw_rect(Rect2(a, b - a).abs(), Color(1, 1, 1, 0.7), false, 1.0)
	if selection_rect.has_area():
		draw_rect(
			Rect2(
				origin + Vector2(selection_rect.position) * zoom,
				Vector2(selection_rect.size) * zoom
			),
			Color(0.2, 0.9, 1.0, 0.9),
			false,
			1.0
		)
	for point in highlight_points:
		draw_rect(
			Rect2(origin + Vector2(point) * zoom, Vector2.ONE * zoom),
			Color(1.0, 0.75, 0.1, 0.75),
			false,
			2.0
		)


func _gui_input(event: InputEvent) -> void:
	if document == null:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if (
			button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
			and button.pressed
		):
			zoom = clampf(
				zoom * (1.25 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8), 2.0, 48.0
			)
			queue_redraw()
			accept_event()
		elif button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			var point := _screen_to_pixel(button.position)
			if button.pressed:
				_begin_stroke(point, button.button_index == MOUSE_BUTTON_RIGHT, button.alt_pressed)
			else:
				_finish_stroke(point, button.button_index == MOUSE_BUTTON_RIGHT)
			accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_X:
		var swap := foreground
		foreground = background
		background = swap
		accept_event()
	elif event is InputEventMouseMotion and _drawing:
		var motion: InputEventMouseMotion = event
		var point := _screen_to_pixel(motion.position)
		if tool in ["pencil", "eraser"]:
			_apply_stroke(_last, point, tool == "eraser")
			_last = point
		else:
			_preview_end = point
			queue_redraw()
		accept_event()


func _begin_stroke(point: Vector2i, secondary: bool, pick: bool) -> void:
	if not Rect2i(Vector2i.ZERO, document.size).has_point(point):
		return
	var image := document.get_frame(layer_index, frame_index)
	if image == null or bool(Dictionary(document.layers[layer_index]).get("locked", false)):
		return
	if pick or tool == "picker":
		var picked := image.get_pixelv(point)
		color_picked.emit(_constrained(picked))
		return
	stroke_started.emit()
	_drawing = true
	_start = point
	_last = point
	_preview_end = point
	if tool == "move":
		_moving_selection = selection_rect.has_area() and selection_rect.has_point(point)
		if _moving_selection:
			_selection_source = image.get_region(selection_rect)
	elif tool in ["pencil", "eraser"]:
		_apply_stroke(point, point, tool == "eraser" or secondary)
	elif tool == "fill":
		Drawing.flood_fill(
			image, point, background if secondary else _constrained(foreground), global_fill
		)
		_commit(Rect2i(Vector2i.ZERO, document.size))
		_drawing = false


func _finish_stroke(point: Vector2i, secondary: bool) -> void:
	if not _drawing:
		return
	var image := document.get_frame(layer_index, frame_index)
	var color := background if secondary else _constrained(foreground)
	var rect := Rect2i(
		Vector2i(mini(_start.x, point.x), mini(_start.y, point.y)),
		Vector2i(absi(point.x - _start.x) + 1, absi(point.y - _start.y) + 1)
	)
	match tool:
		"line":
			Drawing.stroke(
				image, _start, point, color, brush_size, false, pixel_perfect, mirror_h, mirror_v
			)
		"rectangle":
			Drawing.rectangle(image, rect, color)
		"ellipse":
			Drawing.ellipse(image, rect, color)
		"move":
			if _moving_selection:
				_move_selection(image, point - _start)
			else:
				selection_rect = rect.intersection(Rect2i(Vector2i.ZERO, document.size))
	if tool in ["line", "rectangle", "ellipse", "move"]:
		_commit(rect)
	_drawing = false
	_moving_selection = false
	queue_redraw()


func _apply_stroke(start: Vector2i, finish: Vector2i, erase: bool) -> void:
	var image := document.get_frame(layer_index, frame_index)
	var color := Color.TRANSPARENT if erase else _constrained(foreground)
	var dirty := Drawing.stroke(
		image, start, finish, color, brush_size, false, pixel_perfect, mirror_h, mirror_v
	)
	_commit(dirty)


func _commit(dirty: Rect2i) -> void:
	document.dirty = true
	var image := document.get_frame(layer_index, frame_index)
	if _texture == null:
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	document_changed.emit(dirty)
	queue_redraw()


func _refresh_textures() -> void:
	var image := document.flatten(frame_index)
	_texture = ImageTexture.create_from_image(image)
	_onion_before = null
	_onion_after = null
	if frame_index > 0:
		_onion_before = ImageTexture.create_from_image(document.flatten(frame_index - 1))
	if frame_index + 1 < document.frame_count():
		_onion_after = ImageTexture.create_from_image(document.flatten(frame_index + 1))
	queue_redraw()


func refresh() -> void:
	_refresh_textures()


func set_highlights(points: Array[Vector2i]) -> void:
	highlight_points = points.duplicate()
	queue_redraw()


func _constrained(color: Color) -> Color:
	return Drawing.nearest_palette_color(color, document.palette) if constrain_palette else color


func _screen_to_pixel(screen_position: Vector2) -> Vector2i:
	var origin := (size - Vector2(document.size) * zoom) * 0.5
	return Vector2i(((screen_position - origin) / zoom).floor())


func _draw_checker(origin: Vector2, draw_size: Vector2) -> void:
	var step := maxf(4.0, zoom)
	for y in range(int(ceil(draw_size.y / step))):
		for x in range(int(ceil(draw_size.x / step))):
			var color := Color(0.22, 0.23, 0.25) if (x + y) % 2 == 0 else Color(0.13, 0.14, 0.16)
			draw_rect(Rect2(origin + Vector2(x, y) * step, Vector2(step, step)), color, true)


func _move_selection(image: Image, delta: Vector2i) -> void:
	if _selection_source == null or delta == Vector2i.ZERO:
		return
	for y in range(selection_rect.position.y, selection_rect.end.y):
		for x in range(selection_rect.position.x, selection_rect.end.x):
			var old_point := Vector2i(x, y)
			if Rect2i(Vector2i.ZERO, document.size).has_point(old_point):
				image.set_pixelv(old_point, Color.TRANSPARENT)
	var destination := selection_rect.position + delta
	for y in range(_selection_source.get_height()):
		for x in range(_selection_source.get_width()):
			var point := destination + Vector2i(x, y)
			if Rect2i(Vector2i.ZERO, document.size).has_point(point):
				image.set_pixelv(point, _selection_source.get_pixel(x, y))
	selection_rect.position = destination
