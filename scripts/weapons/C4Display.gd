class_name C4Display
extends MeshInstance3D
## Missing native LCD part; original atlas rows, carried by the animated C4 bone.
var row := -1
var _digits: Array = []
var _native_duration := 4.0
var _screen_material: ShaderMaterial

static func install(root: Node3D) -> C4Display:
	var rig := SportGloves._find_skeleton(root)
	if rig == null:
		return null
	var source: MeshInstance3D
	for mesh in SportGloves._find_meshes(root):
		if mesh.skin and not mesh.has_meta("native_view_cosmetic"):
			source = mesh
			break
	if source == null:
		return null
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/c4_display.json"))
	var display := C4Display.new()
	display.name = "NativeC4Digits"
	display.layers = 4
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	display._digits = data.digits
	display._native_duration = float(GameData.models_meta.get("weapons/v_c4", {}).get("seq_durations", {}).get("pressbutton", 4.0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for index in data.positions.size():
		var p: Array = data.positions[index]
		var n: Array = data.normals[index]
		var t: Array = data.uv[index]
		vertices.append(Vector3(p[0], p[1], p[2]))
		normals.append(Vector3(n[0], n[1], n[2]))
		uv.append(Vector2(t[0], t[1]))
		bones.append_array(PackedInt32Array([0, 0, 0, 0]))
		weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array(data.indices)
	var screen := ArrayMesh.new()
	screen.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	display.mesh = screen
	var bone := rig.find_bone("weapon_hand_r")
	if bone < 0:
		display.free()
		return null
	display.skin = Skin.new()
	var found := false
	for index in source.skin.get_bind_count():
		if String(source.skin.get_bind_name(index)) == "weapon_hand_r" or source.skin.get_bind_bone(index) == bone:
			display.skin.add_bind(bone, source.skin.get_bind_pose(index))
			found = true
			break
	if not found:
		display.free()
		return null
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled; uniform sampler2D digits_texture : source_color, filter_linear; uniform float digit_row = 0.0; void fragment(){ vec3 c = texture(digits_texture, UV + vec2(0.0, digit_row / 16.0)).rgb; ALBEDO = c; }"
	display._screen_material = ShaderMaterial.new()
	display._screen_material.shader = shader
	display._screen_material.set_shader_parameter("digits_texture", load(String(data.texture)))
	display.material_override = display._screen_material
	root.add_child(display)
	display.global_transform = source.global_transform
	display.skeleton = display.get_path_to(rig)
	display.set_progress(0.0)
	return display

func set_progress(seconds: float) -> void:
	var sample := clampf(seconds / 3.0, 0, 1) * _native_duration
	var next := 0
	for entry in _digits:
		if float(entry.At) <= sample:
			next = int(entry.Row)
	if next != row:
		row = next
		_screen_material.set_shader_parameter("digit_row", float(row))
