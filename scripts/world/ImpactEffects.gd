class_name ImpactEffects
extends RefCounted
## Authentic Counter-Strike 1.5 bullet tracers, surface bullet-hole decals,
## animated GoldSrc wall_puff sprites, metal ricochet sparks/debris, and enemy blood bursts/splatters.

const MAX_DECALS: int = 96

static var _initialized: bool = false
static var _decal_ring: Array[Node3D] = []

static var _mat_decal_conc: StandardMaterial3D
static var _mat_decal_metal: StandardMaterial3D
static var _mat_decal_wood: StandardMaterial3D
static var _mat_decal_glass: StandardMaterial3D
static var _mat_decal_blood: StandardMaterial3D

static var _mat_spark: StandardMaterial3D
static var _mat_chip_conc: StandardMaterial3D
static var _mat_chip_wood: StandardMaterial3D
static var _mat_chip_glass: StandardMaterial3D
static var _mat_blood_drop: StandardMaterial3D
static var _mat_blood_mist: StandardMaterial3D
static var _mat_tracer: StandardMaterial3D

static var _quad_decal: QuadMesh
static var _quad_blood_decal: QuadMesh
static var _quad_spark: QuadMesh
static var _quad_chip: QuadMesh
static var _quad_drop: QuadMesh
static var _mesh_tracer: ArrayMesh

static var _wall_puff_frames: Array[Texture2D] = []


static func ensure_init() -> void:
	if _initialized:
		return
	_initialized = true

	# Load authentic GoldSrc wall_puff1 sprite frames
	for fi in range(12):
		var p: String = "res://assets/sprites/wall_puff1_%d.png" % fi
		if ResourceLoader.exists(p):
			var tex := load(p) as Texture2D
			if tex != null:
				_wall_puff_frames.append(tex)
	if _wall_puff_frames.is_empty():
		var fb_p: String = "res://assets/sprites/wall_puff1.png"
		if ResourceLoader.exists(fb_p):
			var fb_t := load(fb_p) as Texture2D
			if fb_t != null:
				_wall_puff_frames.append(fb_t)

	_mat_decal_conc = _make_decal_mat(_build_bullet_hole_tex(0))
	_mat_decal_metal = _make_decal_mat(_build_bullet_hole_tex(1))
	_mat_decal_wood = _make_decal_mat(_build_bullet_hole_tex(2))
	_mat_decal_glass = _make_decal_mat(_build_bullet_hole_tex(3))
	_mat_decal_blood = _make_decal_mat(_build_blood_splatter_tex())

	_quad_decal = QuadMesh.new()
	_quad_decal.size = Vector2(0.11, 0.11)
	_quad_blood_decal = QuadMesh.new()
	_quad_blood_decal.size = Vector2(0.46, 0.46)

	# Spark particle material (additive orange-white streak)
	_mat_spark = StandardMaterial3D.new()
	_mat_spark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_spark.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_spark.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_spark.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat_spark.billboard_keep_scale = true
	_mat_spark.vertex_color_use_as_albedo = true
	_mat_spark.albedo_texture = _build_soft_dot_tex(Color(1.0, 0.86, 0.45, 1.0), true)

	_quad_spark = QuadMesh.new()
	_quad_spark.size = Vector2(0.055, 0.055)
	_quad_spark.material = _mat_spark

	# Concrete / Wood / Glass chip materials
	_mat_chip_conc = _make_particle_mat(Color(0.62, 0.60, 0.56, 0.95))
	_mat_chip_wood = _make_particle_mat(Color(0.62, 0.44, 0.25, 0.95))
	_mat_chip_glass = _make_particle_mat(Color(0.76, 0.92, 0.98, 0.85))

	_quad_chip = QuadMesh.new()
	_quad_chip.size = Vector2(0.036, 0.036)

	# Blood droplet & mist materials
	_mat_blood_drop = StandardMaterial3D.new()
	_mat_blood_drop.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_blood_drop.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_blood_drop.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mat_blood_drop.billboard_keep_scale = true
	_mat_blood_drop.vertex_color_use_as_albedo = true
	_mat_blood_drop.albedo_texture = _build_soft_dot_tex(Color(0.68, 0.04, 0.04, 1.0), false)

	_quad_drop = QuadMesh.new()
	_quad_drop.size = Vector2(0.068, 0.068)
	_quad_drop.material = _mat_blood_drop

	_mat_blood_mist = StandardMaterial3D.new()
	_mat_blood_mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_blood_mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_blood_mist.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_mat_blood_mist.billboard_keep_scale = true
	_mat_blood_mist.albedo_texture = _build_blood_mist_tex()
	_mat_blood_mist.albedo_color = Color(0.82, 0.06, 0.06, 0.88)

	# Crossed-quad 3D tracer bolt mesh along -Z (1m unit length)
	_mat_tracer = StandardMaterial3D.new()
	_mat_tracer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_tracer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_tracer.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_tracer.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_tracer.albedo_color = Color(1.0, 0.84, 0.42, 0.82)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = 0.014
	# Horizontal fin along -Z
	st.add_vertex(Vector3(-hw, 0.0, 0.0))
	st.add_vertex(Vector3(hw, 0.0, 0.0))
	st.add_vertex(Vector3(hw * 0.4, 0.0, -1.0))
	st.add_vertex(Vector3(-hw, 0.0, 0.0))
	st.add_vertex(Vector3(hw * 0.4, 0.0, -1.0))
	st.add_vertex(Vector3(-hw * 0.4, 0.0, -1.0))
	# Vertical fin along -Z
	st.add_vertex(Vector3(0.0, -hw, 0.0))
	st.add_vertex(Vector3(0.0, hw, 0.0))
	st.add_vertex(Vector3(0.0, hw * 0.4, -1.0))
	st.add_vertex(Vector3(0.0, -hw, 0.0))
	st.add_vertex(Vector3(0.0, hw * 0.4, -1.0))
	st.add_vertex(Vector3(0.0, -hw * 0.4, -1.0))
	_mesh_tracer = st.commit()


