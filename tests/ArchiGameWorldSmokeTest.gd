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
	await get_tree().process_frame
	_expect(_player_loadout_matches(player), "Match start applies the selected CT gloves and sleeves")

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
		_expect(_player_loadout_matches(player), "Equipping %s applies the current team's selected arms" % wid)

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

	player.team = "CT"
	player.weapon_ctrl.give_weapon("m4a1", 30, 90)
	player.weapon_ctrl.equip_weapon_by_id("m4a1")
	await get_tree().process_frame
	_expect(player._vm_silencer_skeleton != null and player._vm_silencer_bone >= 0,
		"M4A1 resolves its dedicated suppressor bone")
	if player._vm_silencer_skeleton != null and player._vm_silencer_bone >= 0:
		var original_root := player._vm_model_root
		var bone_scale := player._vm_silencer_skeleton.get_bone_pose_scale(player._vm_silencer_bone)
		_expect(bone_scale.x < 0.001, "Unsilenced M4A1 starts without a visible suppressor")
		player.weapon_ctrl.fire_cooldown = 0.0
		player.weapon_ctrl.trigger_secondary()
		_expect(player.weapon_ctrl.is_attaching_silencer, "M4A1 secondary fire begins silencer attachment")
		player.weapon_ctrl._process(player.weapon_ctrl.reload_timer + 0.01)
		await get_tree().process_frame
		bone_scale = player._vm_silencer_skeleton.get_bone_pose_scale(player._vm_silencer_bone)
		_expect(bool(player.weapon_ctrl.silenced_state["m4a1"]) and bone_scale.is_equal_approx(Vector3.ONE) \
			and player._vm_model_root == original_root,
			"Attaching restores the suppressor on the same viewmodel without replaying draw")
		player.weapon_ctrl.fire_cooldown = 0.0
		player.weapon_ctrl.trigger_secondary()
		player.weapon_ctrl._process(player.weapon_ctrl.reload_timer + 0.01)
		await get_tree().process_frame
		bone_scale = player._vm_silencer_skeleton.get_bone_pose_scale(player._vm_silencer_bone)
		_expect(not bool(player.weapon_ctrl.silenced_state["m4a1"]) and bone_scale.x < 0.001 \
			and player._vm_model_root == original_root,
			"Detaching hides only the suppressor even though the weapon model did not change")

	# Reproduce the reported case explicitly: terrorist gloves/sleeves on Glock.
	player.team = "T"
	player.weapon_ctrl.give_weapon("glock18", 20, 40)
	player.weapon_ctrl.equip_weapon_by_id("glock18")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_player_loadout_matches(player), "T Glock uses the selected Fingerless/Professional arms with native rigid binds")
	_expect(_player_arm_bounds_valid(player), "T Glock replacement arms remain human-sized during the live draw/idle transition")
	if player._vm_anim != null and player._vm_anim.has_animation("draw"):
		player._vm_anim.play("draw")
		player._vm_anim.advance(0.55)
	_expect(_player_arm_bounds_valid(player), "T Glock replacement arms remain human-sized at draw midpoint")

	if player._vm_model_root != null:
		player._vm_model_root.position += Vector3.ONE * 0.25
		await get_tree().process_frame
	_expect(player._vm_model_root != null and player._vm_model_root.transform == player._vm_model_rest_transform,
		"First-person weapon root recovers its calibrated transform after an interruption")
	if not _world.bots.is_empty():
		var bot := _world.bots[0] as CSActor
		if bot._held_weapon_model != null:
			var expected_scale := GameData.get_world_model_scale(bot.weapon_ctrl.current_weapon_id)
			_expect(absf(bot._held_weapon_model.scale.x - expected_scale) < 0.0001,
				"Third-person hand attachment applies the per-weapon calibrated scale")
			bot._held_weapon_model.position += Vector3.ONE * 0.25
			await get_tree().process_frame
			_expect(bot._held_weapon_model.transform == bot._held_weapon_rest_transform,
				"Third-person weapon root remains locked to its calibrated hand transform")

	for i in range(600):
		await get_tree().process_frame
	_expect(RoundManager.state == RoundManager.State.LIVE, "Freeze time finishes and the bot round goes live")
	_expect(RoundManager.actors.size() == 10 and is_instance_valid(_world.player), "The live scene retains its real actors")
	await _test_live_incendiary_spread()

	if _failures.is_empty():
		print("[ARCHI GAMEWORLD TEST] PASS: %d checks; 16 purchases, animated buy preview, 9 bots, 600 live-round frames and physical incendiary spread." % _checks)
	else:
		print("[ARCHI GAMEWORLD TEST] FAIL: %d of %d checks failed." % [_failures.size(), _checks])
	# Do not let actors start new footstep playbacks while the audio thread is
	# draining its stop commands during test shutdown.
	RoundManager.set_process(false)
	if is_instance_valid(_world):
		_world.set_process(false)
		_world.set_physics_process(false)
	for actor in RoundManager.actors:
		if is_instance_valid(actor):
			actor.set_process(false)
			actor.set_physics_process(false)
	_stop_audio()
	# Fixed-FPS headless frames can outrun the real audio thread. Give its stop
	# commands wall-clock time before ObjectDB shutdown.
	OS.delay_msec(100)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _player_loadout_matches(player: PlayerController) -> bool:
	if player == null or player._vm_model_root == null:
		return false
	var expected := GameData.get_viewmodel_loadout(player.team)
	var skeleton := _find_skeleton(player._vm_model_root)
	if skeleton == null:
		return false
	var found: Dictionary = {}
	for node in player._vm_model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.has_meta("loadout_kind"):
			continue
		var kind := String(mesh.get_meta("loadout_kind", ""))
		var option: Dictionary = expected.get(kind, {})
		found[kind] = String(mesh.get_meta("loadout_source", "")) == String(option.get("model", ""))
		if mesh.skin == null or mesh.get_node_or_null(mesh.skeleton) != skeleton \
			or not mesh.global_transform.is_equal_approx(skeleton.global_transform):
			return false
		for bind in range(mesh.skin.get_bind_count()):
			var bone := mesh.skin.get_bind_bone(bind)
			if not String(mesh.skin.get_bind_name(bind)).is_empty() or bone < 0 or bone >= skeleton.get_bone_count() \
				or not mesh.skin.get_bind_pose(bind).basis.get_scale().is_equal_approx(Vector3.ONE):
				return false
	return bool(found.get("gloves", false)) and bool(found.get("sleeves", false))


