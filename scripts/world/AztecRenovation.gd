class_name AztecRenovation
extends RefCounted
## Temple relief, upper-wall ferns and out-of-play jungle. No colliders, navigation, gameplay volumes,
## cache/preload system or realtime shadow lights. Original textures stay intact.
const ASSET := "res://assets/maps/de_aztec_dressing.glb"

static func apply(root: Node3D) -> Node3D:
	var scene := load(ASSET) as PackedScene
	if scene == null:
		push_error("[Aztec renovation] Missing dressing asset")
		return null
	var decoration := scene.instantiate() as Node3D
	decoration.name = "AztecVisualRenovation"
	root.add_child(decoration)
	var shared_materials: Dictionary = {}
	for raw in decoration.find_children("*", "MeshInstance3D", true, false):
		var mesh := raw as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.layers = 1
		mesh.visibility_range_end = 260.0 if String(mesh.name).begins_with("Backdrop") else 95.0
		for surface in range(mesh.mesh.get_surface_count()):
			var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var id := source.get_instance_id()
			var material: StandardMaterial3D = shared_materials.get(id)
			if material == null:
				material = source.duplicate() as StandardMaterial3D
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				material.vertex_color_use_as_albedo = true
				material.cull_mode = BaseMaterial3D.CULL_DISABLED if source.resource_name == "Aztec_leaf" else BaseMaterial3D.CULL_BACK
				material.roughness = 1.0
				material.metallic = 0.0
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				shared_materials[id] = material
			mesh.set_surface_override_material(surface, material)
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
	return decoration
