class_name SmokeCloudVolume
extends Node3D
## Counter-Strike 2 style Volumetric Voxel Smoke Cloud (100% gl_compatibility native, 1 MultiMesh draw call):
##   - 3D Flood-Fill Voxel Expansion: hugs BSP walls/ceilings, never bleeds through thin walls,
##     and spills constant-volume smoke further down narrow doorways, hallways, crates & stairs!
##   - Animated Domain-Warped Cumulus Shader (cs2_smoke.gdshader): self-shadowed billows, sunlit silver rims,
##     and turbulent FBM edge erosion!
##   - CS2 Bullet-Tunnel Carving & Exit Plumes: single shots punch crisp swirling peep-holes & shoot supersonic
##     smoke jets out the exit side; sustained sprays tear open wider sight corridors!
##   - CS2 HE Grenade Shockwave Clear: blasts away smoke completely for ~2.2s, refilling from canister outward!

const DURATION: float = 18.5
const CLOUD_RADIUS: float = 4.75
const VOXEL_STEP: float = 0.80
const TARGET_VOXELS: int = 144
const WAKE_POOL_COUNT: int = 28

var cloud_center: Vector3 = Vector3.ZERO
var age: float = 0.0

var _mmi: MultiMeshInstance3D = null
var _mm: MultiMesh = null
var _env_tint: Color = Color(0.95, 0.96, 0.98, 1.0)

# Primary 3D flood-filled voxel arrays
var _v_count: int = 0
var _v_home: PackedVector3Array = PackedVector3Array()
var _v_pos: PackedVector3Array = PackedVector3Array()
var _v_vel: PackedVector3Array = PackedVector3Array()
var _v_base_sz: PackedFloat32Array = PackedFloat32Array()
var _v_hop_norm: PackedFloat32Array = PackedFloat32Array()
var _v_h_norm: PackedFloat32Array = PackedFloat32Array()
var _v_seed: PackedFloat32Array = PackedFloat32Array()
var _v_carve: PackedFloat32Array = PackedFloat32Array()
var _v_hold: PackedFloat32Array = PackedFloat32Array()
var _v_agitate: PackedFloat32Array = PackedFloat32Array()
var _v_angle: PackedFloat32Array = PackedFloat32Array()
var _v_spin_vel: PackedFloat32Array = PackedFloat32Array()

# Pooled high-speed bullet-exit plumes, HE shockwave wisps & canister hiss jets (in the same MultiMesh!)
var _w_cursor: int = 0
var _w_life: PackedFloat32Array = PackedFloat32Array()
var _w_max_life: PackedFloat32Array = PackedFloat32Array()
var _w_pos: PackedVector3Array = PackedVector3Array()
var _w_vel: PackedVector3Array = PackedVector3Array()
var _w_sz_start: PackedFloat32Array = PackedFloat32Array()
var _w_sz_end: PackedFloat32Array = PackedFloat32Array()
var _w_seed: PackedFloat32Array = PackedFloat32Array()
var _w_angle: PackedFloat32Array = PackedFloat32Array()
var _w_spin: PackedFloat32Array = PackedFloat32Array()
var _w_alpha: PackedFloat32Array = PackedFloat32Array()

var _plume_cd: float = 0.0
var _vent_accum: float = 0.0


