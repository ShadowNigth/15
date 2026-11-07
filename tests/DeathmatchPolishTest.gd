extends Node3D
## Runtime regression plus optional OpenGL evidence. No replacement characters or staged idle poses.
var checks := 0
var failures: Array[String] = []
var output := ""

func expect(value: bool, message: String) -> void:
	checks += 1
	print("[DM POLISH] %s: %s" % ["OK" if value else "FAIL", message])
	if not value:
		failures.append(message)
		push_error(message)

func _ready() -> void:
	output = OS.get_environment("POLISH_CAPTURE_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	get_tree().create_timer(150.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	expect(image.save_png(output.path_join(label + ".png")) == OK, "Rendered " + label)

func make_world(map_name: String, mode: String, count: int) -> GameWorld:
	GameData.game_mode = mode
	GameData.selected_map = map_name
	GameData.bot_count = count
	GameData.dm_primary = "m4a1"
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban", false)
	world.team_menu.close_menu(false)
	return world

func free_world(world: GameWorld) -> void:
	RoundManager.state = RoundManager.State.WAITING
	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	AudioManager.stop_all()

func _run() -> void:
	seed(151107)
	RoundManager.set_process(false)
	var world := make_world("de_dust2", "deathmatch", 6)
	expect(RoundManager.map_mode == "dm" and RoundManager.state == RoundManager.State.LIVE, "Additional DM starts immediately, without classic freeze")
	expect(not RoundManager.can_buy_now(), "Free loadouts, no buy window")
	expect(RoundManager.actors.size() == 7, "Human and six real bots")
	expect(world.player.weapon_ctrl.current_weapon_id == "m4a1", "Selected free primary")
	for actor in RoundManager.actors:
		expect(actor.armor == 100 and actor.has_helmet and not actor.is_vip, "Armor/helmet, no VIP: " + actor.actor_name)
		expect(String(actor.weapon_ctrl.slots.get(5, "")) != "c4", "No DM bomb: " + actor.actor_name)
	var enemy: CSBot
	for bot in world.bots:
		if bot.team == "T":
			enemy = bot
			break
	var hp := enemy.health
	enemy.take_bullet_damage(world.player, 250.0, 1.0, 1, "ak47", enemy.get_eye_position())
	expect(enemy.health == hp, "Spawn protection blocks bullets")
	enemy.apply_explosion_damage(world.player, 250.0, "hegrenade")
	expect(enemy.health == hp, "Spawn protection blocks HE/fire")
	var spawn := enemy.global_position
	for frame in range(180):
		await get_tree().physics_frame
		RoundManager._process(1.0 / 60.0)
	expect(enemy.global_position.distance_to(spawn) > 0.5, "DM bot really navigates after spawning")
	world.player.weapon_ctrl.give_weapon("ak47", 30, 90)
	world.player.weapon_ctrl.equip_weapon_by_id("ak47")
	# Wait for the real draw animation; do not photograph an unequipped frame.
	for frame in range(60):
		await get_tree().physics_frame
	face_open_corridor(world.player)
	await get_tree().physics_frame
	world.player.dm_protection = 2.0
	world.player.weapon_ctrl._execute_bullet_shot(world.player.weapon_ctrl.get_current_spec(), false)
	expect(world.player.dm_protection == 0.0, "Firing cancels protection immediately")
	expect(world.player._muzzle_sprite.texture.resource_path.ends_with("polish/muzzle_fire.png"), "Actual first-person authored muzzle atlas")
	expect(world.player._muzzle_sprite.hframes == 8 and world.player._muzzle_sprite.vframes == 4, "Correct muzzle sheet grid")
	capture("deathmatch_firing")
	for bot in world.bots:
		bot.set_physics_process(false)
	var previous := RoundManager.ct_score
	enemy.dm_protection = 0.0
	enemy.take_bullet_damage(world.player, 250.0, 1.0, 1, "ak47", enemy.get_eye_position())
	expect(not enemy.is_alive and RoundManager.ct_score == previous + 1, "Enemy frag increments team score")
	expect(RoundManager.dm_respawns.has(enemy) and RoundManager.state == RoundManager.State.LIVE, "Dead bot queued; no elimination round end")
	expect(RoundManager.dropped_items.is_empty(), "DM deaths do not litter weapons")
	capture("deathmatch_frag")
	RoundManager._process(3.1)
	expect(enemy.is_alive and enemy.health == 100 and enemy.dm_protection > 0.0, "Timed respawn restores life and protection")
	expect(enemy.weapon_ctrl.current_weapon_id != "knife", "Respawn gives bot a free firearm")
	RoundManager.dm_respawns[world.player] = 2.0
	RoundManager.ct_score = GameData.dm_frag_limit - 1
	enemy.dm_protection = 0.0
	enemy.take_bullet_damage(world.player, 250.0, 1.0, 1, "ak47", enemy.get_eye_position())
	expect(RoundManager.ct_score == GameData.dm_frag_limit and RoundManager.state == RoundManager.State.ROUND_OVER, "Frag limit ends DM")
	expect(RoundManager.dm_respawns.is_empty() and RoundManager.is_movement_frozen(), "Final scoreboard freezes play and cancels pending respawns")
	var grenade := GrenadeProjectile.new()
	world.add_child(grenade)
	grenade.setup_grenade("hegrenade", null, Vector3.ZERO)
	RoundManager._process(8.1)
	expect(RoundManager.state == RoundManager.State.LIVE and RoundManager.ct_score == 0, "Automatic fresh DM after final scoreboard")
	expect(grenade.is_queued_for_deletion(), "Fresh match removes old live grenades")
	RoundManager.state_timer = 0.01
	RoundManager._process(0.02)
	expect(RoundManager.state == RoundManager.State.ROUND_OVER, "Time limit also ends DM")
	# Render the real HE detonation path and smoke volume during an active match.
	RoundManager.start_deathmatch()
	for bot in world.bots:
		bot.set_physics_process(false)
	for frame in range(60):
		await get_tree().physics_frame
	face_open_corridor(world.player)
	await get_tree().physics_frame
	var ahead := world.player.global_position - world.player.camera.global_basis.z * 5.0
	ahead.y = world.player.global_position.y + 0.2
	var he := GrenadeProjectile.new()
	world.add_child(he)
	he.global_position = ahead
	he.setup_grenade("hegrenade", world.player, Vector3.ZERO)
	he._detonate()
	for frame in range(5):
		await get_tree().physics_frame
	capture("he_animated_burst")
	var cloud := SmokeCloudVolume.new()
	world.add_child(cloud)
	cloud.setup_cloud(ahead)
	for frame in range(60):
		await get_tree().physics_frame
	capture("smoke_live_volume")
	await free_world(world)
	world = make_world("cs_estate", "deathmatch", 0)
	expect(RoundManager.hostages.is_empty(), "DM on hostage map disables rescue objective")
	await free_world(world)
	world = make_world("cs_estate", "classic", 0)
	expect(RoundManager.map_mode == "cs" and RoundManager.state == RoundManager.State.FREEZE, "Classic hostage mode/freeze preserved")
	expect(not RoundManager.hostages.is_empty() and RoundManager.can_buy_now(), "Classic hostages and buying preserved")
	await free_world(world)
	world = make_world("de_dust2", "classic", 2)
	expect(RoundManager.map_mode == "de", "Classic DE remains map-driven")
	var bombs := 0
	for actor in RoundManager.actors:
		if String(actor.weapon_ctrl.slots.get(5, "")) == "c4":
			bombs += 1
	expect(bombs == 1, "Exactly one classic C4")
	await free_world(world)
	await smoke_checks()
	for wid in ["ak47", "m4a1", "mp5navy", "m3", "usp", "galil", "sg552", "scout", "hegrenade", "smokegrenade", "vest", "vesthelm", "kevlar", "kevlar_helmet", "p2000", "cz75"]:
		expect(GameData.equipment_icon(wid) != null, "Real source equipment icon: " + wid)
	print("[DM POLISH] %s: %d checks; %d failures" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

func face_open_corridor(player: PlayerController) -> void:
	# Stay at the real spawn; rotate toward the clearest sightline for effect evidence.
	var eye := player.get_eye_position()
	var best_distance := -1.0
	var best_yaw := player.look_yaw
	for step in range(24):
		var angle := TAU * float(step) / 24.0
		var direction := Vector3(-sin(angle), 0, -cos(angle))
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye + direction * 20.0, 1))
		var distance: float = 20.0 if hit.is_empty() else eye.distance_to(hit["position"])
		if distance > best_distance:
			best_distance = distance
			best_yaw = angle
	player.look_yaw = best_yaw
	player.camera.rotation.y = best_yaw

