class_name FirstPersonBody
extends RefCounted
## A local-only lower-body mesh sharing the actual agent's animated skeleton.
## No extra animation clock, movement hull, arms, head or first-person gloves.
const LOCAL_LAYER := 8
const HIDDEN_BODY_LAYER := 16
static var _meshes: Dictionary = {}
var parts: Array[MeshInstance3D] = []
var _alive := false
var _initialized := false

static func lower_bone(name: String) -> bool:
	var lower := name.to_lower()
	return lower == "pelvis" or lower == "spine_0" or lower.begins_with("leg_") or lower.begins_with("ankle_") or lower.begins_with("toe_") or lower.begins_with("ball_") or lower.ends_with(" pelvis") or lower.ends_with(" thigh") or lower.ends_with(" calf") or lower.ends_with(" foot") or "toe0" in lower

static func filtered(source: MeshInstance3D, rig: Skeleton3D) -> ArrayMesh:
	if source.mesh == null or source.skin == null:
		return null
	var key := str(source.mesh.get_instance_id()) + ":" + str(source.skin.get_instance_id())
	if _meshes.has(key):
		return _meshes[key]
	var allowed: Array[bool] = []
	for bind in source.skin.get_bind_count():
		var bone := String(source.skin.get_bind_name(bind))
		if bone.is_empty():
			var index := source.skin.get_bind_bone(bind)
			bone = rig.get_bone_name(index) if index >= 0 and index < rig.get_bone_count() else ""
		allowed.append(lower_bone(bone))
	var result := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones.is_empty() or weights.is_empty():
			continue
		var stride: int = bones.size() / maxi(vertices.size(), 1)
		var keep: Array[bool] = []
		for vertex in vertices.size():
			var lower_weight := 0.0
			for slot in stride:
				var offset := vertex * stride + slot
				if bones[offset] < allowed.size() and allowed[bones[offset]]:
					lower_weight += weights[offset]
			keep.append(lower_weight >= 0.90)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in vertices.size():
				indices.append(index)
		var selected := PackedInt32Array()
		for index in range(0, indices.size() - 2, 3):
			if keep[indices[index]] and keep[indices[index + 1]] and keep[indices[index + 2]]:
				selected.append_array(PackedInt32Array([indices[index], indices[index + 1], indices[index + 2]]))
		if selected.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = selected
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, source.get_active_material(surface))
	_meshes[key] = result
	return result

func install(root: Node3D, rig: Skeleton3D) -> void:
	if root == null or rig == null:
		return
	# Snapshot before adding the local copies. Existing third-person assets stay intact.
	for raw in root.find_children("*", "MeshInstance3D", true, false):
		var source := raw as MeshInstance3D
		var mesh := filtered(source, rig)
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var copy := MeshInstance3D.new()
		copy.name = "LocalLowerBody"
		copy.mesh = mesh
		copy.skin = source.skin
		copy.transform = source.transform
		copy.layers = LOCAL_LAYER
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.set_meta("first_person_lower_body", true)
		source.get_parent().add_child(copy)
		copy.skeleton = copy.get_path_to(rig)
		parts.append(copy)

func sync(root: Node3D, alive: bool) -> void:
	if root == null:
		return
	root.visible = true
	if _initialized and _alive == alive:
		return
	_alive = alive
	_initialized = true
	for part in parts:
		if is_instance_valid(part):
			part.visible = alive
	for raw in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := raw as MeshInstance3D
		if mesh.has_meta("first_person_lower_body"):
			continue
		mesh.layers = HIDDEN_BODY_LAYER if alive else 2
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if alive else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
