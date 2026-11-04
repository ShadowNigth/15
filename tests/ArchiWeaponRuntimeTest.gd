extends Node
## Real-engine regression test for the ShadowNigth/archi weapon refresh.
## Run after import with:
##   godot --headless --path . res://tests/ArchiWeaponRuntimeTest.tscn

const EXPECTED_WEAPONS := 43
const EXPECTED_ARCHI_WAVS := 299
const EXPECTED_CS2_WAVS := 130
const EXPECTED_INSPECTIONS := {
	"deagle": ["inspect", "inspect_2"],
	"c4": ["inspect", "inspect_2", "inspect_3"],
	"flashbang": ["inspect", "inspect_2"],
	"hegrenade": ["inspect", "inspect_2"],
	"smokegrenade": ["inspect", "inspect_2"],
	"decoy": ["inspect", "inspect_2"],
	"molotov": ["inspect", "inspect_2"],
	"incendiary": ["inspect", "inspect_2"],
}

var _checks := 0
var _failures: Array[String] = []
var _world: TestWorld = null
var _actor: FakeActor = null
var _controller: WeaponController = null


class TestWorld:
	extends Node3D
	var breakables: Array = []


class FakeActor:
	extends CharacterBody3D
	var is_alive := true
	var is_human := false
	var team := "CT"
	var actor_name := "WeaponTest"
	var sequences: Array = []
	var damage_received: float = 0.0

	func get_eye_position() -> Vector3:
		return global_position + Vector3(0.0, 1.6, 0.0)

	func get_aim_basis(_punch: Vector2) -> Basis:
		return global_basis

	func get_vm_muzzle_world() -> Vector3:
		return get_eye_position() - global_basis.z * 0.35

	func play_viewmodel_sequence(names: Array) -> void:
		sequences.append(names)

	func trigger_upper_body_action(_action: String) -> void:
		pass

	func apply_explosion_damage(_attacker: Node3D, amount: float, _kind: String, _origin: Vector3) -> void:
		damage_received += amount


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[ARCHI TEST] " + description)


func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.actors.clear()
	RoundManager.hostages.clear()
	RoundManager.dropped_items.clear()
	RoundManager.planted_c4 = null
	RoundManager.smoke_clouds.clear()
	RoundManager.smoke_volumes.clear()

	_world = TestWorld.new()
	add_child(_world)
	RoundManager.game_world = _world
	_actor = FakeActor.new()
	_world.add_child(_actor)
	_controller = WeaponController.new()
	_actor.add_child(_controller)
	_controller.setup_for_actor(_actor)
	_controller.set_process(false)

	_test_assets()
	_test_animation_refinements()
	_test_alternate_inspections()
	_test_hd_materials()
	await _test_original_viewmodel_arms()
	await _test_sport_gloves()
	_test_cs2_audio()
	_test_world_calibration_and_molotov()
	_test_gameplay_material_fixes()
	_test_scope_tint_preservation()
	_test_mechanics()
	_test_single_planted_c4_guard()
	_test_grenade_world_scale()
	_test_crate_rule()
	await _test_fire_spread()

	if _failures.is_empty():
		print("[ARCHI TEST] PASS: %d checks; 43 slots, 129 GLBs, 299 archi WAVs and 130 dedicated CS2 WAVs." % _checks)
	else:
		print("[ARCHI TEST] FAIL: %d of %d checks failed." % [_failures.size(), _checks])
	# Radio/weapon playback runs on the audio thread; stop it before the test's
	# immediate exit so headless runs do not report still-active WAV playbacks.
	for player in AudioManager._players_2d:
		player.stop()
		player.stream = null
	for player in AudioManager._players_3d:
		player.stop()
		player.stream = null
	OS.delay_msec(100)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


func _test_assets() -> void:
	_expect(GameData.weapons.size() == EXPECTED_WEAPONS, "weapon roster must contain 43 slots")
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		for key in ["v_model", "p_model", "w_model"]:
			var model_name := String(spec.get(key, ""))
			var packed := GameData.get_model_scene("weapons/" + model_name)
			_expect(packed != null, "%s %s must import as PackedScene" % [wid, key])
			if packed == null:
				continue
			var instance := packed.instantiate() as Node3D
			_expect(instance != null, "%s %s must instantiate" % [wid, key])
			if instance == null:
				continue
			_world.add_child(instance)
			_expect(_mesh_count(instance) > 0, "%s %s must contain meshes" % [wid, key])
			if key == "v_model":
				var player := _find_animation_player(instance)
				_expect(player != null, "%s must have an AnimationPlayer" % wid)
				if player != null:
					_expect(player.has_animation("idle"), "%s must have idle" % wid)
					_expect(player.has_animation("draw") or player.has_animation("deploy"), "%s must have its equip animation" % wid)
					if bool(spec.get("grenade", false)):
						_expect(player.has_animation("pullpin") and player.has_animation("throw") and player.has_animation("underhand"), "%s grenade pin/overhand/underhand clips" % wid)
					elif wid == "c4":
						_expect(player.has_animation("pressbutton"), "C4 planting animation")
					elif wid == "knife":
						_expect(player.has_animation("slash1") and player.has_animation("stab"), "Kukri slash and stab clips")
					elif wid != "taser":
						if wid == "glock18":
							_expect(player.has_animation("shoot") and player.has_animation("shoot2") and player.has_animation("shoot3"), "Glock semi/burst tracks")
						elif wid == "elite":
							_expect(player.has_animation("shoot_left1") and player.has_animation("shoot_right1"), "Elite alternating tracks")
						elif wid == "revolver":
							_expect(player.has_animation("fire") and player.has_animation("shoot1") and player.has_animation("prepare") and player.has_animation("alt1"), "R8 fire aliases, prepare and alt fire")
						else:
							_expect(player.has_animation("shoot1"), "%s must have shoot1" % wid)
						if bool(spec.get("shotgun_reload", false)):
							_expect(player.has_animation("start_reload") and player.has_animation("insert") and player.has_animation("after_reload"), "%s staged shotgun reload clips" % wid)
						else:
							_expect(player.has_animation("reload"), "%s reload clip" % wid)
					if bool(spec.get("silencer", false)):
						_expect(player.has_animation("add_silencer") and player.has_animation("detach_silencer") and player.has_animation("reload_unsil"), "%s silencer and unsuppressed reload clips" % wid)
			if key == "w_model":
				var bounds := _instance_bounds(instance)
				_expect(bounds.size.length() < 2.5, "%s world model has a stray mesh: %s" % [wid, str(bounds.size)])
				if wid == "elite":
					_expect(bounds.size.x < 0.55 and bounds.size.y < 0.25 and bounds.size.z < 0.40, "Elite world model must contain one aligned pistol")
			instance.free()
		var icon := GameData.get_texture("res://assets/ui/vgui/%s.png" % String(spec.get("vgui", "")))
		_expect(icon != null, "%s inventory icon must import" % wid)

	var wavs: Array[String] = []
	_collect_wavs("res://assets/sounds/weapons/archi", wavs)
	_expect(wavs.size() == EXPECTED_ARCHI_WAVS, "all 299 archi WAVs must be installed (found %d)" % wavs.size())
	for path in wavs:
		var stream := load(path) as AudioStream
		_expect(stream != null, "Godot must decode " + path)


