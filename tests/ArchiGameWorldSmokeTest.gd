extends Node
## Full-project smoke test: choose a team, buy/equip every archi addition through
## the real PlayerController, open the animated buy menu and run a live bot round.
##   godot --headless --path . --fixed-fps 60 res://tests/ArchiGameWorldSmokeTest.tscn

const NEW_WEAPONS := [
	"p2000", "cz75", "revolver", "tec9", "famas", "galil", "m4a4",
	"mag7", "sawedoff", "negev", "bizon", "mp7", "taser", "decoy",
	"molotov", "incendiary",
]
const INSPECTION_ROTATIONS := {
	"deagle": ["inspect", "inspect_2"],
	"c4": ["inspect", "inspect_2", "inspect_3"],
	"flashbang": ["inspect", "inspect_2"],
	"hegrenade": ["inspect", "inspect_2"],
	"smokegrenade": ["inspect", "inspect_2"],
	"decoy": ["inspect", "inspect_2"],
	"molotov": ["inspect", "inspect_2"],
	"incendiary": ["inspect", "inspect_2"],
}

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
	print("[ARCHI GAMEWORLD TEST] phase=load")
	GameData.select_glove("classic")
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
	_expect(_player_original_arms_only(player), "Match start uses only the original arms and gloves")

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
		_expect(_player_original_arms_only(player), "Equipping %s uses only the original arms and gloves" % wid)

	_expect(RoundManager.dropped_items.size() >= 8, "Replacing bought weapons creates real dropped-world models")
	print("[ARCHI GAMEWORLD TEST] phase=buy-menu")
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

	for wid in ["m4a1", "usp"]:
		player.team = "CT"
		player.weapon_ctrl.silenced_state[wid] = false
		player.weapon_ctrl.give_weapon(wid, 30, 90)
		player.weapon_ctrl.equip_weapon_by_id(wid)
		await get_tree().process_frame
		_expect(player._vm_silencer_skeleton != null and player._vm_silencer_bone >= 0,
			"%s resolves its dedicated suppressor bone" % wid)
		if player._vm_silencer_skeleton == null or player._vm_silencer_bone < 0:
			continue
		var skeleton := player._vm_silencer_skeleton
		var bone := player._vm_silencer_bone
		var original_root := player._vm_model_root
		var bone_scale := skeleton.get_bone_pose_scale(bone)
		_expect(bone_scale.x < 0.001, "Unsilenced %s starts without a visible suppressor" % wid)
		player.weapon_ctrl.fire_cooldown = 0.0
		player.weapon_ctrl.trigger_secondary()
		_expect(player.weapon_ctrl.is_attaching_silencer and player._vm_anim.current_animation == "add_silencer",
			"%s secondary fire begins its real add_silencer clip" % wid)
		var clip := player._vm_anim.get_animation("add_silencer")
		player._vm_anim.advance(0.20)
		player._apply_vm_silencer_visibility()
		skeleton.force_update_all_bone_transforms()
		var hand_pose := skeleton.get_bone_global_pose(bone)
		bone_scale = skeleton.get_bone_pose_scale(bone)
		_expect(bone_scale.is_equal_approx(Vector3.ONE),
			"%s suppressor is visible in the hand 0.20s into attachment" % wid)
		player._vm_anim.advance(clip.length * 0.5 - 0.20)
		player._apply_vm_silencer_visibility()
		skeleton.force_update_all_bone_transforms()
		var middle_pose := skeleton.get_bone_global_pose(bone)
		bone_scale = skeleton.get_bone_pose_scale(bone)
		_expect(bone_scale.is_equal_approx(Vector3.ONE) and hand_pose.origin.distance_to(middle_pose.origin) > 0.0001,
			"%s suppressor stays visible while following its animated hand-to-barrel path" % wid)
		player.weapon_ctrl._process(player.weapon_ctrl.reload_timer + 0.01)
		await get_tree().process_frame
		bone_scale = skeleton.get_bone_pose_scale(bone)
		_expect(bool(player.weapon_ctrl.silenced_state[wid]) and bone_scale.is_equal_approx(Vector3.ONE) \
			and player._vm_model_root == original_root,
			"%s finishes attached on the same viewmodel without replaying draw" % wid)
		player.weapon_ctrl.fire_cooldown = 0.0
		player.weapon_ctrl.trigger_secondary()
		player._vm_anim.advance(0.20)
		player._apply_vm_silencer_visibility()
		bone_scale = skeleton.get_bone_pose_scale(bone)
		_expect(bone_scale.is_equal_approx(Vector3.ONE),
			"%s suppressor remains visible during detach animation" % wid)
		player.weapon_ctrl._process(player.weapon_ctrl.reload_timer + 0.01)
		await get_tree().process_frame
		bone_scale = skeleton.get_bone_pose_scale(bone)
		_expect(not bool(player.weapon_ctrl.silenced_state[wid]) and bone_scale.x < 0.001 \
			and player._vm_model_root == original_root,
			"%s hides the suppressor only after detaching completes" % wid)

	var inspect_key_bound := false
	for event in InputMap.action_get_events("inspect"):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode == KEY_T or key_event.physical_keycode == KEY_T:
				inspect_key_bound = true
	_expect(inspect_key_bound, "T remains bound to the real inspection input action")
	await _test_inspection_rotation(player)

	# The previously reported T + Glock case must now use only its original arms.
	player.team = "T"
	player.weapon_ctrl.give_weapon("glock18", 20, 40)
	player.weapon_ctrl.equip_weapon_by_id("glock18")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_player_original_arms_only(player), "T Glock uses only its original arms and gloves")
	if player._vm_anim != null and player._vm_anim.has_animation("draw"):
		player._vm_anim.play("draw")
		player._vm_anim.advance(0.55)
	_expect(_player_original_arms_only(player), "T Glock retains the original arm composition at draw midpoint")

	GameData.select_glove("arid_mw")
	player.weapon_ctrl.give_weapon("ak47", 30, 90)
	player.weapon_ctrl.equip_weapon_by_id("ak47")
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(_player_sport_gloves(player, "arid_mw"), "Real PlayerController installs the selected Sport gloves and original arms")
	if player._vm_anim != null and player._vm_anim.has_animation("draw"):
		player._vm_anim.play("draw")
		player._vm_anim.advance(0.55)
	_expect(_player_sport_gloves(player, "arid_mw"), "Sport glove composition remains valid through the real draw animation")
	_test_viewmodel_studio(player)
	print("[ARCHI GAMEWORLD TEST] phase=inspections-complete")
	GameData.select_glove("classic")
	player.weapon_ctrl.give_weapon("m4a1", 30, 90)
	player.weapon_ctrl.equip_weapon_by_id("m4a1")
	await get_tree().process_frame
	_expect(_player_original_arms_only(player), "Switching back to Original restores the classic gloves without overlap")

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

	print("[ARCHI GAMEWORLD TEST] phase=live-round-600")
	for i in range(600):
		if i % 120 == 0:
			print("[ARCHI GAMEWORLD TEST] live_frame=%d" % i)
		await get_tree().process_frame
	print("[ARCHI GAMEWORLD TEST] phase=incendiary-and-c4")
	_expect(RoundManager.state == RoundManager.State.LIVE, "Freeze time finishes and the bot round goes live")
	_expect(RoundManager.actors.size() == 10 and is_instance_valid(_world.player), "The live scene retains its real actors")
	await _test_live_incendiary_spread()
	_test_single_c4_round_assignment()

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


