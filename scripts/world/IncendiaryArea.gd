class_name IncendiaryArea
extends Node3D
## Independent procedural Molotov/incendiary simulation.
##
## Connected random-walk fuel branches are projected onto real floor geometry.
## Every throw owns its seed, envelope, branch lengths, flame meshes and particles.
## Damage follows ignited patches only; neither visuals nor damage cross cover.

const MAX_PATCHES: int = 68
const MOLOTOV_MIN_PATCHES: int = 30
const INCENDIARY_MAX_PATCHES: int = 44
const PATCH_RADIUS: float = 0.82
const SPREAD_STEP: float = 0.72
const SPREAD_INTERVAL: float = 0.052
const PATCHES_PER_STEP: int = 2
const WORLD_COLLISION_MASK: int = 1
const FLAME_SHADER: Shader = preload("res://assets/shaders/incendiary_flame.gdshader")
const HEAT_SHADER: Shader = preload("res://assets/shaders/incendiary_heat.gdshader")

static var _ember_texture: Texture2D = null

var thrower: Node3D = null
var area_type: String = "molotov"
## Maximum fuel travel, not an always-active damage sphere.
var radius: float = 3.25
var life_left: float = 7.0
var simulation_seed: int = 0
var target_patch_count: int = 1
var envelope_aspect: float = 1.0
var propagation_heading: float = 0.0

var _fire_audio: AudioStreamPlayer3D = null
var _audio_extinguished: bool = false
var _smoke_tick := 0.0
var _tick: float = 0.0
var _age: float = 0.0
var _visual_time: float = 0.0
var _spread_tick: float = 0.0
var _spread_interval: float = SPREAD_INTERVAL
var _patches_per_step: int = PATCHES_PER_STEP
var _current_radius: float = PATCH_RADIUS
var _initial_life: float = 7.0
var _branch_budget: int = 3
var _branch_arc: float = TAU
var _branches_started: int = 0
var _rng := RandomNumberGenerator.new()
var _patches: Array[Dictionary] = []
var _walkers: Array[Dictionary] = []
var _flames: Array[Dictionary] = []
var _heat: Array[Dictionary] = []
var _light: OmniLight3D = null
var _burst: GPUParticles3D = null
var _ember_particles: GPUParticles3D = null
var _smoke_particles: GPUParticles3D = null
var _burst_process: ParticleProcessMaterial = null
var _ember_process: ParticleProcessMaterial = null
var _smoke_process: ParticleProcessMaterial = null


func setup_fire(owner_actor: Node3D, kind: String, seed_override: int = 0) -> void:
	thrower = owner_actor
	area_type = kind
	_initial_life = 7.0 if kind == "molotov" else 8.0
	life_left = _initial_life
	if seed_override != 0:
		simulation_seed = seed_override
	else:
		_rng.randomize()
		simulation_seed = int(_rng.randi())
		if simulation_seed == 0:
			simulation_seed = 1
	_rng.seed = simulation_seed

	# These are independent simulation parameters, not a scale applied to a
	# prebuilt ring. Compact blobs, long branches and multi-arm fires emerge here.
	# Molotovs now cover a genuinely wider tactical area, not merely a scaled
	# visual ring. More fuel and longer irregular walker envelopes enlarge both
	# the rendered fire and the exact connected damage patches. The incendiary
	# retains its previous accepted profile.
	target_patch_count = (
		_rng.randi_range(MOLOTOV_MIN_PATCHES, MAX_PATCHES)
		if kind == "molotov"
		else _rng.randi_range(20, INCENDIARY_MAX_PATCHES)
	)
	var base_radius := 4.35 if kind == "molotov" else 3.10
	radius = base_radius * _rng.randf_range(0.72, 1.18)
	envelope_aspect = _rng.randf_range(0.48, 1.0)
	propagation_heading = _rng.randf_range(-PI, PI)
	_branch_budget = _rng.randi_range(3, 7) if kind == "molotov" else _rng.randi_range(2, 5)
	_branch_arc = _rng.randf_range(0.70, TAU)
	_spread_interval = (
		_rng.randf_range(0.042, 0.064)
		if kind == "molotov"
		else _rng.randf_range(0.046, 0.072)
	)
	_patches_per_step = _rng.randi_range(2, 4) if kind == "molotov" else _rng.randi_range(1, 3)
	_spread_tick = _rng.randf_range(0.12, 0.24)
	_tick = 0.08
	_ensure_textures()
	_snap_origin_to_floor()
	_add_patch(Vector3.ZERO, Vector3.ZERO)
	_create_light()
	_create_particle_systems()
	_refresh_particle_emission()
	RoundManager.register_incendiary(self)
	if is_instance_valid(_fire_audio):
		_fire_audio.queue_free()
	_audio_extinguished = false
	_fire_audio = AudioStreamPlayer3D.new()
	_fire_audio.stream = GameData.get_sound(AudioManager.cue_path("fire_loop"))
	_fire_audio.volume_db = -8.0 + GameData.master_volume_db + GameData.sound_gain_db(AudioManager.cue_path("fire_loop"))
	_fire_audio.max_distance = 30.0
	add_child(_fire_audio)
	_fire_audio.finished.connect(func():
		if life_left > 0.0 and is_instance_valid(_fire_audio):
			_fire_audio.play()
	)
	_fire_audio.play()


