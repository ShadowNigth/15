extends Node3D
var checks := 0
var failures := 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[AGENT ARMS] " + message)
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	var original_glove := GameData.selected_glove_id
	var config := AgentViewArms.catalog()
	expect(config.agents.size() == 9, "eight real agent arms and native Sport geometry")
	for option in GameData.get_glove_options():
		if String(option.id).begins_with("cs2go_"):
			expect(bool(option.get("native_uv", false)), "new Sport finish uses native UV, never projected atlas")
	for avatar in config.agents:
		expect(not bool(config.agents[avatar].get("extracted_from_body", true)), "no third-person arm extraction: " + avatar)
		expect(String(config.agents[avatar].source).begins_with("models/gloves/"), "dedicated first-person source: " + avatar)
		var scene := load(String(config.agents[avatar].model)) as PackedScene
		expect(scene != null, "actual mesh " + avatar)
	var substitutes := {"fbi": "5308", "leet": "5105", "phoenix_a": "5200"}
	for avatar in substitutes:
		expect(String(config.agents[avatar].source) == "models/gloves/agents/" + String(substitutes[avatar]) + ".glb", "documented dedicated substitute: " + avatar)
		expect(bool(config.agents[avatar].get("dedicated_first_person", false)), "replacement is a dedicated sleeve pack: " + avatar)
	for model in config.targets:
		for side in ["L", "R"]:
			var entries: Dictionary = config.targets[model]
			var forearm: String = "v_weapon.Bip01_" + side + "_Forearm"
			expect(String(entries[forearm].target).ends_with("_Forearm"), "forearm never aliases twist helper " + model)
			var upper: String = "v_weapon.Bip01_" + side + "_UpperArm"
			expect(entries.has(upper), "upper-arm weights have an animated target, including knives " + model)
		var root := GameData.get_model_scene("weapons/" + String(model)).instantiate() as Node3D
		add_child(root)
		var animation := SportGloves._find_skeleton(root)
		expect(animation != null, "original weapon rig " + model)
		var bones := animation.get_bone_count()
		GameData.select_glove("cs2go_5030_1417")
		expect(SportGloves.apply(root, model), "native Sport on every original weapon " + model)
		expect(root.get_meta("native_sport", "") == "sport", "native geometry not projected legacy fallback " + model)
		expect(AgentViewArms.install(root, model, "sas"), "sleeves on " + model)
		expect(animation.get_bone_count() == bones, "original skeleton untouched " + model)
		var meshes := SportGloves._find_meshes(root)
		var actual := false
		for mesh in meshes:
			if mesh.has_meta("sport_gloves"):
				expect(mesh.get_meta("handedness", "") == "anatomical-same-side-v3", "new gloves explicitly exchange hand geometry " + model)
				for surface in mesh.mesh.get_surface_count():
					var mat := mesh.mesh.surface_get_material(surface)
					var expected := "_R_" if mat.resource_name.ends_with("left") else "_L_"
					var arrays := mesh.mesh.surface_get_arrays(surface)
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
					var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
					var correct := true
					for slot in indices.size():
						if weights[slot] > 0.00001:
							var bone := mesh.skin.get_bind_bone(indices[slot])
							correct = correct and expected in animation.get_bone_name(bone)
					expect(correct, "each native glove/finger follows opposite animated hand " + model + mat.resource_name)
			if mesh.has_meta("agent_arms"):
				actual = actual or mesh.get_meta("agent_arms") == "sas"
				expect(mesh.mesh.get_aabb().size.length() < 4, "bounded sleeve geometry " + model)
		expect(actual, "sleeve mesh installed " + model)
		root.free()
	for option in GameData.get_knife_options():
		var model := String(option.get("v_model", ""))
		if model.is_empty():
			continue
		var root := GameData.get_model_scene("weapons/" + model).instantiate() as Node3D
		add_child(root)
		GameData.select_glove("cs2go_5030_1417")
		expect(SportGloves.apply(root, model), "native Sport on knife " + model)
		expect(AgentViewArms.apply(root, model, "T", "leet"), "agent sleeves on knife " + model)
		expect(root.get_meta("view_agent", "") == "leet", "knife does not silently retain original sleeves")
		root.free()
	for cls in GameData.modern_agents.classes:
		var avatar: String = GameData.modern_agents.classes[cls]
		for glove in ["classic", "arid_mw", "cs2go_5030_1417"]:
			expect(GameData.select_glove(glove), "independent glove selection " + glove)
			var root := GameData.get_model_scene("weapons/v_ak47").instantiate() as Node3D
			add_child(root)
			if glove != "classic":
				expect(SportGloves.apply(root, "v_ak47"), "selected gloves fit " + avatar + "/" + glove)
			expect(AgentViewArms.install(root, "v_ak47", avatar), "actual agent sleeve " + avatar)
			expect(GameData.selected_glove_id == glove, "agent change never overwrites gloves")
			root.free()
	GameData.selected_glove_id = original_glove
	print("[AGENT ARMS] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