func _find_animation_track(clip: Animation, node_name: String, track_type: int) -> int:
	for track in range(clip.get_track_count()):
		if clip.track_get_type(track) == track_type and String(clip.track_get_path(track)).find(node_name) >= 0:
			return track
	return -1


func _find_material(n: Node, wanted: String) -> BaseMaterial3D:
	if n is MeshInstance3D:
		var mesh := n as MeshInstance3D
		if mesh.mesh != null:
			for surface in range(mesh.mesh.get_surface_count()):
				var material := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
				if material != null and material.resource_name.to_lower() == wanted:
					return material
	for child in n.get_children():
		var found := _find_material(child, wanted)
		if found != null:
			return found
	return null


func _test_animation_refinements() -> void:
	var inspection_models := {
		"weapons/v_m4a1": "v_weapon.M4A1_s_Parent",
		"weapons/v_usp": "weapon_hand_r",
	}
	for key in inspection_models:
		var packed := GameData.get_model_scene(key)
		_expect(packed != null, "%s inspection refinement model loads" % key)
		if packed == null:
			continue
		var instance := packed.instantiate()
		_world.add_child(instance)
		var player := _find_animation_player(instance)
		var attachment := String(inspection_models[key])
		var skeleton := _find_skeleton(instance)
		var bone_index := skeleton.find_bone(attachment) if skeleton != null else -1
		_expect(bone_index >= 0, "%s exposes its gun attachment bone" % key)
		if bone_index < 0:
			instance.free()
			continue
		var rest := skeleton.get_bone_rest(bone_index)
		for clip_name in ["inspect", "inspect_unsil"]:
			var idle_name := "idle_unsil" if clip_name == "inspect_unsil" else "idle"
			if player == null or not player.has_animation(clip_name) or not player.has_animation(idle_name):
				_expect(false, "%s has both inspection and idle clips" % key)
				continue
			var clip := player.get_animation(clip_name)
			var idle := player.get_animation(idle_name)
			var position_track := _find_animation_track(clip, attachment, Animation.TYPE_POSITION_3D)
			var idle_position_track := _find_animation_track(idle, attachment, Animation.TYPE_POSITION_3D)
			var position_reference := rest.origin
			if idle_position_track >= 0:
				position_reference = idle.position_track_interpolate(idle_position_track, 0.0)
			# Godot may remove an immutable track that exactly matches the rest pose.
			# That is also a valid rigid attachment, so use rest as the sampled value.
			var position_stable := true
			if position_track >= 0:
				for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
					var sample := clip.position_track_interpolate(position_track, clip.length * fraction)
					position_stable = position_stable and sample.distance_to(position_reference) <= 0.0001
			else:
				position_stable = rest.origin.distance_to(position_reference) <= 0.0001
			_expect(position_stable, "%s/%s keeps the gun rigidly attached to the hand" % [key, clip_name])

			var rotation_track := _find_animation_track(clip, attachment, Animation.TYPE_ROTATION_3D)
			var idle_rotation_track := _find_animation_track(idle, attachment, Animation.TYPE_ROTATION_3D)
			var rotation_reference := rest.basis.get_rotation_quaternion()
			if idle_rotation_track >= 0:
				rotation_reference = idle.rotation_track_interpolate(idle_rotation_track, 0.0)
			var rotation_stable := true
			if rotation_track >= 0:
				for fraction in [0.0, 0.5, 1.0]:
					var sample := clip.rotation_track_interpolate(rotation_track, clip.length * fraction)
					rotation_stable = rotation_stable and absf(1.0 - absf(rotation_reference.dot(sample))) <= 0.000001
			else:
				var rest_rotation := rest.basis.get_rotation_quaternion()
				rotation_stable = absf(1.0 - absf(rotation_reference.dot(rest_rotation))) <= 0.000001
			_expect(rotation_stable, "%s/%s prevents relative gun/hand rotation" % [key, clip_name])

			var hand_track := _find_animation_track(clip, "v_weapon.Bip01_R_Hand", Animation.TYPE_ROTATION_3D)
			var hand_moves := false
			if hand_track >= 0:
				var start := clip.rotation_track_interpolate(hand_track, 0.0)
				var middle := clip.rotation_track_interpolate(hand_track, clip.length * 0.5)
				hand_moves = absf(1.0 - absf(start.dot(middle))) > 0.00001
			_expect(hand_moves, "%s/%s still animates the arms rather than freezing inspection" % [key, clip_name])
		instance.free()

	var glock := GameData.get_model_scene("weapons/v_glock18")
	_expect(glock != null, "Glock slide refinement model loads")
	if glock != null:
		var instance := glock.instantiate()
		_world.add_child(instance)
		var player := _find_animation_player(instance)
		for clip_name in ["shoot", "shoot2", "shoot3", "shoot_empty"]:
			if player == null or not player.has_animation(clip_name):
				_expect(false, "Glock has its %s clip" % clip_name)
				continue
			var clip := player.get_animation(clip_name)
			var track := _find_animation_track(clip, "v_weapon_glock_slide", Animation.TYPE_POSITION_3D)
			_expect(track >= 0, "Glock %s has a slide position track" % clip_name)
			if track >= 0:
				var start := clip.position_track_interpolate(track, 0.0)
				var rear := clip.position_track_interpolate(track, 2.0 / 30.0)
				var finish := clip.position_track_interpolate(track, clip.length)
				var cycle_ok := start.distance_to(rear) > 0.035
				if clip_name == "shoot_empty":
					cycle_ok = cycle_ok and finish.distance_to(rear) < 0.0001
				else:
					cycle_ok = cycle_ok and finish.distance_to(start) < 0.0001
				_expect(cycle_ok, "Glock %s performs the expected visible slide cycle" % clip_name)
		instance.free()


