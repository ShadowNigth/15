extends "res://tests/Dust2PolishTest.gd"
## Same-camera comparison with previous delivered Dust2, plus full physics/bot suite.

func comparison_views() -> Array:
	var views := VIEWS.duplicate(true)
	views.append(["facade", Vector3(-91.5, 8.5, -45.5), Vector3(-91.5, 8.5, -50)])
	return views

func baseline_data(data: Dictionary) -> Dictionary:
	var before := data.duplicate(true)
	before.visual_renovation = false
	return before

func validate_map(built: Dictionary) -> void:
	var root := built.root as Node3D
	expect(root.has_meta("dust2_visual_renovation"), "Renovation enabled only on Dust2")
	expect(root.get_node_or_null("Dust2VisualRenovation") == null, "Added decorative objects removed")
	var environment := (root.get_node("WorldEnvironment") as WorldEnvironment).environment
	expect(environment.fog_enabled and environment.fog_density <= 0.001, "Light compatibility-renderer haze, not opaque fog")
