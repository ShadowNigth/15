class_name GrenadeProjectile
extends Node3D
## Thrown HE Grenade, Flashbang, and Smoke Grenade with GoldSrc bounce physics and detonation.

var grenade_type: String = "hegrenade"
var thrower: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var fuse_left: float = 1.65
var _detonated: bool = false
var _bounces: int = 0


func setup_grenade(gtype: String, owner_actor: Node3D, start_vel: Vector3) -> void:
	grenade_type = gtype
	thrower = owner_actor
	velocity = start_vel
	fuse_left = 1.65 if gtype != "smokegrenade" else 1.85

	var sc := GameData.get_model_scene("weapons/w_" + gtype)
	if sc:
		add_child(sc.instantiate())


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
	queue_free()


func _detonate_he() -> void:
	AudioManager.play_3d("weapons/hegrenade-%d.wav" % randi_range(1, 2), global_position, 3.5, 65.0, 1.0, 42.0)

	var puff := Sprite3D.new()
	puff.texture = GameData.get_texture("res://assets/sprites/black_smoke1.png")
	if not puff.texture:
		puff.texture = GameData.get_texture("res://assets/sprites/wall_puff1.png")
	puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	puff.pixel_size = 0.022
	puff.modulate = Color(1.0, 0.75, 0.35, 0.92)
	puff.global_position = global_position + Vector3(0, 0.45, 0)
	get_parent().add_child(puff)
	var tw := puff.create_tween()
	tw.tween_property(puff, "scale", Vector3(2.4, 2.4, 2.4), 0.38)
	tw.parallel().tween_property(puff, "modulate:a", 0.0, 0.38)
	tw.tween_callback(puff.queue_free)

	var space := get_world_3d().direct_space_state
	var max_r := 11.0  # ~350 GoldSrc units
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		if is_instance_valid(thrower) and a != thrower and String(a.get("team")) == String(thrower.get("team")) and not GameData.friendly_fire:
			continue
		var target_pos: Vector3 = a.global_position + Vector3(0, 1.0, 0)
		var d := global_position.distance_to(target_pos)
		if d > max_r:
			continue
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.2, 0), target_pos)
		q.collision_mask = 1
		var blocked := space.intersect_ray(q)
		var cover_mult := 0.45 if blocked else 1.0
		var dmg := 98.0 * (1.0 - d / max_r) * cover_mult
		if dmg > 1.0 and a.has_method("apply_explosion_damage"):
			a.apply_explosion_damage(thrower, dmg, "hegrenade")


func _detonate_flash() -> void:
	AudioManager.play_3d("weapons/flashbang-%d.wav" % randi_range(1, 2), global_position, 3.0, 58.0, 1.0, 38.0)
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
		var facing := look_dir.dot(to_flash)  # 1.0 looking straight at flash, -1.0 turned away
		var angle_factor := 1.0 if facing > 0.25 else (0.55 if facing > -0.35 else 0.22)
		var dist_factor := clampf(1.0 - (d / max_r) * 0.75, 0.2, 1.0)
		var duration := 4.8 * angle_factor * dist_factor
		if a.has_method("apply_flashbang"):
			a.apply_flashbang(duration)


func _detonate_smoke() -> void:
	AudioManager.play_3d("weapons/sg_explode.wav", global_position, 2.0, 45.0)
	RoundManager.add_smoke_cloud(global_position + Vector3(0, 1.2, 0), 4.6, 18.0)

	var smoke_root := Node3D.new()
	smoke_root.global_position = global_position
	get_parent().add_child(smoke_root)

	var puff_tex := GameData.get_texture("res://assets/sprites/smokepuff.png")
	if not puff_tex:
		puff_tex = GameData.get_texture("res://assets/sprites/wall_puff1.png")

	for i in range(14):
		var sp := Sprite3D.new()
		sp.texture = puff_tex
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.pixel_size = 0.032
		sp.modulate = Color(0.82, 0.84, 0.82, 0.0)
		sp.position = Vector3(randf_range(-2.6, 2.6), randf_range(0.8, 2.4), randf_range(-2.6, 2.6))
		smoke_root.add_child(sp)
		var tw := sp.create_tween()
		tw.tween_property(sp, "modulate:a", 0.78, 0.85)
		tw.tween_interval(14.5)
		tw.tween_property(sp, "modulate:a", 0.0, 2.5)

	var kill_tw := smoke_root.create_tween()
	kill_tw.tween_interval(18.2)
	kill_tw.tween_callback(smoke_root.queue_free)
