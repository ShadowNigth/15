class_name AgentViewArms
extends RefCounted
## Independent dedicated agent sleeves on existing animation rigs.
static var _catalog: Dictionary = {}
static var _mesh_cache: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/agent_view_arms.json"))
	return _catalog

static func matrix(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0], values[4], values[8]), Vector3(values[1], values[5], values[9]), Vector3(values[2], values[6], values[10])), Vector3(values[3], values[7], values[11]))

static func _entry(table: Dictionary, name: String) -> Dictionary:
	if table.has(name):
		return table[name]
	for key in table:
		if String(key).replace(".", "_") == name:
			return table[key]
	return {}

static func _bone(rig: Skeleton3D, name: String) -> int:
	var bone := rig.find_bone(name)
	return bone if bone >= 0 else rig.find_bone(name.replace(".", "_"))

static func _converted(source: MeshInstance3D, rig: Skeleton3D, model: String, avatar: String) -> Dictionary:
	var key := model + ":" + avatar
	var targets: Dictionary = catalog().get("targets", {}).get(model, {})
	if targets.is_empty() or source.skin == null:
		return {}
	var transforms: Array[Transform3D] = []
	var mapped := Skin.new()
	var supported: Array[bool] = []
	for index in source.skin.get_bind_count():
		var name := String(source.skin.get_bind_name(index))
		var entry := _entry(targets, name)
		# Unused weapon/root binds are retained but do not influence these meshes.
		if entry.is_empty():
			supported.append(false)
			transforms.append(Transform3D.IDENTITY)
			mapped.add_bind(0, Transform3D.IDENTITY)
			continue
		var target := _bone(rig, String(entry.target))
		if target < 0:
			return {}
		supported.append(true)
		transforms.append(matrix(entry.matrix))
		mapped.add_bind(target, matrix(entry.bind))
	if _mesh_cache.has(key):
		return {"mesh": _mesh_cache[key], "skin": mapped}
	var mesh := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var count: int = bones.size() / maxi(1, vertices.size())
		for vertex in vertices.size():
			var point := Vector3.ZERO
			var normal := Vector3.ZERO
			for slot in count:
				var offset: int = vertex * count + slot
				var weight := weights[offset]
				if weight <= 0:
					continue
				if bones[offset] >= supported.size() or not supported[bones[offset]]:
					# Never bind a weighted arm vertex to the weapon/root silently.
					return {}
				var transform := transforms[bones[offset]]
				point += (transform * vertices[vertex]) * weight
				normal += (transform.basis.inverse().transposed() * normals[vertex]) * weight
			vertices[vertex] = point
			normals[vertex] = normal.normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		# Tangents from the source bind pose are not valid after retargeting.
		arrays[Mesh.ARRAY_TANGENT] = null
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(surface, source.mesh.surface_get_material(surface))
	var finished := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(mesh, surface)
		tool.generate_tangents()
		tool.commit(finished)
	mesh = finished
	_mesh_cache[key] = mesh
	return {"mesh": mesh, "skin": mapped}

static func install(root: Node3D, model: String, avatar: String, native_textures: Dictionary = {}) -> bool:
	var rig := SportGloves._find_skeleton(root)
	var is_glove: bool = catalog().get("gloves", {}).has(avatar)
	var definition: Dictionary = catalog().get("gloves" if is_glove else "agents", {}).get(avatar, {})
	if rig == null or definition.is_empty():
		return false
	var packed := load(String(definition.model)) as PackedScene
	if packed == null:
		return false
	var source := packed.instantiate() as Node3D
	var meshes := SportGloves._find_meshes(source)
	if meshes.size() != 1:
		source.free()
		return false
	var converted := _converted(meshes[0], rig, model, avatar)
	if converted.is_empty():
		source.free()
		return false
	var copy := MeshInstance3D.new()
	copy.name = "NativeMotoGloves" if is_glove else "AgentSleeves_" + avatar
	copy.mesh = converted.mesh
	var seam_key := model + ":" + avatar + ":" + root.scene_file_path + ":" + GameData.selected_glove_id
	if WristSeamFit.enabled and not is_glove:
		copy.mesh = WristSeamFit.fit(root, rig, converted.mesh, converted.skin, seam_key, avatar)
	copy.skin = converted.skin
	copy.layers = 4
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	copy.set_meta("native_view_cosmetic", true)
	copy.set_meta("agent_arms", avatar)
	if is_glove:
		copy.set_meta("sport_gloves", true)
		copy.set_meta("native_glove", avatar)
		copy.set_meta("sport_glove_id", GameData.selected_glove_id)
	if WristSeamFit.enabled and not is_glove:
		copy.set_meta("wrist_seam_fit", "layered-cuff-v5")
		copy.set_meta("cuff_layer", "inside_glove" if WristSeamFit.is_bare(avatar) else "outside_glove")
		copy.set_meta("cuff_fit", WristSeamFit.profiles_by_key.get(seam_key, {}))
	for surface in copy.mesh.get_surface_count():
		var material := copy.mesh.surface_get_material(surface).duplicate() as BaseMaterial3D
		if is_glove:
			material.albedo_texture = GameData.get_texture(String(native_textures.get(material.resource_name, "")))
			if material.albedo_texture == null:
				copy.free()
				source.free()
				return false
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.roughness = 0.85
		material.metallic = 0
		if is_glove:
			var maps: Dictionary = definition.get("native_maps", {}).get(material.resource_name, {})
			material.normal_texture = GameData.get_texture(String(maps.get("normal", "")))
			material.normal_enabled = material.normal_texture != null
			var orm := GameData.get_texture(String(maps.get("orm", "")))
			material.roughness_texture = orm
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			material.metallic_texture = orm
			material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			material.ao_texture = orm
			material.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			material.ao_enabled = orm != null
			material.roughness = 1.0
			material.metallic = 1.0
			material.set_meta("native_moto_pbr", true)
		copy.set_surface_override_material(surface, material)
	var remove := "ct_base_glove.bmp" if is_glove else "ct_arms.bmp"
	var replaced := 0
	for instance in SportGloves._find_meshes(root):
		if instance.has_meta("native_view_cosmetic") or instance.has_meta("sport_gloves"):
			continue
		var filtered := ArrayMesh.new()
		var removed := false
		for surface in instance.mesh.get_surface_count():
			var mat := instance.mesh.surface_get_material(surface)
			if mat != null and mat.resource_name.to_lower() == remove:
				removed = true
				continue
			filtered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, instance.mesh.surface_get_arrays(surface))
			filtered.surface_set_material(filtered.get_surface_count() - 1, mat)
		if removed:
			instance.mesh = filtered
			replaced += 1
	if replaced == 0:
		copy.free()
		source.free()
		return false
	root.add_child(copy)
	copy.global_transform = rig.global_transform
	copy.skeleton = copy.get_path_to(rig)
	source.free()
	root.set_meta("native_glove" if is_glove else "view_agent", avatar)
	return true

static func apply(root: Node3D, model: String, team: String, class_id: String) -> bool:
	if NativeViewRig.enabled:
		return NativeViewRig.install(root, GameData.get_knife_glove_model(model), ModernAgentPose.role(team, class_id))
	return install(root, GameData.get_knife_glove_model(model), ModernAgentPose.role(team, class_id))
