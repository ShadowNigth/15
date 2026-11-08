extends Node3D
## Baseline vs repaired BSP physics, live bots/objectives and identical-camera renders.
var checks := 0
var failures := 0
var rays: Array[Array] = []
var reference: Array[Dictionary] = []
const VIEWS := [
	["b", Vector3(-84, 6, 48), Vector3(-72, 1.5, 46)],
	["a", Vector3(-95, 9.5, -49), Vector3(-77, 4.5, -36)],
	["ct", Vector3(-77, -1.5, -14), Vector3(-65, -1, -5)],
	["t", Vector3(22, 6.5, 26), Vector3(14, 5.8, 48)],
]

func _ready() -> void:
	get_tree().create_timer(300).timeout.connect(func(): get_tree().quit(1))
	run.call_deferred()

func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("[DUST2] FAIL: " + text)

func vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))

func ray(a: Vector3, b: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(a, b, 1))

func comparison_views() -> Array:
	return VIEWS

func screenshots(root: Node3D, suffix: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var camera := Camera3D.new()
	camera.fov = 74
	root.add_child(camera)
	camera.make_current()
	var primitives := 0
	for view in comparison_views():
		camera.position = view[1]
		camera.look_at(view[2])
		for frame in range(3):
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		primitives += int(RenderingServer.viewport_get_render_info(get_viewport().get_viewport_rid(), RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME))
		DirAccess.make_dir_recursive_absolute("/tmp/dm-polish-review")
		expect(get_viewport().get_texture().get_image().save_png("/tmp/dm-polish-review/dust2_" + view[0] + "_" + suffix + ".png") == OK, "Capture " + view[0] + suffix)
	print("[DUST2] rendered primitives over four identical views ", suffix, "=", primitives)
	camera.queue_free()

func capture_bots(world: GameWorld, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var subject: CSBot = null
	for bot in world.bots:
		if bot.is_alive:
			subject = bot
			break
	expect(subject != null, "Living bot available for gameplay framebuffer")
	if subject == null:
		return
	var camera := Camera3D.new()
	world.add_child(camera)
	var focus := subject.global_position + Vector3.UP
	var desired := focus + Vector3(3, 1.5, 4)
	var obstruction := ray(focus, desired)
	camera.global_position = desired if obstruction.is_empty() else (obstruction.position as Vector3) + (obstruction.normal as Vector3) * 0.25
	camera.look_at(focus)
	camera.make_current()
	for frame in range(3):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	expect(get_viewport().get_texture().get_image().save_png("/tmp/dm-polish-review/" + name + ".png") == OK, "Live bot gameplay " + name)
	camera.queue_free()

func baseline_data(data: Dictionary) -> Dictionary:
	var before := data.duplicate(true)
	before.name = "dust2_baseline"
	before.glb = "res://assets/maps/dust2_baseline.glb"
	return before

func validate_map(_built: Dictionary) -> void:
	pass

func run() -> void:
	seed(2481)
	var data := GameData.load_map_data("de_dust2")
	var before := baseline_data(data)
	var original: Node3D = MapLoader.build_map(self, before).root
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Dense floor and horizontal wall probes, plus every authored spawn.
	for x in range(-116, 48, 7):
		for z in range(-58, 80, 7):
			rays.append([Vector3(x + 0.137, 18, z + 0.271), Vector3(x + 0.137, -12, z + 0.271)])
	for y in [-2.0, 1.5, 5.0, 9.0]:
		for z in range(-55, 76, 5):
			rays.append([Vector3(-120, y, z + 0.173), Vector3(50, y, z + 0.173)])
		for x in range(-113, 45, 5):
			rays.append([Vector3(x + 0.173, y, -65), Vector3(x + 0.173, y, 85)])
	for spawn in data.ct_spawns + data.t_spawns:
		var pos := vec(spawn.pos)
		rays.append([pos + Vector3.UP * 2, pos - Vector3.UP * 10])
	for segment in rays:
		var hit := ray(segment[0], segment[1])
		reference.append({"position": hit.get("position", Vector3.INF), "normal": hit.get("normal", Vector3.ZERO)})
	await screenshots(original, "before")
	original.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var built := MapLoader.build_map(self, data)
	var repaired: Node3D = built.root
	validate_map(built)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for i in range(rays.size()):
		var hit := ray(rays[i][0], rays[i][1])
		var expected: Vector3 = reference[i].position
		var actual: Vector3 = hit.get("position", Vector3.INF)
		expect((not actual.is_finite() and not expected.is_finite()) or (actual.is_finite() and expected.is_finite() and actual.distance_to(expected) < 0.003), "Collision equivalence probe %d expected %s actual %s" % [i, expected, actual])
	var materials: Dictionary = repaired.get_meta("world_materials")
	for material in materials.values():
		expect(is_equal_approx(float(material.get_shader_parameter("lightmap_exponent")), 0.92), "Dust2-only lightmap profile")
		expect(float(material.get_shader_parameter("relief_depth")) <= 0.0181, "Controlled material relief")
	expect(built.bombsites.size() == 2 and built.rescue_zones.is_empty() and built.escape_zones.is_empty(), "Authentic bomb objectives, no invented hostage/VIP goals")
	await screenshots(repaired, "after")
	repaired.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 5
	GameData.game_mode = "classic"
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban")
	world.team_menu.close_menu()
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect(world.bot_navigator.waypoints.size() == 1238, "Authored YaPB graph preserved")
	# Directed routes from every spawn to each objective, for the correct team.
	for team in ["CT", "T"]:
		for spawn in data.ct_spawns if team == "CT" else data.t_spawns:
			var pos := vec(spawn.pos)
			var floor_hit := ray(pos + Vector3.UP * 2, pos - Vector3.UP * 10)
			expect(not floor_hit.is_empty(), "Solid floor at " + team + " spawn")
			if not floor_hit.is_empty():
				var capsule := CapsuleShape3D.new()
				capsule.radius = 0.36
				capsule.height = CSActor.STAND_HEIGHT
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape = capsule
				query.collision_mask = 1
				query.transform = Transform3D(Basis.IDENTITY, (floor_hit.position as Vector3) + Vector3.UP * (CSActor.STAND_HEIGHT * 0.5 + 0.06))
				expect(get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "Standing capsule fits at " + team + " spawn")
			for site in world.bombsites:
				var goal := world.bot_navigator.get_nearest_node(site.get_center())
				var path := world.bot_navigator.plan_node_path(pos, goal, team, BotNavigator.PATH_FAST)
				expect(not path.is_empty(), team + " spawn can route to each site")
	var starts: Array[Vector3] = []
	for bot in world.bots:
		starts.append(bot.global_position)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.state_timer = 120
	RoundManager.freeze_ended.emit()
	for frame in range(900):
		await get_tree().physics_frame
		if frame == 450:
			await capture_bots(world, "dust2_gameplay_a")
	await capture_bots(world, "dust2_gameplay_b")
	var moving := 0
	for i in range(world.bots.size()):
		if world.bots[i].global_position.distance_to(starts[i]) > 3:
			moving += 1
		expect(world.bots[i].global_position.y > -15, "Bot remains inside playable map")
	expect(moving >= 3, "At least three live bots leave their spawn through real physics")
	# Exercise real bomb/kit defusal at both preserved objective volumes.
	for site in world.bombsites:
		var center := site.get_center()
		expect(world.is_in_bombsite(center), "Bombsite interaction volume")
		var bomb := PlantedC4.new()
		world.add_child(bomb)
		bomb.global_position = center
		RoundManager.state = RoundManager.State.LIVE
		RoundManager.notify_bomb_planted(bomb, center)
		world.player.has_defuser = true
		expect(bomb.begin_or_continue_defuse(world.player, 5.1) == 1.0, "Actual C4 defuses with kit at site")
	world.queue_free()
	await get_tree().process_frame
	print("[DUST2] %s: %d checks; %d failures; %d physics probes" % ["PASS" if failures == 0 else "FAIL", checks, failures, rays.size()])
	get_tree().quit(0 if failures == 0 else 1)
