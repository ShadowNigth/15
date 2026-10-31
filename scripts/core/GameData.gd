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
var invert_mouse_y: bool = false
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
var _styled_mat_cache: Dictionary = {}


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


func get_styled_model_material(orig: Material, mode: String) -> Material:
	if orig == null or not (orig is BaseMaterial3D):
		return orig
	var key := "%d_%s" % [orig.get_instance_id(), mode]
	if _styled_mat_cache.has(key):
		return _styled_mat_cache[key] as Material
	var dup := orig.duplicate() as BaseMaterial3D
	dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	dup.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	dup.roughness = 0.92
	dup.metallic = 0.0
	if mode == "vm":
		dup.cull_mode = BaseMaterial3D.CULL_BACK
		dup.albedo_color = Color(1.38, 1.38, 1.38, 1.0)
	elif mode == "vm_flip":
		dup.cull_mode = BaseMaterial3D.CULL_FRONT
		dup.albedo_color = Color(1.38, 1.38, 1.38, 1.0)
	else:
		dup.cull_mode = BaseMaterial3D.CULL_BACK
		dup.albedo_color = Color(1.48, 1.48, 1.48, 1.0)
	_styled_mat_cache[key] = dup
	return dup


func ensure_looping_animations(ap: AnimationPlayer) -> void:
	if not ap:
		return
	for aname in ap.get_animation_list():
		var low := aname.to_lower()
		var anim := ap.get_animation(aname)
		if not anim:
			continue
		if "die" in low or "death" in low or low in ["head", "gutshot"] or "shoot" in low or "aim" in low:
			anim.loop_mode = Animation.LOOP_NONE
		elif low.begins_with("idle") or low.begins_with("walk") or low.begins_with("run") or low.begins_with("crouch_idle") or low.begins_with("crouchrun"):
			anim.loop_mode = Animation.LOOP_LINEAR


func get_smoke_cloud_texture() -> Texture2D:
	return get_smoke_cloud_variant(0)


func get_smoke_cloud_variant(variant_idx: int) -> Texture2D:
	var v_clamped: int = posmod(variant_idx, 4)
	var ckey: String = "__proc_smoke_cloud_%d" % v_clamped
	if _tex_cache.has(ckey):
		return _tex_cache[ckey] as Texture2D

	var seeds := [15015, 29311, 44701, 61909]
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)

	var warp_noise := FastNoiseLite.new()
	warp_noise.seed = int(seeds[v_clamped]) + 701
	warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	warp_noise.fractal_octaves = 2
	warp_noise.frequency = 0.026

	var noise := FastNoiseLite.new()
	noise.seed = int(seeds[v_clamped])
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.frequency = 0.038

	var half := float(sz) * 0.5
	for y in range(sz):
		for x in range(sz):
			var fx := float(x) + 0.5
			var fy := float(y) + 0.5
			var dx := (fx - half) / half
			var dy := (fy - half) / half
			var r := sqrt(dx * dx + dy * dy)
			if r >= 0.99:
				img.set_pixel(x, y, Color(0.84, 0.86, 0.88, 0.0))
				continue

			# Domain-warped coordinates produce authentic curling cauliflower smoke billows!
			var wx := fx + warp_noise.get_noise_2d(fx, fy) * 16.5
			var wy := fy + warp_noise.get_noise_2d(fx + 93.0, fy - 57.0) * 16.5
			var n := noise.get_noise_2d(wx, wy) * 0.5 + 0.5
			var n_fine := noise.get_noise_2d(wx * 2.15 + 41.0, wy * 2.15 - 29.0) * 0.5 + 0.5

			# Organic lobed silhouette with zero hard card edges
			var lobe_perturb := (n - 0.5) * 0.34 * smoothstep(0.10, 0.78, r) + (n_fine - 0.5) * 0.12 * smoothstep(0.25, 0.90, r)
			var eff_r := r + lobe_perturb
			var radial_env := 1.0 - smoothstep(0.24, 0.95, eff_r)
			var soft_outer := 1.0 - smoothstep(0.76, 0.99, r)
			var alpha := clampf(radial_env * soft_outer * (0.82 + 0.28 * n_fine), 0.0, 0.96)

			# Rich volumetric self-shading: sunlit silver crown, cool slate creases & belly
			var crease := smoothstep(0.22, 0.82, n * 0.72 + n_fine * 0.28)
			var shade := clampf(0.74 + 0.19 * crease - 0.11 * dy - 0.06 * r, 0.58, 0.98)
			img.set_pixel(x, y, Color(shade * 0.985, shade, shade * 1.022, alpha))

	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[ckey] = tex
	return tex