func _test_alternate_inspections() -> void:
	for wid in EXPECTED_INSPECTIONS:
		var expected: Array = EXPECTED_INSPECTIONS[wid]
		var spec: Dictionary = GameData.weapons[wid]
		var model_key := "weapons/" + String(spec["v_model"])
		var packed := GameData.get_model_scene(model_key)
		_expect(packed != null, "%s alternate-inspection model loads" % wid)
		if packed == null:
			continue
		var instance := packed.instantiate()
		_world.add_child(instance)
		var player := _find_animation_player(instance)
		_expect(player != null, "%s alternate-inspection AnimationPlayer exists" % wid)
		var metadata: Dictionary = GameData.models_meta.get(model_key, {})
		_expect(metadata.get("inspect_clips", []) == expected, "%s metadata lists every inspection in order" % wid)
		if player != null:
			for raw_name in expected:
				var clip_name := String(raw_name)
				_expect(player.has_animation(clip_name), "%s has %s" % [wid, clip_name])
				if not player.has_animation(clip_name):
					continue
				var clip := player.get_animation(clip_name)
				_expect(clip.length >= 0.90, "%s/%s has its full authored duration" % [wid, clip_name])
				var source_duration := float(metadata.get("seq_durations", {}).get(clip_name, 0.0))
				_expect(absf(clip.length - source_duration) <= 0.04,
					"%s/%s duration matches Source metadata" % [wid, clip_name])
				if clip_name == "inspect":
					continue
				var hand_track := _find_animation_track(clip, "v_weapon.Bip01_R_Hand", Animation.TYPE_ROTATION_3D)
				var hand_moves := false
				if hand_track >= 0:
					var reference := clip.rotation_track_interpolate(hand_track, 0.0)
					for fraction in [0.2, 0.4, 0.6, 0.8, 1.0]:
						var sample := clip.rotation_track_interpolate(hand_track, clip.length * fraction)
						hand_moves = hand_moves or absf(1.0 - absf(reference.dot(sample))) > 0.000001
				_expect(hand_moves, "%s/%s is a distinct moving inspection, not a static alias" % [wid, clip_name])
		instance.free()
	var deagle_events: Array = GameData.models_meta.get("weapons/v_deagle", {}).get("seq_events", {}).get("inspect_2", [])
	_expect(deagle_events.size() == 9, "Long Deagle inspection retains all nine authentic foley events")
	for event in deagle_events:
		_expect(GameData.get_sound(String(event.get("wav", ""))) != null,
			"Deagle inspect_2 event loads %s" % String(event.get("wav", "")))


func _test_hd_materials() -> void:
	_expect(GameData.archi_materials.size() == 54, "Shared archi catalog contains all 54 mapped weapon materials")
	var paths: Dictionary = {}
	for material_name in GameData.archi_materials:
		var entry: Dictionary = GameData.archi_materials[material_name]
		for kind in ["color", "normal", "roughness"]:
			var path := String(entry.get(kind, ""))
			if not path.is_empty():
				paths[path] = entry.get(kind + "_size", [])
	_expect(paths.size() == 136, "Catalog exposes 136 unique shared HD texture files")
	for path in paths:
		var texture := ResourceLoader.load(path) as Texture2D
		_expect(texture != null, "HD texture imports and loads: " + path)
		if texture != null:
			var dimensions: Array = paths[path]
			_expect(texture.get_size() == Vector2(float(dimensions[0]), float(dimensions[1])),
				"HD texture dimensions match catalog: " + path)
		texture = null

	var packed := GameData.get_model_scene("weapons/v_ak47")
	_expect(packed != null, "AK-47 HD material model loads")
	if packed != null:
		var instance := packed.instantiate()
		_world.add_child(instance)
		var original := _find_material(instance, "weapon_rif_ak47")
		_expect(original != null, "AK-47 weapon material is available")
		if original != null:
			var styled := GameData.get_styled_model_material(original, "vm") as BaseMaterial3D
			var entry: Dictionary = GameData.archi_materials["weapon_rif_ak47"]
			_expect(styled != null and styled.albedo_texture == GameData.get_texture(String(entry["color"])),
				"AK-47 uses its shared 2K colour texture")
			_expect(styled != null and styled.normal_enabled and styled.normal_texture == GameData.get_texture(String(entry["normal"])),
				"AK-47 enables its Source normal map")
			_expect(styled != null and styled.roughness_texture == GameData.get_texture(String(entry["roughness"])) \
				and styled.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED,
				"AK-47 uses the red-channel Phong roughness modulation")
			_expect(styled != null and is_equal_approx(styled.roughness, 0.30) and is_equal_approx(styled.metallic, 0.42),
				"HD maps preserve the accepted metallic and scalar roughness finish")
			_expect(styled != null and styled.albedo_color.r > original.albedo_color.r,
				"HD colour preserves first-person brightness multiplication")
			for kind in ["color", "normal", "roughness"]:
				var import_config := ConfigFile.new()
				var import_ok := import_config.load(String(entry[kind]) + ".import") == OK
				_expect(import_ok and bool(import_config.get_value("params", "mipmaps/generate", false)),
					"AK-47 %s retains 3D mipmaps after import" % kind)
		var arms := _find_material(instance, "ct_arms.bmp")
		_expect(arms != null, "Original AK-47 arms remain available for material comparison")
		if arms != null:
			var arm_styled := GameData.get_styled_model_material(arms, "vm") as BaseMaterial3D
			_expect(arm_styled != null and arm_styled.albedo_texture == arms.albedo_texture and arm_styled.normal_texture == null,
				"HD weapon catalog never alters original arm textures")
		instance.free()