func smoke_checks() -> void:
	RoundManager.actors.clear()
	RoundManager.smoke_volumes.clear()
	var wall := StaticBody3D.new()
	wall.position = Vector3(3001, 2, 0)
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 10, 10)
	collision.shape = box
	wall.add_child(collision)
	add_child(wall)
	var smoke := SmokeCloudVolume.new()
	add_child(smoke)
	smoke.setup_cloud(Vector3(3002, 0.6, 0))
	smoke.set_process(false)
	smoke.set_physics_process(false)
	smoke.age = 2.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var point := smoke.global_position + smoke._v_pos[0]
	expect(smoke.get_density_at(point) > 0.1, "Mature rendered voxel has sensing density")
	expect(not smoke.interaction_visible(Vector3(3000, 1, 0), Vector3(3002, 1, 0)), "Wall occludes smoke interaction")
	var before := smoke._v_carve.duplicate()
	smoke.apply_explosion_impulse(Vector3(3000, 1, 0), 5.0)
	for i in range(smoke._v_count):
		var wp := smoke.global_position + smoke._v_pos[i]
		if wp.x > 3001.2:
			expect(is_equal_approx(smoke._v_carve[i], before[i]), "HE cannot clear voxel through wall %d" % i)
			break
	smoke.apply_explosion_impulse(point, 5.0)
	expect(smoke._v_carve[0] > 0.8 and smoke.voxel_opacity(0) < 0.2, "Visible-side HE clears opacity and sensing together")
	var runner := CSActor.new()
	add_child(runner)
	runner.is_alive = true
	runner.set_physics_process(false)
	runner.global_position = point - Vector3.UP * 1.05
	runner.velocity = Vector3.RIGHT * 3.0
	smoke._v_carve[0] = 0.95
	smoke._v_hold[0] = 10.0
	smoke._physics_process(0.01)
	expect(smoke._v_carve[0] >= 0.94, "Running actor cannot refill a stronger HE hole")
	runner.queue_free()
	RoundManager.actors.clear()
	smoke._v_pos[0] = Vector3(-0.87, 1.0, 0.0)
	smoke._v_home[0] = smoke._v_pos[0]
	smoke._v_vel[0] = Vector3.LEFT * 15.0
	smoke._physics_process(0.04)
	expect(smoke.global_position.x + smoke._v_pos[0].x >= 3001.1, "Drifting voxel cannot cross a solid wall")
	smoke._v_carve.fill(1.0)
	expect(smoke.get_density_at(point) == 0.0 and not smoke.blocks_segment(point - Vector3.RIGHT, point + Vector3.RIGHT), "Fully carved cloud neither obscures view nor blinds bots")
	smoke._v_carve.fill(0.0)
	smoke._v_pos[0] = point - smoke.global_position
	smoke.age = SmokeCloudVolume.DURATION - 0.05
	expect(smoke.voxel_opacity(0) < 0.03 and smoke.get_density_at(point) < 0.1, "Visual and sensing fade use the same lifetime")
	smoke.age = 2.0
	var fire := IncendiaryArea.new()
	add_child(fire)
	fire.global_position = point - Vector3.UP * 0.25
	fire.setup_fire(null, "molotov", 1511)
	fire.set_physics_process(false)
	fire._age = 1.0
	fire._extinguish_smoked_patches()
	expect(fire._patches[0].has("extinguished_at") and fire.life_left <= 0.18, "Dense nearby smoke extinguishes actual procedural fuel")
	expect(not fire.burns_at(fire.global_position), "Extinguished fire stops gameplay damage immediately")
	var fx := PolishFx.emit(self, Vector3.ZERO, "grenade_fireburst_atlas", Vector2i(4, 4), 16, 0.4, 1.0, 3.0, 2, Color(1, 1, 1, 0.3))
	expect(fx != null, "Authored explosion atlas is instantiable")
	fx.set_process(false)
	fx._process(0.2)
	expect(fx.sprite.frame == 8 and fx.sprite.modulate.a <= 0.3, "Elapsed-time atlas animation preserves original opacity")
	fx._process(0.3)
	expect(fx.is_queued_for_deletion(), "Transient effects clean up")
	fire.queue_free()
	smoke.queue_free()
	wall.queue_free()
	await get_tree().process_frame
