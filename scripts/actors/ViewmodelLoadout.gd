class_name ViewmodelLoadout
extends RefCounted
## Installs selectable PBR arms on the animated skeleton already inside each v_*.
## Every source mesh is first baked into the TARGET rig's rest space. The result
## uses native rigid target-rest Skin binds instead of scaled Source inverse binds.
## Converted meshes are cached per weapon model and loadout asset.

static var _filtered_meshes: Dictionary = {}
static var _baked_sources: Dictionary = {}


static func apply(root: Node3D, team: String, rig_key: String = "") -> bool:
	if root == null:
		return false
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		return false
	var cache_namespace := rig_key
	if cache_namespace.is_empty():
		cache_namespace = String(root.scene_file_path)
	if cache_namespace.is_empty():
		cache_namespace = "skeleton_%d" % skeleton.get_instance_id()
	var selected := GameData.get_viewmodel_loadout(team)
	var sources: Dictionary = {}
	for kind in ["gloves", "sleeves"]:
		var option: Dictionary = selected.get(kind, {})
		var model := String(option.get("model", ""))
		var packed := GameData.get_model_scene(model)
		if packed == null:
			_free_sources(sources)
			return false
		var instance := packed.instantiate() as Node3D
		if instance == null:
			_free_sources(sources)
			return false
		var meshes := _find_meshes(instance)
		if meshes.is_empty():
			instance.free()
			_free_sources(sources)
			return false
		var valid := true
		for mesh in meshes:
			if (mesh as MeshInstance3D).skin == null:
				valid = false
		if not valid:
			instance.free()
			_free_sources(sources)
			return false
		sources[kind] = {
			"instance": instance,
			"meshes": meshes,
			"path": model,
		}

	# Convert everything before hiding the original arms. Any failure leaves the
	# known-good original model untouched.
	for kind in sources:
		var entry: Dictionary = sources[kind]
		var converted: Array = []
		for raw in entry["meshes"]:
			var baked := _bake_for_target(raw as MeshInstance3D, skeleton, cache_namespace)
			if baked.is_empty():
				_free_sources(sources)
				return false
			converted.append(baked)
		entry["converted"] = converted

	var removed := _remove_legacy_arm_surfaces(root)
	if removed == 0:
		_free_sources(sources)
		return false
	for kind in sources:
		var entry: Dictionary = sources[kind]
		for converted in entry["converted"]:
			var copy := MeshInstance3D.new()
			copy.name = "Loadout_%s_%d" % [kind.capitalize(), root.get_child_count()]
			copy.mesh = converted["mesh"]
			copy.skin = converted["skin"]
			copy.layers = 4
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.set_meta("loadout_kind", kind)
			copy.set_meta("loadout_source", entry["path"])
			copy.set_meta("loadout_bind", "native_target_rest")
			root.add_child(copy)
			# Vertices and inverse binds are both in skeleton-local rest space.
			copy.global_transform = skeleton.global_transform
			copy.skeleton = copy.get_path_to(skeleton)
	_free_sources(sources)
	return true