func _original_arm_composition(root: Node) -> bool:
	var original_arms := false
	var original_gloves := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.has_meta("loadout_kind") or mesh.mesh == null:
			return false
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			var material_name := material.resource_name.to_lower() if material != null else ""
			if material_name == "ct_arms.bmp":
				original_arms = true
			elif material_name == "ct_base_glove.bmp":
				original_gloves = true
			elif material_name.begins_with("bare_arm") or material_name.begins_with("glove_") \
				or material_name.begins_with("sleeve"):
				return false
	return original_arms and original_gloves


func _test_original_viewmodel_arms() -> void:
	var previous_glove := GameData.selected_glove_id
	GameData.select_glove("classic")
	_expect(not DirAccess.dir_exists_absolute("res://assets/models/loadouts"),
		"MultiRig glove/sleeve assets are removed from the project")
	_expect(not FileAccess.file_exists("res://data/viewmodel_loadouts.json") \
		and not FileAccess.file_exists("res://scripts/actors/ViewmodelLoadout.gd"),
		"MultiRig runtime data and installer are removed from the project")
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		var packed := GameData.get_model_scene("weapons/" + String(spec["v_model"]))
		if packed == null:
			_expect(false, "%s original viewmodel loads" % wid)
			continue
		var instance := packed.instantiate() as Node3D
		_world.add_child(instance)
		_expect(_original_arm_composition(instance),
			"%s uses only its original ct_arms and ct_base_glove surfaces" % wid)
		instance.free()

	var menu := load("res://scenes/MainMenu.tscn").instantiate() as MainMenu
	_world.add_child(menu)
	await get_tree().process_frame
	_expect(menu.find_children("Loadout_*", "OptionButton", true, false).is_empty(),
		"3D Arsenal exposes no rejected MultiRig Loadout controls")
	menu._load_viewer_weapon("m4a1")
	_expect(_original_arm_composition(menu._viewer_pivot),
		"3D Arsenal preview uses only the original first-person arms and gloves")
	menu.free()
	GameData.selected_glove_id = previous_glove


func _sport_composition(root: Node, expected_id: String) -> bool:
	var original_arms := false
	var original_glove := false
	var sport_surfaces := 0
	var valid := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or mesh.has_meta("loadout_kind"):
			valid = false
			continue
		if mesh.has_meta("sport_gloves"):
			if String(mesh.get_meta("sport_glove_id", "")) != expected_id or mesh.skin == null:
				valid = false
			sport_surfaces += mesh.mesh.get_surface_count()
			for surface in range(mesh.mesh.get_surface_count()):
				var active := mesh.get_active_material(surface) as BaseMaterial3D
				if active == null or active.albedo_texture == null or not active.resource_name.begins_with("sport_glove_"):
					valid = false
			continue
		for surface in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(surface)
			var material_name := material.resource_name.to_lower() if material != null else ""
			if material_name == "ct_arms.bmp":
				original_arms = true
			elif material_name == "ct_base_glove.bmp":
				original_glove = true
			elif material_name.begins_with("bare_arm") or material_name.begins_with("sleeve"):
				valid = false
	return valid and original_arms and not original_glove and sport_surfaces == 10


func _test_sport_gloves() -> void:
	var previous_glove := GameData.selected_glove_id
	_expect(GameData.get_glove_options().size() == 26, "Sport Gloves catalog exposes all 26 authored finishes")
	_expect(GameData.sport_gloves.get("models", []).size() == 43, "Sport Gloves catalog covers every distinct viewmodel")
	var texture_paths: Dictionary = {}
	for raw in GameData.get_glove_options():
		var option := raw as Dictionary
		var option_id := String(option.get("id", ""))
		_expect(GameData.select_glove(option_id), "Sport finish is selectable: " + option_id)
		for path in option.get("textures", {}).values():
			texture_paths[path] = true
	_expect(texture_paths.size() == 130, "Sport catalog references exactly 130 deduplicated texture files")
	for path in texture_paths:
		_expect(GameData.get_texture(String(path)) != null, "Sport texture imports: " + String(path))
	_expect(GameData.select_glove("arid_mw"), "The default Arid Minimal Wear finish is selectable")
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		var viewmodel_name := String(spec["v_model"])
		var packed := GameData.get_model_scene("weapons/" + viewmodel_name)
		if packed == null:
			_expect(false, "%s Sport test viewmodel loads" % wid)
			continue
		var instance := packed.instantiate() as Node3D
		_world.add_child(instance)
		var animation := _find_animation_player(instance)
		var applied := SportGloves.apply(instance, viewmodel_name)
		_expect(applied, "%s installs Sport native binds" % wid)
		_expect(_sport_composition(instance, "arid_mw"),
			"%s keeps original arms, ten textured Sport surfaces and no original glove overlap" % wid)
		_expect(_find_animation_player(instance) == animation, "%s retains its original AnimationPlayer" % wid)
		instance.free()

	GameData.select_glove("classic")
	var classic := GameData.get_model_scene("weapons/v_ak47").instantiate() as Node3D
	_world.add_child(classic)
	_expect(not SportGloves.apply(classic, "v_ak47") and _original_arm_composition(classic),
		"Original menu option leaves the accepted classic gloves untouched")
	classic.free()

	var menu := load("res://scenes/MainMenu.tscn").instantiate() as MainMenu
	_world.add_child(menu)
	await get_tree().process_frame
	_expect(menu._glove_opt != null and menu._glove_opt.item_count == 27,
		"Create Game exposes Original plus all 26 Sport finishes")
	menu._select_glove_for_match("vice_ww")
	_expect(GameData.selected_glove_id == "vice_ww" and _sport_composition(menu._viewer_pivot, "vice_ww"),
		"3D Arsenal previews and stores the selected Vice finish for the match")
	menu.free()
	GameData.selected_glove_id = previous_glove


