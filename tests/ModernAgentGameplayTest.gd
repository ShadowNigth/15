extends Node3D
var checks := 0
var failures := 0
var bot_navigator: BotNavigator = null
var actors: Array[CSActor] = []
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[MODERN GAMEPLAY] " + message)
func capture(label: String) -> void:
	var path := OS.get_environment("MODERN_CAPTURE_DIR")
	if path.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(path)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	expect(get_viewport().get_texture().get_image().save_png(path.path_join(label+".png")) == OK, "capture " + label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(50, 0.5, 50)
	collision.shape = shape
	floor_body.position.y = -0.25
	floor_body.add_child(collision)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	floor_body.add_child(mesh)
	add_child(floor_body)
	var camera := Camera3D.new()
	camera.fov = 48
	add_child(camera)
	camera.look_at_from_position(Vector3(3, 2.1, -4.5), Vector3(0, 0.95, 0))
	camera.current = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.75
	camera.environment = env
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	add_child(light)
	for i in 2:
		var actor := CSBot.new()
		actor.team = "CT" if i == 0 else "T"
		add_child(actor)
		actor.set_team_and_class(actor.team, "urban" if i == 0 else "terror")
		actor.spawn_for_round(Vector3(-0.8 if i == 0 else 0.8, 0.03, 0), 0, true)
		actor.set_physics_process(false)
		actor.weapon_ctrl.give_weapon("m4a1" if i == 0 else "ak47", 30, 90)
		actor.weapon_ctrl.equip_weapon_by_id("m4a1" if i == 0 else "ak47")
		actors.append(actor)
		expect(actor._modern_pose != null and actor._skel.find_bone("head_0") >= 0, "modern default actor")
		expect(actor._hand_attachment.bone_name == "hand_R", "native socket")
		expect(actor._bullet_hitboxes.entries.size() == 11, "all bullet regions")
	await get_tree().physics_frame
	for actor in actors:
		for wid in GameData.weapons:
			var spec: Dictionary = GameData.weapons[wid]
			if bool(spec.get("grenade", false)):
				actor.weapon_ctrl.grenades[wid] = 1
			actor.weapon_ctrl.give_weapon(wid, 30, 90)
			actor.weapon_ctrl.equip_weapon_by_id(wid)
			actor._evaluate_character_pose(0.12)
			actor._skel.force_update_all_bone_transforms()
			await get_tree().process_frame
			actor._stabilize_held_weapon()
			expect(actor._held_weapon_model != null, "held mesh " + wid)
			if actor._held_weapon_model != null:
				var scale := actor._held_weapon_model.global_basis.get_scale()
				expect(scale.is_finite() and scale.length() > 0.05 and scale.length() < 2.0, "metric weapon scale " + wid + str(scale))
			var clips: Dictionary = ModernAgentPose.table(ModernAgentPose.role(actor.team), wid).get("clips", {})
			expect(clips.has("idle"), "native hold " + wid)
			if int(spec.get("slot", 0)) in [1, 2]:
				expect(clips.has("shoot") and clips.has("reload"), "native firearm actions " + wid)
		actor.weapon_ctrl.give_weapon("ak47", 30, 90)
		actor.weapon_ctrl.equip_weapon_by_id("ak47")
		actor._modern_pose.action = ""
		actor._evaluate_character_pose(0.1)
		actor._skel.force_update_all_bone_transforms()
		var head := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("head_0")).origin
		expect(head.y > 1.2 and head.y < 2.2, "standing head height")
	await capture("modern_live_idle")
	for frame in 35:
		for actor in actors:
			actor.apply_goldsrc_movement(Vector3.FORWARD, false, false, false, 1.0/60)
			actor._evaluate_character_pose(1.0/60)
		await get_tree().physics_frame
	for actor in actors:
		expect(actor.global_position.z < -0.3, "actual GoldSrc movement")
		expect("run" in actor._modern_pose.selected_gait or "walk" in actor._modern_pose.selected_gait, "moving native gait selected")
	await capture("modern_live_run")
	for actor in actors:
		actor.velocity = Vector3.ZERO
		actor.is_crouching = true
		actor._evaluate_character_pose(0.1)
	await capture("modern_live_crouch")
	for actor in actors:
		actor.is_crouching = false
		actor.weapon_ctrl.fire_cooldown = 0
		actor.weapon_ctrl.is_reloading = false
		actor.weapon_ctrl.trigger_primary(false, 0.016)
		expect(actor._modern_pose.action == "shoot", "real firing routes native upper action")
		actor._evaluate_character_pose(0.04)
	await capture("modern_live_shoot")
	for actor in actors:
		actor.weapon_ctrl.fire_cooldown = 0
		actor.weapon_ctrl.start_reload()
		expect(actor.weapon_ctrl.is_reloading and actor._modern_pose.action == "reload", "real reload routes native action")
		actor._evaluate_character_pose(0.4)
	await capture("modern_live_reload")
	for actor in actors:
		actor._die(null, "ak47", false)
		for frame in 60:
			actor._evaluate_character_pose(1.0/60)
		expect(not actor.is_alive and actor._body_root.rotation.x > 1.4, "bounded corpse fall")
		expect(actor._held_weapon_model == null, "death drops held prop")
		actor._bullet_hitboxes.sync_pose()
		for entry in actor._bullet_hitboxes.entries:
			expect(entry.area.collision_layer == 0, "dead hitbox disabled")
	await capture("modern_live_death")
	for actor in actors:
		actor.spawn_for_round(Vector3.ZERO, 0, true)
		actor._evaluate_character_pose(0.1)
		expect(actor.is_alive and absf(actor._body_root.rotation.x) < 0.01, "respawn resets death pose")
	var vip := CSActor.new()
	vip.is_vip = true
	add_child(vip)
	vip.spawn_for_round(Vector3(4, 0.03, 0), 0, true)
	expect(vip._modern_pose == null and vip._skel.find_bone("Bip01 Head") >= 0, "VIP preserved")
	print("PASS: Modern gameplay ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