static func _bake_for_target(source: MeshInstance3D, skeleton: Skeleton3D, cache_namespace: String) -> Dictionary:
	var cache_key := "%s/%d" % [cache_namespace, source.mesh.get_instance_id()]
	if _baked_sources.has(cache_key):
		return _baked_sources[cache_key] as Dictionary
	var mapped_skin := _skin_for_skeleton(source.skin, skeleton)
	var target_rest := skeleton.create_skin_from_rest_transforms()
	var result_skin := Skin.new()
	var joints: Array[Transform3D] = []
	var normal_joints: Array[Basis] = []
	for bind in range(mapped_skin.get_bind_count()):
		var target_bone := skeleton.find_bone(String(mapped_skin.get_bind_name(bind)))
		if target_bone < 0:
			return {}
		var target_inverse := target_rest.get_bind_pose(target_bone)
		result_skin.add_bind(target_bone, target_inverse)
		var joint := target_inverse.affine_inverse() * mapped_skin.get_bind_pose(bind)
		joints.append(joint)
		normal_joints.append(joint.basis.inverse().transposed())

	var rebuilt := ArrayMesh.new()
	for surface in range(source.mesh.get_surface_count()):
		var arrays := source.mesh.surface_get_arrays(surface).duplicate()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var tangents := PackedFloat32Array()
		if arrays[Mesh.ARRAY_TANGENT] != null:
			tangents = arrays[Mesh.ARRAY_TANGENT]
		if vertices.is_empty() or normals.size() != vertices.size() \
			or bones.size() < vertices.size() * 4 or weights.size() < vertices.size() * 4:
			return {}
		var baked_vertices := PackedVector3Array()
		var baked_normals := PackedVector3Array()
		var baked_tangents := PackedFloat32Array()
		baked_vertices.resize(vertices.size())
		baked_normals.resize(vertices.size())
		var has_tangents := tangents.size() == vertices.size() * 4
		if has_tangents:
			baked_tangents.resize(vertices.size() * 4)
		for index in range(vertices.size()):
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			var tangent := Vector3.ZERO
			for influence in range(4):
				var weight := weights[index * 4 + influence]
				var joint_index := bones[index * 4 + influence]
				if weight <= 0.0:
					continue
				if joint_index < 0 or joint_index >= joints.size():
					return {}
				point += (joints[joint_index] * vertices[index]) * weight
				normal += (normal_joints[joint_index] * normals[index]) * weight
				if has_tangents:
					var source_tangent := Vector3(tangents[index * 4], tangents[index * 4 + 1], tangents[index * 4 + 2])
					tangent += (normal_joints[joint_index] * source_tangent) * weight
			baked_vertices[index] = point
			baked_normals[index] = normal.normalized()
			if has_tangents:
				var baked_tangent := tangent.normalized()
				baked_tangents[index * 4] = baked_tangent.x
				baked_tangents[index * 4 + 1] = baked_tangent.y
				baked_tangents[index * 4 + 2] = baked_tangent.z
				baked_tangents[index * 4 + 3] = tangents[index * 4 + 3]
		arrays[Mesh.ARRAY_VERTEX] = baked_vertices
		arrays[Mesh.ARRAY_NORMAL] = baked_normals
		if has_tangents:
			arrays[Mesh.ARRAY_TANGENT] = baked_tangents
		rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, source.mesh.surface_get_material(surface))
	var result := {"mesh": rebuilt, "skin": result_skin}
	_baked_sources[cache_key] = result
	return result


static func _free_sources(sources: Dictionary) -> void:
	for entry in sources.values():
		var instance := entry.get("instance") as Node
		if is_instance_valid(instance):
			instance.free()


static func _skin_for_skeleton(source: Skin, skeleton: Skeleton3D) -> Skin:
	var result := source
	var duplicated := false
	for index in range(source.get_bind_count()):
		var bone_name := String(source.get_bind_name(index))
		if skeleton.find_bone(bone_name) >= 0:
			continue
		if not duplicated:
			result = source.duplicate() as Skin
			duplicated = true
		var fallback := bone_name
		if bone_name.contains("_UpperArm") or bone_name.contains("_ForeTwist"):
			fallback = bone_name.replace("_UpperArm", "_Forearm").replace("_ForeTwist", "_Forearm")
		elif bone_name.contains("_Finger"):
			fallback = bone_name.left(bone_name.find("_Finger")) + "_Hand"
		if skeleton.find_bone(fallback) < 0:
			fallback = "v_weapon.Bip01_L_Hand" if "_L_" in bone_name else "v_weapon.Bip01_R_Hand"
		result.set_bind_name(index, fallback)
		result.set_bind_bone(index, -1)
	return result


static func _remove_legacy_arm_surfaces(root: Node) -> int:
	var removed := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null or instance.has_meta("loadout_kind"):
			continue
		var filtered := _filtered_mesh(instance.mesh)
		if filtered != instance.mesh:
			instance.mesh = filtered
			removed += 1
	return removed


static func _filtered_mesh(source: Mesh) -> Mesh:
	var key := source.get_instance_id()
	if _filtered_meshes.has(key):
		return _filtered_meshes[key] as Mesh
	var rebuilt := ArrayMesh.new()
	var removed := 0
	for surface in range(source.get_surface_count()):
		var material := source.surface_get_material(surface)
		var material_name := material.resource_name.to_lower() if material != null else ""
		if material_name in ["ct_arms.bmp", "ct_base_glove.bmp"]:
			removed += 1
			continue
		rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
		rebuilt.surface_set_material(rebuilt.get_surface_count() - 1, material)
	var result: Mesh = rebuilt if removed > 0 else source
	_filtered_meshes[key] = result
	return result


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


static func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_find_meshes(child))
	return result