func _player_arm_bounds_valid(player: PlayerController) -> bool:
	var skeleton := _find_skeleton(player._vm_model_root)
	if skeleton == null:
		return false
	skeleton.force_update_all_bone_transforms()
	var count := 0
	for node in player._vm_model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.has_meta("loadout_kind"):
			continue
		count += 1
		var evaluated := _cpu_skin_bounds(mesh, skeleton)
		if not bool(evaluated.get("valid", false)):
			return false
		var box: AABB = evaluated["box"]
		if not box.position.is_finite() or not box.size.is_finite() \
			or box.size.length() <= 0.01 or box.size.length() >= 2.5:
			return false
	return count >= 2


func _cpu_skin_bounds(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Dictionary:
	if mesh == null or skeleton == null or mesh.mesh == null or mesh.skin == null:
		return {"valid": false}
	var joints: Array[Transform3D] = []
	var relative := mesh.global_transform.affine_inverse() * skeleton.global_transform
	for bind in range(mesh.skin.get_bind_count()):
		var bone := skeleton.find_bone(String(mesh.skin.get_bind_name(bind)))
		if String(mesh.skin.get_bind_name(bind)).is_empty():
			bone = mesh.skin.get_bind_bone(bind)
		if bone < 0 or bone >= skeleton.get_bone_count():
			return {"valid": false}
		joints.append(relative * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
	var minimum := Vector3.ZERO
	var maximum := Vector3.ZERO
	var count := 0
	for surface in range(mesh.mesh.get_surface_count()):
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if bones.size() < vertices.size() * 4 or weights.size() < vertices.size() * 4:
			return {"valid": false}
		for index in range(vertices.size()):
			var point := Vector3.ZERO
			for influence in range(4):
				var weight := weights[index * 4 + influence]
				var joint := bones[index * 4 + influence]
				if weight <= 0.0:
					continue
				if joint < 0 or joint >= joints.size():
					return {"valid": false}
				point += (joints[joint] * vertices[index]) * weight
			if count == 0:
				minimum = point
				maximum = point
			else:
				minimum = Vector3(minf(minimum.x, point.x), minf(minimum.y, point.y), minf(minimum.z, point.z))
				maximum = Vector3(maxf(maximum.x, point.x), maxf(maximum.y, point.y), maxf(maximum.z, point.z))
			count += 1
	return {"valid": count > 0, "box": AABB(minimum, maximum - minimum)}


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


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
