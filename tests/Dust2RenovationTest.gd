extends "res://tests/Dust2PolishTest.gd"
## Same-camera comparison with previous delivered Dust2, plus full physics/bot suite.

func baseline_data(data: Dictionary) -> Dictionary:
	var before := data.duplicate(true)
	before.visual_renovation = false
	return before

func validate_map(built: Dictionary) -> void:
	var root := built.root as Node3D
	expect(root.has_meta("dust2_visual_renovation"), "Renovation enabled only on Dust2")
	var dressing := root.get_node_or_null("Dust2VisualRenovation") as Node3D
	expect(dressing != null, "Dressing instantiated")
	if dressing == null:
		return
	expect(dressing.find_children("*", "CollisionObject3D", true, false).is_empty(), "Decor cannot add invisible walls or affect bullets/navigation")
	var meshes := dressing.find_children("*", "MeshInstance3D", true, false)
	expect(meshes.size() == 27, "Spatially batched dressing budget")
	var triangles := 0
	for raw in meshes:
		var mesh := raw as MeshInstance3D
		expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "No additional shadow render passes")
		for surface in range(mesh.mesh.get_surface_count()):
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var material := mesh.get_surface_override_material(surface) as StandardMaterial3D
			expect(material != null and material.vertex_color_use_as_albedo and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "Original texture with baked matte face shading")
	expect(triangles <= 7200, "Added geometry remains within budget")
	for raw in root.get_node("GoldSrcSkybox").get_children():
		var face := raw as MeshInstance3D
		expect(face.material_override is ShaderMaterial, "Directional sky installed")
		var shader := face.material_override as ShaderMaterial
		expect(shader.get_shader_parameter("original_sky") != null, "Original mountain/sky texture retained")
	var environment := (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	expect(environment.fog_enabled and environment.fog_density <= 0.001, "Light compatibility-renderer haze, not opaque fog")
	print("[DUST2 RENOVATION] Dressing triangles=",triangles,"; cells=",meshes.size())
