class_name NativeViewRig
extends Node3D
## Independent original cs2go skeletons driven by the existing weapon animation.
## Geometry, source bone names, skin inverse binds and weights are never remapped.
static var enabled := true # Original source skins; legacy path retained only for historical tests.
static var _catalog: Dictionary = {}
var target: Skeleton3D
var bindings: Array[Dictionary] = []

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/native_view_rigs.json"))
	return _catalog

func _process(_delta: float) -> void:
	sync_pose()

func sync_pose() -> void:
	if not is_instance_valid(target):
		return
	target.force_update_all_bone_transforms()
	for binding in bindings:
		var rig: Skeleton3D = binding.rig
		# Source skeletons may have their own import root. Express poses in that
		# skeleton's coordinates, not in the camera or mesh coordinates.
		var space := rig.global_transform.affine_inverse() * target.global_transform
		for driver in binding.drivers:
			var pose: Transform3D = space * target.get_bone_global_pose(driver.target) * driver.correction
			rig.set_bone_global_pose_override(driver.source, pose, 1.0, true)
		rig.force_update_all_bone_transforms()

func _prepare(definition: Dictionary, model: String, gloves: bool, smoke: bool) -> bool:
	var packed := load(String(definition.model)) as PackedScene
	if packed == null or not definition.drivers.has(model):
		return false
	var source := packed.instantiate() as Node3D
	add_child(source)
	var driver_table: Dictionary = definition.drivers[model]
	var found := false
	var rigs: Dictionary = {}
	for mesh in SportGloves._find_meshes(source):
		# A full-cover native glove includes its matching forearm endpoint.
		# Never render the default agent hands underneath a second pair.
		if smoke and not gloves and String(mesh.name).begins_with("agent_hands_"):
			mesh.hide()
			continue
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if rig == null or mesh.skin == null:
			return false
		rigs[rig] = true
		var filtered := ArrayMesh.new()
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat == null:
				return false
			var name_lower := mat.resource_name.to_lower()
			if smoke and not gloves and name_lower.contains("glove"):
				continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for offset in bones.size():
				if weights[offset] <= 0.00001:
					continue
				var name := String(mesh.skin.get_bind_name(bones[offset]))
				if name.is_empty():
					name = String(rig.get_bone_name(mesh.skin.get_bind_bone(bones[offset])))
				if not driver_table.has(name):
					push_error("Native view: unmapped weighted source bone " + name)
					return false
			# Arrays are copied unchanged: no projection, clipping, compression,
			# new cuff geometry, remapped joint indices or reweighted vertices.
			filtered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var material := mat.duplicate() as BaseMaterial3D
			material.albedo_color.a = 1.0
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			if gloves and name_lower.begins_with("glove_motorcycle_"):
				material.albedo_color = Color.WHITE # Replace unpainted native black factor as well as texture.
				var option := GameData.get_selected_glove()
				material.albedo_texture = GameData.get_texture(String(option.get("native_textures", {}).get(material.resource_name, "")))
				if material.albedo_texture == null:
					return false
				var maps: Dictionary = AgentViewArms.catalog().gloves.moto_smoke_out.native_maps.get(material.resource_name, {})
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
			filtered.surface_set_material(filtered.get_surface_count() - 1, material)
		mesh.mesh = filtered
		mesh.visible = filtered.get_surface_count() > 0
		mesh.layers = 4
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.set_meta("native_source_skin", true)
		found = found or mesh.visible
	for rig in rigs:
		var drivers: Array[Dictionary] = []
		for name in driver_table:
			var bone: int = rig.find_bone(name)
			if bone < 0:
				continue
			var entry: Dictionary = driver_table[name]
			var destination := AgentViewArms._bone(target, String(entry.target))
			if destination < 0:
				return false
			drivers.append({"source": bone, "target": destination, "correction": AgentViewArms.matrix(entry.correction)})
		bindings.append({"rig": rig, "drivers": drivers})
	return found or (smoke and not gloves)

static func install(root: Node3D, model: String, avatar: String) -> bool:
	var target_rig := SportGloves._find_skeleton(root)
	var definition: Dictionary = catalog().agents.get(avatar, {})
	var selected := GameData.get_selected_glove()
	var smoke := String(selected.get("id", "")) == "5033_10078"
	if target_rig == null or definition.is_empty():
		return false
	var replacement := NativeViewRig.new()
	replacement.name = "NativeViewRig"
	replacement.target = target_rig
	replacement.process_priority = 100
	root.add_child(replacement)
	var ok := replacement._prepare(definition, model, false, smoke)
	if ok and smoke:
		ok = replacement._prepare(catalog().gloves.moto_smoke_out, model, true, true)
	if not ok:
		replacement.free()
		return false
	# Transaction: original meshes remain intact until every native bind passed.
	var previous := root.get_meta("native_view_rig") as NativeViewRig if root.has_meta("native_view_rig") else null
	if is_instance_valid(previous):
		previous.free()
	for mesh in SportGloves._find_meshes(root):
		if mesh.has_meta("native_source_skin"):
			continue
		if mesh.has_meta("native_view_cosmetic") or mesh.has_meta("sport_gloves"):
			mesh.visible = false
			continue
		var filtered := ArrayMesh.new()
		var removed := false
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material != null and material.resource_name.to_lower() in ["ct_arms.bmp", "ct_base_glove.bmp"]:
				removed = true
				continue
			filtered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.mesh.surface_get_arrays(surface))
			filtered.surface_set_material(filtered.get_surface_count() - 1, material)
		if removed:
			for surface in mesh.mesh.get_surface_count(): mesh.set_surface_override_material(surface, null)
			mesh.mesh = filtered
			mesh.visible = filtered.get_surface_count() > 0
	root.set_meta("native_view_rig", replacement)
	root.set_meta("view_agent", avatar)
	replacement.sync_pose()
	return true
