extends Node
## Real-engine regression test for the ShadowNigth/archi weapon refresh.
## Run after import with:
##   godot --headless --path . res://tests/ArchiWeaponRuntimeTest.tscn

const EXPECTED_WEAPONS := 43
const EXPECTED_ARCHI_WAVS := 299

var _checks := 0
var _failures: Array[String] = []
var _world: TestWorld = null
var _actor: FakeActor = null
var _controller: WeaponController = null


class TestWorld:
	extends Node3D
	var breakables: Array = []


class FakeActor:
	extends CharacterBody3D
	var is_alive := true
	var is_human := false
	var team := "CT"
	var actor_name := "WeaponTest"
	var sequences: Array = []

	func get_eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.6, 0.0)

	func get_aim_basis(_punch: Vector2) -> Basis:
		return global_basis

	func get_vm_muzzle_world() -> Vector3:
		return get_eye_position() - global_basis.z * 0.35

	func play_viewmodel_sequence(names: Array) -> void:
		sequences.append(names)

	func trigger_upper_body_action(_action: String) -> void:
		pass


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[ARCHI TEST] " + description)


func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.actors.clear()
	RoundManager.hostages.clear()
	RoundManager.dropped_items.clear()
	RoundManager.smoke_clouds.clear()
	RoundManager.smoke_volumes.clear()

	_world = TestWorld.new()
	add_child(_world)
	RoundManager.game_world = _world
	_actor = FakeActor.new()
	_world.add_child(_actor)
	_controller = WeaponController.new()
	_actor.add_child(_controller)
	_controller.setup_for_actor(_actor)
	_controller.set_process(false)

	_test_assets()
	_test_mechanics()
	_test_crate_rule()

	if _failures.is_empty():
		print("[ARCHI TEST] PASS: %d checks; 43 slots, 129 GLBs and 299 archi WAVs loaded by Godot." % _checks)
	else:
		print("[ARCHI TEST] FAIL: %d of %d checks failed." % [_failures.size(), _checks])
	# Radio/weapon playback runs on the audio thread; stop it before the test's
	# immediate exit so headless runs do not report still-active WAV playbacks.
	for player in AudioManager._players_2d:
		player.stop()
		player.stream = null
	for player in AudioManager._players_3d:
		player.stop()
		player.stream = null
	OS.delay_msec(100)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_assets() -> void:
	_expect(GameData.weapons.size() == EXPECTED_WEAPONS, "weapon roster must contain 43 slots")
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		for key in ["v_model", "p_model", "w_model"]:
			var model_name := String(spec.get(key, ""))
			var packed := GameData.get_model_scene("weapons/" + model_name)
			_expect(packed != null, "%s %s must import as PackedScene" % [wid, key])
			if packed == null:
				continue
			var instance := packed.instantiate() as Node3D
			_expect(instance != null, "%s %s must instantiate" % [wid, key])
			if instance == null:
				continue
			_world.add_child(instance)
			_expect(_mesh_count(instance) > 0, "%s %s must contain meshes" % [wid, key])
			if key == "v_model":
				var player := _find_animation_player(instance)
				_expect(player != null, "%s must have an AnimationPlayer" % wid)
				if player != null:
					_expect(player.has_animation("idle"), "%s must have idle" % wid)
					_expect(player.has_animation("draw") or player.has_animation("deploy"), "%s must have its equip animation" % wid)
					if bool(spec.get("grenade", false)):
						_expect(player.has_animation("pullpin") and player.has_animation("throw") and player.has_animation("underhand"), "%s grenade pin/overhand/underhand clips" % wid)
					elif wid == "c4":
						_expect(player.has_animation("pressbutton"), "C4 planting animation")
					elif wid == "knife":
						_expect(player.has_animation("slash1") and player.has_animation("stab"), "Kukri slash and stab clips")
					elif wid != "taser":
						if wid == "glock18":
							_expect(player.has_animation("shoot") and player.has_animation("shoot2") and player.has_animation("shoot3"), "Glock semi/burst tracks")
						elif wid == "elite":
							_expect(player.has_animation("shoot_left1") and player.has_animation("shoot_right1"), "Elite alternating tracks")
						elif wid == "revolver":
							_expect(player.has_animation("fire") and player.has_animation("shoot1") and player.has_animation("prepare") and player.has_animation("alt1"), "R8 fire aliases, prepare and alt fire")
						else:
							_expect(player.has_animation("shoot1"), "%s must have shoot1" % wid)
						if bool(spec.get("shotgun_reload", false)):
							_expect(player.has_animation("start_reload") and player.has_animation("insert") and player.has_animation("after_reload"), "%s staged shotgun reload clips" % wid)
						else:
							_expect(player.has_animation("reload"), "%s reload clip" % wid)
					if bool(spec.get("silencer", false)):
						_expect(player.has_animation("add_silencer") and player.has_animation("detach_silencer") and player.has_animation("reload_unsil"), "%s silencer and unsuppressed reload clips" % wid)
			if key == "w_model":
				var bounds := _instance_bounds(instance)
				_expect(bounds.size.length() < 2.5, "%s world model has a stray mesh: %s" % [wid, str(bounds.size)])
				if wid == "elite":
					_expect(bounds.size.x < 0.55 and bounds.size.y < 0.25 and bounds.size.z < 0.40, "Elite world model must contain one aligned pistol")
			instance.free()
		var icon := GameData.get_texture("res://assets/ui/vgui/%s.png" % String(spec.get("vgui", "")))
		_expect(icon != null, "%s inventory icon must import" % wid)

	var wavs: Array[String] = []
	_collect_wavs("res://assets/sounds/weapons/archi", wavs)
	_expect(wavs.size() == EXPECTED_ARCHI_WAVS, "all 299 archi WAVs must be installed (found %d)" % wavs.size())
	for path in wavs:
		var stream := load(path) as AudioStream
		_expect(stream != null, "Godot must decode " + path)


