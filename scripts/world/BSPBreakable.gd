class_name BSPBreakable
extends Node3D
## Destructible GoldSrc func_breakable entity (glass windows, wooden crates, air vents, electronics)
## with volumetric 3D shard/splinter/shrapnel shatter effects & explosion blast support.

var max_health: float = 40.0
var health: float = 40.0
var material_type: int = 0  # 0=Glass, 1=Wood, 2=Metal, 4=Concrete, 5=Tile, 6=Computer, 8=Rock
var broken: bool = false
var world_aabb: AABB = AABB()
var _col_shapes: Array[CollisionShape3D] = []


func setup_breakable(hp: float, mat_id: int) -> void:
	max_health = maxf(10.0, hp)
	health = max_health
	material_type = mat_id
	_collect_shapes(self)
	_compute_world_aabb(self)


func _collect_shapes(n: Node) -> void:
	if n is CollisionShape3D:
		_col_shapes.append(n as CollisionShape3D)
	for c in n.get_children():
		_collect_shapes(c)


func _compute_world_aabb(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var la: AABB = mi.get_aabb()
			var wa := AABB(mi.global_position + la.position, la.size)
			if world_aabb.size.length_squared() < 0.0001:
				world_aabb = wa
			else:
				world_aabb = world_aabb.merge(wa)
	for c in n.get_children():
		_compute_world_aabb(c)


func apply_damage(amount: float, hit_pos: Vector3) -> void:
	if broken or material_type == 7:
		return
	health -= amount
	if health <= 0.0:
		_shatter(hit_pos)
	else:
		if material_type == 0:
			AudioManager.play_3d("player/pl_tile%d.wav" % randi_range(1, 4), hit_pos, -4.5, 20.0, randf_range(1.35, 1.55))
		elif material_type in [2, 6]:
			AudioManager.play_3d("player/pl_duct%d.wav" % randi_range(1, 4), hit_pos, -4.5, 22.0, randf_range(1.05, 1.22))
		else:
			AudioManager.play_3d("weapons/ric_conc-%d.wav" % randi_range(1, 2), hit_pos, -5.5, 20.0, randf_range(0.88, 1.05))


func apply_explosion_impulse(blast_pos: Vector3, blast_radius: float, peak_dmg: float = 95.0) -> void:
	if broken or material_type == 7:
		return
	var center: Vector3 = world_aabb.get_center() if world_aabb.size.length_squared() > 0.001 else global_position
	var d: float = center.distance_to(blast_pos)
	if d > blast_radius:
		return
	var falloff: float = clampf(1.0 - d / maxf(0.5, blast_radius), 0.0, 1.0)
	var dmg: float = peak_dmg * falloff
	if dmg > 4.0:
		apply_damage(dmg, center)


func _shatter(hit_pos: Vector3) -> void:
	broken = true
	visible = false
	for cs in _col_shapes:
		if is_instance_valid(cs):
			cs.set_deferred("disabled", true)

	if is_instance_valid(RoundManager.game_world):
		ImpactEffects.spawn_breakable_shatter(RoundManager.game_world, world_aabb, hit_pos, material_type)

	if material_type == 0:
		AudioManager.play_3d("player/pl_tile%d.wav" % randi_range(1, 4), hit_pos, 0.5, 34.0, 1.48, 24.0)
		AudioManager.play_3d("weapons/ric%d.wav" % randi_range(4, 5), hit_pos, -3.5, 30.0, 1.62)
	elif material_type in [2, 6]:
		AudioManager.play_3d("player/pl_duct%d.wav" % randi_range(1, 4), hit_pos, 1.0, 34.0, 0.86, 24.0)
		AudioManager.play_3d("weapons/ric_metal-%d.wav" % randi_range(1, 2), hit_pos, -2.0, 32.0, 0.92)
	else:
		AudioManager.play_3d("weapons/grenade_hit%d.wav" % randi_range(1, 3), hit_pos, 0.5, 32.0, 0.72, 22.0)
		AudioManager.play_3d("weapons/ric_conc-%d.wav" % randi_range(1, 2), hit_pos, -2.5, 28.0, 0.82)


func reset_for_round() -> void:
	broken = false
	health = max_health
	visible = true
	for cs in _col_shapes:
		if is_instance_valid(cs):
			cs.disabled = false
