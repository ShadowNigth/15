class_name HostageNPC
extends CharacterBody3D
## Counter-Strike 1.5 Hostage NPC (hostage.glb) for cs_* Hostage Rescue maps.

var is_alive: bool = true
var is_rescued: bool = false
var leader: Node3D = null
var health: float = 100.0
var spawn_pos: Vector3 = Vector3.ZERO
var spawn_yaw: float = 0.0

var _anim_player: AnimationPlayer = null
var _touched_once: bool = false
var _nav_path: Array[Vector3] = []
var _repath_timer: float = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.95
	col.shape = cap
	col.position = Vector3(0, 0.975, 0)
	add_child(col)

	var sc := GameData.get_model_scene("players/hostage")
	if sc:
		var mdl := sc.instantiate()
		add_child(mdl)
		_anim_player = _find_anim_player(mdl)
		_play_anim("idle")


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


func _play_anim(substr: String) -> void:
	if not _anim_player:
		return
	for aname in _anim_player.get_animation_list():
		if substr in aname.to_lower():
			if _anim_player.current_animation != aname:
				_anim_player.play(aname)
			return


func reset_for_round() -> void:
	is_alive = true
	is_rescued = false
	leader = null
	health = 100.0
	_touched_once = false
	_nav_path.clear()
	visible = true
	global_position = spawn_pos + Vector3(0, 0.08, 0)
	rotation = Vector3(0, spawn_yaw, 0)
	velocity = Vector3.ZERO
	_play_anim("idle")


func interact(actor: Node3D) -> void:
	if not is_alive or is_rescued or not is_instance_valid(actor):
		return
	if String(actor.get("team")) != "CT":
		return
	if leader == actor:
		leader = null
		_play_anim("idle")
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
	if is_instance_valid(attacker) and attacker.has_method("add_money"):
		attacker.call("add_money", -300)
	if health <= 0.0:
		is_alive = false
		leader = null
		AudioManager.play_radio("radio/hosdown.wav")
		visible = false


func _physics_process(delta: float) -> void:
	if not is_alive or is_rescued:
		return

	if not is_on_floor():
		velocity.y -= 24.0 * delta

	if is_instance_valid(leader) and bool(leader.get("is_alive")):
		var dist := global_position.distance_to(leader.global_position)
		if dist > 2.3:
			_repath_timer -= delta
			var move_target := leader.global_position
			if dist > 6.0 and _repath_timer <= 0.0 and is_instance_valid(RoundManager.game_world):
				_repath_timer = 0.7
				var nav = RoundManager.game_world.get("bot_navigator")
				if nav != null and nav.has_method("find_path"):
					_nav_path = nav.find_path(global_position, leader.global_position)
			if not _nav_path.is_empty():
				if global_position.distance_to(_nav_path[0]) < 1.4:
					_nav_path.remove_at(0)
				if not _nav_path.is_empty():
					move_target = _nav_path[0]

			var dir := (move_target - global_position)
			dir.y = 0.0
			if dir.length_squared() > 0.01:
				dir = dir.normalized()
				var spd := 6.5 if dist > 5.0 else 4.6
				velocity.x = dir.x * spd
				velocity.z = dir.z * spd
				rotation.y = atan2(-dir.x, -dir.z)
				_play_anim("run" if spd > 5.5 else "walk")
		else:
			velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)
			_play_anim("idle")
	else:
		leader = null
		velocity.x = move_toward(velocity.x, 0.0, 18.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 18.0 * delta)

	move_and_slide()

	# Check if inside rescue zone!
	if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_rescue_zone"):
		if bool(RoundManager.game_world.call("is_in_rescue_zone", global_position)):
			is_rescued = true
			visible = false
			RoundManager.notify_hostage_rescued(leader)
			leader = null
