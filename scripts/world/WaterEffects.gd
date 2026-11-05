class_name WaterEffects
extends Node3D
## BSP water volumes, animated impact rings, droplets and original CS water audio.

var zones: Array[AABB] = []
var _ripples: Array[Dictionary] = []
var _ring_mesh: ArrayMesh = null
var _drop_mesh: SphereMesh = null


func _ready() -> void:
	_build_assets()


func setup(water_zones: Array[AABB]) -> void:
	zones.assign(water_zones)
	_build_assets()


func _build_assets() -> void:
	if _ring_mesh == null:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_normal(Vector3.UP)
		for i in range(64):
			var a0 := TAU * float(i) / 64.0
			var a1 := TAU * float(i + 1) / 64.0
			var inner0 := Vector3(cos(a0) * 0.82, 0.0, sin(a0) * 0.82)
			var outer0 := Vector3(cos(a0), 0.0, sin(a0))
			var inner1 := Vector3(cos(a1) * 0.82, 0.0, sin(a1) * 0.82)
			var outer1 := Vector3(cos(a1), 0.0, sin(a1))
			surface.add_vertex(inner0)
			surface.add_vertex(outer0)
			surface.add_vertex(outer1)
			surface.add_vertex(inner0)
			surface.add_vertex(outer1)
			surface.add_vertex(inner1)
		_ring_mesh = surface.commit()
	if _drop_mesh == null:
		_drop_mesh = SphereMesh.new()
		_drop_mesh.radius = 0.5
		_drop_mesh.height = 1.0
		_drop_mesh.radial_segments = 8
		_drop_mesh.rings = 4
		var drop_material := StandardMaterial3D.new()
		drop_material.albedo_color = Color(0.62, 0.82, 0.91, 0.76)
		drop_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		drop_material.roughness = 0.24
		drop_material.metallic = 0.04
		drop_material.render_priority = 9
		_drop_mesh.material = drop_material


static func _inside_xz(zone: AABB, point: Vector3) -> bool:
	return point.x >= zone.position.x and point.x <= zone.end.x \
		and point.z >= zone.position.z and point.z <= zone.end.z


func get_water_info(feet_pos: Vector3, actor_height: float = 1.88) -> Dictionary:
	var best_surface := -INF
	for zone in zones:
		if not _inside_xz(zone, feet_pos):
			continue
		var surface_y := zone.end.y
		# A body must actually intersect the surface; bridges and rooms far
		# underneath a river must not accidentally inherit water movement.
		if feet_pos.y <= surface_y + 0.12 and feet_pos.y + actor_height >= surface_y - 0.04:
			best_surface = maxf(best_surface, surface_y)
	if is_inf(best_surface):
		return {"in_water": false, "surface_y": feet_pos.y, "depth": 0.0}
	return {
		"in_water": true,
		"surface_y": best_surface,
		"depth": maxf(0.0, best_surface - feet_pos.y),
	}


func get_water_ray_hit(from_pos: Vector3, to_pos: Vector3) -> Dictionary:
	var motion := to_pos - from_pos
	if motion.length_squared() < 0.0000001 or absf(motion.y) < 0.000001:
		return {}
	var best_t := 2.0
	var best_point := Vector3.ZERO
	for zone in zones:
		var surface_y := zone.end.y
		var t := (surface_y - from_pos.y) / motion.y
		if t <= 0.0001 or t > 1.0 or t >= best_t:
			continue
		var point := from_pos + motion * t
		if _inside_xz(zone, point):
			best_t = t
			best_point = point
	if best_t > 1.0:
		return {}
	return {"position": best_point, "normal": Vector3.UP, "distance": best_t}


func footstep_at(feet_pos: Vector3, team: String = "", quiet: bool = false) -> bool:
	var info := get_water_info(feet_pos)
	if not bool(info.get("in_water", false)):
		return false
	var point := Vector3(feet_pos.x, float(info["surface_y"]) + 0.025, feet_pos.z)
	_spawn_effect(point, 0.52, 7)
	AudioManager.play_3d(
		"player/pl_wade%d.wav" % randi_range(1, 4), point,
		-11.0 if quiet else -6.5, 24.0, randf_range(0.94, 1.05),
		10.0 if quiet else 16.0, team
	)
	return true


