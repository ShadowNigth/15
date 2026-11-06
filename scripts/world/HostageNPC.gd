class_name HostageNPC
extends CharacterBody3D
## Counter-Strike 1.5 Hostage NPC (hostage.glb) for cs_* Hostage Rescue maps:
##   - Smooth animation crossfades (idle1, crouch_idle, walk, walk_scared, run, gutshot)
##   - Cower/startle reactions to nearby gunfire & explosions
##   - GoldSrc 18u (0.54m) stair/curb step-up & automatic door interaction while following CTs

const STEP_HEIGHT: float = 0.54

var is_alive: bool = true
var is_rescued: bool = false
var leader: Node3D = null
var health: float = 100.0
var spawn_pos: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0

var _col_shape: CollisionShape3D = null
var _anim_player: AnimationPlayer = null
var _touched_once: bool = false
var _nav_path: Array[Vector3] = []
var _repath_timer: float = 0.0
var _scared_timer: float = 0.0
var _stuck_timer: float = 0.0
var _blocked_timer: float = 0.0
var _avoid_timer: float = 0.0
var _avoid_dir: Vector3 = Vector3.ZERO
var _last_pos: Vector3 = Vector3.ZERO
var _avoid_side: float = 1.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	_last_pos = global_position
	_avoid_side = 1.0 if get_instance_id() % 2 == 0 else -1.0

	_col_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.36
	cap.height = 1.90
	_col_shape.shape = cap
	_col_shape.position = Vector3(0.0, 0.95, 0.0)
	add_child(_col_shape)

	var sc := GameData.get_model_scene("players/hostage")
	if sc:
		var mdl := sc.instantiate()
		_configure_hostage_meshes(mdl)
		add_child(mdl)
		_anim_player = _find_anim_player(mdl)
		GameData.ensure_looping_animations(_anim_player)
		if _anim_player != null:
			for aname in _anim_player.get_animation_list():
				if "gutshot" in aname.to_lower():
					var ga := _anim_player.get_animation(aname)
					if ga != null:
						ga.loop_mode = Animation.LOOP_NONE
		_play_anim("idle1", 0.0)


func _configure_hostage_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "char")
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_configure_hostage_meshes(c)


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


func _play_anim(substr: String, blend_sec: float = 0.18) -> void:
	if not _anim_player:
		return
	var kw := substr.to_lower()
	for aname in _anim_player.get_animation_list():
		var low := aname.to_lower()
		if low == kw:
			if _anim_player.current_animation != aname:
				_anim_player.play(aname, blend_sec)
			return
	for aname in _anim_player.get_animation_list():
		var low := aname.to_lower()
		if "crouch" in low and not kw.begins_with("crouch"):
			continue
		if low.begins_with(kw) or kw in low:
			if _anim_player.current_animation != aname:
				_anim_player.play(aname, blend_sec)
			return


func notify_nearby_danger(danger_pos: Vector3, max_r: float = 12.0) -> void:
	if not is_alive or is_rescued:
		return
	if global_position.distance_to(danger_pos) <= max_r:
		_scared_timer = maxf(_scared_timer, 3.2)


func reset_for_round() -> void:
	is_alive = true
	is_rescued = false
	leader = null
	health = 100.0
	_touched_once = false
	_scared_timer = 0.0
	_stuck_timer = 0.0
	_blocked_timer = 0.0
	_avoid_timer = 0.0
	_avoid_dir = Vector3.ZERO
	_repath_timer = 0.0
	_nav_path.clear()
	visible = true
	if _col_shape != null:
		_col_shape.disabled = false
	var floor_p := spawn_pos + Vector3(0.0, 0.05, 0.0)
	if is_inside_tree() and get_world_3d():
		var q := PhysicsRayQueryParameters3D.create(spawn_pos + Vector3(0, 0.5, 0), spawn_pos - Vector3(0, 2.2, 0))
		q.collision_mask = 1
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			floor_p = (hit["position"] as Vector3) + Vector3(0.0, 0.03, 0.0)
	global_position = floor_p
	_last_pos = global_position
	rotation = Vector3(0, spawn_yaw, 0)
	velocity = Vector3.ZERO
	_play_anim("idle1", 0.0)


func interact(actor: Node3D) -> void:
	if not is_alive or is_rescued or not is_instance_valid(actor):
		return
	if String(actor.get("team")) != "CT":
		return
	if leader == actor:
		leader = null
		_play_anim("idle1")
		return

	leader = actor
	_nav_path.clear()
	_repath_timer = 0.0
	_stuck_timer = 0.0
	_blocked_timer = 0.0
	_avoid_timer = 0.0
	_last_pos = global_position
	AudioManager.play_3d("hostage/hos%d.wav" % randi_range(1, 5), global_position, 0.0, 26.0)
	if not _touched_once and actor.has_method("add_money"):
		_touched_once = true
		actor.call("add_money", int(GameData.economy.get("hostage_touch_reward", 150)))


