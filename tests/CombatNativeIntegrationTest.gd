extends Node3D
# Keep the existing scene entry point, now guarding the requested classic rollback.
var checks := 0
var failures: Array[String] = []

func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures.append(text)
		push_error("[COMBAT NATIVE] " + text)

func _ready() -> void:
	get_tree().create_timer(45.0).timeout.connect(func(): get_tree().quit(1))
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
	camera.look_at_from_position(Vector3(0, 1.1, -5), Vector3(0, 0.95, 0), Vector3.UP)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.06, 0.08, 0.1)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	environment.ambient_light_energy = 0.8
	camera.environment = environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 140, 0)
	add_child(light)
	block(Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	var actors: Array[CSActor] = []
	for role in ["CT", "T"]:
		var actor := CSActor.new()
		actor.position.x = -0.75 if role == "CT" else 0.75
		add_child(actor)
		actor.set_team_and_class(role, "urban" if role == "CT" else "terror")
		actor._prev_phys_pos = actor.global_position
		actor.set_physics_process(false)
		actor.weapon_ctrl.give_weapon("ak47", 30, 90)
		actor.weapon_ctrl.equip_weapon_by_id("ak47")
		actors.append(actor)
		expect(actor._skel.find_bone("Bip01 Head") >= 0, "Actual classic " + role + " skeleton")
		expect(actor._skel.find_bone("head_0") < 0, "No native tactical rig in live " + role)
		expect(actor._hand_attachment.bone_name == "Bip01 R Hand", "Classic hand socket")
		expect(actor._bullet_hitboxes.entries.size() == 11, "Skeletal bullet regions retained on classic rig")
		actor._evaluate_character_pose(0.1)
		actor._bullet_hitboxes.sync_pose()
	await get_tree().physics_frame
	await get_tree().physics_frame
	for actor in actors:
		var head: Area3D = actor._bullet_hitboxes.entries[0]["area"]
		var query := PhysicsRayQueryParameters3D.create(head.global_position + Vector3.FORWARD * 2, head.global_position + Vector3.BACK * 2, 16)
		query.collide_with_areas = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		expect(not hit.is_empty() and hit["collider"].get_meta("hitgroup") == 1, "Classic bone head region is shootable")
	if "--capture" in OS.get_cmdline_user_args():
		await save_frame("live_ct_t")
	for actor in actors:
		actor.is_crouching = true
		actor._visual_crouch_t = 1.0
		actor._evaluate_character_pose(0.1)
	if "--capture" in OS.get_cmdline_user_args():
		await save_frame("live_crouch")
	for actor in actors:
		actor.visible = false
	var hostage := HostageNPC.new()
	add_child(hostage)
	hostage.set_physics_process(false)
	var rigs := hostage.find_children("*", "Skeleton3D", true, false)
	expect(not rigs.is_empty(), "Classic hostage has original animated skeleton")
	expect(hostage._anim_player != null and hostage._anim_player.has_animation("gutshot"), "Classic hostage retains authored death")
	if "--capture" in OS.get_cmdline_user_args():
		await save_frame("live_hostage")
	hostage.visible = false
	var wall := block(Vector3(5, 1, 0), Vector3(0.2, 2, 2))
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var entry := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(3, 1, 0), Vector3(7, 1, 0), 1))
	var exit := BallisticModel.find_exit(space, entry, Vector3.RIGHT, 0.5)
	expect(not exit.is_empty() and absf(float(exit.get("thickness", 0.0)) - 0.2) < 0.015, "Penetration still measures real wall thickness")
	expect(BallisticModel.find_exit(space, entry, Vector3.RIGHT, 0.1).is_empty(), "Cannot penetrate thicker-than-allowed wall")
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		var kick := BallisticModel.spray_kick(spec, 7, false)
		expect(kick == BallisticModel.spray_kick(spec, 7, false), "Repeatable recoil " + wid)
	var player := PlayerController.new()
	add_child(player)
	player.set_team_and_class("CT", "urban")
	player.set_physics_process(false)
	player.set_process(false)
	player.camera.current = true
	block(Vector3(0, 3, -10), Vector3(50, 40, 0.1))
	await get_tree().physics_frame
	var center := get_viewport().get_visible_rect().size * 0.5
	for eye_height in [1.66, 0.96]:
		for fov in [74.0, 30.0]:
			player.camera.global_position = Vector3(0, eye_height, 0)
			player.camera.rotation = Vector3(0.13, 0.2, 0.04)
			player.camera.fov = fov
			player.weapon_ctrl.punch_angles = Vector2(6, -2)
			var origin := player.get_eye_position()
			var aim := -player.get_aim_basis(player.weapon_ctrl.punch_angles).z
			expect(origin.distance_to(player.camera.project_ray_origin(center)) < 0.0001, "Human bullet starts at optical eye, including duck interpolation")
			expect(aim.dot(player.camera.project_ray_normal(center)) > 0.99999, "No extra recoil multiplier or camera shake divergence")
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin + aim * 50, 1))
			expect(not hit.is_empty(), "Optical ray hits real wall")
			if not hit.is_empty():
				expect(player.camera.unproject_position(hit["position"]).distance_to(center) < 0.5, "Real impact projects onto crosshair within half a pixel")
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
