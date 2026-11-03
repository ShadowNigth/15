extends Node
## Full-project smoke test: choose a team, buy/equip every archi addition through
## the real PlayerController, open the animated buy menu and run a live bot round.
##   godot --headless --path . --fixed-fps 60 res://tests/ArchiGameWorldSmokeTest.tscn

const NEW_WEAPONS := [
	"p2000", "cz75", "revolver", "tec9", "famas", "galil", "m4a4",
	"mag7", "sawedoff", "negev", "bizon", "mp7", "taser", "decoy",
	"molotov", "incendiary",
]

var _checks := 0
var _failures: Array[String] = []
var _world: GameWorld = null


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[ARCHI GAMEWORLD TEST] " + description)


func _run() -> void:
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 9
	GameData.start_money = 800
	var packed := load("res://scenes/GameWorld.tscn") as PackedScene
	_expect(packed != null, "GameWorld scene must load")
	if packed == null:
		get_tree().quit(1)
		return
	_world = packed.instantiate() as GameWorld
	add_child(_world)
	_world._on_player_team_chosen("CT", "urban")
	_world.team_menu.close_menu()
	var player := _world.player
	_expect(player != null and player.is_alive, "Team choice spawns a living local player")
	_expect(_world.bots.size() == 9 and RoundManager.actors.size() == 10, "Team choice creates nine bots plus the player")
	_expect(RoundManager.state == RoundManager.State.FREEZE, "The real round enters freeze time")

	player.money = 16000
	for wid in NEW_WEAPONS:
		var spec: Dictionary = GameData.weapons[wid]
		# The real economy clamps money to $16,000; replenish only when this
		# cumulative purchase sequence would otherwise make the next test unaffordable.
		player.money = maxi(player.money, int(spec.get("price", 0)))
		player.team = String(spec.get("team", "ANY"))
		if player.team == "ANY":
			player.team = "CT"
		_place_in_buyzone(player.team)
		var bought := player.buy_weapon(wid)
		_expect(bought, "Real buy flow must purchase " + wid)
		if not bought:
			continue
		if bool(spec.get("grenade", false)):
			player.weapon_ctrl.equip_weapon_by_id(wid)
		_expect(player.weapon_ctrl.current_weapon_id == wid, "Real inventory equips " + wid)
		_expect(player._cur_vm_model_name == String(spec["v_model"]) and player._vm_anim != null, "PlayerController builds the archi viewmodel and AnimationPlayer for " + wid)

	_expect(RoundManager.dropped_items.size() >= 8, "Replacing bought weapons creates real dropped-world models")
	player.team = "CT"
	_place_in_buyzone("CT")
	_world.buy_menu.open_menu(player)
	_expect(_world.buy_menu.is_open, "Circular buy menu opens in the real buy zone")
	_expect(_world.buy_menu._pv_model != null and _world.buy_menu._pv_skel != null, "Buy menu creates its character preview")
	for i in range(6):
		await get_tree().process_frame
	_expect(_world.buy_menu._pv_anim_t > 0.0 and not String(_world.buy_menu._pv_lower_name).is_empty(), "Buy menu preview advances a real animation instead of a T-pose")
	_world.buy_menu.open_category(4)
	_expect(_world.buy_menu.current_category == 4, "Circular weapon category navigation works")
	_world.buy_menu.close_menu()
	player.ui_blocking_input = false

	for i in range(600):
		await get_tree().process_frame
	_expect(RoundManager.state == RoundManager.State.LIVE, "Freeze time finishes and the bot round goes live")
	_expect(RoundManager.actors.size() == 10 and is_instance_valid(_world.player), "The live scene retains its real actors")
	await _test_live_incendiary_spread()

	if _failures.is_empty():
		print("[ARCHI GAMEWORLD TEST] PASS: %d checks; 16 purchases, animated buy preview, 9 bots, 600 live-round frames and physical incendiary spread." % _checks)
	else:
		print("[ARCHI GAMEWORLD TEST] FAIL: %d of %d checks failed." % [_failures.size(), _checks])
	_stop_audio()
	# Fixed-FPS headless frames can outrun the real audio thread. Give its stop
	# commands wall-clock time before ObjectDB shutdown.
	OS.delay_msec(100)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_live_incendiary_spread() -> void:
	var player := _world.player
	var space := player.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP * 0.45,
		player.global_position - Vector3.UP * 5.0
	)
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	_expect(not hit.is_empty(), "Incendiary live test finds real de_dust2 floor geometry")
	if hit.is_empty():
		return
	var area := IncendiaryArea.new()
	_world.add_child(area)
	area.global_position = (hit["position"] as Vector3) + Vector3.UP * 0.025
	area.setup_fire(player, "incendiary")
	area._tick = 999.0 # This smoke check isolates propagation; the unit suite covers damage.
	_expect(area._patches.size() == 1, "Live incendiary starts as a single ignition patch")
	for _frame in range(75):
		await get_tree().process_frame
	_expect(is_instance_valid(area) and area._patches.size() > 3 and area._current_radius > 1.0,
		"Incendiary expands across the real map with staggered physical patches")
	if is_instance_valid(area):
		area.queue_free()


func _place_in_buyzone(team: String) -> void:
	var wanted := "2" if team == "CT" else "1"
	for raw in _world.buyzones:
		if String(raw["team"]) not in ["0", wanted]:
			continue
		var box: AABB = raw["aabb"]
		_world.player.global_position = box.get_center()
		_world.player.velocity = Vector3.ZERO
		return


func _stop_audio() -> void:
	for player in AudioManager._players_2d:
		player.stop()
		player.stream = null
	for player in AudioManager._players_3d:
		player.stop()
		player.stream = null
