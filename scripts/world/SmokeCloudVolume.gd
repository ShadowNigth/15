class_name SmokeCloudVolume
extends Node3D
## Interactive physical Counter-Strike 1.5 volumetric smoke grenade cloud:
##   - High-density 3D billowing dome (~9.5m diameter x 4m tall) that genuinely blocks vision
##   - Reacts physically to HE Grenade / C4 explosions (shockwave radial dispersal + blast cavity)
##   - Reacts physically to bullet wakes (gunfire parts, ripples, and churns puffs along trajectories)
##   - Reacts physically to Players & Bots running through the cloud

const DURATION: float = 18.5
const CLOUD_RADIUS: float = 4.75

var cloud_center: Vector3 = Vector3.ZERO
var age: float = 0.0

var _puffs: Array[Sprite3D] = []
var _puff_home: Array[Vector3] = []
var _puff_pos: Array[Vector3] = []
var _puff_vel: Array[Vector3] = []
var _puff_base_scale: Array[float] = []
var _puff_peak_alpha: Array[float] = []
var _puff_thinning: Array[float] = []
var _puff_phase: Array[float] = []

var _core_lobes: Array[MeshInstance3D] = []
var _core_targets: Array[Vector3] = []

var _cavity_pos: Vector3 = Vector3.ZERO
var _cavity_radius: float = 0.0
var _cavity_strength: float = 0.0  # 1.0 = freshly blasted open, decays to 0 as smoke refills!


func setup_cloud(origin_pos: Vector3) -> void:
	global_position = origin_pos
	cloud_center = origin_pos + Vector3(0.0, 1.45, 0.0)
	RoundManager.register_smoke_volume(self)

	# Resting smoke canister on the floor
	var can_sc := GameData.get_model_scene("weapons/w_smokegrenade")
	if can_sc:
		var can_inst := can_sc.instantiate()
		for c in can_inst.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).layers = 2
		can_inst.position = Vector3(0.0, 0.04, 0.0)
		add_child(can_inst)

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() else null

	# 1. Cached Volumetric Core Lobes
	if not GameData._styled_mat_cache.has("__smoke_core_sphere"):
		var core_mat := StandardMaterial3D.new()
		core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		core_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		core_mat.albedo_color = Color(0.75, 0.77, 0.79, 0.94)
		GameData._styled_mat_cache["__smoke_core_sphere"] = core_mat

	var core_offsets := [
		Vector3(0.0, 1.55, 0.0),
		Vector3(1.15, 1.35, 0.45),
		Vector3(-1.10, 1.40, -0.50),
		Vector3(0.35, 1.45, -1.15),
		Vector3(-0.40, 1.50, 1.10),
	]
	for co in core_offsets:
		var target_c := co as Vector3
		if space != null:
			var q_c := PhysicsRayQueryParameters3D.create(
				origin_pos + Vector3(0.0, 0.6, 0.0),
				origin_pos + target_c
			)
			q_c.collision_mask = 1
			var hc := space.intersect_ray(q_c)
			if not hc.is_empty():
				target_c = ((hc["position"] as Vector3) - origin_pos) * 0.65
		var lobe := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.05
		sm.height = 3.35
		sm.radial_segments = 16
		sm.rings = 10
		lobe.mesh = sm
		lobe.layers = 2
		lobe.material_override = GameData._styled_mat_cache["__smoke_core_sphere"] as Material
		lobe.position = Vector3(0.0, 0.35, 0.0)
		lobe.scale = Vector3.ONE * 0.08
		add_child(lobe)
		_core_lobes.append(lobe)
		_core_targets.append(target_c)

	# 2. 54 Physical Billowing Cloud Puffs
	var cloud_tex := GameData.get_smoke_cloud_texture()
	var total_puffs := 54
	var golden_angle := 2.39996323
	for i in range(total_puffs):
		var frac := float(i) / float(total_puffs)
		var tier := i % 3
		var max_rad := 3.60 if tier != 2 else 2.80
		var r := sqrt(frac) * max_rad
		var theta := float(i) * golden_angle + randf_range(-0.18, 0.18)
		var y_h := 0.95
		if tier == 1:
			y_h = randf_range(1.55, 2.25)
		elif tier == 2:
			y_h = randf_range(2.35, 3.25)
		else:
			y_h = randf_range(0.75, 1.35)

		var home := Vector3(cos(theta) * r, y_h, sin(theta) * r)
		if space != null:
			var from_w := origin_pos + Vector3(0.0, clampf(y_h, 0.5, 1.8), 0.0)
			var to_w := origin_pos + home
			var q_w := PhysicsRayQueryParameters3D.create(from_w, to_w)
			q_w.collision_mask = 1
			var hw := space.intersect_ray(q_w)
			if not hw.is_empty():
				var hit_local := (hw["position"] as Vector3) - origin_pos + (hw["normal"] as Vector3) * 0.45
				home = Vector3(hit_local.x, maxf(0.75, hit_local.y), hit_local.z)

		var sp := Sprite3D.new()
		sp.layers = 2
		sp.texture = cloud_tex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.pixel_size = randf_range(0.034, 0.042)
		sp.flip_h = (i % 2 == 0)
		sp.flip_v = (i % 4 < 2)
		var lum := lerpf(0.66, 0.88, clampf((y_h - 0.7) / 2.5, 0.0, 1.0)) + randf_range(-0.04, 0.04)
		sp.modulate = Color(lum * 0.98, lum, lum * 1.02, 0.0)
		var start_p := Vector3(randf_range(-0.18, 0.18), 0.22, randf_range(-0.18, 0.18))
		sp.position = start_p
		sp.scale = Vector3.ONE * 0.25
		add_child(sp)

		_puffs.append(sp)
		_puff_home.append(home)
		_puff_pos.append(start_p)
		_puff_vel.append((home - start_p) * randf_range(2.6, 4.2))
		_puff_base_scale.append(randf_range(1.0, 1.32))
		_puff_peak_alpha.append(0.96 if r < 2.5 else 0.90)
		_puff_thinning.append(0.0)
		_puff_phase.append(randf() * TAU)