static func clear_decals() -> void:
	for d in _decal_ring:
		if is_instance_valid(d):
			if d.get_parent() != null:
				d.get_parent().remove_child(d)
			d.queue_free()
	_decal_ring.clear()


static func spawn_bullet_tracer(world_root: Node3D, from_pos: Vector3, to_pos: Vector3, is_heavy: bool = false) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	ensure_init()
	var span: Vector3 = to_pos - from_pos
	var total_len: float = span.length()
	if total_len < 1.6:
		return
	var dir: Vector3 = span / total_len
	var bolt_len: float = clampf(total_len * 0.32, 1.4, 4.8) if not is_heavy else clampf(total_len * 0.48, 2.2, 7.5)
	var start_p: Vector3 = from_pos + dir * 0.65
	var end_p: Vector3 = to_pos - dir * minf(0.35, total_len * 0.15)

	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_tracer
	mi.material_override = _mat_tracer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(mi)
	mi.global_position = start_p
	var up_ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.96 else Vector3.RIGHT
	mi.look_at(start_p + dir, up_ref)
	var w_scale: float = 1.45 if is_heavy else 1.0
	mi.scale = Vector3(w_scale, w_scale, bolt_len)

	var dur: float = clampf(total_len / 240.0, 0.028, 0.065)
	var tw := world_root.create_tween()
	tw.tween_property(mi, "global_position", end_p, dur)
	tw.tween_callback(_safe_retire_node.bind(mi))


