class_name PlantedC4
extends Node3D
## Planted C4 explosive on Bombsite A/B with accelerating CS 1.5 beep, red LED glow,
## CT defusal (10s standard / 5s with Defuse Kit), and detonation blast.

var time_left: float = 45.0
var defuser_actor: Node3D = null
var defuse_progress: float = 0.0
var defuse_required: float = 10.0

var _beep_timer: float = 1.0
var _led_sprite: Sprite3D = null
var _led_flash_timer: float = 0.0
var _exploded: bool = false
var _defused: bool = false


func _ready() -> void:
	time_left = GameData.c4_timer
	var sc := GameData.get_model_scene("weapons/w_c4")
	if sc:
		var inst := sc.instantiate()
		for c in inst.find_children("*", "MeshInstance3D", true, false):
			(c as MeshInstance3D).layers = 2
		add_child(inst)

	_led_sprite = Sprite3D.new()
	_led_sprite.texture = GameData.get_texture("res://assets/sprites/ledglow.png")
	_led_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_led_sprite.modulate = Color(1.0, 0.15, 0.1, 0.95)
	_led_sprite.pixel_size = 0.006
	_led_sprite.position = Vector3(0.0, 0.14, 0.0)
	_led_sprite.visible = false
	add_child(_led_sprite)

	AudioManager.play_3d("weapons/c4_plant.wav", global_position, 2.0, 48.0, 1.0, 32.0, "T")


func begin_or_continue_defuse(actor: Node3D, delta: float) -> float:
	if _exploded or _defused or not is_instance_valid(actor):
		return 0.0
	if defuser_actor != actor:
		defuser_actor = actor
		defuse_progress = 0.0
		defuse_required = 5.0 if bool(actor.get("has_defuser")) else 10.0
		AudioManager.play_3d("weapons/c4_disarm.wav", global_position, 0.0, 28.0, 1.0, 20.0, "CT")

	defuse_progress += delta
	if defuse_progress >= defuse_required:
		_defused = true
		AudioManager.play_3d("weapons/c4_disarmed.wav", global_position, 2.0, 40.0)
		RoundManager.notify_bomb_defused(actor)
		queue_free()
		return 1.0
	return clampf(defuse_progress / defuse_required, 0.0, 1.0)


func cancel_defuse(actor: Node3D) -> void:
	if defuser_actor == actor:
		defuser_actor = null
		defuse_progress = 0.0


func _process(delta: float) -> void:
	if _exploded or _defused:
		return

	# Reset defusal if defuser died or walked away
	if defuser_actor != null:
		if not is_instance_valid(defuser_actor) or not bool(defuser_actor.get("is_alive")) or defuser_actor.global_position.distance_to(global_position) > 2.8:
			defuser_actor = null
			defuse_progress = 0.0

	if _led_flash_timer > 0.0:
		_led_flash_timer -= delta
		if _led_flash_timer <= 0.0 and _led_sprite:
			_led_sprite.visible = false

	time_left -= delta
	if time_left <= 0.0:
		_detonate()
		return

	_beep_timer -= delta
	if _beep_timer <= 0.0:
		var ratio := clampf(1.0 - (time_left / maxf(1.0, GameData.c4_timer)), 0.0, 1.0)
		var beep_idx := clampi(1 + int(ratio * 4.99), 1, 5)
		AudioManager.play_3d("weapons/c4_beep%d.wav" % beep_idx, global_position, 1.5, 65.0, 1.0, 45.0, "T")
		_beep_timer = lerpf(1.45, 0.16, ratio * ratio)
		if _led_sprite:
			_led_sprite.visible = true
			_led_flash_timer = 0.10


func _detonate() -> void:
	_exploded = true
	AudioManager.play_3d("weapons/c4_explode1.wav", global_position, 6.0, 150.0)
	GrenadeProjectile.spawn_explosion_fx(get_parent(), global_position, 2.15)

	# Radial blast damage (CS 1.5 C4 radius ~54m = 1750 GoldSrc units)
	var max_r := 54.0
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		var a_node := a as Node3D
		if a_node == null:
			continue
		var d: float = a_node.global_position.distance_to(global_position)
		if d < max_r and a_node.has_method("apply_explosion_damage"):
			var dmg := 500.0 * pow(maxf(0.0, 1.0 - d / max_r), 1.65)
			if dmg > 1.0:
				a_node.call("apply_explosion_damage", null, dmg, "c4")

	RoundManager.notify_bomb_exploded()
	queue_free()
