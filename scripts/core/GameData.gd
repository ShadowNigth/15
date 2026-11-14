extends Node
## Central database & resource cache for Counter-Strike 1.5 (Godot 4 Remake).
## Loads all extracted JSON metadata from res://data/ and caches textures, models, and HUD atlases.

const SCALE: float = 1.0 / 32.0
## Held/thrown grenades stay slightly compact; floor pickups use their own
## larger scale so they remain easy to see without changing projectile behavior.
const GRENADE_WORLD_SCALE: float = 0.90
const GRENADE_DROP_SCALE: float = 1.0
const MOLOTOV_GLASS_FLIP_SHADER: Shader = preload("res://assets/shaders/molotov_glass_flip.gdshader")
const MOLOTOV_LIQUID_FLIP_SHADER: Shader = preload("res://assets/shaders/molotov_liquid_flip.gdshader")
const MOLOTOV_GLASS_SHADER: Shader = preload("res://assets/shaders/molotov_glass.gdshader")
const MOLOTOV_LIQUID_SHADER: Shader = preload("res://assets/shaders/molotov_liquid.gdshader")

var native_audio: Dictionary = {}
var voice_language: String = "en"
var weapons: Dictionary = {}
var ammo_types: Dictionary = {}
var equipment: Dictionary = {}
var economy: Dictionary = {}
var classes: Dictionary = {}
var modern_agents: Dictionary = {}
var maps_index: Array = []
var overviews: Dictionary = {}
var hud_sprites: Dictionary = {}
var weapon_hud: Dictionary = {}
var materials_map: Dictionary = {}
var radio_menus: Dictionary = {}
var titles: Dictionary = {}
var world_textures_meta: Dictionary = {}
var models_meta: Dictionary = {}
## Shared high-resolution archi weapon textures, keyed by Source material name.
var archi_materials: Dictionary = {}
## Sport_gloves catalog and the local player's choice for subsequent matches.
var sport_gloves: Dictionary = {}
var selected_glove_id: String = ""
## Authentic UV-mapped weapon finishes, selected independently per weapon.
var weapon_skins: Dictionary = {}
var selected_weapon_skins: Dictionary = {}
var _skin_material_owners: Dictionary = {}
## Knife appearances share the classic slot, economy and melee rules.
var knife_models: Dictionary = {}
var selected_knife_id: String = "original"
var _original_knife_spec: Dictionary = {}

# Match / User settings
# Phase one: only grounded acceleration/braking. Air, jump and BSP movement remain classic.
var movement_profile: String = "cs2_experimental"
# Cosmetic preview context, independent from selected gloves and match team.
var view_agent_class: String = "sas"
var view_agent_team: String = "CT"
var game_mode: String = "classic" # classic / deathmatch (team DM)
var dm_frag_limit: int = 40
var dm_time_limit: float = 600.0
var dm_primary: String = "ak47"
var selected_map: String = "de_dust2"
var bot_count: int = 9  # 9 bots + 1 player = 5v5 classic match
var bot_difficulty: int = 1  # 0=Easy, 1=Normal, 2=Hard, 3=Expert
var start_money: int = 800
var freeze_time: float = 4.0
var round_time: float = 135.0
var c4_timer: float = 45.0
var friendly_fire: bool = false

# Cosmetic world resources (no weapon/economy changes).
var native_casings: Dictionary = {}
var native_casings_enabled: bool = true
var native_ammo_icons: bool = false
var low_ammo_warning: bool = true
var ambient_chickens_enabled: bool = false
var native_defuser_model: bool = true

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
	_warn_if_assets_missing()
	_ensure_input_map()
	_load_all_databases()
	_load_cosmetic_preferences()


func _warn_if_assets_missing() -> void:
	# Models, maps, textures and sounds are stored compressed in res://packs and
	# must be restored into res://assets once (see docs/ASSET_PACKS.md).
	if DirAccess.dir_exists_absolute("res://assets/models") or ResourceLoader.exists("res://assets/sprites/ledglow.png"):
		return
	var message := "No se encuentra la carpeta assets/.\n\nCierra Godot, ejecuta unpack_assets.bat (Windows) o ./unpack_assets.sh (Linux/macOS) — equivale a `python tools/pak.py unpack` — y vuelve a abrir el proyecto."
	push_error("[GameData] " + message)
	if DisplayServer.get_name() != "headless":
		OS.alert(message, "Counter-Strike 1.5 — assets sin desempaquetar")


