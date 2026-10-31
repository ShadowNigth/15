class_name BSPBreakable
extends Node3D
## Destructible GoldSrc func_breakable entity (crates, glass windows, air vents).

var max_health: float = 40.0
var health: float = 40.0
var material_type: int = 0  # 0=Glass, 1=Wood, 2=Metal
var broken: bool = false
var _col_shapes: Array[CollisionShape3D] = []


func setup_breakable(hp: float, mat_id: int) -> void:
	max_health = maxf(10.0, hp)
	health = max_health
	material_type = mat_id
	_collect_shapes(self)


func _collect_shapes(n: Node) -> void:
	if n is CollisionShape3D:
		_col_shapes.append(n)
	for c in n.get_children():
		_collect_shapes(c)


func apply_damage(amount: float, hit_pos: Vector3) -> void:
	if broken:
		return
	health -= amount
	if health <= 0.0:
		_shatter(hit_pos)
	else:
		AudioManager.play_3d("weapons/ric_conc-1.wav", hit_pos, -6.0, 20.0)


func _shatter(hit_pos: Vector3) -> void:
	broken = true
	visible = false
	for cs in _col_shapes:
		if is_instance_valid(cs):
			cs.set_deferred("disabled", true)
	var wav := "weapons/ric_metal-1.wav" if material_type == 2 else "weapons/ric1.wav"
	AudioManager.play_3d(wav, hit_pos, -2.0, 32.0, 0.85, 22.0)


func reset_for_round() -> void:
	broken = false
	health = max_health
	visible = true
	for cs in _col_shapes:
		if is_instance_valid(cs):
			cs.disabled = false