func _exit_tree() -> void:
	RoundManager.unregister_incendiary(self)


func navigation_danger_at(world_pos: Vector3) -> float:
	## Coarse, inexpensive cost used by bot A* only. Actual fire damage continues
	## to use the individual wall-tested patches below, never this radial estimate.
	if life_left <= 0.0 or _patches.is_empty() or not is_inside_tree():
		return 0.0
	var local_pos := to_local(world_pos)
	if absf(local_pos.y) > 2.2:
		return 0.0
	var distance := Vector2(local_pos.x, local_pos.z).length()
	return clampf((_current_radius + 0.85 - distance) / 1.25, 0.0, 1.0)


func _snap_origin_to_floor() -> void:
	if get_world_3d() == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.45, global_position - Vector3.UP * 1.1
	)
	query.collision_mask = WORLD_COLLISION_MASK
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if normal.y >= 0.55:
		var point: Vector3 = hit.get("position", global_position)
		global_position = point + normal * 0.018


static func _ensure_textures() -> void:
	if _ember_texture != null:
		return
	var ember_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var dx := (float(x) + 0.5 - 8.0) / 8.0
			var dy := (float(y) + 0.5 - 8.0) / 8.0
			var falloff := clampf(1.0 - Vector2(dx, dy).length(), 0.0, 1.0)
			ember_image.set_pixel(x, y, Color(1.0, 0.72, 0.26, falloff * falloff))
	ember_image.generate_mipmaps()
	_ember_texture = ImageTexture.create_from_image(ember_image)


static func _make_ramp(start: Color, middle: Color, end: Color) -> Texture2D:
	var image := Image.create(64, 1, false, Image.FORMAT_RGBA8)
	for x in range(64):
		var t := float(x) / 63.0
		var colour := (
			start.lerp(middle, t / 0.32) if t < 0.32 else middle.lerp(end, (t - 0.32) / 0.68)
		)
		image.set_pixel(x, 0, colour)
	return ImageTexture.create_from_image(image)


func _create_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = Color(1.0, 0.42, 0.075)
	_light.light_energy = 0.0
	_light.omni_range = 2.0
	_light.light_cull_mask = 3
	add_child(_light)
	_light.position = Vector3(0.0, 0.72, 0.0)


