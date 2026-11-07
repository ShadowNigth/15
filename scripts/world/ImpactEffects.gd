class_name ImpactEffects
extends RefCounted
## Authentic Counter-Strike 1.5 combat & world effects:
##   - High-speed 3D crossed-fin bullet tracers & wallbang exit plumes
##   - Material-specific persistent bullet-hole decals (concrete, dirt/sand, metal, wood, glass)
##   - Multi-variant GoldSrc wall_puff1..4, fast_wallpuff1, rifle_smoke1..3, and pistol_smoke1..2 sprites
##   - Real 3D ballistic brass shell casings with wall/floor/crate bounces & clink foley
##   - Destructible func_breakable glass/wood/metal/stone shatter bursts & corpse blood pools

const MAX_DECALS: int = 112
const MAX_SHELLS: int = 36

static var _initialized: bool = false
static var _decal_ring: Array = []

static var _mat_decal_conc: StandardMaterial3D
static var _mat_decal_dirt: StandardMaterial3D
static var _mat_decal_metal: StandardMaterial3D
static var _mat_decal_wood: StandardMaterial3D
static var _mat_decal_glass: StandardMaterial3D
static var _mat_decal_blood: StandardMaterial3D
static var _mat_slash_conc: StandardMaterial3D
static var _mat_slash_metal: StandardMaterial3D
static var _mat_slash_wood: StandardMaterial3D
static var _mat_slash_dirt: StandardMaterial3D
static var _tex_impact_flash: ImageTexture

static var _mat_spark: StandardMaterial3D
static var _mat_chip_conc: StandardMaterial3D
static var _mat_chip_dirt: StandardMaterial3D
static var _mat_chip_wood: StandardMaterial3D
static var _mat_chip_glass: StandardMaterial3D
static var _mat_chip_metal: StandardMaterial3D
static var _mat_blood_drop: StandardMaterial3D
static var _mat_blood_mist: StandardMaterial3D
static var _mat_tracer: StandardMaterial3D

static var _quad_decal: QuadMesh
static var _quad_blood_decal: QuadMesh
static var _quad_slash: QuadMesh
static var _quad_spark: QuadMesh
static var _quad_drop: QuadMesh
static var _quad_shard_glass: QuadMesh
static var _quad_splinter_wood: QuadMesh
static var _mesh_tracer: ArrayMesh

static var _wall_puff_sets: Array = []   # Array of Array[Texture2D]
static var _rifle_smoke_sets: Array = [] # Array of Array[Texture2D]
static var _pistol_smoke_sets: Array = []


class ShellRunner extends Node3D:
	var _entries: Array = []

	func clear_all() -> void:
		for item in _entries:
			var d := item as Dictionary
			var nd_v: Variant = d.get("node", null)
			if is_instance_valid(nd_v):
				var nd := nd_v as Node3D
				if nd != null:
					if nd.get_parent() != null:
						nd.get_parent().remove_child(nd)
					nd.queue_free()
		_entries.clear()

	func add_shell(
		shell_node: Node3D,
		start_pos: Vector3,
		init_vel: Vector3,
		ang_vel: Vector3,
		delay_sec: float
	) -> void:
		while _entries.size() >= MAX_SHELLS:
			var oldest := _entries.pop_front() as Dictionary
			var old_v: Variant = oldest.get("node", null)
			if is_instance_valid(old_v):
				var old_n := old_v as Node3D
				if old_n != null:
					if old_n.get_parent() != null:
						old_n.get_parent().remove_child(old_n)
					old_n.queue_free()

		add_child(shell_node)
		shell_node.global_position = start_pos
		shell_node.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		shell_node.visible = (delay_sec <= 0.0)
		_entries.append({
			"node": shell_node,
			"vel": init_vel,
			"ang": ang_vel,
			"delay": delay_sec,
			"life": 3.4,
			"bounces": 0,
			"settled": false,
			"casing_sound": "native/sccsgoknives/casing_shotgun.wav" if (shell_node.name.to_lower().contains("rshell_big") or shell_node.name.contains("nova") or shell_node.name.contains("xm1014") or shell_node.name.contains("mag7")) else "native/sccsgoknives/casing_metal.wav",
		})
		set_physics_process(true)

	func _physics_process(delta: float) -> void:
		if _entries.is_empty():
			set_physics_process(false)
			return

		var w3d := get_world_3d()
		var space: PhysicsDirectSpaceState3D = w3d.direct_space_state if w3d != null else null
		var idx: int = _entries.size() - 1
		while idx >= 0:
			var d := _entries[idx] as Dictionary
			var nd_v: Variant = d.get("node", null)
			if not is_instance_valid(nd_v):
				_entries.remove_at(idx)
				idx -= 1
				continue
			var nd := nd_v as Node3D

			var delay_t: float = float(d["delay"])
			if delay_t > 0.0:
				delay_t -= delta
				d["delay"] = delay_t
				if delay_t <= 0.0:
					nd.visible = true
				idx -= 1
				continue

			var life_t: float = float(d["life"]) - delta
			d["life"] = life_t
			if life_t <= 0.0:
				if nd.get_parent() != null:
					nd.get_parent().remove_child(nd)
				nd.queue_free()
				_entries.remove_at(idx)
				idx -= 1
				continue

			if life_t < 0.35:
				var shrink: float = clampf(life_t / 0.35, 0.05, 1.0)
				nd.scale = Vector3.ONE * shrink

			var settled: bool = bool(d["settled"])
			if not settled and space != null:
				var vel: Vector3 = d["vel"]
				var ang: Vector3 = d["ang"]
				vel.y -= 19.8 * delta
				var cur_p: Vector3 = nd.global_position
				var step_v: Vector3 = vel * delta
				if step_v.length_squared() > 0.000004:
					var q := PhysicsRayQueryParameters3D.create(cur_p, cur_p + step_v + step_v.normalized() * 0.03)
					q.collision_mask = 1
					var hit: Dictionary = space.intersect_ray(q)
					if not hit.is_empty():
						var nrm: Vector3 = hit["normal"]
						var hpos: Vector3 = hit["position"]
						var imp: float = absf(vel.dot(nrm))
						nd.global_position = hpos + nrm * 0.018
						if nrm.y > 0.62:
							vel = vel.bounce(nrm)
							vel.y *= 0.42
							vel.x *= 0.68
							vel.z *= 0.68
							ang *= 0.56
						else:
							vel = vel.bounce(nrm) * 0.55
							ang = -ang * 0.65

						var bcnt: int = int(d["bounces"])
						if imp > 1.05 and bcnt < 3:
							d["bounces"] = bcnt + 1
							var vol_db: float = lerpf(-13.5, -7.8, clampf(imp / 5.5, 0.0, 1.0))
							AudioManager.play_3d(
								String(d.get("casing_sound", "native/sccsgoknives/casing_metal.wav")),
								nd.global_position,
								vol_db,
								13.5,
								randf_range(0.94, 1.10)
							)
						if nrm.y > 0.70 and vel.length_squared() < 0.16:
							vel = Vector3.ZERO
							ang = Vector3.ZERO
							nd.rotation.x = 0.0
							nd.rotation.z = 0.0
							d["settled"] = true
					else:
						nd.global_position = cur_p + step_v

				if not bool(d["settled"]):
					nd.rotation += ang * delta
				d["vel"] = vel
				d["ang"] = ang

			idx -= 1


