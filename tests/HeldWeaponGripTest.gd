extends Node3D
var checks := 0
var failures := 0
var bot_navigator: BotNavigator = null
var camera: Camera3D
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[HELD GRIP] " + message)
func _ready() -> void:
	_run.call_deferred()
func capture(label: String) -> void:
	var path := "/tmp/modern-captures"
	DirAccess.make_dir_recursive_absolute(path)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path.path_join("held_" + label + ".png"))
func equip(actor: CSActor, wid: String) -> void:
	if bool(GameData.weapons[wid].get("grenade", false)):
		actor.weapon_ctrl.grenades[wid] = 1
	actor.weapon_ctrl.give_weapon(wid, 30, 90)
	actor.weapon_ctrl.equip_weapon_by_id(wid)
	actor._update_held_weapon_model(wid)
	actor._modern_pose.action = ""
	for frame in 24:
		actor._evaluate_character_pose(1.0 / 60)
	actor._skel.force_update_all_bone_transforms()
	await get_tree().process_frame
	actor._stabilize_held_weapon()
	var prop := actor._held_weapon_model
	expect(is_instance_valid(prop), "mesh " + wid)
	if not is_instance_valid(prop): return
	var hand := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("hand_R"))
	expect(prop.global_position.distance_to(hand.origin) < 0.001, "right wrist anchor " + wid)
	expect(prop.global_basis.is_finite(), "finite transform " + wid)
	var scale := prop.global_basis.get_scale()
	expect(scale.x > 0.4 and scale.x <= 1.081 and absf(scale.x-scale.y)<0.001 and absf(scale.x-scale.z)<0.001, "metric uniform size " + wid + str(scale))
	var info := HeldWeaponGrip.entry(wid)
	if int(GameData.weapons[wid].slot) in [1,2]:
		var tip: Array = info.parts.R.tip
		var forward := prop.global_basis * Vector3(tip[0],tip[1],tip[2])
		print("[HELD GRIP] DIRECTION ", actor.class_id, " ", wid, " ", forward.normalized())
		expect(forward.normalized().dot(Vector3.FORWARD) > 0.5, "actual geometry faces forward " + wid)
	if info.parts.has("L"):
		expect(is_instance_valid(actor._held_left_attachment), "independent left prop " + wid)
	else:
		expect(not is_instance_valid(actor._held_left_attachment), "no stale left prop " + wid)
func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	camera = Camera3D.new()
	camera.fov = 44
	add_child(camera)
	camera.look_at_from_position(Vector3(1.7,1.75,-2.65), Vector3(0,1.3,-0.25))
	camera.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16,0.19,0.23)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.9
	camera.environment = env
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-30,0)
	sun.light_energy = 1.5
	add_child(sun)
	for cid in GameData.modern_agents.classes:
		var actor := CSBot.new()
		var avatar: String = GameData.modern_agents.classes[cid]
		actor.team = GameData.modern_agents.agents[avatar].team
		add_child(actor)
		actor.set_team_and_class(actor.team,cid)
		actor.spawn_for_round(Vector3.ZERO,0,true)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.weapon_ctrl.set_process(false)
		var roster: Array = GameData.weapons.keys() if cid in ["sas","terror"] else ["ak47","awp","glock18","mp5navy","knife","hegrenade","molotov","elite"]
		for wid in roster:
			await equip(actor,wid)
			if cid == "sas": await capture(wid)
			if cid == "terror" and wid in ["mp5navy","tec9","knife","molotov"]: await capture("phoenix_"+wid)
		if cid == "sas":
			for option in GameData.get_knife_options():
				GameData.select_knife(option.id)
				await equip(actor,"knife")
				await capture("knife_"+option.id)
			GameData.select_knife("original")
		await equip(actor,"ak47")
		actor.is_crouching = true
		actor._modern_pose.action = ""
		for frame in 24: actor._evaluate_character_pose(1.0/60)
		actor.look_yaw = 0.5
		actor.look_pitch = -0.25
		for frame in 24: actor._evaluate_character_pose(1.0/60)
		if cid == "sas": await capture("crouch_turn")
		actor.queue_free()
		await get_tree().process_frame
	print("[HELD GRIP] PASS: %d checks; %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
