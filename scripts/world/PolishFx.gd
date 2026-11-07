class_name PolishFx
extends Node3D
## Actual upstream sprite sheets, advanced by elapsed time, compatibility renderer.
var elapsed := 0.0
var duration := 0.5
var count := 16
var opacity := 1.0
var start_size := 1.0
var end_size := 2.0
var sprite: Sprite3D

static func emit(parent: Node, point: Vector3, sheet: String, grid: Vector2i, frames: int, seconds: float, size_from: float, size_to: float, layer: int = 2, tint: Color = Color.WHITE) -> PolishFx:
	if not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	# Bound transient particles, not resource loading or caches.
	if parent.get_tree().get_nodes_in_group("polish_transient_fx").size() >= 96:
		return null
	var texture := GameData.get_texture("res://assets/polish/" + sheet + ".png")
	if texture == null:
		return null
	var effect := PolishFx.new()
	effect.opacity = tint.a
	effect.duration = seconds
	effect.count = frames
	effect.start_size = size_from
	effect.end_size = size_to
	effect.sprite = Sprite3D.new()
	effect.sprite.texture = texture
	effect.sprite.hframes = grid.x
	effect.sprite.vframes = grid.y
	effect.sprite.pixel_size = 1.0 / (float(texture.get_width()) / grid.x)
	effect.sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	effect.sprite.shaded = false
	effect.sprite.layers = layer
	effect.sprite.modulate = tint
	effect.add_child(effect.sprite)
	parent.add_child(effect)
	effect.position = point
	effect.add_to_group("polish_transient_fx")
	effect.sprite.scale = Vector3.ONE * size_from
	return effect

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	var progress := clampf(elapsed / maxf(0.001, duration), 0.0, 1.0)
	sprite.frame = mini(count - 1, int(progress * count))
	sprite.scale = Vector3.ONE * lerpf(start_size, end_size, progress)
	sprite.modulate.a = opacity * (1.0 - smoothstep(0.45, 1.0, progress))
	position.y += delta * 0.18
