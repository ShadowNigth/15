class_name ViewmodelLoadout
extends RefCounted
## Installs selectable PBR arms on the animated skeleton already inside each v_*.
## Named Skin binds are resolved by Godot against that skeleton, so all weapon
## animations continue to drive the replacement hands, gloves and sleeves.

static var _filtered_meshes: Dictionary = {}


static func apply(root: Node3D, team: String) -> bool:
	if root == null:
		return false
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		return false
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

	# Do not remove the original arms until every replacement asset is valid.
	var removed := _remove_legacy_arm_surfaces(root)
	if removed == 0:
		_free_sources(sources)
		return false
	for kind in sources:
		var entry: Dictionary = sources[kind]
		for raw in entry["meshes"]:
			var source := raw as MeshInstance3D
			var copy := MeshInstance3D.new()
			copy.name = "Loadout_%s_%d" % [kind.capitalize(), root.get_child_count()]
			copy.mesh = source.mesh
			copy.skin = _skin_for_skeleton(source.skin, skeleton)
			copy.transform = Transform3D.IDENTITY
			copy.layers = 4
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.set_meta("loadout_kind", kind)
			copy.set_meta("loadout_source", entry["path"])
			root.add_child(copy)
			copy.skeleton = copy.get_path_to(skeleton)
	_free_sources(sources)
	return true


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