func _exit_tree() -> void:
	RoundManager.unregister_smoke_volume(self)


func apply_explosion_impulse(blast_pos: Vector3, blast_radius: float, strength: float = 1.0) -> void:
	var dist_center := cloud_center.distance_to(blast_pos)
	if dist_center > blast_radius + CLOUD_RADIUS + 1.5:
		return

	# Carve a shockwave dispersal cavity in the smoke cloud!
	var overlap := clampf(1.0 - dist_center / (blast_radius + CLOUD_RADIUS * 0.5), 0.25, 1.0)
	_cavity_pos = blast_pos
	_cavity_radius = maxf(_cavity_radius, 4.4 * strength * overlap)
	_cavity_strength = clampf(maxf(_cavity_strength, 0.96 * overlap * strength), 0.0, 1.0)

	# Violently blast individual smoke puffs radially outward from the detonation!
	for i in range(_puffs.size()):
		var world_p := global_position + _puff_pos[i]
		var diff := world_p - blast_pos
		var d := diff.length()
		if d < blast_radius * 1.15:
			var dir := (diff / maxf(0.15, d))
			var falloff := pow(1.0 - d / (blast_radius * 1.15), 0.75)
			_puff_vel[i] += (dir * 19.5 + Vector3(0.0, 4.5, 0.0)) * falloff * strength
			_puff_thinning[i] = clampf(_puff_thinning[i] + 0.88 * falloff, 0.0, 0.92)


