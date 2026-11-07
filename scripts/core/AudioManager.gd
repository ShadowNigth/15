extends Node
## Pooled 2D & 3D spatial sound manager for Counter-Strike 1.5 audio.
## Also emits sound perception events so Bots IA hear footsteps, gunfire, and C4 beeps.

signal world_sound_emitted(world_pos: Vector3, radius: float, team: String)

const POOL_2D_SIZE: int = 12
const POOL_3D_SIZE: int = 32

var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _idx_2d: int = 0
var _idx_3d: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Preserve transient headroom when several guns/explosions overlap.
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -0.5
	limiter.threshold_db = -1.0
	AudioServer.add_bus_effect(0, limiter)
	for i in range(POOL_2D_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players_2d.append(p)

	for i in range(POOL_3D_SIZE):
		var p3 := AudioStreamPlayer3D.new()
		p3.bus = "Master"
		p3.unit_size = 6.5
		p3.max_distance = 55.0
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p3)
		_players_3d.append(p3)


func play_2d(rel_path: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	var sound_path := GameData.resolve_sound_path(rel_path)
	var st := GameData.get_sound(sound_path)
	if not st:
		return
	var p := _players_2d[_idx_2d]
	_idx_2d = (_idx_2d + 1) % POOL_2D_SIZE
	p.stream = st
	p.volume_db = vol_db + GameData.master_volume_db + GameData.sound_gain_db(sound_path)
	p.pitch_scale = pitch
	p.play()


func play_ui(sound_name: String) -> void:
	play_2d("ui/%s" % sound_name, -3.0)


func play_radio(rel_path: String, speaker_team: String = "") -> void:
	if speaker_team.is_empty():
		speaker_team = "CT"
		for actor in RoundManager.actors:
			if is_instance_valid(actor) and bool(actor.get("is_human")):
				speaker_team = String(actor.get("team"))
				break
	var commands := {
		"radio/ct_fireinhole.wav": "grenade", "radio/ct_coverme.wav": "radio.needbackup",
		"radio/com_go.wav": "radio.letsgo", "radio/letsgo.wav": "radio.letsgo",
		"radio/locknload.wav": "radio.letsgo", "radio/moveout.wav": "radio.letsgo",
		"radio/followme.wav": "radio.followme", "radio/ct_enemys.wav": "radio.enemyspotted",
		"radio/ct_backup.wav": "radio.needbackup", "radio/fireassis.wav": "radio.takingfire",
		"radio/roger.wav": "affirmative", "radio/negative.wav": "negative",
		"radio/enemydown.wav": "enemydown", "radio/position.wav": "waitinghere",
		"radio/inpos.wav": "inposition"
	}
	var command := String(commands.get(rel_path, ""))
	if not command.is_empty() and play_voice(command, speaker_team):
		return
	play_2d(rel_path, -1.5)


func play_voice(command: String, speaker_team: String) -> bool:
	var voices: Dictionary = GameData.native_audio.get("voices", {})
	var language := GameData.voice_language if voices.has(GameData.voice_language) else "en"
	var variants: Array = voices.get(language, {}).get(speaker_team.to_lower(), {}).get(command, [])
	if variants.is_empty():
		return false
	play_2d(String(variants.pick_random()), -1.5)
	return true


func cue_path(cue: String, fallback: String = "") -> String:
	var variants: Array = GameData.native_audio.get("cues", {}).get(cue, [])
	return String(variants.pick_random()) if not variants.is_empty() else fallback


func play_cue_3d(cue: String, pos: Vector3, vol_db: float = 0.0, max_dist: float = 55.0, hear_radius: float = 0.0, team: String = "") -> void:
	play_3d(cue_path(cue), pos, vol_db, max_dist, 1.0, hear_radius, team)


func play_3d(
	rel_path: String,
	world_pos: Vector3,
	vol_db: float = 0.0,
	max_dist: float = 55.0,
	pitch: float = 1.0,
	ai_hear_radius: float = 0.0,
	team: String = ""
) -> void:
	var sound_path := GameData.resolve_sound_path(rel_path)
	var st := GameData.get_sound(sound_path)
	if not st:
		return
	var p3 := _players_3d[_idx_3d]
	_idx_3d = (_idx_3d + 1) % POOL_3D_SIZE
	p3.global_position = world_pos
	p3.stream = st
	p3.volume_db = vol_db + GameData.master_volume_db + GameData.sound_gain_db(sound_path)
	p3.max_distance = max_dist
	p3.pitch_scale = pitch
	p3.play()

	if ai_hear_radius > 0.0:
		world_sound_emitted.emit(world_pos, ai_hear_radius, team)


func stop_all() -> void:
	# Scene transitions and isolated native tests must also release map-ambient
	# players, not only this manager's pools, before the audio thread shuts down.
	_stop_audio_branch(get_tree().root)


func _stop_audio_branch(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
		(node as AudioStreamPlayer).stream = null
	elif node is AudioStreamPlayer3D:
		(node as AudioStreamPlayer3D).stop()
		(node as AudioStreamPlayer3D).stream = null
	for child in node.get_children():
		_stop_audio_branch(child)


func play_footstep(mat_char: String, world_pos: Vector3, team: String) -> void:
	var prefix := "player/pl_step"
	var count := 4
	match mat_char:
		"M":
			prefix = "player/pl_metal"
		"D":
			prefix = "player/pl_dirt"
		"T":
			prefix = "player/pl_tile"
			count = 5
		"W", "V":
			prefix = "player/pl_duct"
		"G":
			prefix = "player/pl_grate"
		"S":
			prefix = "player/pl_snow"
			count = 6
		"L":
			prefix = "player/pl_ladder"
		"P":
			prefix = "player/pl_slosh"
	var idx := randi_range(1, count)
	play_3d("%s%d.wav" % [prefix, idx], world_pos, -5.0, 24.0, randf_range(0.96, 1.04), 16.0, team)


func stop_viewmodel_audio(owner_node: Node) -> void:
	var branch := owner_node.get_node_or_null("NativeViewmodelFoley")
	if branch != null:
		for child in branch.get_children():
			if child is AudioStreamPlayer:
				(child as AudioStreamPlayer).stop()
			child.queue_free()


func play_viewmodel_audio(owner_node: Node, path: String, pitch: float = 1.0) -> void:
	var stream := GameData.get_sound(path)
	if stream == null:
		return
	var branch := owner_node.get_node_or_null("NativeViewmodelFoley")
	if branch == null:
		branch = Node.new()
		branch.name = "NativeViewmodelFoley"
		owner_node.add_child(branch)
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = -2.2 + GameData.master_volume_db + GameData.sound_gain_db(path)
	player.pitch_scale = pitch
	branch.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
