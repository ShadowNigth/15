class_name GrenadeProjectile
extends Node3D
## Thrown HE Grenade, Flashbang, and Smoke Grenade with GoldSrc bounce physics,
## multi-layered animated CS 1.5 fireball/shockwave/spark/plume HE blasts,
## and high-volume vision-blocking 3D smoke clouds.

var grenade_type: String = "hegrenade"
var thrower: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var fuse_left: float = 1.65
var _ang_vel: Vector3 = Vector3.ZERO
var _detonated: bool = false
var _bounces: int = 0
var _decoy_active: bool = false
var _decoy_life: float = 0.0
var _decoy_tick: float = 0.0
var _decoy_burst: int = 0
var _decoy_sounds: Array = []
var _decoy_light: OmniLight3D = null


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

	# 7. Physical Shockwave Impulse on Dropped Weapons & Volumetric Smoke Clouds!
	RoundManager.apply_world_explosion_physics(
		world_pos,
		13.5 * scale_mult,
		17.5 * scale_mult,
		1.15 * scale_mult
	)

	# 8. Distance-Attenuated Concussive Camera Shake for Human Player
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
	_ang_vel = Vector3(randf_range(6.0, 11.0), randf_range(-5.5, 5.5), randf_range(-4.5, 4.5))
	match gtype:
		"smokegrenade": fuse_left = 1.85
		"decoy": fuse_left = 0.85
		"molotov": fuse_left = 3.0  # normally ignites on its first surface impact
		_: fuse_left = 1.65

	var sc := GameData.get_model_scene("weapons/w_" + gtype)
	if sc:
		var inst := sc.instantiate()
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			mi.layers = 2
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if mi.mesh:
				for s in range(mi.mesh.get_surface_count()):
					var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "w_drop")
					if styled:
						mi.set_surface_override_material(s, styled)
		if inst is Node3D:
			(inst as Node3D).scale = Vector3.ONE * GameData.GRENADE_WORLD_SCALE
		add_child(inst)


func _physics_process(delta: float) -> void:
	if _decoy_active:
		_process_decoy(delta)
		return
	if _detonated:
		return

	fuse_left -= delta
	if fuse_left <= 0.0:
		# Smoke and decoy wait until slow/near ground before activating.
		if grenade_type not in ["smokegrenade", "decoy"] or velocity.length() < 3.5 or fuse_left < -1.2:
			_detonate()
			return

	velocity.y -= 21.0 * delta  # GoldSrc ~0.55 * 800u gravity on grenades
	var space := get_world_3d().direct_space_state
	var rem_dt: float = delta

	for _sub in range(2):
		if rem_dt <= 0.0001:
			break
		var spd: float = velocity.length()
		if spd < 0.05:
			break
		var step: Vector3 = velocity * rem_dt
		var dir: Vector3 = step.normalized()
		var q := PhysicsRayQueryParameters3D.create(global_position, global_position + step + dir * 0.085)
		q.collision_mask = 1 | 8
		q.hit_from_inside = true
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			global_position += step
			rotation += _ang_vel * rem_dt
			break

		var hit_pos: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		var col = hit["collider"]

		# Smash straight through fragile glass windows when thrown hard (classic CS 1.5 window entry!)
		if col is Node and (col as Node).has_meta("breakable") and spd > 4.2:
			var brk = (col as Node).get_meta("breakable")
			if is_instance_valid(brk) and int(brk.get("material_type")) == 0 and brk.has_method("apply_damage"):
				brk.call("apply_damage", 48.0, hit_pos)
				if bool(brk.get("broken")):
					velocity *= 0.74
					global_position = hit_pos + dir * 0.09
					rem_dt *= 0.5
					continue

		var travel_frac: float = clampf(global_position.distance_to(hit_pos) / maxf(0.08, step.length()), 0.0, 1.0)
		global_position = hit_pos + n * 0.075
		rem_dt *= (1.0 - travel_frac) * 0.85
		if grenade_type == "molotov":
			_detonate()
			return

		var impact_n_spd: float = absf(velocity.dot(n))
		if n.y > 0.65:
			velocity = velocity.bounce(n)
			velocity.y *= 0.42
			velocity.x *= 0.74
			velocity.z *= 0.74
			_ang_vel *= 0.65
			if velocity.length() < 1.05 and absf(velocity.y) < 0.55:
				velocity = Vector3.ZERO
				_ang_vel = Vector3.ZERO
				rotation.x = 0.0
				rotation.z = 0.0
		else:
			velocity = velocity.bounce(n) * 0.56
			_ang_vel = Vector3(-_ang_vel.x * 0.7, _ang_vel.y + randf_range(-4.0, 4.0), -_ang_vel.z * 0.7)

		if impact_n_spd > 1.35 and _bounces < 6:
			_bounces += 1
			var is_grate: bool = (col is StaticBody3D and (col as StaticBody3D).collision_layer == 8)
			var grenade_spec: Dictionary = GameData.weapons.get(grenade_type, {})
			var default_bounce := "weapons/archi/cs2_flashbang/hit1.wav" if is_grate else "weapons/archi/cs2_hegren/he_bounce-1.wav"
			var bwav := String(grenade_spec.get("bounce_sound", default_bounce))
			var vol_db: float = lerpf(-8.5, -2.5, clampf(impact_n_spd / 9.0, 0.0, 1.0))
			AudioManager.play_3d(bwav, global_position, vol_db, 24.0, randf_range(0.95, 1.06), 14.0)


