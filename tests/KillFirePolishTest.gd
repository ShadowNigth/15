extends Node3D
## Real physics ray / lethal-event integration, multikill timing and animated surface fire.
var checks := 0
var failures: Array[String] = []
var events: Array[Dictionary] = []
var shooter: PlayerController
var victim: CSActor
var hud: CSHud
var output := ""

func expect(value: bool, message: String) -> void:
	checks += 1
	print("[KILL FIRE] %s: %s" % ["OK" if value else "FAIL", message])
	if not value:
		failures.append(message)
		push_error(message)

func block(point: Vector3, dimensions: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = point
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = dimensions
	mesh.mesh = cube
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.21, 0.24)
	mesh.material_override = material
	body.add_child(mesh)
	add_child(body)
	return body

func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit(1))
	output = OS.get_environment("POLISH_CAPTURE_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	_run.call_deferred()

func snapshot(zoom: int = -1) -> Dictionary:
	return KillContext.capture(shooter, GameData.weapons["awp"], zoom)

func reset_victim() -> void:
	victim.spawn_for_round(Vector3(-6, 0.1, -6), 0, true)
	victim.armor = 0
	victim.has_helmet = false
	victim.set_physics_process(false)
	victim._evaluate_character_pose(0.1)
	victim._bullet_hitboxes.sync_pose()
	await get_tree().physics_frame
	await get_tree().physics_frame

func shoot(context: Dictionary, damage: float = 200.0) -> void:
	var head: Area3D = victim._bullet_hitboxes.entries[0]["area"]
	var eye := shooter.get_eye_position()
	shooter.weapon_ctrl._fire_penetrating_ray(eye, (head.global_position - eye).normalized(), 25, damage, 1.0, 0.99, 3, context)

func capture(name: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	for frame in range(3):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	expect(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "OpenGL framebuffer " + name)

func _run() -> void:
	seed(7771)
	GameData.game_mode = "classic"
	RoundManager.map_mode = "de"
	RoundManager.state = RoundManager.State.WAITING
	RoundManager.game_world = self
	RoundManager.set_process(false)
	RoundManager.actors.clear()
	RoundManager.smoke_volumes.clear()
	RoundManager.kill_detailed.connect(func(_kn, _kt, _vn, _vt, _w, _hs, facts): events.append(facts.duplicate(true)))
	block(Vector3(0, -0.12, 0), Vector3(32, 0.24, 26))
	var camera := Camera3D.new()
	add_child(camera)
	camera.look_at_from_position(Vector3(11, 9, 15), Vector3(2, 0.5, 0))
	camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.045, 0.065)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.75, 0.85)
	environment.ambient_light_energy = 0.65
	camera.environment = environment
	shooter = PlayerController.new()
	add_child(shooter)
	shooter.set_team_and_class("CT", "urban")
	shooter.actor_name = "Player"
	shooter.spawn_for_round(Vector3(-6, 0.1, 0), 0, true)
	shooter.set_physics_process(false)
	shooter.weapon_ctrl.give_weapon("awp", 10, 30)
	shooter.weapon_ctrl.equip_weapon_by_id("awp")
	shooter._vm_container.visible = false
	camera.make_current()
	victim = CSActor.new()
	add_child(victim)
	victim.set_team_and_class("T", "terror")
	victim.actor_name = "Target"
	hud = CSHud.new()
	add_child(hud)
	hud.bind_player(shooter)
	await reset_victim()
	shooter.flash_alpha = 0.9
	var captured := snapshot()
	shooter.flash_alpha = 0.0
	expect(captured["attacker_blind"] and captured["no_scope"], "Blind and no-scope frozen at attack time")
	shoot(captured)
	expect(not victim.is_alive and events.size() == 1, "Real skeletal bullet produces one lethal event")
	if not events.is_empty():
		expect(events.back()["headshot"] and events.back()["attacker_blind"] and events.back()["no_scope"], "Lethal context reaches confirmed HUD event")
		expect(not events.back().has("_smoke"), "Private smoke snapshots never leak to HUD")
	await reset_victim()
	victim.flash_alpha = 2.0
	shoot(snapshot(0))
	if events.size() >= 2:
		expect(not events.back()["attacker_blind"] and not events.back()["no_scope"], "Victim blindness is not attacker blindness; scoped shot is not no-scope")
	expect(hud._killcards.combo_count == 2 and hud._killcards.combo_label == "DOUBLE KILL", "Real second kill drives double-kill animation")
	await capture("kill_double")
	await reset_victim()
	var wall := block(Vector3(-6, 1.2, -3), Vector3(2.0, 2.4, 0.06))
	wall.set_meta("surface_mat", "W")
	await get_tree().physics_frame
	shoot(snapshot())
	expect(not victim.is_alive and events.size() == 3, "Bullet actually penetrates thin wall and kills")
	if events.size() >= 3:
		expect(events.back()["penetration"], "Only completed world traversal grants wallbang")
	expect(hud._killcards.combo_label == "TRIPLE KILL", "Real third kill drives triple-kill animation")
	await capture("kill_triple")
	wall.queue_free()
	await get_tree().physics_frame
	await reset_victim()
	var cloud := SmokeCloudVolume.new()
	add_child(cloud)
	cloud.setup_cloud(Vector3(-6, 0.1, -3))
	cloud.set_physics_process(false)
	cloud.age = 2.0
	captured = snapshot()
	cloud._v_carve.fill(1.0)
	expect(KillContext.crosses_smoke(captured, shooter.get_eye_position(), victim.get_eye_position()), "Smoke snapshot survives wake/clear after trigger")
	expect(not KillContext.crosses_smoke(snapshot(), shooter.get_eye_position(), victim.get_eye_position()), "Cleared smoke grants no false badge")
	expect(not KillContext.crosses_smoke({"_smoke": [{"positions": PackedVector3Array([Vector3(0, 1, -20)]), "opacity": PackedFloat32Array([1])}]}, Vector3(0, 1, 0), Vector3(0, 1, -5)), "Smoke behind victim is excluded")
	shoot(captured)
	if events.size() >= 4:
		expect(events.back()["through_smoke"] and not events.back()["penetration"], "Smoke reaches lethal event; wallbang never leaks between shots")
	cloud.queue_free()
	await get_tree().process_frame
	await reset_victim()
	var count_before := events.size()
	shoot(snapshot(0), 0.25)
	expect(victim.is_alive and events.size() == count_before, "Nonlethal hit creates neither killcard nor kill event")
	victim.apply_explosion_damage(shooter, 500, "molotov")
	if events.size() > count_before:
		expect(not events.back()["no_scope"] and not events.back()["through_smoke"], "Fire death does not inherit previous bullet flags")
	for flag in KillContext.FLAGS:
		expect(KillContext.icon(flag) != null, "Pinned original icon " + flag)
	var cards := hud._killcards
	cards._process(4.1)
	cards.register_kill(null)
	expect(cards.combo_count == 1 and cards.combo_label == "", "Combo expires without erasing round kill total")
	cards.reset_round()
	expect(cards.cards.is_empty() and cards.combo_count == 0 and cards.latest_flags.is_empty(), "Round reset clears cards and timing")
	RoundManager.map_mode = "dm"
	for i in range(12):
		cards.register_kill(null, {"headshot": true})
	expect(cards.cards.size() == 5 and cards.kills == 12 and cards.combo_count == 12, "Long DM retains five recent cards and accurate multikill count")
	RoundManager.map_mode = "de"
	cards.reset_round()
	# Both grenade kinds retain the exact same collision-aware procedural meshes.
	block(Vector3(4.5, 0.65, 0), Vector3(0.18, 1.3, 20))
	var fires: Array[IncendiaryArea] = []
	for kind in ["molotov", "incendiary"]:
		var fire := IncendiaryArea.new()
		add_child(fire)
		fire.global_position = Vector3(2, 0.02, 2) if kind == "molotov" else Vector3(7, 0.02, -1)
		fire.setup_fire(null, kind, 333 if kind == "molotov" else 777)
		fires.append(fire)
	for frame in range(150):
		await get_tree().physics_frame
	for fire in fires:
		expect(fire._patches.size() > 5 and fire._flames.size() == fire._patches.size(), "Original ribbon geometry/propagation retained: " + fire.area_type)
		var material: ShaderMaterial = fire._flames[0]["material"]
		var atlas := material.get_shader_parameter("original_fire_atlas") as Texture2D
		expect(atlas != null and atlas.resource_path.ends_with("grenade_fire_atlas.png"), "Original flame atlas bound: " + fire.area_type)
		expect(is_equal_approx(float(material.get_shader_parameter("atlas_mix")), 0.42), "Hybrid, not replacement, flames: " + fire.area_type)
		for patch in fire._patches:
			var world := fire.to_global(patch["pos"] as Vector3)
			expect(world.x < 4.5 if fire.area_type == "molotov" else world.x > 4.5, "No fire propagation across wall")
	await capture("fire_hybrid_a")
	for frame in range(25):
		await get_tree().physics_frame
	await capture("fire_hybrid_b")
	print("[KILL FIRE] %s: %d checks; %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
