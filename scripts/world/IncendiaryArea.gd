class_name IncendiaryArea
extends Node3D
## Propagating Molotov/incendiary ground fire.
##
## Fuel ignites in staggered patches instead of appearing as one instant ring.
## Each new patch is projected onto walkable geometry and must be reachable from
## an existing patch without crossing a wall. Damage follows the burning patches,
## not the maximum radius, so the fire cannot hurt through cover or ahead of its
## visible expansion. All simulation runs in physics; only presentation is per-frame.

const MAX_PATCHES: int = 42
const PATCH_RADIUS: float = 0.82
const SPREAD_STEP: float = 0.72
const SPREAD_INTERVAL: float = 0.052
const PATCHES_PER_STEP: int = 2
const WORLD_COLLISION_MASK: int = 1
const FLAME_SHADER: Shader = preload("res://assets/shaders/incendiary_flame.gdshader")

static var _ember_texture: Texture2D = null

var thrower: Node3D = null
var area_type: String = "molotov"
## Maximum fuel travel, not an always-active damage sphere.
var radius: float = 3.25
var life_left: float = 7.0

var _tick: float = 0.0
var _age: float = 0.0
var _visual_time: float = 0.0
var _spread_tick: float = 0.0
var _current_radius: float = PATCH_RADIUS
var _rng := RandomNumberGenerator.new()
var _patches: Array[Dictionary] = []
var _frontier: Array[Vector3] = []
var _pending: Array[Dictionary] = []
var _flames: Array[Dictionary] = []
var _smoke: Array[Dictionary] = []
var _embers: Array[Dictionary] = []
var _light: OmniLight3D = null


func setup_fire(owner_actor: Node3D, kind: String) -> void:
	thrower = owner_actor
	area_type = kind
	life_left = 7.0 if kind == "molotov" else 8.0
	radius = 3.35 if kind == "molotov" else 3.10
	_tick = 0.08
	_spread_tick = 0.09
	_rng.randomize()
	_ensure_textures()
	_snap_origin_to_floor()
	_add_patch(Vector3.ZERO)
	_frontier.append(Vector3.ZERO)
	_create_light()
	_create_smoke()
	_create_embers()


func _snap_origin_to_floor() -> void:
	if get_world_3d() == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.45,
		global_position - Vector3.UP * 1.1
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


func _create_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "FireLight"
	_light.light_color = Color(1.0, 0.36, 0.065)
	_light.light_energy = 0.0
	_light.omni_range = 2.0
	_light.position = Vector3(0.0, 0.72, 0.0)
	_light.light_cull_mask = 3
	add_child(_light)


func _add_patch(local_pos: Vector3) -> void:
	var patch_index := _patches.size()
	var patch := {
		"pos": local_pos,
		"born": _age,
		"phase": _rng.randf_range(0.0, TAU),
	}
	_patches.append(patch)
	_current_radius = maxf(_current_radius, Vector2(local_pos.x, local_pos.z).length() + PATCH_RADIUS)

	var scorch := Sprite3D.new()
	scorch.name = "Scorch%02d" % patch_index
	scorch.texture = GameData.get_scorch_decal_texture()
	scorch.pixel_size = 0.012 * _rng.randf_range(0.85, 1.18)
	scorch.rotation = Vector3(-PI * 0.5, 0.0, _rng.randf_range(0.0, TAU))
	scorch.position = local_pos + Vector3.UP * 0.012
	scorch.modulate = Color(0.42, 0.19, 0.075, 0.0)
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scorch)
	patch["scorch"] = scorch

	# Two animated shaders per fuel patch: a broad violet/orange envelope and a
	# smaller white-hot core. Their low, irregular tongues merge into the broad
	# CS2-style ground fire instead of forming repeated upright orange cones.
	var quad_sizes := [Vector2(1.42, 0.82), Vector2(0.96, 0.68)]
	var base_heights := [0.37, 0.31]
	for layer in range(2):
		var flame := MeshInstance3D.new()
		flame.name = "Flame%02d_%d" % [patch_index, layer]
		var quad := QuadMesh.new()
		var quad_size: Vector2 = quad_sizes[layer]
		quad.size = quad_size
		flame.mesh = quad
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = FLAME_SHADER
		material.set_shader_parameter("seed", _rng.randf_range(0.0, 80.0))
		material.set_shader_parameter("layer", float(layer))
		material.set_shader_parameter("ignition", 0.0)
		flame.material_override = material
		var lateral := Vector3(_rng.randf_range(-0.15, 0.15), 0.0, _rng.randf_range(-0.15, 0.15))
		flame.position = local_pos + lateral + Vector3.UP * float(base_heights[layer])
		flame.scale = Vector3.ONE * 0.01
		add_child(flame)
		_flames.append({
			"node": flame,
			"material": material,
			"origin": flame.position,
			"root_y": flame.position.y - quad_size.y * 0.5,
			"born": _age + float(layer) * 0.045,
			"phase": _rng.randf_range(0.0, TAU),
			"scale": Vector2(_rng.randf_range(0.82, 1.18), _rng.randf_range(0.80, 1.20)),
			"layer": layer,
		})


