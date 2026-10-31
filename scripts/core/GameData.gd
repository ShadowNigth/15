extends Node
## Central database & resource cache for Counter-Strike 1.5 (Godot 4 Remake).
## Loads all extracted JSON metadata from res://data/ and caches textures, models, and HUD atlases.

const SCALE: float = 1.0 / 32.0

var weapons: Dictionary = {}
var ammo_types: Dictionary = {}
var equipment: Dictionary = {}
var economy: Dictionary = {}
var classes: Dictionary = {}
var maps_index: Array = []
var overviews: Dictionary = {}
var hud_sprites: Dictionary = {}
var weapon_hud: Dictionary = {}
var materials_map: Dictionary = {}
var radio_menus: Dictionary = {}
var titles: Dictionary = {}
var world_textures_meta: Dictionary = {}
var models_meta: Dictionary = {}

# Match / User settings
var selected_map: String = "de_dust2"
var bot_count: int = 9  # 9 bots + 1 player = 5v5 classic match
var bot_difficulty: int = 1  # 0=Easy, 1=Normal, 2=Hard, 3=Expert
var start_money: int = 800
var freeze_time: float = 4.0
var round_time: float = 135.0
var c4_timer: float = 45.0
var friendly_fire: bool = false

# Player preferences
var mouse_sensitivity: float = 0.16
var master_volume_db: float = 0.0
var fov: float = 74.0  # Vertical FOV 74 deg = authentic CS 1.5 horizontal 90 deg (4:3) / 106 deg (16:9 Hor+)
var right_hand: bool = true  # cl_righthand 1
var dynamic_crosshair: bool = true
var crosshair_color: Color = Color(0.2, 1.0, 0.2, 0.92)
var player_name: String = "Player"

# Resource caches
var _tex_cache: Dictionary = {}
var _scene_cache: Dictionary = {}
var _hud_atlas_cache: Dictionary = {}
var _wav_cache: Dictionary = {}


func _ready() -> void:
	_ensure_input_map()
	_load_all_databases()


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[GameData] Missing JSON file: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	return parsed if parsed != null else {}


func _load_all_databases() -> void:
	var wdb: Dictionary = _load_json("res://data/weapons.json")
	weapons = wdb.get("weapons", {})
	ammo_types = wdb.get("ammo", {})
	equipment = wdb.get("equipment", {})
	economy = wdb.get("economy", {})

	classes = _load_json("res://data/classes.json")
	var midx = _load_json("res://data/maps_index.json")
	if midx is Array:
		maps_index = midx
	overviews = _load_json("res://data/overviews.json")

	var hdb: Dictionary = _load_json("res://data/hud_sprites.json")
	hud_sprites = hdb.get("hud", {})
	weapon_hud = hdb.get("weapons", {})

	materials_map = _load_json("res://data/materials.json")
	radio_menus = _load_json("res://data/radio.json")
	titles = _load_json("res://data/titles.json")
	world_textures_meta = _load_json("res://data/world_textures.json")
	models_meta = _load_json("res://data/models_meta.json")


func load_map_data(map_name: String) -> Dictionary:
	var p := "res://data/maps/%s.json" % map_name.to_lower()
	var res = _load_json(p)
	return res if res is Dictionary else {}


func get_texture(res_path: String) -> Texture2D:
	if res_path.is_empty():
		return null
	if _tex_cache.has(res_path):
		return _tex_cache[res_path]
	if not ResourceLoader.exists(res_path):
		return null
	var tex := load(res_path) as Texture2D
	if tex:
		_tex_cache[res_path] = tex
	return tex


func get_model_scene(rel_path: String) -> PackedScene:
	var full := rel_path if rel_path.begins_with("res://") else ("res://assets/models/%s.glb" % rel_path)
	if _scene_cache.has(full):
		return _scene_cache[full]
	if not ResourceLoader.exists(full):
		return null
	var sc := load(full) as PackedScene
	if sc:
		_scene_cache[full] = sc
	return sc


func get_sound(rel_path: String) -> AudioStream:
	if rel_path.is_empty():
		return null
	var full := rel_path if rel_path.begins_with("res://") else ("res://assets/sounds/%s" % rel_path.to_lower())
	if _wav_cache.has(full):
		return _wav_cache[full]
	if not ResourceLoader.exists(full):
		return null
	var st := load(full) as AudioStream
	if st:
		_wav_cache[full] = st
	return st


