class_name IncendiaryArea
extends Node3D
## Molotov/incendiary ground fire: a persistent, animated area that damages
## actors and explosive-only breakables in short ticks rather than one blast.

var thrower: Node3D = null
var area_type: String = "molotov"
var radius: float = 3.25
var life_left: float = 7.0
var _tick: float = 0.0
var _anim_tick: float = 0.0
var _frame: int = 0
var _flames: Array[Sprite3D] = []
var _frames: Array[Texture2D] = []
var _light: OmniLight3D = null


func setup_fire(owner_actor: Node3D, kind: String) -> void:
	thrower = owner_actor
	area_type = kind
	life_left = 7.0 if kind == "molotov" else 8.0
	radius = 3.35 if kind == "molotov" else 3.10
	_tick = 0.05

	for i in range(8):
		var path := "res://assets/sprites/fexplo.png" if i == 0 else "res://assets/sprites/fexplo_%d.png" % i
		var tex := GameData.get_texture(path)
		if tex != null:
			_frames.append(tex)
	if _frames.is_empty():
		return

	# A ring plus a hotter centre makes the gameplay radius readable in 3D.
	for i in range(13):
		var flame := Sprite3D.new()
		flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		flame.shaded = false
		flame.pixel_size = 0.0065
		flame.modulate = Color(1.0, 0.72, 0.30, 0.88)
		var angle := float(i - 1) * TAU / 12.0
		var r := 0.0 if i == 0 else radius * (0.42 + 0.30 * float((i % 3) / 2))
		flame.position = Vector3(cos(angle) * r, 0.42 + 0.12 * float(i % 3), sin(angle) * r)
		flame.scale = Vector3.ONE * (1.25 if i == 0 else 0.85)
		flame.texture = _frames[i % _frames.size()]
		add_child(flame)
		_flames.append(flame)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.38, 0.08)
	_light.light_energy = 2.2
	_light.omni_range = radius * 2.2
	_light.position = Vector3(0.0, 0.75, 0.0)
	add_child(_light)


func _process(delta: float) -> void:
	life_left -= delta
	if life_left <= 0.0:
		queue_free()
		return

	_anim_tick -= delta
	if _anim_tick <= 0.0 and not _frames.is_empty():
		_anim_tick = 0.075
		_frame = (_frame + 1) % _frames.size()
		for i in range(_flames.size()):
			var flame := _flames[i]
			flame.texture = _frames[(_frame + i) % _frames.size()]
			var pulse := 0.88 + 0.15 * sin(float(_frame + i * 3) * 1.7)
			flame.scale = Vector3.ONE * pulse * (1.25 if i == 0 else 0.85)
			flame.modulate.a = clampf(life_left, 0.0, 1.0) * 0.88
	if is_instance_valid(_light):
		_light.light_energy = (1.8 + 0.35 * sin(float(_frame) * 1.9)) * clampf(life_left, 0.0, 1.0)

	_tick -= delta
	if _tick > 0.0:
		return
	_tick += 0.25
	_damage_tick()


func _damage_tick() -> void:
	for actor in RoundManager.actors:
		if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
			continue
		if is_instance_valid(thrower) and actor != thrower and String(actor.get("team")) == String(thrower.get("team")) and not GameData.friendly_fire:
			continue
		var target: Vector3 = actor.global_position + Vector3(0.0, 0.65, 0.0)
		var flat := Vector2(target.x - global_position.x, target.z - global_position.z).length()
		if flat > radius or absf(target.y - global_position.y) > 2.0:
			continue
		var falloff := lerpf(1.0, 0.55, clampf(flat / radius, 0.0, 1.0))
		if actor.has_method("apply_explosion_damage"):
			actor.call("apply_explosion_damage", thrower, 5.5 * falloff, area_type, global_position)

	# Bomb-site crates remain bulletproof, but incendiaries are grenades and can
	# scorch them over repeated ticks. One ignition can never delete a 250-HP crate.
	var world: Node = RoundManager.game_world
	if is_instance_valid(world) and world.get("breakables") != null:
		for breakable in world.get("breakables"):
			if not is_instance_valid(breakable) or not breakable.has_method("apply_damage"):
				continue
			var center: Vector3 = breakable.world_aabb.get_center() if breakable.world_aabb.size.length_squared() > 0.001 else breakable.global_position
			if center.distance_to(global_position) <= radius:
				breakable.call("apply_damage", 2.0, center, true)
