class_name DroppedWeapon
extends StaticBody3D
## Interactive physical dropped weapon / grenade / C4 backpack / Defuse thighpack on the ground.
## Features:
##   - Exact mesh-AABB geometric centering & per-weapon rotated BoxShape3D hitbox on Layer 4
##   - Substepped 3D swept sphere continuous collision (cast_motion + get_rest_info depenetration) on Layer 1
##   - Oriented barrel/stock/flank endpoint wall & crate push-out with natural wall-parallel yaw torque
##   - 3-point floor/stair/ramp support (stock + receiver + muzzle) so long rifles never clip into steps/slopes
##   - Automatic wake-up if a breakable crate or door supporting the weapon moves or shatters!

var item_id: String = ""  # weapon_id, grenade_id, "c4", or "defuser"
var clip_ammo: int = 0
var reserve_ammo: int = 0
var silenced: bool = false

var _visual_root: Node3D = null
var _hit_col: CollisionShape3D = null
var _hit_box: BoxShape3D = null
var _core_shape: SphereShape3D = null
var _shadow_mi: MeshInstance3D = null

var _half_extents: Vector3 = Vector3(0.32, 0.06, 0.16)
var _core_radius: float = 0.075
var _rest_half_h: float = 0.055
var _long_local_x: bool = true
var _is_grenade: bool = false

var _vel: Vector3 = Vector3.ZERO
var _ang_vel: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _roll: float = 0.0

var _pickup_cooldown: float = 0.55
var _settled: bool = false
var _clatter_cooldown: float = 0.0
var _support_recheck_cd: float = 0.20

# Team-share gifts: temporarily lock the donor out so they never re-pick their own drop!
var pickup_lock_actor: Node3D = null
var pickup_lock_time: float = 0.0


func _ready() -> void:
	collision_layer = 4  # Raycastable by bullets & knife, non-snagging for player/bot capsules
	collision_mask = 0

	_hit_col = CollisionShape3D.new()
	_hit_box = BoxShape3D.new()
	_hit_box.size = Vector3(0.64, 0.16, 0.32)
	_hit_col.shape = _hit_box
	add_child(_hit_col)

	_core_shape = SphereShape3D.new()
	_core_shape.radius = _core_radius