static func _load_sprite_strip(prefix: String, max_frames: int = 8) -> Array[Texture2D]:
	var arr: Array[Texture2D] = []
	var base_p: String = "res://assets/sprites/%s.png" % prefix
	if ResourceLoader.exists(base_p):
		var t0 := load(base_p) as Texture2D
		if t0 != null:
			arr.append(t0)
	for fi in range(1, max_frames + 1):
		var fp: String = "res://assets/sprites/%s_%d.png" % [prefix, fi]
		if ResourceLoader.exists(fp):
			var tf := load(fp) as Texture2D
			if tf != null:
				arr.append(tf)
	return arr


static func ensure_init() -> void:
	if _initialized:
		return
	_initialized = true

	for wp in ["wall_puff1", "wall_puff2", "wall_puff3", "wall_puff4", "fast_wallpuff1"]:
		var strip := _load_sprite_strip(wp, 8)
		if not strip.is_empty():
			_wall_puff_sets.append(strip)

	for rs in ["rifle_smoke1", "rifle_smoke2", "rifle_smoke3"]:
		var rstrip := _load_sprite_strip(rs, 8)
		if not rstrip.is_empty():
			_rifle_smoke_sets.append(rstrip)

	for ps in ["pistol_smoke1", "pistol_smoke2"]:
		var pstrip := _load_sprite_strip(ps, 8)
		if not pstrip.is_empty():
			_pistol_smoke_sets.append(pstrip)

	_mat_decal_conc = _make_decal_mat(_build_bullet_hole_tex(0))
	_mat_decal_metal = _make_decal_mat(_build_bullet_hole_tex(1))
	_mat_decal_wood = _make_decal_mat(_build_bullet_hole_tex(2))
	_mat_decal_glass = _make_decal_mat(_build_bullet_hole_tex(3))
	_mat_decal_dirt = _make_decal_mat(_build_bullet_hole_tex(4))
	_mat_decal_blood = _make_decal_mat(_build_blood_splatter_tex())
	var slash_tex := _build_slash_tex()
	_mat_slash_conc = _make_decal_mat(slash_tex)
	_mat_slash_conc.albedo_color = Color(0.88, 0.88, 0.90)
	_mat_slash_metal = _make_decal_mat(slash_tex)
	_mat_slash_metal.albedo_color = Color(1.0, 0.98, 0.90)
	_mat_slash_wood = _make_decal_mat(slash_tex)
	_mat_slash_wood.albedo_color = Color(0.95, 0.85, 0.66)
	_mat_slash_dirt = _make_decal_mat(slash_tex)
	_mat_slash_dirt.albedo_color = Color(0.90, 0.82, 0.62)
	_tex_impact_flash = _build_soft_dot_tex(Color(1.0, 0.97, 0.86, 1.0), true)

	_quad_decal = QuadMesh.new()
	_quad_decal.size = Vector2(0.11, 0.11)
	_quad_blood_decal = QuadMesh.new()
	_quad_blood_decal.size = Vector2(0.46, 0.46)
	_quad_slash = QuadMesh.new()
	_quad_slash.size = Vector2(0.36, 0.11)

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
	_quad_spark.size = Vector2(0.058, 0.058)
	_quad_spark.material = _mat_spark

	# Concrete / Dirt / Wood / Glass / Metal chip materials
	_mat_chip_conc = _make_particle_mat(Color(0.62, 0.60, 0.56, 0.95), true)
	_mat_chip_dirt = _make_particle_mat(Color(0.76, 0.66, 0.48, 0.92), true)
	_mat_chip_wood = _make_particle_mat(Color(0.64, 0.45, 0.25, 0.96), false)
	_mat_chip_glass = _make_particle_mat(Color(0.78, 0.94, 1.0, 0.86), false)
	_mat_chip_metal = _make_particle_mat(Color(0.56, 0.60, 0.65, 0.96), false)

	_quad_shard_glass = QuadMesh.new()
	_quad_shard_glass.size = Vector2(0.095, 0.065)
	_quad_shard_glass.material = _mat_chip_glass

	_quad_splinter_wood = QuadMesh.new()
	_quad_splinter_wood.size = Vector2(0.135, 0.038)
	_quad_splinter_wood.material = _mat_chip_wood

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
	_mat_tracer.albedo_color = Color(1.0, 0.86, 0.44, 0.85)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = 0.015
	st.add_vertex(Vector3(-hw, 0.0, 0.0))
	st.add_vertex(Vector3(hw, 0.0, 0.0))
	st.add_vertex(Vector3(hw * 0.35, 0.0, -1.0))
	st.add_vertex(Vector3(-hw, 0.0, 0.0))
	st.add_vertex(Vector3(hw * 0.35, 0.0, -1.0))
	st.add_vertex(Vector3(-hw * 0.35, 0.0, -1.0))
	st.add_vertex(Vector3(0.0, -hw, 0.0))
	st.add_vertex(Vector3(0.0, hw, 0.0))
	st.add_vertex(Vector3(0.0, hw * 0.35, -1.0))
	st.add_vertex(Vector3(0.0, -hw, 0.0))
	st.add_vertex(Vector3(0.0, hw * 0.35, -1.0))
	st.add_vertex(Vector3(0.0, -hw * 0.35, -1.0))
	_mesh_tracer = st.commit()


