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


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)

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

	var grounded := is_on_floor()
	if not grounded:
		velocity.y -= 24.0 * delta

	if is_instance_valid(leader) and bool(leader.get("is_alive")):
		var dist := global_position.distance_to(leader.global_position)
		if dist > 2.25:
			_repath_timer -= delta
			var move_target := leader.global_position
			if dist > 5.5 and _repath_timer <= 0.0 and is_instance_valid(RoundManager.game_world):
				_repath_timer = 0.65
				var nav = RoundManager.game_world.get("bot_navigator")
				if nav != null and nav.has_method("find_path"):
					_nav_path.assign(nav.find_path(global_position, leader.global_position))
			if not _nav_path.is_empty():
				if global_position.distance_to(_nav_path[0]) < 1.45:
					_nav_path.remove_at(0)
				if not _nav_path.is_empty():
					move_target = _nav_path[0]

			var dir := (move_target - global_position)
			dir.y = 0.0
			if dir.length_squared() > 0.01:
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
		leader = null
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

	# Check if inside rescue zone!
	if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_rescue_zone"):
		if bool(RoundManager.game_world.call("is_in_rescue_zone", global_position)):
			is_rescued = true
			visible = false
			if _col_shape != null:
				_col_shape.set_deferred("disabled", true)
			RoundManager.notify_hostage_rescued(leader)
			leader = null
