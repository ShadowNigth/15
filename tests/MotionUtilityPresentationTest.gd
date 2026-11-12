extends Node3D
var checks := 0
var failures := 0
var camera: Camera3D
func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[MOTION UTILITY] " + text)
func _ready() -> void:
	run.call_deferred()
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	expect(get_viewport().get_texture().get_image().save_png("/tmp/modern-captures/" + label + ".png") == OK, "capture " + label)
func step(actor: CSActor, direction: Vector3, jump: bool, crouch: bool, count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
		actor.apply_goldsrc_movement(direction, jump and frame == 0, crouch, false, 1.0 / 60)
		actor._evaluate_character_pose(1.0 / 60)
func run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 0.2, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.1
	var floor_mesh := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = box.size
	floor_mesh.mesh = floor_box
	floor_body.add_child(floor_mesh)
	add_child(floor_body)
	camera = Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 48
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.09, 0.12, 0.16)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = 0.85
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	add_child(light)
	for faction in ["CT", "T"]:
		for info in GameData.classes[faction]:
			var actor := CSBot.new()
			actor.team = faction
			add_child(actor)
			actor.set_team_and_class(faction, info.id)
			actor.spawn_for_round(Vector3(0, 0.03, 0), 0, true)
			actor.set_process(false)
			actor.set_physics_process(false)
			actor.weapon_ctrl.set_physics_process(false)
			actor.weapon_ctrl.give_weapon("ak47", 30, 90)
			actor.weapon_ctrl.equip_weapon_by_id("ak47")
			await step(actor, Vector3.ZERO, false, false, 15)
			await step(actor, Vector3(0.7, 0, -0.7), false, false, 22)
			expect(actor._modern_pose._direction_weight > 0.35, "diagonal blends cardinal clips " + info.id)
			if info.id == "sas":
				camera.look_at_from_position(actor.global_position + Vector3(3, 1.9, -4), actor.global_position + Vector3.UP)
				await capture("motion_diagonal")
			await step(actor, Vector3.ZERO, false, true, 20)
			expect("crouch" in actor._modern_pose.selected_gait, "crouched gait " + info.id)
			if info.id == "sas":
				await capture("motion_crouch")
			await step(actor, Vector3.FORWARD, true, true, 8)
			expect(not actor.is_on_floor(), "physical crouch jump " + info.id)
			expect("crouch" in actor._modern_pose.selected_gait, "airborne crouch animation " + info.id)
			if info.id == "sas":
				camera.look_at_from_position(actor.global_position + Vector3(3, 1.9, -4), actor.global_position + Vector3.UP)
				await capture("motion_crouch_jump")
			await step(actor, Vector3.ZERO, false, false, 60)
			expect(actor.is_on_floor(), "landed " + info.id)
			# While falling for longer than a clip, never wrap back into takeoff.
			actor.global_position.y = 50
			actor.velocity = Vector3(0, -1, 0)
			await step(actor, Vector3.ZERO, false, false, 65)
			expect(actor._modern_pose.selected_gait.begins_with("inair_"), "fall keeps airborne gait " + info.id)
			expect(actor._modern_pose.gait_phase > 0.95, "airborne end pose holds instead of cycling " + info.id)
			actor.free()
	var player := PlayerController.new()
	add_child(player)
	player.set_team_and_class("T", "terror")
	player.spawn_for_round(Vector3(0, 0.03, 0), 0, true)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.weapon_ctrl.set_physics_process(false)
	player.weapon_ctrl.give_weapon("c4")
	player.weapon_ctrl.equip_weapon_by_id("c4")
	expect(player._c4_display != null, "actual C4 has omitted native LCD mesh")
	player.play_viewmodel_sequence(["pressbutton"])
	player._vm_anim.pause()
	for t in [0.0, 1.5, 2.9]:
		player.weapon_ctrl.plant_progress = t
		player._vm_anim.seek(t, true)
		player._c4_display.set_progress(t)
		expect(player._c4_display.row >= 0, "LCD row " + str(t))
		await capture("c4_digits_" + str(int(t * 10)))
	expect(player._c4_display.row == 8, "full entered code at plant completion")
	player.weapon_ctrl.plant_progress = 0
	player._c4_display.set_progress(0)
	expect(player._c4_display.row == 0, "cancel resets LCD")
	player.weapon_ctrl.grenades["molotov"] = 1
	player.weapon_ctrl.give_weapon("molotov")
	player.weapon_ctrl.equip_weapon_by_id("molotov")
	player._vm_anim.play("idle")
	player._vm_anim.advance(0)
	player._vm_anim.pause()
	var glass: ShaderMaterial
	for mesh in SportGloves._find_meshes(player._vm_model_root):
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(surface)
			if mat is ShaderMaterial and (mat as ShaderMaterial).get_shader_parameter("glass_opacity") != null:
				glass = mat
	if glass:
		expect(float(glass.get_shader_parameter("glass_opacity")) >= 0.58, "bottle less transparent")
		var tint: Vector3 = glass.get_shader_parameter("glass_tint")
		expect(tint.y > tint.x * 2.0 and tint.y > tint.z * 1.8, "strong green tint")
	else:
		expect(false, "molotov glass shader found")
	await capture("molotov_green")
	player.free()
	print("[MOTION UTILITY] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