func get_hud_atlas(entry_name: String, prefer_res: int = 640) -> AtlasTexture:
	var key := "%s_%d" % [entry_name, prefer_res]
	if not hud_sprites.has(key):
		key = "%s_320" % entry_name
		if not hud_sprites.has(key):
			key = "%s_640" % entry_name
	if _hud_atlas_cache.has(key):
		return _hud_atlas_cache[key]
	if not hud_sprites.has(key):
		return null
	var info: Dictionary = hud_sprites[key]
	var spr_path := "res://assets/sprites/%s.png" % String(info.get("sprite", ""))
	var base_tex := get_texture(spr_path)
	if not base_tex:
		return null
	var r: Array = info.get("rect", [0, 0, 16, 16])
	var atlas := AtlasTexture.new()
	atlas.atlas = base_tex
	atlas.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_hud_atlas_cache[key] = atlas
	return atlas


func get_weapon_hud_atlas(weapon_id: String, field: String = "weapon_640") -> AtlasTexture:
	var ckey := "whud_%s_%s" % [weapon_id, field]
	if _hud_atlas_cache.has(ckey):
		return _hud_atlas_cache[ckey]
	var wdict: Dictionary = weapon_hud.get("weapon_" + weapon_id, {})
	if not wdict.has(field):
		field = "weapon_320"
	if not wdict.has(field):
		return null
	var info: Dictionary = wdict[field]
	var spr_path := "res://assets/sprites/%s.png" % String(info.get("sprite", ""))
	var base_tex := get_texture(spr_path)
	if not base_tex:
		return null
	var r: Array = info.get("rect", [0, 0, 80, 20])
	var atlas := AtlasTexture.new()
	atlas.atlas = base_tex
	atlas.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	_hud_atlas_cache[ckey] = atlas
	return atlas


func get_material_char(tex_name: String) -> String:
	var clean := tex_name.to_lower()
	clean = clean.trim_prefix("mask_").trim_prefix("water_").trim_prefix("anim_").trim_prefix("lgt_")
	if materials_map.has(clean):
		return String(materials_map[clean])
	for k in materials_map.keys():
		if clean.begins_with(k) or k.begins_with(clean.substr(0, min(8, clean.length()))):
			return String(materials_map[k])
	if "metal" in clean or "steel" in clean or "vent" in clean or "duct" in clean:
		return "M"
	if "wood" in clean or "crate" in clean:
		return "W"
	if "sand" in clean or "dirt" in clean or "grass" in clean or "rock" in clean:
		return "D"
	if "snow" in clean or "ice" in clean:
		return "S"
	if "tile" in clean or "marble" in clean:
		return "T"
	if "grate" in clean or "fence" in clean:
		return "G"
	return "C"  # Concrete default


func _ensure_input_map() -> void:
	var bindings := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"crouch": [KEY_CTRL],
		"walk": [KEY_SHIFT],
		"reload": [KEY_R],
		"use": [KEY_E],
		"drop": [KEY_G],
		"buy_menu": [KEY_B],
		"buy_ammo1": [KEY_COMMA],
		"buy_ammo2": [KEY_PERIOD],
		"team_menu": [KEY_M],
		"last_weapon": [KEY_Q],
		"flashlight": [KEY_F],
		"nightvision": [KEY_N],
		"scoreboard": [KEY_TAB],
		"slot_1": [KEY_1],
		"slot_2": [KEY_2],
		"slot_3": [KEY_3],
		"slot_4": [KEY_4],
		"slot_5": [KEY_5],
		"slot_6": [KEY_6],
		"slot_7": [KEY_7],
		"slot_8": [KEY_8],
		"slot_9": [KEY_9],
		"slot_0": [KEY_0],
		"radio_1": [KEY_Z],
		"radio_2": [KEY_X],
		"radio_3": [KEY_C],
	}
	for act in bindings.keys():
		if not InputMap.has_action(act):
			InputMap.add_action(act)
			for kc in bindings[act]:
				var ev := InputEventKey.new()
				ev.physical_keycode = kc
				InputMap.action_add_event(act, ev)

	if not InputMap.has_action("attack1"):
		InputMap.add_action("attack1")
		var m1 := InputEventMouseButton.new()
		m1.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack1", m1)

	if not InputMap.has_action("attack2"):
		InputMap.add_action("attack2")
		var m2 := InputEventMouseButton.new()
		m2.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event("attack2", m2)
