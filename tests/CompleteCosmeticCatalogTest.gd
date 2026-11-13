extends Node
## Complete shipped catalog, exercised through the real player and material path.
var _checks := 0
var _failures: Array[String] = []
var _capture := false
var _output := "/tmp/catalog-captures"


func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
		push_error("[CATALOG TEST] " + label)


func _run() -> void:
	if _capture and DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	GameData.select_knife("original")
	GameData.select_glove("classic")
	var original: Dictionary = GameData.weapons["knife"].duplicate(true)
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 2
	GameData.freeze_time = 600.0
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban")
	world.team_menu.close_menu()
	var player := world.player
	var knife_count := 0
	var knife_finishes := 0
	_expect(GameData.get_knife_options().size() == 23, "Original plus all 22 source models")
	for raw in GameData.get_knife_options():
		var option := raw as Dictionary
		var key := String(option["id"])
		if key == "original":
			continue
		knife_count += 1
		_expect(GameData.select_knife(key), "Select " + key)
		for field in original:
			if field not in ["name", "v_model", "p_model", "w_model"]:
				_expect(GameData.weapons["knife"][field] == original[field], key + " unchanged rule " + String(field))
		player.weapon_ctrl.equip_slot(2)
		player.weapon_ctrl.equip_slot(3)
		await get_tree().process_frame
		_expect(player._cur_vm_model_name == String(option["v_model"]) and player._vm_anim != null, key + " real viewmodel")
		_expect(_has_agent_arms(player._vm_model_root), key + " original arms")
		_expect((_material(player._vm_model_root, "ct_base_glove.bmp") != null or player._vm_model_root.has_meta("native_view_rig")), key + " original gloves")
		var native_meta: Dictionary = GameData.models_meta["weapons/" + String(option["v_model"])]
		_expect(bool(native_meta.get("native_cs2_animation", false)), key + " model-specific native animation")
		_expect(bool(native_meta.get("authored_right_hand", false)), key + " native right-handed camera coordinates")
		for clip_name in native_meta["sequences"]:
			_expect(player._vm_anim.has_animation(String(clip_name)), key + " native clip " + String(clip_name))
			if player._vm_anim.has_animation(String(clip_name)):
				_expect(absf(player._vm_anim.get_animation(String(clip_name)).length - float(native_meta["seq_durations"][clip_name])) < 0.002, key + " original duration " + String(clip_name))
		var source := _material(player._vm_model_root, "sc_cs2_" + key)
		_expect(source != null, key + " own material")
		for clip in ["draw", "idle", "slash1", "slash2", "midslash1", "midslash2", "stab", "stab_miss", "inspect"]:
			_expect(player._vm_anim.has_animation(clip), key + " clip " + clip)
		if key in ["butterfly", "falchion", "flip", "navaja", "outdoor", "stiletto"]:
			var skeleton := SportGloves._find_skeleton(player._vm_model_root)
			var bone := skeleton.find_bone("cs2_mechanical_blade")
			_expect(bone >= 0, key + " articulated blade, not a rigid folding knife")
			if bone >= 0:
				player.play_viewmodel_sequence(["draw"])
				player._vm_anim.seek(0.0, true)
				var start := skeleton.get_bone_pose_rotation(bone)
				var moved := false
				for at in [0.2, 0.4, 0.6, 0.79]:
					player._vm_anim.seek(at, true)
					moved = moved or absf(start.dot(skeleton.get_bone_pose_rotation(bone))) < 0.9999
				_expect(moved, key + " source blade movement survives import")
				if _capture and key == "butterfly":
					player._vm_anim.seek(0.4, true)
					await _save("butterfly_fold")
		player._play_idle_viewmodel()
		for frame in range(3):
			await get_tree().physics_frame
		if _capture:
			await _save(key + "_idle")
		# Inspect every available native variant, not an inherited Kukri clip.
		for inspection in native_meta["inspect_clips"]:
			player.play_viewmodel_sequence([String(inspection)])
			var length := player._vm_anim.get_animation(String(inspection)).length
			var skeleton := SportGloves._find_skeleton(player._vm_model_root)
			var hand := skeleton.find_bone("v_weapon.Bip01_R_Hand")
			_expect(skeleton.get_bone_global_pose(hand).basis.determinant() < 0.0, key + " port hand parity survives native retarget")
			player._vm_anim.seek(length * 0.1, true)
			var before := skeleton.get_bone_global_pose(hand)
			player._vm_anim.seek(length * 0.65, true)
			_expect(not before.is_equal_approx(skeleton.get_bone_global_pose(hand)), key + " hands move during " + String(inspection))
			if _capture:
				var pose_index := 0
				for fraction in [0.15, 0.35, 0.6, 0.85]:
					pose_index += 1
					player.play_viewmodel_sequence([String(inspection)])
					player._vm_anim.seek(length * fraction, true)
					await _save(key + "_" + String(inspection) + "_pose" + str(pose_index))
		player._play_idle_viewmodel()
		for skin_raw in GameData.get_weapon_skin_options("knife"):
			var skin := skin_raw as Dictionary
			knife_finishes += 1
			_expect(GameData.select_weapon_skin("knife", String(skin["id"])), key + " selects " + String(skin["id"]))
			if source != null:
				for mode in ["vm", "vm_flip", "w_held", "w_drop"]:
					var styled := GameData.get_styled_model_material(source, mode) as BaseMaterial3D
					_expect(styled != null and styled.albedo_texture == GameData.get_texture(String(skin["texture"])), key + " finish art " + mode)
					_expect(styled != null and styled.albedo_color == source.albedo_color, key + " no white chrome wash " + mode)
					_expect(styled != null and styled.metallic > 0.0 and styled.metallic <= 0.42 and styled.roughness >= 0.479, key + " subordinate chrome " + mode)
					_expect(styled != null and styled.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_GREEN and styled.metallic_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_BLUE, key + " matching ORM channels " + mode)
		GameData.select_weapon_skin("knife", "original")
		var glove: Dictionary = GameData.get_glove_options()[0]
		GameData.select_glove(String(glove["id"]))
		player._rebuild_viewmodel("knife")
		_expect(_has_sport(player._vm_model_root), key + " native Sport Gloves geometry")
		GameData.select_glove("classic")
	GameData.select_knife("butterfly")
	GameData.select_weapon_skin("knife", "factory")
	GameData.select_knife("talon")
	_expect(GameData.get_selected_weapon_skin_id("knife") == "original", "Knife choices do not leak across model UVs")
	GameData.select_knife("butterfly")
	_expect(GameData.get_selected_weapon_skin_id("knife") == "factory", "Each knife remembers its own finish")
	GameData.select_weapon_skin("knife", "original")
	_expect(knife_count == 22 and knife_finishes == 42, "Complete 22 model / 42 factory-and-painted knife catalog")
	var guns := 0
	for raw_wid in GameData.weapon_skins["weapons"]:
		var wid := String(raw_wid)
		if wid.begins_with("knife_"):
			continue
		var entry: Dictionary = GameData.weapon_skins["weapons"][wid]
		for raw_skin in entry["options"]:
			var skin := raw_skin as Dictionary
			if not String(skin["id"]).begins_with("sc_"):
				continue
			guns += 1
			_expect(GameData.select_weapon_skin(wid, String(skin["id"])), wid + " accepts source finish")
			var spec: Dictionary = GameData.weapons[wid]
			player.weapon_ctrl.give_weapon(wid, maxi(1, int(spec.get("clip_size", 1))), 90)
			player.weapon_ctrl.equip_weapon_by_id(wid)
			player._rebuild_viewmodel(wid)
			player._play_idle_viewmodel()
			await get_tree().process_frame
			for field in ["v_model", "p_model", "w_model"]:
				var packed := GameData.get_model_scene("weapons/" + String(spec[field]))
				_expect(packed != null, wid + " original " + field)
				if packed == null:
					continue
				var model := packed.instantiate() as Node3D
				for mat_name in entry["materials"]:
					var mat := _material(model, String(mat_name))
					_expect(mat != null, wid + " paint material " + String(mat_name))
					if mat != null:
						for mode in ["vm", "w_held", "w_drop"]:
							var styled := GameData.get_styled_model_material(mat, mode) as BaseMaterial3D
							_expect(styled != null and styled.albedo_texture == GameData.get_texture(String(skin["texture"])), wid + " exact selected texture " + mode)
				model.free()
			if _capture:
				await _save(wid + "_" + String(skin["id"]))
			GameData.select_weapon_skin(wid, "original")
	_expect(guns == 44, "All 44 shipped gun finishes")
	GameData.select_knife("original")
	_expect(GameData.weapons["knife"] == original, "Original knife reversible")
	_expect(_checks > 1500, "Full catalog test completed, not a partial coroutine")
	world.queue_free()
	AudioManager.stop_all()
	await get_tree().process_frame
	print("[CATALOG TEST] %s: %d checks, %d knives, %d knife finishes, %d gun finishes" % ["PASS" if _failures.is_empty() else "FAIL", _checks, knife_count, knife_finishes, guns])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _material(root: Node, name: String) -> BaseMaterial3D:
	for mesh in SportGloves._find_meshes(root):
		for surface in range(mesh.mesh.get_surface_count()):
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat != null and mat.resource_name == name:
				return mat
	return null


func _has_sport(root: Node) -> bool:
	if root.has_meta("sport_gloves"):
		return true
	for child in root.get_children():
		if _has_sport(child):
			return true
	return false


func _save(name: String) -> void:
	get_tree().paused = true
	for frame in range(4):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	_expect(image != null and not image.is_empty(), "Rendered framebuffer " + name)
	if image != null and not image.is_empty():
		_expect(image.save_png(_output.path_join(name + ".png")) == OK, "Full PNG " + name)
		image.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		_expect(image.save_jpg(_output.path_join(name + ".jpg"), 0.35) == OK, "Review JPEG " + name)
	get_tree().paused = false


func _has_agent_arms(root: Node) -> bool:
	if root == null or String(root.get_meta("view_agent", "")).is_empty():
		return false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.has_meta("agent_arms") and String(mesh.get_meta("agent_arms")) != "sport" and mesh.mesh != null and mesh.skin != null:
			return true
	return false
