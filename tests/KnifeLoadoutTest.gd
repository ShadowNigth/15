extends Node
## Native gameplay + optional real OpenGL framebuffer evidence for knife loadouts.
var _checks := 0
var _failures: Array[String] = []
var _capture := false
var _output := "/tmp/knife-captures"


func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[KNIFE TEST] " + description)


func _run() -> void:
	if _capture and DisplayServer.get_name() == "headless":
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	GameData.select_knife("original")
	var original: Dictionary = GameData.weapons["knife"].duplicate(true)
	var original_ak: Dictionary = GameData.weapons["ak47"].duplicate(true)
	_expect(GameData.get_knife_options().size() == 4, "Original plus three distinct new knives")
	_expect(not GameData.select_knife("invalid"), "Reject invalid loadout without changing the knife")
	_expect(GameData.weapons["knife"] == original, "Invalid selection leaves original intact")
	var menu := (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(menu)
	_expect(menu._knife_opt != null and menu._knife_opt.item_count == 4, "Create Game exposes all knife choices")
	menu._select_knife_for_match("m9")
	_expect(GameData.selected_knife_id == "m9" and menu._viewer_anim != null, "Arsenal selection configures a real animated knife preview")
	menu.queue_free()
	await get_tree().process_frame
	for key in ["karambit", "m9", "bayonet"]:
		_expect(GameData.select_knife(key), "Select " + key)
		var spec: Dictionary = GameData.weapons["knife"]
		for field in original:
			if field not in ["v_model", "p_model", "w_model", "name"]:
				_expect(spec[field] == original[field], key + " preserves melee rule " + String(field))
		_expect(GameData.weapons.size() == 43 and GameData.weapons["ak47"] == original_ak, "No firearm or economy roster replacement")
		for field in ["v_model", "p_model", "w_model"]:
			_expect(GameData.get_model_scene("weapons/" + String(spec[field])) != null, key + " loads " + field)
		GameData.selected_map = "de_dust2"
		GameData.bot_count = 2
		GameData.freeze_time = 60.0
		GameData.select_glove("classic")
		var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
		add_child(world)
		world._on_player_team_chosen("CT", "urban")
		world.team_menu.close_menu()
		var player := world.player
		player.weapon_ctrl.equip_slot(3)
		await get_tree().process_frame
		_expect(player.weapon_ctrl.current_weapon_id == "knife" and player.weapon_ctrl.slots[3] == "knife", "Slot 3 remains a real knife")
		_expect(player._cur_vm_model_name == "v_knife_" + key and player._vm_anim != null, key + " builds through production PlayerController")
		if player._vm_anim == null:
			get_tree().quit(1)
			return
		_expect(_surface_count(player._vm_model_root, "sc_cs2_" + key) > 0, key + " renders its distinct knife material and geometry")
		for clip in ["draw", "idle", "slash1", "slash2", "midslash1", "midslash2", "stab_miss", "stab", "inspect"]:
			_expect(player._vm_anim.has_animation(clip), key + " retains animation " + clip)
		_expect(_surface_count(player._vm_model_root, "ct_arms.bmp") > 0, key + " preserves original arms")
		_expect(_surface_count(player._vm_model_root, "ct_base_glove.bmp") > 0, key + " preserves original gloves")
		for frame in range(65):
			await get_tree().physics_frame
		_expect(String(player._vm_anim.current_animation) == "idle", key + " draw returns to idle")
		if _capture:
			await _save_capture(key + "_idle")
		player._try_inspect_viewmodel()
		_expect(String(player._vm_anim.current_animation) == "inspect", key + " T inspection plays")
		for frame in range(60):
			await get_tree().physics_frame
		if _capture:
			await _save_capture(key + "_inspect")
		# Exercise the same primary/secondary controller entry points as input.
		RoundManager.state = RoundManager.State.LIVE
		RoundManager.state_timer = 600.0
		player.weapon_ctrl.fire_cooldown = 0.0
		player.weapon_ctrl.trigger_primary(false, 0.0166667)
		_expect(String(player._vm_anim.current_animation) in ["midslash1", "midslash2", "slash1", "slash2"], key + " primary plays a light slash")
		_expect(player.weapon_ctrl.fire_cooldown > 0.0, key + " primary has classic cooldown")
		player.weapon_ctrl.fire_cooldown = 0.0
		player.weapon_ctrl.trigger_secondary()
		_expect(String(player._vm_anim.current_animation) in ["stab", "stab_miss"], key + " secondary plays heavy stab")
		player.weapon_ctrl.equip_slot(2)
		player.weapon_ctrl.equip_slot(3)
		_expect(player._cur_vm_model_name == "v_knife_" + key, key + " survives pistol/knife switching")
		player.weapon_ctrl.reset_loadout("CT")
		player.weapon_ctrl.equip_slot(3)
		_expect(player._cur_vm_model_name == "v_knife_" + key, key + " survives round loadout reset")
		var glove: Dictionary = GameData.get_glove_options()[0]
		GameData.select_glove(String(glove["id"]))
		player._rebuild_viewmodel("knife")
		_expect(_has_sport_glove(player._vm_model_root), key + " supports real Sport Glove geometry")
		_expect(_surface_count(player._vm_model_root, "ct_base_glove.bmp") == 0 and _surface_count(player._vm_model_root, "ct_arms.bmp") > 0, key + " swaps only gloves, never arms")
		world.queue_free()
		AudioManager.stop_all()
		await get_tree().process_frame
		await get_tree().process_frame
	GameData.select_knife("original")
	_expect(GameData.weapons["knife"] == original, "Original knife restored without lost fields")
	_expect(_checks >= 200, "All three gameplay test cases completed")
	print("[KNIFE TEST] %s: %d checks; three knives, original arms, Sport Gloves, melee and round resets" % ["PASS" if _failures.is_empty() else "FAIL", _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _surface_count(root: Node, material_name: String) -> int:
	var count := 0
	if root is MeshInstance3D:
		var mesh := (root as MeshInstance3D).mesh
		if mesh != null:
			for surface in range(mesh.get_surface_count()):
				var material := mesh.surface_get_material(surface)
				if material != null and material.resource_name == material_name:
					count += 1
	for child in root.get_children():
		count += _surface_count(child, material_name)
	return count


func _has_sport_glove(root: Node) -> bool:
	if root.has_meta("sport_gloves"):
		return true
	for child in root.get_children():
		if _has_sport_glove(child):
			return true
	return false


func _save_capture(name: String) -> void:
	# Capture the production first-person camera, HUD and BSP after real frames.
	get_tree().paused = true
	for frame in range(4):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	_expect(image != null and not image.is_empty(), "Nonempty OpenGL framebuffer " + name)
	if image != null and not image.is_empty():
		_expect(image.save_png(_output.path_join(name + ".png")) == OK, "Save full-resolution " + name)
		image.resize(480, 270, Image.INTERPOLATE_LANCZOS)
		_expect(image.save_jpg(_output.path_join(name + ".jpg"), 0.35) == OK, "Save review JPEG " + name)
	get_tree().paused = false