func setup_cloud(origin_pos: Vector3) -> void:
	global_position = origin_pos
	cloud_center = origin_pos + Vector3(0.0, 1.52, 0.0)
	RoundManager.register_smoke_volume(self)

	# Resting w_smokegrenade canister on the floor
	var can_sc := GameData.get_model_scene("weapons/w_smokegrenade")
	if can_sc != null:
		var can_inst := can_sc.instantiate()
		for c in can_inst.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			mi.layers = 2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "char")
					if styled != null:
						mi.set_surface_override_material(s, styled)
		can_inst.position = Vector3(0.0, 0.04, 0.0)
		add_child(can_inst)

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() != null else null

	# Sample outdoor sky vs indoor tunnel lighting so smoke naturally matches environment tone like CS2!
	if space != null:
		var q_sky := PhysicsRayQueryParameters3D.create(
			origin_pos + Vector3(0.0, 0.75, 0.0),
			origin_pos + Vector3(0.0, 26.0, 0.0)
		)
		q_sky.collision_mask = 1
		if space.intersect_ray(q_sky).is_empty():
			_env_tint = Color(1.00, 0.99, 0.97, 1.0)
		else:
			_env_tint = Color(0.84, 0.87, 0.92, 1.0)

	# 1. CS2 3D BFS Flood-Fill Voxel Generation (wall-hugging + constant-volume hallway spill!)
	_build_flood_fill_voxels(origin_pos, space)

	# 2. Initialize wake-plume pool arrays
	_w_life.resize(WAKE_POOL_COUNT)
	_w_max_life.resize(WAKE_POOL_COUNT)
	_w_pos.resize(WAKE_POOL_COUNT)
	_w_vel.resize(WAKE_POOL_COUNT)
	_w_sz_start.resize(WAKE_POOL_COUNT)
	_w_sz_end.resize(WAKE_POOL_COUNT)
	_w_seed.resize(WAKE_POOL_COUNT)
	_w_angle.resize(WAKE_POOL_COUNT)
	_w_spin.resize(WAKE_POOL_COUNT)
	_w_alpha.resize(WAKE_POOL_COUNT)
	for wi in range(WAKE_POOL_COUNT):
		_w_life[wi] = 0.0
		_w_max_life[wi] = 0.4
		_w_seed[wi] = randf()

	# 3. Single GPU-instanced MultiMeshInstance3D for ALL voxels + wake plumes!
	var total_inst: int = _v_count + WAKE_POOL_COUNT
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	var qm := QuadMesh.new()
	qm.size = Vector2(1.0, 1.0)
	_mm.mesh = qm
	_mm.instance_count = total_inst

	var zero_xf := Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), Vector3.ZERO)
	for idx in range(total_inst):
		_mm.set_instance_transform(idx, zero_xf)
		_mm.set_instance_color(idx, Color(_env_tint.r, _env_tint.g, _env_tint.b, 0.0))
		_mm.set_instance_custom_data(idx, Color(0.0, 0.0, 0.5, 0.0))

	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "CS2SmokeMultiMesh"
	_mmi.layers = 2
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mmi.material_override = GameData.get_cs2_smoke_material()
	_mmi.multimesh = _mm
	_mmi.custom_aabb = AABB(Vector3(-9.5, -2.5, -9.5), Vector3(19.0, 9.5, 19.0))
	add_child(_mmi)