func setup_drop(id: String, clip: int, reserve: int, throw_vel: Vector3, is_silenced: bool = false) -> void:
	item_id = id
	clip_ammo = clip
	reserve_ammo = reserve
	silenced = is_silenced
	_vel = throw_vel
	_settled = false

	_is_grenade = GameData.weapons.has(id) and bool(GameData.weapons[id].get("grenade", false))
	_yaw = atan2(-throw_vel.x, -throw_vel.z) + PI * 0.5 + randf_range(-0.45, 0.45)
	_pitch = randf_range(-0.18, 0.18)
	_roll = randf_range(-0.18, 0.18)
	if _is_grenade:
		_ang_vel = Vector3(randf_range(-6.5, 6.5), randf_range(-8.0, 8.0), randf_range(-6.5, 6.5))
	else:
		_ang_vel = Vector3(randf_range(-2.6, 2.6), randf_range(-6.2, 6.2), randf_range(-2.6, 2.6))

	_visual_root = Node3D.new()
	_visual_root.name = "VisualModel"
	add_child(_visual_root)

	var mdl_name := "w_ak47"
	if id == "defuser":
		mdl_name = "w_thighpack"
	elif id == "c4":
		# The carrier backpack stays removed: a dropped bomb uses the real archi C4.
		mdl_name = String(GameData.weapons.get("c4", {}).get("w_model", "w_c4"))
	elif GameData.weapons.has(id):
		mdl_name = String(GameData.weapons[id].get("w_model", "w_" + id))

	var mdl_scale: float = GameData.get_dropped_model_scale(id) if GameData.weapons.has(id) else 1.0
	var sc := GameData.get_model_scene("weapons/" + mdl_name)
	if sc != null:
		var inst := sc.instantiate() as Node3D
		_style_meshes_recursive(inst)
		var raw_aabb := _compute_local_mesh_aabb(inst, Transform3D.IDENTITY)
		if raw_aabb.size.length_squared() > 0.0001:
			var center_local: Vector3 = raw_aabb.position + raw_aabb.size * 0.5
			inst.scale = Vector3.ONE * mdl_scale
			inst.position = -center_local * mdl_scale
			_half_extents = (raw_aabb.size * mdl_scale) * 0.5
		_visual_root.add_child(inst)
	else:
		var mi := MeshInstance3D.new()
		mi.layers = 2
		var bm := BoxMesh.new()
		bm.size = Vector3(0.38, 0.10, 0.18)
		mi.mesh = bm
		_half_extents = bm.size * 0.5
		_visual_root.add_child(mi)

	_long_local_x = (_half_extents.x >= _half_extents.z)
	_rest_half_h = clampf(_half_extents.y + 0.010, 0.036, 0.14)
	_core_radius = clampf(maxf(_half_extents.y + 0.022, 0.068 if not _is_grenade else 0.088), 0.062, 0.13)
	if _core_shape != null:
		_core_shape.radius = _core_radius

	# Fit bullet/knife Layer-4 BoxShape3D tightly to the centered weapon with generous vertical/lateral grab margin
	if _hit_box != null:
		_hit_box.size = Vector3(
			maxf(0.22, _half_extents.x * 2.04),
			maxf(0.13, _half_extents.y * 2.35 + 0.05),
			maxf(0.18, _half_extents.z * 2.08)
		)

	# Soft floor contact shadow quad so dropped weapons & grenades sit visibly grounded on surfaces
	_shadow_mi = MeshInstance3D.new()
	_shadow_mi.layers = 2
	_shadow_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sq := QuadMesh.new()
	sq.orientation = PlaneMesh.FACE_Y
	sq.size = Vector2(
		clampf(_half_extents.x * 2.15, 0.22, 1.45),
		clampf(_half_extents.z * 2.15, 0.20, 0.62)
	)
	_shadow_mi.mesh = sq
	_shadow_mi.material_override = GameData.get_drop_shadow_material()
	_shadow_mi.visible = false
	add_child(_shadow_mi)

	_sync_visual_and_hitbox()


func _compute_local_mesh_aabb(node: Node, accum_xf: Transform3D) -> AABB:
	var cur_xf := accum_xf
	if node is Node3D:
		cur_xf = accum_xf * (node as Node3D).transform

	var merged := AABB()
	var has_any := false
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var ma := mi.mesh.get_aabb()
			if ma.size.length_squared() > 0.00001:
				merged = cur_xf * ma
				has_any = true

	for c in node.get_children():
		var ca := _compute_local_mesh_aabb(c, cur_xf)
		if ca.size.length_squared() > 0.00001:
			if has_any:
				merged = merged.merge(ca)
			else:
				merged = ca
				has_any = true
	return merged


func _style_meshes_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "w_drop")
				if styled != null:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_style_meshes_recursive(c)


func _sync_visual_and_hitbox() -> void:
	var rot_b := Basis.from_euler(Vector3(_pitch, _yaw, _roll), EULER_ORDER_YXZ)
	if _visual_root != null:
		_visual_root.basis = rot_b
	if _hit_col != null:
		_hit_col.basis = rot_b


