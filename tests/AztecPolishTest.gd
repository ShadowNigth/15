extends Node3D
## Baseline vs repaired BSP physics, live bots/objectives and identical-camera renders.
var checks := 0
var failures := 0
var rays: Array[Array] = []
var reference: Array[Dictionary] = []
const VIEWS := [
	["a", Vector3(43, -4, -29), Vector3(49, -6, -20)],
	["b", Vector3(-30, -4, 14), Vector3(-30.5, -6, 26)],
	["bridge", Vector3(-22, -4, -29), Vector3(-22, -6, -10)],
	["water", Vector3(5, -14.5, -14), Vector3(25, -16.5, -16)],
]
func _ready() -> void:
	get_tree().create_timer(300).timeout.connect(func(): get_tree().quit(1))
	run.call_deferred()

func expect(value: bool, text: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("[AZTEC] FAIL: " + text)

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
		expect(get_viewport().get_texture().get_image().save_png("/tmp/dm-polish-review/aztec_" + view[0] + "_" + suffix + ".png") == OK, "Capture " + view[0] + suffix)
	print("[AZTEC] rendered primitives over four identical views ", suffix, "=", primitives)
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

func cross_bridge(world: GameWorld) -> void:
	for bot in world.bots:
		bot.set_physics_process(false)
	world.player.set_physics_process(false)
	world.player.dm_protection = 999.0
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.state_timer = 999
	for direction in [1.0, -1.0]:
		var start_z := -28.0 if direction > 0 else -1.0
		var finish_z := -1.0 if direction > 0 else -28.0
		world.player.spawn_for_round(Vector3(-22, -5.5, start_z), 0, false)
		for frame in range(600):
			await get_tree().physics_frame
			world.player.apply_goldsrc_movement(Vector3(0, 0, direction), false, false, false, 1.0 / 60.0)
			if (world.player.global_position.z-finish_z)*direction >= 0:
				break
		expect((world.player.global_position.z-finish_z)*direction >= 0 and world.player.global_position.y > -12, "Real standing player crosses the bridge without falling or snagging: " + str(world.player.global_position))

func baseline_data(data: Dictionary) -> Dictionary:
	var before := data.duplicate(true)
	before.name = "aztec_baseline"
	before.glb = "res://assets/maps/aztec_baseline.glb"
	return before

func validate_map(_built: Dictionary) -> void:
	pass

func run() -> void:
	seed(2481)
	var data := GameData.load_map_data("de_aztec")
	var before := baseline_data(data)
	var original: Node3D = MapLoader.build_map(self, before).root
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Dense floor and horizontal wall probes, plus every authored spawn.
	for x in range(-46, 56, 6):
		for z in range(-114, 70, 6):
			rays.append([Vector3(x + 0.137, 12, z + 0.271), Vector3(x + 0.137, -23, z + 0.271)])
	for y in [-15.0, -7.0, -3.0, 1.0]:
		for z in range(-111, 69, 6):
			rays.append([Vector3(-50, y, z + 0.173), Vector3(60, y, z + 0.173)])
		for x in range(-45, 55, 6):
			rays.append([Vector3(x + 0.173, y, -120), Vector3(x + 0.173, y, 75)])
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
	var restored_bridge_hits := 0
	for i in range(rays.size()):
		var hit := ray(rays[i][0], rays[i][1])
		var expected: Vector3 = reference[i].position
		var actual: Vector3 = hit.get("position", Vector3.INF)
		var is_bridge_fix: bool = not hit.is_empty() and (hit.collider as Node).has_meta("aztec_bridge_floor")
		if is_bridge_fix:
			restored_bridge_hits += 1
			expect(actual.x >= -24.001 and actual.x <= -19.999 and actual.z >= -28.001 and actual.z <= -3.499 and actual.y >= -7.05 and actual.y <= -5.99 and (not expected.is_finite() or expected.y < actual.y - 1), "Only the missing bridge support may change baseline probes")
		else:
			expect((not actual.is_finite() and not expected.is_finite()) or (actual.is_finite() and expected.is_finite() and actual.distance_to(expected) < 0.003), "Collision equivalence probe %d expected %s actual %s" % [i, expected, actual])
	expect(restored_bridge_hits > 0, "Physical comparison detects and bounds the restored bridge support")
	var bridge_nodes := repaired.find_children("AztecBridgeWalkSurface", "StaticBody3D", true, false)
	expect(bridge_nodes.size() == 1, "Exactly one targeted bridge support, no blanket illusionary collision")
	for z in [-26.0, -22.0, -17.0, -12.0, -5.0]:
		var bridge_hit := ray(Vector3(-22, -4.5, z), Vector3(-22, -12, z))
		expect(not bridge_hit.is_empty() and (bridge_hit.collider as Node).has_meta("aztec_bridge_floor"), "Visible deck has physical support along its length")
	var materials: Dictionary = repaired.get_meta("world_materials")
	var waters := 0
	var glass := 0
	for material in materials.values():
		expect(is_equal_approx(float(material.get_shader_parameter("lightmap_exponent")), 0.90), "Aztec-only lightmap profile")
		var kind: String = material.shader.resource_path.get_file()
		if kind == "goldsrc_world.gdshader":
			expect(float(material.get_shader_parameter("relief_depth")) <= 0.0201, "Controlled stone/wood/metal relief")
			if material.resource_name in ["generic035", "generic039"]:
				expect(float(material.get_shader_parameter("material_roughness")) >= 0.95, "Concrete tile is not treated as metal")
		elif kind == "water.gdshader":
			waters += 1
			expect(is_equal_approx(float(material.get_shader_parameter("water_roughness")), 0.48), "Matte water, not a chrome surface")
			expect(is_equal_approx(float(material.get_shader_parameter("water_metallic")), 0.0), "Water is not metallic")
		elif kind == "goldsrc_world_alpha.gdshader":
			glass += 1
			expect(float(material.get_shader_parameter("alpha_Val")) < 0.4, "Original transparent glass retained")
	expect(waters == 1 and glass >= 1, "Original river and glass materials installed")
	expect(built.water_zones.size() == 3, "Three original water volumes preserved")
	for zone in built.water_zones:
		var surface: Vector3 = (zone as AABB).get_center()
		surface.y = (zone as AABB).end.y
		expect(ray(surface + Vector3.UP * 0.15, surface - Vector3.UP * 0.15).is_empty(), "Water surface never becomes a solid invisible floor")
	expect(built.bombsites.size() == 2 and built.rescue_zones.is_empty() and built.escape_zones.is_empty(), "Authentic bomb objectives, no invented hostage/VIP goals")
	await screenshots(repaired, "after")
	repaired.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	GameData.selected_map = "de_aztec"
	GameData.bot_count = 5
	GameData.game_mode = "classic"
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban")
	world.team_menu.close_menu()
	await get_tree().physics_frame
	await get_tree().physics_frame
	expect(world.bot_navigator.waypoints.size() == 514, "Authored YaPB graph preserved")
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
			await capture_bots(world, "aztec_gameplay_a")
	await capture_bots(world, "aztec_gameplay_b")
	var moving := 0
	for i in range(world.bots.size()):
		if world.bots[i].global_position.distance_to(starts[i]) > 3:
			moving += 1
		expect(world.bots[i].global_position.y > -23, "Bot remains inside playable map")
	expect(moving >= 3, "At least three live bots leave their spawn through real physics")
	await cross_bridge(world)
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
	var holder := Node3D.new()
	add_child(holder)
	var ordinary := SkyBuilder.setup_environment(holder, "doom1")
	expect(is_equal_approx(ordinary.environment.ambient_light_energy, 1.05), "Base environment remains unchanged for other maps")
	holder.queue_free()
	print("[AZTEC] %s: %d checks; %d failures; %d physics probes" % ["PASS" if failures == 0 else "FAIL", checks, failures, rays.size()])
	get_tree().quit(0 if failures == 0 else 1)
