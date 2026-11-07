extends Node3D
var checks := 0
var failures: Array[String] = []

func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error("[COMBAT NATIVE] " + text)

func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(func():
		push_error("[COMBAT NATIVE] Watchdog: test did not finish")
		get_tree().quit(1)
	)
	_run.call_deferred()

func block(position_value: Vector3, size_value: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position_value
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_value
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body

func _run() -> void:
	RoundManager.set_process(false)
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 40
	camera.look_at_from_position(Vector3(0, 1.1, -5.0), Vector3(0, 0.95, 0), Vector3.UP)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.08, 0.1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	environment.ambient_light_energy = 0.8
	camera.environment = environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 140, 0)
	light.light_energy = 1.2
	add_child(light)
	block(Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	var actors: Array[CSActor] = []
	for role in ["CT", "T"]:
		var actor := CSActor.new()
		actor.team = role
		actor.is_alive = true
		actor.position.x = -0.75 if role == "CT" else 0.75
		add_child(actor)
		actor.set_team_and_class(role, "urban" if role == "CT" else "terror")
		actor._prev_phys_pos = actor.global_position
		actor.set_physics_process(false)
		actor.weapon_ctrl.give_weapon("ak47", 30, 90)
		actor.weapon_ctrl.equip_weapon_by_id("ak47")
		actors.append(actor)
		expect(actor._native_character, role + " really uses live native rig")
		expect(actor._skel.find_bone("head_0") >= 0, "Native head bone")
		expect(actor._hand_attachment.bone_name == "hand_R", "Real native weapon attachment")
		expect(actor._held_weapon_model != null, "Held weapon exists")
		expect(actor._bullet_hitboxes.entries.size() == 11, "All anatomical hit regions")
		actor._evaluate_character_pose(0.1)
		actor._bullet_hitboxes.sync_pose()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for actor in actors:
		var head: Area3D = actor._bullet_hitboxes.entries[0]["area"]
		var query := PhysicsRayQueryParameters3D.create(head.global_position + Vector3.FORWARD * 2, head.global_position + Vector3.BACK * 2, 16)
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		expect(not hit.is_empty() and hit["collider"].get_meta("hitgroup") == 1, "Head ray hits head, not movement capsule/chest")
		query.from.x += 0.34
		query.to.x += 0.34
		expect(get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "Empty space beside head is not a hit")
	var target := actors[1]
	var target_head: Area3D = target._bullet_hitboxes.entries[0]["area"]
	target.health = 1000
	target.armor = 0
	actors[0].weapon_ctrl._fire_penetrating_ray(target_head.global_position + Vector3.FORWARD * 2, Vector3.BACK, 4.0, 10.0, 1.0, 1.0, 0)
	expect(target.health == 960, "Production bullet applies native head hitgroup multiplier")
	for actor in actors:
		var rows: Array = GameData.native_actor_sockets[actor.team.to_lower()]["ak47"]["classic_basis"]
		var expected := Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2])).orthonormalized()
		var actual := actor._held_weapon_model.global_basis.orthonormalized()
		expect(actual.x.distance_to(expected.x) < 0.03 and actual.z.distance_to(expected.z) < 0.03, "Mixed gait/hold keeps rifle aimed forward " + actor.team)
	if "--capture" in OS.get_cmdline_user_args():
		await save_frame("live_ct_t")
	for actor in actors:
		var old_head := actor._skel.get_bone_global_pose(actor._skel.find_bone("head_0")).origin
		actor.is_crouching = true
		actor._visual_crouch_t = 1.0
		actor._evaluate_character_pose(0.1)
		actor._bullet_hitboxes.sync_pose()
		var head: Area3D = actor._bullet_hitboxes.entries[0]["area"]
		expect(head.global_position.y < old_head.y - 0.45, "Crouched hitboxes follow visible head")
		var ankle := actor._skel.find_bone("ankle_L")
		var foot := actor._skel.global_transform * actor._skel.get_bone_global_pose(ankle).origin
		expect(foot.y > -0.08 and foot.y < 0.4, "Crouch IK keeps ankle near floor without squashing geometry")
	if "--capture" in OS.get_cmdline_user_args():
		await save_frame("live_crouch")
	var wall := block(Vector3(5, 1, 0), Vector3(0.2, 2, 2))
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var entry := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3, 1, 0), Vector3(7, 1, 0), 1))
	var exit := BallisticModel.find_exit(space, entry, Vector3.RIGHT, 0.5)
	expect(not exit.is_empty() and absf(float(exit.get("thickness", 0.0)) - 0.2) < 0.015, "Real wall thickness and forward exit")
	expect(BallisticModel.find_exit(space, entry, Vector3.RIGHT, 0.1).is_empty(), "Thick wall cannot jump back to entry")
	expect(BallisticModel.profile("W", "762nato").x > BallisticModel.profile("M", "762nato").x, "Material penetration differs")
	expect(BallisticModel.damage_retention(Vector2(0.8, 0.75), 0.6) < BallisticModel.damage_retention(Vector2(0.8, 0.75), 0.1), "Thickness attenuates damage")
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		var first := BallisticModel.spray_kick(spec, 7, false)
		expect(first == BallisticModel.spray_kick(spec, 7, false), "Reproducible recoil " + wid)
		expect(BallisticModel.spray_kick(spec, 7, true).length() <= first.length(), "Crouch controls recoil " + wid)
	var hostage := HostageNPC.new()
	hostage.position = Vector3(0, 0, 0)
	add_child(hostage)
	hostage.set_physics_process(false)
	expect(hostage._native_model != null and hostage._bullet_hitboxes != null, "Live native hostage, not review-only")
	for actor in actors:
		actor.visible = false
	if "--capture" in OS.get_cmdline_user_args():
		await save_frame("live_hostage")
	var bird := AmbientChicken.new()
	bird.home = Vector3(0.6, 0, 0)
	add_child(bird)
	bird.set_physics_process(false)
	expect(bird._model.scale.is_equal_approx(Vector3.ONE * 1.85), "Adult chicken scale applies to model")
	if "--capture" in OS.get_cmdline_user_args():
		await save_frame("chicken_scale")
	var paths := GameData.prepare_match_resources()
	var progress := GameData.poll_match_resources(paths)
	for frame in range(600):
		if progress.x >= paths.size():
			break
		await get_tree().process_frame
		progress = GameData.poll_match_resources(paths)
	expect(progress.x == paths.size() and progress.y == 0, "Threaded match warmup completes without failed assets")
	var hud := CSHud.new()
	add_child(hud)
	expect(hud._native_ammo_icon == null, "HUD has no magazine icon")
	hud.queue_free()
	expect(GameData._scene_cache.size() <= 48, "Bounded scene cache")
	wall.queue_free()
	AudioManager.stop_all()
	print("[COMBAT NATIVE] %s: %d checks, %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func save_frame(label: String) -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/combat-native-review")
	for frame in range(3):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	image.save_png("/tmp/combat-native-review/" + label + ".png")
	image.resize(640, 360)
	image.save_jpg("/tmp/combat-native-review/" + label + ".jpg", 0.5)