func _build_flood_fill_voxels(origin_pos: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	# Find unblocked seed point right above the canister
	var seed_local := Vector3(0.0, 0.92, 0.0)
	if space != null:
		var q_up := PhysicsRayQueryParameters3D.create(
			origin_pos + Vector3(0.0, 0.22, 0.0),
			origin_pos + Vector3(0.0, 1.05, 0.0)
		)
		q_up.collision_mask = 1
		var h_up: Dictionary = space.intersect_ray(q_up)
		if not h_up.is_empty():
			seed_local = ((h_up["position"] as Vector3) - origin_pos) * 0.65 + Vector3(0.0, 0.18, 0.0)

	# 10-neighbor 3D flood connectivity (6 cardinal + 4 horizontal diagonals for smooth organic roundness)
	var dirs := [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
		Vector3i(0, 1, 0), Vector3i(0, -1, 0),
		Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1),
	]

	var visited: Dictionary = {}
	var queue: Array = []
	var accepted_local: Array[Vector3] = []
	var accepted_hops: Array[int] = []

	var start_key := Vector3i(0, 1, 0)
	visited[start_key] = true
	queue.append({"cell": start_key, "pos": seed_local, "hop": 0})

	var max_hop_seen: int = 1
	var q_head: int = 0

	# Two-pass adaptive threshold: normal dome radius 1.0, expanding up to 1.42 if walls confine the cloud!
	var e_limit: float = 1.02
	var spill_candidates: Array = []

	while (q_head < queue.size() or not spill_candidates.is_empty()) and accepted_local.size() < TARGET_VOXELS:
		if q_head >= queue.size():
			if e_limit < 1.42 and not spill_candidates.is_empty():
				e_limit = 1.42
				for sc_item in spill_candidates:
					queue.append(sc_item)
				spill_candidates.clear()
			else:
				break

		var cur: Dictionary = queue[q_head]
		q_head += 1
		var c_idx: Vector3i = cur["cell"]
		var c_pos: Vector3 = cur["pos"]
		var c_hop: int = int(cur["hop"])

		accepted_local.append(c_pos)
		accepted_hops.append(c_hop)
		if c_hop > max_hop_seen:
			max_hop_seen = c_hop

		if c_hop >= 9:
			continue

		for d_cell in dirs:
			var step_i := d_cell as Vector3i
			var n_cell: Vector3i = c_idx + step_i
			if n_cell.y < -1 or n_cell.y > 4 or abs(n_cell.x) > 7 or abs(n_cell.z) > 7:
				continue
			if visited.has(n_cell):
				continue

			var raw_local := Vector3(
				float(n_cell.x) * VOXEL_STEP,
				0.56 + float(n_cell.y) * 0.68,
				float(n_cell.z) * VOXEL_STEP
			)
			# CS2 ellipsoidal dome metric centered at y = 1.55m
			var nx: float = raw_local.x / 4.25
			var ny: float = (raw_local.y - 1.55) / 1.95
			var nz: float = raw_local.z / 4.25
			var e_dist: float = sqrt(nx * nx + ny * ny + nz * nz)
			if e_dist > 1.42:
				continue

			# Verify real 3D line-of-sight from parent voxel so smoke NEVER passes through thin walls/doors!
			var final_local := raw_local
			if space != null:
				var w_from: Vector3 = origin_pos + c_pos
				var w_to: Vector3 = origin_pos + raw_local
				var q_seg := PhysicsRayQueryParameters3D.create(w_from, w_to)
				q_seg.collision_mask = 1
				var h_seg: Dictionary = space.intersect_ray(q_seg)
				if not h_seg.is_empty():
					var hit_w: Vector3 = h_seg["position"]
					var hit_n: Vector3 = h_seg["normal"]
					# Allow hugging floor/slopes cleanly, reject wall/door crossings
					if hit_n.y > 0.65 and step_i.y <= 0:
						final_local = (hit_w - origin_pos) + Vector3(0.0, 0.52, 0.0)
					else:
						continue

			visited[n_cell] = true
			var entry_dict := {"cell": n_cell, "pos": final_local, "hop": c_hop + 1}
			if e_dist <= e_limit:
				queue.append(entry_dict)
			else:
				spill_candidates.append(entry_dict)

	_v_count = accepted_local.size()
	_v_home.resize(_v_count)
	_v_pos.resize(_v_count)
	_v_vel.resize(_v_count)
	_v_base_sz.resize(_v_count)
	_v_hop_norm.resize(_v_count)
	_v_h_norm.resize(_v_count)
	_v_seed.resize(_v_count)
	_v_carve.resize(_v_count)
	_v_hold.resize(_v_count)
	_v_agitate.resize(_v_count)
	_v_angle.resize(_v_count)
	_v_spin_vel.resize(_v_count)

	var min_y: float = 999.0
	var max_y: float = -999.0
	for i in range(_v_count):
		var py: float = accepted_local[i].y
		if py < min_y:
			min_y = py
		if py > max_y:
			max_y = py
	var y_span: float = maxf(0.8, max_y - min_y)

	for i in range(_v_count):
		# Organic sub-voxel jitter so lattice lines are completely invisible!
		var jitter := Vector3(randf_range(-0.22, 0.22), randf_range(-0.16, 0.16), randf_range(-0.22, 0.22))
		var home_p: Vector3 = accepted_local[i] + jitter
		var hop_f: float = float(accepted_hops[i]) / float(maxi(1, max_hop_seen))
		var start_p := Vector3(randf_range(-0.12, 0.12), 0.22, randf_range(-0.12, 0.12))

		_v_home[i] = home_p
		_v_pos[i] = start_p
		_v_vel[i] = (home_p - start_p) * randf_range(3.6, 5.4)
		# Overlapping volumetric lobes (~1.85m..2.35m) form a seamless cohesive cloud with zero gaps
		_v_base_sz[i] = lerpf(2.32, 1.82, hop_f) * randf_range(0.92, 1.10)
		_v_hop_norm[i] = hop_f
		_v_h_norm[i] = clampf((home_p.y - min_y) / y_span, 0.0, 1.0)
		_v_seed[i] = randf()
		_v_carve[i] = 0.0
		_v_hold[i] = 0.0
		_v_agitate[i] = 0.25
		_v_angle[i] = randf() * TAU
		_v_spin_vel[i] = randf_range(-0.22, 0.22)

	# Re-center logical cloud_center on actual flood-filled centroid
	if _v_count > 0:
		var sum_v := Vector3.ZERO
		for i in range(_v_count):
			sum_v += _v_home[i]
		cloud_center = global_position + (sum_v / float(_v_count))


