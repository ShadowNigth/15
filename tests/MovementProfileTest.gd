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
	for rate in [30.0, 60.0, 128.0]:
		var air := Vector3(4, 2, 0)
		for tick in int(rate):
			air = CS2ExperimentalPhysics.air_step(air, Vector3.FORWARD, cap, 1.0 / rate)
		expect(absf(air.y - 2) < 0.0001, "air steering preserves vertical component")
		expect(absf(air.x - 4) < 0.0001, "air steering preserves perpendicular momentum")
		expect(absf(air.z + CS2ExperimentalPhysics.AIR_WISH_CAP) < 0.001, "air projection cap at " + str(rate))
	var incoming := Vector3(5, -8, 2)
	for restitution in [CS2ExperimentalPhysics.GRENADE_RESTITUTION, CS2ExperimentalPhysics.OBJECT_RESTITUTION]:
		var bounce := CS2ExperimentalPhysics.impact(incoming, Vector3.UP, restitution)
		expect(bounce.y > 0 and bounce.length() < incoming.length(), "experimental impact loses energy and leaves surface")
		expect(CS2ExperimentalPhysics.impact(Vector3.UP, Vector3.UP, restitution) == Vector3.UP, "separating contact never reflects twice")
	expect(CS2ExperimentalPhysics.GRENADE_GRAVITY < CS2ExperimentalPhysics.GRAVITY, "grenade arc has independent gravity")
	expect(absf(CS2ExperimentalPhysics.JUMP_SPEED * CS2ExperimentalPhysics.JUMP_SPEED / (2 * CS2ExperimentalPhysics.GRAVITY) - 1.7812) < 0.01, "experimental ballistic apex approximately 57 map units")
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
			var supported_position := actor.global_position
			actor.global_position = Vector3(50.15, 0.03, 0)
			expect(actor._has_nearby_step_support(), "capsule edge support found when centre ray misses")
			actor.global_position = Vector3(50.6, 0.03, 0)
			expect(not actor._has_nearby_step_support(), "no support beyond capsule footprint")
			actor.global_position = Vector3(0, 0.8, 0)
			expect(not actor._has_nearby_step_support(), "airborne actor cannot step on a distant floor")
			actor.global_position = supported_position

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
			var jump_speed := CS2ExperimentalPhysics.JUMP_SPEED if profile == "cs2_experimental" else CSActor.JUMP_VEL_MPS
			expect(absf(actor.velocity.y - jump_speed) < 0.01, profile + " jump impulse selected")
			actor.position = Vector3(0, 20, 0)
			actor._corpse_vel = Vector3.ZERO
			actor._tick_corpse_grounding(1.0 / 60)
			expect(actor._corpse_vel.y < 0 and actor.position.y < 20, profile + " corpse actually falls")
			actor.free()
		var grenade := GrenadeProjectile.new()
		add_child(grenade)
		grenade.set_physics_process(false)
		grenade.position = Vector3(0, 20, 0)
		grenade.velocity = Vector3(4, 0, 0)
		grenade._physics_process(1.0 / 60)
		var grenade_gravity := CS2ExperimentalPhysics.GRENADE_GRAVITY if profile == "cs2_experimental" else 21.0
		expect(absf(grenade.velocity.y + grenade_gravity / 60.0) < 0.001, profile + " real grenade gravity")
		expect(grenade.position.x > 0, "real grenade keeps horizontal flight")
		grenade.free()
		var drop := DroppedWeapon.new()
		add_child(drop)
		drop.set_physics_process(false)
		drop.position = Vector3(0, 20, 0)
		drop._vel = Vector3(4, 0, 0)
		drop._step_swept_physics(get_world_3d().direct_space_state, 1.0 / 60)
		var drop_gravity := CS2ExperimentalPhysics.OBJECT_GRAVITY if profile == "cs2_experimental" else 21.5
		expect(absf(drop._vel.y + drop_gravity / 60.0) < 0.001, profile + " real equipment gravity")
		expect(drop.position.y < 20, "real equipment falls through swept path")
		drop.free()
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