func _create_smoke() -> void:
	for index in range(8):
		var sprite := Sprite3D.new()
		sprite.name = "FireSmoke%02d" % index
		sprite.texture = GameData.get_smoke_cloud_variant(index)
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.pixel_size = 0.009
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.visible = false
		add_child(sprite)
		var entry := {"node": sprite, "age": 0.0, "life": 1.0, "origin": Vector3.ZERO,
			"velocity": Vector3.ZERO, "size": 1.0}
		_smoke.append(entry)
		_reset_smoke(entry, true)


func _reset_smoke(entry: Dictionary, initial: bool = false) -> void:
	if _patches.is_empty():
		return
	var patch: Dictionary = _patches[_rng.randi_range(0, _patches.size() - 1)]
	var origin: Vector3 = patch.get("pos", Vector3.ZERO)
	origin += Vector3(_rng.randf_range(-0.28, 0.28), _rng.randf_range(0.45, 0.82), _rng.randf_range(-0.28, 0.28))
	var life := _rng.randf_range(2.1, 3.4)
	entry["life"] = life
	entry["age"] = -_rng.randf_range(0.0, 1.5) if initial else 0.0
	entry["origin"] = origin
	entry["velocity"] = Vector3(_rng.randf_range(-0.13, 0.13), _rng.randf_range(0.34, 0.58), _rng.randf_range(-0.13, 0.13))
	entry["size"] = _rng.randf_range(0.72, 1.18)


func _create_embers() -> void:
	for index in range(16):
		var sprite := Sprite3D.new()
		sprite.name = "Ember%02d" % index
		sprite.texture = _ember_texture
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.pixel_size = 0.0032
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sprite.visible = false
		add_child(sprite)
		var entry := {"node": sprite, "age": 0.0, "life": 1.0, "origin": Vector3.ZERO,
			"velocity": Vector3.ZERO, "size": 1.0}
		_embers.append(entry)
		_reset_ember(entry, true)


func _reset_ember(entry: Dictionary, initial: bool = false) -> void:
	if _patches.is_empty():
		return
	var patch: Dictionary = _patches[_rng.randi_range(0, _patches.size() - 1)]
	var origin: Vector3 = patch.get("pos", Vector3.ZERO)
	origin += Vector3(_rng.randf_range(-0.20, 0.20), _rng.randf_range(0.18, 0.46), _rng.randf_range(-0.20, 0.20))
	entry["life"] = _rng.randf_range(0.65, 1.45)
	entry["age"] = -_rng.randf_range(0.0, 1.1) if initial else 0.0
	entry["origin"] = origin
	entry["velocity"] = Vector3(_rng.randf_range(-0.42, 0.42), _rng.randf_range(0.85, 1.85), _rng.randf_range(-0.42, 0.42))
	entry["size"] = _rng.randf_range(0.45, 1.0)


func _refill_candidates() -> void:
	if _frontier.is_empty():
		return
	var parent: Vector3 = _frontier.pop_front()
	var start := _rng.randi_range(0, 7)
	for offset in range(8):
		var direction_index := (start + offset) % 8
		var angle := float(direction_index) * TAU / 8.0 + _rng.randf_range(-0.09, 0.09)
		var distance := SPREAD_STEP * _rng.randf_range(0.93, 1.07)
		var candidate := parent + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		_pending.append({"from": parent, "to": candidate})


func _is_occupied(candidate: Vector3) -> bool:
	for patch in _patches:
		var pos: Vector3 = patch.get("pos", Vector3.ZERO)
		if Vector2(pos.x - candidate.x, pos.z - candidate.z).length() < SPREAD_STEP * 0.63:
			return true
	return false


