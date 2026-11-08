class_name CrosshairPainter
extends RefCounted
## Shared geometry for gameplay and editor. Does not alter aim, recoil or scope.
static func paint(canvas: Control, center: Vector2, gap: float) -> void:
	var prefs: Dictionary = UICustomization.crosshair
	if not prefs.enabled:
		return
	var length_value: float = prefs.length
	var width: float = prefs.width
	var outline: float = prefs.outline
	var color: Color = GameData.crosshair_color
	var directions: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]
	if not prefs.t_shape:
		directions.append(Vector2.UP)
	for direction in directions:
		var start := center + direction * gap
		var end := center + direction * (gap + length_value)
		if outline > 0:
			canvas.draw_line(start, end, Color(0, 0, 0, color.a * 0.55), width + outline * 2)
		canvas.draw_line(start, end, color, width)
	if prefs.dot:
		if outline > 0:
			canvas.draw_circle(center, width * 0.5 + outline, Color(0, 0, 0, color.a))
		canvas.draw_circle(center, width * 0.5, color)