static func clear_decals() -> void:
	for d_var in _decal_ring:
		if is_instance_valid(d_var):
			var d_node := d_var as Node3D
			if d_node != null:
				if d_node.get_parent() != null:
					d_node.get_parent().remove_child(d_node)
				d_node.queue_free()
	_decal_ring.clear()
	if is_instance_valid(RoundManager.game_world):
		var sr := RoundManager.game_world.get_node_or_null("__ShellRunner") as ShellRunner
		if sr != null:
			sr.clear_all()


static func spawn_physical_shell(
	world_root: Node3D,
	shell_mdl: String,
	start_pos: Vector3,
	eject_vel: Vector3,
	delay_sec: float = 0.0
) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	var sc := GameData.get_model_scene(shell_mdl if shell_mdl.begins_with("native/") else "weapons/" + shell_mdl)
	if sc == null:
		return
	var sr := world_root.get_node_or_null("__ShellRunner") as ShellRunner
	if sr == null:
		sr = ShellRunner.new()
		sr.name = "__ShellRunner"
		world_root.add_child(sr)
	var shell := sc.instantiate() as Node3D
	shell.name = shell_mdl.get_file()
	for c in shell.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ang_v := Vector3(randf_range(-24.0, 24.0), randf_range(-28.0, 28.0), randf_range(-22.0, 22.0))
	sr.add_shell(shell, start_pos, eject_vel, ang_v, delay_sec)