func _project_candidate(parent: Vector3, candidate: Vector3) -> Variant:
	if Vector2(candidate.x, candidate.z).length() > radius or get_world_3d() == null:
		return null
	var space := get_world_3d().direct_space_state
	var floor_query := PhysicsRayQueryParameters3D.create(
		to_global(candidate + Vector3.UP * 0.62),
		to_global(candidate - Vector3.UP * 1.05)
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
		to_global(parent + Vector3.UP * 0.20),
		to_global(local + Vector3.UP * 0.20)
	)
	wall_query.collision_mask = WORLD_COLLISION_MASK
	if not space.intersect_ray(wall_query).is_empty():
		return null
	return local


func _expand_one() -> void:
	var attempts := 0
	while attempts < 12 and _patches.size() < MAX_PATCHES:
		if _pending.is_empty():
			_refill_candidates()
			if _pending.is_empty():
				return
		var candidate: Dictionary = _pending.pop_front()
		var parent: Vector3 = candidate.get("from", Vector3.ZERO)
		var target: Vector3 = candidate.get("to", Vector3.ZERO)
		attempts += 1
		if _is_occupied(target):
			continue
		var projected: Variant = _project_candidate(parent, target)
		if projected == null:
			continue
		var local_pos := projected as Vector3
		_add_patch(local_pos)
		_frontier.append(local_pos)
		return


func _physics_process(delta: float) -> void:
	life_left -= delta
	if life_left <= 0.0:
		queue_free()
		return
	_age += delta
	_spread_tick -= delta
	if _spread_tick <= 0.0:
		_spread_tick = maxf(_spread_tick + SPREAD_INTERVAL, SPREAD_INTERVAL)
		for _index in range(PATCHES_PER_STEP):
			_expand_one()
	if is_instance_valid(_light):
		var flicker := 0.88 + 0.09 * sin(_age * 19.0) + 0.06 * sin(_age * 31.7)
		_light.light_energy = (1.45 + _current_radius * 0.32) * flicker * clampf(life_left, 0.0, 1.0)
		_light.omni_range = maxf(1.8, _current_radius * 2.15)

	_tick -= delta
	if _tick <= 0.0:
		_tick += 0.25
		_damage_tick()


func _process(delta: float) -> void:
	_visual_time += delta
	var fade := clampf(life_left / 0.90, 0.0, 1.0)
	for entry in _flames:
		var flame := entry.get("node") as MeshInstance3D
		if not is_instance_valid(flame):
			continue
		var material := entry.get("material") as ShaderMaterial
		var born := float(entry.get("born", 0.0))
		var ignition := clampf((_age - born) / 0.24, 0.0, 1.0)
		flame.visible = ignition > 0.001 and fade > 0.001
		if not flame.visible:
			continue
		var phase := float(entry.get("phase", 0.0))
		var layer := int(entry.get("layer", 0))
		var wave := sin(_visual_time * (9.0 + float(layer) * 1.7) + phase)
		var sway := sin(_visual_time * 5.3 + phase * 1.3)
		var base_scale: Vector2 = entry.get("scale", Vector2.ONE)
		var width_scale := base_scale.x * (0.94 + wave * 0.09) * ignition
		var height_scale := base_scale.y * (0.95 + wave * 0.13) * ignition
		flame.scale = Vector3(width_scale, height_scale, 1.0)
		var origin: Vector3 = entry.get("origin", Vector3.ZERO)
		flame.position = origin + Vector3(sway * 0.028, 0.0, -sway * 0.020)
		# QuadMesh scales around its centre. Reconstruct its centre from the
		# ground root so ignition grows upward instead of floating in mid-air.
		var quad := flame.mesh as QuadMesh
		if quad != null:
			var root_y := float(entry.get("root_y", origin.y - quad.size.y * 0.5))
			flame.position.y = root_y + quad.size.y * height_scale * 0.5
		if is_instance_valid(material):
			material.set_shader_parameter("ignition", ignition)
			material.set_shader_parameter("fade", fade * (0.94 + wave * 0.06))

	for patch in _patches:
		var scorch := patch.get("scorch") as Sprite3D
		if is_instance_valid(scorch):
			var born := float(patch.get("born", 0.0))
			var ignition := clampf((_age - born) / 0.35, 0.0, 1.0)
			scorch.modulate.a = 0.40 * ignition * fade

	_process_smoke(delta, fade)
	_process_embers(delta, fade)


