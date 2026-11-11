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
	var original_models: Dictionary = {}
	var config := AgentViewArms.catalog()
	expect(config.agents.size() == 9, "eight real agent arms and native Sport geometry")
	for avatar in config.agents:
		var scene := load(String(config.agents[avatar].model)) as PackedScene
		expect(scene != null, "actual mesh " + avatar)
	for model in config.targets:
		var root := GameData.get_model_scene("weapons/" + String(model)).instantiate() as Node3D
		add_child(root)
		var animation := SportGloves._find_skeleton(root)
		expect(animation != null, "original weapon rig " + model)
		var bones := animation.get_bone_count()
		GameData.select_glove("classic")
		expect(AgentViewArms.install(root, model, "sas"), "sleeves on " + model)
		expect(animation.get_bone_count() == bones, "original skeleton untouched " + model)
		var meshes := SportGloves._find_meshes(root)
		var actual := false
		for mesh in meshes:
			if mesh.has_meta("agent_arms"):
				actual = true
				expect(mesh.mesh.get_aabb().size.length() < 4, "bounded sleeve geometry " + model)
		expect(actual, "sleeve mesh installed " + model)
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
