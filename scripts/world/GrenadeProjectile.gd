class_name GrenadeProjectile
extends Node3D
## Thrown HE Grenade, Flashbang, and Smoke Grenade with GoldSrc bounce physics,
## multi-layered animated CS 1.5 fireball/shockwave/spark/plume HE blasts,
## and high-volume vision-blocking 3D smoke clouds.

var grenade_type: String = "hegrenade"
var thrower: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var fuse_left: float = 1.65
var _detonated: bool = false
var _bounces: int = 0


static func _get_cached_fx_mat(key: String, tex: Texture2D, additive: bool, billboard: bool, alpha_val: float = 1.0) -> StandardMaterial3D:
	if GameData._styled_mat_cache.has(key):
		return GameData._styled_mat_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(1.0, 1.0, 1.0, alpha_val)
	GameData._styled_mat_cache[key] = mat
	return mat


static func _safe_free_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	var kids := n.get_children()
	for c in kids:
		n.remove_child(c)
		c.queue_free()
	if n.get_parent():
		n.get_parent().remove_child(n)
	n.queue_free()


static func spawn_explosion_fx(parent_node: Node, world_pos: Vector3, scale_mult: float = 1.0) -> void:
	if not is_instance_valid(parent_node):
		return

	var fx_root := Node3D.new()
	fx_root.name = "ExplosionFX"
	parent_node.add_child(fx_root)
	fx_root.global_position = world_pos

	# 1. Surface Scorch Crater Decal (raycast down/around to nearest BSP surface)
	if fx_root.get_world_3d():
		var space := fx_root.get_world_3d().direct_space_state
		var q_floor := PhysicsRayQueryParameters3D.create(
			world_pos + Vector3(0.0, 0.45, 0.0),
			world_pos - Vector3(0.0, 2.2, 0.0)
		)
		q_floor.collision_mask = 1
		var hit_floor := space.intersect_ray(q_floor)
		if not hit_floor.is_empty():
			var scorch := Sprite3D.new()
			scorch.texture = GameData.get_scorch_decal_texture()
			scorch.pixel_size = 0.024 * scale_mult
			scorch.modulate = Color(0.08, 0.07, 0.06, 0.88)
			parent_node.add_child(scorch)
			var nrm := hit_floor["normal"] as Vector3
			scorch.global_position = (hit_floor["position"] as Vector3) + nrm * 0.025
			if absf(nrm.dot(Vector3.UP)) > 0.98:
				scorch.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
			else:
				scorch.look_at(scorch.global_position + nrm, Vector3.UP)
			var stw := scorch.create_tween()
			stw.tween_interval(14.0)
			stw.tween_property(scorch, "modulate:a", 0.0, 3.0)
			stw.tween_callback(func() -> void: _safe_free_node(scorch))

	# 2. Intense Dynamic Fiery Blast OmniLight3D + Initial Flash Core
	var blast_light := OmniLight3D.new()
	blast_light.light_color = Color(1.0, 0.68, 0.24)
	blast_light.light_energy = 8.5 * scale_mult
	blast_light.omni_range = 17.5 * scale_mult
	blast_light.light_cull_mask = 3
	fx_root.add_child(blast_light)
	blast_light.position = Vector3(0.0, 0.55, 0.0)
	var ltw := blast_light.create_tween()
	ltw.tween_property(blast_light, "light_energy", 0.0, 0.48 * sqrt(scale_mult)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var flash_tex := GameData.get_texture("res://assets/sprites/ledglow.png")
	if flash_tex:
		var flare := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(4.4, 4.4) * scale_mult
		flare.mesh = qm
		flare.layers = 2
		flare.material_override = _get_cached_fx_mat("__fx_flare_add", flash_tex, true, true, 0.95)
		flare.position = Vector3(0.0, 0.55, 0.0)
		fx_root.add_child(flare)
		var ftw := flare.create_tween()
		ftw.tween_property(flare, "scale", Vector3.ONE * 1.85, 0.14)
		ftw.tween_callback(func() -> void: flare.visible = false)

	# 3. Expanding Ground Shockwave Ring
	var ring_mi := MeshInstance3D.new()
	var ring_quad := QuadMesh.new()
	ring_quad.size = Vector2(1.2, 1.2) * scale_mult
	ring_quad.orientation = PlaneMesh.FACE_Y
	ring_mi.mesh = ring_quad
	ring_mi.layers = 2
	ring_mi.material_override = _get_cached_fx_mat("__fx_shock_ring", GameData.get_shockwave_ring_texture(), true, false, 0.85)
	ring_mi.position = Vector3(0.0, 0.12, 0.0)
	fx_root.add_child(ring_mi)
	var rtw := ring_mi.create_tween()
	rtw.tween_property(ring_mi, "scale", Vector3(6.8, 1.0, 6.8), 0.30 * sqrt(scale_mult)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rtw.tween_callback(func() -> void: ring_mi.visible = false)

	# 4. Three Staggered Animated CS 1.5 Fireball Columns (fexplo, fexplo1, eexplo frames 0..7!)
	var columns := [
		{"prefix": "fexplo", "offset": Vector3(0.0, 0.95, 0.0) * scale_mult, "sz": 4.2 * scale_mult, "delay": 0.0, "dur": 0.50},
		{"prefix": "fexplo1", "offset": Vector3(0.52, 1.25, -0.38) * scale_mult, "sz": 3.7 * scale_mult, "delay": 0.05, "dur": 0.54},
		{"prefix": "eexplo", "offset": Vector3(-0.48, 0.82, 0.44) * scale_mult, "sz": 3.5 * scale_mult, "delay": 0.09, "dur": 0.52},
	]
	for col_info in columns:
		var pref := String(col_info["prefix"])
		var frames: Array[StandardMaterial3D] = []
		for fi in range(8):
			var spath := ("res://assets/sprites/%s.png" % pref) if fi == 0 else ("res://assets/sprites/%s_%d.png" % [pref, fi])
			var t := GameData.get_texture(spath)
			if t:
				frames.append(_get_cached_fx_mat("__fx_add_%s_%d" % [pref, fi], t, true, true, 1.0))
		if frames.is_empty():
			continue
		var fb_mi := MeshInstance3D.new()
		var fb_q := QuadMesh.new()
		var base_sz := float(col_info["sz"])
		fb_q.size = Vector2(base_sz, base_sz * 1.12)
		fb_mi.mesh = fb_q
		fb_mi.layers = 2
		fb_mi.material_override = frames[0]
		fb_mi.position = col_info["offset"] as Vector3
		fb_mi.scale = Vector3.ONE * 0.55
		fb_mi.visible = false
		fx_root.add_child(fb_mi)

		var delay_t := float(col_info["delay"])
		var step_dt := float(col_info["dur"]) / float(frames.size())
		var ctw := fb_mi.create_tween()
		if delay_t > 0.0:
			ctw.tween_interval(delay_t)
		ctw.tween_callback(func() -> void: fb_mi.visible = true)
		for fi in range(frames.size()):
			var fmat := frames[fi]
			var target_s := lerpf(0.82, 1.48, float(fi + 1) / float(frames.size()))
			ctw.tween_callback((func(m: StandardMaterial3D) -> void: fb_mi.material_override = m).bind(fmat))
			ctw.tween_property(fb_mi, "scale", Vector3.ONE * target_s, step_dt)
		ctw.tween_callback(func() -> void: fb_mi.visible = false)

	# 5. High-Velocity Fiery Sparks & Shrapnel Burst (CPUParticles3D - native gl_compatibility!)
	var sparks := CPUParticles3D.new()
	sparks.layers = 2
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = int(38.0 * scale_mult)
	sparks.lifetime = 0.62
	sparks.explosiveness = 0.96
	var sp_mesh := QuadMesh.new()
	sp_mesh.size = Vector2(0.11, 0.11) * scale_mult
	sp_mesh.material = _get_cached_fx_mat("__fx_spark_quad", flash_tex if flash_tex else GameData.get_shockwave_ring_texture(), true, true, 1.0)
	sparks.mesh = sp_mesh
	sparks.direction = Vector3.UP
	sparks.spread = 82.0
	sparks.initial_velocity_min = 9.0 * sqrt(scale_mult)
	sparks.initial_velocity_max = 19.5 * sqrt(scale_mult)
	sparks.gravity = Vector3(0.0, -22.0, 0.0)
	sparks.damping_min = 2.0
	sparks.damping_max = 5.0
	sparks.scale_amount_min = 0.6
	sparks.scale_amount_max = 1.4
	sparks.position = Vector3(0.0, 0.35, 0.0)
	fx_root.add_child(sparks)
	sparks.emitting = true

	# 6. Billowing Dark Charcoal Smoke Plume Rising from Blast
	for i in range(10):
		var bs_idx := 1 + (i % 4)
		var bs_tex := GameData.get_texture("res://assets/sprites/black_smoke%d_3.png" % bs_idx)
		if not bs_tex:
			bs_tex = GameData.get_smoke_cloud_texture()
		var sp := Sprite3D.new()
		sp.layers = 2
		sp.texture = bs_tex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.pixel_size = (0.042 if bs_tex.get_width() <= 80 else 0.026) * scale_mult
		var grey := randf_range(0.14, 0.26)
		sp.modulate = Color(grey, grey * 0.96, grey * 0.92, 0.82)
		var ang := TAU * float(i) / 10.0 + randf_range(-0.2, 0.2)
		var rad := randf_range(0.15, 0.95) * scale_mult
		var start_p := Vector3(cos(ang) * rad, randf_range(0.35, 1.1) * scale_mult, sin(ang) * rad)
		var end_p := start_p + Vector3(cos(ang) * 1.45, randf_range(1.8, 3.6), sin(ang) * 1.45) * scale_mult
		sp.position = start_p
		sp.scale = Vector3.ONE * 0.65
		fx_root.add_child(sp)

		var ptw := sp.create_tween()
		ptw.tween_interval(0.04 * float(i % 4))
		ptw.tween_property(sp, "position", end_p, 2.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ptw.parallel().tween_property(sp, "scale", Vector3.ONE * 1.85, 2.15)
		ptw.parallel().tween_property(sp, "modulate:a", 0.0, 2.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# 7. Distance-Attenuated Concussive Camera Shake for Human Player
	for a in RoundManager.actors:
		if is_instance_valid(a) and bool(a.get("is_human")) and bool(a.get("is_alive")) and a.has_method("apply_camera_shake"):
			var dist := (a as Node3D).global_position.distance_to(world_pos)
			var shake_r := 18.0 * scale_mult
			if dist < shake_r:
				var trauma := (1.0 - dist / shake_r) * 0.92 * minf(1.4, scale_mult)
				a.call("apply_camera_shake", trauma)

	var cleanup_tw := fx_root.create_tween()
	cleanup_tw.tween_interval(2.6)
	cleanup_tw.tween_callback(func() -> void: _safe_free_node(fx_root))


func setup_grenade(gtype: String, owner_actor: Node3D, start_vel: Vector3) -> void:
	grenade_type = gtype
	thrower = owner_actor
	velocity = start_vel
	fuse_left = 1.65 if gtype != "smokegrenade" else 1.85

	var sc := GameData.get_model_scene("weapons/w_" + gtype)
	if sc:
		var inst := sc.instantiate()
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).layers = 2
		add_child(inst)


func _physics_process(delta: float) -> void:
	if _detonated:
		return

	fuse_left -= delta
	if fuse_left <= 0.0:
		# Smoke grenade waits until slow/near ground like CS 1.5
		if grenade_type != "smokegrenade" or velocity.length() < 3.5 or fuse_left < -1.2:
			_detonate()
			return

	velocity.y -= 21.0 * delta  # GoldSrc ~0.55 * 800u gravity on grenades
	var step := velocity * delta
	if step.length_squared() > 0.00001:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit:
			var n: Vector3 = hit["normal"]
			global_position = hit["position"] + n * 0.06
			velocity = velocity.bounce(n) * 0.48
			if velocity.length() < 1.1 and n.y > 0.7:
				velocity = Vector3.ZERO
			elif _bounces < 5:
				_bounces += 1
				var bwav := "weapons/he_bounce-1.wav" if grenade_type == "hegrenade" else ("weapons/grenade_hit%d.wav" % randi_range(1, 3))
				AudioManager.play_3d(bwav, global_position, -4.0, 24.0)
		else:
			global_position += step
			rotate_x(delta * 7.0)


func _detonate() -> void:
	_detonated = true
	match grenade_type:
		"hegrenade":
			_detonate_he()
		"flashbang":
			_detonate_flash()
		"smokegrenade":
			_detonate_smoke()
	_safe_free_node(self)


func _detonate_he() -> void:
	AudioManager.play_3d("weapons/hegrenade-%d.wav" % randi_range(1, 2), global_position, 4.0, 72.0, 1.0, 46.0)
	spawn_explosion_fx(get_parent(), global_position, 1.0)

	var space := get_world_3d().direct_space_state
	var max_r := 11.2  # ~358 GoldSrc units
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		if is_instance_valid(thrower) and a != thrower and String(a.get("team")) == String(thrower.get("team")) and not GameData.friendly_fire:
			continue
		var target_pos: Vector3 = a.global_position + Vector3(0, 1.0, 0)
		var d := global_position.distance_to(target_pos)
		if d > max_r:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.25, 0), target_pos)
		q.collision_mask = 1
		var blocked := space.intersect_ray(q)
		var cover_mult := 0.45 if blocked else 1.0
		var dmg := 98.0 * (1.0 - d / max_r) * cover_mult
		if dmg > 1.0 and a.has_method("apply_explosion_damage"):
			a.apply_explosion_damage(thrower, dmg, "hegrenade")


func _detonate_flash() -> void:
	AudioManager.play_3d("weapons/flashbang-%d.wav" % randi_range(1, 2), global_position, 3.0, 58.0, 1.0, 38.0)

	if is_instance_valid(get_parent()):
		var flash_fx := Node3D.new()
		get_parent().add_child(flash_fx)
		flash_fx.global_position = global_position + Vector3(0.0, 0.3, 0.0)
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.99, 0.94)
		fl.light_energy = 10.0
		fl.omni_range = 24.0
		flash_fx.add_child(fl)
		var ftw := flash_fx.create_tween()
		ftw.tween_property(fl, "light_energy", 0.0, 0.20)
		ftw.tween_callback(func() -> void: _safe_free_node(flash_fx))

	var space := get_world_3d().direct_space_state
	var max_r := 46.0  # ~1500 GoldSrc units

	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		var eye_pos: Vector3 = a.get_eye_position() if a.has_method("get_eye_position") else (a.global_position + Vector3(0, 1.75, 0))
		var d := global_position.distance_to(eye_pos)
		if d > max_r:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.15, 0), eye_pos)
		q.collision_mask = 1
		if space.intersect_ray(q):
			continue
		var look_dir: Vector3 = a.get_look_forward() if a.has_method("get_look_forward") else (-a.global_transform.basis.z)
		var to_flash := (global_position - eye_pos).normalized()
		var facing := look_dir.dot(to_flash)
		var angle_factor := 1.0 if facing > 0.25 else (0.55 if facing > -0.35 else 0.22)
		var dist_factor := clampf(1.0 - (d / max_r) * 0.75, 0.2, 1.0)
		var duration := 4.8 * angle_factor * dist_factor
		if a.has_method("apply_flashbang"):
			a.apply_flashbang(duration)