static func spawn_surface_impact(
	world_root: Node3D,
	hit_pos: Vector3,
	hit_nrm: Vector3,
	bullet_dir: Vector3,
	mat_char: String,
	caliber_scale: float = 1.0,
	attach_parent: Node3D = null
) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	ensure_init()
	var nrm: Vector3 = hit_nrm.normalized() if hit_nrm.length_squared() > 0.001 else Vector3.UP

	# 1. Persistent surface bullet-hole decal (attached to moving door/breakable if hit!)
	var decal_mat: StandardMaterial3D = _mat_decal_conc
	var hole_sz: float = 0.105 * caliber_scale
	match mat_char:
		"M", "V", "L", "G":
			decal_mat = _mat_decal_metal
			hole_sz = 0.088 * caliber_scale
		"W":
			decal_mat = _mat_decal_wood
			hole_sz = 0.108 * caliber_scale
		"Y":
			decal_mat = _mat_decal_glass
			hole_sz = 0.165 * caliber_scale

	var d_parent: Node3D = attach_parent if (attach_parent != null and is_instance_valid(attach_parent)) else world_root
	_place_decal(d_parent, hit_pos + nrm * 0.008, nrm, _quad_decal, decal_mat, hole_sz / 0.11)

	# 2. Authentic CS 1.5 animated wall_puff smoke sprite
	if not _wall_puff_frames.is_empty():
		var puff := Sprite3D.new()
		puff.texture = _wall_puff_frames[0]
		puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		puff.shaded = false
		puff.pixel_size = 0.0052 * caliber_scale
		puff.modulate = Color(0.88, 0.86, 0.82, 0.68) if mat_char != "W" else Color(0.82, 0.72, 0.56, 0.70)
		world_root.add_child(puff)
		puff.global_position = hit_pos + nrm * 0.06
		var drift_end: Vector3 = puff.global_position + nrm * 0.52 + Vector3(0.0, 0.34, 0.0)
		var tw_p := world_root.create_tween()
		tw_p.set_parallel(true)
		tw_p.tween_property(puff, "global_position", drift_end, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_p.tween_property(puff, "pixel_size", 0.0105 * caliber_scale, 0.28)
		tw_p.tween_property(puff, "modulate:a", 0.0, 0.28)
		var fcnt: int = _wall_puff_frames.size()
		for fi in range(1, fcnt):
			var tex_f: Texture2D = _wall_puff_frames[fi]
			tw_p.tween_callback(_set_sprite_tex.bind(puff, tex_f)).set_delay(0.26 * float(fi) / float(fcnt))
		tw_p.chain().tween_callback(_safe_retire_node.bind(puff))

	# 3. Ricochet Sparks (Metal/Doors/Ladders/Vents/Grates or grazing stone hits) & Surface Chips
	var is_metallic: bool = mat_char in ["M", "V", "L", "G"]
	var grazing_ric: bool = (not is_metallic and mat_char in ["C", "T"] and absf(bullet_dir.dot(nrm)) < 0.52 and randf() < 0.45)
	if is_metallic or grazing_ric:
		var refl: Vector3 = bullet_dir.bounce(nrm).normalized()
		var sparks := CPUParticles3D.new()
		sparks.emitting = false
		sparks.one_shot = true
		sparks.explosiveness = 0.96
		sparks.amount = 12 if is_metallic else 7
		sparks.lifetime = 0.24
		sparks.mesh = _quad_spark
		sparks.direction = (refl * 0.65 + nrm * 0.35).normalized()
		sparks.spread = 34.0
		sparks.initial_velocity_min = 4.2
		sparks.initial_velocity_max = 9.6
		sparks.gravity = Vector3(0.0, -14.5, 0.0)
		sparks.scale_amount_min = 0.65
		sparks.scale_amount_max = 1.35
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.95, 0.68, 1.0))
		grad.set_color(1, Color(1.0, 0.42, 0.08, 0.0))
		sparks.color_ramp = grad
		world_root.add_child(sparks)
		sparks.global_position = hit_pos + nrm * 0.03
		sparks.emitting = true

		# Brief hot spark flash on metallic ricochet
		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.72, 0.32)
		fl.light_energy = 1.35 if is_metallic else 0.85
		fl.omni_range = 2.4
		world_root.add_child(fl)
		fl.global_position = hit_pos + nrm * 0.08

		var tw_s := world_root.create_tween()
		tw_s.tween_callback(_safe_retire_node.bind(fl)).set_delay(0.045)
		tw_s.tween_callback(_safe_retire_node.bind(sparks)).set_delay(0.28)
	else:
		var chips := CPUParticles3D.new()
		chips.emitting = false
		chips.one_shot = true
		chips.explosiveness = 0.95
		chips.amount = 8
		chips.lifetime = 0.34
		var c_mesh := QuadMesh.new()
		c_mesh.size = Vector2(0.035, 0.035)
		if mat_char == "W":
			c_mesh.material = _mat_chip_wood
		elif mat_char == "Y":
			c_mesh.material = _mat_chip_glass
		else:
			c_mesh.material = _mat_chip_conc
		chips.mesh = c_mesh
		chips.direction = (nrm + Vector3(0.0, 0.35, 0.0)).normalized()
		chips.spread = 42.0
		chips.initial_velocity_min = 2.0
		chips.initial_velocity_max = 5.4
		chips.gravity = Vector3(0.0, -15.0, 0.0)
		world_root.add_child(chips)
		chips.global_position = hit_pos + nrm * 0.03
		chips.emitting = true
		var tw_c := world_root.create_tween()
		tw_c.tween_callback(_safe_retire_node.bind(chips)).set_delay(0.42)