func splash_at(feet_pos: Vector3, strength: float = 1.0, team: String = "") -> bool:
	var info := get_water_info(feet_pos)
	if not bool(info.get("in_water", false)):
		return false
	var point := Vector3(feet_pos.x, float(info["surface_y"]) + 0.025, feet_pos.z)
	_spawn_effect(point, clampf(strength, 0.45, 1.8), 18)
	AudioManager.play_3d(
		"player/pl_slosh%d.wav" % randi_range(1, 4), point,
		-8.0, 30.0, randf_range(0.93, 1.04), 14.0, team
	)
	return true


func spawn_ray_impact(from_pos: Vector3, to_pos: Vector3, strength: float = 1.0) -> bool:
	var hit := get_water_ray_hit(from_pos, to_pos)
	if hit.is_empty():
		return false
	var point := (hit["position"] as Vector3) + Vector3.UP * 0.025
	_spawn_effect(point, clampf(strength, 0.55, 1.7), 20)
	AudioManager.play_3d(
		"player/pl_slosh%d.wav" % randi_range(1, 4), point,
		-9.0, 30.0, randf_range(0.95, 1.08)
	)
	return true


func _spawn_effect(point: Vector3, strength: float, droplet_count: int) -> void:
	_build_assets()
	if _ripples.size() >= 48:
		var oldest: Dictionary = _ripples.pop_front()
		var old_node := oldest.get("node") as MeshInstance3D
		if is_instance_valid(old_node):
			old_node.queue_free()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = 8
	material.albedo_color = Color(0.62, 0.84, 0.94, 0.52)
	var ring := MeshInstance3D.new()
	ring.name = "WaterImpactRing"
	ring.mesh = _ring_mesh
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.global_position = point
	ring.scale = Vector3(0.12, 1.0, 0.12)
	_ripples.append({
		"node": ring,
		"material": material,
		"age": 0.0,
		"life": 0.82 + strength * 0.24,
		"radius": 0.72 + strength * 0.82,
	})

	var drops := CPUParticles3D.new()
	drops.name = "WaterSplashDroplets"
	drops.amount = droplet_count
	drops.lifetime = 0.42 + strength * 0.12
	drops.one_shot = true
	drops.explosiveness = 1.0
	drops.emitting = false
	drops.mesh = _drop_mesh
	drops.direction = Vector3.UP
	drops.spread = 38.0
	drops.initial_velocity_min = 0.65 + strength * 0.35
	drops.initial_velocity_max = 1.25 + strength * 1.15
	drops.gravity = Vector3(0.0, -7.5, 0.0)
	drops.damping_min = 0.4
	drops.damping_max = 1.1
	drops.scale_amount_min = 0.025
	drops.scale_amount_max = 0.055
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(drops)
	drops.global_position = point + Vector3.UP * 0.025
	drops.emitting = true
	get_tree().create_timer(drops.lifetime + 0.20).timeout.connect(func() -> void:
		if is_instance_valid(drops):
			drops.queue_free()
	)


func _process(delta: float) -> void:
	for i in range(_ripples.size() - 1, -1, -1):
		var ripple: Dictionary = _ripples[i]
		ripple["age"] = float(ripple["age"]) + delta
		var t := float(ripple["age"]) / float(ripple["life"])
		var ring := ripple["node"] as MeshInstance3D
		var material := ripple["material"] as StandardMaterial3D
		if not is_instance_valid(ring) or t >= 1.0:
			if is_instance_valid(ring):
				ring.queue_free()
			_ripples.remove_at(i)
			continue
		var radius := float(ripple["radius"]) * lerpf(0.12, 1.0, t)
		ring.scale = Vector3(radius, 1.0, radius)
		material.albedo_color = Color(0.62, 0.84, 0.94, (1.0 - t) * 0.52)
