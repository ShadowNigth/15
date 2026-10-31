class_name DroppedWeapon
extends StaticBody3D
## Interactive physical dropped weapon / C4 backpack / Defuse thighpack on the ground.
## Collides on Layer 4 (bullet/knife interactive props, non-blocking to player/bot capsules)
## and reacts with full 3D velocity, wall/floor bounces, sliding friction, and angular tumble
## when hit by gunshots, knife slashes, HE grenades, or C4 explosions!

var item_id: String = ""  # weapon_id, "c4", or "defuser"
var clip_ammo: int = 0
var reserve_ammo: int = 0
var silenced: bool = false

var _visual_root: Node3D = null
var _vel: Vector3 = Vector3.ZERO
var _ang_vel: Vector3 = Vector3.ZERO
var _pickup_cooldown: float = 0.55
var _settled: bool = false
var _clatter_cooldown: float = 0.0


func _ready() -> void:
	collision_layer = 4  # Interactive physics prop layer (raycastable by bullets, non-snagging for actors)
	collision_mask = 0

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.66, 0.24, 0.38)
	col.shape = box
	col.position = Vector3(0.0, 0.10, 0.0)
	add_child(col)


func setup_drop(id: String, clip: int, reserve: int, throw_vel: Vector3, is_silenced: bool = false) -> void:
	item_id = id
	clip_ammo = clip
	reserve_ammo = reserve
	silenced = is_silenced
	_vel = throw_vel
	_ang_vel = Vector3(randf_range(-4.5, 4.5), randf_range(-6.0, 6.0), randf_range(-3.5, 3.5))
	_settled = false

	_visual_root = Node3D.new()
	_visual_root.name = "VisualModel"
	_visual_root.position = Vector3(0.0, 0.06, 0.0)
	add_child(_visual_root)

	var mdl_name := "w_ak47"
	if id == "defuser":
		mdl_name = "w_thighpack"
	elif id == "c4":
		mdl_name = "w_backpack"
	elif GameData.weapons.has(id):
		mdl_name = String(GameData.weapons[id].get("w_model", "w_" + id))

	var sc := GameData.get_model_scene("weapons/" + mdl_name)
	if sc:
		var inst := sc.instantiate()
		_set_layer_recursive(inst)
		_visual_root.add_child(inst)
	else:
		var mi := MeshInstance3D.new()
		mi.layers = 2
		var bm := BoxMesh.new()
		bm.size = Vector3(0.38, 0.12, 0.18)
		mi.mesh = bm
		_visual_root.add_child(mi)


func _set_layer_recursive(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "char")
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_set_layer_recursive(c)


func apply_bullet_impulse(hit_pos: Vector3, bullet_dir: Vector3, damage: float) -> void:
	_settled = false
	_pickup_cooldown = maxf(_pickup_cooldown, 0.20)

	var dir := bullet_dir.normalized()
	var push_mag := clampf(damage * 0.13, 2.8, 9.8)
	var up_pop := clampf(damage * 0.055, 1.5, 4.2)
	_vel += Vector3(dir.x * push_mag, maxf(0.8, dir.y * push_mag * 0.5) + up_pop, dir.z * push_mag)
	if _vel.length() > 22.0:
		_vel = _vel.normalized() * 22.0

	# Off-center torque spins the rifle realistically around the impact lever arm!
	var lever := hit_pos - (global_position + Vector3(0.0, 0.08, 0.0))
	var torque := lever.cross(dir * push_mag) * 16.0
	_ang_vel += torque + Vector3(randf_range(-5.0, 5.0), randf_range(-9.0, 9.0), randf_range(-5.0, 5.0))
	if _ang_vel.length() > 28.0:
		_ang_vel = _ang_vel.normalized() * 28.0

	AudioManager.play_3d("weapons/ric_metal-%d.wav" % randi_range(1, 2), hit_pos, -1.5, 24.0, randf_range(0.94, 1.10))
	_spawn_ricochet_spark(hit_pos)