func apply_bullet_impulse(hit_pos: Vector3, bullet_dir: Vector3, damage: float) -> void:
	_settled = false
	_pickup_cooldown = maxf(_pickup_cooldown, 0.20)

	var dir := bullet_dir.normalized()
	var mass_scale: float = 1.38 if _is_grenade else 1.0
	var push_mag := clampf(damage * 0.13 * mass_scale, 2.8, 10.5)
	var up_pop := clampf(damage * 0.055 * mass_scale, 1.4, 4.2)
	_vel += Vector3(dir.x * push_mag, maxf(0.85, dir.y * push_mag * 0.45) + up_pop, dir.z * push_mag)
	if _vel.length() > 20.0:
		_vel = _vel.normalized() * 20.0

	var lever := hit_pos - global_position
	var torque := lever.cross(dir * push_mag) * 15.0
	_ang_vel += torque + Vector3(randf_range(-3.0, 3.0), randf_range(-8.5, 8.5), randf_range(-3.0, 3.0))
	if _ang_vel.length() > 24.0:
		_ang_vel = _ang_vel.normalized() * 24.0

	AudioManager.play_3d("weapons/ric_metal-%d.wav" % randi_range(1, 2), hit_pos, -1.5, 24.0, randf_range(0.94, 1.10))
	_spawn_ricochet_spark(hit_pos)


func apply_explosion_impulse(blast_pos: Vector3, blast_radius: float, peak_speed: float = 16.5) -> void:
	var to_self := global_position - blast_pos
	var dist := to_self.length()
	if dist > blast_radius:
		return
	var falloff := pow(clampf(1.0 - dist / maxf(0.5, blast_radius), 0.0, 1.0), 0.85)
	if falloff <= 0.02:
		return

	_settled = false
	_pickup_cooldown = maxf(_pickup_cooldown, 0.32)

	var horiz := Vector3(to_self.x, 0.0, to_self.z)
	if horiz.length_squared() < 0.001:
		var rnd_a := randf() * TAU
		horiz = Vector3(cos(rnd_a), 0.0, sin(rnd_a))
	else:
		horiz = horiz.normalized()

	var radial_spd := peak_speed * falloff
	var up_spd := (5.2 + peak_speed * 0.45) * falloff
	_vel += horiz * radial_spd + Vector3(0.0, up_spd, 0.0)
	if _vel.length() > 23.0:
		_vel = _vel.normalized() * 23.0

	_ang_vel += Vector3(
		randf_range(-8.0, 8.0),
		randf_range(-18.0, 18.0),
		randf_range(-8.0, 8.0)
	) * falloff


func _spawn_ricochet_spark(pos: Vector3) -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	var sp := Sprite3D.new()
	sp.layers = 2
	var tex := GameData.get_texture("res://assets/sprites/ledglow.png")
	if tex == null:
		tex = GameData.get_shockwave_ring_texture()
	sp.texture = tex
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.pixel_size = 0.0042
	sp.modulate = Color(1.0, 0.86, 0.42, 0.95)
	RoundManager.game_world.add_child(sp)
	sp.global_position = pos
	var tw := sp.create_tween()
	tw.tween_property(sp, "scale", Vector3.ONE * 2.2, 0.11)
	tw.parallel().tween_property(sp, "modulate:a", 0.0, 0.11)
	tw.tween_callback(sp.queue_free)


func _play_bounce_clatter(pos_w: Vector3, impact_spd: float) -> void:
	if _clatter_cooldown > 0.0:
		return
	_clatter_cooldown = 0.13
	var vol_db: float = clampf(-11.0 + impact_spd * 1.1, -10.5, -2.5)
	if _is_grenade:
		AudioManager.play_3d("weapons/archi/cs2_flashbang/hit1.wav", pos_w, vol_db, 18.0, randf_range(0.95, 1.08))
	else:
		AudioManager.play_3d("player/pl_shell%d.wav" % randi_range(1, 3), pos_w, vol_db, 18.0, randf_range(0.64, 0.80))


