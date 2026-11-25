extends Node
## Real economy and shared DE tactical AI regression.
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
		var annotation := description.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
		print("::error title=Tactical AI QA::" + annotation)


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
			bot.weapon_ctrl.reset_loadout(team)
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


func _run() -> void:
	seed(472047)
	RoundManager.round_ended.connect(_capture_round_result)

	await _test_weighted_purchases()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("[TACTICAL AI TEST] PASS: %d checks; varied real purchases and DE squad roles." % _checks)
		get_tree().quit()
	else:
		printerr("[TACTICAL AI TEST] FAIL: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			printerr(" - " + failure)
		get_tree().quit(1)