static func spawn_barrel_smoke(
	parent_node: Node3D,
	local_pos: Vector3,
	is_rifle: bool,
	layer_mask: int = 4,
	use_world_pos: bool = false
) -> void:
	if parent_node == null or not is_instance_valid(parent_node):
		return
	ensure_init()
	var pool: Array = _rifle_smoke_sets if is_rifle else _pistol_smoke_sets
	if pool.is_empty():
		pool = _wall_puff_sets
	if pool.is_empty():
		return
	var frames: Array = pool[randi() % pool.size()]
	if frames.is_empty():
		return

	var sp := Sprite3D.new()
	sp.layers = layer_mask
	sp.texture = frames[0] as Texture2D
	sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sp.shaded = false
	var base_px: float = (0.0021 if layer_mask == 4 else 0.0038) * (1.22 if is_rifle else 0.92)
	sp.pixel_size = base_px
	sp.modulate = Color(0.84, 0.85, 0.88, 0.42 if is_rifle else 0.34)
	parent_node.add_child(sp)
	if use_world_pos:
		sp.global_position = local_pos
	else:
		sp.position = local_pos

	var dur: float = 0.32 if is_rifle else 0.25
	var drift := Vector3(randf_range(-0.025, 0.035), 0.14 if layer_mask == 4 else 0.28, -0.04 if layer_mask == 4 else 0.0)
	var tw := parent_node.create_tween()
	tw.set_parallel(true)
	if use_world_pos:
		tw.tween_property(sp, "global_position", local_pos + drift, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(sp, "position", local_pos + drift, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "pixel_size", base_px * 2.15, dur)
	tw.tween_property(sp, "modulate:a", 0.0, dur)
	var fcnt: int = frames.size()
	for fi in range(1, fcnt):
		var tex_f: Texture2D = frames[fi] as Texture2D
		tw.tween_callback(_set_sprite_tex.bind(sp, tex_f)).set_delay((dur * 0.92) * float(fi) / float(fcnt))
	tw.chain().tween_callback(_safe_retire_node.bind(sp))


static func spawn_bullet_tracer(world_root: Node3D, from_pos: Vector3, to_pos: Vector3, is_heavy: bool = false) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	ensure_init()
	var span: Vector3 = to_pos - from_pos
	var total_len: float = span.length()
	if total_len < 1.5:
		return
	var dir: Vector3 = span / total_len
	var bolt_len: float = clampf(total_len * 0.34, 1.5, 5.2) if not is_heavy else clampf(total_len * 0.50, 2.4, 8.0)
	var start_p: Vector3 = from_pos + dir * 0.58
	var end_p: Vector3 = to_pos - dir * minf(0.35, total_len * 0.14)

	var mi := MeshInstance3D.new()
	mi.mesh = _mesh_tracer
	mi.material_override = _mat_tracer
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(mi)
	mi.global_position = start_p
	var up_ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.96 else Vector3.RIGHT
	mi.look_at(start_p + dir, up_ref)
	var w_scale: float = 1.50 if is_heavy else 1.0
	mi.scale = Vector3(w_scale, w_scale, bolt_len)

	var dur: float = clampf(total_len / 255.0, 0.026, 0.062)
	var tw := world_root.create_tween()
	tw.tween_property(mi, "global_position", end_p, dur)
	tw.tween_callback(_safe_retire_node.bind(mi))


static func spawn_taser_arc(world_root: Node3D, from_pos: Vector3, to_pos: Vector3) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	var span := to_pos - from_pos
	if span.length() < 0.15:
		return
	var side := span.normalized().cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := span.normalized().cross(side).normalized()
	var points: Array[Vector3] = []
	for i in range(10):
		var ratio := float(i) / 9.0
		var jitter := Vector3.ZERO if i == 0 or i == 9 else (side * randf_range(-0.09, 0.09) + up * randf_range(-0.07, 0.07)) * sin(ratio * PI)
		points.append(from_pos.lerp(to_pos, ratio) + jitter)
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(points.size() - 1):
		immediate.surface_set_color(Color(0.32, 0.82, 1.0, 1.0))
		immediate.surface_add_vertex(points[i])
		immediate.surface_add_vertex(points[i + 1])
	immediate.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var arc := MeshInstance3D.new()
	arc.mesh = immediate
	arc.material_override = material
	arc.layers = 2
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world_root.add_child(arc)
	var light := OmniLight3D.new()
	light.light_color = Color(0.20, 0.65, 1.0)
	light.light_energy = 2.0
	light.omni_range = 2.8
	world_root.add_child(light)
	light.global_position = from_pos.lerp(to_pos, 0.35)
	var tween := world_root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(light, "light_energy", 0.0, 0.13)
	tween.tween_interval(0.13)
	tween.chain().tween_callback(_safe_retire_node.bind(arc))
	tween.chain().tween_callback(_safe_retire_node.bind(light))


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

	# 0. Hot impact flash — a quick white burst frame on EVERY surface so hits
	#    read instantly, plus a soft radial glow scale-up that burns out fast
	var flash := Sprite3D.new()
	flash.texture = _tex_impact_flash
	flash.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flash.shaded = false
	flash.pixel_size = 0.0060 * caliber_scale
	flash.modulate = Color(1.0, 0.97, 0.88, 0.95)
	world_root.add_child(flash)
	flash.global_position = hit_pos + nrm * 0.045
	var tw_f := world_root.create_tween()
	tw_f.set_parallel(true)
	tw_f.tween_property(flash, "pixel_size", 0.017 * caliber_scale, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw_f.tween_property(flash, "modulate:a", 0.0, 0.10)
	tw_f.chain().tween_callback(_safe_retire_node.bind(flash))

	# Rifle-class hits: a brief hot flash light for extra punch (pistols skip it)
	if caliber_scale >= 1.12:
		var fl2 := OmniLight3D.new()
		fl2.light_color = Color(1.0, 0.82, 0.55)
		fl2.light_energy = 1.15
		fl2.omni_range = 2.4
		world_root.add_child(fl2)
		fl2.global_position = hit_pos + nrm * 0.10
		var tw_fl2 := world_root.create_tween()
		tw_fl2.tween_callback(_safe_retire_node.bind(fl2)).set_delay(0.075)

	# 1. Persistent surface bullet-hole decal (attached to moving door/breakable if hit!)
	var decal_mat: StandardMaterial3D = _mat_decal_conc
	var hole_sz: float = 0.105 * caliber_scale
	match mat_char:
		"M", "V", "L", "G":
			decal_mat = _mat_decal_metal
			hole_sz = 0.088 * caliber_scale
		"W":
			decal_mat = _mat_decal_wood
			hole_sz = 0.110 * caliber_scale
		"Y":
			decal_mat = _mat_decal_glass
			hole_sz = 0.170 * caliber_scale
		"D":
			decal_mat = _mat_decal_dirt
			hole_sz = 0.125 * caliber_scale

	var d_parent: Node3D = attach_parent if (attach_parent != null and is_instance_valid(attach_parent)) else world_root
	if mat_char not in ["L", "G"] and not (attach_parent is DroppedWeapon):
		_place_decal(d_parent, hit_pos + nrm * 0.008, nrm, _quad_decal, decal_mat, hole_sz / 0.11)

	# 2. Authentic CS 1.5 multi-variant animated wall_puff / sand plume
	if not _wall_puff_sets.is_empty():
		var pframes: Array = _wall_puff_sets[randi() % _wall_puff_sets.size()]
		var puff := Sprite3D.new()
		puff.texture = pframes[0] as Texture2D
		puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		puff.shaded = false
		var px_mult: float = 1.25 if mat_char == "D" else 1.0
		puff.pixel_size = 0.0054 * caliber_scale * px_mult
		if mat_char == "W":
			puff.modulate = Color(0.84, 0.72, 0.54, 0.74)
		elif mat_char == "D":
			puff.modulate = Color(0.88, 0.80, 0.62, 0.78)
		elif mat_char == "Y":
			puff.modulate = Color(0.88, 0.96, 1.0, 0.65)
		else:
			puff.modulate = Color(0.88, 0.86, 0.82, 0.70)
		world_root.add_child(puff)
		puff.global_position = hit_pos + nrm * 0.06
		var drift_end: Vector3 = puff.global_position + nrm * (0.74 if mat_char == "D" else 0.62) + Vector3(0.0, 0.44, 0.0)
		var pdur: float = 0.44 if mat_char == "D" else 0.36
		var tw_p := world_root.create_tween()
		tw_p.set_parallel(true)
		tw_p.tween_property(puff, "global_position", drift_end, pdur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_p.tween_property(puff, "pixel_size", 0.0138 * caliber_scale * px_mult, pdur)
		tw_p.tween_property(puff, "modulate:a", 0.0, pdur)
		var fcnt: int = pframes.size()
		for fi in range(1, fcnt):
			var tex_f: Texture2D = pframes[fi] as Texture2D
			tw_p.tween_callback(_set_sprite_tex.bind(puff, tex_f)).set_delay((pdur * 0.92) * float(fi) / float(fcnt))
		tw_p.chain().tween_callback(_safe_retire_node.bind(puff))

	# 3. Ricochet Sparks (Metal/Doors/Ladders/Vents/Grates or grazing stone hits) & Surface Chips
	var is_metallic: bool = mat_char in ["M", "V", "L", "G"]
	var grazing_ric: bool = (not is_metallic and mat_char in ["C", "T"] and absf(bullet_dir.dot(nrm)) < 0.52 and randf() < 0.48)
	if is_metallic or grazing_ric:
		var refl: Vector3 = bullet_dir.bounce(nrm).normalized()
		var sparks := CPUParticles3D.new()
		sparks.emitting = false
		sparks.one_shot = true
		sparks.explosiveness = 0.96
		sparks.amount = 14 if is_metallic else 8
		sparks.lifetime = 0.25
		sparks.mesh = _quad_spark
		sparks.direction = (refl * 0.65 + nrm * 0.35).normalized()
		sparks.spread = 36.0
		sparks.initial_velocity_min = 4.6
		sparks.initial_velocity_max = 10.4
		sparks.gravity = Vector3(0.0, -15.5, 0.0)
		sparks.scale_amount_min = 0.65
		sparks.scale_amount_max = 1.40
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.96, 0.72, 1.0))
		grad.set_color(1, Color(1.0, 0.40, 0.06, 0.0))
		sparks.color_ramp = grad
		world_root.add_child(sparks)
		sparks.global_position = hit_pos + nrm * 0.03
		sparks.emitting = true

		var fl := OmniLight3D.new()
		fl.light_color = Color(1.0, 0.74, 0.34)
		fl.light_energy = 1.45 if is_metallic else 0.90
		fl.omni_range = 2.6
		world_root.add_child(fl)
		fl.global_position = hit_pos + nrm * 0.08

		var tw_s := world_root.create_tween()
		tw_s.tween_callback(_safe_retire_node.bind(fl)).set_delay(0.05)
		tw_s.tween_callback(_safe_retire_node.bind(sparks)).set_delay(0.30)
	else:
		# Short ricochet sparkle on stone/dirt/wood too — not just metal
		var refl_s := bullet_dir.bounce(nrm).normalized()
		var sp2 := CPUParticles3D.new()
		sp2.emitting = false
		sp2.one_shot = true
		sp2.explosiveness = 0.95
		sp2.amount = 6
		sp2.lifetime = 0.17
		sp2.mesh = _quad_spark
		sp2.direction = (refl_s * 0.45 + nrm * 0.30 + Vector3.UP * 0.42).normalized()
		sp2.spread = 44.0
		sp2.initial_velocity_min = 2.8
		sp2.initial_velocity_max = 6.6
		sp2.gravity = Vector3(0.0, -15.5, 0.0)
		sp2.scale_amount_min = 0.5
		sp2.scale_amount_max = 1.1
		var grad_s := Gradient.new()
		grad_s.set_color(0, Color(1.0, 0.93, 0.62, 1.0))
		grad_s.set_color(1, Color(1.0, 0.45, 0.08, 0.0))
		sp2.color_ramp = grad_s
		world_root.add_child(sp2)
		sp2.global_position = hit_pos + nrm * 0.03
		sp2.emitting = true
		var tw_sp2 := world_root.create_tween()
		tw_sp2.tween_callback(_safe_retire_node.bind(sp2)).set_delay(0.24)

		var chips := CPUParticles3D.new()
		chips.emitting = false
		chips.one_shot = true
		chips.explosiveness = 0.95
		chips.amount = 14 if mat_char in ["W", "D", "Y"] else 11
		chips.lifetime = 0.38
		var c_mesh := QuadMesh.new()
		c_mesh.size = Vector2(0.052, 0.028) if mat_char == "W" else Vector2(0.038, 0.038)
		if mat_char == "W":
			c_mesh.material = _mat_chip_wood
		elif mat_char == "Y":
			c_mesh.material = _mat_chip_glass
		elif mat_char == "D":
			c_mesh.material = _mat_chip_dirt
		else:
			c_mesh.material = _mat_chip_conc
		chips.mesh = c_mesh
		chips.direction = (nrm + Vector3(0.0, 0.38, 0.0)).normalized()
		chips.spread = 46.0
		chips.initial_velocity_min = 2.2
		chips.initial_velocity_max = 5.8
		chips.gravity = Vector3(0.0, -15.5, 0.0)
		world_root.add_child(chips)
		chips.global_position = hit_pos + nrm * 0.03
		chips.emitting = true
		var tw_c := world_root.create_tween()
		tw_c.tween_callback(_safe_retire_node.bind(chips)).set_delay(0.44)


static func spawn_breakable_shatter(
	world_root: Node3D,
	box_aabb: AABB,
	hit_pos: Vector3,
	material_type: int
) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	ensure_init()

	var center: Vector3 = box_aabb.get_center() if box_aabb.size.length_squared() > 0.01 else hit_pos
	var half_ext: Vector3 = (box_aabb.size * 0.45).clamp(Vector3(0.15, 0.15, 0.15), Vector3(2.8, 2.8, 2.8))

	# 1. Volumetric shard / splinter / shrapnel burst across the brush volume!
	var burst := CPUParticles3D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 0.96
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	burst.emission_box_extents = half_ext

	if material_type in [0, 7]:  # Glass
		burst.amount = 34
		burst.lifetime = 0.85
		burst.mesh = _quad_shard_glass
	elif material_type == 1:  # Wood crate / panel
		burst.amount = 28
		burst.lifetime = 0.90
		burst.mesh = _quad_splinter_wood
	elif material_type in [2, 6]:  # Metal vent / computer
		burst.amount = 22
		burst.lifetime = 0.78
		var m_quad := QuadMesh.new()
		m_quad.size = Vector2(0.09, 0.06)
		m_quad.material = _mat_chip_metal
		burst.mesh = m_quad
	else:  # Concrete / Tile / Rock
		burst.amount = 24
		burst.lifetime = 0.82
		var s_quad := QuadMesh.new()
		s_quad.size = Vector2(0.075, 0.075)
		s_quad.material = _mat_chip_conc
		burst.mesh = s_quad

	var out_dir: Vector3 = (center - hit_pos)
	if out_dir.length_squared() < 0.01:
		out_dir = Vector3.UP
	else:
		out_dir = (out_dir.normalized() * 0.65 + Vector3.UP * 0.35).normalized()

	burst.direction = out_dir
	burst.spread = 86.0
	burst.initial_velocity_min = 2.6
	burst.initial_velocity_max = 7.8
	burst.gravity = Vector3(0.0, -17.5, 0.0)
	burst.angular_velocity_min = -360.0
	burst.angular_velocity_max = 360.0
	burst.scale_amount_min = 0.75
	burst.scale_amount_max = 1.65
	world_root.add_child(burst)
	burst.global_position = center
	burst.emitting = true

	var tw_b := world_root.create_tween()
	tw_b.tween_callback(_safe_retire_node.bind(burst)).set_delay(1.0)

	# 2. Spawn 3D tumbling shrapnel chunks for metal/wood/crate breakables + spark flash on metal!
	if material_type in [1, 2, 6]:
		var shrap_sc := GameData.get_model_scene("props/shrapnel")
		if shrap_sc != null:
			for ci in range(4):
				var chunk := shrap_sc.instantiate() as Node3D
				for mnode in chunk.find_children("*", "MeshInstance3D", true, false):
					(mnode as MeshInstance3D).layers = 2
				world_root.add_child(chunk)
				var ofs := Vector3(
					randf_range(-half_ext.x, half_ext.x) * 0.5,
					randf_range(-half_ext.y, half_ext.y) * 0.5,
					randf_range(-half_ext.z, half_ext.z) * 0.5
				)
				var sp_start: Vector3 = center + ofs
				chunk.global_position = sp_start
				chunk.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
				var end_c: Vector3 = sp_start + Vector3(randf_range(-2.2, 2.2), randf_range(-1.4, -0.3), randf_range(-2.2, 2.2))
				var tw_ch := world_root.create_tween()
				tw_ch.set_parallel(true)
				tw_ch.tween_property(chunk, "global_position", end_c, 0.52).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw_ch.tween_property(chunk, "rotation", chunk.rotation + Vector3(7.0, 9.0, 5.0), 0.52)
				tw_ch.tween_property(chunk, "scale", Vector3.ONE * 0.05, 0.52).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
				tw_ch.chain().tween_callback(_safe_retire_node.bind(chunk))

		if material_type in [2, 6]:
			var m_sparks := CPUParticles3D.new()
			m_sparks.emitting = false
			m_sparks.one_shot = true
			m_sparks.explosiveness = 0.96
			m_sparks.amount = 18
			m_sparks.lifetime = 0.30
			m_sparks.mesh = _quad_spark
			m_sparks.spread = 110.0
			m_sparks.initial_velocity_min = 4.0
			m_sparks.initial_velocity_max = 9.5
			m_sparks.gravity = Vector3(0.0, -15.0, 0.0)
			world_root.add_child(m_sparks)
			m_sparks.global_position = center
			m_sparks.emitting = true
			var tw_ms := world_root.create_tween()
			tw_ms.tween_callback(_safe_retire_node.bind(m_sparks)).set_delay(0.36)

	# 3. Billowing dust / vapor puff at breakable center
	if not _wall_puff_sets.is_empty():
		var pf: Array = _wall_puff_sets[0]
		var dust := Sprite3D.new()
		dust.texture = pf[0] as Texture2D
		dust.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dust.shaded = false
		dust.pixel_size = 0.015
		dust.modulate = Color(0.86, 0.95, 1.0, 0.52) if material_type in [0, 7] else Color(0.82, 0.74, 0.60, 0.68)
		world_root.add_child(dust)
		dust.global_position = center
		var tw_d := world_root.create_tween()
		tw_d.set_parallel(true)
		tw_d.tween_property(dust, "pixel_size", 0.032, 0.42)
		tw_d.tween_property(dust, "modulate:a", 0.0, 0.42)
		tw_d.chain().tween_callback(_safe_retire_node.bind(dust))


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

	# 1. Volumetric crimson blood mist — three staggered expanding billboards
	#    plus a dense fine-spray cone so the hit reads as 3D volume, not a PNG
	var m_quad := QuadMesh.new()
	m_quad.size = Vector2(0.26 * b_scale, 0.26 * b_scale)
	for mi_i in range(3):
		var mist := MeshInstance3D.new()
		mist.mesh = m_quad
		mist.material_override = _mat_blood_mist
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world_root.add_child(mist)
		mist.global_position = hit_pos + bullet_dir * (0.07 * float(mi_i))
		var m_end: float = [1.9, 2.35, 2.8][mi_i]
		var tw_m := world_root.create_tween()
		tw_m.tween_interval(0.055 * float(mi_i))
		tw_m.set_parallel(true)
		tw_m.tween_property(mist, "scale", Vector3.ONE * m_end, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw_m.tween_property(mist, "global_position", hit_pos + bullet_dir * (0.24 + 0.13 * float(mi_i)) + Vector3(0.0, -0.09, 0.0), 0.32)
		tw_m.tween_property(mist, "transparency", 0.9, 0.32)
		tw_m.chain().tween_callback(_safe_retire_node.bind(mist))

	# 1b. Dense fine blood spray cone travelling along the bullet path
	var fine := CPUParticles3D.new()
	fine.emitting = false
	fine.one_shot = true
	fine.explosiveness = 1.0
	fine.amount = 26 if is_head else 18
	fine.lifetime = 0.24
	fine.mesh = _quad_drop
	fine.direction = bullet_dir.normalized()
	fine.spread = 36.0
	fine.initial_velocity_min = 3.4
	fine.initial_velocity_max = 7.6 * b_scale
	fine.gravity = Vector3(0.0, -11.0, 0.0)
	fine.scale_amount_min = 0.32
	fine.scale_amount_max = 0.85
	var fine_grad := Gradient.new()
	fine_grad.set_color(0, Color(0.78, 0.03, 0.03, 0.95))
	fine_grad.set_color(1, Color(0.42, 0.02, 0.02, 0.0))
	fine.color_ramp = fine_grad
	world_root.add_child(fine)
	fine.global_position = hit_pos + bullet_dir * 0.05
	fine.emitting = true
	var tw_fine := world_root.create_tween()
	tw_fine.tween_callback(_safe_retire_node.bind(fine)).set_delay(0.32)

	# 2. Gravity-arcing crimson blood droplets spray
	var drops := CPUParticles3D.new()
	drops.emitting = false
	drops.one_shot = true
	drops.explosiveness = 0.94
	drops.amount = 26 if is_head else 16
	drops.lifetime = 0.44
	drops.mesh = _quad_drop
	drops.direction = (bullet_dir * 0.55 + Vector3(0.0, 0.35, 0.0)).normalized()
	drops.spread = 50.0 if is_head else 40.0
	drops.initial_velocity_min = 1.9
	drops.initial_velocity_max = 5.0 * b_scale
	drops.gravity = Vector3(0.0, -13.8, 0.0)
	drops.scale_amount_min = 0.75
	drops.scale_amount_max = 1.48 * b_scale
	var b_grad := Gradient.new()
	b_grad.set_color(0, Color(0.86, 0.05, 0.05, 0.96))
	b_grad.set_color(1, Color(0.38, 0.02, 0.02, 0.0))
	drops.color_ramp = b_grad
	world_root.add_child(drops)
	drops.global_position = hit_pos
	drops.emitting = true

	var tw_d := world_root.create_tween()
	tw_d.tween_callback(_safe_retire_node.bind(drops)).set_delay(0.46)

	# 3. Kevlar helmet headshot spark flash ("dink" visual cue!)
	if is_head and armored_head:
		var h_sparks := CPUParticles3D.new()
		h_sparks.emitting = false
		h_sparks.one_shot = true
		h_sparks.explosiveness = 0.98
		h_sparks.amount = 12
		h_sparks.lifetime = 0.20
		h_sparks.mesh = _quad_spark
		h_sparks.direction = (-bullet_dir + Vector3(0.0, 0.5, 0.0)).normalized()
		h_sparks.spread = 54.0
		h_sparks.initial_velocity_min = 3.8
		h_sparks.initial_velocity_max = 8.2
		h_sparks.gravity = Vector3(0.0, -12.0, 0.0)
		world_root.add_child(h_sparks)
		h_sparks.global_position = hit_pos
		h_sparks.emitting = true
		var tw_hs := world_root.create_tween()
		tw_hs.tween_callback(_safe_retire_node.bind(h_sparks)).set_delay(0.26)

	# 4. Stamp crimson blood splatter decals on wall behind victim & floor beneath!
	if space != null:
		var q_wall := PhysicsRayQueryParameters3D.create(hit_pos, hit_pos + bullet_dir * 3.2)
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


static func spawn_death_blood_pool(world_root: Node3D, floor_pos: Vector3, floor_nrm: Vector3 = Vector3.UP) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	ensure_init()
	var nrm: Vector3 = floor_nrm.normalized() if floor_nrm.length_squared() > 0.001 else Vector3.UP
	var d_node: MeshInstance3D = _place_decal(world_root, floor_pos + nrm * 0.007, nrm, _quad_blood_decal, _mat_decal_blood, 0.25)
	if is_instance_valid(d_node):
		var tw := world_root.create_tween()
		tw.tween_property(d_node, "scale", Vector3.ONE * randf_range(1.45, 1.85), 1.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Places a surface decal. fixed_roll overrides the random spin (used by the
## knife slash to align cuts with the blade travel direction).
static func _place_decal(parent_node: Node3D, pos: Vector3, nrm: Vector3, qmesh: QuadMesh, mat: StandardMaterial3D, scl: float, fixed_roll: float = NAN) -> MeshInstance3D:
	if parent_node == null or not is_instance_valid(parent_node):
		return null
	for di in range(_decal_ring.size() - 1, -1, -1):
		if not is_instance_valid(_decal_ring[di]):
			_decal_ring.remove_at(di)
	while _decal_ring.size() >= MAX_DECALS:
		var old_v: Variant = _decal_ring.pop_front()
		if is_instance_valid(old_v):
			var old_d := old_v as Node3D
			if old_d != null:
				if old_d.get_parent() != null:
					old_d.get_parent().remove_child(old_d)
				old_d.queue_free()

	var mi := MeshInstance3D.new()
	mi.mesh = qmesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent_node.add_child(mi)
	mi.global_position = pos
	var up_ref: Vector3 = Vector3.UP if absf(nrm.dot(Vector3.UP)) < 0.96 else Vector3.RIGHT
	mi.look_at(pos - nrm, up_ref)
	mi.rotate_object_local(Vector3.FORWARD, randf() * TAU if is_nan(fixed_roll) else fixed_roll)
	mi.scale = Vector3.ONE * scl
	_decal_ring.append(mi)
	return mi


## Knife wall scrape: an elongated cut gouge oriented along the blade's travel
## (with random jitter, length and spin) instead of a bullet hole + bullet FX.
static func spawn_knife_slash(
	world_root: Node3D,
	hit_pos: Vector3,
	hit_nrm: Vector3,
	blade_dir: Vector3,
	mat_char: String,
	attach_parent: Node3D = null
) -> void:
	if world_root == null or not is_instance_valid(world_root):
		return
	ensure_init()
	var nrm: Vector3 = hit_nrm.normalized() if hit_nrm.length_squared() > 0.001 else Vector3.UP
	var slash_mat: StandardMaterial3D = _mat_slash_conc
	match mat_char:
		"M", "V", "L", "G", "Y":
			slash_mat = _mat_slash_metal
		"W":
			slash_mat = _mat_slash_wood
		"D":
			slash_mat = _mat_slash_dirt
	var d_parent: Node3D = attach_parent if (attach_parent != null and is_instance_valid(attach_parent)) else world_root
	var mi := _place_decal(d_parent, hit_pos + nrm * 0.009, nrm, _quad_slash, slash_mat, randf_range(0.78, 1.35), 0.0)
	if mi != null:
		var roll := randf() * TAU
		var tangent := blade_dir - nrm * blade_dir.dot(nrm)
		if tangent.length_squared() > 0.004:
			var local_t: Vector3 = mi.global_transform.basis.inverse() * tangent.normalized()
			roll = atan2(local_t.y, local_t.x) + randf_range(-0.42, 0.42)
		mi.rotate_object_local(Vector3.FORWARD, roll)

	# Small dust puff — the cut lands with a bit of life, no bullet-hole sparks
	var dust := CPUParticles3D.new()
	dust.emitting = false
	dust.one_shot = true
	dust.explosiveness = 1.0
	dust.amount = 5
	dust.lifetime = 0.26
	var dm := QuadMesh.new()
	dm.size = Vector2(0.030, 0.030)
	dm.material = _mat_chip_conc
	dust.mesh = dm
	dust.direction = (nrm + Vector3(0.0, 0.30, 0.0)).normalized()
	dust.spread = 52.0
	dust.initial_velocity_min = 1.2
	dust.initial_velocity_max = 3.0
	dust.gravity = Vector3(0.0, -14.0, 0.0)
	world_root.add_child(dust)
	dust.global_position = hit_pos + nrm * 0.03
	dust.emitting = true
	var tw_d := world_root.create_tween()
	tw_d.tween_callback(_safe_retire_node.bind(dust)).set_delay(0.32)


## Procedural slash gouge texture: one long tapered bright core with a darker
## lip plus a short secondary nick — reads as a blade cut at any rotation.
static func _build_slash_tex() -> ImageTexture:
	var w: int = 160
	var h: int = 48
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in range(w):
		var u := float(x) / float(w - 1)
		var yc := float(h) * 0.5 + sin(u * PI) * 6.0 - 3.0
		var taper := 1.0 - absf(u - 0.5) * 2.0
		var th := 1.0 + 5.4 * pow(taper, 0.65)
		for y in range(h):
			var d := absf(float(y) - yc)
			if d >= th:
				continue
			var t := 1.0 - d / th
			var a := t * t
			var core := clampf((t - 0.45) / 0.55, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.40, 0.40, 0.43, a).lerp(Color(1.0, 1.0, 1.0, a), core))
	for x in range(30, 78):
		var u2 := (float(x) - 30.0) / 47.0
		var yc2 := 12.0 + u2 * 7.0
		var th2 := 1.1 + 2.0 * maxf(0.0, 1.0 - absf(u2 - 0.5) * 2.0)
		for y in range(h):
			var d2 := absf(float(y) - yc2)
			if d2 < th2:
				var t2 := 1.0 - d2 / th2
				img.set_pixel(x, y, Color(0.72, 0.72, 0.76, t2 * 0.8))
	return ImageTexture.create_from_image(img)


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


static func _make_particle_mat(col: Color, billboard: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if billboard:
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
	# kind: 0=concrete, 1=metal, 2=wood, 3=glass, 4=dirt/sand
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
				var ray: float = absf(sin(ang * 7.0))
				if d < 0.24:
					col = Color(0.88, 0.95, 1.0, 0.92)
				elif d < 0.92 and ray < 0.14:
					col = Color(0.82, 0.92, 0.98, (1.0 - d) * 0.85)
				elif d < 0.52:
					col = Color(0.75, 0.88, 0.95, (0.52 - d) * 0.9)
			elif d < 0.30:
				col = Color(0.05, 0.05, 0.06, 0.96) if kind != 4 else Color(0.18, 0.14, 0.09, 0.92)
			elif d < 0.65:
				var t: float = 1.0 - (d - 0.30) / 0.35
				if kind == 1:
					col = Color(0.68, 0.72, 0.76, t * 0.88)
				elif kind == 2:
					col = Color(0.46, 0.30, 0.16, t * 0.85)
				elif kind == 4:
					col = Color(0.56, 0.46, 0.30, t * 0.80)
				else:
					col = Color(0.26, 0.25, 0.24, t * 0.82)
			elif d < 0.85 and rng.randf() < 0.25:
				col = Color(0.16, 0.16, 0.16, (0.85 - d) * 1.4)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Realistic blood splatter: irregular central mass (overlapping blobs), a ring
## of satellite droplets and a few directional spray streaks — replaces the old
##4-lobe starfish shape.
static func _build_blood_splatter_tex() -> ImageTexture:
	var sz: int = 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xB10D5EED
	var c: float = sz * 0.5
	var blobs: Array[Vector2] = []
	var blob_r: Array[float] = []
	for i in range(7):
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(0.0, sz * 0.13)
		blobs.append(Vector2(cos(ang), sin(ang)) * dist + Vector2(c, c))
		blob_r.append(rng.randf_range(sz * 0.10, sz * 0.19))
	for y in range(sz):
		for x in range(sz):
			var px: float = float(x)
			var py: float = float(y)
			var field: float = 0.0
			for i in range(blobs.size()):
				var dxb: float = px - blobs[i].x
				var dyb: float = py - blobs[i].y
				var dv: float = sqrt(dxb * dxb + dyb * dyb) / maxf(1.0, blob_r[i])
				field += maxf(0.0, 1.0 - dv)
			if field >= 1.0:
				var thick: float = clampf(field - 1.0, 0.0, 1.0)
				var shade: float = lerpf(0.44, 0.15, thick)
				var alpha: float = lerpf(0.70, 0.97, thick)
				img.set_pixel(x, y, Color(shade, 0.012, 0.012, alpha))
	# Satellite droplets + fine spray dots around the main mass
	for i in range(30):
		var ang2: float = rng.randf_range(0.0, TAU)
		var dist2: float = rng.randf_range(sz * 0.24, sz * 0.47)
		var dcx: float = c + cos(ang2) * dist2
		var dcy: float = c + sin(ang2) * dist2
		var rr: float = rng.randf_range(1.1, 4.0)
		for y in range(maxi(0, int(dcy - rr - 1)), mini(sz, int(dcy + rr + 2))):
			for x in range(maxi(0, int(dcx - rr - 1)), mini(sz, int(dcx + rr + 2))):
				var ddx: float = float(x) - dcx
				var ddy: float = float(y) - dcy
				var d: float = sqrt(ddx * ddx + ddy * ddy)
				if d <= rr:
					var t2: float = 1.0 - d / maxf(0.5, rr)
					img.set_pixel(x, y, Color(lerpf(0.50, 0.20, t2), 0.010, 0.010, t2 * 0.95))
	# Directional spray streaks
	for i in range(4):
		var sang: float = rng.randf_range(0.0, TAU)
		var sdir_x: float = cos(sang)
		var sdir_y: float = sin(sang)
		var slen: float = rng.randf_range(sz * 0.12, sz * 0.28)
		var sstart_d: float = rng.randf_range(sz * 0.10, sz * 0.15)
		var steps: int = int(slen)
		for si in range(steps):
			var ft: float = float(si) / float(maxi(1, steps))
			var sx: float = c + sdir_x * (sstart_d + float(si))
			var sy: float = c + sdir_y * (sstart_d + float(si))
			var sr: float = lerpf(2.8, 0.5, ft)
			for y in range(maxi(0, int(sy - sr - 1)), mini(sz, int(sy + sr + 2))):
				for x in range(maxi(0, int(sx - sr - 1)), mini(sz, int(sx + sr + 2))):
					var ssx: float = float(x) - sx
					var ssy: float = float(y) - sy
					var sd: float = sqrt(ssx * ssx + ssy * ssy)
					if sd <= sr:
						var st: float = 1.0 - sd / maxf(0.4, sr)
						img.set_pixel(x, y, Color(lerpf(0.46, 0.22, st), 0.010, 0.010, st * 0.9))
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