func _add_patch(local_pos: Vector3, parent_pos: Vector3) -> void:
	var patch_index := _patches.size()
	var patch_radius := PATCH_RADIUS * _rng.randf_range(0.76, 1.18)
	var fade_offset := _rng.randf_range(0.0, 0.72)
	var patch := {
		"pos": local_pos,
		"born": _age,
		"phase": _rng.randf_range(0.0, TAU),
		"radius": patch_radius,
		"fade_offset": fade_offset,
	}
	_patches.append(patch)
	_current_radius = maxf(
		_current_radius, Vector2(local_pos.x, local_pos.z).length() + patch_radius
	)

	var flame := MeshInstance3D.new()
	flame.name = "VolumetricFlame%02d" % patch_index
	var flame_mesh := _build_flame_mesh(local_pos, parent_pos, patch_radius, patch_index == 0)
	flame.custom_aabb = flame_mesh.get_aabb().grow(0.45)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = FLAME_SHADER
	material.render_priority = 4
	material.set_shader_parameter(
		"seed", float(simulation_seed % 4096) * 0.013 + float(patch_index) * 7.17 + _rng.randf()
	)
	material.set_shader_parameter("ignition", 0.0)
	material.set_shader_parameter("fade", 1.0)
	material.set_shader_parameter("height_fade", 1.0)
	material.set_shader_parameter("intensity", _rng.randf_range(0.88, 1.18))
	material.set_shader_parameter("motion_rate", _rng.randf_range(0.76, 1.34))
	flame.material_override = material
	add_child(flame)
	flame.position = local_pos
	flame.mesh = flame_mesh
	(
		_flames
		. append(
			{
				"node": flame,
				"material": material,
				"born": _age,
				"patch": patch,
				"ignition_span": _rng.randf_range(0.17, 0.34),
				"fade_offset": fade_offset,
				"phase": _rng.randf_range(0.0, TAU),
				"intensity": _rng.randf_range(0.90, 1.12),
			}
		)
	)

	# Sparse heat plumes distort only the air above connected fire zones.
	if patch_index % 4 == 0:
		var heat := MeshInstance3D.new()
		heat.name = "HeatPlume%02d" % patch_index
		var quad := QuadMesh.new()
		quad.size = Vector2(_rng.randf_range(1.05, 1.72), _rng.randf_range(1.0, 1.65))
		heat.mesh = quad
		var heat_height := _rng.randf_range(0.56, 0.86)
		heat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var heat_material := ShaderMaterial.new()
		heat_material.shader = HEAT_SHADER
		heat_material.render_priority = 6
		heat_material.set_shader_parameter("seed", _rng.randf_range(0.0, 90.0))
		heat_material.set_shader_parameter("ignition", 0.0)
		heat.material_override = heat_material
		add_child(heat)
		heat.position = local_pos + Vector3.UP * heat_height
		_heat.append(
			{"node": heat, "material": heat_material, "born": _age, "fade_offset": fade_offset, "patch": patch}
		)
	_refresh_particle_emission()


func _build_flame_mesh(
	local_pos: Vector3, parent_pos: Vector3, patch_radius: float, initial: bool
) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tongue_count := _rng.randi_range(2, 4) + (1 if initial else 0)
	var connector_count := 0 if initial else _rng.randi_range(1, 2)
	var size_factor := patch_radius / PATCH_RADIUS
	for tongue_index in range(tongue_count + connector_count):
		var connector := tongue_index >= tongue_count
		var root := Vector3.ZERO
		if connector:
			var t := _rng.randf_range(0.28, 0.76)
			root = (parent_pos - local_pos) * t
			root += Vector3(_rng.randf_range(-0.09, 0.09), 0.0, _rng.randf_range(-0.09, 0.09))
		else:
			root = Vector3(
				_rng.randf_range(-0.27, 0.27) * size_factor,
				0.0,
				_rng.randf_range(-0.27, 0.27) * size_factor
			)
		var height := _rng.randf_range(0.34, 0.94) * size_factor
		if initial:
			height *= 1.20
		if connector:
			height *= _rng.randf_range(0.50, 0.76)
		var width := _rng.randf_range(0.42, 0.78) * size_factor
		var angle := _rng.randf_range(0.0, TAU)
		var lean_angle := angle + _rng.randf_range(-1.2, 1.2)
		var lean := (
			Vector3(cos(lean_angle), 0.0, sin(lean_angle)) * height * _rng.randf_range(0.12, 0.38)
		)
		var phase := _rng.randf_range(0.0, TAU)
		for plane in range(2):
			var ribbon_angle := angle + float(plane) * PI * 0.5
			var right := Vector3(cos(ribbon_angle), 0.0, sin(ribbon_angle))
			_append_ribbon(surface, root, right, lean, height, width, 7, phase + float(plane))
	return surface.commit()


