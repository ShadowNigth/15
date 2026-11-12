class_name FirstPersonBody
extends RefCounted
## Local continuous abdomen/legs copying the actual agent's exact skeletal pose.
## No extra animation clock, movement hull, arms, head or first-person gloves.
const LOCAL_LAYER := 8
const HIDDEN_BODY_LAYER := 16
static var _meshes: Dictionary = {}
var parts: Array[MeshInstance3D] = []
var sources: Array[MeshInstance3D] = []
var source_rig: Skeleton3D = null
var local_rig: Skeleton3D = null
const CAMERA_BODY_OFFSET := 0.38
var _alive := false
var _initialized := false

static func lower_bone(name: String) -> bool:
	var lower := name.to_lower()
	return lower == "pelvis" or lower.begins_with("spine_") or lower.begins_with("clavicle_") or lower.ends_with(" spine") or " spine1" in lower or " spine2" in lower or lower.begins_with("leg_") or lower.begins_with("ankle_") or lower.begins_with("toe_") or lower.begins_with("ball_") or lower.ends_with(" pelvis") or lower.ends_with(" thigh") or lower.ends_with(" calf") or lower.ends_with(" foot") or "toe0" in lower

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
		# Keep original lower-abdomen/pelvis geometry; never fabricate a waist disk.
		# A fan using averaged trouser UVs created the black concentric disk.
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, source.get_active_material(surface))
	_meshes[key] = result
	return result

static func cap_waist(arrays: Array, stride: int) -> Array:
	# Skin-weight filtering opens the waist. Weld UV seam duplicates only for
	# boundary discovery, then close upper boundary loops with a skinned fan.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var canonical: Dictionary = {}
	var representatives: Dictionary = {}
	var extent := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices:
		extent = extent.expand(vertex)
	var tolerance := maxf(extent.size.length() * 0.00001, 0.000001)
	for index in vertices.size():
		var key := vertices[index].snapped(Vector3.ONE * tolerance)
		if not representatives.has(key):
			representatives[key] = index
		canonical[index] = representatives[key]
	var edges: Dictionary = {}
	for index in range(0, indices.size(), 3):
		for slot in 3:
			var a: int = canonical[indices[index + slot]]
			var b: int = canonical[indices[index + (slot + 1) % 3]]
			var key := Vector2i(mini(a, b), maxi(a, b))
			edges[key] = int(edges.get(key, 0)) + 1
	var neighbors: Dictionary = {}
	for edge in edges:
		if edges[edge] != 1:
			continue
		if not neighbors.has(edge.x): neighbors[edge.x] = []
		if not neighbors.has(edge.y): neighbors[edge.y] = []
		neighbors[edge.x].append(edge.y)
		neighbors[edge.y].append(edge.x)
	var seen: Dictionary = {}
	for start in neighbors:
		if seen.has(start): continue
		var loop: Array[int] = []
		var current: int = start
		var previous := -1
		while not seen.has(current) and neighbors[current].size() == 2:
			seen[current] = true
			loop.append(current)
			var next: int = neighbors[current][0] if neighbors[current][0] != previous else neighbors[current][1]
			previous = current
			current = next
		if current != start or loop.size() < 6: continue
		var center := Vector3.ZERO
		for index in loop: center += vertices[index]
		center /= float(loop.size())
		if center.y < extent.position.y + extent.size.y * 0.45: continue
		var center_index: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var influence: Dictionary = {}
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in loop:
			for slot in stride:
				var bind := bones[index * stride + slot]
				influence[bind] = float(influence.get(bind, 0.0)) + weights[index * stride + slot]
		var ranked := influence.keys()
		ranked.sort_custom(func(a, b): return influence[a] > influence[b])
		var total := 0.0
		for slot in mini(stride, ranked.size()): total += influence[ranked[slot]]
		for slot in stride:
			bones.append(ranked[slot] if slot < ranked.size() else 0)
			weights.append(float(influence[ranked[slot]]) / maxf(total, 0.000001) if slot < ranked.size() else 0.0)
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
			var values = arrays[channel]
			if values == null or values.is_empty(): continue
			var average = values[loop[0]] * 0.0
			for index in loop: average += values[index]
			average /= float(loop.size())
			values.append(Vector3.UP if channel == Mesh.ARRAY_NORMAL else average)
			arrays[channel] = values
		var tangents = arrays[Mesh.ARRAY_TANGENT]
		if tangents != null and not tangents.is_empty():
			tangents.append_array(PackedFloat32Array([1, 0, 0, 1]))
			arrays[Mesh.ARRAY_TANGENT] = tangents
		for index in loop.size():
			var a := loop[index]
			var b := loop[(index + 1) % loop.size()]
			# Godot ArrayMesh front faces are clockwise, unlike glTF source faces.
			if (vertices[a] - center).cross(vertices[b] - center).y > 0:
				indices.append_array(PackedInt32Array([center_index, b, a]))
			else:
				indices.append_array(PackedInt32Array([center_index, a, b]))
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func install(root: Node3D, rig: Skeleton3D) -> void:
	if root == null or rig == null:
		return
	source_rig = rig
	local_rig = Skeleton3D.new()
	local_rig.name = "LocalLowerBodyPose"
	root.add_child(local_rig)
	for index in rig.get_bone_count():
		local_rig.add_bone(rig.get_bone_name(index))
		local_rig.set_bone_parent(index, rig.get_bone_parent(index))
		local_rig.set_bone_rest(index, rig.get_bone_rest(index))
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
		copy.skeleton = copy.get_path_to(local_rig)
		parts.append(copy)
		sources.append(source)

func sync(root: Node3D, alive: bool, view_yaw: float = 0.0) -> void:
	if root == null:
		return
	root.visible = true
	if alive:
		update_pose(root, view_yaw)
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

func update_pose(root: Node3D, view_yaw: float = 0.0) -> void:
	if not is_instance_valid(source_rig) or not is_instance_valid(local_rig):
		return
	# The camera is ahead of the chest. Keep the local waist behind it rather
	# than looking straight into the top of the trousers. No physics/hitbox shift.
	var offset := Basis(Vector3.UP, view_yaw).z * CAMERA_BODY_OFFSET
	local_rig.global_transform = source_rig.global_transform
	local_rig.global_position += offset
	for index in source_rig.get_bone_count():
		local_rig.set_bone_pose_position(index, source_rig.get_bone_pose_position(index))
		local_rig.set_bone_pose_rotation(index, source_rig.get_bone_pose_rotation(index))
		local_rig.set_bone_pose_scale(index, source_rig.get_bone_pose_scale(index))
	for index in parts.size():
		if is_instance_valid(parts[index]) and is_instance_valid(sources[index]):
			parts[index].global_transform = sources[index].global_transform
			parts[index].global_position += offset