func _physics_process(delta: float) -> void:
	if _pickup_cooldown > 0.0:
		_pickup_cooldown -= delta
	if _clatter_cooldown > 0.0:
		_clatter_cooldown -= delta
	if pickup_lock_time > 0.0:
		pickup_lock_time -= delta
		if pickup_lock_time <= 0.0:
			pickup_lock_actor = null

	if not is_inside_tree() or get_world_3d() == null:
		return

	var space := get_world_3d().direct_space_state

	# Wake up settled weapon if a breakable crate shattered or a door opened underneath it!
	if _settled:
		_support_recheck_cd -= delta
		if _support_recheck_cd <= 0.0:
			_support_recheck_cd = 0.20
			var q_sup := PhysicsRayQueryParameters3D.create(
				global_position + Vector3(0.0, 0.08, 0.0),
				global_position - Vector3(0.0, _rest_half_h + 0.09, 0.0)
			)
			q_sup.collision_mask = 1
			q_sup.hit_from_inside = true
			if space.intersect_ray(q_sup).is_empty():
				_settled = false

	if not _settled:
		_step_swept_physics(space, delta)

	if _pickup_cooldown <= 0.0:
		_check_actor_pickup()


func _step_swept_physics(space: PhysicsDirectSpaceState3D, delta: float) -> void:
	_vel.y -= 21.5 * delta
	var cur_pos: Vector3 = global_position

	# 1. Continuous Substepped 3D Swept Sphere Collision against BSP Floors, Walls, Crates & Doors!
	var frame_dist: float = (_vel * delta).length()
	var sub_n: int = clampi(int(ceil(frame_dist / 0.09)), 1, 6)
	var sub_dt: float = delta / float(sub_n)

	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = _core_shape
	sq.collision_mask = 1
	sq.margin = 0.008

	for _si in range(sub_n):
		# Depenetrate if starting overlapped (e.g. moving door or tight corner)
		sq.transform = Transform3D(Basis.IDENTITY, cur_pos)
		sq.motion = Vector3.ZERO
		var rest_now: Dictionary = space.get_rest_info(sq)
		if not rest_now.is_empty():
			var dep_n: Vector3 = rest_now["normal"]
			if dep_n.length_squared() > 0.001:
				cur_pos += dep_n.normalized() * 0.018
				if _vel.dot(dep_n) < 0.0:
					_vel -= dep_n * _vel.dot(dep_n)

		var sub_step: Vector3 = _vel * sub_dt
		var sub_len: float = sub_step.length()
		if sub_len <= 0.00001:
			break

		sq.transform = Transform3D(Basis.IDENTITY, cur_pos)
		sq.motion = sub_step
		var toi: PackedFloat32Array = space.cast_motion(sq)
		var safe_t: float = toi[0] if toi.size() >= 2 else 1.0
		var unsafe_t: float = toi[1] if toi.size() >= 2 else 1.0

		cur_pos += sub_step * safe_t

		if unsafe_t < 0.999:
			var hit_n := Vector3.UP
			var got_n := false
			sq.transform = Transform3D(Basis.IDENTITY, cur_pos + sub_step * maxf(unsafe_t - safe_t, 0.01))
			sq.motion = Vector3.ZERO
			var rest_hit: Dictionary = space.get_rest_info(sq)
			if not rest_hit.is_empty():
				var rn: Vector3 = rest_hit["normal"]
				if rn.length_squared() > 0.001:
					hit_n = rn.normalized()
					got_n = true

			if not got_n:
				var dir_n: Vector3 = sub_step / sub_len
				var q_fb := PhysicsRayQueryParameters3D.create(
					cur_pos - dir_n * 0.05,
					cur_pos + dir_n * (_core_radius + 0.14)
				)
				q_fb.collision_mask = 1
				q_fb.hit_from_inside = true
				var h_fb: Dictionary = space.intersect_ray(q_fb)
				if not h_fb.is_empty():
					var fn_fb: Vector3 = h_fb["normal"]
					if fn_fb.length_squared() > 0.001:
						hit_n = fn_fb.normalized()
						got_n = true

			if got_n:
				cur_pos += hit_n * 0.004
				var impact_spd: float = -_vel.dot(hit_n)
				if hit_n.y > 0.58:
					# Floor / slope / crate-top bounce & surface friction
					var rest_y: float = 0.42 if _is_grenade else 0.28
					_vel = _vel.bounce(hit_n)
					_vel.y *= rest_y
					_vel.x *= 0.74
					_vel.z *= 0.74
					_ang_vel *= 0.64
					if impact_spd > 1.85:
						_play_bounce_clatter(cur_pos, impact_spd)
				else:
					# Wall / crate-side / ceiling ricochet
					_vel = _vel.bounce(hit_n) * (0.54 if _is_grenade else 0.46)
					_ang_vel.y = -_ang_vel.y * 0.60
					_ang_vel.x *= 0.55
					_ang_vel.z *= 0.55
					if impact_spd > 2.15:
						_play_bounce_clatter(cur_pos, impact_spd)
				# Slide remaining fraction along bounced velocity
				var rem_t: float = maxf(0.0, 1.0 - safe_t)
				if rem_t > 0.02:
					sq.transform = Transform3D(Basis.IDENTITY, cur_pos)
					sq.motion = _vel * (sub_dt * rem_t)
					var toi2: PackedFloat32Array = space.cast_motion(sq)
					var safe2: float = toi2[0] if toi2.size() >= 2 else 1.0
					cur_pos += _vel * (sub_dt * rem_t * safe2)

	# 2. Integrate Yaw/Pitch/Roll safely (bounded pitch/roll so long rifles never flip vertically into floors!)
	_yaw = wrapf(_yaw + _ang_vel.y * delta, -PI, PI)
	if _is_grenade:
		_pitch = wrapf(_pitch + _ang_vel.x * delta, -PI, PI)
		_roll = wrapf(_roll + _ang_vel.z * delta, -PI, PI)
	else:
		_pitch = clampf(_pitch + _ang_vel.x * delta, -0.44, 0.44)
		_roll = clampf(_roll + _ang_vel.z * delta, -0.44, 0.44)

	# 3. Oriented Barrel / Buttstock / Flank Endpoint Bumper (prevents rifle ends from poking into walls & crates!)
	var yaw_basis := Basis(Vector3.UP, _yaw)
	var long_dir: Vector3 = yaw_basis.x if _long_local_x else yaw_basis.z
	var lat_dir: Vector3 = yaw_basis.z if _long_local_x else yaw_basis.x
	var reach_long: float = clampf(maxf(_half_extents.x, _half_extents.z), 0.10, 0.78)
	var reach_lat: float = clampf(minf(_half_extents.x, _half_extents.z), 0.08, 0.34)

	var bumper_dirs := [long_dir, -long_dir, lat_dir, -lat_dir]
	var bumper_lens := [reach_long, reach_long, reach_lat, reach_lat]
	var bumper_signs := [1.0, -1.0, 0.0, 0.0]

	for bi in range(4):
		var b_dir: Vector3 = bumper_dirs[bi]
		var b_len: float = float(bumper_lens[bi])
		var q_bmp := PhysicsRayQueryParameters3D.create(
			cur_pos + Vector3(0.0, 0.015, 0.0),
			cur_pos + Vector3(0.0, 0.015, 0.0) + b_dir * b_len
		)
		q_bmp.collision_mask = 1
		q_bmp.hit_from_inside = true
		var h_bmp: Dictionary = space.intersect_ray(q_bmp)
		if not h_bmp.is_empty():
			var wn: Vector3 = h_bmp["normal"]
			if absf(wn.y) < 0.68 and wn.length_squared() > 0.001:
				var hit_p: Vector3 = h_bmp["position"]
				var dist_hit: float = (hit_p - (cur_pos + Vector3(0.0, 0.015, 0.0))).dot(b_dir)
				var pen: float = maxf(0.0, b_len - maxf(0.0, dist_hit)) + 0.016
				var push_h := Vector3(wn.x, 0.0, wn.z)
				if push_h.length_squared() < 0.001:
					push_h = -b_dir
				else:
					push_h = push_h.normalized()
				cur_pos += push_h * pen
				var vn: float = _vel.dot(push_h)
				if vn < 0.0:
					_vel -= push_h * (vn * 1.30)
				# Natural rotational torque aligns long rifle barrel flush alongside the wall/crate!
				var end_sign: float = float(bumper_signs[bi])
				if absf(end_sign) > 0.5:
					var cross_y: float = (b_dir * end_sign).cross(push_h).y
					_ang_vel.y = clampf(_ang_vel.y + cross_y * 9.5, -14.0, 14.0)

	# 4. 3-Point Floor/Stair/Ramp Support (Rear Stock + Center Receiver + Front Muzzle!)
	var sample_span: float = reach_long * 0.76
	var probe_up: float = 0.20
	var probe_dn: float = _rest_half_h + 0.16

	var q_c := PhysicsRayQueryParameters3D.create(cur_pos + Vector3(0.0, probe_up, 0.0), cur_pos - Vector3(0.0, probe_dn, 0.0))
	q_c.collision_mask = 1
	q_c.hit_from_inside = true
	var hc: Dictionary = space.intersect_ray(q_c)

	var front_pt: Vector3 = cur_pos + long_dir * sample_span
	var q_f := PhysicsRayQueryParameters3D.create(front_pt + Vector3(0.0, probe_up, 0.0), front_pt - Vector3(0.0, probe_dn, 0.0))
	q_f.collision_mask = 1
	q_f.hit_from_inside = true
	var hf: Dictionary = space.intersect_ray(q_f)

	var back_pt: Vector3 = cur_pos - long_dir * sample_span
	var q_b := PhysicsRayQueryParameters3D.create(back_pt + Vector3(0.0, probe_up, 0.0), back_pt - Vector3(0.0, probe_dn, 0.0))
	q_b.collision_mask = 1
	q_b.hit_from_inside = true
	var hb: Dictionary = space.intersect_ray(q_b)

	var has_floor := false
	var req_y: float = -1e9
	var floor_n := Vector3.UP
	var shadow_y: float = cur_pos.y - _rest_half_h

	if not hc.is_empty() and (hc["normal"] as Vector3).y > 0.50:
		var cy: float = (hc["position"] as Vector3).y
		req_y = maxf(req_y, cy + _rest_half_h)
		floor_n = hc["normal"] as Vector3
		shadow_y = cy
		has_floor = true

	var yf: float = -1e9
	if not hf.is_empty() and (hf["normal"] as Vector3).y > 0.50:
		yf = (hf["position"] as Vector3).y
		req_y = maxf(req_y, yf + _rest_half_h - 0.02)
		if not has_floor:
			floor_n = hf["normal"] as Vector3
			shadow_y = yf
			has_floor = true

	var yb: float = -1e9
	if not hb.is_empty() and (hb["normal"] as Vector3).y > 0.50:
		yb = (hb["position"] as Vector3).y
		req_y = maxf(req_y, yb + _rest_half_h - 0.02)
		if not has_floor:
			floor_n = hb["normal"] as Vector3
			shadow_y = yb
			has_floor = true

	# The swept sphere rests slightly ABOVE the mesh rest height (core radius >
	# rest half-height), so a fixed 3.5cm window missed thin weapons and
	# grenades: they hovered visibly and never received floor friction, which
	# let them glide on their own forever. Size the window to the sphere gap
	# and snap flush to the mesh rest height whenever grounded.
	var y_tol: float = maxf(0.035, _core_radius - _rest_half_h + 0.030)
	if has_floor and cur_pos.y <= req_y + y_tol and _vel.y <= 0.45:
		cur_pos.y = req_y
		if _vel.y < 0.0:
			_vel.y = 0.0

		var h_drag: float = maxf(0.0, 1.0 - 8.2 * delta)
		_vel.x *= h_drag
		_vel.z *= h_drag
		_ang_vel *= maxf(0.0, 1.0 - 10.0 * delta)

		# Align weapon flush to slope OR stair-bridge tilt across front & rear endpoints!
		var local_fn: Vector3 = yaw_basis.inverse() * floor_n.normalized()
		var target_pitch: float = atan2(local_fn.z, maxf(0.25, local_fn.y))
		var target_roll: float = asin(clampf(-local_fn.x, -0.62, 0.62))

		if yf > -1e8 and yb > -1e8 and sample_span > 0.08:
			var span_slope: float = clampf(atan2(yf - yb, sample_span * 2.0), -0.52, 0.52)
			if _long_local_x:
				target_roll = -span_slope
			else:
				target_pitch = span_slope

		var settle_rate: float = minf(1.0, 14.0 * delta)
		_pitch = lerp_angle(_pitch, target_pitch, settle_rate)
		_roll = lerp_angle(_roll, target_roll, settle_rate)

		if _vel.length_squared() < 0.025 and _ang_vel.length_squared() < 0.05:
			_vel = Vector3.ZERO
			_ang_vel = Vector3.ZERO
			_pitch = target_pitch
			_roll = target_roll
			_settled = true
			_support_recheck_cd = 0.20

	global_position = cur_pos
	_sync_visual_and_hitbox()
	_update_contact_shadow(space, cur_pos, has_floor, shadow_y, floor_n)