func _test_cs2_audio() -> void:
	var wavs: Array[String] = []
	_collect_wavs("res://assets/sounds/weapons/cs2", wavs)
	_expect(wavs.size() == EXPECTED_CS2_WAVS, "all 130 dedicated CS2 WAVs must be installed (found %d)" % wavs.size())
	for path in wavs:
		var stream := load(path) as AudioStream
		_expect(stream != null, "Godot must decode " + path)

	var owners: Dictionary = {}
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		var sounds: Array = spec.get("fire_sounds", [])
		if sounds.is_empty():
			continue
		var dedicated := true
		for raw in sounds:
			var path := String(raw)
			if not path.begins_with("weapons/cs2/"):
				dedicated = false
			if owners.has(path) and String(owners[path]) != wid:
				dedicated = false
			owners[path] = wid
		_expect(dedicated, "%s must use its own CS2 firing recordings" % wid)
	var m4a4_sounds: Array = GameData.weapons["m4a4"]["fire_sounds"]
	var m4a1s_sounds: Array = GameData.weapons["m4a1"]["fire_sounds"]
	_expect("weapons/cs2/m4a1/m4a1_01.wav" in m4a4_sounds,
		"M4A4 uses the CS2 m4a1_01 recording")
	_expect("weapons/cs2/m4a1/m4a1_us_01.wav" in m4a1s_sounds,
		"M4A1-S unsuppressed uses the distinct m4a1_us_01 recording")
	_expect(String(GameData.weapons["knife"]["wall_sound"]).find("flashbang") < 0,
		"Knife wall impacts no longer use a flashbang sample")
	_expect(String(GameData.weapons["molotov"]["explode_sounds"][0]).find("molotov_detonate") >= 0,
		"Molotov uses its own detonation rather than HE")
	var m4a4_foley := true
	for events in GameData.models_meta["weapons/v_m4a4"]["seq_events"].values():
		for event in events:
			if not String(event["wav"]).begins_with("weapons/cs2/m4a1/"):
				m4a4_foley = false
	_expect(m4a4_foley, "Every M4A4 draw/reload event uses its dedicated CS2 foley")
	var mag7_foley := true
	for events in GameData.models_meta["weapons/v_mag7"]["seq_events"].values():
		for event in events:
			if not String(event["wav"]).begins_with("weapons/cs2/mag7/"):
				mag7_foley = false
	_expect(mag7_foley, "MAG-7 reload, draw and pump events all use MAG-7 recordings")
	_expect(String(GameData.weapons["molotov"]["pinpull_sound"]).find("cs2_hegren") < 0,
		"Molotov ignition no longer plays the HE pin sound")
	_expect(String(GameData.weapons["decoy"]["deploy_sound"]).begins_with("weapons/cs2/decoy/"),
		"Decoy deploy uses its own recording")


func _test_world_calibration_and_molotov() -> void:
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		var scale := GameData.get_world_model_scale(wid)
		_expect(scale >= 0.45 and scale <= 1.0 and is_equal_approx(scale, float(spec.get("world_scale", 1.0))),
			"%s has a bounded shared world scale" % wid)
		if bool(spec.get("grenade", false)):
			_expect(is_equal_approx(scale, GameData.GRENADE_WORLD_SCALE), "%s preserves grenade scale 0.90" % wid)
		else:
			_expect(is_equal_approx(scale, 1.0), "%s restores normal world size" % wid)

	var drop := DroppedWeapon.new()
	_world.add_child(drop)
	drop.setup_drop("m4a1", 30, 90, Vector3.ZERO)
	var held_scale := GameData.get_world_model_scale("m4a1")
	var drop_scale_ok := drop._visual_root.get_child_count() > 0
	if drop_scale_ok:
		var model := drop._visual_root.get_child(0) as Node3D
		drop_scale_ok = model != null and absf(model.scale.x - held_scale) < 0.0001
	_expect(drop_scale_ok, "Dropped M4A1 uses the same normal scale as the hand model")
	drop.free()

	var packed := GameData.get_model_scene("weapons/v_molotov")
	_expect(packed != null, "Molotov material test model loads")
	if packed == null:
		return
	var instance := packed.instantiate()
	_world.add_child(instance)
	var outer_glass_ok := false
	var intermediate_glass_ok := false
	var liquid_ok := false
	var weapon_finish_ok := false
	for node in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var original := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if original == null:
				continue
			if original.resource_name in ["weapon_molotov", "weapon_molotov_liquid"]:
				var glass := GameData.get_styled_model_material(original, "vm") as ShaderMaterial
				var tint: Vector3 = glass.get_shader_parameter("glass_tint") if glass != null else Vector3.ZERO
				var hd_entry: Dictionary = GameData.archi_materials.get(original.resource_name.to_lower(), {})
				var expected_bottle := GameData.get_texture(String(hd_entry.get("color", "")))
				var valid: bool = glass != null and glass.shader == GameData.MOLOTOV_GLASS_SHADER \
					and glass.get_shader_parameter("bottle_texture") != null \
					and glass.get_shader_parameter("bottle_texture") == expected_bottle \
					and float(glass.get_shader_parameter("glass_opacity")) >= 0.28 \
					and float(glass.get_shader_parameter("refraction_strength")) >= 0.012 \
					and tint.y >= tint.x and tint.y >= tint.z
				if original.resource_name == "weapon_molotov":
					outer_glass_ok = valid and glass.render_priority == 2
				else:
					intermediate_glass_ok = valid and glass.render_priority == 1
			elif original.resource_name == "molotov_inside":
				var liquid := GameData.get_styled_model_material(original, "vm") as ShaderMaterial
				liquid_ok = liquid != null and liquid.shader == GameData.MOLOTOV_LIQUID_SHADER \
					and float(liquid.get_shader_parameter("deformation")) > 0.5 \
					and float(liquid.get_shader_parameter("opacity")) >= 0.58 \
					and float(liquid.get_shader_parameter("refraction_strength")) > 0.0 and liquid.render_priority == 0
			elif original.resource_name == "weapon_molotov_lighter":
				var finish := GameData.get_styled_model_material(original, "vm") as BaseMaterial3D
				weapon_finish_ok = finish != null and finish.roughness <= 0.31 and finish.metallic >= 0.41 \
					and finish.metallic_specular >= 0.77
	_expect(outer_glass_ok and intermediate_glass_ok, "Both Molotov glass layers refract the scene and preserve printed detail")
	_expect(liquid_ok, "Molotov liquid is animated, refractive and drawn behind the glass")
	_expect(GameData.MOLOTOV_GLASS_SHADER.code.contains("hint_screen_texture") \
		and GameData.MOLOTOV_GLASS_SHADER.code.contains("SCREEN_UV") \
		and GameData.MOLOTOV_LIQUID_SHADER.code.contains("hint_screen_texture"),
		"Liquid-glass shaders use actual screen transmission rather than plain alpha")
	_expect(weapon_finish_ok, "Weapon materials preserve their accepted first-person metallic response")
	instance.free()


