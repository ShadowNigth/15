extends Node
var checks: int = 0
var failures: int = 0
var hud: CSHud
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[HUD QA] " + label)
func _ready() -> void:
	_run.call_deferred()
func settle(frames: int = 8) -> void:
	for frame in range(frames):
		await get_tree().process_frame
func capture(name: String) -> void:
	var output := OS.get_environment("HUD_CAPTURE_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(output)
	await settle()
	RenderingServer.force_draw(false)
	expect(get_viewport().get_texture().get_image().save_png(output.path_join(name + ".png")) == OK, "framebuffer " + name)
func _run() -> void:
	UICustomization.hud.clear()
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_tree().root.size = Vector2i(1280, 720)
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 9
	GameData.start_money = 16000
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world.team_menu.close_menu(false)
	world._on_player_team_chosen("CT", "sas", false)
	hud = world.hud
	var player := world.player
	var weapon := player.weapon_ctrl
	RoundManager.state_timer = 88
	player.money = 1400
	player.health = 44
	player.armor = 100
	player.has_helmet = true
	hud._on_money(1400, 0)
	hud._on_hp_armor(44, 100, true)
	weapon.give_weapon("mp7", 16, 120)
	weapon.give_weapon("hegrenade")
	weapon.give_weapon("flashbang")
	weapon.equip_weapon_by_id("mp7")
	await settle()
	expect(hud._radar_panel.clip_children == CanvasItem.CLIP_CHILDREN_AND_DRAW, "true circular radar alpha clipping")
	expect(hud._ov_tex != null and hud._ov_affine.size() >= 4, "original affine overview retained")
	expect(hud.layout_elements.size() == 10, "all ten editor groups retained")
	expect(hud._hp_label.text == "44" and hud._armor_label.text == "100", "live vitals")
	expect(hud._money_label.text == "$1400", "live money")
	expect(hud._ammo_label.text == "16", "live numerical magazine")
	expect(hud._native_ammo_icon == null, "no removed magazine HUD icon reintroduced")
	expect(hud._inv_icons.size() == 5, "primary secondary knife utility bomb rows")
	expect(hud._inv_icons[3].texture != null, "owned utility appears even without slot dictionary entry")
	expect(RoundManager.actors.size() == 10, "portrait strip uses actual match roster")
	hud._on_kill_logged("CT player", "CT", "T player", "T", "mp7", true)
	await settle(60)
	await capture("hud_firearm")
	var hashes: Dictionary = {}
	var firearm_icon := GameData.equipment_icon("mp7")
	for option in GameData.get_knife_options():
		expect(GameData.select_knife(String(option.id)), "select knife " + String(option.id))
		var icon := GameData.equipment_icon("knife")
		expect(icon != null, "geometry silhouette " + String(option.id))
		if icon != null:
			expect(icon.resource_path.ends_with("/" + String(option.id) + ".png"), "icon follows exact equipped model " + String(option.id))
			hashes[icon.get_image().get_data().hex_encode().sha256_text()] = true
		hud._process(0.016)
		expect(hud._inv_icons[2].texture == icon, "inventory refresh on loadout change " + String(option.id))
	expect(hashes.size() >= 22, "knife silhouettes are distinct, not recoloured generic icons")
	expect(GameData.equipment_icon("mp7") == firearm_icon, "knife changes never replace firearm icon")
	GameData.select_knife("karambit")
	weapon.equip_weapon_by_id("knife")
	await settle()
	expect(hud._weapon_icon.texture == GameData.equipment_icon("knife"), "active weapon icon is karambit")
	expect(hud._inv_icons[2].modulate == CSHud.HUD_WHITE, "only active inventory row fully highlighted")
	expect(hud._ammo_label.text.is_empty(), "melee has no fake ammunition")
	expect(player._cur_vm_model_name == "v_knife_karambit", "HUD icon matches actual in-hand viewmodel")
	await settle(60)
	await capture("hud_karambit")
	get_tree().root.size = Vector2i(1024, 768)
	await settle()
	for id in ["radar", "score", "health", "equipment"]:
		var rect: Rect2 = hud.layout_elements[id].get_global_rect()
		expect(Rect2(Vector2.ZERO, Vector2(1024, 768)).encloses(rect), "4:3 group stays on screen " + id)
	await capture("hud_karambit_4x3")
	hud._on_hp_armor(12, 0, false)
	expect(hud._hp_label.get_theme_color("font_color") == CSHud.RED_WARN, "low health remains red")
	hud._on_ammo_updated(0, 90)
	expect(hud._ammo_label.text == "0" and hud._ammo_reserve_label.text.contains("90"), "empty firearm ammo remains numerical")
	world.queue_free()
	await settle()
	GameData.select_knife("original")
	print("[HUD QA] %s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
