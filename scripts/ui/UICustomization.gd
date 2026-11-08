extends Node
## Local visual preferences only. Editing is transactional; only Save writes to disk.
signal changed
const PATH := "user://ui_customization.cfg"
const CROSSHAIR_DEFAULTS := {"length": 8.0, "gap": 5.0, "width": 1.8, "outline": 0.7, "dot": false, "t_shape": false, "enabled": true}
var crosshair: Dictionary = CROSSHAIR_DEFAULTS.duplicate(true)
var hud: Dictionary = {}

func _ready() -> void:
	load_preferences()

func snapshot() -> Dictionary:
	return {"crosshair": crosshair.duplicate(true), "hud": hud.duplicate(true), "color": GameData.crosshair_color, "dynamic": GameData.dynamic_crosshair}

func restore(data: Dictionary) -> void:
	crosshair = CROSSHAIR_DEFAULTS.duplicate(true)
	var incoming: Variant = data.get("crosshair", {})
	if incoming is Dictionary:
		for key in crosshair:
			var value: Variant = incoming.get(key, crosshair[key])
			if typeof(value) == typeof(crosshair[key]) or (value is int and crosshair[key] is float):
				crosshair[key] = value
	for key in ["length", "gap", "width", "outline"]:
		var limits: Dictionary = {"length": Vector2(1, 30), "gap": Vector2(0, 30), "width": Vector2(1, 8), "outline": Vector2(0, 4)}
		crosshair[key] = clampf(float(crosshair[key]), limits[key].x, limits[key].y) if is_finite(float(crosshair[key])) else CROSSHAIR_DEFAULTS[key]
	hud.clear()
	var layouts: Variant = data.get("hud", {})
	if layouts is Dictionary:
		for key in layouts:
			var item: Variant = layouts[key]
			if not item is Dictionary:
				continue
			var pos: Variant = item.get("position", Vector2(0.5, 0.5))
			if not pos is Vector2 or not pos.is_finite():
				pos = Vector2(0.5, 0.5)
			var scale_value: Variant = item.get("scale", 1.0)
			var alpha: Variant = item.get("opacity", 1.0)
			if not (scale_value is float or scale_value is int) or not (alpha is float or alpha is int):
				continue
			hud[str(key)] = {"position": pos.clamp(Vector2.ZERO, Vector2.ONE), "scale": clampf(scale_value, 0.5, 2.5) if is_finite(scale_value) else 1.0, "opacity": clampf(alpha, 0.2, 1.0) if is_finite(alpha) else 1.0, "visible": bool(item.get("visible", true))}
	var color: Variant = data.get("color", GameData.crosshair_color)
	if color is Color and Vector4(color.r, color.g, color.b, color.a).is_finite():
		GameData.crosshair_color = color.clamp()
	GameData.dynamic_crosshair = bool(data.get("dynamic", true))
	changed.emit()

func load_preferences(path: String = PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		var data: Variant = config.get_value("ui", "preferences", {})
		if data is Dictionary:
			restore(data)

func save_preferences(path: String = PATH) -> Error:
	var config := ConfigFile.new()
	config.set_value("ui", "preferences", snapshot())
	return config.save(path)

func reset_crosshair() -> void:
	crosshair = CROSSHAIR_DEFAULTS.duplicate(true)
	GameData.crosshair_color = Color(0.2, 1, 0.2, 0.92)
	GameData.dynamic_crosshair = true
	changed.emit()