func take_damage(attacker: Node3D, dmg: float) -> void:
	if not is_alive or is_rescued:
		return
	health -= dmg
	_scared_timer = 4.0
	var pain_ids := [2, 4, 5, 6, 7]
	var pid: int = pain_ids[randi() % pain_ids.size()]
	AudioManager.play_3d("player/pl_pain%d.wav" % pid, global_position, -1.5, 22.0, 1.06)
	if is_instance_valid(attacker) and attacker.has_method("add_money"):
		attacker.call("add_money", -300)
	if health <= 0.0:
		is_alive = false
		leader = null
		velocity = Vector3.ZERO
		if _col_shape != null:
			_col_shape.set_deferred("disabled", true)
		AudioManager.play_radio("radio/hosdown.wav")
		_play_anim("gutshot", 0.08)
		if is_instance_valid(RoundManager.game_world):
			ImpactEffects.spawn_death_blood_pool(RoundManager.game_world, global_position, Vector3.UP)


func needs_navigation_help() -> bool:
	return _blocked_timer > 0.0 and is_alive and not is_rescued


func _solid_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var excluded: Array[RID] = []
	for _attempt in range(3):
		var query := PhysicsRayQueryParameters3D.create(a, b)
		query.collision_mask = 1
		query.exclude = excluded
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var collider = hit.get("collider")
		if collider is CollisionObject3D and (collider as Node).has_meta("door"):
			excluded.append((collider as CollisionObject3D).get_rid())
			continue
		return true
	return false


func _has_clear_move_line(to_pos: Vector3) -> bool:
	if get_world_3d() == null:
		return true
	# Direct following is horizontal plus a small GoldSrc step. Never confuse
	# a leader on another deck with an unobstructed walk to the same X/Z.
	if absf(to_pos.y - global_position.y) > STEP_HEIGHT + 0.14:
		return false
	var delta := to_pos - global_position
	delta.y = 0.0
	if delta.length_squared() < 0.04:
		return true
	var side := Vector3(-delta.z, 0.0, delta.x).normalized() * 0.34
	var space := get_world_3d().direct_space_state
	for height in [0.38, 1.02]:
		for lateral in [Vector3.ZERO, side, -side]:
			var offset: Vector3 = lateral + Vector3(0.0, float(height), 0.0)
			if _solid_between(space, global_position + offset, to_pos + offset):
				return false
	return true


func _pick_unstick_direction(forward: Vector3) -> Vector3:
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length_squared() < 0.01:
		return Vector3.ZERO
	flat = flat.normalized()
	var right := Vector3(-flat.z, 0.0, flat.x) * _avoid_side
	var candidates: Array[Vector3] = [right, -right, (right + flat).normalized(), (-right + flat).normalized(), -flat]
	var space := get_world_3d().direct_space_state
	for direction in candidates:
		var probe := global_position + direction * 1.25
		if not _has_clear_move_line(probe):
			continue
		var floor_query := PhysicsRayQueryParameters3D.create(probe + Vector3(0.0, 0.55, 0.0), probe - Vector3(0.0, 1.35, 0.0))
		floor_query.collision_mask = 1
		if not space.intersect_ray(floor_query).is_empty():
			_avoid_side = -_avoid_side
			return direction
	return Vector3.ZERO


func _try_step_up(horiz_motion: Vector3, preserve_hvel: Vector3) -> void:
	var step_dir := horiz_motion.normalized() * maxf(horiz_motion.length(), 0.08)
	for sh in [0.22, 0.38, STEP_HEIGHT]:
		var up_vec := Vector3(0.0, float(sh), 0.0)
		if test_move(global_transform, up_vec):
			continue
		var raised_xf := global_transform.translated(up_vec)
		if test_move(raised_xf, step_dir):
			continue
		global_position += up_vec + step_dir
		move_and_collide(Vector3(0.0, -float(sh) - 0.06, 0.0))
		velocity.x = preserve_hvel.x
		velocity.z = preserve_hvel.z
		return


