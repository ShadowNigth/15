extends Node
## Real economy, shared tactical AI and Assassination extraction regression.
##   godot --headless --path . --fixed-fps 60 res://tests/TacticalAIRegressionTest.tscn

var _checks := 0
var _failures: Array[String] = []
var _last_round_result: Dictionary = {}


func _capture_round_result(winner: String, reason: String) -> void:
	_last_round_result = {"winner": winner, "reason": reason}


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[TACTICAL AI TEST] " + description)


func _place_in_buyzone(bot: CSBot, world: GameWorld, team: String) -> bool:
	var team_code := "2" if team == "CT" else "1"
	for raw in world.buyzones:
		var zone: AABB = raw["aabb"]
		var zone_team := String(raw.get("team", "0"))
		if zone_team == "0" or zone_team == team_code:
			bot.global_position = zone.get_center()
			return world.is_in_buyzone(bot.global_position, team)
	return false


func _test_weighted_purchases() -> void:
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 0
	GameData.start_money = 16000
	var packed := load("res://scenes/GameWorld.tscn") as PackedScene
	_expect(packed != null, "GameWorld loads for real bot purchases")
	if packed == null:
		return
	var world := packed.instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban")
	world.team_menu.close_menu()
	RoundManager.state = RoundManager.State.FREEZE
	RoundManager.state_timer = 999.0
	RoundManager.buy_time_left = 90.0

	for team in ["CT", "T"]:
		var unique: Dictionary = {}
		var classes: Dictionary = {}
		var sniper_count := 0
		var purchased := 0
		for i in range(10):
			var bot := CSBot.new()
			bot.actor_name = "Market%s%02d" % [team, i]
			world.add_child(bot)
			bot.set_team_and_class(team, "urban" if team == "CT" else "terror")
			bot.set_physics_process(false)
			# Manual regression bots do not pass through GameWorld's round spawn;
			# mark them alive just as spawn_for_round does before real purchases.
			bot.is_alive = true
			bot.money = 16000
			bot.armor = 100
			bot.has_defuser = true
			bot.weapon_ctrl.reset_loadout(team, false)
			var placed := _place_in_buyzone(bot, world, team)
			_expect(placed and bot.can_use_buy_menu(), "%s buyer %d starts alive in a valid team buyzone" % [team, i])
			bot._perform_bot_buy()
			var primary := String(bot.weapon_ctrl.slots.get(1, ""))
			if primary.is_empty():
				_expect(false, "%s buyer %d purchases a primary with a rich budget" % [team, i])
				continue
			purchased += 1
			unique[primary] = true
			classes[bot._primary_class(primary)] = true
			if bot._primary_class(primary) == "sniper":
				sniper_count += 1
			var spec: Dictionary = GameData.weapons.get(primary, {})
			var weapon_team := String(spec.get("team", "MISSING"))
			_expect(weapon_team in ["ANY", team], "%s purchase %s remains legal for its team" % [team, primary])
			_expect(bot.money >= 0 and bot.money <= 16000, "%s purchase %s preserves a valid wallet" % [team, primary])
			_expect(bot._last_bought_primary == primary, "%s purchase %s records personal variety memory" % [team, primary])
		_expect(purchased == 10, "%s completes all ten real purchases" % team)
		_expect(unique.size() >= 4, "%s buys at least four different primaries instead of one repeated rifle (%s)" % [team, ", ".join(unique.keys())])
		_expect(classes.size() >= 2, "%s purchases span multiple tactical weapon classes (%s)" % [team, ", ".join(classes.keys())])
		_expect(sniper_count <= 2, "%s preserves the two-sniper squad scarcity rule" % team)
		print("[TACTICAL AI TEST] %s purchases: %s" % [team, ", ".join(unique.keys())])

	world.queue_free()
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame


func _find_vip_bot() -> CSBot:
	for raw in RoundManager.actors:
		var bot := raw as CSBot
		if is_instance_valid(bot) and bot.is_vip and bot.is_alive:
			return bot
	return null


