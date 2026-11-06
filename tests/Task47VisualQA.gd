extends Node
## Browser-rendered gameplay QA for task 47. Never changes production timings.
## Query: ?state=texture | fire | vip

var _state := "texture"
var _world: GameWorld = null
var _area: IncendiaryArea = null
var _vip: CSBot = null
var _vip_start := Vector3.ZERO
var _vip_moved := false
var _vip_escaped := false
var _camera: Camera3D = null
var _frame := 0
var _freeze_frame := -1
var _acked := false
var _resumed := false


func _ready() -> void:
	RoundManager.round_ended.connect(_capture_round_result)
	call_deferred("_run")


func _capture_round_result(winner: String, reason: String) -> void:
	_vip_escaped = winner == "CT" and reason.contains("The VIP has escaped!")
	print("[TASK47 QA] round result winner=%s reason=%s" % [winner, reason.replace("\n", " / ")])


func _web_bool(name: String, value: bool) -> void:
	# Ringozz's minimal Web build omits godot_js_eval. Console metrics are
	# consumed directly by Playwright and work identically in native QA.
	print("[TASK47 METRIC] %s=%s" % [name, "true" if value else "false"])


func _web_number(name: String, value: float) -> void:
	print("[TASK47 METRIC] %s=%f" % [name, value])


func _floor_snap(pos: Vector3) -> Vector3:
	if not is_instance_valid(_world):
		return pos
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 4.0, pos - Vector3.UP * 9.0)
	query.collision_mask = 1
	var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
	return (hit.get("position", pos) as Vector3) + Vector3.UP * 0.04 if not hit.is_empty() else pos


func _aim_player_at(target: Vector3) -> void:
	var player := _world.player
	var diff := target - player.get_eye_position()
	var horizontal := Vector2(diff.x, diff.z).length()
	if horizontal > 0.001:
		player.look_yaw = atan2(-diff.x, -diff.z)
		player.look_pitch = clampf(atan2(diff.y, horizontal), deg_to_rad(-70.0), deg_to_rad(70.0))


func _find_vip() -> CSBot:
	for raw in RoundManager.actors:
		var bot := raw as CSBot
		if is_instance_valid(bot) and bot.is_vip:
			return bot
	return null