func apply_explosion_impulse(blast_pos: Vector3, blast_radius: float, peak_speed: float = 16.5) -> void:
	var to_self := (global_position + Vector3(0.0, 0.22, 0.0)) - blast_pos
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
	var up_spd := (5.5 + peak_speed * 0.48) * falloff
	_vel += horiz * radial_spd + Vector3(0.0, up_spd, 0.0)
	if _vel.length() > 26.0:
		_vel = _vel.normalized() * 26.0

	_ang_vel += Vector3(
		randf_range(-16.0, 16.0),
		randf_range(-20.0, 20.0),
		randf_range(-16.0, 16.0)
	) * falloff


func _spawn_ricochet_spark(pos: Vector3) -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	var sp := Sprite3D.new()
	sp.layers = 2
	var tex := GameData.get_texture("res://assets/sprites/ledglow.png")
	if not tex:
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


func _physics_process(delta: float) -> void:
	if _pickup_cooldown > 0.0:
		_pickup_cooldown -= delta
	if _clatter_cooldown > 0.0:
		_clatter_cooldown -= delta

	if not _settled and is_inside_tree() and get_world_3d():
		_vel.y -= 21.5 * delta
		var space := get_world_3d().direct_space_state
		var cur := global_position
		var step := _vel * delta
		var step_len := step.length()

		if step_len > 0.00001:
			var probe_ofs := Vector3(0.0, 0.08, 0.0)
			var q := PhysicsRayQueryParameters3D.create(cur + probe_ofs, cur + probe_ofs + step + step.normalized() * 0.08)
			q.collision_mask = 1
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var nrm := hit["normal"] as Vector3
				var impact_spd := absf(_vel.dot(nrm))
				global_position = (hit["position"] as Vector3) + nrm * 0.05 - probe_ofs
				if nrm.y > 0.65:
					# Floor bounce + surface sliding friction!
					_vel = _vel.bounce(nrm)
					_vel.y *= 0.36
					_vel.x *= 0.72
					_vel.z *= 0.72
					_ang_vel *= 0.62
					if impact_spd > 2.2 and _clatter_cooldown <= 0.0:
						_clatter_cooldown = 0.14
						AudioManager.play_3d("player/pl_shell%d.wav" % randi_range(1, 3), global_position, -5.0, 18.0, randf_range(0.68, 0.82))
				else:
					# Wall ricochet bounce!
					_vel = _vel.bounce(nrm) * 0.52
					_ang_vel = -_ang_vel * 0.65
			else:
				global_position = cur + step

		# Continuous ground check & skidding friction when sliding along floor
		var q_down := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.16, 0.0), global_position - Vector3(0.0, 0.09, 0.0))
		q_down.collision_mask = 1
		var floor_hit := space.intersect_ray(q_down)
		if not floor_hit.is_empty() and _vel.y <= 0.35:
			global_position.y = (floor_hit["position"] as Vector3).y + 0.03
			if _vel.y < 0.0:
				_vel.y = 0.0
			var h_drag := maxf(0.0, 1.0 - 7.5 * delta)
			_vel.x *= h_drag
			_vel.z *= h_drag
			_ang_vel *= maxf(0.0, 1.0 - 9.0 * delta)
			if _visual_root:
				# Settle weapon flat onto floor while preserving its spun Y yaw!
				_visual_root.rotation.x = lerpf(_visual_root.rotation.x, 0.0, minf(1.0, 12.0 * delta))
				_visual_root.rotation.z = lerpf(_visual_root.rotation.z, 0.0, minf(1.0, 12.0 * delta))
			if _vel.length_squared() < 0.035 and _ang_vel.length_squared() < 0.08:
				_vel = Vector3.ZERO
				_ang_vel = Vector3.ZERO
				if _visual_root:
					_visual_root.rotation.x = 0.0
					_visual_root.rotation.z = 0.0
				_settled = true

		if _visual_root and _ang_vel.length_squared() > 0.001:
			_visual_root.rotation += _ang_vel * delta

	if _pickup_cooldown <= 0.0:
		_check_actor_pickup()


func _check_actor_pickup() -> void:
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		if a.global_position.distance_squared_to(global_position) > 1.40:
			continue
		if a.has_method("try_pickup_dropped") and a.try_pickup_dropped(self):
			RoundManager.dropped_items.erase(self)
			if get_parent():
				get_parent().remove_child(self)
			queue_free()
			return