func _test_gameplay_material_fixes() -> void:
	var ak := GameData.get_model_scene("weapons/w_ak47").instantiate() as Node3D
	_world.add_child(ak)
	var original := _find_material(ak, "weapon_rif_ak47")
	_expect(original != null, "Dropped AK material is available for finish comparison")
	if original != null:
		var dropped := GameData.get_styled_model_material(original, "w_drop") as BaseMaterial3D
		var first_person := GameData.get_styled_model_material(original, "vm") as BaseMaterial3D
		_expect(dropped != null and is_equal_approx(dropped.roughness, 0.70) \
			and is_equal_approx(dropped.metallic, 0.06) and is_equal_approx(dropped.metallic_specular, 0.34),
			"Dropped weapons use the matte low-specular floor finish")
		_expect(first_person != null and is_equal_approx(first_person.roughness, 0.30) \
			and is_equal_approx(first_person.metallic, 0.42) and is_equal_approx(first_person.metallic_specular, 0.78),
			"First-person metallic brightness remains unchanged")
	ak.free()

	var c4 := GameData.get_model_scene("weapons/w_c4").instantiate() as Node3D
	_world.add_child(c4)
	var panel := _find_material(c4, "c4_light")
	_expect(panel != null, "C4 red control-panel material exists")
	if panel != null:
		var styled := GameData.get_styled_model_material(panel, "w_drop") as BaseMaterial3D
		_expect(styled != null and not styled.emission_enabled and styled.emission_energy_multiplier <= 0.0 \
			and is_equal_approx(styled.albedo_color.r, 0.18) and styled.metallic <= 0.0,
			"Dropped C4 red rectangle is a dark non-emissive panel, not a glowing square")
	c4.free()

	var planted := PlantedC4.new()
	_world.add_child(planted)
	_expect(planted._led_sprite != null and is_equal_approx(planted._led_sprite.pixel_size, 0.0028) \
		and is_equal_approx(planted._led_sprite.modulate.a, 0.58), "Planted C4 uses a small restrained LED glow")
	_expect(planted._led_light != null and is_equal_approx(planted._led_light.omni_range, 1.6) \
		and is_equal_approx(planted._led_light.light_energy, 0.65), "Planted C4 local red light has bounded range and energy")
	planted.time_left = 0.05
	planted._beep_timer = 0.0
	planted._process(0.001)
	_expect(planted._led_light != null and is_equal_approx(planted._led_light.omni_range, 1.6) \
		and planted._led_light.light_energy <= 0.8501, "The brightest C4 beep keeps the reduced local light bounds")
	planted.free()


func _test_scope_tint_preservation() -> void:
	for wid in ["aug", "awp", "sg552", "scout", "g3sg1", "sg550"]:
		var spec: Dictionary = GameData.weapons[wid]
		var packed := GameData.get_model_scene("weapons/" + String(spec["v_model"]))
		_expect(packed != null, "%s scope test model loads" % wid)
		if packed == null:
			continue
		var instance := packed.instantiate() as Node3D
		_world.add_child(instance)
		var black_lenses := 0
		for node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh == null:
				continue
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var original := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
				if original == null:
					continue
				var colour := original.albedo_color
				if maxf(colour.r, maxf(colour.g, colour.b)) > 0.001:
					continue
				black_lenses += 1
				for mode in ["vm", "vm_flip", "w", "w_drop"]:
					var styled := GameData.get_styled_model_material(original, mode) as BaseMaterial3D
					_expect(styled != null and maxf(styled.albedo_color.r, maxf(styled.albedo_color.g, styled.albedo_color.b)) <= 0.001,
						"%s %s must preserve its black scope factor" % [wid, mode])
		_expect(black_lenses > 0, "%s has a real black lens material to test" % wid)
		instance.free()


