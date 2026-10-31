class_name SmokeCloudVolume
extends Node3D
## Interactive physical Counter-Strike volumetric smoke grenade cloud:
##   - Pure multi-layered unshaded cumulus billows (~9.5m diameter x 4m tall, 4 domain-warped FBM textures, ZERO plastic spheres!)
##   - Cylindrical bullet-tunnel carving + anisotropic puff stretch + high-speed exit wake tendrils when bullets cross!
##   - Shockwave radial dispersal & cavity carving from HE Grenades / C4 blasts
##   - Player & Bot body-wake parting + active ground canister hiss jet

const DURATION: float = 18.5
const CLOUD_RADIUS: float = 4.75
const MAX_BULLET_TUNNELS: int = 14

var cloud_center: Vector3 = Vector3.ZERO
var age: float = 0.0

var _puffs: Array[Sprite3D] = []
var _puff_home: Array[Vector3] = []
var _puff_pos: Array[Vector3] = []
var _puff_vel: Array[Vector3] = []
var _puff_base_scale: Array[float] = []
var _puff_peak_alpha: Array[float] = []
var _puff_thinning: Array[float] = []
var _puff_stretch: Array[Vector2] = []
var _puff_phase: Array[float] = []

var _bullet_tunnels: Array = []
var _wisp_cooldown: float = 0.0
var _vent_accum: float = 0.0

var _cavity_pos: Vector3 = Vector3.ZERO
var _cavity_radius: float = 0.0
var _cavity_strength: float = 0.0


func setup_cloud(origin_pos: Vector3) -> void:
	global_position = origin_pos
	cloud_center = origin_pos + Vector3(0.0, 1.48, 0.0)
	RoundManager.register_smoke_volume(self)

	# Resting smoke canister on the floor
	var can_sc := GameData.get_model_scene("weapons/w_smokegrenade")
	if can_sc:
		var can_inst := can_sc.instantiate()
		for c in can_inst.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			mi.layers = 2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.mesh:
				for s in range(mi.mesh.get_surface_count()):
					var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "char")
					if styled:
						mi.set_surface_override_material(s, styled)
		can_inst.position = Vector3(0.0, 0.04, 0.0)
		add_child(can_inst)

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() else null

	# Build 90 layered unshaded volumetric cumulus puffs (inner dense heart + mid cauliflower body + wispy outer skirt)
	var total_puffs: int = 90
	var golden_angle: float = 2.39996323
	for i in range(total_puffs):
		var is_core: bool = (i < 26)
		var is_mid: bool = (i >= 26 and i < 66)
		var r: float = 0.0
		var y_h: float = 1.2
		var px_sz: float = 0.040
		var peak_a: float = 0.94

		if is_core:
			var fc: float = float(i) / 26.0
			r = sqrt(fc) * 1.92
			y_h = lerpf(0.88, 2.28, fposmod(float(i) * 0.37, 1.0)) + randf_range(-0.14, 0.14)
			px_sz = randf_range(0.045, 0.055)
			peak_a = 0.97
		elif is_mid:
			var fm: float = float(i - 26) / 40.0
			r = 1.45 + sqrt(fm) * 2.05
			var tier_m: int = i % 3
			if tier_m == 0:
				y_h = randf_range(0.76, 1.38)
			elif tier_m == 1:
				y_h = randf_range(1.42, 2.30)
			else:
				y_h = randf_range(2.25, 3.20)
			px_sz = randf_range(0.036, 0.044)
			peak_a = 0.93
		else:
			var fo: float = float(i - 66) / 24.0
			r = 2.65 + sqrt(fo) * 1.48
			y_h = randf_range(0.72, 2.75)
			px_sz = randf_range(0.029, 0.036)
			peak_a = 0.84

		var theta: float = float(i) * golden_angle + randf_range(-0.20, 0.20)
		var home := Vector3(cos(theta) * r, y_h, sin(theta) * r)

		# Conform cloud organically against indoor corridors, doorways & ceilings!
		if space != null:
			var from_w := origin_pos + Vector3(0.0, clampf(y_h, 0.52, 1.75), 0.0)
			var to_w := origin_pos + home
			var q_w := PhysicsRayQueryParameters3D.create(from_w, to_w)
			q_w.collision_mask = 1
			var hw: Dictionary = space.intersect_ray(q_w)
			if not hw.is_empty():
				var hit_local: Vector3 = (hw["position"] as Vector3) - origin_pos + (hw["normal"] as Vector3) * 0.48
				home = Vector3(hit_local.x, maxf(0.72, hit_local.y), hit_local.z)

		var sp := Sprite3D.new()
		sp.layers = 2
		sp.texture = GameData.get_smoke_cloud_variant(i % 4)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false  # Eliminates harsh flat-lit polygon seams when orbiting camera!
		sp.pixel_size = px_sz
		sp.flip_h = ((i % 2) == 0)
		sp.flip_v = ((i % 4) < 2)

		# Natural volumetric vertical & radial ambient-occlusion tinting:
		# darker cool slate belly near the floor, brighter sunlit silver-grey billowing crown!
		var h_norm: float = clampf((home.y - 0.68) / 2.55, 0.0, 1.0)
		var r_norm: float = clampf(Vector2(home.x, home.z).length() / 3.9, 0.0, 1.0)
		var lum: float = lerpf(0.62, 0.90, h_norm) * lerpf(0.93, 1.04, r_norm) + randf_range(-0.035, 0.035)
		sp.modulate = Color(lum * 0.975, lum * 0.992, minf(1.0, lum * 1.025), 0.0)

		var start_p := Vector3(randf_range(-0.16, 0.16), 0.20, randf_range(-0.16, 0.16))
		sp.position = start_p
		sp.scale = Vector3.ONE * 0.22
		add_child(sp)

		_puffs.append(sp)
		_puff_home.append(home)
		_puff_pos.append(start_p)
		_puff_vel.append((home - start_p) * randf_range(2.8, 4.5))
		_puff_base_scale.append(randf_range(0.96, 1.30))
		_puff_peak_alpha.append(peak_a)
		_puff_thinning.append(0.0)
		_puff_stretch.append(Vector2.ONE)
		_puff_phase.append(randf() * TAU)