func _exit_tree() -> void:
	RoundManager.unregister_smoke_volume(self)


func _emit_wake_plume(
	local_start: Vector3,
	vel_vec: Vector3,
	sz_a: float,
	sz_b: float,
	dur: float,
	peak_alpha: float,
	spin_spd: float
) -> void:
	if WAKE_POOL_COUNT <= 0:
		return
	var slot: int = _w_cursor
	_w_cursor = (_w_cursor + 1) % WAKE_POOL_COUNT
	_w_pos[slot] = local_start
	_w_vel[slot] = vel_vec
	_w_sz_start[slot] = sz_a
	_w_sz_end[slot] = sz_b
	_w_max_life[slot] = maxf(0.12, dur)
	_w_life[slot] = maxf(0.12, dur)
	_w_alpha[slot] = peak_alpha
	_w_angle[slot] = randf() * TAU
	_w_spin[slot] = spin_spd
	_w_seed[slot] = randf()


func apply_explosion_impulse(blast_pos: Vector3, blast_radius: float, strength: float = 1.0) -> void:
	if cloud_center.distance_to(blast_pos) > blast_radius + CLOUD_RADIUS + 2.2:
		return

	var eff_r: float = blast_radius * 1.18
	var any_carved := false
	for i in range(_v_count):
		var wp: Vector3 = global_position + _v_pos[i]
		var diff: Vector3 = wp - blast_pos
		var d: float = diff.length()
		if d < eff_r:
			any_carved = true
			var dir: Vector3 = diff / maxf(0.12, d)
			var falloff: float = pow(clampf(1.0 - d / eff_r, 0.0, 1.0), 0.65)
			# CS2 HE Smoke-Clear: completely disperses voxels for ~2.2s, refilling from center outward!
			_v_carve[i] = clampf(maxf(_v_carve[i], 1.0 * minf(1.0, falloff * 1.45 * strength)), 0.0, 1.0)
			_v_hold[i] = maxf(_v_hold[i], (1.25 + _v_hop_norm[i] * 0.90) * strength * falloff)
			_v_agitate[i] = 1.0
			_v_vel[i] += (dir * 18.5 + Vector3(0.0, 4.2, 0.0)) * falloff * strength
			_v_spin_vel[i] = randf_range(-5.5, 5.5)

	# Burst outward shockwave ring of turbulent smoke fragments!
	if any_carved:
		var local_blast: Vector3 = blast_pos - global_position
		for k in range(14):
			var ang: float = TAU * float(k) / 14.0 + randf_range(-0.15, 0.15)
			var out_dir := Vector3(cos(ang), randf_range(0.08, 0.38), sin(ang)).normalized()
			_emit_wake_plume(
				local_blast + out_dir * 0.7,
				out_dir * randf_range(11.0, 18.0) * strength,
				1.35,
				2.85,
				randf_range(0.42, 0.62),
				0.72,
				randf_range(-6.0, 6.0)
			)