func _detonate() -> void:
	_detonated = true
	match grenade_type:
		"hegrenade":
			_detonate_he()
		"flashbang":
			_detonate_flash()
		"smokegrenade":
			_detonate_smoke()
		"molotov", "incendiary":
			_detonate_fire()
		"decoy":
			_activate_decoy()
			return
	_safe_free_node(self)


func _detonate_he() -> void:
	AudioManager.play_3d("weapons/archi/core/hegrenade-%d.wav" % randi_range(1, 2), global_position, 4.0, 72.0, 1.0, 46.0)
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
			a.call("apply_explosion_damage", thrower, dmg, "hegrenade", global_position)


func _detonate_flash() -> void:
	AudioManager.play_3d("weapons/archi/core/flashbang-%d.wav" % randi_range(1, 2), global_position, 3.0, 58.0, 1.0, 38.0)

	if is_instance_valid(get_parent()):
		var flash_fx := Node3D.new()
		get_parent().add_child(flash_fx)
		flash_fx.global_position = global_position + Vector3(0.0, 0.32, 0.0)
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.99, 0.95)
		fl.light_energy = 11.5
		fl.omni_range = 26.0
		flash_fx.add_child(fl)

		var star_tex := GameData.get_texture("res://assets/sprites/3dmflaora.png")
		if not star_tex:
			star_tex = GameData.get_texture("res://assets/sprites/ledglow.png")
		if star_tex:
			var star_mi := MeshInstance3D.new()
			var sq := QuadMesh.new()
			sq.size = Vector2(3.6, 3.6)
			star_mi.mesh = sq
			star_mi.layers = 2
			star_mi.material_override = _get_cached_fx_mat("__fx_flash_star", star_tex, true, true, 0.98)
			flash_fx.add_child(star_mi)
			var stw := star_mi.create_tween()
			stw.tween_property(star_mi, "scale", Vector3.ONE * 2.2, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			stw.tween_callback(func() -> void: star_mi.visible = false)

		var ftw := flash_fx.create_tween()
		ftw.tween_property(fl, "light_energy", 0.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		ftw.tween_callback(func() -> void: _safe_free_node(flash_fx))

	RoundManager.apply_world_explosion_physics(global_position, 5.5, 6.5, 0.35)

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
	AudioManager.play_3d("weapons/archi/core/sg_explode.wav", global_position, 2.5, 48.0)
	var parent_node := get_parent()
	if not is_instance_valid(parent_node):
		return
	var cloud := SmokeCloudVolume.new()
	cloud.name = "VolumetricSmokeCloud"
	parent_node.add_child(cloud)
	cloud.setup_cloud(global_position)


func _detonate_fire() -> void:
	AudioManager.play_3d("weapons/archi/core/hegrenade-1.wav", global_position, -8.0, 28.0, 1.12, 20.0)
	var parent_node := get_parent()
	if not is_instance_valid(parent_node):
		return
	var area := IncendiaryArea.new()
	area.name = "MolotovFire" if grenade_type == "molotov" else "IncendiaryFire"
	parent_node.add_child(area)
	area.global_position = global_position
	area.setup_fire(thrower, grenade_type)


func _activate_decoy() -> void:
	_detonated = false
	_decoy_active = true
	_decoy_life = 12.0
	_decoy_tick = 0.12
	_decoy_burst = 0
	velocity = Vector3.ZERO
	_ang_vel = Vector3.ZERO
	_decoy_sounds = []
	# A decoy imitates the thrower's primary (secondary as fallback), using only
	# the archi firing samples installed with the weapon refresh.
	if is_instance_valid(thrower):
		var controller = thrower.get("weapon_ctrl")
		if controller != null:
			for slot_num in [1, 2]:
				var wid := String(controller.slots.get(slot_num, ""))
				var spec: Dictionary = GameData.weapons.get(wid, {})
				var sounds: Array = spec.get("fire_sounds", [])
				if not sounds.is_empty():
					_decoy_sounds = sounds.duplicate()
					break
	if _decoy_sounds.is_empty():
		_decoy_sounds = ["weapons/archi/core/ak47-1.wav", "weapons/archi/core/ak47-2.wav"]
	_decoy_light = OmniLight3D.new()
	_decoy_light.light_color = Color(1.0, 0.72, 0.32)
	_decoy_light.light_energy = 0.0
	_decoy_light.omni_range = 4.0
	_decoy_light.position = Vector3(0.0, 0.22, 0.0)
	add_child(_decoy_light)


func _process_decoy(delta: float) -> void:
	_decoy_life -= delta
	if _decoy_life <= 0.0:
		_detonate_decoy()
		return
	if is_instance_valid(_decoy_light):
		_decoy_light.light_energy = move_toward(_decoy_light.light_energy, 0.0, delta * 18.0)
	_decoy_tick -= delta
	if _decoy_tick > 0.0:
		return
	var wav := String(_decoy_sounds[randi() % _decoy_sounds.size()])
	AudioManager.play_3d(wav, global_position, -1.0, 48.0, randf_range(0.98, 1.02), 42.0)
	var team := String(thrower.get("team")) if is_instance_valid(thrower) else ""
	AudioManager.world_sound_emitted.emit(global_position, 42.0, team)
	if is_instance_valid(_decoy_light):
		_decoy_light.light_energy = 2.4
	_decoy_burst += 1
	if _decoy_burst >= 4:
		_decoy_burst = 0
		_decoy_tick = 0.72
	else:
		_decoy_tick = 0.095


func _detonate_decoy() -> void:
	_decoy_active = false
	_detonated = true
	AudioManager.play_3d("weapons/archi/core/sg_explode.wav", global_position, -1.0, 32.0)
	spawn_explosion_fx(get_parent(), global_position, 0.28)
	for actor in RoundManager.actors:
		if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
			continue
		if is_instance_valid(thrower) and actor != thrower and String(actor.get("team")) == String(thrower.get("team")) and not GameData.friendly_fire:
			continue
		var distance := global_position.distance_to(actor.global_position + Vector3(0.0, 0.8, 0.0))
		if distance < 2.6 and actor.has_method("apply_explosion_damage"):
			actor.call("apply_explosion_damage", thrower, 22.0 * (1.0 - distance / 2.6), "decoy", global_position)
	_safe_free_node(self)