func _exit_tree() -> void:
	RoundManager.unregister_smoke_volume(self)


func apply_explosion_impulse(blast_pos: Vector3, blast_radius: float, strength: float = 1.0) -> void:
	var dist_center := cloud_center.distance_to(blast_pos)
	if dist_center > blast_radius + CLOUD_RADIUS + 1.5:
		return

	var overlap := clampf(1.0 - dist_center / (blast_radius + CLOUD_RADIUS * 0.5), 0.25, 1.0)
	_cavity_pos = blast_pos
	_cavity_radius = maxf(_cavity_radius, 4.5 * strength * overlap)
	_cavity_strength = clampf(maxf(_cavity_strength, 0.96 * overlap * strength), 0.0, 1.0)

	for i in range(_puffs.size()):
		var world_p := global_position + _puff_pos[i]
		var diff := world_p - blast_pos
		var d := diff.length()
		if d < blast_radius * 1.18:
			var dir := diff / maxf(0.15, d)
			var falloff := pow(1.0 - d / (blast_radius * 1.18), 0.75)
			_puff_vel[i] += (dir * 20.5 + Vector3(0.0, 4.8, 0.0)) * falloff * strength
			_puff_thinning[i] = clampf(_puff_thinning[i] + 0.90 * falloff, 0.0, 0.95)
			_puff_stretch[i] = Vector2(1.0 + 0.45 * falloff, maxf(0.68, 1.0 - 0.25 * falloff))