func _test_viewmodel_studio(player: PlayerController) -> void:
	_expect(player._vm_viewport != null and player._vm_viewport.own_world_3d \
		and player._vm_viewport.msaa_3d == Viewport.MSAA_4X,
		"First-person HD presentation uses its own 4x-MSAA studio viewport")
	var key := player._vm_viewport.get_node_or_null("ViewModelStudioKey") as DirectionalLight3D
	var fill := player._vm_viewport.get_node_or_null("ViewModelStudioFill") as DirectionalLight3D
	var softbox := player._vm_camera.get_node_or_null("ViewModelStudioSoftbox") as OmniLight3D
	_expect(key != null and fill != null and softbox != null \
		and key.light_cull_mask == 4 and fill.light_cull_mask == 4 and softbox.light_cull_mask == 4,
		"Studio key, fill and softbox illuminate only the first-person render layer")
	var studio_environment := player._vm_viewport.get_node_or_null("ViewModelStudioEnvironment") as WorldEnvironment
	var chrome_ok := false
	if studio_environment != null and studio_environment.environment != null:
		var environment := studio_environment.environment
		var sky := environment.sky
		var panorama := sky.sky_material as PanoramaSkyMaterial if sky != null else null
		chrome_ok = environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY \
			and sky != null and panorama != null and panorama.panorama != null \
			and panorama.panorama.get_size() == Vector2(512, 256) \
			and is_equal_approx(panorama.energy_multiplier, 0.68) \
			and player._vm_viewport.transparent_bg
	_expect(chrome_ok, "Chrome uses a filtered studio radiance sky without drawing a background")
	var hd_ok := false
	if player._vm_model_root != null:
		for node in player._vm_model_root.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null:
				continue
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				if material == null or material.resource_name.to_lower() != "weapon_rif_ak47":
					continue
				var entry: Dictionary = GameData.archi_materials.get("weapon_rif_ak47", {})
				hd_ok = material.albedo_texture == GameData.get_texture(String(entry.get("color", ""))) \
					and material.normal_texture == GameData.get_texture(String(entry.get("normal", ""))) \
					and material.roughness_texture == GameData.get_texture(String(entry.get("roughness", "")))
	_expect(hd_ok, "The real first-person AK retains the same HD colour, normal and roughness maps as the Arsenal")
	_expect(player._vm_muzzle_light != null and not player._vm_muzzle_light.visible \
		and player._vm_muzzle_light.light_cull_mask == 4,
		"The isolated viewmodel has its own bounded muzzle-light companion")
	player._on_fired_shot("ak47", false)
	_expect(player._muzzle_light.visible and player._vm_muzzle_light.visible \
		and player._vm_muzzle_light.position == player._muzzle_light.position \
		and is_equal_approx(player._vm_muzzle_light.light_energy, player._muzzle_light.light_energy),
		"Firing synchronizes world and first-person muzzle illumination")
	player._muzzle_timer = 0.0001
	player._process(0.001)
	_expect(not player._muzzle_light.visible and not player._vm_muzzle_light.visible,
		"Both muzzle lights switch off after the same short flash")