func _test_mechanics() -> void:
	# FAMAS: one click produces exactly a three-round burst.
	_equip("famas", 25, 50)
	_controller.burst_state["famas"] = true
	_controller.trigger_primary(false, 0.016)
	_expect(int(_controller.clips["famas"]) == 24 and _controller.burst_remaining == 2, "FAMAS burst starts with one shot and two queued")
	_controller._process(0.06)
	_controller._process(0.06)
	_expect(int(_controller.clips["famas"]) == 22 and _controller.burst_remaining == 0, "FAMAS burst fires exactly three rounds")

	# R8: primary waits for the hammer, reload cancels that pending shot.
	_equip("revolver", 8, 8)
	_controller.clips["revolver"] = 7
	_controller.trigger_primary(false, 0.016)
	_expect(int(_controller.clips["revolver"]) == 7 and _controller._revolver_windup > 0.0, "R8 primary must not fire before hammer wind-up")
	_controller.start_reload()
	_controller._process(0.30)
	_expect(int(_controller.clips["revolver"]) == 7 and _controller._revolver_windup <= 0.0, "R8 reload cancels pending hammer shot")
	_controller._process(_controller.reload_timer + 0.05)
	_expect(int(_controller.clips["revolver"]) == 8, "R8 magazine/cylinder reload completes")
	_equip("revolver", 8, 8)
	_controller.trigger_primary(false, 0.016)
	_controller._process(0.22)
	_expect(int(_controller.clips["revolver"]) == 7, "R8 delayed primary fires after wind-up")
	_controller.fire_cooldown = 0.0
	_controller.trigger_secondary()
	_expect(int(_controller.clips["revolver"]) == 6 and _controller.revolver_alt_fire, "R8 secondary is immediate alt fire")

	# MAG-7 uses a magazine; Sawed-Off retains staged shell insertion.
	_equip("mag7", 5, 10)
	_controller.clips["mag7"] = 2
	_controller.start_reload()
	_expect(_controller.is_reloading and not bool(_controller.get_current_spec().get("shotgun_reload", false)), "MAG-7 must use magazine reload")
	_controller._process(_controller.reload_timer + 0.05)
	_expect(int(_controller.clips["mag7"]) == 5 and int(_controller.ammo_pool["buckshot"]) == 7 and not _controller.is_reloading, "MAG-7 magazine refills in one step")
	_equip("sawedoff", 7, 10)
	_controller.clips["sawedoff"] = 5
	_controller.start_reload()
	_controller._process(_controller.reload_timer + 0.02)
	_expect(int(_controller.clips["sawedoff"]) == 6 and _controller.is_reloading, "Sawed-Off inserts one shell and continues")
	var guard := 0
	while _controller.is_reloading and guard < 10:
		_controller._process(_controller.reload_timer + 0.02)
		guard += 1
	_expect(int(_controller.clips["sawedoff"]) == 7 and int(_controller.ammo_pool["buckshot"]) == 8, "Sawed-Off staged reload consumes exactly two shells")

	# Zeus consumes its only charge and uses the short-range electroshock path.
	_equip("taser", 1, 0)
	_controller.trigger_primary(false, 0.016)
	_expect(int(_controller.clips["taser"]) == 0, "Zeus consumes its single charge")
	_expect(float(_controller.get_current_spec().get("range", 0.0)) <= 180.0, "Zeus remains short range")

	_test_underhand_throw()
	_test_decoy()
	_test_fire_projectile("molotov")
	_test_fire_projectile("incendiary")


func _test_underhand_throw() -> void:
	_actor.is_human = true
	_equip("hegrenade", 1, 0)
	_controller.trigger_secondary()
	_controller._process(0.33)
	_controller.release_secondary()
	_expect(not _actor.sequences.is_empty() and _actor.sequences.back()[0] == "underhand", "Secondary grenade throw uses archi's underhand animation")
	_expect(int(_controller.grenades["hegrenade"]) == 0, "Underhand throw consumes the grenade")
	_actor.is_human = false


func _test_decoy() -> void:
	_equip("decoy", 1, 0)
	_controller.trigger_primary(false, 0.016)
	var projectile := _latest_grenade()
	_expect(projectile != null and projectile.grenade_type == "decoy", "Decoy throw creates its projectile")
	if projectile == null:
		return
	projectile.set_physics_process(false)
	projectile._detonate()
	_expect(projectile._decoy_active, "Decoy enters its timed sound-lure state")
	projectile._process_decoy(0.20)
	_expect(projectile._decoy_life > 0.0 and not projectile._decoy_sounds.is_empty(), "Decoy uses archi weapon sounds while active")
	projectile._process_decoy(12.0)
	_expect(projectile._detonated and not projectile._decoy_active, "Decoy expires into its final small burst")


func _test_fire_projectile(kind: String) -> void:
	var projectile := GrenadeProjectile.new()
	_world.add_child(projectile)
	projectile.setup_grenade(kind, _actor, Vector3.ZERO)
	projectile.set_physics_process(false)
	projectile._detonate()
	var area: IncendiaryArea = null
	for child in _world.get_children():
		if child is IncendiaryArea and child.area_type == kind:
			area = child
	_expect(area != null, "%s creates persistent fire" % kind)
	if area != null:
		_expect(area._patches.size() == 1 and not area._flames.is_empty() and area.life_left >= 7.0,
			"%s fire has an ignition patch, layered flames and a real lifetime" % kind)
		_expect(area._flames.size() == 2, "%s uses an outer flame and a white-hot core" % kind)
		var visual_layers: Array[float] = []
		var shaders_valid := true
		for flame_entry in area._flames:
			var flame := flame_entry.get("node") as MeshInstance3D
			var material := flame_entry.get("material") as ShaderMaterial
			if flame == null or material == null or material.shader != IncendiaryArea.FLAME_SHADER:
				shaders_valid = false
				continue
			visual_layers.append(float(material.get_shader_parameter("layer")))
			var quad := flame.mesh as QuadMesh
			shaders_valid = shaders_valid and quad != null and quad.size.y <= 0.82
		visual_layers.sort()
		_expect(shaders_valid and visual_layers == [0.0, 1.0],
			"%s flames use the animated low CS2-style shader" % kind)
		area._damage_tick()
		area.set_physics_process(false)
		area.set_process(false)
		area.queue_free()


