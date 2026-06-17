class_name PFCanvasPixelGridRenderer
extends RefCounted

## 画布像素网格绘制 helper。
## 输入：PFInfiniteCanvas 的坐标转换方法；输出：当前可视区域内的像素边界线。


static func draw(canvas: Control, color: Color) -> void:
	var top_left: Vector2 = canvas.screen_to_world(Vector2.ZERO)
	var bottom_right: Vector2 = canvas.screen_to_world(canvas.size)
	var start_x := floori(top_left.x)
	var end_x := ceili(bottom_right.x)
	var start_y := floori(top_left.y)
	var end_y := ceili(bottom_right.y)

	for x in range(start_x, end_x + 1):
		var screen_x: float = canvas.world_to_screen(Vector2(float(x), 0.0)).x
		canvas.draw_line(Vector2(screen_x, 0.0), Vector2(screen_x, canvas.size.y), color, 1.0)

	for y in range(start_y, end_y + 1):
		var screen_y: float = canvas.world_to_screen(Vector2(0.0, float(y))).y
		canvas.draw_line(Vector2(0.0, screen_y), Vector2(canvas.size.x, screen_y), color, 1.0)