func _test_inspection_rotation(player: PlayerController) -> void:
	player._inspect_variant_indices.clear()
	for wid in INSPECTION_ROTATIONS:
		var expected: Array = INSPECTION_ROTATIONS[wid]
		player.weapon_ctrl.give_weapon(wid, 30, 90)
		player.weapon_ctrl.equip_weapon_by_id(wid)
		await get_tree().process_frame
		_expect(player._vm_anim != null and player._available_inspection_clips() == expected,
			"%s exposes its complete ordered inspection rotation" % wid)
		if player._vm_anim == null:
			continue
		for clip_name in expected:
			_press_inspect(player)
			_expect(player._vm_anim.current_animation == String(clip_name),
				"%s T selects %s" % [wid, clip_name])
			if wid == "deagle" and clip_name == "inspect_2":
				_expect(player._pending_vm_events.size() == 9,
					"Deagle T schedules all nine authentic inspect_2 foley events")
		_press_inspect(player)
		_expect(player._vm_anim.current_animation == "inspect",
			"%s inspection rotation wraps to the original clip" % wid)
		if wid == "deagle":
			player.weapon_ctrl.is_reloading = true
			player._vm_anim.play("idle")
			_press_inspect(player)
			_expect(player._vm_anim.current_animation == "idle",
				"Reload still blocks inspection variant selection")
			player.weapon_ctrl.is_reloading = false
		if wid == "c4":
			player.weapon_ctrl.plant_progress = 0.5
			player._vm_anim.play("idle")
			_press_inspect(player)
			_expect(player._vm_anim.current_animation == "idle",
				"C4 planting blocks all three inspection variants")
			player.weapon_ctrl.plant_progress = 0.0


