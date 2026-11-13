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
	NativeViewRig.enabled = false # Historical legacy-pipeline regression only.
	var original_glove := GameData.selected_glove_id
	var config := AgentViewArms.catalog()
	expect(config.agents.size() == 8, "eight dedicated agent sleeve packages")
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
		GameData.select_glove("classic")
		expect(not SportGloves.apply(root, model), "original gloves do not install a replacement " + model)
		expect(not root.has_meta("native_sport"), "retired glove conversion absent " + model)
		expect(AgentViewArms.install(root, model, "sas"), "sleeves on " + model)
		expect(animation.get_bone_count() == bones, "original skeleton untouched " + model)
		var meshes := SportGloves._find_meshes(root)
		var actual := false
		for mesh in meshes:
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
		GameData.select_glove("classic")
		expect(not SportGloves.apply(root, model), "original gloves retained on knife " + model)
		expect(AgentViewArms.apply(root, model, "T", "leet"), "agent sleeves on knife " + model)
		expect(root.get_meta("view_agent", "") == "leet", "knife does not silently retain original sleeves")
		root.free()
	for cls in GameData.modern_agents.classes:
		var avatar: String = GameData.modern_agents.classes[cls]
		for glove in ["classic", "arid_mw"]:
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