func _test_mechanics() -> void:
	# FAMAS: one click produces exactly a three-round burst.
	_equip("famas", 25, 50)
	_controller.burst_state["famas"] = true
	_controller.trigger_primary(false, 0.016)
	_expect(int(_controller.clips["famas"]) == 24 and _controller.burst_remaining == 2, "FAMAS burst starts with one shot and two queued")
	_controller._process(0.06)
	_controller._process(0.06)
	_expect(int(_controller.clips["famas"]) == 22 and _controller.burst_remaining == 0, "FAMAS burst fires exactly three rounds")

	# R8: primary waits for the hammer, reload cancels that pending shot.
	_equip("revolver", 8, 8)
	_controller.clips["revolver"] = 7
	_controller.trigger_primary(false, 0.016)
	_expect(int(_controller.clips["revolver"]) == 7 and _controller._revolver_windup > 0.0, "R8 primary must not fire before hammer wind-up")
	_controller.start_reload()
	_controller._process(0.30)
	_expect(int(_controller.clips["revolver"]) == 7 and _controller._revolver_windup <= 0.0, "R8 reload cancels pending hammer shot")
	_controller._process(_controller.reload_timer + 0.05)
	_expect(int(_controller.clips["revolver"]) == 8, "R8 magazine/cylinder reload completes")
	_equip("revolver", 8, 8)
	_controller.trigger_primary(false, 0.016)
	_controller._process(0.22)
	_expect(int(_controller.clips["revolver"]) == 7, "R8 delayed primary fires after wind-up")
	_controller.fire_cooldown = 0.0
	_controller.trigger_secondary()
	_expect(int(_controller.clips["revolver"]) == 6 and _controller.revolver_alt_fire, "R8 secondary is immediate alt fire")

	# MAG-7 uses a magazine; Sawed-Off retains staged shell insertion.
	_equip("mag7", 5, 10)
	_controller.clips["mag7"] = 2
	_controller.start_reload()
	_expect(_controller.is_reloading and not bool(_controller.get_current_spec().get("shotgun_reload", false)), "MAG-7 must use magazine reload")
	_controller._process(_controller.reload_timer + 0.05)
	_expect(int(_controller.clips["mag7"]) == 5 and int(_controller.ammo_pool["buckshot"]) == 7 and not _controller.is_reloading, "MAG-7 magazine refills in one step")
	_equip("sawedoff", 7, 10)
	_controller.clips["sawedoff"] = 5
	_controller.start_reload()
	_controller._process(_controller.reload_timer + 0.02)
	_expect(int(_controller.clips["sawedoff"]) == 6 and _controller.is_reloading, "Sawed-Off inserts one shell and continues")
	var guard := 0
	while _controller.is_reloading and guard < 10:
		_controller._process(_controller.reload_timer + 0.02)
		guard += 1
	_expect(int(_controller.clips["sawedoff"]) == 7 and int(_controller.ammo_pool["buckshot"]) == 8, "Sawed-Off staged reload consumes exactly two shells")

	# Zeus consumes its only charge and uses the short-range electroshock path.
	_equip("taser", 1, 0)
	_controller.trigger_primary(false, 0.016)
	_expect(int(_controller.clips["taser"]) == 0, "Zeus consumes its single charge")
	_expect(float(_controller.get_current_spec().get("range", 0.0)) <= 180.0, "Zeus remains short range")

	_test_underhand_throw()
	_test_decoy()
	_test_fire_projectile("molotov")
	_test_fire_projectile("incendiary")