static func _append_ribbon(
	surface: SurfaceTool,
	root: Vector3,
	right: Vector3,
	lean: Vector3,
	height: float,
	width: float,
	segments: int,
	phase: float
) -> void:
	for segment in range(segments):
		var h0 := float(segment) / float(segments)
		var h1 := float(segment + 1) / float(segments)
		var curl0 := sin(phase + h0 * 6.2) * width * 0.16 * h0
		var curl1 := sin(phase + h1 * 6.2) * width * 0.16 * h1
		var centre0 := root + Vector3.UP * (height * h0) + lean * (h0 * h0) + right * curl0
		var centre1 := root + Vector3.UP * (height * h1) + lean * (h1 * h1) + right * curl1
		var billow0 := 0.94 + 0.18 * sin(phase + h0 * 8.0) + 0.08 * sin(phase * 1.7 + h0 * 17.0)
		var billow1 := 0.94 + 0.18 * sin(phase + h1 * 8.0) + 0.08 * sin(phase * 1.7 + h1 * 17.0)
		var width0 := width * maxf(0.025, pow(1.0 - h0, 0.52) * billow0)
		var width1 := width * maxf(0.025, pow(1.0 - h1, 0.52) * billow1)
		var v00 := centre0 - right * width0 * 0.5
		var v01 := centre0 + right * width0 * 0.5
		var v10 := centre1 - right * width1 * 0.5
		var v11 := centre1 + right * width1 * 0.5
		_mesh_vertex(surface, v00, Vector2(0.0, h0))
		_mesh_vertex(surface, v01, Vector2(1.0, h0))
		_mesh_vertex(surface, v11, Vector2(1.0, h1))
		_mesh_vertex(surface, v00, Vector2(0.0, h0))
		_mesh_vertex(surface, v11, Vector2(1.0, h1))
		_mesh_vertex(surface, v10, Vector2(0.0, h1))