static func spawn_blood_impact(
	world_root: Node3D,
	space: PhysicsDirectSpaceState3D,
	hit_pos: Vector3,
	bullet_dir: Vector3,
	hitgroup: int,
	armored_head: bool = false,
	damage: float = 28.0
) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	ensure_init()

	var is_head: bool = (hitgroup == 1)
	var b_scale: float = clampf(damage / 28.0, 0.85, 1.55) * (1.35 if is_head else 1.0)

	# 1. Expanding GoldSrc crimson blood mist billboard at wound site
	var mist := MeshInstance3D.new()
	var m_quad := QuadMesh.new()
	m_quad.size = Vector2(0.26 * b_scale, 0.26 * b_scale)
	mist.mesh = m_quad
	mist.material_override = _mat_blood_mist
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(mist)
	mist.global_position = hit_pos

	var tw_m := world_root.create_tween()
	tw_m.set_parallel(true)
	tw_m.tween_property(mist, "scale", Vector3.ONE * 2.25, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_m.tween_property(mist, "global_position", hit_pos + bullet_dir * 0.24 + Vector3(0.0, -0.08, 0.0), 0.22)
	tw_m.chain().tween_callback(_safe_retire_node.bind(mist))

	# 2. Gravity-arcing crimson blood droplets spray
	var drops := CPUParticles3D.new()
	drops.emitting = false
	drops.one_shot = true
	drops.explosiveness = 0.94
	drops.amount = 16 if is_head else 10
	drops.lifetime = 0.38
	drops.mesh = _quad_drop
	drops.direction = (bullet_dir * 0.55 + Vector3(0.0, 0.35, 0.0)).normalized()
	drops.spread = 48.0 if is_head else 38.0
	drops.initial_velocity_min = 1.8
	drops.initial_velocity_max = 4.8 * b_scale
	drops.gravity = Vector3(0.0, -13.5, 0.0)
	drops.scale_amount_min = 0.75
	drops.scale_amount_max = 1.45 * b_scale
	var b_grad := Gradient.new()
	b_grad.set_color(0, Color(0.86, 0.05, 0.05, 0.96))
	b_grad.set_color(1, Color(0.38, 0.02, 0.02, 0.0))
	drops.color_ramp = b_grad
	world_root.add_child(drops)
	drops.global_position = hit_pos
	drops.emitting = true

	var tw_d := world_root.create_tween()
	tw_d.tween_callback(_safe_retire_node.bind(drops)).set_delay(0.45)

	# 3. Kevlar helmet headshot spark flash ("dink" visual cue!)
	if is_head and armored_head:
		var h_sparks := CPUParticles3D.new()
		h_sparks.emitting = false
		h_sparks.one_shot = true
		h_sparks.explosiveness = 0.98
		h_sparks.amount = 10
		h_sparks.lifetime = 0.18
		h_sparks.mesh = _quad_spark
		h_sparks.direction = (-bullet_dir + Vector3(0.0, 0.5, 0.0)).normalized()
		h_sparks.spread = 52.0
		h_sparks.initial_velocity_min = 3.6
		h_sparks.initial_velocity_max = 7.8
		h_sparks.gravity = Vector3(0.0, -12.0, 0.0)
		world_root.add_child(h_sparks)
		h_sparks.global_position = hit_pos
		h_sparks.emitting = true
		var tw_hs := world_root.create_tween()
		tw_hs.tween_callback(_safe_retire_node.bind(h_sparks)).set_delay(0.24)

	# 4. Stamp crimson blood splatter decals on wall behind victim & floor beneath!
	if space != null:
		var q_wall := PhysicsRayQueryParameters3D.create(hit_pos, hit_pos + bullet_dir * 3.1)
		q_wall.collision_mask = 1
		var wh: Dictionary = space.intersect_ray(q_wall)
		if not wh.is_empty():
			var wp: Vector3 = wh["position"]
			var wn: Vector3 = wh["normal"]
			_place_decal(world_root, wp + wn * 0.009, wn, _quad_blood_decal, _mat_decal_blood, randf_range(0.75, 1.25) * b_scale)

		var down_dir: Vector3 = (bullet_dir * 0.28 + Vector3.DOWN).normalized()
		var q_flr := PhysicsRayQueryParameters3D.create(hit_pos, hit_pos + down_dir * 2.5)
		q_flr.collision_mask = 1
		var fh: Dictionary = space.intersect_ray(q_flr)
		if not fh.is_empty():
			var fp: Vector3 = fh["position"]
			var fn: Vector3 = fh["normal"]
			_place_decal(world_root, fp + fn * 0.009, fn, _quad_blood_decal, _mat_decal_blood, randf_range(0.65, 1.05))


static func _place_decal(parent_node: Node3D, pos: Vector3, nrm: Vector3, qmesh: QuadMesh, mat: StandardMaterial3D, scl: float) -> void:
	while _decal_ring.size() >= MAX_DECALS:
		var old_d: Node3D = _decal_ring.pop_front()
		if is_instance_valid(old_d):
			if old_d.get_parent() != null:
				old_d.get_parent().remove_child(old_d)
			old_d.queue_free()

	var mi := MeshInstance3D.new()
	mi.mesh = qmesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(mi)
	mi.global_position = pos
	# QuadMesh front face points along +Z; look_at aligns -Z with target, so look_at(pos - nrm) points +Z along +nrm!
	var up_ref: Vector3 = Vector3.UP if absf(nrm.dot(Vector3.UP)) < 0.96 else Vector3.RIGHT
	mi.look_at(pos - nrm, up_ref)
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU)
	mi.scale = Vector3.ONE * scl
	_decal_ring.append(mi)


