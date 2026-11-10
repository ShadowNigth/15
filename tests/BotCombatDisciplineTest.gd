extends Node3D
var checks := 0
var failures := 0
var bot_navigator: BotNavigator = null
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[BOT DISCIPLINE] " + message)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	for distance in [1.0, 11.5, 12.0, 23.0, 24.0, 80.0]:
		expect(BotCombatDiscipline.burst_limit(distance, true, 1) == 1, "single sniper shots")
		expect(BotCombatDiscipline.burst_limit(distance, false, 2) == 1, "pistol pacing")
		expect(BotCombatDiscipline.burst_limit(distance, false, 1) <= 10, "finite rifle bursts")
	expect(BotCombatDiscipline.burst_limit(30, false, 1) < BotCombatDiscipline.burst_limit(5, false, 1), "distance controls burst length")
	expect(not BotCombatDiscipline.stable_enough(30, 4, false, 1), "running rifle does not shoot distant target")
	expect(BotCombatDiscipline.stable_enough(30, 0.5, false, 1), "settled rifle can fire")
	expect(BotCombatDiscipline.stable_enough(5, 4, false, 1), "near threat can be fought moving")
	expect(not BotCombatDiscipline.stable_enough(5, 2, true, 1), "sniper must settle")
	for urgent in [false, true]:
		for route in [false, true]:
			for reload in [false, true]:
				expect(BotCombatDiscipline.advance_objective(30, urgent, route, reload) == (urgent and route and not reload), "objective precedence")
				expect(not BotCombatDiscipline.advance_objective(5, urgent, route, reload), "close threat interrupts mission")
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collision.shape = shape
	floor_body.position.y = -0.5
	floor_body.add_child(collision)
	add_child(floor_body)
	var bot := CSBot.new()
	add_child(bot)
	bot.set_team_and_class("CT", "urban")
	bot.spawn_for_round(Vector3(0, 0.03, 0), 0, true)
	bot.set_physics_process(false)
	bot.weapon_ctrl.set_process(false)
	var enemy := CSActor.new()
	enemy.team = "T"
	add_child(enemy)
	enemy.spawn_for_round(Vector3(0, 0.03, -30), 0, true)
	enemy.health = 10000
	enemy.set_physics_process(false)
	bot.target_enemy = enemy
	bot.weapon_ctrl.give_weapon("ak47", 30, 90)
	bot.weapon_ctrl.equip_weapon_by_id("ak47")
	bot._reaction_timer = 0
	bot._grenade_cooldown = 100
	bot._burst_stop_timer = 10
	await get_tree().physics_frame
	for i in 3:
		bot.velocity = Vector3.ZERO
		bot.weapon_ctrl.fire_cooldown = 0
		bot._engage_enemy(0.016)
	expect(bot._tactical_burst_shots == 3, "production counts three real shots")
	var clip := int(bot.weapon_ctrl.clips["ak47"])
	bot.weapon_ctrl.fire_cooldown = 0
	bot._engage_enemy(0.016)
	expect(bot._burst_pause_timer > 0, "production starts pause")
	expect(int(bot.weapon_ctrl.clips["ak47"]) == clip, "pause emits no bullet")
	bot.weapon_ctrl.shots_fired = 0
	bot._engage_enemy(0.016)
	expect(int(bot.weapon_ctrl.clips["ak47"]) == clip, "recoil decay does not bypass pause")
	bot._burst_pause_timer = 0.001
	bot.weapon_ctrl.fire_cooldown = 0
	bot._engage_enemy(0.016)
	expect(bot._tactical_burst_shots == 1, "pause restarts actual shot counter")
	bot.spawn_for_round(Vector3.ZERO, 0, true)
	expect(bot._tactical_burst_shots == 0 and bot._tactical_burst_weapon.is_empty(), "round reset")
	bot.bomb_role = "defuse"
	expect(bot._combat_objective_is_urgent(), "elected defuser has urgent objective")
	bot.queue_free()
	enemy.queue_free()
	await get_tree().process_frame
	RoundManager.game_world = null
	print("PASS: Bot combat discipline ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