func apply_bullet_wake(seg_a: Vector3, seg_b: Vector3, strength: float = 1.0) -> void:
	var ab: Vector3 = seg_b - seg_a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.001 or _v_count <= 0:
		return

	# Broadphase sphere reject
	var broad_r: float = CLOUD_RADIUS + 2.2
	var tc: float = clampf((cloud_center - seg_a).dot(ab) / len_sq, 0.0, 1.0)
	if (seg_a + ab * tc).distance_squared_to(cloud_center) > broad_r * broad_r:
		return

	var seg_len: float = sqrt(len_sq)
	var bullet_dir: Vector3 = ab / seg_len
	var cal: float = clampf(strength, 0.65, 2.0)

	# CS2 voxel-carving radii: crisp inner daylight peep-hole + swirling eroded outer wake!
	var core_r: float = 0.76 + 0.22 * cal
	var wake_r: float = core_r + 0.88
	var wake_r_sq: float = wake_r * wake_r

	var hit_any_voxel := false
	var min_proj: float = 1e9
	var max_proj: float = -1e9
	var first_local := Vector3.ZERO
	var last_local := Vector3.ZERO

	for i in range(_v_count):
		var wp: Vector3 = global_position + _v_pos[i]
		var proj: float = (wp - seg_a).dot(bullet_dir)
		if proj < -0.5 or proj > seg_len + 0.5:
			continue
		var closest: Vector3 = seg_a + bullet_dir * clampf(proj, 0.0, seg_len)
		var diff: Vector3 = wp - closest
		var dsq: float = diff.length_squared()
		if dsq >= wake_r_sq:
			continue

		var d: float = sqrt(dsq)
		var radial: Vector3 = diff / d if d > 0.04 else bullet_dir.cross(Vector3.UP).normalized()
		if radial.length_squared() < 0.01:
			radial = Vector3.RIGHT

		# Track actual live voxel entry & exit surfaces for supersonic wake plumes!
		if d < core_r * 1.15 and _v_carve[i] < 0.85:
			hit_any_voxel = true
			if proj < min_proj:
				min_proj = proj
				first_local = _v_pos[i]
			if proj > max_proj:
				max_proj = proj
				last_local = _v_pos[i]

		# 1. Punch cylindrical hole through core voxels
		if d < core_r:
			var core_f: float = 1.0 - (d / core_r)
			var carve_add: float = (0.86 + 0.26 * cal) * pow(core_f, 0.55)
			_v_carve[i] = clampf(_v_carve[i] + carve_add, 0.0, 1.0)
			_v_hold[i] = clampf(maxf(_v_hold[i], (0.36 + 0.18 * cal) * core_f), 0.0, 0.95)

		# 2. Agitate FBM erosion, shove voxels radially outward & spin vortex eddy!
		var wake_f: float = pow(1.0 - (d / wake_r), 0.75)
		_v_agitate[i] = clampf(_v_agitate[i] + 0.92 * wake_f * cal, 0.0, 1.0)
		_v_vel[i] += (radial * 10.8 + bullet_dir * 4.6) * wake_f * cal
		var spin_dir: float = 1.0 if ((i % 2) == 0) else -1.0
		_v_spin_vel[i] = clampf(_v_spin_vel[i] + spin_dir * 4.8 * wake_f * cal, -8.5, 8.5)

	# 3. Launch CS2 supersonic smoke exit cone & entry back-splash plumes!
	if hit_any_voxel and age > 0.22 and (DURATION - age) > 0.9 and _plume_cd <= 0.0:
		_plume_cd = 0.032
		var perp_a: Vector3 = bullet_dir.cross(Vector3.UP)
		if perp_a.length_squared() < 0.01:
			perp_a = Vector3.RIGHT
		perp_a = perp_a.normalized()
		var perp_b: Vector3 = bullet_dir.cross(perp_a).normalized()

		for p_idx in range(3):
			var spread_ang: float = randf() * TAU
			var cone_ofs: Vector3 = (perp_a * cos(spread_ang) + perp_b * sin(spread_ang)) * randf_range(0.06, 0.24)
			var jet_dir: Vector3 = (bullet_dir + cone_ofs * 0.55).normalized()
			_emit_wake_plume(
				last_local + bullet_dir * 0.25 + cone_ofs,
				jet_dir * randf_range(8.5, 14.5) * cal + Vector3(0.0, 0.8, 0.0),
				0.75 * clampf(cal, 0.85, 1.35),
				1.95 * clampf(cal, 0.85, 1.40),
				randf_range(0.32, 0.48),
				0.68,
				randf_range(-7.5, 7.5)
			)
		# Subtle entry back-puff where the bullet entered the front of the smoke
		_emit_wake_plume(
			first_local - bullet_dir * 0.18,
			(-bullet_dir * randf_range(2.2, 3.8)) + Vector3(0.0, 0.65, 0.0),
			0.62,
			1.35,
			0.30,
			0.48,
			randf_range(-5.0, 5.0)
		)


