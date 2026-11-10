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
	expect(GameData.modern_agents.get("agents", {}).size() == 8, "eight genuine modern appearances")
	expect(GameData.modern_agents.get("classes", {}).size() == 8, "all faction class aliases retained")
	expect(ModernAgentPose.role("CT", "sas") == "sas" and ModernAgentPose.role("T", "terror") == "phoenix", "original modern SAS and Phoenix retained")
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 0.5, 200)
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
		actor.set_process(false)
		actor.weapon_ctrl.set_process(false)
		actor.weapon_ctrl.give_weapon("m4a1" if i == 0 else "ak47", 30, 90)
		actor.weapon_ctrl.equip_weapon_by_id("m4a1" if i == 0 else "ak47")
		actors.append(actor)
		expect(actor._modern_pose != null and actor._skel.find_bone("head_0") >= 0, "modern default actor")
		expect(actor._hand_attachment.bone_name == "hand_R", "native socket")
		expect(actor._bullet_hitboxes.entries.size() == 11, "all bullet regions")
		expect(actor._body_root.scale.is_equal_approx(Vector3.ONE * 1.08), "bot body enlarged eight percent")
		expect(actor.scale.is_equal_approx(Vector3.ONE), "GoldSrc movement body not scaled")
		expect(is_equal_approx(actor._capsule.height, CSActor.STAND_HEIGHT), "original movement hull retained")
		expect(is_equal_approx(actor._bullet_hitboxes.entries[0].shape.radius, 0.115 * 1.08), "headshot radius follows larger body")
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
			var clips: Dictionary = ModernAgentPose.table(ModernAgentPose.role(actor.team, actor.class_id), wid).get("clips", {})
			expect(clips.has("idle"), "native hold " + wid)
			if int(spec.get("slot", 0)) in [1, 2]:
				expect(clips.has("shoot") and clips.has("reload"), "native firearm actions " + wid)
		actor.weapon_ctrl.reset_loadout(actor.team, false)
		actor.weapon_ctrl.give_weapon("ak47", 30, 90)
		actor.weapon_ctrl.equip_weapon_by_id("ak47")
		actor._modern_pose.action = ""
		actor._evaluate_character_pose(0.1)
		actor._skel.force_update_all_bone_transforms()
		var head := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("head_0")).origin
		expect(head.y > 1.2 and head.y < 2.2, "standing head height")
	# Real socket direction, not just a non-null prop/valid scale. The classic
	# grip previously passed those checks while aiming ninety degrees sideways.
	for actor in actors:
		for wid in GameData.weapons:
			actor.weapon_ctrl.give_weapon(wid, 30, 90)
			actor.weapon_ctrl.equip_weapon_by_id(wid)
			actor._modern_pose.action = ""
			for frame in 18:
				actor._evaluate_character_pose(1.0 / 60)
			var hand := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("hand_R"))
			var muzzle_axis := (hand.basis * ModernAgentPose.socket_basis(ModernAgentPose.role(actor.team, actor.class_id), wid) * Vector3.FORWARD).normalized()
			if int(GameData.weapons[wid].get("slot", 0)) in [1, 2]:
				expect(muzzle_axis.dot(Vector3.FORWARD) > 0.80, "barrel faces actor forward " + wid)
			if int(GameData.weapons[wid].slot) == 1:
				var support: Array = ModernAgentPose.table(ModernAgentPose.role(actor.team, actor.class_id), wid).support
				var target := hand * Vector3(support[0], support[1], support[2])
				var left := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("hand_L")).origin
				expect(target.distance_to(left) < 0.075, "support hand contacts foregrip " + wid + str(target.distance_to(left)))
		actor.weapon_ctrl.equip_weapon_by_id("ak47")
		actor._modern_pose.action = ""
		actor._evaluate_character_pose(0.2)
		# A sharp turn must apply to the body BEFORE world-space pitch and IK.
		actor.look_yaw = PI * 0.5
		actor.look_pitch = 0.25
		actor._evaluate_character_pose(1.0 / 60)
		expect(absf(actor._body_root.rotation.y - actor.look_yaw) < 0.001, "same-frame turn orientation")
		var turn_hand := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("hand_R"))
		var turn_support: Array = ModernAgentPose.table(ModernAgentPose.role(actor.team, actor.class_id), "ak47").support
		var turn_target := turn_hand * Vector3(turn_support[0], turn_support[1], turn_support[2])
		var turn_left := actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("hand_L")).origin
		expect(turn_left.distance_to(turn_target) < 0.075, "support grip stays attached during sharp aimed turn")
		actor.look_yaw = 0.0
		actor.look_pitch = 0.0

	for frame in 10:
		for actor in actors:
			actor.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0/60)
			actor._evaluate_character_pose(1.0/60)
		await get_tree().physics_frame
	await capture("modern_live_idle")
	for frame in 35:
		for actor in actors:
			actor.apply_goldsrc_movement(Vector3.FORWARD, false, false, false, 1.0/60)
			actor._evaluate_character_pose(1.0/60)
		await get_tree().physics_frame
	for actor in actors:
		expect(actor.global_position.z < -0.3, "actual GoldSrc movement")
		expect("run" in actor._modern_pose.selected_gait or "walk" in actor._modern_pose.selected_gait, "moving native gait selected")
	var center_z := actors[0].global_position.z
	camera.look_at_from_position(Vector3(3, 2.1, center_z - 4.5), Vector3(0, 0.95, center_z))
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
		expect(is_equal_approx(actor._modern_pose.action_duration, actor.weapon_ctrl.reload_timer), "magazine animation uses actual reload duration")
		actor._evaluate_character_pose(0.4)
	await capture("modern_live_reload")
	for actor in actors:
		actor._die(null, "ak47", false)
		var death_clip: Animation = actor._anim_res_map[actor._death_anim_key]
		for frame in int(ceil(death_clip.length * 60)) + 6:
			actor._evaluate_character_pose(1.0/60)
		expect(not actor.is_alive and actor._anim_res_map.has(actor._death_anim_key), "skeletal death selected")
		var pelvis_height := (actor._skel.global_transform * actor._skel.get_bone_global_pose(actor._skel.find_bone("pelvis")).origin).y - actor.global_position.y
		expect(pelvis_height < 0.75, "animated corpse pelvis settles")
		expect(actor._held_weapon_model == null, "death drops held prop")
		actor._bullet_hitboxes.sync_pose()
		for entry in actor._bullet_hitboxes.entries:
			expect(entry.area.collision_layer == 0, "dead hitbox disabled")
	await capture("modern_live_death")
	for key in ["head", "gutshot", "back", "forward", "left", "right", "crouch_die", "death1", "death2", "death3"]:
		for index in actors.size():
			var actor := actors[index]
			actor.spawn_for_round(Vector3(-0.8 if index == 0 else 0.8, 0.03, center_z), 0, true)
			actor.set_process(false)
			actor.set_physics_process(false)
			actor.weapon_ctrl.set_process(false)
			actor._evaluate_character_pose(0.2)
			actor._die(null, "ak47", key == "head")
			actor._death_anim_key = key
			actor._modern_pose.death_time = 0
			expect(actor._anim_res_map.has(key), "retargeted death available " + key)
			var start := actor._skel.get_bone_pose_rotation(actor._skel.find_bone("spine_0"))
			for frame in 32:
				actor._evaluate_character_pose(1.0/60)
			var middle := actor._skel.get_bone_pose_rotation(actor._skel.find_bone("spine_0"))
			expect(start.angle_to(middle) > 0.02, "death articulates torso " + key)
			var death_clip: Animation = actor._anim_res_map[key]
			for frame in int(ceil(death_clip.length * 60)) + 6:
				actor._evaluate_character_pose(1.0/60)
			expect(actor._skel.get_bone_global_pose(actor._skel.find_bone("head_0")).origin.is_finite(), "finite corpse " + key)
		if key in ["head", "left", "crouch_die"]:
			# Pose sampling above is manual. Let real dropped bodies fall under
			# engine physics before recording; do not mistake frozen drops for flight.
			for frame in 60:
				await get_tree().physics_frame
			await capture("modern_death_" + key)
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
