extends Node3D
var checks := 0
var failures := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[MOVEMENT] " + message)

func stop_time(input: Vector3, rate: float) -> float:
	var v := Vector3(250.0 / 32.0, 0, 0)
	for tick in int(rate):
		v = CS2GroundMovement.step(v, input, 250.0 / 32.0, 1.0 / rate)
		if v.x <= 0.1:
			return float(tick + 1) / rate
	return 1.0

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var old_profile: String = GameData.movement_profile
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var cap := 250.0 / 32.0
	expect(CS2GroundMovement.step(Vector3.ONE, Vector3.RIGHT, cap, 0) == Vector3.ONE, "zero delta")
	expect(CS2GroundMovement.step(Vector3(0, -4, 0), Vector3.RIGHT, cap, 0.1).y == -4, "vertical motion unaffected")
	for rate in [30.0, 60.0, 128.0]:
		var release := stop_time(Vector3.ZERO, rate)
		var opposite := stop_time(Vector3.LEFT, rate)
		expect(opposite < release, "counter-strafe brakes sooner than releasing at " + str(rate))
		expect(opposite > 0.03 and opposite < 0.2, "counter-strafe is progressive, not instant")
		print("[MOVEMENT] rate=", rate, " release_s=", release, " opposite_s=", opposite)
	expect(absf(stop_time(Vector3.ZERO, 30) - stop_time(Vector3.ZERO, 128)) < 0.04, "rate-stable release")
	for speed in [100.0 / 32.0, cap]:
		var straight := Vector3.ZERO
		var diagonal := Vector3.ZERO
		for tick in 128:
			straight = CS2GroundMovement.step(straight, Vector3.RIGHT, speed, 1.0 / 128)
			diagonal = CS2GroundMovement.step(diagonal, Vector3(1, 0, 1), speed, 1.0 / 128)
		expect(absf(straight.length() - speed) < 0.001, "weapon maximum respected")
		expect(absf(diagonal.length() - straight.length()) < 0.001, "no diagonal speed boost")
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.5, 100)
	collision.shape = box
	floor_body.position.y = -0.25
	floor_body.add_child(collision)
	add_child(floor_body)
	await get_tree().physics_frame
	for profile in ["goldsrc", "cs2_experimental"]:
		GameData.movement_profile = profile
		for human in [true, false]:
			var actor: CSActor = PlayerController.new() if human else CSBot.new()
			add_child(actor)
			actor.set_team_and_class("CT" if human else "T", "sas" if human else "terror")
			actor.spawn_for_round(Vector3(0, 0.02, 0), 0, true)
			actor.set_process(false)
			actor.set_physics_process(false)
			actor.set_process_unhandled_input(false)
			actor.weapon_ctrl.set_physics_process(false)
			actor.weapon_ctrl.set_process(false)
			for tick in 20:
				await get_tree().physics_frame
				actor.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0 / 60)
			expect(actor.is_on_floor(), profile + " actual floor contact")
			actor.velocity = Vector3(4, 0, 0)
			actor.stamina_factor = 1.0
			var max_speed := actor.weapon_ctrl.get_max_speed_gs() * GameData.SCALE
			var expected_x := CS2GroundMovement.step(actor.velocity, Vector3.LEFT, max_speed, 1.0 / 60).x
			if profile == "goldsrc":
				expected_x = 4.0 * (1.0 - CSActor.FRICTION / 60.0) - CSActor.GROUND_ACCEL * max_speed / 60.0
			await get_tree().physics_frame
			actor.apply_goldsrc_movement(Vector3.LEFT, false, false, false, 1.0 / 60)
			expect(absf(actor.velocity.x - expected_x) < 0.001, profile + " real actor selects correct equations")
			expect(is_equal_approx(actor._capsule.height, CSActor.STAND_HEIGHT), "movement hull unchanged")
			actor.velocity = Vector3.ZERO
			for tick in 60:
				await get_tree().physics_frame
				actor.apply_goldsrc_movement(Vector3.RIGHT, false, false, false, 1.0 / 60)
			expect(absf(actor.velocity.x - max_speed) < 0.01, profile + " live grounded acceleration reaches weapon speed")
			actor.stamina_factor = 1.0
			await get_tree().physics_frame
			actor.apply_goldsrc_movement(Vector3.ZERO, true, false, false, 1.0 / 60)
			expect(absf(actor.velocity.y - CSActor.JUMP_VEL_MPS) < 0.01, "jump impulse unchanged")
			actor.free()
	var menu := load("res://scenes/MainMenu.tscn").instantiate() as MainMenu
	add_child(menu)
	var selector := menu.find_child("MovementProfile", true, false) as OptionButton
	expect(selector != null and selector.item_count == 2, "both profiles accessible in Create Game")
	if selector != null:
		selector.item_selected.emit(1)
		expect(GameData.movement_profile == "goldsrc", "menu restores GoldSrc")
		selector.item_selected.emit(0)
		expect(GameData.movement_profile == "cs2_experimental", "menu enables experimental movement")
	menu.free()
	GameData.movement_profile = old_profile
	print("[MOVEMENT] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks, ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
