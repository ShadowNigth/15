class_name BSPDoor
extends Node3D
## GoldSrc func_door / func_door_rotating brush entity with automatic proximity opening,
## HLSDK double-door linking, targetname / func_button / trigger_multiple support, and doorway anti-crush hold.

var is_rotating: bool = false
var move_dir: Vector3 = Vector3(1, 0, 0)
var move_distance: float = 1.92
var open_angle_rad: float = deg_to_rad(90.0)
var rot_axis: Vector3 = Vector3.UP
var speed_mps: float = 3.2
var wait_sec: float = 3.5
var target_name: String = ""
var auto_open: bool = true
var toggle_only: bool = false

var is_open: bool = false
var _closed_pos: Vector3
var _closed_rot: Vector3
var _open_sign: float = 1.0
var _progress: float = 0.0
var _target_progress: float = 0.0
var _close_timer: float = 0.0
var closed_aabb: AABB = AABB()
var linked_doors: Array[BSPDoor] = []


func setup_door(
	rotating: bool,
	angles_gs: Array,
	speed_gs: float,
	lip_gs: float,
	aabb_world: AABB,
	distance_deg: float = 90.0,
	wait_gs: float = 4.0,
	tname: String = "",
	spawnflags: int = 0
) -> void:
	is_rotating = rotating
	_closed_pos = position
	_closed_rot = rotation
	closed_aabb = aabb_world
	target_name = tname
	speed_mps = clampf(speed_gs * GameData.SCALE, 1.35, 8.5)
	wait_sec = 3.5 if wait_gs <= 0.0 else clampf(wait_gs, 1.8, 12.0)
	toggle_only = (wait_gs < 0.0) or ((spawnflags & 32) != 0)
	# Doors without targetname open automatically on touch/proximity (and GlassDoor* automatic doors too!)
	auto_open = (tname.is_empty() or tname.to_lower().begins_with("glassdoor") or tname.to_lower().begins_with("autodoor"))

	if is_rotating:
		var deg_abs: float = absf(distance_deg) if absf(distance_deg) > 1.0 else 90.0
		var sgn: float = -1.0 if ((spawnflags & 2) != 0 or distance_deg < 0.0) else 1.0
		open_angle_rad = deg_to_rad(deg_abs) * sgn
		if (spawnflags & 64) != 0:
			rot_axis = Vector3(0, 0, 1)
		elif (spawnflags & 128) != 0:
			rot_axis = Vector3(1, 0, 0)
		else:
			rot_axis = Vector3.UP
	else:
		var pitch_deg: float = float(angles_gs[0]) if angles_gs.size() > 0 else 0.0
		var yaw_deg: float = float(angles_gs[1]) if angles_gs.size() > 1 else 0.0
		if pitch_deg <= -85.0:
			move_dir = Vector3.UP
		elif pitch_deg >= 85.0:
			move_dir = Vector3.DOWN
		else:
			# GoldSrc yaw -> Godot direction: gs_vec_to_gd(cos y, sin y, 0) = (-sin y, 0, -cos y)
			var yaw_rad: float = deg_to_rad(yaw_deg)
			move_dir = Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad)).normalized()
		var lip_m: float = lip_gs * GameData.SCALE
		if lip_gs == 0.0:
			lip_m = 0.08  # Leave clean 8cm door edge visible inside frame when lip=0
		var sz: Vector3 = aabb_world.size
		var span: float = absf(move_dir.x) * sz.x + absf(move_dir.y) * sz.y + absf(move_dir.z) * sz.z
		if span < 0.15:
			span = maxf(sz.x, sz.z)
		move_distance = clampf(span - lip_m, 0.35, 12.0)


func interact(actor: Node3D = null, propagate_links: bool = true) -> void:
	if _target_progress < 0.5:
		_open_for_actor(actor)
		if propagate_links:
			for partner in linked_doors:
				if is_instance_valid(partner) and partner != self:
					partner._open_for_actor(actor)
	elif toggle_only:
		_target_progress = 0.0
		is_open = false
		AudioManager.play_3d("doors/doormove1.wav", closed_aabb.get_center(), -5.0, 22.0, 0.94, 12.0)
		if propagate_links:
			for partner in linked_doors:
				if is_instance_valid(partner) and partner != self:
					partner._target_progress = 0.0
					partner.is_open = false


