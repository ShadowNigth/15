extends Node3D
## Production movement + classic skeletons + production shot/weapon pickup pipeline.
var checks: int = 0
var failures: int = 0
var water: WaterEffects = null
var shots: Array[Dictionary] = []
var traces: Array[Dictionary] = []
var output: String = ""
var camera: Camera3D

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[SQUAD GAMEPLAY] " + label)

func block(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	body.add_child(visual)
	add_child(body)

func capture(label: String) -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	for frame in range(3):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	expect(get_viewport().get_texture().get_image().save_png(output.path_join(label+".png")) == OK, "rendered evidence " + label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(7771)
	output = OS.get_environment("SQUAD_CAPTURE_DIR")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.map_mode = "de"
	RoundManager.game_world = self
	RoundManager.actors.clear()
	block(Vector3(0, -0.25, 0), Vector3(24, 0.5, 24))
	# A narrow passage which widens at both ends. Actor masks stay exactly 2/1.
	block(Vector3(-1.0, 1, 0), Vector3(0.5, 2, 4))
	block(Vector3(1.0, 1, 0), Vector3(0.5, 2, 4))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 20, 0)
	add_child(light)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(6, 7, 8)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.current = true
	var first := CSBot.new()
	add_child(first)
	first.set_physics_process(false)
	first.set_team_and_class("CT", "urban")
	first.spawn_for_round(Vector3(0, 0.03, -1.6), PI, true)
	var second := CSBot.new()
	add_child(second)
	second.set_physics_process(false)
	second.set_team_and_class("CT", "gsg9")
	second.spawn_for_round(Vector3(0, 0.03, 1.6), 0, true)
	for frame in range(4):
		first.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0/60.0)
		second.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0/60.0)
		await get_tree().physics_frame
	await capture("corridor_before")
	var negotiated := false
	for frame in range(330):
		var first_goal := Vector3(0, first.global_position.y, 5)
		var second_goal := Vector3(0, second.global_position.y, -5)
		var wish_a := (first_goal-first.global_position).normalized() if first.global_position.distance_to(first_goal) > 0.3 else Vector3.ZERO
		var wish_b := (second_goal-second.global_position).normalized() if second.global_position.distance_to(second_goal) > 0.3 else Vector3.ZERO
		first.apply_goldsrc_movement(wish_a, false, false, false, 1.0/60.0)
		second.apply_goldsrc_movement(wish_b, false, false, false, 1.0/60.0)
		negotiated = negotiated or first.traffic.mode in ["wait", "yield", "sidestep"] or second.traffic.mode in ["wait", "yield", "sidestep"]
		await get_tree().physics_frame
		if frame == 75:
			await capture("corridor_yield")
	expect(negotiated, "real corridor encounter negotiates instead of overlapping unconditionally")
	expect(first.global_position.z > 2.0 and second.global_position.z < -2.0, "both bots pass and resume their goals")
	expect(first.collision_layer == 2 and first.collision_mask == 1, "classic actor masks unchanged")
	expect(first._banned_nodes.is_empty() and second._banned_nodes.is_empty(), "intentional yield does not ban authored graph nodes")
	await capture("corridor_after")
	second.queue_free()
	await get_tree().process_frame
	# Controlled idle evaluation must not accumulate IK, stretch limbs or move weapons.
	first.velocity = Vector3.ZERO
	first.weapon_ctrl.give_weapon("ak47", 30, 90)
	first.weapon_ctrl.equip_weapon_by_id("ak47")
	first._upper_action_key = ""
	first._evaluate_character_pose(0.0)
	var skeleton := first._skel
	expect(skeleton != null, "actual classic character skeleton loaded")
	var positions := PackedVector3Array()
	var rotations: Array[Quaternion] = []
	if skeleton != null:
		for i in range(skeleton.get_bone_count()):
			positions.append(skeleton.get_bone_pose_position(i))
			rotations.append(skeleton.get_bone_pose_rotation(i))
		for frame in range(90):
			first._evaluate_character_pose(0.0)
		for i in range(skeleton.get_bone_count()):
			expect(absf(rotations[i].dot(skeleton.get_bone_pose_rotation(i))) > 0.99999, "pose fitting does not accumulate rotation")
			expect(positions[i].distance_to(skeleton.get_bone_pose_position(i)) < 0.0001, "pose fitting does not accumulate bone translation")
		expect(first._held_weapon_model.transform.is_equal_approx(first._held_weapon_rest_transform), "weapon fixed attachment and scale preserved")
	var player := PlayerController.new()
	add_child(player)
	player.set_physics_process(false)
	player.set_team_and_class("CT", "urban")
	player.spawn_for_round(Vector3(-7, 0.03, 0), 0, true)
	player.weapon_ctrl.shot_audited.connect(func(facts: Dictionary): shots.append(facts))
	player.weapon_ctrl.tracer_audited.connect(func(facts: Dictionary): traces.append(facts))
	for wid in ["glock18", "m4a1", "awp", "famas", "elite", "m3"]:
		player.weapon_ctrl.give_weapon(wid, 20, 90)
		player.weapon_ctrl.equip_weapon_by_id(wid)
		player.weapon_ctrl.punch_angles = Vector2.ZERO
		var before := shots.size()
		player.weapon_ctrl._execute_bullet_shot(GameData.weapons[wid], false)
		expect(shots.size() == before+1, "one audited event per actual shot " + wid)
		if shots.size() > before:
			var shot: Dictionary = shots.back()
			expect(shot.clip_before-shot.clip_after == 1, "one cartridge per shot " + wid)
			expect(not String(shot.sound).is_empty(), "native sound path selected " + wid)
			expect((shot.aim as Vector3).dot(player.get_look_forward()) > 0.999, "ballistic aim remains on reticle before recoil " + wid)
			expect(not player._vm_anim.current_animation.is_empty(), "native firing animation triggered " + wid)
			expect(not traces.is_empty() and int(traces.back().serial) == int(shot.serial), "tracer and shot share identity " + wid)
			if not traces.is_empty():
				expect((traces.back().muzzle as Vector3).distance_to(player.get_vm_muzzle_world()) < 0.001, "tracer starts at animated muzzle " + wid)
		await get_tree().physics_frame
	# An explicit E swap preserves the outgoing clip and silencer; automatic pickup
	# still refuses replacing occupied slots.
	player.weapon_ctrl.give_weapon("m4a1", 17, 45)
	player.weapon_ctrl.equip_weapon_by_id("m4a1")
	player.weapon_ctrl.silenced_state["m4a1"] = true
	var incoming := DroppedWeapon.new()
	add_child(incoming)
	incoming.setup_drop("ak47", 11, 35, Vector3.ZERO)
	incoming._pickup_cooldown = 0.0
	incoming.position = player.position+Vector3(0, 0.15, -1)
	RoundManager.dropped_items.append(incoming)
	expect(not player.try_pickup_dropped(incoming), "automatic pickup cannot replace primary")
	expect(player.perform_use_selection({"kind": "drop", "target": incoming}), "explicit E swaps occupied primary")
	expect(String(player.weapon_ctrl.slots[1]) == "ak47" and int(player.weapon_ctrl.clips["ak47"]) == 11, "incoming weapon clip retained")
	var outgoing: DroppedWeapon = null
	for raw in RoundManager.dropped_items:
		if is_instance_valid(raw) and raw.item_id == "m4a1":
			outgoing = raw
	expect(outgoing != null and outgoing.clip_ammo == 17 and outgoing.silenced, "outgoing native weapon state retained")
	await capture("classic_pose_and_weapon")
	print("[SQUAD GAMEPLAY] %s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