func _sample_seamless_2d(n: FastNoiseLite, u: float, v: float, period: float) -> float:
	var su := u * u * (3.0 - 2.0 * u)
	var sv := v * v * (3.0 - 2.0 * v)
	var px := u * period
	var py := v * period
	var n00 := n.get_noise_2d(px, py)
	var n10 := n.get_noise_2d(px - period, py)
	var n01 := n.get_noise_2d(px, py - period)
	var n11 := n.get_noise_2d(px - period, py - period)
	var nx0 := lerpf(n00, n10, su)
	var nx1 := lerpf(n01, n11, su)
	return clampf(lerpf(nx0, nx1, sv) * 0.5 + 0.5, 0.0, 1.0)


func get_cs2_smoke_noise_texture() -> Texture2D:
	if _tex_cache.has("__cs2_smoke_noise_rgb"):
		return _tex_cache["__cs2_smoke_noise_rgb"] as Texture2D

	var sz := 96
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)

	var n_low := FastNoiseLite.new()
	n_low.seed = 31337
	n_low.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_low.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_low.fractal_octaves = 3
	n_low.frequency = 0.036

	var n_mid := FastNoiseLite.new()
	n_mid.seed = 77419
	n_mid.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n_mid.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_mid.fractal_octaves = 4
	n_mid.frequency = 0.068

	var n_cell := FastNoiseLite.new()
	n_cell.seed = 94111
	n_cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	n_cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	n_cell.frequency = 0.085

	var period := float(sz)
	for y in range(sz):
		var v := float(y) / period
		for x in range(sz):
			var u := float(x) / period
			var ch_r := _sample_seamless_2d(n_low, u, v, period)
			var ch_g := _sample_seamless_2d(n_mid, u, v, period)
			var cell_raw := _sample_seamless_2d(n_cell, u, v, period)
			var ch_b := clampf(1.0 - cell_raw * 1.15, 0.0, 1.0)
			img.set_pixel(x, y, Color(ch_r, ch_g, ch_b, 1.0))

	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["__cs2_smoke_noise_rgb"] = tex
	return tex


func get_cs2_smoke_material() -> ShaderMaterial:
	if _styled_mat_cache.has("__cs2_smoke_shader_mat"):
		return _styled_mat_cache["__cs2_smoke_shader_mat"] as ShaderMaterial
	var sh := load("res://assets/shaders/cs2_smoke.gdshader") as Shader
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("noise_tex", get_cs2_smoke_noise_texture())
	_styled_mat_cache["__cs2_smoke_shader_mat"] = sm
	return sm


func get_shockwave_ring_texture() -> Texture2D:
	if _tex_cache.has("__proc_shock_ring"):
		return _tex_cache["__proc_shock_ring"] as Texture2D
	var sz := 128
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz) * 0.5
	for y in range(sz):
		for x in range(sz):
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var ring := exp(-pow((r - 0.72) / 0.13, 2.0)) * (1.0 - smoothstep(0.90, 1.0, r))
			var inner := (1.0 - smoothstep(0.0, 0.65, r)) * 0.22
			var a := clampf(ring + inner, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.78, 0.42, a))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["__proc_shock_ring"] = tex
	return tex


func get_scorch_decal_texture() -> Texture2D:
	if _tex_cache.has("__proc_scorch"):
		return _tex_cache["__proc_scorch"] as Texture2D
	var sz := 96
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 909
	noise.frequency = 0.075
	var half := float(sz) * 0.5
	for y in range(sz):
		for x in range(sz):
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var ang := atan2(dy, dx)
			var streak := noise.get_noise_2d(cos(ang) * 26.0, sin(ang) * 26.0) * 0.18
			var a := (1.0 - smoothstep(0.18, 0.92, r + streak)) * 0.88
			img.set_pixel(x, y, Color(0.05, 0.04, 0.04, clampf(a, 0.0, 0.90)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache["__proc_scorch"] = tex
	return tex


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