func _load_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("[GameData] Missing JSON file: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	return parsed if parsed != null else {}


func _load_all_databases() -> void:
	native_casings = _load_json("res://data/native_casings.json")
	var wdb: Dictionary = _load_json("res://data/weapons.json")
	weapons = wdb.get("weapons", {})
	ammo_types = wdb.get("ammo", {})
	equipment = wdb.get("equipment", {})
	economy = wdb.get("economy", {})

	classes = _load_json("res://data/classes.json")
	modern_agents = _load_json("res://data/modern_agents.json")
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
	var archi_db: Dictionary = _load_json("res://data/archi_materials.json")
	archi_materials = archi_db.get("materials", {})
	sport_gloves = _load_json("res://data/sport_gloves.json")
	if selected_glove_id.is_empty() or selected_glove_id.begins_with("cs2go_5030_"):
		selected_glove_id = String(sport_gloves.get("default", "classic"))
	native_audio = _load_json("res://data/native_audio.json")
	_apply_native_audio()
	knife_models = _load_json("res://data/knife_models.json")
	_original_knife_spec = (weapons.get("knife", {}) as Dictionary).duplicate(true)
	if not select_knife(selected_knife_id):
		select_knife("original")
	weapon_skins = _load_json("res://data/weapon_skins.json")
	_skin_material_owners.clear()
	var skin_weapons: Dictionary = weapon_skins.get("weapons", {})
	for raw_wid in skin_weapons:
		var entry: Dictionary = skin_weapons[raw_wid]
		for raw_material in entry.get("materials", []):
			_skin_material_owners[String(raw_material).to_lower()] = String(raw_wid)


func _apply_native_audio() -> void:
	# Sound-only overlays: source assets/gameplay data remain independently rebuildable.
	for wid in native_audio.get("weapons", {}):
		if weapons.has(wid):
			weapons[wid].merge(native_audio["weapons"][wid], true)
	for model in native_audio.get("model_events", {}):
		if models_meta.has(model):
			var events: Dictionary = models_meta[model].get("seq_events", {}).duplicate(true)
			events.merge(native_audio["model_events"][model], true)
			models_meta[model]["seq_events"] = events


func sound_variant(event: Dictionary) -> String:
	var variants: Array = event.get("variants", [])
	return String(variants.pick_random()) if not variants.is_empty() else String(event.get("wav", ""))


func sound_gain_db(path: String) -> float:
	return float(native_audio.get("gains", {}).get(path.trim_prefix("res://assets/sounds/").to_lower(), 0.0))


func resolve_sound_path(rel_path: String) -> String:
	var key := rel_path.trim_prefix("res://assets/sounds/").to_lower()
	var replacements: Array = native_audio.get("replacements", {}).get(key, [])
	return String(replacements.pick_random()) if not replacements.is_empty() else key


func get_knife_options() -> Array:
	return knife_models.get("options", []) as Array


func select_knife(option_id: String) -> bool:
	for raw in get_knife_options():
		var option := raw as Dictionary
		if String(option.get("id", "")) != option_id:
			continue
		var spec := _original_knife_spec.duplicate(true)
		for field in ["v_model", "p_model", "w_model"]:
			spec[field] = String(option[field])
		if option_id != "original":
			spec["name"] = String(option["name"])
		weapons["knife"] = spec
		selected_knife_id = option_id
		return true
	return false


func get_knife_glove_model(viewmodel_name: String) -> String:
	# New fixed-blade knives retain exactly the original rig and arm surfaces.
	for raw in get_knife_options():
		if String((raw as Dictionary).get("v_model", "")) == viewmodel_name:
			return "v_knife"
	return viewmodel_name


func get_glove_options() -> Array:
	return sport_gloves.get("options", []) as Array


func get_selected_glove() -> Dictionary:
	if selected_glove_id == String(sport_gloves.get("classic_id", "classic")):
		return {}
	for raw in get_glove_options():
		var option := raw as Dictionary
		if String(option.get("id", "")) == selected_glove_id:
			return option
	return {}


func get_glove_display_name() -> String:
	var selected := get_selected_glove()
	return String(selected.get("name", "Original Counter-Strike Gloves"))


func select_glove(option_id: String) -> bool:
	if option_id == String(sport_gloves.get("classic_id", "classic")):
		selected_glove_id = option_id
		return true
	for raw in get_glove_options():
		if String((raw as Dictionary).get("id", "")) == option_id:
			selected_glove_id = option_id
			return true
	return false


func get_sport_glove_source_material(orig: Material, option: Dictionary) -> Material:
	if orig == null or not (orig is BaseMaterial3D):
		return orig
	var source := orig as BaseMaterial3D
	var material_name := source.resource_name.to_lower()
	var key := "sport_%s_%s" % [String(option.get("id", "")), material_name]
	if _styled_mat_cache.has(key):
		return _styled_mat_cache[key] as Material
	var textures: Dictionary = option.get("textures", {})
	if not textures.has(material_name):
		return null
	var dup := source.duplicate() as BaseMaterial3D
	dup.albedo_texture = get_texture(String(textures[material_name]))
	if dup.albedo_texture == null:
		return null
	dup.albedo_color = Color.WHITE
	_styled_mat_cache[key] = dup
	return dup


func _weapon_skin_key(wid: String) -> String:
	return "knife_" + selected_knife_id if wid == "knife" and selected_knife_id != "original" else wid


func get_weapon_skin_options(wid: String) -> Array:
	wid = _weapon_skin_key(wid)
	var entry: Dictionary = weapon_skins.get("weapons", {}).get(wid, {})
	return entry.get("options", []) as Array


func get_selected_weapon_skin_id(wid: String) -> String:
	wid = _weapon_skin_key(wid)
	var original := String(weapon_skins.get("default", "original"))
	var selected := String(selected_weapon_skins.get(wid, original))
	for raw in get_weapon_skin_options(wid):
		if String((raw as Dictionary).get("id", "")) == selected:
			return selected
	return original


func get_selected_weapon_skin(wid: String) -> Dictionary:
	var selected := get_selected_weapon_skin_id(wid)
	if selected == String(weapon_skins.get("default", "original")):
		return {}
	for raw in get_weapon_skin_options(wid):
		var option := raw as Dictionary
		if String(option.get("id", "")) == selected:
			return option
	return {}


func get_weapon_skin_display_name(wid: String) -> String:
	var selected := get_selected_weapon_skin(wid)
	return String(selected.get("name", "Original HD"))


func select_weapon_skin(wid: String, option_id: String) -> bool:
	wid = _weapon_skin_key(wid)
	var original := String(weapon_skins.get("default", "original"))
	if option_id == original and weapon_skins.get("weapons", {}).has(wid):
		selected_weapon_skins.erase(wid)
		return true
	for raw in get_weapon_skin_options(wid):
		if String((raw as Dictionary).get("id", "")) == option_id:
			selected_weapon_skins[wid] = option_id
			return true
	return false


func _selected_skin_for_material(material_name: String) -> Dictionary:
	var wid := String(_skin_material_owners.get(material_name, ""))
	return get_selected_weapon_skin(wid) if not wid.is_empty() else {}


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
	# Appearance aliases retain class IDs/rules and automatic faction selection.
	if rel_path.begins_with("players/"):
		var cid := rel_path.trim_prefix("players/")
		var avatar := String(modern_agents.get("classes", {}).get(cid, ""))
		if not avatar.is_empty():
			var modern_path := "modern/" + avatar
			if ResourceLoader.exists("res://assets/models/%s.glb" % modern_path):
				rel_path = modern_path
	var full := rel_path if rel_path.begins_with("res://") else ("res://assets/models/%s.glb" % rel_path)
	if _scene_cache.has(full):
		return _scene_cache[full]
	if not ResourceLoader.exists(full):
		return null
	var sc := load(full) as PackedScene
	if sc:
		_scene_cache[full] = sc
	return sc


func get_world_model_scale(wid: String) -> float:
	var spec: Dictionary = weapons.get(wid, {})
	if bool(spec.get("grenade", false)):
		return GRENADE_WORLD_SCALE
	# Every presentation of the same weapon reads this value, including the hand
	# attachment and dropped mesh. Normal firearms/tools ship at 1.0; the bound
	# only protects against malformed experimental calibration data.
	return clampf(float(spec.get("world_scale", 1.0)), 0.45, 1.0)


func get_dropped_model_scale(wid: String) -> float:
	var spec: Dictionary = weapons.get(wid, {})
	if bool(spec.get("grenade", false)):
		return GRENADE_DROP_SCALE
	return get_world_model_scale(wid)


func get_styled_model_material(orig: Material, mode: String) -> Material:
	if orig == null or not (orig is BaseMaterial3D):
		return orig
	var source := orig as BaseMaterial3D
	var material_name := source.resource_name.to_lower()
	var skin_wid := String(_skin_material_owners.get(material_name, ""))
	var skin_id := get_selected_weapon_skin_id(skin_wid) if not skin_wid.is_empty() else ""
	var key := "%d_%s" % [source.get_instance_id(), mode]
	if not skin_id.is_empty():
		key += "_" + skin_id
	if _styled_mat_cache.has(key):
		return _styled_mat_cache[key] as Material
	var archi_entry: Dictionary = archi_materials.get(material_name, {})
	var skin_entry := _selected_skin_for_material(material_name)
	var hd_albedo: Texture2D = source.albedo_texture
	if archi_entry.has("color"):
		var enhanced := get_texture(String(archi_entry["color"]))
		if enhanced != null:
			hd_albedo = enhanced
	if not skin_entry.is_empty():
		var skin_texture := get_texture(String(skin_entry.get("texture", "")))
		if skin_texture != null:
			hd_albedo = skin_texture
	if material_name in ["weapon_molotov", "weapon_molotov_liquid"]:
		var glass := ShaderMaterial.new()
		glass.shader = MOLOTOV_GLASS_FLIP_SHADER if mode == "vm_flip" else MOLOTOV_GLASS_SHADER
		glass.set_shader_parameter("bottle_texture", hd_albedo)
		glass.set_shader_parameter("bottle_tint", source.albedo_color)
		glass.set_shader_parameter("glass_tint", Vector3(0.46, 1.12, 0.56))
		glass.set_shader_parameter("glass_opacity", 0.72 if material_name == "weapon_molotov" else 0.58)
		glass.set_shader_parameter("refraction_strength", 0.018 if material_name == "weapon_molotov" else 0.012)
		glass.set_shader_parameter("brightness", 1.12 if mode in ["vm", "vm_flip"] else 1.06)
		# Draw the liquid first, then the intermediate green surface, then the
		# outer glass/label. The source's second surface must not stay alpha-masked.
		glass.render_priority = 2 if material_name == "weapon_molotov" else 1
		_styled_mat_cache[key] = glass
		return glass
	if material_name == "molotov_inside":
		var liquid := ShaderMaterial.new()
		liquid.shader = MOLOTOV_LIQUID_FLIP_SHADER if mode == "vm_flip" else MOLOTOV_LIQUID_SHADER
		liquid.set_shader_parameter("liquid_texture", hd_albedo)
		liquid.set_shader_parameter("liquid_tint", Color(source.albedo_color.r * 0.72, source.albedo_color.g * 0.94, source.albedo_color.b * 0.58, source.albedo_color.a))
		liquid.set_shader_parameter("brightness", 1.16 if mode in ["vm", "vm_flip"] else 1.08)
		liquid.set_shader_parameter("deformation", 1.0 if mode in ["vm", "vm_flip"] else 0.0)
		liquid.set_shader_parameter("opacity", 0.58 if mode in ["vm", "vm_flip"] else 0.52)
		liquid.set_shader_parameter("refraction_strength", 0.008)
		liquid.render_priority = 0
		_styled_mat_cache[key] = liquid
		return liquid

	var dup := orig.duplicate() as BaseMaterial3D
	dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if bool(orig.get_meta("native_moto_pbr", false)):
		# The native paint supplies normal, roughness, metal and AO maps.
		# Do not replace its leather/pad response with the old glove scalar.
		dup.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		dup.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_styled_mat_cache[key] = dup
		return dup
	dup.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	dup.roughness = 0.92
	dup.metallic = 0.0
	# Multiply the imported colour instead of replacing it. Several archi VMTs
	# use baseColorFactor for essential detail (notably black scope lenses).
	var original := dup.albedo_color
	if mode in ["vm", "vm_flip", "w_held", "w_drop"]:
		dup.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
		dup.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	if mode == "vm":
		dup.cull_mode = BaseMaterial3D.CULL_BACK
		# Chrome stays beneath the original albedo artwork. The studio sky still
		# supplies real reflections, but the texture's own colour and contrast
		# remain dominant instead of being replaced by a silver/white surface.
		dup.roughness = 0.22
		dup.metallic = 0.68
		dup.metallic_specular = 0.86
		dup.albedo_color = original
	elif mode == "vm_flip":
		dup.cull_mode = BaseMaterial3D.CULL_FRONT
		dup.roughness = 0.22
		dup.metallic = 0.68
		dup.metallic_specular = 0.86
		dup.albedo_color = original
	elif mode == "w_held":
		dup.cull_mode = BaseMaterial3D.CULL_BACK
		dup.roughness = 0.38
		dup.metallic = 0.32
		dup.metallic_specular = 0.70
		dup.albedo_color = Color(original.r * 1.32, original.g * 1.32, original.b * 1.34, original.a)
	elif mode == "w_drop":
		dup.cull_mode = BaseMaterial3D.CULL_BACK
		# Floor pickups must retain their texture colour under direct sunlight,
		# not become the bright silver mirrors used by first-person metal.
		dup.roughness = 0.70
		dup.metallic = 0.06
		dup.metallic_specular = 0.34
		dup.albedo_color = Color(original.r * 1.10, original.g * 1.10, original.b * 1.12, original.a)
	else:
		# Character cloth and skin stay matte; only weapons receive the harder
		# specular response above.
		dup.cull_mode = BaseMaterial3D.CULL_BACK
		dup.albedo_color = Color(original.r * 1.36, original.g * 1.36, original.b * 1.38, original.a)
	if material_name == "c4_light":
		# This rectangular mesh is the red control-panel insert, not a bloom
		# sprite. Its imported full-strength emission otherwise becomes a red
		# square on both dropped and planted models under gl_compatibility.
		dup.albedo_color = Color(0.18, 0.004, 0.002, 1.0)
		dup.emission_enabled = false
		dup.emission = Color.BLACK
		dup.emission_energy_multiplier = 0.0
		dup.metallic = 0.0
		dup.metallic_specular = 0.22
		dup.roughness = 0.86
	if material_name.begins_with("sc_cs2_") or material_name == "weapon_knife_kukri":
		# Subordinate PBR chrome: reflect beneath the unchanged base-colour art.
		dup.roughness = 0.48 if mode in ["vm", "vm_flip"] else 0.72
		dup.metallic = 0.42 if mode in ["vm", "vm_flip"] else 0.22
		dup.metallic_specular = 0.54 if mode in ["vm", "vm_flip"] else 0.38
		dup.albedo_color = original
	var character_surface := material_name.contains("glove") or material_name.contains("arms") \
		or material_name.contains("bare_arm") or material_name.contains("sleeve") or material_name.contains("skin")
	if character_surface:
		dup.metallic = 0.0
		if material_name.contains("glove"):
			dup.roughness = 0.64
		elif material_name.contains("sleeve"):
			dup.roughness = 0.76
		else:
			dup.roughness = 0.72
		dup.metallic_specular = 0.46
		if mode in ["vm", "vm_flip"]:
			dup.albedo_color = Color(original.r * 1.10, original.g * 1.10, original.b * 1.10, original.a)
	if (not archi_entry.is_empty() or not skin_entry.is_empty()) and not character_surface:
		if hd_albedo != null:
			dup.albedo_texture = hd_albedo
		var normal_map := get_texture(String(skin_entry.get("normal", archi_entry.get("normal", ""))))
		if normal_map != null:
			dup.normal_enabled = true
			dup.normal_texture = normal_map
			dup.normal_scale = 1.0
		var roughness_map := get_texture(String(archi_entry.get("roughness", "")))
		if roughness_map != null:
			# The red-channel Phong conversion modulates the established scalar;
			# metallic and the accepted per-mode roughness maxima stay unchanged.
			dup.roughness_texture = roughness_map
			dup.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# Knife finishes carry their own matching packed material maps. Never mix
	# a new finish with the preceding knife's material or the archi red channel.
	if material_name.begins_with("sc_cs2_") and skin_entry.has("orm"):
		var packed_orm := get_texture(String(skin_entry["orm"]))
		if packed_orm != null:
			dup.roughness_texture = packed_orm
			dup.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			dup.metallic_texture = packed_orm
			dup.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			dup.ao_enabled = true
			dup.ao_texture = packed_orm
			dup.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_styled_mat_cache[key] = dup
	return dup


func get_drop_shadow_material() -> StandardMaterial3D:
	var ckey := "__proc_drop_shadow_mat"
	if _styled_mat_cache.has(ckey):
		return _styled_mat_cache[ckey] as StandardMaterial3D
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var half := float(sz) * 0.5
	for y in range(sz):
		for x in range(sz):
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var r := sqrt(dx * dx + dy * dy)
			var a := pow(clampf(1.0 - r, 0.0, 1.0), 1.85) * 0.46
			img.set_pixel(x, y, Color(0.02, 0.02, 0.03, a))
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	_styled_mat_cache[ckey] = mat
	return mat


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
	var full := rel_path if rel_path.begins_with("res://") else ("res://assets/sounds/%s" % resolve_sound_path(rel_path))
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
		"inspect": [KEY_T],
		"graffiti_spray": [KEY_V],
		"graffiti_next": [KEY_J],
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


const COSMETIC_KEYS := ["native_casings_enabled", "native_ammo_icons", "low_ammo_warning", "ambient_chickens_enabled", "native_defuser_model"]

func _load_cosmetic_preferences() -> void:
	var config := ConfigFile.new()
	if config.load("user://cosmetics.cfg") == OK:
		for key in COSMETIC_KEYS:
			set(key, bool(config.get_value("cosmetics", key, get(key))))

func set_cosmetic_preference(enabled: bool, key: String) -> void:
	if key not in COSMETIC_KEYS:
		return
	set(key, enabled)
	var config := ConfigFile.new()
	for setting in COSMETIC_KEYS:
		config.set_value("cosmetics", setting, get(setting))
	config.save("user://cosmetics.cfg")

func ammo_icon_for(wid: String) -> Texture2D:
	var spec: Dictionary = weapons.get(wid, {})
	if int(spec.get("clip_size", 0)) <= 0 or wid == "taser":
		return null
	var icon := "magazine"
	if wid in ["ak47", "galil", "sg552"]:
		icon = "banana_mag"
	elif wid == "bizon":
		icon = "bizon_tube"
	elif wid in ["m249", "negev"]:
		icon = "box"
	elif wid == "p90":
		icon = "p90"
	elif wid == "revolver":
		icon = "revolver_loader"
	elif bool(spec.get("shotgun_reload", false)) or wid in ["mag7", "sawedoff"]:
		icon = "shotgun_shell"
	elif wid in ["awp", "scout"]:
		icon = "generic_bullet"
	return get_texture("res://assets/ui/native/hud_ammo_%s.png" % icon)


func apply_native_world_material(instance: Node3D, resource: String) -> void:
	# Upstream kit GLB deliberately has no materials; TacticalItemMesh binds
	# the separate same-named PNG. Preserve both original files, bind at runtime.
	if resource != "defuser_item":
		return
	var material := StandardMaterial3D.new()
	material.resource_name = "Original tactical defuser pouch"
	material.albedo_texture = get_texture("res://assets/models/native/defuser_item.png")
	material.roughness = 0.85
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		if child.mesh != null:
			for surface in range(child.mesh.get_surface_count()):
				child.set_surface_override_material(surface, material)


func equipment_icon(wid: String) -> Texture2D:
	if wid == "knife":
		var knife_path := "res://assets/ui/knives/%s.png" % selected_knife_id
		if ResourceLoader.exists(knife_path):
			return get_texture(knife_path)
	# Tiny explicit aliases: do not parse the multi-megabyte animation report for HUD icons.
	const ALIASES := {"p2000": "hkp2000", "cz75": "cz75a", "usp": "usp_silencer", "p228": "p250", "m3": "nova", "mp5navy": "mp5sd", "tmp": "mp9", "m4a1": "m4a1s", "galil": "galilar", "sg552": "sg556", "scout": "ssg08", "sg550": "scar20"}
	var path := "res://assets/polish/hud_weapon_%s.png" % String(ALIASES.get(wid, wid))
	if ResourceLoader.exists(path):
		return get_texture(path)
	path = "res://assets/polish/grenade_%s_slot.png" % wid
	if ResourceLoader.exists(path):
		return get_texture(path)
	if wid in ["vest", "vesthelm", "kevlar", "kevlar_helmet"]:
		return get_texture("res://assets/polish/hud_%s.png" % ("helmet" if wid in ["vesthelm", "kevlar_helmet"] else "armor"))
	return null
