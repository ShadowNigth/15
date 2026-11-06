extends Node
## Physical mission-objective regressions for task 48.
##   godot --headless --path . --fixed-fps 60 res://tests/MissionObjectiveRegressionTest.tscn
##
## Enemies stay alive but have physics disabled: rounds cannot be won by team
## elimination, while VIP escorts and hostage rescuers use their real AI/physics.

var _checks := 0
var _failures: Array[String] = []
var _last_round_result: Dictionary = {}


func _ready() -> void:
	RoundManager.round_ended.connect(_capture_round_result)
	call_deferred("_run")


func _capture_round_result(winner: String, reason: String) -> void:
	_last_round_result = {"winner": winner, "reason": reason}


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[MISSION AI TEST] " + description)
		var annotation := description.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
		print("::error title=Mission objective QA::" + annotation)


func _progress(message: String) -> void:
	print("[MISSION AI TEST] " + message)
	var annotation := message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
	print("::notice title=Mission progress::" + annotation)


func _make_world(map_name: String, bot_count: int) -> GameWorld:
	GameData.selected_map = map_name
	GameData.bot_count = bot_count
	GameData.start_money = 16000
	var packed := load("res://scenes/GameWorld.tscn") as PackedScene
	_expect(packed != null, "%s GameWorld scene loads" % map_name)
	if packed == null:
		return null
	var world := packed.instantiate() as GameWorld
	_expect(world != null, "%s GameWorld root instantiates with its native script" % map_name)
	if world == null:
		return null
	add_child(world)
	world._on_player_team_chosen("T", "terror", false)
	world.team_menu.close_menu(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.state_timer = 600.0
	RoundManager.buy_time_left = 0.0
	world.player.team = "SPECTATOR"
	world.player.is_alive = false
	world.player.set_physics_process(false)
	for bot in world.bots:
		if bot.team == "T":
			# Keep them in the alive-team count, but outside perception/weapons
			# range so combat cannot decide the result or distract mission AI.
			bot.target_enemy = null
			bot.set_physics_process(false)
			bot.global_position = Vector3(0.0, -10000.0, 0.0)
		else:
			bot.target_enemy = null
	return world


func _free_world(world: GameWorld) -> void:
	if is_instance_valid(world):
		world.queue_free()
	AudioManager.stop_all()
	await get_tree().process_frame
	OS.delay_msec(50)
	await get_tree().process_frame
	await get_tree().process_frame


func _find_vip(world: GameWorld) -> CSBot:
	for bot in world.bots:
		if is_instance_valid(bot) and bot.team == "CT" and bot.is_vip and bot.is_alive:
			return bot
	return null


func _test_oilrig_escort() -> void:
	_last_round_result = {}
	var world := _make_world("as_oilrig", 8)
	if world == null:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var vip := _find_vip(world)
	_expect(vip != null, "OilRig spawns a living AI VIP for the full-squad drive")
	if vip == null:
		await _free_world(world)
		return
	var escorts: Array[CSBot] = []
	for bot in world.bots:
		if bot.team == "CT" and not bot.is_vip:
			bot._update_tactical_objective()
			if bot._vip_escort_slot >= 0 and bot._vip_escort_slot < 3:
				escorts.append(bot)
	escorts.sort_custom(func(a: CSBot, b: CSBot) -> bool: return a.get_instance_id() < b.get_instance_id())
	_expect(escorts.size() == 3, "OilRig assigns three non-VIP CT escorts")
	var start_positions: Dictionary = {}
	var closest_distances: Dictionary = {}
	for escort in escorts:
		start_positions[escort.get_instance_id()] = escort.global_position
		closest_distances[escort.get_instance_id()] = 1e9

	var frames := 0
	var escort_camped := false
	while frames < 14400 and RoundManager.state == RoundManager.State.LIVE:
		await get_tree().physics_frame
		frames += 1
		for escort in escorts:
			if not is_instance_valid(escort):
				continue
			var distance := escort.global_position.distance_to(vip.global_position)
			closest_distances[escort.get_instance_id()] = minf(float(closest_distances[escort.get_instance_id()]), distance)
			if escort._is_assigned_vip_escort() and escort._camp_timer > 0.0:
				escort_camped = true
		if frames % 1800 == 0:
			var distances: Array[String] = []
			for escort in escorts:
				distances.append("%.1f" % escort.global_position.distance_to(vip.global_position))
			_progress("OilRig t=%ds VIP=%s escort_dist=%s path=%d" % [frames / 60, vip.global_position, ", ".join(distances), vip._node_path.size()])

	_progress("OilRig final VIP pos=%s result=%s" % [vip.global_position, str(_last_round_result)])
	for escort in escorts:
		_progress("OilRig final escort dist=%.2f pos=%s path=%d goal=%s direct=%s stuck=%.2f escape=%.2f weapon=%s" % [escort.global_position.distance_to(vip.global_position), escort.global_position, escort._node_path.size(), escort._goal_pos, escort._vip_escort_direct_active, escort._stuck_timer, escort._escape_timer, escort.weapon_ctrl.current_weapon_id])
	_expect(not escort_camped, "Assigned OilRig escorts never switch into stationary camp behaviour")
	for escort in escorts:
		var moved := escort.global_position.distance_to(start_positions[escort.get_instance_id()] as Vector3)
		_expect(moved > 2.0, "OilRig escort leaves its spawn instead of waiting at round start (moved=%.2f)" % moved)
		_expect(float(closest_distances[escort.get_instance_id()]) < 8.0, "OilRig escort genuinely catches and accompanies the VIP")
	var close_at_finish := 0
	for escort in escorts:
		if escort.global_position.distance_to(vip.global_position) < 18.0:
			close_at_finish += 1
	_expect(close_at_finish >= 2, "At least two escorts remain with the VIP through extraction")
	_expect(RoundManager.state == RoundManager.State.ROUND_OVER and String(_last_round_result.get("reason", "")).contains("The VIP has escaped!"),
		"Full OilRig squad wins by physical VIP extraction, not elimination (result=%s)" % str(_last_round_result))
	_expect(world.is_in_escape_zone(vip.global_position), "Full-squad VIP finishes inside the OilRig safety brush")
	await _free_world(world)


func _test_hostage_map(map_name: String, expected_hostages: int, bot_count: int, max_frames: int) -> void:
	_last_round_result = {}
	var world := _make_world(map_name, bot_count)
	if world == null:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hostages: Array[HostageNPC] = []
	for raw in RoundManager.hostages:
		var hostage := raw as HostageNPC
		if is_instance_valid(hostage):
			hostages.append(hostage)
	_expect(hostages.size() == expected_hostages, "%s spawns every authored hostage" % map_name)
	var starts: Dictionary = {}
	var assigned: Dictionary = {}
	for hostage in hostages:
		starts[hostage.get_instance_id()] = hostage.global_position
		assigned[hostage.get_instance_id()] = false

	var frames := 0
	while frames < max_frames and RoundManager.state == RoundManager.State.LIVE:
		await get_tree().physics_frame
		frames += 1
		for hostage in hostages:
			if is_instance_valid(hostage.leader):
				assigned[hostage.get_instance_id()] = true
		if frames % 1800 == 0:
			_progress("%s t=%ds rescued=%d/%d" % [map_name, frames / 60, RoundManager.hostages_rescued_this_round, hostages.size()])

	for hostage in hostages:
		var hid := hostage.get_instance_id()
		_expect(bool(assigned[hid]), "%s hostage is actually assigned to a CT instead of being abandoned" % map_name)
		_expect(hostage.is_rescued, "%s hostage physically reaches a valid rescue brush" % map_name)
		_expect(hostage.global_position.distance_to(starts[hid] as Vector3) > 1.0, "%s rescued hostage moved away from its initial position" % map_name)
	_expect(RoundManager.hostages_rescued_this_round == expected_hostages, "%s registers every hostage rescue exactly once" % map_name)
	_expect(RoundManager.state == RoundManager.State.ROUND_OVER and String(_last_round_result.get("reason", "")).contains("All Hostages Rescued!"),
		"%s CT bots win by completing the rescue objective (frames=%d, result=%s)" % [map_name, frames, str(_last_round_result)])
	await _free_world(world)


func _run() -> void:
	var scenario := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
	print("[MISSION AI TEST] scenario=%s" % scenario)
	if scenario == "check":
		_progress("Native scene, autoloads and script compilation are valid")
		_finish()
		return
	if scenario in ["all", "oilrig"]:
		seed(2)
		await _test_oilrig_escort()
	if scenario in ["all", "747"]:
		seed(4807)
		await _test_hostage_map("cs_747", 5, 10, 18000)
	if scenario in ["all", "estate"]:
		seed(4808)
		await _test_hostage_map("cs_estate", 3, 6, 14400)
	if scenario not in ["all", "oilrig", "747", "estate"]:
		_expect(false, "Unknown scenario: %s" % scenario)
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("[MISSION AI TEST] PASS: %d checks; full VIP escort and physical hostage rescues." % _checks)
		print("::notice title=Mission objective QA::PASS: %d physical checks" % _checks)
		get_tree().quit()
	else:
		printerr("[MISSION AI TEST] FAIL: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			printerr(" - " + failure)
		get_tree().quit(1)