func _detonate_smoke() -> void:
	AudioManager.play_3d("weapons/sg_explode.wav", global_position, 2.5, 48.0)
	var cloud_center := global_position + Vector3(0.0, 1.45, 0.0)
	RoundManager.add_smoke_cloud(cloud_center, 4.75, 18.5)

	var parent_node := get_parent()
	if not is_instance_valid(parent_node):
		return

	var smoke_root := Node3D.new()
	smoke_root.name = "VolumetricSmokeCloud"
	parent_node.add_child(smoke_root)
	smoke_root.global_position = global_position

	# Leave resting smoke canister model on the ground during cloud lifetime
	var can_sc := GameData.get_model_scene("weapons/w_smokegrenade")
	if can_sc:
		var can_inst := can_sc.instantiate()
		for c in can_inst.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).layers = 2
		can_inst.position = Vector3(0.0, 0.04, 0.0)
		smoke_root.add_child(can_inst)

	var cloud_tex := GameData.get_smoke_cloud_texture()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() else null

	# 1. Dense 3D Opaque-Feeling Volumetric Core Lobes (guarantees 0% sightline leakage through center!)
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
				global_position + Vector3(0.0, 0.6, 0.0),
				global_position + target_c
			)
			q_c.collision_mask = 1
			var hc := space.intersect_ray(q_c)
			if not hc.is_empty():
				target_c = ((hc["position"] as Vector3) - global_position) * 0.65
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
		lobe.scale = Vector3.ONE * 0.12
		smoke_root.add_child(lobe)
		var l_tw := lobe.create_tween()
		l_tw.tween_property(lobe, "position", target_c, 0.78).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		l_tw.parallel().tween_property(lobe, "scale", Vector3(1.18, 0.92, 1.18), 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		l_tw.tween_interval(14.8)
		l_tw.tween_property(lobe, "scale", Vector3.ONE * 0.05, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	# 2. 52 Large Overlapping Billowing 3D Cloud Puffs (4.2m - 5.2m wide each!)
	#    Arranged across 3 vertical tiers with wall-clamping raycasts so smoke hugs corridors cleanly!
	var total_puffs := 52
	var golden_angle := 2.39996323
	for i in range(total_puffs):
		var frac := float(i) / float(total_puffs)
		var tier := i % 3  # 0 = ground blanket, 1 = eye-level wall, 2 = upper dome canopy
		var max_rad := 3.55 if tier != 2 else 2.75
		var r := sqrt(frac) * max_rad
		var theta := float(i) * golden_angle + randf_range(-0.18, 0.18)
		var y_h := 0.95
		if tier == 1:
			y_h = randf_range(1.55, 2.25)
		elif tier == 2:
			y_h = randf_range(2.35, 3.25)
		else:
			y_h = randf_range(0.75, 1.35)

		var local_target := Vector3(cos(theta) * r, y_h, sin(theta) * r)
		if space != null:
			var from_w := global_position + Vector3(0.0, clampf(y_h, 0.5, 1.8), 0.0)
			var to_w := global_position + local_target
			var q_w := PhysicsRayQueryParameters3D.create(from_w, to_w)
			q_w.collision_mask = 1
			var hw := space.intersect_ray(q_w)
			if not hw.is_empty():
				var hit_local := (hw["position"] as Vector3) - global_position + (hw["normal"] as Vector3) * 0.45
				local_target = Vector3(hit_local.x, maxf(0.75, hit_local.y), hit_local.z)

		var sp := Sprite3D.new()
		sp.layers = 2
		sp.texture = cloud_tex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# 128px * 0.036 = 4.61m wide per puff!
		sp.pixel_size = randf_range(0.033, 0.041)
		sp.flip_h = (i % 2 == 0)
		sp.flip_v = (i % 4 < 2)
		# Self-shadowed 3D volumetric shading: cooler slate at base, dense neutral grey mid, brighter crown!
		var lum := lerpf(0.66, 0.88, clampf((y_h - 0.7) / 2.5, 0.0, 1.0)) + randf_range(-0.04, 0.04)
		sp.modulate = Color(lum * 0.98, lum, lum * 1.02, 0.0)
		sp.position = Vector3(randf_range(-0.2, 0.2), 0.25, randf_range(-0.2, 0.2))
		sp.scale = Vector3.ONE * 0.28
		smoke_root.add_child(sp)

		var bloom_t := randf_range(0.45, 1.05)
		var peak_alpha := 0.96 if r < 2.5 else 0.90
		var drift_vec := Vector3(randf_range(-0.42, 0.42), randf_range(0.15, 0.55), randf_range(-0.42, 0.42))

		var tw := sp.create_tween()
		tw.tween_property(sp, "position", local_target, bloom_t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sp, "scale", Vector3.ONE * randf_range(0.95, 1.22), bloom_t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sp, "modulate:a", peak_alpha, bloom_t * 0.85)
		tw.tween_property(sp, "position", local_target + drift_vec, 14.8).set_trans(Tween.TRANS_SINE)
		tw.parallel().tween_property(sp, "scale", Vector3.ONE * randf_range(1.12, 1.36), 14.8)
		tw.tween_property(sp, "modulate:a", 0.0, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	var kill_tw := smoke_root.create_tween()
	kill_tw.tween_interval(19.0)
	kill_tw.tween_callback(func() -> void: _safe_free_node(smoke_root))
