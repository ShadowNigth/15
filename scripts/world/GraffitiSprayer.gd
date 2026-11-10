class_name GraffitiSprayer
extends Node
## Small, offline prototype. Mesh overlays work in GL Compatibility (no Decal).
## Reject unsupported edges instead of stretching paint across gaps/corners.
var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/graffiti.json"))
const SIZE := 0.55
const RANGE := 3.0
const COOLDOWN := 3.0
const LIFETIME := 120.0
const MAX_MARKS := 32
const GRID := 8
const SETTINGS := "user://graffiti.cfg"
var selected := 0
var cooldown := 0.0
var marks: Array[MeshInstance3D] = []
var _textures: Array[Texture2D] = []
var _notice: Label
var _icon: TextureRect
var _notice_time := 0.0

func _ready() -> void:
	for item in catalog.items:
		_textures.append(load("res://" + str(item.texture)) as Texture2D)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		for i in catalog.items.size():
			if catalog.items[i].id == cfg.get_value("graffiti", "selected", ""):
				selected = i
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	_icon = TextureRect.new()
	_icon.position = Vector2(24, 170)
	_icon.size = Vector2(96, 72)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_icon)
	_notice = Label.new()
	_notice.position = Vector2(24, 246)
	_notice.add_theme_font_size_override("font_size", 16)
	_notice.add_theme_color_override("font_shadow_color", Color.BLACK)
	_notice.add_theme_constant_override("shadow_outline_size", 4)
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_notice)
	show_notice("V: pintar · J: cambiar grafiti", 6.0)

func _process(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	_notice_time = maxf(0.0, _notice_time - delta)
	_notice.visible = _notice_time > 0.0 and not GameplayInputGate.blocked()
	_icon.visible = _notice.visible

func show_notice(text: String, seconds: float = 2.5) -> void:
	_notice.text = str(catalog.items[selected].name) + "\n" + text
	_icon.texture = _textures[selected]
	_notice_time = seconds

func cycle() -> void:
	selected = (selected + 1) % _textures.size()
	var cfg := ConfigFile.new()
	cfg.set_value("graffiti", "selected", catalog.items[selected].id)
	cfg.save(SETTINGS)
	show_notice("V: pintar · J: cambiar grafiti")

func spray(camera: Camera3D) -> bool:
	if cooldown > 0.0:
		show_notice("Espera %.1f s" % cooldown)
		return false
	var mesh := build_surface(camera)
	if mesh == null:
		show_notice("Apunta a una pared plana y cercana (máximo 3 m)")
		return false
	var mark := MeshInstance3D.new()
	mark.name = "Graffiti"
	mark.mesh = mesh
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_texture = _textures[selected]
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mark.material_override = material
	# World-space vertices; identity transform under the current scene.
	get_tree().current_scene.add_child(mark)
	marks.append(mark)
	while marks.size() > MAX_MARKS:
		var oldest := marks.pop_front() as MeshInstance3D
		if is_instance_valid(oldest):
			oldest.queue_free()
	get_tree().create_timer(LIFETIME).timeout.connect(_expire.bind(mark))
	cooldown = COOLDOWN
	show_notice("Grafiti aplicado · V: pintar · J: cambiar")
	return true

func _expire(mark: MeshInstance3D) -> void:
	marks.erase(mark)
	if is_instance_valid(mark):
		mark.queue_free()

func _exit_tree() -> void:
	for mark in marks:
		if is_instance_valid(mark):
			mark.queue_free()

func build_surface(camera: Camera3D) -> ArrayMesh:
	var space := camera.get_world_3d().direct_space_state
	var origin := camera.global_position
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		origin, origin - camera.global_basis.z * RANGE, 1))
	if hit.is_empty() or not hit.collider is StaticBody3D:
		return null
	var normal: Vector3 = hit.normal
	# First batch: walls only; exclude floors, ceilings and grazing angles.
	if absf(normal.y) > 0.25 or normal.dot(camera.global_basis.z) < 0.35:
		return null
	var right := Vector3.UP.cross(normal).normalized()
	var up := normal.cross(right).normalized()
	var center: Vector3 = hit.position
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for y in GRID + 1:
		for x in GRID + 1:
			var uv := Vector2(float(x) / GRID, float(y) / GRID)
			var p := center + right * (uv.x - 0.5) * SIZE + up * (0.5 - uv.y) * SIZE
			var sample := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p + normal * 0.08, p - normal * 0.08, 1))
			if sample.is_empty() or sample.collider != hit.collider:
				return null
			var sample_normal: Vector3 = sample.normal
			var sample_position: Vector3 = sample.position
			if sample_normal.dot(normal) < 0.995 or absf((sample_position - center).dot(normal)) > 0.012:
				return null
			vertices.append(sample_position + normal * 0.003)
			uvs.append(uv)
			normals.append(normal)
	for y in GRID:
		for x in GRID:
			var a := y * (GRID + 1) + x
			indices.append_array(PackedInt32Array([a, a + 1, a + GRID + 1, a + 1, a + GRID + 2, a + GRID + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
