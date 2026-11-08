extends "res://tests/AztecPolishTest.gd"
## Inherits the full native bridge/bot/C4 suite, against the delivered polished map.
func baseline_data(data: Dictionary) -> Dictionary:
	var before := data.duplicate(true)
	before.visual_renovation = false
	return before

func validate_map(built: Dictionary) -> void:
	var root := built.root as Node3D
	expect(root.has_meta("aztec_visual_renovation"), "Aztec renovation installed")
	var decor := root.get_node_or_null("AztecVisualRenovation") as Node3D
	expect(decor != null, "Temple and jungle asset instantiated")
	if decor == null:
		return
	expect(decor.find_children("*", "CollisionObject3D", true, false).is_empty(), "Visual dressing adds no invisible collision, cover or bullet blocking")
	var meshes := decor.find_children("*", "MeshInstance3D", true, false)
	var report: Dictionary = GameData._load_json("res://data/aztec_renovation.json")
	expect(meshes.size() == int(report.mesh_cells) and meshes.size() <= 50, "Spatial mesh budget")
	var triangles := 0
	for raw in meshes:
		var mesh := raw as MeshInstance3D
		expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "No new shadow passes")
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			expect(material != null and material.vertex_color_use_as_albedo and material.roughness == 1.0, "Original textures, matte baked shading")
	expect(triangles <= 18000, "Decoration triangle budget")
	var environment := (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	expect(environment.fog_enabled and environment.fog_density <= 0.0015, "Thin jungle haze, not opaque fog")
	for raw in root.get_node("GoldSrcSkybox").get_children():
		var face := raw as MeshInstance3D
		var material := face.material_override as ShaderMaterial
		expect(material != null and material.get_shader_parameter("original_sky") != null, "Continuous storm sky retains original artwork")
	print("[AZTEC RENOVATION] triangles=", triangles, "; cells=", meshes.size())

func comparison_views() -> Array:
	var views := VIEWS.duplicate(true)
	views.append(["canopy", Vector3(43, -4, -29), Vector3(49, 4, -20)])
	views.append(["temple", Vector3(-30, -4, 14), Vector3(-30, 4, 30)])
	return views