func _process_smoke(delta: float, fade: float) -> void:
	for entry in _smoke:
		var sprite := entry.get("node") as Sprite3D
		if not is_instance_valid(sprite):
			continue
		var age := float(entry.get("age", 0.0)) + delta
		var life := float(entry.get("life", 1.0))
		entry["age"] = age
		if age >= life:
			_reset_smoke(entry)
			age = float(entry["age"])
			life = float(entry["life"])
		if age < 0.0:
			sprite.visible = false
			continue
		var t := clampf(age / maxf(0.01, life), 0.0, 1.0)
		var origin: Vector3 = entry.get("origin", Vector3.ZERO)
		var velocity: Vector3 = entry.get("velocity", Vector3.ZERO)
		var size := float(entry.get("size", 1.0))
		sprite.visible = fade > 0.001
		sprite.position = origin + velocity * age + Vector3(sin(age * 1.7) * 0.08, 0.0, cos(age * 1.3) * 0.06)
		sprite.scale = Vector3.ONE * size * lerpf(0.42, 1.65, t)
		var alpha := sin(t * PI) * 0.19 * fade
		sprite.modulate = Color(0.30, 0.27, 0.24, alpha)


func _process_embers(delta: float, fade: float) -> void:
	for entry in _embers:
		var sprite := entry.get("node") as Sprite3D
		if not is_instance_valid(sprite):
			continue
		var age := float(entry.get("age", 0.0)) + delta
		var life := float(entry.get("life", 1.0))
		entry["age"] = age
		if age >= life:
			_reset_ember(entry)
			age = float(entry["age"])
			life = float(entry["life"])
		if age < 0.0:
			sprite.visible = false
			continue
		var t := clampf(age / maxf(0.01, life), 0.0, 1.0)
		var origin: Vector3 = entry.get("origin", Vector3.ZERO)
		var velocity: Vector3 = entry.get("velocity", Vector3.ZERO)
		var size := float(entry.get("size", 1.0))
		sprite.visible = fade > 0.001
		sprite.position = origin + velocity * age + Vector3.DOWN * (0.62 * age * age)
		sprite.scale = Vector3.ONE * size * lerpf(1.0, 0.30, t)
		sprite.modulate = Color(1.0, 0.64, 0.20, (1.0 - t) * 0.82 * fade)


func _nearest_patch(target: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := PATCH_RADIUS
	for patch in _patches:
		# Let the short ignition flare become visible before this patch can hurt.
		if _age - float(patch.get("born", 0.0)) < 0.12:
			continue
		var local: Vector3 = patch.get("pos", Vector3.ZERO)
		var world := to_global(local)
		if absf(target.y - world.y) > 1.85:
			continue
		var distance := Vector2(target.x - world.x, target.z - world.z).length()
		if distance <= best_distance:
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
	for actor in RoundManager.actors:
		if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
			continue
		if is_instance_valid(thrower) and actor != thrower and String(actor.get("team")) == String(thrower.get("team")) and not GameData.friendly_fire:
			continue
		var target: Vector3 = actor.global_position + Vector3(0.0, 0.65, 0.0)
		var patch := _nearest_patch(target)
		if patch.is_empty():
			continue
		var patch_pos := to_global(patch.get("pos", Vector3.ZERO) as Vector3)
		if not _patch_visible_to_actor(patch_pos, target):
			continue
		var falloff := lerpf(1.0, 0.62, clampf(Vector2(target.x - patch_pos.x, target.z - patch_pos.z).length() / PATCH_RADIUS, 0.0, 1.0))
		if actor.has_method("apply_explosion_damage"):
			actor.call("apply_explosion_damage", thrower, 5.5 * falloff, area_type, patch_pos)

	# Bomb-site crates remain bulletproof, but fire damages them in repeated small
	# ticks. One ignition can never delete a 250-HP crate.
	var world: Node = RoundManager.game_world
	if is_instance_valid(world) and world.get("breakables") != null:
		for breakable in world.get("breakables"):
			if not is_instance_valid(breakable) or not breakable.has_method("apply_damage"):
				continue
			var centre: Vector3 = breakable.world_aabb.get_center() if breakable.world_aabb.size.length_squared() > 0.001 else breakable.global_position
			if not _nearest_patch(centre).is_empty():
				breakable.call("apply_damage", 2.0, centre, true)
