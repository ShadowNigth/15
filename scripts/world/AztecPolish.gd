class_name AztecPolish
extends RefCounted
## Aztec-only lightmap/material profile. No layout, sky, actor or objective swap.

static func configure_lighting(root: Node3D) -> void:
	var environment := (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	environment.ambient_light_color = Color(0.82, 0.88, 0.84)
	environment.ambient_light_energy = 0.86
	var sun := root.get_node("CharacterSunLight") as DirectionalLight3D
	sun.light_color = Color(0.92, 0.96, 0.90)
	sun.light_energy = 1.04
	var fill := root.get_node("CharacterFillLight") as DirectionalLight3D
	fill.light_color = Color(0.74, 0.82, 0.92)
	fill.light_energy = 0.40
	# BSP remains lightmapped: no costly shadow passes or doubled world lighting.

static func configure_material(material: ShaderMaterial, name: String) -> void:
	material.set_shader_parameter("lightmap_boost", 1.15)
	material.set_shader_parameter("lightmap_exponent", 0.90)
	material.set_shader_parameter("lightmap_floor", 0.095)
	material.set_shader_parameter("lightmap_ceiling", 1.40)
	var kind := material.shader.resource_path.get_file()
	if kind == "water.gdshader":
		# Keep original green water, waves, transparency and refraction, less glossy.
		material.set_shader_parameter("wave_uv_strength", 0.0055)
		material.set_shader_parameter("refraction_strength", 0.0028)
		material.set_shader_parameter("wave_normal_strength", 0.065)
		material.set_shader_parameter("water_roughness", 0.48)
		material.set_shader_parameter("water_specular", 0.28)
		material.set_shader_parameter("water_metallic", 0.0)
	elif kind == "goldsrc_world.gdshader":
		var flat := name in ["black", "nothing", "made_by_me", "thanks", "special_thx"] or "sign" in name or "lgt_" in name
		var wood := "wood" in name or "rope" in name
		var metal := "rusty" in name or "rung" in name
		# generic035/generic039 are concrete tiles in this map, not metal.
		material.set_shader_parameter("relief_depth", 0.0 if flat else (0.006 if metal else (0.010 if wood else 0.020)))
		material.set_shader_parameter("detail_strength", 0.0 if flat else 0.20)
		material.set_shader_parameter("relief_light_strength", 0.52)
		material.set_shader_parameter("material_roughness", 0.88 if metal else 0.96)

static func restore_bridge_floor(mesh: MeshInstance3D) -> void:
	# The authored net deck is func_illusionary; its player clip hull was not
	# exported with BSP rendering faces. Restore only the existing upper deck,
	# never its invisible side faces or a bounding box spanning the river.
	var faces := PackedVector3Array()
	for surface in range(mesh.mesh.get_surface_count()):
		var material := mesh.mesh.surface_get_material(surface)
		if material == null or material.resource_name != "mask_vinage2":
			continue
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for index in range(vertices.size()):
				indices.append(index)
		for offset in range(0, indices.size(), 3):
			var a := indices[offset]
			var b := indices[offset + 1]
			var c := indices[offset + 2]
			if minf(normals[a].y, minf(normals[b].y, normals[c].y)) < 0.65:
				continue
			faces.append_array(PackedVector3Array([vertices[a], vertices[b], vertices[c]]))
	if faces.is_empty():
		push_error("[Aztec] No authored bridge deck faces found")
		return
	var body := StaticBody3D.new()
	body.name = "AztecBridgeWalkSurface"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("aztec_bridge_floor", true)
	# Weapons must still query the original layer-8 net, not double-hit its support.
	body.add_to_group("weapon_ray_excluded_support")
	mesh.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collision.shape = shape
	body.add_child(collision)