func _update_contact_shadow(
	space: PhysicsDirectSpaceState3D,
	cur_pos: Vector3,
	has_near_floor: bool,
	near_y: float,
	near_n: Vector3
) -> void:
	if _shadow_mi == null:
		return
	var sh_y: float = near_y
	var sh_n: Vector3 = near_n
	var found: bool = has_near_floor
	if not found:
		var q_sh := PhysicsRayQueryParameters3D.create(cur_pos, cur_pos - Vector3(0.0, 1.35, 0.0))
		q_sh.collision_mask = 1
		var h_sh: Dictionary = space.intersect_ray(q_sh)
		if not h_sh.is_empty() and (h_sh["normal"] as Vector3).y > 0.50:
			sh_y = (h_sh["position"] as Vector3).y
			sh_n = h_sh["normal"] as Vector3
			found = true

	if not found:
		_shadow_mi.visible = false
		return

	var h_above: float = maxf(0.0, (cur_pos.y - _rest_half_h) - sh_y)
	if h_above > 1.15:
		_shadow_mi.visible = false
		return

	_shadow_mi.visible = true
	var up_v: Vector3 = sh_n.normalized()
	var fwd_v: Vector3 = Basis(Vector3.UP, _yaw).z
	var right_v: Vector3 = up_v.cross(fwd_v)
	if right_v.length_squared() < 0.001:
		right_v = up_v.cross(Vector3.RIGHT)
	right_v = right_v.normalized()
	var ortho_fwd: Vector3 = right_v.cross(up_v).normalized()
	var shrink: float = clampf(1.0 - h_above * 0.45, 0.45, 1.0)
	_shadow_mi.global_transform = Transform3D(
		Basis(right_v * shrink, up_v, ortho_fwd * shrink),
		Vector3(cur_pos.x, sh_y + 0.012, cur_pos.z)
	)


func _check_actor_pickup() -> void:
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		if pickup_lock_time > 0.0 and is_instance_valid(pickup_lock_actor) and a == pickup_lock_actor:
			continue
		var ap: Vector3 = a.global_position
		var dx: float = ap.x - global_position.x
		var dz: float = ap.z - global_position.z
		var dy: float = (ap.y + 0.45) - global_position.y
		if (dx * dx + dz * dz) > 1.38 or absf(dy) > 1.25:
			continue
		if a.has_method("try_pickup_dropped") and a.try_pickup_dropped(self):
			RoundManager.dropped_items.erase(self)
			var kids := get_children()
			for c in kids:
				remove_child(c)
				c.queue_free()
			if get_parent() != null:
				get_parent().remove_child(self)
			queue_free()
			return
