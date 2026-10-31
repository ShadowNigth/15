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
	var st := GameData.get_sound(rel_path)
	if not st:
		return
	var p := _players_2d[_idx_2d]
	_idx_2d = (_idx_2d + 1) % POOL_2D_SIZE
	p.stream = st
	p.volume_db = vol_db + GameData.master_volume_db
	p.pitch_scale = pitch
	p.play()


func play_ui(sound_name: String) -> void:
	play_2d("ui/%s" % sound_name, -3.0)


func play_radio(rel_path: String) -> void:
	play_2d(rel_path, -1.5)


func play_3d(
	rel_path: String,
	world_pos: Vector3,
	vol_db: float = 0.0,
	max_dist: float = 55.0,
	pitch: float = 1.0,
	ai_hear_radius: float = 0.0,
	team: String = ""
) -> void:
	var st := GameData.get_sound(rel_path)
	if not st:
		return
	var p3 := _players_3d[_idx_3d]
	_idx_3d = (_idx_3d + 1) % POOL_3D_SIZE
	p3.global_position = world_pos
	p3.stream = st
	p3.volume_db = vol_db + GameData.master_volume_db
	p3.max_distance = max_dist
	p3.pitch_scale = pitch
	p3.play()

	if ai_hear_radius > 0.0:
		world_sound_emitted.emit(world_pos, ai_hear_radius, team)


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