func _test_vip_map(map_name: String, expected_zones: int, drive_to_extraction: bool) -> void:
	GameData.selected_map = map_name
	GameData.bot_count = 5
	GameData.start_money = 16000
	var packed := load("res://scenes/GameWorld.tscn") as PackedScene
	_expect(packed != null, "%s GameWorld scene loads" % map_name)
	if packed == null:
		return
	var world := packed.instantiate() as GameWorld
	add_child(world)
	# A T human guarantees five enemy CT bots, so random selection must choose
	# an AI VIP rather than making the requested behaviour human-dependent.
	world._on_player_team_chosen("T", "terror")
	world.team_menu.close_menu()
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.state_timer = 180.0
	RoundManager.buy_time_left = 0.0
	for bot in world.bots:
		bot.set_physics_process(false)
	world.player.set_physics_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_expect(world.escape_zones.size() == expected_zones, "%s restores every func_vip_safetyzone brush" % map_name)
	var vip_count := 0
	for raw in RoundManager.actors:
		var actor := raw as CSActor
		if is_instance_valid(actor) and actor.is_vip:
			vip_count += 1
			_expect(actor is CSBot, "%s assigns an AI VIP when the human plays T" % map_name)
	_expect(vip_count == 1, "%s designates exactly one VIP" % map_name)
	var vip := _find_vip_bot()
	_expect(vip != null, "%s exposes a living bot VIP" % map_name)
	if vip == null:
		world.queue_free()
		await get_tree().process_frame
		return

	vip._update_tactical_objective()
	_expect(vip._vip_escape_node >= 0, "%s VIP chooses an actual extraction node" % map_name)
	_expect(not vip._node_path.is_empty() or vip._vip_direct_active, "%s VIP obtains a navigable extraction route" % map_name)
	var destination_known := false
	for zone in world.escape_zones:
		if (zone as AABB).get_center().distance_to(vip._vip_direct_goal) < 0.01:
			destination_known = true
	_expect(destination_known, "%s VIP retains the real safety-zone centre for final approach" % map_name)
	if drive_to_extraction:
		var nav: BotNavigator = world.bot_navigator
		var space := vip.get_world_3d().direct_space_state
		var origin := nav.get_nearest_node(vip.global_position, space, 3.6, true)
		var banned_origin: Dictionary = {origin: vip._nav_clock + 3.0}
		var recovered_origin := nav.get_nearest_node(vip.global_position, space, 3.6, true, banned_origin)
		_expect(origin >= 0 and recovered_origin >= 0 and recovered_origin != origin,
			"%s stuck recovery does not reselect an actively banned walk origin" % map_name)

	var escort_verified := false
	for bot in world.bots:
		if bot.team != "CT" or bot.is_vip:
			continue
		bot._update_tactical_objective()
		if bot._vip_escort_slot >= 0 and bot._vip_escort_slot < 3:
			escort_verified = escort_verified or bot._has_goal or bot._hold_pos_timer > 0.0
	_expect(escort_verified, "%s assigns a CT formation escort around the VIP" % map_name)

	if drive_to_extraction:
		_last_round_result = {}
		# Isolate navigation from combat. The VIP still uses its ordinary physics,
		# directed YaPB links, ladders, doors, stuck recovery and extraction check.
		for raw in RoundManager.actors:
			var actor := raw as CSActor
			if is_instance_valid(actor) and actor != vip and actor != world.player:
				actor.is_alive = false
				actor.set_physics_process(false)
		# Remove the human from team elimination without disabling any VIP rule.
		# OilRig's environmental hazards can otherwise kill a stationary T and
		# produce a false CT elimination win before extraction has occurred.
		world.player.team = "SPECTATOR"
		world.player.is_alive = false
		world.player.set_physics_process(false)
		vip.set_physics_process(true)
		var frames := 0
		var start_pos := vip.global_position
		while frames < 10800 and RoundManager.state == RoundManager.State.LIVE:
			await get_tree().physics_frame
			frames += 1
			if frames % 1800 == 0:
				print("[TACTICAL AI TEST] %s VIP t=%ds pos=%s path=%d goal=%d" % [map_name, frames / 60, vip.global_position, vip._node_path.size(), vip._vip_escape_node])
				if not vip._node_path.is_empty():
					var current_node: int = vip._node_path[0]
					var target_pos: Vector3 = world.bot_navigator.get_node_pos(current_node)
					var query := PhysicsRayQueryParameters3D.create(vip.global_position + Vector3(0.0, 1.05, 0.0), target_pos + Vector3(0.0, 1.05, 0.0))
					query.collision_mask = 1
					var hit := vip.get_world_3d().direct_space_state.intersect_ray(query)
					var obstacle := str((hit.get("collider") as Node).get_path()) if not hit.is_empty() and hit.get("collider") is Node else "none"
					print("[TACTICAL AI TEST] route node=%d target=%s stuck=%.2f elapsed=%.2f escape=%.2f retries=%d velocity=%s obstacle=%s" % [current_node, target_pos, vip._stuck_timer, vip._cur_node_elapsed, vip._escape_timer, vip._rechoice_count, vip.velocity, obstacle])
		print("[TACTICAL AI TEST] %s round result=%s player_alive=%s player_team=%s" % [map_name, _last_round_result, world.player.is_alive, world.player.team])
		_expect(RoundManager.state == RoundManager.State.ROUND_OVER and RoundManager.ct_score == 1,
			"%s VIP physically reaches extraction and wins for CT (frames=%d, start=%s, end=%s, path=%d)" % [map_name, frames, start_pos, vip.global_position, vip._node_path.size()])
		_expect(world.is_in_escape_zone(vip.global_position), "%s winning VIP stands inside a real extraction AABB" % map_name)
	else:
		# Independently verify the actual actor movement extraction hook on every
		# authored zone without replacing the full route drive above.
		for zone in world.escape_zones:
			RoundManager.state = RoundManager.State.LIVE
			vip.global_position = (zone as AABB).get_center()
			vip.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0 / 60.0)
			_expect(RoundManager.state == RoundManager.State.ROUND_OVER, "%s extraction volume accepts the VIP through real actor movement" % map_name)
			if RoundManager.state == RoundManager.State.ROUND_OVER:
				break

	vip.set_physics_process(false)
	world.queue_free()
	AudioManager.stop_all()
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	seed(472047)
	RoundManager.round_ended.connect(_capture_round_result)
	var oilrig := GameData.load_map_data("as_oilrig")
	var tundra := GameData.load_map_data("as_tundra")
	_expect((oilrig.get("escape_zones", []) as Array).size() == 1, "OilRig source data contains its helicopter safety zone")
	_expect((tundra.get("escape_zones", []) as Array).size() == 2, "Tundra source data contains both safety zones")
	for data in [oilrig, tundra]:
		for raw in data.get("escape_zones", []):
			var lo: Array = raw.get("min", [])
			var hi: Array = raw.get("max", [])
			_expect(lo.size() == 3 and hi.size() == 3 and float(hi[0]) > float(lo[0]) and float(hi[2]) > float(lo[2]),
				"%s extraction has a positive BSP brush volume" % String(data.get("name", "AS")))

	await _test_weighted_purchases()
	# Regression seed: the upper OilRig ladder used to trap the VIP in a
	# replan loop because the lower waypoint pulls it away from the rungs.
	seed(2)
	await _test_vip_map("as_oilrig", 1, true)
	await _test_vip_map("as_tundra", 2, true)
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("[TACTICAL AI TEST] PASS: %d checks; varied real purchases, squad roles and physical VIP extraction." % _checks)
		get_tree().quit()
	else:
		printerr("[TACTICAL AI TEST] FAIL: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			printerr(" - " + failure)
		get_tree().quit(1)
