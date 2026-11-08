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
		var metal := "generic" in name
		material.set_shader_parameter("relief_depth", 0.0 if flat else (0.006 if metal else (0.010 if wood else 0.020)))
		material.set_shader_parameter("detail_strength", 0.0 if flat else 0.20)
		material.set_shader_parameter("relief_light_strength", 0.52)
		material.set_shader_parameter("material_roughness", 0.88 if metal else 0.96)