func _run() -> void:
	print("[TASK47 QA] run entered web=%s bridge=%s" % [OS.has_feature("web"), Engine.has_singleton("JavaScriptBridge")])
	if OS.has_feature("web"):
		var requested := ""
		if FileAccess.file_exists("res://task47_qa_state.txt"):
			requested = FileAccess.get_file_as_string("res://task47_qa_state.txt").strip_edges()
		if requested not in ["texture", "fire", "vip"]:
			push_error("[TASK47 QA] Missing or invalid staged state: " + requested)
			return
		_state = requested
	else:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("state="):
				_state = arg.trim_prefix("state=")
			elif arg.begins_with("seed="):
				seed(int(arg.trim_prefix("seed=")))
		if _state not in ["texture", "fire", "vip"]:
			push_error("[TASK47 QA] Invalid native state: " + _state)
			return
	GameData.selected_map = "as_oilrig" if _state == "vip" else "de_dust2"
	GameData.bot_count = 5 if _state == "vip" else 0
	GameData.start_money = 16000
	var packed := load("res://scenes/GameWorld.tscn") as PackedScene
	if packed == null:
		push_error("[TASK47 QA] GameWorld failed to load")
		return
	_world = packed.instantiate() as GameWorld
	add_child(_world)
	print("[TASK47 QA] world added state=%s" % _state)
	_world._on_player_team_chosen("T" if _state == "vip" else "CT", "terror" if _state == "vip" else "urban", false)
	print("[TASK47 QA] team selected")
	_world.team_menu.close_menu(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.state_timer = 180.0
	RoundManager.buy_time_left = 0.0
	print("[TASK47 QA] awaiting physics")
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[TASK47 QA] physics resumed")
	_world.player.set_physics_process(false)

	if _state == "vip":
		# Prevent a stationary human T or an environmental death from producing
		# a false CT elimination win before the physical extraction assertion.
		_world.player.team = "SPECTATOR"
		_world.player.is_alive = false
		_vip = _find_vip()
		_vip_start = _vip.global_position if is_instance_valid(_vip) else Vector3.ZERO
		_camera = Camera3D.new()
		_camera.name = "Task47VipSpectator"
		_camera.fov = 72.0
		_camera.near = 0.06
		_world.add_child(_camera)
		_camera.current = true
		print("[TASK47 QA] VIP initial state pos=%s zones=%d" % [_vip.global_position if _vip else Vector3.ZERO, _world.escape_zones.size()])
	else:
		var sites: Array = _world.bombsites
		var center := sites[0].get_center() as Vector3 if not sites.is_empty() else _world.player.global_position
		var camera_offset := Vector3(1.8, 0.0, 7.2)
		_world.player.global_position = _floor_snap(center + camera_offset)
		_world.player.velocity = Vector3.ZERO
		_aim_player_at(center + Vector3.UP * 1.15)
		if _state == "fire":
			var fire_pos := _floor_snap(center)
			var projectile := GrenadeProjectile.new()
			_world.add_child(projectile)
			projectile.global_position = fire_pos + Vector3.UP * 0.18
			projectile.setup_grenade("molotov", _world.player, Vector3.ZERO)
			projectile.set_physics_process(false)
			projectile._detonate()
			for child in _world.get_children():
				if child is IncendiaryArea:
					_area = child
					break
			print("[TASK47 QA] Molotov created at %s" % fire_pos)
	print("[TASK47 QA] setup complete")
	_web_bool("task47Booted", true)


func _freeze_fire() -> void:
	if _area == null:
		return
	_area.set_physics_process(false)
	_area.set_process(false)
	for particles in [_area._burst, _area._ember_particles, _area._smoke_particles]:
		if is_instance_valid(particles):
			particles.speed_scale = 0.0
	_web_number("task47FirePatches", _area._patches.size())
	_web_number("task47FireRadius", _area._current_radius)
	print("[TASK47 QA] Fire frozen for capture patches=%d radius=%.3f" % [_area._patches.size(), _area._current_radius])


func _resume_fire() -> void:
	if _area == null or _resumed:
		return
	_resumed = true
	for particles in [_area._burst, _area._ember_particles, _area._smoke_particles]:
		if is_instance_valid(particles):
			particles.speed_scale = 1.0
	_area.set_physics_process(true)
	_area.set_process(true)
	_web_bool("task47FireResumed", true)


func _ack() -> void:
	if _acked:
		return
	_acked = true
	_web_bool("task47Ready", true)
	print("[TASK47 QA] READY state=%s" % _state)


func _process(_delta: float) -> void:
	if _world == null:
		return
	_frame += 1
	if _frame <= 5 or _frame % 60 == 0:
		print("[TASK47 QA] process frame=%d state=%s" % [_frame, _state])
	if _frame % 5 == 0:
		_web_number("task47Frame", _frame)
	if _state == "fire" and _freeze_frame < 0 and is_instance_valid(_area) and _area._age >= 2.65:
		_freeze_frame = _frame
		_freeze_fire()
	if _state == "fire" and _freeze_frame >= 0 and _frame >= _freeze_frame + 3:
		_ack()
	if _state == "fire" and _acked and not _resumed and OS.has_feature("web"):
		if FileAccess.file_exists("res://task47_resume_fire"):
			_resume_fire()
	elif _state == "texture" and _frame >= 5:
		_ack()
	elif _state == "vip":
		if is_instance_valid(_vip):
			if not _vip_moved and _vip.global_position.distance_to(_vip_start) >= 0.25:
				_vip_moved = true
				_web_bool("task47VipMoved", true)
			var target := _vip.global_position + Vector3.UP * 1.15
			var desired := _vip.global_position + Vector3(4.5, 2.7, 6.0)
			var query := PhysicsRayQueryParameters3D.create(target, desired)
			query.collision_mask = 1
			var hit := _world.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				desired = (hit.get("position", desired) as Vector3) + (hit.get("normal", Vector3.UP) as Vector3) * 0.35
			_camera.global_position = desired
			_camera.look_at(target, Vector3.UP)
			if _frame % 60 == 0:
				_web_number("task47VipX", _vip.global_position.x)
				_web_number("task47VipY", _vip.global_position.y)
				_web_number("task47VipZ", _vip.global_position.z)
				_web_number("task47VipPath", _vip._node_path.size())
				_web_number("task47VipNode", _vip._node_path[0] if not _vip._node_path.is_empty() else -1)
				_web_number("task47VipHealth", _vip.health)
				_web_bool("task47VipCombat", is_instance_valid(_vip.target_enemy) and _vip.target_enemy.is_alive)
				var debug_target := _world.bot_navigator.get_node_pos(_vip._node_path[0]) if not _vip._node_path.is_empty() else Vector3.ZERO
				print("[TASK47 QA] VIP route pos=%s target=%s ladder=%s floor=%s velocity=%s stuck=%.2f elapsed=%.2f retries=%d banned=%s path=%s" % [_vip.global_position, debug_target, _vip.on_ladder, _vip.is_on_floor(), _vip.velocity, _vip._stuck_timer, _vip._cur_node_elapsed, _vip._rechoice_count, str(_vip._banned_nodes.keys()), str(_vip._node_path.slice(0, 8))])
		if RoundManager.state == RoundManager.State.ROUND_OVER and not _acked:
			_web_bool("task47VipEscaped", _vip_escaped)
			_web_bool("task47VipInZone", is_instance_valid(_vip) and _world.is_in_escape_zone(_vip.global_position))
			_ack()
