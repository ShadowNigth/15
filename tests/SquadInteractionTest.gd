extends Node3D
var failures: int = 0
var checks: int = 0

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[SQUAD INPUT] " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.actors.clear()
	var first := Node.new()
	var second := Node.new()
	add_child(first)
	add_child(second)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameplayInputGate.acquire(first)
	GameplayInputGate.acquire(first)
	GameplayInputGate.acquire(second)
	expect(GameplayInputGate.blocked(), "nested modal owners block gameplay")
	GameplayInputGate.release(first)
	expect(GameplayInputGate.blocked() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "closing parent cannot capture over child")
	second.queue_free()
	await get_tree().process_frame
	expect(not GameplayInputGate.blocked(), "freed modal releases ownership")
	GameplayInputGate.acquire(first)
	GameplayInputGate.release(first, false)
	expect(not GameplayInputGate.blocked() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "QA noncapturing close releases owner")
	var bot := CSBot.new()
	add_child(bot)
	bot.set_physics_process(false)
	bot.team = "CT"
	bot.has_defuser = true
	var mate := CSBot.new()
	add_child(mate)
	mate.set_physics_process(false)
	mate.team = "CT"
	mate.global_position = Vector3(1, 0, 0)
	var bomb := PlantedC4.new()
	add_child(bomb)
	bomb.set_process(false)
	bomb.time_left = 30.0
	var squad: Array = [bot, mate]
	expect(BombSquad.elect_defuser(bomb, squad) == bot, "kit-aware defuse election")
	bomb.defuser_actor = mate
	bomb.defuse_progress = 2.0
	expect(BombSquad.elect_defuser(bomb, squad) == mate and bomb.defuse_progress == 2.0, "active defuser is retained without resetting progress")
	mate.is_alive = false
	expect(BombSquad.elect_defuser(bomb, squad) == bot, "dead defuser is replaced")
	var ctrl := bot.weapon_ctrl
	ctrl.burst_remaining = 2
	ctrl._revolver_windup = 0.2
	ctrl._grenade_pin_pulled = true
	ctrl._grenade_want_release = true
	ctrl.plant_progress = 0.4
	ctrl.suspend_input()
	expect(ctrl.burst_remaining == 0 and ctrl._revolver_windup == 0.0, "modal cancels queued burst and revolver")
	expect(not ctrl._grenade_pin_pulled and not ctrl._grenade_want_release and ctrl.plant_progress == 0.0, "modal cancels grenade intent and plant without releasing grenade")
	bot.queue_free()
	mate.queue_free()
	bomb.queue_free()
	first.queue_free()
	await get_tree().process_frame
	print("[SQUAD INPUT] %s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