func _test_underhand_throw() -> void:
	_actor.is_human = true
	_equip("hegrenade", 1, 0)
	_controller.trigger_secondary()
	_controller._process(0.33)
	_controller.release_secondary()
	_expect(not _actor.sequences.is_empty() and _actor.sequences.back()[0] == "underhand", "Secondary grenade throw uses archi's underhand animation")
	_expect(int(_controller.grenades["hegrenade"]) == 0, "Underhand throw consumes the grenade")
	_actor.is_human = false


func _test_decoy() -> void:
	_equip("decoy", 1, 0)
	_controller.trigger_primary(false, 0.016)
	var projectile := _latest_grenade()
	_expect(projectile != null and projectile.grenade_type == "decoy", "Decoy throw creates its projectile")
	if projectile == null:
		return
	projectile.set_physics_process(false)
	projectile._detonate()
	_expect(projectile._decoy_active, "Decoy enters its timed sound-lure state")
	projectile._process_decoy(0.20)
	_expect(projectile._decoy_life > 0.0 and not projectile._decoy_sounds.is_empty(), "Decoy uses archi weapon sounds while active")
	projectile._process_decoy(12.0)
	_expect(projectile._detonated and not projectile._decoy_active, "Decoy expires into its final small burst")


func _test_fire_projectile(kind: String) -> void:
	var projectile := GrenadeProjectile.new()
	_world.add_child(projectile)
	projectile.setup_grenade(kind, _actor, Vector3.ZERO)
	projectile.set_physics_process(false)
	projectile._detonate()
	var area: IncendiaryArea = null
	for child in _world.get_children():
		if child is IncendiaryArea and child.area_type == kind:
			area = child
	_expect(area != null, "%s creates persistent fire" % kind)
	if area != null:
		_expect(not area._frames.is_empty() and area.life_left >= 7.0, "%s fire has animated frames and a real lifetime" % kind)
		area._damage_tick()


func _test_crate_rule() -> void:
	var crate := BSPBreakable.new()
	crate.health = 250.0
	crate.bulletproof = true
	crate.material_type = 1
	_world.add_child(crate)
	_world.breakables.append(crate)
	crate.apply_damage(500.0, Vector3.ZERO, false)
	_expect(crate.health == 250.0 and not crate.broken, "Bullets never destroy bomb-site crates")
	# Match the maximum C4 effect multiplier: one blast must leave HP remaining.
	RoundManager.apply_world_explosion_physics(Vector3.ZERO, 29.025, 0.0, 2.4725)
	_expect(not crate.broken and crate.health > 0.0 and crate.health < 250.0, "One C4-scale explosion damages but cannot delete a 250-HP crate")
	_world.breakables.clear()
	crate.free()


func _equip(wid: String, clip: int, reserve: int) -> void:
	_controller.clear_all_weapons()
	_controller.give_weapon(wid, clip, reserve)
	_controller.equip_weapon_by_id(wid)
	_controller.fire_cooldown = 0.0


func _latest_grenade() -> GrenadeProjectile:
	for i in range(_world.get_child_count() - 1, -1, -1):
		var child := _world.get_child(i)
		if child is GrenadeProjectile:
			return child
	return null


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _instance_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			var box: AABB = node.global_transform * node.get_aabb()
			result = box if first else result.merge(box)
			first = false
		for child in node.get_children():
			stack.append(child)
	return result


func _collect_wavs(directory: String, output: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			var path := directory + "/" + name
			if dir.current_is_dir():
				_collect_wavs(path, output)
			elif name.to_lower().ends_with(".wav"):
				output.append(path)
		name = dir.get_next()
	dir.list_dir_end()
