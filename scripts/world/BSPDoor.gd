class_name BSPDoor
extends Node3D
## Interactive GoldSrc func_door and func_door_rotating entity.

var is_rotating: bool = false
var move_offset: Vector3 = Vector3.ZERO
var rot_target_rad: Vector3 = Vector3.ZERO
var speed_mps: float = 3.2
var wait_time: float = 3.5

var _base_pos: Vector3 = Vector3.ZERO
var _base_rot: Vector3 = Vector3.ZERO
var _open_ratio: float = 0.0
var _opening: bool = false
var _hold_timer: float = 0.0


func setup_sliding(offset: Vector3, spd_gs: float) -> void:
	is_rotating = false
	move_offset = offset
	speed_mps = maxf(0.8, spd_gs * GameData.SCALE)
	_base_pos = position
	_base_rot = rotation


func setup_rotating(rot_rad: Vector3, spd_deg: float) -> void:
	is_rotating = true
	rot_target_rad = rot_rad
	speed_mps = maxf(0.8, deg_to_rad(spd_deg))
	_base_pos = position
	_base_rot = rotation


func interact(_actor: Node3D = null) -> void:
	if not _opening and _open_ratio < 0.05:
		AudioManager.play_3d("plats/bigmove1.wav", global_position, -6.0, 22.0)
	_opening = true
	_hold_timer = wait_time


func reset_for_round() -> void:
	_opening = false
	_open_ratio = 0.0
	_hold_timer = 0.0
	position = _base_pos
	rotation = _base_rot


func _physics_process(delta: float) -> void:
	if _opening:
		var dur := 1.0
		if not is_rotating and move_offset.length() > 0.01:
			dur = move_offset.length() / speed_mps
		_open_ratio = minf(1.0, _open_ratio + delta / maxf(0.2, dur))
		if _open_ratio >= 1.0:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				_opening = false
	elif _open_ratio > 0.0:
		var dur2 := 1.0
		if not is_rotating and move_offset.length() > 0.01:
			dur2 = move_offset.length() / speed_mps
		_open_ratio = maxf(0.0, _open_ratio - delta / maxf(0.2, dur2))

	if is_rotating:
		rotation = _base_rot + rot_target_rad * _open_ratio
	else:
		position = _base_pos + move_offset * _open_ratio