func _physics_process(delta: float) -> void:
	if not is_alive or is_rescued:
		return

	if _scared_timer > 0.0:
		_scared_timer = maxf(0.0, _scared_timer - delta)
	if _blocked_timer > 0.0:
		_blocked_timer = maxf(0.0, _blocked_timer - delta)
	if _avoid_timer > 0.0:
		_avoid_timer = maxf(0.0, _avoid_timer - delta)

	var grounded := is_on_floor()
	if not grounded:
		velocity.y -= 24.0 * delta

	if is_instance_valid(leader) and bool(leader.get("is_alive")):
		var dist := global_position.distance_to(leader.global_position)
		var finishing_rescue := false
		if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_rescue_zone"):
			var leader_inside := bool(RoundManager.game_world.call("is_in_rescue_zone", leader.global_position + Vector3(0.0, 0.95, 0.0)))
			var self_inside := bool(RoundManager.game_world.call("is_in_rescue_zone", global_position + Vector3(0.0, 0.95, 0.0))) or bool(RoundManager.game_world.call("is_in_rescue_zone", global_position))
			finishing_rescue = leader_inside and not self_inside
		# The normal 2.15 m follow gap must not leave the NPC just outside the
		# trigger after its rescuer has entered. Close in until this body crosses.
		var follow_stop := 0.35 if finishing_rescue else 2.15
		if dist > follow_stop:
			_repath_timer -= delta
			var direct_clear := dist < 7.0 and _has_clear_move_line(leader.global_position)
			if (dist > 5.2 or not direct_clear) and _repath_timer <= 0.0 and is_instance_valid(RoundManager.game_world):
				_repath_timer = 0.55
				var nav = RoundManager.game_world.get("bot_navigator")
				if nav != null and nav.has_method("find_path"):
					_nav_path.assign(nav.find_path(global_position, leader.global_position))
			if direct_clear and dist <= 5.2:
				_nav_path.clear()

			while not _nav_path.is_empty():
				var node := _nav_path[0]
				var flat := Vector2(node.x - global_position.x, node.z - global_position.z).length()
				if flat < 0.88 and absf(node.y - global_position.y) < 1.30:
					_nav_path.remove_at(0)
				else:
					break

			var move_target := leader.global_position
			if _avoid_timer > 0.0:
				move_target = global_position + _avoid_dir * 1.50
			elif not _nav_path.is_empty():
				move_target = _nav_path[0]
			elif not direct_clear:
				# No safe graph route and a wall direct to the leader. Ask the CT
				# to regroup while trying a locally validated lateral detour.
				_blocked_timer = maxf(_blocked_timer, 0.75)
				if _avoid_timer <= 0.0:
					_avoid_dir = _pick_unstick_direction((leader.global_position - global_position).normalized())
					_avoid_timer = 0.42 if _avoid_dir.length_squared() > 0.01 else 0.0
				move_target = global_position + _avoid_dir * 1.50

			var dir := move_target - global_position
			dir.y = 0.0
			if dir.length_squared() > 0.01 and (_avoid_timer > 0.0 or direct_clear or not _nav_path.is_empty()):
				dir = dir.normalized()
				var spd := 6.6 if dist > 4.8 else 4.7
				velocity.x = dir.x * spd
				velocity.z = dir.z * spd
				var target_yaw := atan2(-dir.x, -dir.z)
				rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, 10.5 * delta))
				if spd > 5.5:
					_play_anim("run")
				else:
					_play_anim("walk_scared" if _scared_timer > 0.0 else "walk")
			else:
				velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
				velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
				_play_anim("crouch_idle" if _scared_timer > 0.0 else "idle1")
		else:
			_nav_path.clear()
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
			_play_anim("crouch_idle" if _scared_timer > 0.0 else "idle1")
	else:
		leader = null
		_nav_path.clear()
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
		_play_anim("crouch_idle" if _scared_timer > 0.0 else "idle1")

	var pre_hvel := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()

	if grounded and is_on_wall() and pre_hvel.length_squared() > 0.04:
		_try_step_up(pre_hvel * delta, pre_hvel)

	for si in range(get_slide_collision_count()):
		var kc := get_slide_collision(si)
		var col := kc.get_collider()
		if col is Node and col.has_meta("door"):
			var door = col.get_meta("door")
			if is_instance_valid(door) and door.has_method("interact"):
				door.call("interact", self)

	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
	if pre_hvel.length() > 0.20 and moved < pre_hvel.length() * delta * 0.24:
		_stuck_timer += delta
	else:
		_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.5)
	_last_pos = global_position
	if _stuck_timer > 0.34:
		_blocked_timer = 1.50
		_repath_timer = 0.0
		_nav_path.clear()
		_avoid_dir = _pick_unstick_direction(pre_hvel.normalized())
		_avoid_timer = 0.48 if _avoid_dir.length_squared() > 0.01 else 0.0
		_stuck_timer = 0.0

	# A rescue brush intersects the hostage capsule, not merely its feet. Some
	# authored YaPB rescue nodes sit slightly below the BSP trigger's lower Y.
	if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_rescue_zone"):
		var feet_inside := bool(RoundManager.game_world.call("is_in_rescue_zone", global_position))
		var body_inside := bool(RoundManager.game_world.call("is_in_rescue_zone", global_position + Vector3(0.0, 0.95, 0.0)))
		if feet_inside or body_inside:
			is_rescued = true
			visible = false
			if _col_shape != null:
				_col_shape.set_deferred("disabled", true)
			RoundManager.notify_hostage_rescued(leader)
			leader = null