static func _set_sprite_tex(sp: Sprite3D, tex: Texture2D) -> void:
	if is_instance_valid(sp):
		sp.texture = tex


static func _safe_retire_node(n: Node) -> void:
	if is_instance_valid(n):
		if n.get_parent() != null:
			n.get_parent().remove_child(n)
		n.queue_free()


static func _make_decal_mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return m


static func _make_particle_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.albedo_color = col
	return m


static func _build_soft_dot_tex(col: Color, bright_core: bool) -> ImageTexture:
	var sz: int = 16
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c: float = (sz - 1) * 0.5
	for y in range(sz):
		for x in range(sz):
			var d: float = Vector2(x - c, y - c).length() / c
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			var px: Color = col
			if bright_core and d < 0.35:
				px = Color(1.0, 1.0, 0.95, 1.0)
			px.a = col.a * a
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)


static func _build_bullet_hole_tex(kind: int) -> ImageTexture:
	# kind: 0=concrete, 1=metal, 2=wood, 3=glass
	var sz: int = 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c: float = (sz - 1) * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + kind * 137
	for y in range(sz):
		for x in range(sz):
			var dx: float = x - c
			var dy: float = y - c
			var ang: float = atan2(dy, dx)
			var jag: float = sin(ang * 5.0 + float(kind)) * 0.08 + cos(ang * 9.0) * 0.06
			var d: float = sqrt(dx * dx + dy * dy) / c + jag
			var col := Color(0, 0, 0, 0)
			if kind == 3:
				# Glass fracture: dark impact center + white spiderweb radial cracks
				var ray: float = absf(sin(ang * 7.0))
				if d < 0.24:
					col = Color(0.88, 0.95, 1.0, 0.92)
				elif d < 0.92 and ray < 0.14:
					col = Color(0.82, 0.92, 0.98, (1.0 - d) * 0.85)
				elif d < 0.52:
					col = Color(0.75, 0.88, 0.95, (0.52 - d) * 0.9)
			elif d < 0.30:
				# Deep dark bullet entry hole
				col = Color(0.05, 0.05, 0.06, 0.96)
			elif d < 0.62:
				# Material-specific rim crater (bright brushed steel on metal, warm splinter on wood, grey chip on stone)
				var t: float = 1.0 - (d - 0.30) / 0.32
				if kind == 1:
					col = Color(0.68, 0.72, 0.76, t * 0.88)
				elif kind == 2:
					col = Color(0.46, 0.30, 0.16, t * 0.85)
				else:
					col = Color(0.26, 0.25, 0.24, t * 0.82)
			elif d < 0.85 and rng.randf() < 0.25:
				col = Color(0.16, 0.16, 0.16, (0.85 - d) * 1.4)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func _build_blood_splatter_tex() -> ImageTexture:
	var sz: int = 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c: float = (sz - 1) * 0.5
	for y in range(sz):
		for x in range(sz):
			var dx: float = x - c
			var dy: float = y - c
			var ang: float = atan2(dy, dx)
			var lobes: float = sin(ang * 4.0 + 0.7) * 0.16 + cos(ang * 7.0 - 1.2) * 0.12 + sin(ang * 11.0) * 0.07
			var d: float = sqrt(dx * dx + dy * dy) / c - lobes
			if d < 0.68:
				var shade: float = lerpf(0.32, 0.58, clampf(d / 0.68, 0.0, 1.0))
				var alpha: float = clampf((0.68 - d) * 2.6, 0.0, 0.90)
				img.set_pixel(x, y, Color(shade, 0.02, 0.02, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


static func _build_blood_mist_tex() -> ImageTexture:
	var sz: int = 24
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var c: float = (sz - 1) * 0.5
	for y in range(sz):
		for x in range(sz):
			var dx: float = x - c
			var dy: float = y - c
			var ang: float = atan2(dy, dx)
			var d: float = sqrt(dx * dx + dy * dy) / c + sin(ang * 5.0) * 0.08
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * 0.85))
	return ImageTexture.create_from_image(img)