static func _mesh_vertex(surface: SurfaceTool, point: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(point)


func _particle_mesh(
	texture: Texture2D, size: float, tint: Color, additive: bool = false
) -> QuadMesh:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.albedo_color = tint
	material.render_priority = 5
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = material
	return quad


func _new_gpu_particles(
	node_name: String, amount: int, lifetime: float, process: ParticleProcessMaterial, mesh: Mesh
) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.randomness = 0.72
	particles.local_coords = true
	particles.emitting = false
	particles.process_material = process
	particles.draw_passes = 1
	particles.draw_pass_1 = mesh
	particles.visibility_aabb = AABB(Vector3(-8.0, -1.0, -8.0), Vector3(16.0, 8.0, 16.0))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(particles)
	return particles


func _create_particle_systems() -> void:
	_burst_process = ParticleProcessMaterial.new()
	_burst_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_burst_process.emission_sphere_radius = 0.24
	_burst_process.direction = Vector3.UP
	_burst_process.spread = 74.0
	_burst_process.initial_velocity_min = 1.15
	_burst_process.initial_velocity_max = 2.85
	_burst_process.gravity = Vector3(0.0, -3.8, 0.0)
	_burst_process.damping_min = 1.1
	_burst_process.damping_max = 2.0
	_burst_process.scale_min = 0.48
	_burst_process.scale_max = 1.25
	_burst_process.color_ramp = _make_ramp(
		Color(1.0, 0.98, 0.68, 1.0), Color(1.0, 0.28, 0.015, 0.90), Color(0.35, 0.008, 0.001, 0.0)
	)
	_burst = _new_gpu_particles(
		"InitialFlameBurst",
		42,
		0.68,
		_burst_process,
		_particle_mesh(_ember_texture, 0.15, Color.WHITE, true)
	)
	_burst.one_shot = true
	_burst.explosiveness = 0.94
	_burst.emitting = true

	_ember_process = ParticleProcessMaterial.new()
	_ember_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_ember_process.emission_shape_offset = Vector3.UP * 0.24
	_ember_process.direction = Vector3.UP
	_ember_process.spread = 54.0
	_ember_process.initial_velocity_min = 0.58
	_ember_process.initial_velocity_max = 1.62
	_ember_process.gravity = Vector3(0.0, -0.78, 0.0)
	_ember_process.damping_min = 0.25
	_ember_process.damping_max = 0.68
	_ember_process.scale_min = 0.34
	_ember_process.scale_max = 1.0
	_ember_process.color_ramp = _make_ramp(
		Color(1.0, 0.94, 0.46, 1.0), Color(1.0, 0.31, 0.025, 0.82), Color(0.42, 0.012, 0.001, 0.0)
	)
	_ember_particles = _new_gpu_particles(
		"IncandescentEmbers",
		88,
		1.35,
		_ember_process,
		_particle_mesh(_ember_texture, 0.075, Color.WHITE, true)
	)
	_ember_particles.emitting = true

	_smoke_process = ParticleProcessMaterial.new()
	_smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_smoke_process.emission_shape_offset = Vector3.UP * 0.58
	_smoke_process.direction = Vector3.UP
	_smoke_process.spread = 24.0
	_smoke_process.initial_velocity_min = 0.22
	_smoke_process.initial_velocity_max = 0.52
	_smoke_process.gravity = Vector3(0.0, 0.045, 0.0)
	_smoke_process.damping_min = 0.10
	_smoke_process.damping_max = 0.32
	_smoke_process.scale_min = 0.52
	_smoke_process.scale_max = 1.35
	_smoke_process.color_ramp = _make_ramp(
		Color(0.22, 0.20, 0.18, 0.0), Color(0.26, 0.23, 0.20, 0.14), Color(0.18, 0.17, 0.16, 0.0)
	)
	_smoke_particles = _new_gpu_particles(
		"LightFireSmoke",
		30,
		3.35,
		_smoke_process,
		_particle_mesh(GameData.get_smoke_cloud_variant(0), 0.92, Color(0.42, 0.39, 0.35, 0.58))
	)
	_smoke_particles.emitting = true


func _refresh_particle_emission() -> void:
	if _ember_process == null or _smoke_process == null or _patches.is_empty():
		return
	var points_active: Array[Vector3] = []
	for patch in _patches:
		if not patch.has("extinguished_at"):
			points_active.append(patch.get("pos", Vector3.ZERO))
	if points_active.is_empty():
		_ember_particles.emitting = false
		_smoke_particles.emitting = false
		return
	var image := Image.create(points_active.size(), 1, false, Image.FORMAT_RGBF)
	for index in range(points_active.size()):
		var point := points_active[index]
		image.set_pixel(index, 0, Color(point.x, point.y, point.z, 1.0))
	var points := ImageTexture.create_from_image(image)
	for process in [_ember_process, _smoke_process]:
		process.emission_point_count = points_active.size()
		process.emission_point_texture = points


func _inside_fuel_envelope(candidate: Vector3) -> bool:
	var point := Vector2(candidate.x, candidate.z)
	if point.length() > radius * 1.08:
		return false
	var forward := Vector2(cos(propagation_heading), sin(propagation_heading))
	var side := Vector2(-forward.y, forward.x)
	var along := point.dot(forward) / maxf(0.1, radius)
	var across := point.dot(side) / maxf(0.1, radius * envelope_aspect)
	var wobble := 1.0 + 0.13 * sin(along * 5.3 + across * 3.7 + float(simulation_seed % 997))
	return along * along + across * across <= wobble


func _start_branch(
	origin: Vector3, forced_angle: float = 999.0, continuation: bool = false
) -> void:
	if not continuation and _branches_started >= _branch_budget:
		return
	var branch_index := _branches_started % _branch_budget
	var angle := forced_angle
	if angle > 100.0:
		var arc_position := float(branch_index) / maxf(1.0, float(_branch_budget - 1)) - 0.5
		angle = propagation_heading + arc_position * _branch_arc + _rng.randf_range(-0.45, 0.45)
	var direction := Vector2(cos(angle), sin(angle))
	(
		_walkers
		. append(
			{
				"pos": origin,
				"direction": direction,
				"remaining": _rng.randi_range(4, 11),
				"step": _rng.randf_range(0.52, 0.86),
				"failures": 0,
			}
		)
	)
	_branches_started += 1


func _is_occupied(candidate: Vector3) -> bool:
	for patch in _patches:
		var pos: Vector3 = patch.get("pos", Vector3.ZERO)
		if Vector2(pos.x - candidate.x, pos.z - candidate.z).length() < SPREAD_STEP * 0.52:
			return true
	return false


func _project_candidate(parent: Vector3, candidate: Vector3) -> Variant:
	if get_world_3d() == null:
		return null
	if RoundManager.get_smoke_density_at(to_global(candidate + Vector3.UP * 0.25)) > 0.24:
		return null
	var space := get_world_3d().direct_space_state
	var floor_query := PhysicsRayQueryParameters3D.create(
		to_global(candidate + Vector3.UP * 0.62), to_global(candidate - Vector3.UP * 1.05)
	)
	floor_query.collision_mask = WORLD_COLLISION_MASK
	var floor_hit: Dictionary = space.intersect_ray(floor_query)
	if floor_hit.is_empty():
		return null
	var normal: Vector3 = floor_hit.get("normal", Vector3.UP)
	if normal.y < 0.55:
		return null
	var floor_world: Vector3 = floor_hit.get("position", Vector3.ZERO)
	var local := to_local(floor_world) + Vector3.UP * 0.014
	# Do not jump up walls or down to a separate lower floor while spreading.
	if absf(local.y - parent.y) > 0.46:
		return null
	var wall_query := PhysicsRayQueryParameters3D.create(
		to_global(parent + Vector3.UP * 0.20), to_global(local + Vector3.UP * 0.20)
	)
	wall_query.collision_mask = WORLD_COLLISION_MASK
	if not space.intersect_ray(wall_query).is_empty():
		return null
	return local


func _expand_one() -> void:
	var attempts := 0
	while attempts < 18 and _patches.size() < target_patch_count:
		if _walkers.is_empty():
			var continuation := _branches_started >= _branch_budget
			var origin := Vector3.ZERO
			if continuation or (_patches.size() > 6 and _rng.randf() < 0.42):
				var parent_patch: Dictionary = _patches[_rng.randi_range(0, _patches.size() - 1)]
				if parent_patch.has("extinguished_at"):
					attempts += 1
					continue
				origin = parent_patch.get("pos", Vector3.ZERO)
			# A finished primary arm does not extinguish unused fuel. Continue from
			# an existing connected patch; walls and the fuel envelope still apply.
			_start_branch(origin, 999.0, continuation)
			continue
		var walker_index := _rng.randi_range(0, _walkers.size() - 1)
		var walker: Dictionary = _walkers[walker_index]
		var parent: Vector3 = walker.get("pos", Vector3.ZERO)
		var direction := (walker.get("direction", Vector2.RIGHT) as Vector2).rotated(
			_rng.randf_range(-0.38, 0.38)
		)
		var distance := float(walker.get("step", SPREAD_STEP)) * _rng.randf_range(0.84, 1.18)
		var lateral := Vector2(-direction.y, direction.x) * _rng.randf_range(-0.15, 0.15)
		var offset := (direction + lateral).normalized() * distance
		var candidate := parent + Vector3(offset.x, 0.0, offset.y)
		attempts += 1
		if not _inside_fuel_envelope(candidate):
			_walkers.remove_at(walker_index)
			continue
		if _is_occupied(candidate):
			walker["direction"] = direction.rotated(_rng.randf_range(0.42, 1.05))
			walker["failures"] = int(walker.get("failures", 0)) + 1
			if int(walker["failures"]) >= 7:
				_walkers.remove_at(walker_index)
			continue
		var projected: Variant = _project_candidate(parent, candidate)
		if projected == null:
			_walkers.remove_at(walker_index)
			continue
		var local_pos := projected as Vector3
		_add_patch(local_pos, parent)
		walker["pos"] = local_pos
		walker["direction"] = direction
		walker["failures"] = 0
		walker["remaining"] = int(walker.get("remaining", 1)) - 1
		walker["step"] = clampf(
			float(walker.get("step", SPREAD_STEP)) * _rng.randf_range(0.90, 1.10), 0.44, 0.94
		)
		if (
			int(walker["remaining"]) > 1
			and _branches_started < _branch_budget
			and _rng.randf() < 0.16
		):
			_start_branch(local_pos, direction.angle() + _rng.randf_range(-1.15, 1.15))
		if int(walker["remaining"]) <= 0:
			_walkers.remove_at(walker_index)
		return


func _physics_process(delta: float) -> void:
	_smoke_tick -= delta
	if _smoke_tick <= 0.0 and life_left > 0.0:
		_smoke_tick = 0.20
		_extinguish_smoked_patches()
	life_left -= delta
	if life_left <= 0.0 and not _audio_extinguished:
		_audio_extinguished = true
		if is_instance_valid(_fire_audio):
			_fire_audio.stop()
		AudioManager.play_cue_3d("fire_extinguish", global_position, -5.0, 25.0)
	if life_left <= -1.15:
		queue_free()
		return
	_age += delta
	if life_left > 0.0:
		_spread_tick -= delta
		if _spread_tick <= 0.0:
			_spread_tick = maxf(_spread_tick + _spread_interval, _spread_interval)
			for _index in range(_patches_per_step):
				_expand_one()
		if is_instance_valid(_light):
			var flicker := (
				0.88
				+ 0.09 * sin(_age * 19.0 + float(simulation_seed % 31))
				+ 0.06 * sin(_age * 31.7)
			)
			_light.light_energy = (
				(1.40 + _current_radius * 0.30) * flicker * clampf(life_left / 1.05, 0.0, 1.0)
			)
			_light.omni_range = maxf(1.8, _current_radius * 2.15)
		_tick -= delta
		if _tick <= 0.0:
			_tick += 0.25
			_damage_tick()
	else:
		if is_instance_valid(_light):
			_light.light_energy = 0.0
	if life_left < 0.95:
		if is_instance_valid(_ember_particles):
			_ember_particles.emitting = false
		if is_instance_valid(_smoke_particles):
			_smoke_particles.emitting = false


func _process(delta: float) -> void:
	_visual_time += delta
	for entry in _flames:
		var flame := entry.get("node") as MeshInstance3D
		if not is_instance_valid(flame):
			continue
		var material := entry.get("material") as ShaderMaterial
		var born := float(entry.get("born", 0.0))
		var ignition := clampf((_age - born) / float(entry.get("ignition_span", 0.24)), 0.0, 1.0)
		var patch_fade := clampf(
			(life_left - float(entry.get("fade_offset", 0.0))) / 1.05, 0.0, 1.0
		)
		patch_fade *= _patch_extinction_fade(entry.get("patch", {}))
		flame.visible = ignition > 0.001 and patch_fade > 0.001
		if not flame.visible:
			continue
		var phase := float(entry.get("phase", 0.0))
		var flicker := 0.95 + 0.05 * sin(_visual_time * 11.0 + phase)
		var time_height := lerpf(0.68, 1.0, clampf(life_left / _initial_life, 0.0, 1.0))
		if is_instance_valid(material):
			material.set_shader_parameter("ignition", ignition)
			material.set_shader_parameter("fade", patch_fade * flicker)
			material.set_shader_parameter("height_fade", time_height * lerpf(0.25, 1.0, patch_fade))
			material.set_shader_parameter(
				"intensity",
				float(entry.get("intensity", 1.0)) * (0.94 + 0.06 * sin(_visual_time * 7.3 + phase))
			)
	for entry in _heat:
		var heat := entry.get("node") as MeshInstance3D
		if not is_instance_valid(heat):
			continue
		var material := entry.get("material") as ShaderMaterial
		var ignition := clampf((_age - float(entry.get("born", 0.0))) / 0.38, 0.0, 1.0)
		var fade := clampf((life_left - float(entry.get("fade_offset", 0.0))) / 1.2, 0.0, 1.0)
		fade *= _patch_extinction_fade(entry.get("patch", {}))
		heat.visible = ignition > 0.001 and fade > 0.001
		if is_instance_valid(material):
			material.set_shader_parameter("ignition", ignition)
			material.set_shader_parameter("fade", fade)


func _nearest_patch(target: Vector3) -> Dictionary:
	var best: Dictionary = {}
	if life_left <= 0.0:
		return best
	var best_distance := INF
	for patch in _patches:
		if patch.has("extinguished_at"):
			continue
		# Let the short ignition flare become visible before this patch can hurt.
		if _age - float(patch.get("born", 0.0)) < 0.12:
			continue
		var local: Vector3 = patch.get("pos", Vector3.ZERO)
		var world := to_global(local)
		if absf(target.y - world.y) > 1.85:
			continue
		var distance := Vector2(target.x - world.x, target.z - world.z).length()
		var patch_radius := float(patch.get("radius", PATCH_RADIUS))
		if distance <= patch_radius and distance < best_distance:
			best_distance = distance
			best = patch
	return best


func _patch_visible_to_actor(patch_pos: Vector3, target: Vector3) -> bool:
	if get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(patch_pos + Vector3.UP * 0.22, target)
	query.collision_mask = WORLD_COLLISION_MASK
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _damage_tick() -> void:
	if life_left <= 0.0:
		return
	for actor in RoundManager.actors:
		if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
			continue
		if (
			is_instance_valid(thrower)
			and actor != thrower
			and String(actor.get("team")) == String(thrower.get("team"))
			and not GameData.friendly_fire
		):
			continue
		var target: Vector3 = actor.global_position + Vector3(0.0, 0.65, 0.0)
		var patch := _nearest_patch(target)
		if patch.is_empty():
			continue
		var patch_pos := to_global(patch.get("pos", Vector3.ZERO) as Vector3)
		if not _patch_visible_to_actor(patch_pos, target):
			continue
		var patch_radius := float(patch.get("radius", PATCH_RADIUS))
		var falloff := lerpf(
			1.0,
			0.62,
			clampf(
				Vector2(target.x - patch_pos.x, target.z - patch_pos.z).length() / patch_radius,
				0.0,
				1.0
			)
		)
		if actor.has_method("apply_explosion_damage"):
			actor.call("apply_explosion_damage", thrower, 5.5 * falloff, area_type, patch_pos)

	# Bomb-site crates remain bulletproof, but fire damages them in repeated small
	# ticks. One ignition can never delete a 250-HP crate.
	var world: Node = RoundManager.game_world
	if is_instance_valid(world) and world.get("breakables") != null:
		for breakable in world.get("breakables"):
			if not is_instance_valid(breakable) or not breakable.has_method("apply_damage"):
				continue
			var centre: Vector3 = (
				breakable.world_aabb.get_center()
				if breakable.world_aabb.size.length_squared() > 0.001
				else breakable.global_position
			)
			if not _nearest_patch(centre).is_empty():
				breakable.call("apply_damage", 2.0, centre, true)


func burns_at(point: Vector3) -> bool:
	return not _nearest_patch(point).is_empty()

func _patch_extinction_fade(patch: Dictionary) -> float:
	return clampf(1.0 - (_age - float(patch["extinguished_at"])) / 0.38, 0.0, 1.0) if patch.has("extinguished_at") else 1.0

func _extinguish_smoked_patches() -> void:
	if RoundManager.smoke_volumes.is_empty():
		return
	var active := 0
	var changed := false
	for patch in _patches:
		if patch.has("extinguished_at"):
			continue
		var point := to_global(patch["pos"] as Vector3) + Vector3.UP * 0.25
		for cloud in RoundManager.smoke_volumes:
			if is_instance_valid(cloud) and cloud.get_density_at(point) > 0.24 and cloud.interaction_visible(cloud.global_position, point):
				patch["extinguished_at"] = _age
				changed = true
				break
		if not patch.has("extinguished_at"):
			active += 1
	if changed:
		# Stop propagation from covered fuel; untouched branches can continue.
		for i in range(_walkers.size() - 1, -1, -1):
			var parent: Vector3 = _walkers[i].get("pos", Vector3.ZERO)
			for patch in _patches:
				if patch.has("extinguished_at") and parent.distance_squared_to(patch["pos"]) < 0.04:
					_walkers.remove_at(i)
					break
		_refresh_particle_emission()
	if active == 0:
		_walkers.clear()
		life_left = minf(life_left, 0.18)