func _press_inspect(player: PlayerController) -> void:
	var event := InputEventAction.new()
	event.action = "inspect"
	event.pressed = true
	player._unhandled_input(event)


func _player_original_arms_only(player: PlayerController) -> bool:
	if player == null or player._vm_model_root == null:
		return false
	var original_arms := false
	var original_gloves := false
	for node in player._vm_model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.has_meta("loadout_kind") or mesh.mesh == null:
			return false
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			var material_name := material.resource_name.to_lower() if material != null else ""
			if material_name == "ct_arms.bmp":
				original_arms = true
			elif material_name == "ct_base_glove.bmp":
				original_gloves = true
			elif material_name.begins_with("bare_arm") or material_name.begins_with("glove_") \
				or material_name.begins_with("sleeve"):
				return false
	return original_arms and original_gloves


func _player_sport_gloves(player: PlayerController, expected_id: String) -> bool:
	if player == null or player._vm_model_root == null:
		return false
	var original_arms := false
	var original_glove := false
	var sport_surfaces := 0
	var textured := true
	for node in player._vm_model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.has_meta("loadout_kind"):
			return false
		if mesh.has_meta("sport_gloves"):
			if String(mesh.get_meta("sport_glove_id", "")) != expected_id or mesh.skin == null:
				return false
			sport_surfaces += mesh.mesh.get_surface_count()
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				textured = textured and material != null and material.albedo_texture != null
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			var material_name := material.resource_name.to_lower() if material != null else ""
			if material_name == "ct_arms.bmp":
				original_arms = true
			elif material_name == "ct_base_glove.bmp":
				original_glove = true
	return textured and original_arms and not original_glove and sport_surfaces == 10


func _test_single_c4_round_assignment() -> void:
	var terrorists: Array[CSActor] = []
	for raw in RoundManager.actors:
		var actor := raw as CSActor
		if actor != null and actor.team == "T":
			terrorists.append(actor)
	_expect(terrorists.size() >= 2, "Round reset test has at least two terrorist survivors")
	if terrorists.size() < 2:
		return
	for index in range(2):
		terrorists[index].is_alive = true
		terrorists[index].health = 100
		terrorists[index].weapon_ctrl.give_weapon("c4", 1, 0)
		terrorists[index].weapon_ctrl.equip_weapon_by_id("c4")
	var stale_c4_drop := DroppedWeapon.new()
	_world.add_child(stale_c4_drop)
	stale_c4_drop.setup_drop("c4", 0, 0, Vector3.ZERO)
	RoundManager.dropped_items.append(stale_c4_drop)
	_world.prepare_round_entities(false)
	var carriers := 0
	var stale_equipped := 0
	for actor in terrorists:
		if String(actor.weapon_ctrl.slots.get(5, "")) == "c4":
			carriers += 1
		if actor.weapon_ctrl.current_weapon_id == "c4":
			stale_equipped += 1
	_expect(carriers == 1, "Two surviving C4 carriers are reduced to exactly one bomb next round")
	_expect(stale_equipped == 0, "Removed duplicate C4 inventories never leave a stale equipped bomb")
	var dropped_bombs := 0
	for raw in RoundManager.dropped_items:
		if is_instance_valid(raw) and String((raw as DroppedWeapon).item_id) == "c4":
			dropped_bombs += 1
	_expect(dropped_bombs == 0, "Round preparation leaves no duplicate dropped C4 behind")
	_expect(is_instance_valid(stale_c4_drop) and stale_c4_drop.is_queued_for_deletion(),
		"Previous-round ground C4 is explicitly queued for removal")
	_expect(carriers + dropped_bombs == 1,
		"Exactly one legitimate C4 remains across surviving inventories and registered drops")


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
