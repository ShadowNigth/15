class_name Dust2Renovation
extends RefCounted
## Visual-only upper-facade dressing. No colliders, navigation, gameplay volumes,
## cache/preload system or realtime shadow lights. Original textures stay intact.
const ASSET := "res://assets/maps/de_dust2_dressing.glb"

static func apply(root: Node3D) -> Node3D:
	var scene := load(ASSET) as PackedScene
	if scene == null:
		push_error("[Dust2 renovation] Missing dressing asset")
		return null
	var decoration := scene.instantiate() as Node3D
	decoration.name = "Dust2VisualRenovation"
	root.add_child(decoration)
	var shared_materials: Dictionary = {}
	for raw in decoration.find_children("*", "MeshInstance3D", true, false):
		var mesh := raw as MeshInstance3D
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.layers = 1
		mesh.visibility_range_end = 420.0 if String(mesh.name).begins_with("Backdrop") else 110.0
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
				material.roughness = 1.0
				material.metallic = 0.0
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				shared_materials[id] = material
			mesh.set_surface_override_material(surface, material)
	var environment := (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	# Compatibility-renderer depth fog, very light at map distances. No volumetrics.
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.73, 0.70, 0.62)
	environment.fog_density = 0.0008
	environment.fog_sky_affect = 0.0
	var shader := load("res://assets/shaders/dust2_sky.gdshader") as Shader
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
	root.set_meta("dust2_visual_renovation", true)
	return decoration
