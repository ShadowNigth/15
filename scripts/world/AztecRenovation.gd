class_name AztecRenovation
extends RefCounted
## Atmosphere only. Added map decoration removed by request; BSP remains intact.

static func apply(root: Node3D) -> Node3D:
	var environment := (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	# Compatibility-renderer depth fog, very light at map distances. No volumetrics.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.46, 0.57, 0.52)
	environment.fog_density = 0.0014
	environment.fog_sky_affect = 0.0
	var shader := load("res://assets/shaders/aztec_sky.gdshader") as Shader
	for raw in root.get_node("GoldSrcSkybox").get_children():
		var face := raw as MeshInstance3D
		if face == null:
			continue
		var original := face.material_override as StandardMaterial3D
		if original == null:
			continue
		var sky := ShaderMaterial.new()
		sky.shader = shader
		sky.set_shader_parameter("original_sky", original.albedo_texture)
		face.material_override = sky
	root.set_meta("aztec_visual_renovation", true)
	return null
