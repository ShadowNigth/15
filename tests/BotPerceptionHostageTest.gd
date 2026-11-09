extends Node3D
## Real collision/production perception tests; no replica AI implementation.
var checks: int = 0
var failures: int = 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[BOT PERCEPTION] " + message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.game_world = null
	RoundManager.actors.clear()
	var bot := CSBot.new()
	bot.team = "CT"
	add_child(bot)
	bot.set_physics_process(false)
	bot.is_alive = true
	var enemy := CSBot.new()
	enemy.team = "T"
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.is_alive = true
	enemy.position = Vector3(0, 0, -8)
	RoundManager.actors.assign([bot, enemy])
	await get_tree().physics_frame
	expect(bot._can_see_actor(enemy), "unobstructed visual contact")
	bot.target_enemy = enemy
	bot._validate_visual_contact()
	expect(bot.target_enemy == enemy, "visible target retained")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.position = Vector3(0, 1.5, -4)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 4, 0.5)
	shape.shape = box
	wall.add_child(shape)
	add_child(wall)
	await get_tree().physics_frame
	expect(not bot._can_see_actor(enemy), "wall blocks visibility")
	bot._last_enemy_pos = Vector3(2, 0, -2)
	bot._last_enemy_seen_age = 7.0
	bot._validate_visual_contact()
	expect(bot.target_enemy == null, "contact invalidated between tactical scans")
	var previous_memory := bot._last_enemy_pos
	var impact := Vector3(0.1, 1, 0)
	bot._on_taken_damage_from(enemy, impact)
	expect(bot.target_enemy == null, "hidden damage does not grant visual target")
	expect(bot._last_enemy_pos == previous_memory and bot._last_enemy_seen_age == 7.0, "hidden attacker does not overwrite visual memory")
	expect(bot._sound_investigate_pos == impact, "hidden hit stores local evidence, not attacker coordinates")
	wall.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	bot._on_taken_damage_from(enemy, impact)
	expect(bot.target_enemy == enemy and bot._last_enemy_pos == enemy.global_position, "visible attacker can be acquired")
	expect(not HostageNPC.should_follow(2.0, false, false), "waiting hostage keeps normal gap")
	expect(HostageNPC.should_follow(2.2, false, false), "hostage starts after outer threshold")
	expect(HostageNPC.should_follow(2.0, true, false), "moving hostage does not chatter at start threshold")
	expect(not HostageNPC.should_follow(1.6, true, false), "hostage stops at inner threshold")
	expect(HostageNPC.should_follow(0.5, false, true), "rescue completion overrides normal waiting gap")
	expect(not HostageNPC.should_follow(0.3, true, true), "rescue close-in remains bounded")
	var hostage := HostageNPC.new()
	add_child(hostage)
	hostage.set_physics_process(false)
	hostage.leader = bot
	hostage._following_motion = true
	bot.is_alive = false
	hostage._physics_process(1.0 / 60.0)
	expect(hostage.leader == null and not hostage._following_motion, "dead leader releases follower state")
	expect(hostage._nav_path.is_empty(), "dead leader clears stale path")
	AudioManager.stop_all()
	if failures == 0:
		print("[BOT PERCEPTION] PASS: %d checks" % checks)
	else:
		printerr("[BOT PERCEPTION] FAIL: %d/%d" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
