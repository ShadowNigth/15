extends Node3D
## Production ammo choice, pickup swaps, melee pursuit and environmental probes.
var bot_navigator: BotNavigator = null
var checks: int = 0
var failures: int = 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[BOT RESOURCE] " + label)

func block(pos: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	return body

func drop_at(wid: String, pos: Vector3, clip: int, reserve: int) -> DroppedWeapon:
	var drop := DroppedWeapon.new()
	drop.item_id = wid
	drop.clip_ammo = clip
	drop.reserve_ammo = reserve
	add_child(drop)
	drop.global_position = pos
	drop._pickup_cooldown = 0.0
	drop.set_physics_process(false)
	RoundManager.dropped_items.append(drop)
	return drop

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.map_mode = "de"
	RoundManager.game_world = self
	block(Vector3(0, -0.25, 0), Vector3(24, 0.5, 24))
	var bot := CSBot.new()
	bot.team = "CT"
	add_child(bot)
	bot.is_alive = true
	bot.set_physics_process(false)
	bot.weapon_ctrl.give_weapon("ak47", 0, 0)
	bot.weapon_ctrl.give_weapon("usp", 7, 0)
	bot.weapon_ctrl.equip_slot(1)
	bot._select_usable_gun()
	expect(bot.weapon_ctrl.current_weapon_id == "usp", "loaded pistol replaces dry rifle regardless of enemy range")
	bot.weapon_ctrl.clips["usp"] = 0
	bot.weapon_ctrl.ammo_pool["45acp"] = 0
	bot.weapon_ctrl.ammo_pool[String(GameData.weapons["usp"].ammo_type)] = 0
	bot._select_usable_gun()
	expect(not bot._has_usable_gun() and bot.weapon_ctrl.current_weapon_id == "knife", "fully exhausted guns fall back to knife")
	bot.weapon_ctrl.fire_cooldown = 0.2
	for i in range(20):
		bot._select_usable_gun()
	expect(is_equal_approx(bot.weapon_ctrl.fire_cooldown, 0.2), "fallback never restarts deploy delay each frame")
	bot.weapon_ctrl.ammo_pool[String(GameData.weapons["ak47"].ammo_type)] = 30
	bot._select_usable_gun()
	expect(bot.weapon_ctrl.current_weapon_id == "ak47", "reserve ammo is usable rather than abandoning a reloadable gun")
	bot.weapon_ctrl.ammo_pool[String(GameData.weapons["ak47"].ammo_type)] = 0
	bot.weapon_ctrl.equip_slot(3)
	await get_tree().physics_frame
	expect(bot._has_local_floor(Vector3.FORWARD), "floor supports local motion")
	bot.position = Vector3(0, 0, -11.6)
	expect(not bot._has_local_floor(Vector3.FORWARD), "edge probe detects unsupported drop")
	bot.position = Vector3(50, 0, 0)
	expect(bot._pick_open_escape_direction(Vector3.FORWARD) == Vector3.ZERO, "no valid floor means no random escape into void")
	bot.position = Vector3.ZERO
	var empty := drop_at("m4a1", Vector3(0, 0.15, -1), 0, 0)
	var usable := drop_at("m4a1", Vector3(0, 0.15, -3), 17, 23)
	expect(bot._find_visible_supply() == usable, "prefer usable visible gun, never an empty drop")
	usable.pickup_lock_actor = bot
	usable.pickup_lock_time = 5.0
	expect(bot._find_visible_supply() == null, "donor pickup lock respected")
	usable.pickup_lock_time = 0.0
	var wall := block(Vector3(0, 1, -1.5), Vector3(4, 3, 0.3))
	await get_tree().physics_frame
	expect(bot._find_visible_supply() == null, "wall hides dropped weapon")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	usable.position = Vector3(0, 0.15, -0.8)
	bot._supply_scan_left = 0.0
	expect(bot._seek_visible_supply(1.0/60.0), "nearby usable drop is collected")
	expect(bot.weapon_ctrl.current_weapon_id == "m4a1", "dry occupied primary slot can be replaced")
	expect(bot.weapon_ctrl.clips.get("m4a1", 0) == 17, "pickup preserves magazine")
	expect(bot.weapon_ctrl.ammo_pool.get(String(GameData.weapons["m4a1"].ammo_type), 0) == 23, "pickup preserves reserve")
	expect(usable.is_queued_for_deletion() and not RoundManager.dropped_items.has(usable), "picked gun consumed exactly once")
	expect(not bot.try_pickup_dropped(usable), "queued pickup cannot duplicate ammunition")
	expect(not bot.try_pickup_dropped(empty), "empty drop cannot replace loaded gun")
	RoundManager.dropped_items.clear()
	empty.queue_free()
	# Environmental decisions use real collision shapes, not canned flags.
	var ledge := block(Vector3(0, 0.4, -0.9), Vector3(1.5, 0.8, 0.5))
	await get_tree().physics_frame
	expect(bot._can_opportunistic_jump(Vector3.FORWARD), "low ledge with landing supports opportunistic jump")
	var ceiling := block(Vector3(0, 2.0, 0), Vector3(2, 0.2, 2))
	await get_tree().physics_frame
	expect(not bot._can_opportunistic_jump(Vector3.FORWARD), "ceiling cancels improvised jump")
	ceiling.queue_free()
	ledge.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var duct := block(Vector3(0, 1.65, -0.8), Vector3(2, 0.3, 0.3))
	await get_tree().physics_frame
	expect(bot._needs_crouch_clearance(Vector3.FORWARD), "low passage requests crouch")
	duct.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Drive actual GoldSrc movement with the dedicated melee decision, not strafing.
	bot.weapon_ctrl.clips["m4a1"] = 0
	bot.weapon_ctrl.ammo_pool[String(GameData.weapons["m4a1"].ammo_type)] = 0
	bot._supply_target = null
	var enemy := CSBot.new()
	enemy.team = "T"
	add_child(enemy)
	enemy.is_alive = true
	enemy.set_physics_process(false)
	enemy.position = Vector3(0, 0, -5)
	bot.target_enemy = enemy
	bot._select_usable_gun()
	var start_distance := bot.global_position.distance_to(enemy.global_position)
	for i in range(45):
		bot._engage_without_ammo(1.0/60.0)
		await get_tree().physics_frame
	expect(bot.weapon_ctrl.current_weapon_id == "knife", "melee remains equipped throughout pursuit")
	expect(bot.global_position.distance_to(enemy.global_position) < start_distance - 1.0, "real melee movement closes distance instead of rifle strafing")
	AudioManager.stop_all()
	if failures == 0:
		print("[BOT RESOURCE] PASS: %d checks" % checks)
	else:
		printerr("[BOT RESOURCE] FAIL: %d/%d" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