func _test_single_planted_c4_guard() -> void:
	_controller.reset_loadout("T")
	_controller.current_weapon_id = "c4"
	_controller.slots[5] = "c4"
	var existing := Node3D.new()
	_world.add_child(existing)
	RoundManager.planted_c4 = existing
	var before := _world.get_child_count()
	_controller._complete_c4_plant()
	_expect(_world.get_child_count() == before and String(_controller.slots[5]) == "c4",
		"An existing planted bomb blocks every second planting attempt")
	RoundManager.planted_c4 = null
	existing.free()

	_controller.slots[5] = ""
	before = _world.get_child_count()
	_controller._complete_c4_plant()
	_expect(_world.get_child_count() == before, "A stale C4 viewmodel without inventory cannot plant")
	_controller.slots[5] = "c4"
	_controller._complete_c4_plant()
	var planted := RoundManager.planted_c4 as PlantedC4
	_expect(is_instance_valid(planted) and String(_controller.slots[5]).is_empty(),
		"The one legitimate C4 creates exactly one planted object and is consumed")
	if planted != null:
		planted.set_process(false)
		_controller.current_weapon_id = "c4"
		_controller.slots[5] = "c4"
		before = _world.get_child_count()
		_controller._complete_c4_plant()
		_expect(_world.get_child_count() == before and RoundManager.planted_c4 == planted,
			"A second carrier cannot replace or duplicate the live planted C4")
		RoundManager.planted_c4 = null
		planted.free()
	_controller.reset_loadout("T")


func _test_grenade_world_scale() -> void:
	for wid in ["flashbang", "hegrenade", "smokegrenade", "decoy", "molotov", "incendiary"]:
		var projectile := GrenadeProjectile.new()
		_world.add_child(projectile)
		projectile.set_physics_process(false)
		projectile.setup_grenade(wid, _actor, Vector3.ZERO)
		var thrown_model := projectile.get_child(0) as Node3D
		_expect(thrown_model != null and thrown_model.scale.is_equal_approx(Vector3.ONE * GameData.GRENADE_WORLD_SCALE),
			"%s thrown model uses the enlarged shared scale" % wid)
		projectile.free()

		var drop := DroppedWeapon.new()
		_world.add_child(drop)
		drop.set_physics_process(false)
		drop.setup_drop(wid, 1, 0, Vector3.ZERO)
		var dropped_model := drop._visual_root.get_child(0) as Node3D
		_expect(dropped_model != null and dropped_model.scale.is_equal_approx(Vector3.ONE * GameData.GRENADE_DROP_SCALE),
			"%s dropped model uses the larger floor-pickup scale" % wid)
		_expect(is_equal_approx(GameData.GRENADE_WORLD_SCALE, 0.90) and is_equal_approx(GameData.GRENADE_DROP_SCALE, 1.0),
			"Thrown grenades stay at 0.90 while dropped grenades use 1.0")
		drop.free()


func _make_test_collision(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	_world.add_child(body)
	body.position = pos
	body.add_child(collision)
	return body


func _test_fire_spread() -> void:
	var floor_body := _make_test_collision(Vector3(12.0, 0.20, 12.0), Vector3(0.0, -0.10, 0.0))
	var wall_body := _make_test_collision(Vector3(0.20, 2.0, 10.0), Vector3(0.65, 1.0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var area := IncendiaryArea.new()
	_world.add_child(area)
	area.global_position = Vector3(0.0, 0.03, 0.0)
	area.setup_fire(null, "incendiary")
	area.set_physics_process(false)
	area.set_process(false)
	_expect(area._patches.size() == 1 and not area._flames.is_empty(), "Fire begins with one visible ignition patch")
	for _step in range(26):
		area._physics_process(0.052)
		area._process(0.052)
	_expect(area._patches.size() > 6 and area._current_radius > 1.0, "Fire physically expands into staggered ground patches")
	var crossed_wall := false
	for patch in area._patches:
		var pos: Vector3 = patch.get("pos", Vector3.ZERO)
		# The near wall face is x=0.55; allow only a tiny contact epsilon.
		if pos.x > 0.551:
			crossed_wall = true
	_expect(not crossed_wall, "Fire propagation cannot cross a solid wall")

	var target := FakeActor.new()
	_world.add_child(target)
	target.position = Vector3(0.78, 0.0, 0.0)
	RoundManager.actors.append(target)
	area._damage_tick()
	_expect(is_zero_approx(target.damage_received), "Fire damage is blocked by the same wall as its visuals")
	target.position = Vector3(-0.25, 0.0, 0.0)
	area._damage_tick()
	_expect(target.damage_received > 0.0, "A target on a burning patch receives incendiary damage")
	RoundManager.actors.erase(target)
	target.free()
	area.free()
	floor_body.free()
	wall_body.free()


func _test_crate_rule() -> void:
	var crate := BSPBreakable.new()
	crate.health = 250.0
	crate.bulletproof = true
	crate.material_type = 1
	_world.add_child(crate)
	_world.breakables.append(crate)
	crate.apply_damage(500.0, Vector3.ZERO, false)
	_expect(crate.health == 250.0 and not crate.broken, "Bullets never destroy bomb-site crates")
	# Match the maximum C4 effect multiplier: one blast must leave HP remaining.
	RoundManager.apply_world_explosion_physics(Vector3.ZERO, 29.025, 0.0, 2.4725)
	_expect(not crate.broken and crate.health > 0.0 and crate.health < 250.0, "One C4-scale explosion damages but cannot delete a 250-HP crate")
	_world.breakables.clear()
	crate.free()


func _equip(wid: String, clip: int, reserve: int) -> void:
	_controller.clear_all_weapons()
	_controller.give_weapon(wid, clip, reserve)
	_controller.equip_weapon_by_id(wid)
	_controller.fire_cooldown = 0.0


func _latest_grenade() -> GrenadeProjectile:
	for i in range(_world.get_child_count() - 1, -1, -1):
		var child := _world.get_child(i)
		if child is GrenadeProjectile:
			return child
	return null


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _instance_bounds(root: Node3D) -> AABB:
	var result := AABB()
	var first := true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.mesh != null:
			var box: AABB = node.global_transform * node.get_aabb()
			result = box if first else result.merge(box)
			first = false
		for child in node.get_children():
			stack.append(child)
	return result


func _collect_wavs(directory: String, output: Array[String]) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if name not in [".", ".."]:
			var path := directory + "/" + name
			if dir.current_is_dir():
				_collect_wavs(path, output)
			elif name.to_lower().ends_with(".wav"):
				output.append(path)
		name = dir.get_next()
	dir.list_dir_end()
