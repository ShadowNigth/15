extends "res://tests/AztecPolishTest.gd"
## Inherits the full native bridge/bot/C4 suite, against the delivered polished map.
func baseline_data(data: Dictionary) -> Dictionary:
	var before := data.duplicate(true)
	before.visual_renovation = false
	return before

func validate_map(built: Dictionary) -> void:
	var root := built.root as Node3D
	expect(root.has_meta("aztec_visual_renovation"), "Aztec renovation installed")
	expect(root.get_node_or_null("AztecVisualRenovation") == null, "Added decorative objects removed")
	var environment := (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	expect(environment.fog_enabled and environment.fog_density <= 0.0015, "Thin jungle haze, not opaque fog")
	for raw in root.get_node("GoldSrcSkybox").get_children():
		var face := raw as MeshInstance3D
		var material := face.material_override as ShaderMaterial
		expect(material != null and material.get_shader_parameter("original_sky") != null, "Continuous storm sky retains original artwork")

func comparison_views() -> Array:
	var views := VIEWS.duplicate(true)
	views.append(["canopy", Vector3(43, -4, -29), Vector3(49, 4, -20)])
	views.append(["temple", Vector3(16, -4, 60), Vector3(25, 14, 83)])
	return views