func apply_bullet_wake(seg_a: Vector3, seg_b: Vector3, strength: float = 1.0) -> void:
	var ab := seg_b - seg_a
	var len_sq := ab.length_squared()
	if len_sq < 0.001:
		return
	# Quick sphere reject against entire cloud
	var tc := clampf((cloud_center - seg_a).dot(ab) / len_sq, 0.0, 1.0)
	if (seg_a + ab * tc).distance_squared_to(cloud_center) > (CLOUD_RADIUS + 1.8) * (CLOUD_RADIUS + 1.8):
		return

	var bullet_dir := ab.normalized()
	var wake_r := 1.40
	var wake_r_sq := wake_r * wake_r
	for i in range(_puffs.size()):
		var wp := global_position + _puff_pos[i]
		var t := clampf((wp - seg_a).dot(ab) / len_sq, 0.0, 1.0)
		var closest := seg_a + ab * t
		var dsq := wp.distance_squared_to(closest)
		if dsq < wake_r_sq:
			var d := sqrt(dsq)
			var falloff := 1.0 - (d / wake_r)
			var radial := (wp - closest)
			if radial.length_squared() < 0.001:
				radial = bullet_dir.cross(Vector3.UP)
			else:
				radial = radial.normalized()
			# Bullet vortex wake pushes smoke along shot trajectory & parts puffs radially outward!
			_puff_vel[i] += (bullet_dir * 4.2 + radial * 6.8) * falloff * strength
			_puff_thinning[i] = clampf(_puff_thinning[i] + 0.34 * falloff * strength, 0.0, 0.72)


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
	# If an HE grenade blasted a cavity right through this line of sight, vision opens briefly!
	if _cavity_strength > 0.48:
		var tc := clampf((_cavity_pos - a).dot(ab) / len_sq, 0.0, 1.0)
		var c_cav := a + ab * tc
		if c_cav.distance_to(_cavity_pos) < _cavity_radius * 0.78:
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

	if _cavity_strength > 0.0:
		_cavity_strength = maxf(0.0, _cavity_strength - delta * 0.38)

	var bloom := clampf(age / 0.75, 0.0, 1.0)
	var fade := clampf((DURATION - age) / 2.8, 0.0, 1.0)
	var env := bloom * fade

	# Actor body wake: players and bots moving through the cloud push puffs aside!
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
			if dsq < 2.25:
				var push_out := (wp - a_pos).normalized()
				var fac := (1.0 - sqrt(dsq) / 1.5) * delta * 8.5
				_puff_vel[i] += (a_vel * 0.55 + push_out * 2.8) * fac

	# Update 3D core lobes (shrink when blasted by HE shockwave, billow back as smoke refills!)
	var core_supp := 1.0 - _cavity_strength * 0.92
	for li in range(_core_lobes.size()):
		var lobe := _core_lobes[li]
		lobe.position = lobe.position.lerp(_core_targets[li], minf(1.0, delta * 3.5))
		var s := env * core_supp
		lobe.scale = Vector3(1.18 * s, 0.92 * s, 1.18 * s)
		lobe.visible = s > 0.06

	# Update 54 turbulent physical smoke puffs
	var spring_k := 3.2
	var drag := maxf(0.0, 1.0 - 3.6 * delta)
	for i in range(_puffs.size()):
		var ph := _puff_phase[i] + age * 1.15
		var swirl := Vector3(sin(ph) * 0.28, sin(ph * 0.7 + 1.1) * 0.16, cos(ph * 0.9) * 0.28)
		var target_p := _puff_home[i] + swirl
		var force := (target_p - _puff_pos[i]) * spring_k
		_puff_vel[i] = (_puff_vel[i] + force * delta) * drag
		_puff_pos[i] += _puff_vel[i] * delta
		if _puff_pos[i].y < 0.45:
			_puff_pos[i].y = 0.45
			if _puff_vel[i].y < 0.0:
				_puff_vel[i].y *= -0.3

		_puff_thinning[i] = maxf(0.0, _puff_thinning[i] - delta * 0.52)

		var sp := _puffs[i]
		sp.position = _puff_pos[i]
		var grow := lerpf(0.32, _puff_base_scale[i] * (1.0 + age * 0.012), bloom)
		sp.scale = Vector3.ONE * (grow + _puff_thinning[i] * 0.45)
		sp.modulate.a = clampf(_puff_peak_alpha[i] * env * (1.0 - _puff_thinning[i]), 0.0, 0.97)
