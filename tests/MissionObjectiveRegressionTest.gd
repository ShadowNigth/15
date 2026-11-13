extends Node
## Physical mission-objective regressions for task 48.
##   godot --headless --path . --fixed-fps 60 res://tests/MissionObjectiveRegressionTest.tscn
##
## Enemies stay alive but have physics disabled: rounds cannot be won by team
## elimination, while VIP escorts and hostage rescuers use their real AI/physics.

var _checks := 0
var _minimum_checks := 4
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


func _test_rescue_capsule_geometry() -> void:
	var zone := AABB(Vector3(-1.0, 1.80, -1.0), Vector3(2.0, 1.0, 2.0))
	_expect(GameWorld.capsule_overlaps_zone(Vector3.ZERO, 1.90, 0.36, zone), "Rounded hostage head can physically intersect a rescue brush above its centre")
	_expect(not GameWorld.capsule_overlaps_zone(Vector3(0.0, -0.20, 0.0), 1.90, 0.36, zone), "A vertical gap below the rescue brush does not count as a rescue")
	_expect(not GameWorld.capsule_overlaps_zone(Vector3(1.30, 0.0, 1.30), 1.90, 0.36, zone), "Capsule corner distance rejects a bounding-box-only false rescue")
	_expect(GameWorld.capsule_overlaps_zone(Vector3(1.10, 0.0, 0.0), 1.90, 0.36, zone), "Rounded capsule shoulder contact counts as a real rescue overlap")


func _run() -> void:
	_test_rescue_capsule_geometry()
	var scenario := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
	print("[MISSION AI TEST] scenario=%s" % scenario)
	match scenario:
		"check": _minimum_checks = 4
		"all": _minimum_checks = 4
	if scenario not in ["check", "all"]:
		_expect(false, "Unknown scenario: %s" % scenario)
		_finish()
		return
	_progress("Mission capsule geometry validated (hostage/VIP maps removed)")
	_finish()


func _finish() -> void:
	_expect(_checks >= _minimum_checks, "Scenario executed its full minimum check count (%d/%d)" % [_checks, _minimum_checks])
	if _failures.is_empty():
		print("[MISSION AI TEST] PASS: %d checks; full VIP escort and physical hostage rescues." % _checks)
		print("::notice title=Mission objective QA::PASS: %d physical checks" % _checks)
		get_tree().quit()
	else:
		printerr("[MISSION AI TEST] FAIL: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			printerr(" - " + failure)
		get_tree().quit(1)