func force_open(actor: Node3D = null) -> void:
	if _target_progress < 0.5:
		interact(actor, true)
	else:
		_close_timer = maxf(_close_timer, wait_sec)
		for partner in linked_doors:
			if is_instance_valid(partner) and partner != self:
				partner._close_timer = maxf(partner._close_timer, partner.wait_sec)


func _open_for_actor(actor: Node3D) -> void:
	if is_rotating and actor != null and is_instance_valid(actor) and rot_axis == Vector3.UP and _progress < 0.05:
		# Swing rotating door AWAY from approaching actor so it never blocks them!
		var leaf_vec: Vector3 = closed_aabb.get_center() - global_position
		leaf_vec.y = 0.0
		if leaf_vec.length_squared() > 0.01:
			var to_actor: Vector3 = actor.global_position - global_position
			to_actor.y = 0.0
			var test_pos: Vector3 = leaf_vec.rotated(Vector3.UP, open_angle_rad * 0.5)
			var test_neg: Vector3 = leaf_vec.rotated(Vector3.UP, -open_angle_rad * 0.5)
			if test_neg.distance_squared_to(to_actor) > test_pos.distance_squared_to(to_actor) + 0.05:
				_open_sign = -1.0
			else:
				_open_sign = 1.0
	_target_progress = 1.0
	is_open = true
	_close_timer = wait_sec
	AudioManager.play_3d("doors/doormove1.wav", closed_aabb.get_center(), -4.5, 24.0, randf_range(0.96, 1.05), 14.0)


func is_point_near_door(pt: Vector3, horiz_pad: float = 1.85, vert_pad_lo: float = 0.45, vert_pad_hi: float = 0.65) -> bool:
	var lo: Vector3 = closed_aabb.position
	var hi: Vector3 = closed_aabb.end
	return (
		pt.x >= lo.x - horiz_pad and pt.x <= hi.x + horiz_pad
		and pt.z >= lo.z - horiz_pad and pt.z <= hi.z + horiz_pad
		and pt.y + 1.65 >= lo.y - vert_pad_lo and pt.y <= hi.y + vert_pad_hi
	)


func _any_actor_near(horiz_pad: float) -> CSActor:
	for a in RoundManager.actors:
		if is_instance_valid(a) and a.is_alive:
			if is_point_near_door(a.global_position, horiz_pad):
				return a
	return null


func _physics_process(delta: float) -> void:
	# Automatic proximity sensor for players & bots approaching untargeted / automatic doors
	if auto_open and _target_progress < 0.5:
		var near_actor: CSActor = _any_actor_near(1.85)
		if near_actor != null:
			interact(near_actor, true)

	if not is_equal_approx(_progress, _target_progress):
		var was_moving_to_end: bool = true
		var travel: float = 1.35 if is_rotating else maxf(0.45, move_distance)
		var rate: float = speed_mps / travel
		_progress = move_toward(_progress, _target_progress, rate * delta)
		if is_rotating:
			rotation = _closed_rot + rot_axis * (open_angle_rad * _open_sign * _progress)
		else:
			position = _closed_pos + move_dir * (move_distance * _progress)
		if was_moving_to_end and is_equal_approx(_progress, _target_progress):
			AudioManager.play_3d("doors/doorstop1.wav", closed_aabb.get_center(), -5.5, 20.0, randf_range(0.95, 1.04))

	if is_open and not toggle_only and _progress >= 0.99:
		# Keep doorway held open while any player or bot stands inside/near the frame
		if _any_actor_near(1.55) != null:
			_close_timer = maxf(_close_timer, 1.4)
		else:
			_close_timer -= delta
			if _close_timer <= 0.0:
				_target_progress = 0.0
				is_open = false
				AudioManager.play_3d("doors/doormove1.wav", closed_aabb.get_center(), -5.5, 22.0, 0.92)


func reset_for_round() -> void:
	_progress = 0.0
	_target_progress = 0.0
	is_open = false
	_open_sign = 1.0
	_close_timer = 0.0
	position = _closed_pos
	rotation = _closed_rot
