extends Node3D
var checks := 0
var failures := 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[HITBOX ACCURACY] " + label)
func _ready() -> void:
	run.call_deferred()
func trace(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, 16)
	query.collide_with_areas = true
	return get_world_3d().direct_space_state.intersect_ray(query)
func run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var rng := RandomNumberGenerator.new()
	rng.seed = 29410
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		var idle := WeaponAccuracy.cone(spec, 0, true, false, true, 1)
		expect(WeaponAccuracy.cone(spec, 0, true, true, true, 1) <= idle, "crouch accuracy " + wid)
		expect(WeaponAccuracy.cone(spec, 250, true, false, true, 1) >= idle, "movement penalty " + wid)
		expect(WeaponAccuracy.cone(spec, 0, false, false, true, 1) >= idle, "airborne penalty " + wid)
		expect(WeaponAccuracy.cone(spec, 0, true, false, true, 15) >= idle, "spray bloom " + wid)
		for shot in range(1, 40):
			var kick := BallisticModel.spray_kick(spec, shot, false)
			expect(kick == BallisticModel.spray_kick(spec, shot, false), "reproducible spray " + wid)
			expect(kick.is_finite(), "finite spray " + wid)
	var mean := Vector2.ZERO
	var bounded := true
	for sample in 12000:
		var offset := WeaponAccuracy.sample_disk(rng, 0.02)
		bounded = bounded and offset.length() <= 0.020001
		mean += offset
	expect(bounded, "spread never produces Gaussian outliers outside the cone")
	expect((mean / 12000.0).length() < 0.0005, "spread is centred, without horizontal or vertical bias")
	var target := Vector2.ZERO
	for shot in range(1, 31): target += BallisticModel.spray_kick(GameData.weapons.ak47, shot, false)
	expect(target.is_equal_approx(BallisticModel.spray_target(GameData.weapons.ak47, 30)), "AK kick deltas reproduce its full spray target")
	var original_classes: Dictionary = GameData.modern_agents.classes.duplicate()
	for modern in [true, false]:
		GameData.modern_agents.classes = original_classes if modern else {}
		for faction in ["CT", "T"]:
			for info in GameData.classes[faction]:
				var actor := CSActor.new()
				actor.is_alive = true
				add_child(actor)
				actor.set_physics_process(false)
				actor.set_process(false)
				actor.weapon_ctrl.set_process(false)
				actor.set_team_and_class(faction, String(info.id))
				var hitboxes := actor._bullet_hitboxes
				expect(hitboxes != null and hitboxes.entries.size() == 11, "complete regions " + info.id)
				var head: Dictionary = hitboxes.entries[0]
				expect(int(head.get("fitted_vertices", 0)) >= 12, "head fitted from actual agent mesh " + info.id)
				for crouch in [false, true]:
					for yaw in [0.0, PI * 0.5, PI]:
						actor.is_crouching = crouch
						actor._visual_crouch_t = 1.0 if crouch else 0.0
						actor.look_yaw = yaw
						actor._evaluate_character_pose(0.2)
						hitboxes.sync_pose()
						await get_tree().physics_frame
						await get_tree().physics_frame
						var area: Area3D = head.area
						var direction := Vector3(sin(yaw), 0, cos(yaw))
						var hit := trace(area.global_position + direction, area.global_position - direction)
						expect(not hit.is_empty() and int(hit.collider.get_meta("hitgroup", 0)) == 1, "head ray is head: " + info.id + " duck=" + str(crouch) + " yaw=" + str(yaw))
						if not hit.is_empty():
							actor.health = 100
							actor.armor = 0
							actor.take_bullet_damage(null, 5, 1.0, int(hit.collider.get_meta("hitgroup", 0)), "ak47", hit.position)
							expect(actor.health == 80, "actual head ray applies headshot damage " + info.id)
						var chest: Area3D = hitboxes.entries[1].area
						hit = trace(chest.global_position + direction, chest.global_position - direction)
						expect(not hit.is_empty() and int(hit.collider.get_meta("hitgroup", 0)) != 1, "chest must not become head " + info.id)
				actor.is_alive = false
				hitboxes.sync_pose()
				expect((head.area as Area3D).collision_layer == 0, "dead actor hitboxes disabled")
				actor.free()
	GameData.modern_agents.classes = original_classes
	var vip := CSActor.new()
	vip.is_vip = true
	vip.is_alive = true
	add_child(vip)
	vip.set_physics_process(false)
	vip.set_process(false)
	vip.weapon_ctrl.set_process(false)
	vip.set_team_and_class("CT", "urban")
	expect(int(vip._bullet_hitboxes.entries[0].get("fitted_vertices", 0)) >= 12, "VIP head is fitted too")
	vip.free()
	var controller := WeaponController.new()
	var actor := CSActor.new()
	actor.is_alive = true
	add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.weapon_ctrl.set_process(false)
	controller.setup_for_actor(actor)
	add_child(controller)
	for rate in [30, 60, 144]:
		controller._reset_states()
		controller.punch_angles = Vector2(6, -2)
		controller.accuracy_heat = 10
		for tick in rate: controller._process(1.0 / float(rate))
		expect(controller.punch_angles.length() < 0.04, "recoil recovery after idle " + str(rate))
		expect(controller.accuracy_heat < 0.16, "accuracy recovery after idle " + str(rate))
	controller.free()
	actor.free()
	print("[HITBOX ACCURACY] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