func apply_bullet_wake(seg_a: Vector3, seg_b: Vector3, strength: float = 1.0) -> void:
	var ab := seg_b - seg_a
	var len_sq := ab.length_squared()
	if len_sq < 0.001:
		return

	# Sphere-segment intersection against the smoke volume
	var outer_r: float = CLOUD_RADIUS + 1.15
	var tc := clampf((cloud_center - seg_a).dot(ab) / len_sq, 0.0, 1.0)
	var closest_c := seg_a + ab * tc
	var d_center_sq := closest_c.distance_squared_to(cloud_center)
	if d_center_sq > outer_r * outer_r:
		return

	var seg_len := sqrt(len_sq)
	var bullet_dir := ab / seg_len
	var half_chord := sqrt(maxf(0.04, outer_r * outer_r - d_center_sq))
	var t_mid := (closest_c - seg_a).dot(bullet_dir)
	var enter_d := clampf(t_mid - half_chord, 0.0, seg_len)
	var exit_d := clampf(t_mid + half_chord, 0.0, seg_len)
	if exit_d - enter_d < 0.15:
		return

	var entry_pt := seg_a + bullet_dir * enter_d
	var exit_pt := seg_a + bullet_dir * exit_d
	var cal := clampf(strength, 0.55, 2.0)

	# 1. Register or widen a 3D cylindrical bullet-vortex tunnel through the cloud!
	var merged := false
	for ti in range(_bullet_tunnels.size()):
		var tun := _bullet_tunnels[ti] as Dictionary
		var ta: Vector3 = tun["a"]
		var tdir: Vector3 = tun["dir"]
		if tdir.dot(bullet_dir) > 0.92 and ta.distance_squared_to(entry_pt) < 0.42:
			tun["r"] = minf(1.85, float(tun["r"]) + 0.16 * cal)
			tun["strength"] = clampf(float(tun["strength"]) + 0.28 * cal, 0.0, 1.35)
			tun["age"] = 0.0
			merged = true
			break

	if not merged:
		while _bullet_tunnels.size() >= MAX_BULLET_TUNNELS:
			_bullet_tunnels.pop_front()
		_bullet_tunnels.append({
			"a": entry_pt,
			"b": exit_pt,
			"dir": bullet_dir,
			"r": clampf(0.95 + 0.26 * cal, 0.95, 1.55),
			"strength": clampf(0.88 * cal, 0.65, 1.25),
			"age": 0.0,
			"dur": clampf(1.35 + 0.22 * cal, 1.30, 1.85),
		})

	# 2. Immediate physical shock + radial parting + shear stretch on every grazed puff!
	var wake_r: float = 1.75 + 0.22 * cal
	var wake_r_sq: float = wake_r * wake_r
	var t_ab := exit_pt - entry_pt
	var t_len_sq := maxf(0.01, t_ab.length_squared())

	for i in range(_puffs.size()):
		var wp := global_position + _puff_pos[i]
		var t := clampf((wp - entry_pt).dot(t_ab) / t_len_sq, 0.0, 1.0)
		var closest := entry_pt + t_ab * t
		var dsq := wp.distance_squared_to(closest)
		if dsq < wake_r_sq:
			var d := sqrt(dsq)
			var falloff := pow(1.0 - (d / wake_r), 0.72)
			var radial := wp - closest
			if radial.length_squared() < 0.001:
				var perp := bullet_dir.cross(Vector3.UP)
				if perp.length_squared() < 0.001:
					perp = Vector3.RIGHT
				radial = perp.normalized().rotated(bullet_dir, float(i) * 1.9)
			else:
				radial = radial.normalized()

			# Part puffs strongly outward from bullet ray + drag forward with swirling curl!
			var swirl_tan := bullet_dir.cross(radial)
			_puff_vel[i] += (radial * 14.8 + bullet_dir * 6.8 + swirl_tan * 3.4) * falloff * cal
			_puff_thinning[i] = clampf(_puff_thinning[i] + 0.68 * falloff * cal, 0.0, 0.94)
			var stretch_amt := 0.42 * falloff * cal
			_puff_stretch[i] = Vector2(
				clampf(_puff_stretch[i].x + stretch_amt, 0.72, 1.65),
				clampf(_puff_stretch[i].y - stretch_amt * 0.48, 0.62, 1.25)
			)

	# 3. Rip visible high-speed smoke tendrils out the exit (and entry) side along the bullet path!
	if age > 0.25 and (DURATION - age) > 1.0 and _wisp_cooldown <= 0.0:
		_wisp_cooldown = 0.045
		_spawn_bullet_wake_tendrils(entry_pt, exit_pt, bullet_dir, cal)


