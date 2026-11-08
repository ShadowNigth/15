class_name Dust2Polish
extends RefCounted
## Dust2-only art direction. Authored textures/UVs, lightmap and gameplay stay intact.
## The baked lightmap remains the source of indoor/outdoor illumination; no extra
## shadow maps, realtime world lights, loading overlays or background caches.

static func configure_lighting(root: Node3D) -> void:
	var world_environment := root.get_node("WorldEnvironment") as WorldEnvironment
	world_environment.environment.ambient_light_energy = 0.82
	world_environment.environment.ambient_light_color = Color(0.93, 0.91, 0.87)
	var sun := root.get_node("CharacterSunLight") as DirectionalLight3D
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.95, 0.86)
	var fill := root.get_node("CharacterFillLight") as DirectionalLight3D
	fill.light_energy = 0.38
	# Actor lighting still excludes the BSP: do not double-light baked interiors.

static func configure_material(material: ShaderMaterial, texture_name: String) -> void:
	material.set_shader_parameter("lightmap_boost", 1.16)
	material.set_shader_parameter("lightmap_exponent", 0.92)
	material.set_shader_parameter("lightmap_floor", 0.075)
	material.set_shader_parameter("lightmap_ceiling", 1.40)
	var wood := "crt" in texture_name or "crate" in texture_name or "door" in texture_name
	var metal := "mltry" in texture_name or "generic011" in texture_name
	var flat := texture_name in ["white", "black"] or "credit" in texture_name or "lgt_" in texture_name
	material.set_shader_parameter("relief_depth", 0.0 if flat else (0.004 if metal else (0.012 if wood else 0.018)))
	material.set_shader_parameter("detail_strength", 0.0 if flat else 0.18)
	material.set_shader_parameter("relief_light_strength", 0.48)
	material.set_shader_parameter("material_roughness", 0.86 if metal else 0.96)
