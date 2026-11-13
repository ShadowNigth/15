extends Node3D
var checks: int = 0
var failures: Array[String] = []
var capture: bool = false

func _ready() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("[NATIVE WORLD] " + message)

func shot(player: PlayerController, wid: String) -> void:
	player.weapon_ctrl.give_weapon(wid, 10, 60)
	player.weapon_ctrl.equip_weapon_by_id(wid)
	player.weapon_ctrl.fire_cooldown = 0.0
	player.weapon_ctrl._execute_bullet_shot(GameData.weapons[wid], false)

func _run() -> void:
	GameData.native_casings_enabled = true
	GameData.ambient_chickens_enabled = true
	GameData.native_ammo_icons = true
	GameData.native_defuser_model = true
	RoundManager.set_process(false)
	for model in ["ak47", "awp", "deagle", "glock", "p90", "mag7", "nova", "xm1014"]:
		var packed := GameData.get_model_scene("native/casing_" + model + "_casing")
		expect(packed != null, "Engine loads original shell " + model)
	for wid in GameData.native_casings["weapons"]:
		var route: Dictionary = GameData.native_casings["weapons"][wid]
		for clip in route["clips"]:
			for cue in route["clips"][clip]:
				expect(float(cue["at"]) >= 0.0, "Nonnegative source time " + wid + ":" + clip)
				expect(NativeCasings.frame_from_rows(cue["frame"]).basis.determinant() != 0.0, "Invertible port calibration " + wid)
	expect(NativeCasings.events_for("awp", "shoot1")[0]["at"] == 0.74, "AWP source event + emitter delay = .74s")
	expect(NativeCasings.events_for("taser", "shoot1").is_empty(), "No Zeus shell")
	expect(NativeCasings.events_for("revolver", "shoot1").is_empty(), "No R8 shot shell")
	for wid in ["ak47", "bizon", "m249", "awp", "p90", "revolver", "m3", "usp"]:
		expect(GameData.ammo_icon_for(wid) != null, "Engine decodes icon " + wid)
	expect(GameData.ammo_icon_for("knife") == null, "No ammunition icon for melee")
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 2
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban")
	world.team_menu.close_menu()
	var player := world.player
	player.ui_blocking_input = true
	for bot in world.bots:
		bot.set_physics_process(false)
		bot.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect(world.ambient_chickens.is_empty(), "Chicken without native death animation has been removed")
	var actor_count := RoundManager.actors.size()
	var system := world.native_casing_system
	system.set_physics_process(false)
	shot(player, "awp")
	expect(system.pending.size() == 1, "Real AWP shot queues one source casing")
	var count := system.emitted_count
	system._physics_process(0.70)
	expect(system.emitted_count == count, "AWP does not eject early")
	player._vm_anim.advance(0.74)
	system._physics_process(0.041)
	expect(system.emitted_count == count + 1 and system.pending.is_empty(), "AWP ejects exactly once at native time")
	var runner := world.get_node_or_null("__ShellRunner")
	expect(runner != null and runner._entries.size() > 0, "Original mesh enters bounded ballistic shell runner")
	if runner != null and not runner._entries.is_empty():
		var shell: Node3D = runner._entries[-1]["node"]
		expect(shell.global_position.distance_to(player.get_eye_position()) < 2.0, "Animated ejection port stays at the real gun")
	shot(player, "awp")
	player.weapon_ctrl.equip_weapon_by_id("knife")
	player.weapon_ctrl.equip_weapon_by_id("awp")
	count = system.emitted_count
	system._physics_process(1.0)
	expect(system.emitted_count == count and system.pending.is_empty(), "Switch-away/back cancels stale pending shells")
	shot(player, "awp")
	player.is_alive = false
	system._physics_process(1.0)
	expect(system.pending.is_empty(), "Death cancels delayed ejection")
	player.is_alive = true
	GameData.native_casings_enabled = false
	system.queue_shot(player, "awp", "shoot1")
	expect(system.pending.is_empty(), "Option disables native queue")
	GameData.native_casings_enabled = true
	for wid in GameData.native_casings["weapons"].keys() + ["revolver", "taser"]:
		system.clear_all()
		shot(player, wid)
		var expected := 0 if wid in ["revolver", "taser"] else 1
		if not system.pending.is_empty():
			var cue: Dictionary = system.pending[0]["cue"]
			var bound := false
			for skeleton in player._vm_model_root.find_children("*", "Skeleton3D", true, false):
				bound = bound or skeleton.find_bone(String(cue["bone"])) >= 0
			expect(bound, "Source port resolves an animated bone, not fallback: " + wid)
			var frame: Transform3D = player.native_casing_frame(cue)
			expect(frame.origin.distance_to(player.get_eye_position()) < 2.0, "Animated port has metre-scale placement: " + wid)
		expect(system.pending.size() == expected, "Production shot ejection count " + wid)
		system._physics_process(1.0)
	var kit := DroppedWeapon.new()
	world.add_child(kit)
	kit.position = player.position + Vector3.RIGHT
	kit.setup_drop("defuser", 0, 0, Vector3.ZERO)
	expect(kit._visual_root.get_child_count() > 0, "Native kit uses existing dropped-item physics")
	player.has_defuser = false
	expect(player.try_pickup_dropped(kit), "Native kit still picked up by CT")
	expect(player.has_defuser, "Pickup grants real defuser flag")
	for resource in ["ct", "t", "hostage", "chicken"]:
		var scene := GameData.get_model_scene("native/" + resource)
		expect(scene != null, "Engine loads reviewed model " + resource)
		if scene == null:
			continue
		var instance := scene.instantiate() as Node3D
		add_child(instance)
		var players := instance.find_children("*", "AnimationPlayer", true, false)
		expect(not players.is_empty(), "Reviewed model has real animations " + resource)
		if not players.is_empty():
			var anim := players[0] as AnimationPlayer
			var expected := 170 if resource in ["ct", "t"] else 7 if resource == "hostage" else 3
			expect(anim.get_animation_list().size() >= expected, "Native clip count " + resource)
			for clip in ["walk", "run", "idle"]:
				if anim.has_animation(clip):
					anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
					anim.play(clip)
					anim.advance(0.0)
					var skeletons := instance.find_children("*", "Skeleton3D", true, false)
					var before: Array[Transform3D] = []
					if not skeletons.is_empty():
						for bone in range(skeletons[0].get_bone_count()):
							before.append(skeletons[0].get_bone_pose(bone))
					anim.advance(0.35)
					if clip != "idle" and not skeletons.is_empty():
						var moving := 0
						for bone in range(before.size()):
							if not before[bone].is_equal_approx(skeletons[0].get_bone_pose(bone)):
								moving += 1
						expect(moving >= 3, "Native skeletal motion, not frozen bind pose: " + resource + ":" + clip)
					expect(anim.current_animation == clip, "Real playback " + resource + ":" + clip)
		instance.queue_free()
	if capture:
		await _capture_gameplay(world, player)
	system.clear_all()
	expect(system.pending.is_empty(), "Round cleanup clears pending events")
	print("[NATIVE WORLD TEST] %s: %d checks; %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	AudioManager.stop_all()
	get_tree().quit(0 if failures.is_empty() else 1)

func _capture_gameplay(world: GameWorld, player: PlayerController) -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/native-world-review")
	player.weapon_ctrl.equip_weapon_by_id("ak47")
	player.look_pitch = deg_to_rad(-20.0)
	player.camera.current = true
	player.velocity = Vector3.ZERO
	player.viewmodel_pivot.visible = true
	player._vm_container.visible = true
	player._vm_layer.visible = true
	world.native_casing_system.set_physics_process(true)
	shot(player, "ak47")
	for i in range(8):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	expect(not image.is_empty(), "Real OpenGL gameplay render")
	image.save_png("/tmp/native-world-review/italy_hud_chicken.png")
	image.resize(480, 270)
	image.save_jpg("/tmp/native-world-review/italy_hud_chicken.jpg", 0.35)
	# Separate animated model review, never replace live bots with incompatible rigs.
	world.hide()
	world.hud.visible = false
	player._vm_layer.visible = false
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	camera.fov = 40.0
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.075, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	environment.ambient_light_energy = 0.6
	camera.environment = environment
	camera.look_at_from_position(Vector3(0, 1.15, 3.6), Vector3(0, 0.95, 0), Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -25, 0)
	light.light_energy = 1.5
	add_child(light)
	for resource in ["ct", "t", "hostage", "defuser_item"]:
		var path: String = {"ct": "players/urban", "t": "players/terror", "hostage": "players/hostage"}.get(resource, "native/" + resource)
		var instance := GameData.get_model_scene(path).instantiate() as Node3D
		add_child(instance)
		if resource == "defuser_item":
			GameData.apply_native_world_material(instance, resource)
		if resource in ["defuser_item", "chicken"]:
			instance.scale = Vector3.ONE * 2.2
			instance.position.y = 0.65
		var players := instance.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			players[0].get_animation("walk").loop_mode = Animation.LOOP_LINEAR
			players[0].play("walk")
			players[0].advance(0.2)
		for phase in range(2):
			if not players.is_empty():
				players[0].advance(0.25)
			await get_tree().process_frame
			RenderingServer.force_draw(false)
			var rendered := get_viewport().get_texture().get_image()
			rendered.save_png("/tmp/native-world-review/%s_%d.png" % [resource, phase])
			rendered.resize(480, 270)
			rendered.save_jpg("/tmp/native-world-review/%s_%d.jpg" % [resource, phase], 0.35)
		instance.queue_free()
		await get_tree().process_frame