func _spawn_bullet_wake_tendrils(entry_pt: Vector3, exit_pt: Vector3, bullet_dir: Vector3, cal: float) -> void:
	var env := clampf(age / 0.75, 0.0, 1.0) * clampf((DURATION - age) / 2.8, 0.0, 1.0)
	if env < 0.15:
		return

	# Spawn 2 fast exit-wake smoke tendrils + 1 entry eddy puff
	for wi in range(3):
		var is_exit: bool = (wi < 2)
		var base_w: Vector3 = exit_pt if is_exit else entry_pt
		var sp := Sprite3D.new()
		sp.layers = 2
		sp.texture = GameData.get_smoke_cloud_variant((wi + randi()) % 4)
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.shaded = false
		var px: float = (0.018 if wi == 0 else 0.013) * clampf(cal, 0.8, 1.35)
		sp.pixel_size = px
		sp.modulate = Color(0.82, 0.84, 0.87, 0.66 * env)
		add_child(sp)
		var jitter := Vector3(randf_range(-0.16, 0.16), randf_range(-0.14, 0.16), randf_range(-0.16, 0.16))
		var start_local: Vector3 = (base_w - global_position) + jitter
		sp.position = start_local
		sp.scale = Vector3(1.25, 0.82, 1.0)

		var travel: float = randf_range(1.55, 2.75) * cal if is_exit else -randf_range(0.55, 1.05)
		var end_local: Vector3 = start_local + bullet_dir * travel + Vector3(0.0, randf_range(0.18, 0.45), 0.0)
		var dur: float = randf_range(0.34, 0.48)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(sp, "position", end_local, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "scale", Vector3(2.15, 1.55, 1.0), dur)
		tw.tween_property(sp, "modulate:a", 0.0, dur)
		tw.chain().tween_callback(_retire_child_sprite.bind(sp))


func _retire_child_sprite(sp: Sprite3D) -> void:
	if is_instance_valid(sp):
		if sp.get_parent() != null:
			sp.get_parent().remove_child(sp)
		sp.queue_free()