func get_density_at(pt: Vector3) -> float:
	if _v_count <= 0 or age < 0.12:
		return 0.0
	var local_pt: Vector3 = pt - global_position
	if local_pt.length_squared() > (CLOUD_RADIUS + 2.6) * (CLOUD_RADIUS + 2.6):
		return 0.0

	var fade: float = clampf((DURATION - age) / 2.6, 0.0, 1.0)
	var accum: float = 0.0
	var sense_r_sq: float = 1.95 * 1.95
	for i in range(_v_count):
		var c_val: float = _v_carve[i]
		if c_val >= 0.92:
			continue
		var dsq: float = local_pt.distance_squared_to(_v_pos[i])
		if dsq < sense_r_sq:
			var bloom_i: float = clampf((age - _v_hop_norm[i] * 0.34) / 0.26, 0.0, 1.0)
			var w: float = (1.0 - sqrt(dsq) / 1.95) * (1.0 - c_val) * bloom_i
			accum += w * 0.52
			if accum >= 1.0:
				return fade
	return clampf(accum * fade, 0.0, 1.0)


func blocks_segment(a: Vector3, b: Vector3) -> bool:
	if _v_count <= 0 or age < 0.32 or (DURATION - age) < 0.85:
		return false
	var ab: Vector3 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.001:
		return false
	var broad_r: float = CLOUD_RADIUS + 2.0
	var tc: float = clampf((cloud_center - a).dot(ab) / len_sq, 0.0, 1.0)
	if (a + ab * tc).distance_squared_to(cloud_center) > broad_r * broad_r:
		return false

	# Accumulate optical thickness through actual live uncarved 3D voxels!
	var la: Vector3 = a - global_position
	var lab: Vector3 = b - a
	var optical_depth: float = 0.0
	var hit_r_sq: float = 1.18 * 1.18
	for i in range(_v_count):
		var c_val: float = _v_carve[i]
		if c_val >= 0.80:
			continue
		var t_seg: float = clampf((_v_pos[i] - la).dot(lab) / len_sq, 0.0, 1.0)
		var dsq: float = _v_pos[i].distance_squared_to(la + lab * t_seg)
		if dsq < hit_r_sq:
			var bloom_i: float = clampf((age - _v_hop_norm[i] * 0.34) / 0.26, 0.0, 1.0)
			optical_depth += (1.0 - sqrt(dsq) / 1.18) * (1.0 - c_val) * bloom_i
			if optical_depth >= 1.35:
				return true
	return false


