class_name SportGloves
extends RefCounted
## Attaches pre-converted Sport_gloves meshes to the existing viewmodel skeleton.
## All vertex/bone conversion is baked offline per weapon. This installer only
## maps native Skin binds by name and replaces ct_base_glove.bmp; the original
## ct_arms.bmp surface, target skeleton and every animation remain untouched.

static var _filtered_meshes: Dictionary = {}


static func apply(root: Node3D, viewmodel_name: String) -> bool:
	if root == null:
		return false
	var option := GameData.get_selected_glove()
	var glove_model := GameData.get_knife_glove_model(viewmodel_name)
	if option.is_empty() or not glove_model in GameData.sport_gloves.get("models", []):
		return false
	if bool(option.get("native_uv", false)):
		return AgentViewArms.install(root, glove_model, "sport", option.get("native_textures", {}))
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		return false
	var packed := GameData.get_model_scene("sport_gloves/" + glove_model)
	if packed == null:
		return false
	var source := packed.instantiate() as Node3D
	if source == null:
		return false
	var source_meshes := _find_meshes(source)
	if source_meshes.is_empty():
		source.free()
		return false

	var copies: Array[MeshInstance3D] = []
	for raw in source_meshes:
		var source_mesh := raw as MeshInstance3D
		if source_mesh.mesh == null or source_mesh.skin == null:
			_free_copies(copies)
			source.free()
			return false
		var mapped := _mapped_skin(source_mesh.skin, skeleton)
		if mapped == null:
			_free_copies(copies)
			source.free()
			return false
		var copy := MeshInstance3D.new()
		copy.name = "SportGloves_%d" % copies.size()
		copy.mesh = source_mesh.mesh
		copy.skin = mapped
		copy.layers = 4
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		copy.set_meta("sport_gloves", true)
		copy.set_meta("sport_glove_id", String(option.get("id", "")))
		for surface in range(copy.mesh.get_surface_count()):
			var material := copy.mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null:
				_free_copies(copies)
				source.free()
				return false
			var textured := GameData.get_sport_glove_source_material(material, option)
			if textured == null:
				_free_copies(copies)
				source.free()
				return false
			copy.set_surface_override_material(surface, textured)
		copies.append(copy)

	# Do not hide the known-good glove until every source mesh and bind passed.
	var removed := _remove_original_gloves(root)
	if removed == 0:
		_free_copies(copies)
		source.free()
		return false
	for copy in copies:
		root.add_child(copy)
		copy.global_transform = skeleton.global_transform
		copy.skeleton = copy.get_path_to(skeleton)
	source.free()
	return true


static func _mapped_skin(source: Skin, skeleton: Skeleton3D) -> Skin:
	var mapped := Skin.new()
	for bind in range(source.get_bind_count()):
		var bone_name := String(source.get_bind_name(bind))
		var target_bone := skeleton.find_bone(bone_name)
		if target_bone < 0:
			return null
		mapped.add_bind(target_bone, source.get_bind_pose(bind))
	return mapped


static func _remove_original_gloves(root: Node3D) -> int:
	var removed := 0
	for raw in _find_meshes(root):
		var instance := raw as MeshInstance3D
		if instance.has_meta("sport_gloves"):
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
		if material_name == "ct_base_glove.bmp":
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


static func _free_copies(copies: Array[MeshInstance3D]) -> void:
	for copy in copies:
		copy.free()