func _spawn_canister_vent_wisp(env: float) -> void:
	var sp := Sprite3D.new()
	sp.layers = 2
	sp.texture = GameData.get_smoke_cloud_variant(randi() % 4)
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	sp.pixel_size = 0.012
	sp.modulate = Color(0.86, 0.88, 0.90, 0.52 * env)
	sp.position = Vector3(randf_range(-0.06, 0.06), 0.12, randf_range(-0.06, 0.06))
	sp.scale = Vector3.ONE * 0.45
	add_child(sp)

	var end_p := Vector3(randf_range(-0.55, 0.55), randf_range(1.15, 1.85), randf_range(-0.55, 0.55))
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sp, "position", end_p, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "scale", Vector3.ONE * 1.65, 0.55)
	tw.tween_property(sp, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(_retire_child_sprite.bind(sp))


func get_density_at(pt: Vector3) -> float:
	var d := pt.distance_to(cloud_center)
	if d > CLOUD_RADIUS * 1.15:
		return 0.0
	var rem := DURATION - age
	var time_fac := clampf(age / 0.80, 0.0, 1.0) * clampf(rem / 2.8, 0.0, 1.0)
	var radial := 1.0 - smoothstep(CLOUD_RADIUS * 0.42, CLOUD_RADIUS * 1.12, d)
	var dens := radial * time_fac
	if _cavity_strength > 0.02:
		var cd := pt.distance_to(_cavity_pos)
		if cd < _cavity_radius:
			var hole := (1.0 - smoothstep(_cavity_radius * 0.35, _cavity_radius, cd)) * _cavity_strength
			dens *= (1.0 - hole)

	for item in _bullet_tunnels:
		var tun := item as Dictionary
		var ta: Vector3 = tun["a"]
		var tb: Vector3 = tun["b"]
		var tab: Vector3 = tb - ta
		var lsq: float = maxf(0.01, tab.length_squared())
		var t: float = clampf((pt - ta).dot(tab) / lsq, 0.0, 1.0)
		var td: float = pt.distance_to(ta + tab * t)
		var tr: float = float(tun["r"])
		if td < tr:
			var life_f: float = 1.0 - clampf(float(tun["age"]) / float(tun["dur"]), 0.0, 1.0)
			var carve: float = (1.0 - td / tr) * minf(0.88, float(tun["strength"]) * life_f)
			dens *= (1.0 - carve)

	return clampf(dens, 0.0, 1.0)


func blocks_segment(a: Vector3, b: Vector3) -> bool:
	if age < 0.35 or (DURATION - age) < 0.8:
		return false
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.001:
		return false
	var t := clampf((cloud_center - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest := a + ab * t
	if closest.distance_squared_to(cloud_center) > CLOUD_RADIUS * CLOUD_RADIUS:
		return false
	if _cavity_strength > 0.48:
		var tc := clampf((_cavity_pos - a).dot(ab) / len_sq, 0.0, 1.0)
		var c_cav := a + ab * tc
		if c_cav.distance_to(_cavity_pos) < _cavity_radius * 0.78:
			return false
	# Heavy sustained spray tunnel aligned with sightline briefly opens visibility!
	var sight_dir := ab.normalized()
	for item in _bullet_tunnels:
		var tun := item as Dictionary
		var life_f: float = 1.0 - clampf(float(tun["age"]) / float(tun["dur"]), 0.0, 1.0)
		if float(tun["r"]) >= 1.35 and float(tun["strength"]) * life_f > 0.65:
			var tdir: Vector3 = tun["dir"]
			if absf(tdir.dot(sight_dir)) > 0.90:
				var ta: Vector3 = tun["a"]
				var ts := clampf((ta - a).dot(ab) / len_sq, 0.0, 1.0)
				if (a + ab * ts).distance_to(ta) < float(tun["r"]) * 0.75:
					return false
	return true


func _physics_process(delta: float) -> void:
	age += delta
	if age >= DURATION:
		var kids := get_children()
		for c in kids:
			remove_child(c)
			c.queue_free()
		if get_parent():
			get_parent().remove_child(self)
		queue_free()
		return

	if _wisp_cooldown > 0.0:
		_wisp_cooldown = maxf(0.0, _wisp_cooldown - delta)

	if _cavity_strength > 0.0:
		_cavity_strength = maxf(0.0, _cavity_strength - delta * 0.38)

	for ti in range(_bullet_tunnels.size() - 1, -1, -1):
		var tun := _bullet_tunnels[ti] as Dictionary
		var next_age: float = float(tun["age"]) + delta
		if next_age >= float(tun["dur"]):
			_bullet_tunnels.remove_at(ti)
		else:
			tun["age"] = next_age

	var bloom := clampf(age / 0.75, 0.0, 1.0)
	var fade := clampf((DURATION - age) / 2.8, 0.0, 1.0)
	var env := bloom * fade

	# Active canister hiss plume rising from the floor grenade
	if age < DURATION - 4.0:
		_vent_accum += delta
		if _vent_accum >= 0.16:
			_vent_accum = 0.0
			_spawn_canister_vent_wisp(env)

	# Actor body wake: players and bots moving through the cloud push & deform puffs aside!
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		var a_body := a as CharacterBody3D
		if a_body == null:
			continue
		var a_pos := a_body.global_position + Vector3(0.0, 1.1, 0.0)
		if a_pos.distance_squared_to(cloud_center) > (CLOUD_RADIUS + 1.5) * (CLOUD_RADIUS + 1.5):
			continue
		var a_vel := a_body.velocity
		var spd := a_vel.length()
		if spd < 0.6:
			continue
		for i in range(_puffs.size()):
			var wp := global_position + _puff_pos[i]
			var dsq := wp.distance_squared_to(a_pos)
			if dsq < 2.56:
				var push_out := (wp - a_pos).normalized()
				var fac := (1.0 - sqrt(dsq) / 1.6) * delta * 9.5
				_puff_vel[i] += (a_vel * 0.62 + push_out * 3.4) * fac
				_puff_thinning[i] = clampf(_puff_thinning[i] + fac * 0.22, 0.0, 0.65)

	# Update 90 turbulent physical cumulus puffs + active cylindrical bullet-tunnel carving
	var spring_k := 2.95
	var drag := maxf(0.0, 1.0 - 3.4 * delta)
	var has_tunnels: bool = not _bullet_tunnels.is_empty()

	for i in range(_puffs.size()):
		var ph := _puff_phase[i] + age * 0.95
		var swirl := Vector3(
			sin(ph) * 0.30 + cos(ph * 1.7) * 0.08,
			sin(ph * 0.68 + 1.1) * 0.18,
			cos(ph * 0.88) * 0.30 - sin(ph * 1.5) * 0.08
		)
		var target_p := _puff_home[i] + swirl
		var force := (target_p - _puff_pos[i]) * spring_k

		var tunnel_alpha_cut: float = 0.0
		if has_tunnels:
			var wp_cur := global_position + _puff_pos[i]
			for item in _bullet_tunnels:
				var tun := item as Dictionary
				var life_f: float = 1.0 - clampf(float(tun["age"]) / float(tun["dur"]), 0.0, 1.0)
				var ta: Vector3 = tun["a"]
				var tb: Vector3 = tun["b"]
				var tab: Vector3 = tb - ta
				var lsq: float = maxf(0.01, tab.length_squared())
				var t_seg: float = clampf((wp_cur - ta).dot(tab) / lsq, 0.0, 1.0)
				var axis_pt: Vector3 = ta + tab * t_seg
				var diff_r: Vector3 = wp_cur - axis_pt
				var tr: float = float(tun["r"])
				var d_sq: float = diff_r.length_squared()
				if d_sq < tr * tr:
					var d_ax: float = sqrt(d_sq)
					var pen: float = (1.0 - d_ax / tr) * life_f * float(tun["strength"])
					var rad_dir: Vector3 = diff_r / maxf(0.08, d_ax)
					force += rad_dir * (18.5 * pen)
					tunnel_alpha_cut = maxf(tunnel_alpha_cut, pen * 0.92)

		_puff_vel[i] = (_puff_vel[i] + force * delta) * drag
		_puff_pos[i] += _puff_vel[i] * delta
		if _puff_pos[i].y < 0.42:
			_puff_pos[i].y = 0.42
			if _puff_vel[i].y < 0.0:
				_puff_vel[i].y *= -0.28

		_puff_thinning[i] = maxf(0.0, _puff_thinning[i] - delta * 0.46)
		_puff_stretch[i] = _puff_stretch[i].lerp(Vector2.ONE, minf(1.0, 4.2 * delta))

		# Subtle organic breathing squash-and-stretch + bullet-wake shear deformation
		var breath_x: float = 1.0 + sin(ph * 0.82) * 0.055
		var breath_y: float = 1.0 + cos(ph * 0.74) * 0.048
		var sp := _puffs[i]
		sp.position = _puff_pos[i]
		var grow := lerpf(0.28, _puff_base_scale[i] * (1.0 + age * 0.010), bloom)
		var eff_thin: float = clampf(maxf(_puff_thinning[i], tunnel_alpha_cut), 0.0, 0.96)
		var expand: float = grow + eff_thin * 0.32
		sp.scale = Vector3(expand * _puff_stretch[i].x * breath_x, expand * _puff_stretch[i].y * breath_y, 1.0)
		sp.modulate.a = clampf(_puff_peak_alpha[i] * env * (1.0 - eff_thin) * (1.0 - _cavity_strength * 0.85), 0.0, 0.96)
