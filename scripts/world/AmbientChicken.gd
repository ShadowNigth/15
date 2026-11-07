class_name AmbientChicken
extends CharacterBody3D
## Non-objective, non-blocking ambient animal. World movement owns translation;
## the upstream GLB already removes root_motion travel from native walk/run.
var home: Vector3 = Vector3.ZERO
var is_alive: bool = true
var _anim: AnimationPlayer = null
var _model: Node3D = null
var _direction := Vector3.FORWARD
var _decision: float = 0.0
var _voice: float = 5.0
var _panic: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	collision_layer = 2  # Bullet/knife target, never a navigation obstacle.
	collision_mask = 1
	floor_snap_length = 0.25
	_rng.seed = int(home.x * 701.0 + home.z * 1907.0) + 7907
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.14
	capsule.height = 0.42
	shape.shape = capsule
	shape.position.y = 0.22
	add_child(shape)
	var scene := GameData.get_model_scene("native/chicken")
	if scene:
		_model = scene.instantiate()
		add_child(_model)
		for mesh in _model.find_children("*", "MeshInstance3D", true, false):
			mesh.layers = 2
		var animations := _model.find_children("*", "AnimationPlayer", true, false)
		if not animations.is_empty():
			_anim = animations[0]
			for clip in _anim.get_animation_list():
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	AudioManager.world_sound_emitted.connect(_on_world_sound)
	add_to_group("ambient_chickens")
	reset_for_round()

func reset_for_round() -> void:
	is_alive = true
	visible = GameData.ambient_chickens_enabled
	collision_layer = 2 if visible else 0
	global_position = home
	velocity = Vector3.ZERO
	_panic = 0.0
	_decision = 0.0
	_voice = _rng.randf_range(4.0, 12.0)
	if _model:
		_model.rotation = Vector3.ZERO
	_play("idle")

func _play(clip: String) -> void:
	if _anim != null and _anim.has_animation(clip) and _anim.current_animation != clip:
		_anim.play(clip, 0.15)

func _on_world_sound(point: Vector3, radius: float, _team: String) -> void:
	if not is_alive or not visible or point.distance_to(global_position) > minf(radius, 18.0):
		return
	_direction = (global_position - point).normalized()
	_direction.y = 0.0
	_panic = 3.0
	_decision = 0.5

func take_damage(_attacker: Node3D, damage: float) -> void:
	if not is_alive or damage <= 0.0:
		return
	is_alive = false
	collision_layer = 0
	velocity = Vector3.ZERO
	if _anim:
		_anim.pause()
	if _model:
		_model.rotation.z = PI * 0.5  # Authored fall, not a native death clip/ragdoll.
	AudioManager.play_3d("native/sccsgoknives/Chicken/death/chicken_death_%02d.wav" % _rng.randi_range(1, 3), global_position, -9.0, 14.0)

func _physics_process(delta: float) -> void:
	visible = GameData.ambient_chickens_enabled
	if not visible:
		collision_layer = 0
		return
	if not is_alive:
		return
	collision_layer = 2
	if RoundManager.get_incendiary_danger_at(global_position) > 0.5:
		take_damage(null, 30.0)
		return
	_panic = maxf(0.0, _panic - delta)
	_decision -= delta
	_voice -= delta
	if _voice <= 0.0:
		_voice = _rng.randf_range(8.0, 20.0)
		AudioManager.play_3d("native/sccsgoknives/Chicken/idle/chicken_idle_%02d.wav" % _rng.randi_range(1, 5), global_position, -14.0, 12.0)
	if _decision <= 0.0:
		_decision = _rng.randf_range(1.0, 3.0)
		_direction = Vector3.ZERO if _rng.randf() < 0.4 else Vector3.FORWARD.rotated(Vector3.UP, _rng.randf_range(-PI, PI))
	if global_position.distance_to(home) > 6.0:
		_direction = (home - global_position).normalized()
		_direction.y = 0.0
	var space := get_world_3d().direct_space_state
	if _direction.length_squared() > 0.01:
		var ahead := global_position + _direction * 0.6
		var wall := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, ahead + Vector3.UP * 0.2, 1)
		var floor_ray := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 0.3, ahead - Vector3.UP * 0.45, 1)
		var floor_hit := space.intersect_ray(floor_ray)
		if not space.intersect_ray(wall).is_empty() or floor_hit.is_empty() or floor_hit["normal"].y < 0.7:
			_direction = _direction.rotated(Vector3.UP, PI * 0.65)
			velocity.x = 0.0
			velocity.z = 0.0
		else:
			var speed := 2.1 if _panic > 0.0 else 0.65
			velocity.x = _direction.x * speed
			velocity.z = _direction.z * speed
			rotation.y = lerp_angle(rotation.y, atan2(_direction.x, _direction.z), minf(1.0, delta * 9.0))
	else:
		velocity.x = 0.0
		velocity.z = 0.0
	velocity.y -= 12.0 * delta
	move_and_slide()
	_play("run" if _panic > 0.0 else "walk" if Vector2(velocity.x, velocity.z).length() > 0.1 else "idle")
