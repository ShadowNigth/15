extends Node3D
var checks := 0
var failures := 0
var actors: Array[CSActor] = []
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[COSMETICS] " + message)
func capture(label: String) -> void:
	var dir := OS.get_environment("MODERN_CAPTURE_DIR")
	if dir.is_empty(): return
	DirAccess.make_dir_recursive_absolute(dir)
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	expect(get_viewport().get_texture().get_image().save_png(dir.path_join(label + ".png")) == OK, "capture " + label)
func _ready() -> void:
	run.call_deferred()
func run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/cs2go_cosmetics.json"))
	expect(report.weapons.size() == 68, "68 new gun finishes")
	expect(report.gloves.size() == 19, "19 Sport finishes")
	expect(report.agents.size() == 6, "six additional agents")
	var selected := GameData.selected_weapon_skins.duplicate()
	for row in report.weapons:
		var wid: String = row.weapon
		expect(GameData.select_weapon_skin(wid, row.id), "select " + row.id)
		expect(GameData.get_selected_weapon_skin_id(wid) == row.id, "selection persists " + wid)
		var texture := GameData.get_texture(row.texture)
		expect(texture != null and texture.get_width() == 512, "real imported paint map " + row.id)
		expect(row.source_sha256.length() == 64, "pinned provenance")
		var scene := GameData.get_model_scene("weapons/" + String(GameData.weapons[wid].v_model))
		var model := scene.instantiate()
		add_child(model)
		var found := false
		for node in model.find_children("*", "MeshInstance3D", true, false):
			for surface in node.mesh.get_surface_count():
				var mat := node.mesh.surface_get_material(surface) as BaseMaterial3D
				if mat == null: continue
				if mat.resource_name in GameData.weapon_skins.weapons[wid].materials:
					found = true
					for mode in ["vm", "w_held", "w_drop"]:
						var styled := GameData.get_styled_model_material(mat, mode) as BaseMaterial3D
						expect(styled != null and styled.albedo_texture == texture, "paint reaches " + wid + "/" + mode)
		expect(found, "paintable body " + wid)
		model.free()
	GameData.selected_weapon_skins = selected
	var old_glove := GameData.selected_glove_id
	for row in report.gloves:
		expect(GameData.select_glove(row.id), "select Sport " + row.id)
		var option := GameData.get_selected_glove()
		expect(option.textures.size() == 10, "all ten existing Sport material slots")
		for path in option.textures.values(): expect(GameData.get_texture(path) != null, "actual Sport texture")
		var model := GameData.get_model_scene("weapons/v_ak47").instantiate() as Node3D
		add_child(model)
		expect(SportGloves.apply(model, "v_ak47"), "native binds retain original geometry")
		model.free()
	GameData.selected_glove_id = old_glove
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.5, 100)
	floor_shape.shape = box
	floor_body.position.y = -0.25
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var camera := Camera3D.new()
	camera.fov = 36
	add_child(camera)
	camera.look_at_from_position(Vector3(0, 2.6, -7.5), Vector3(0, 0.9, 1.2))
	camera.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.85
	camera.environment = env
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	add_child(light)
	var index := 0
	for team in ["CT", "T"]:
		for definition in GameData.classes[team]:
			var actor := CSBot.new()
			actor.team = team
			add_child(actor)
			actor.set_team_and_class(team, definition.id)
			actor.spawn_for_round(Vector3((index % 4 - 1.5) * 1.8, 0.03, (index / 4) * 2.8), 0, true)
			actor.set_process(false)
			actor.set_physics_process(false)
			actor.weapon_ctrl.set_process(false)
			var wid := "m4a1" if team == "CT" else "ak47"
			actor.weapon_ctrl.give_weapon(wid, 30, 90)
			actor.weapon_ctrl.equip_weapon_by_id(wid)
			expect(actor._modern_pose != null, "modern body " + definition.id)
			var avatar := ModernAgentPose.role(team, definition.id)
			expect(actor._anim_res_map.has("modern_reload_" + wid) and actor._anim_res_map.has("head"), "shared native actions and skeletal death " + avatar)
			actor._modern_pose.action = ""
			for frame in 20: actor._evaluate_character_pose(1.0/60)
			var hand := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("hand_R"))
			var axis := (hand.basis * ModernAgentPose.socket_basis(avatar, wid) * Vector3.FORWARD).normalized()
			expect(axis.dot(Vector3.FORWARD) > 0.85, "forward grip " + avatar)
			var head := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("head_0")).origin
			expect(head.y > 1.2 and head.y < 2.2, "metric body proportions " + avatar)
			actor._bullet_hitboxes.sync_pose()
			expect(actor._bullet_hitboxes.entries.size() == 11, "animated hitboxes " + avatar)
			for weapon_id in GameData.weapons:
				var grip := ModernAgentPose.table(avatar, weapon_id)
				expect(grip.has("basis") and grip.has("clips"), "per-weapon calibration " + avatar + "/" + weapon_id)
				var basis := ModernAgentPose.socket_basis(avatar, weapon_id)
				expect(basis.is_finite() and absf(basis.determinant()) > 0.01, "valid grip frame " + avatar + "/" + weapon_id)

			actors.append(actor)
			index += 1
	for frame in 15:
		for actor in actors:
			actor.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0 / 60)
			actor._evaluate_character_pose(1.0 / 60)
		await get_tree().physics_frame
	await capture("cosmetic_agents")
	for actor in actors:
		actor.velocity = Vector3.FORWARD * 5.5
		actor._modern_pose.action = ""
		for frame in 30: actor._evaluate_character_pose(1.0/60)
	await capture("cosmetic_agents_motion")
	for actor in actors: actor.visible = false
	var menu := load("res://scenes/MainMenu.tscn").instantiate() as MainMenu
	add_child(menu)
	await get_tree().process_frame
	menu._open_arsenal()
	for wid in ["ak47", "m4a1", "awp"]:
		var rows: Array = report.weapons.filter(func(row): return row.weapon == wid)
		GameData.select_weapon_skin(wid, rows[0].id)
		GameData.select_glove("cs2go_5030_1417")
		menu._load_viewer_weapon(wid)
		await capture("cosmetic_arsenal_" + wid)
	menu.free()
	var player := PlayerController.new()
	add_child(player)
	player.set_team_and_class("CT", "urban")
	player.spawn_for_round(Vector3.ZERO, 0.0, true)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.weapon_ctrl.set_physics_process(false)
	for wid in ["ak47", "m4a1", "awp"]:
		player.weapon_ctrl.give_weapon(wid)
		expect(player.weapon_ctrl.equip_weapon_by_id(wid), "Production equip " + wid)
		await get_tree().create_timer(1.5).timeout
		expect(player._vm_model_root != null, "Production first-person model " + wid)
		expect(player._vm_anim != null, "Production first-person animation " + wid)
		await capture("cosmetic_" + wid)
	player.free()
	GameData.selected_weapon_skins = selected
	GameData.selected_glove_id = old_glove
	print("PASS: Cosmetics ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