func _physics_process(delta: float) -> void:
	age += delta
	if age >= DURATION:
		var kids := get_children()
		for c in kids:
			remove_child(c)
			c.queue_free()
		if get_parent() != null:
			get_parent().remove_child(self)
		queue_free()
		return

	if _mm == null:
		return

	if _plume_cd > 0.0:
		_plume_cd = maxf(0.0, _plume_cd - delta)

	var fade: float = clampf((DURATION - age) / 2.6, 0.0, 1.0)

	# Continuous pressurized canister hiss jet feeding the cloud base
	if age < DURATION - 3.5:
		_vent_accum += delta
		if _vent_accum >= 0.11:
			_vent_accum = 0.0
			_emit_wake_plume(
				Vector3(randf_range(-0.06, 0.06), 0.14, randf_range(-0.06, 0.06)),
				Vector3(randf_range(-0.9, 0.9), randf_range(2.6, 4.2), randf_range(-0.9, 0.9)),
				0.48,
				1.55,
				0.48,
				0.58 * fade,
				randf_range(-3.2, 3.2)
			)

	# Player & Bot body-wake interaction: running through CS2 smoke parts & churns nearby voxels!
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		var a_body := a as CharacterBody3D
		if a_body == null:
			continue
		var a_local: Vector3 = (a_body.global_position + Vector3(0.0, 1.05, 0.0)) - global_position
		if a_local.length_squared() > (CLOUD_RADIUS + 2.4) * (CLOUD_RADIUS + 2.4):
			continue
		var a_vel: Vector3 = a_body.velocity
		var spd: float = a_vel.length()
		if spd < 0.55:
			continue
		for i in range(_v_count):
			var diff_a: Vector3 = _v_pos[i] - a_local
			var dsq_a: float = diff_a.length_squared()
			if dsq_a < 2.40:
				var d_a: float = sqrt(dsq_a)
				var push_dir: Vector3 = diff_a / maxf(0.10, d_a)
				var fac: float = (1.0 - d_a / 1.55) * delta * 8.5
				_v_vel[i] += (a_vel * 0.55 + push_dir * 3.8) * fac
				_v_agitate[i] = clampf(_v_agitate[i] + fac * 0.45, 0.0, 0.85)
				_v_carve[i] = clampf(_v_carve[i] + fac * 0.25, 0.0, 0.55)

	# 1. Update all 3D Flood-Filled Voxels & upload to MultiMesh
	var spring_k: float = 4.2
	var v_drag: float = maxf(0.0, 1.0 - 4.4 * delta)

	for i in range(_v_count):
		var seed_v: float = _v_seed[i]
		var ph: float = seed_v * TAU + age * 0.82
		var swirl := Vector3(
			sin(ph) * 0.16,
			sin(ph * 0.72 + 1.3) * 0.10,
			cos(ph * 0.91) * 0.16
		)
		var target_p: Vector3 = _v_home[i] + swirl
		var accel: Vector3 = (target_p - _v_pos[i]) * spring_k
		_v_vel[i] = (_v_vel[i] + accel * delta) * v_drag
		var next_p: Vector3 = _v_pos[i] + _v_vel[i] * delta

		# Leash displacement around flood-filled home so voxels never push through walls!
		var disp: Vector3 = next_p - _v_home[i]
		var disp_len: float = disp.length()
		if disp_len > 1.25:
			next_p = _v_home[i] + (disp / disp_len) * 1.25
			_v_vel[i] *= 0.5
		if next_p.y < 0.36:
			next_p.y = 0.36
			if _v_vel[i].y < 0.0:
				_v_vel[i].y *= -0.25
		_v_pos[i] = next_p

		# Refill carved bullet tunnels & HE cavities with natural pressurized delay
		if _v_hold[i] > 0.0:
			_v_hold[i] = maxf(0.0, _v_hold[i] - delta)
		else:
			_v_carve[i] = move_toward(_v_carve[i], 0.0, delta * 0.92)

		_v_agitate[i] = move_toward(_v_agitate[i], 0.0, delta * 0.85)
		_v_spin_vel[i] = lerpf(_v_spin_vel[i], 0.12 if (i % 2 == 0) else -0.12, minf(1.0, 2.8 * delta))
		_v_angle[i] = wrapf(_v_angle[i] + _v_spin_vel[i] * delta, -PI, PI)

		var hop_delay: float = _v_hop_norm[i] * 0.34
		var v_bloom: float = clampf((age - hop_delay) / 0.26, 0.0, 1.0)
		var carve_cur: float = _v_carve[i]
		var alpha_v: float = clampf(0.92 * v_bloom * fade * (1.0 - carve_cur), 0.0, 0.95)

		if alpha_v <= 0.008:
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), _v_pos[i]))
			_mm.set_instance_color(i, Color(_env_tint.r, _env_tint.g, _env_tint.b, 0.0))
		else:
			var grow_sz: float = _v_base_sz[i] * lerpf(0.38, 1.0, v_bloom) * (1.0 + _v_agitate[i] * 0.14)
			var squash_x: float = grow_sz * (1.0 + sin(ph * 0.9) * 0.045)
			var squash_y: float = grow_sz * (0.94 + cos(ph * 0.8) * 0.045)
			_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(squash_x, squash_y, 1.0)), _v_pos[i]))
			_mm.set_instance_color(i, Color(_env_tint.r, _env_tint.g, _env_tint.b, alpha_v))
			var eff_agitate: float = clampf(maxf(_v_agitate[i], carve_cur * 0.85), 0.0, 1.0)
			_mm.set_instance_custom_data(i, Color(seed_v, eff_agitate, _v_h_norm[i], _v_angle[i]))

	# 2. Update pooled high-speed bullet-wake plumes, HE wisps & canister jets
	var p_drag: float = maxf(0.0, 1.0 - 3.8 * delta)
	for wi in range(WAKE_POOL_COUNT):
		var mm_idx: int = _v_count + wi
		var rem_w: float = _w_life[wi]
		if rem_w <= 0.0:
			_mm.set_instance_transform(mm_idx, Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), Vector3.ZERO))
			_mm.set_instance_color(mm_idx, Color(_env_tint.r, _env_tint.g, _env_tint.b, 0.0))
			continue

		rem_w -= delta
		_w_life[wi] = rem_w
		if rem_w <= 0.0:
			_mm.set_instance_transform(mm_idx, Transform3D(Basis.from_scale(Vector3(0.001, 0.001, 0.001)), Vector3.ZERO))
			_mm.set_instance_color(mm_idx, Color(_env_tint.r, _env_tint.g, _env_tint.b, 0.0))
			continue

		_w_vel[wi] = (_w_vel[wi] + Vector3(0.0, 1.15 * delta, 0.0)) * p_drag
		_w_pos[wi] += _w_vel[wi] * delta
		_w_angle[wi] = wrapf(_w_angle[wi] + _w_spin[wi] * delta, -PI, PI)

		var prog: float = 1.0 - clampf(rem_w / _w_max_life[wi], 0.0, 1.0)
		var sz_w: float = lerpf(_w_sz_start[wi], _w_sz_end[wi], ease(prog, 0.45))
		var a_env: float = sin(minf(1.0, prog * 3.5) * PI * 0.5) * (1.0 - smoothstep(0.28, 1.0, prog))
		var alpha_w: float = clampf(_w_alpha[wi] * a_env, 0.0, 0.88)
		var h_w: float = clampf((_w_pos[wi].y - 0.4) / 2.8, 0.0, 1.0)

		_mm.set_instance_transform(mm_idx, Transform3D(Basis.from_scale(Vector3(sz_w, sz_w, 1.0)), _w_pos[wi]))
		_mm.set_instance_color(mm_idx, Color(_env_tint.r, _env_tint.g, _env_tint.b, alpha_w))
		_mm.set_instance_custom_data(mm_idx, Color(_w_seed[wi], prog * 0.72, h_w, _w_angle[wi]))
