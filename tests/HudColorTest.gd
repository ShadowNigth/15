extends Node
var checks := 0
var failures := 0
func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[HUD COLOR] " + text)
func settle(frames: int = 6) -> void:
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
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var original := UICustomization.snapshot()
	var old_warning := GameData.low_ammo_warning
	GameData.low_ammo_warning = true
	UICustomization.hud.clear()
	UICustomization.reset_hud_appearance()
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_tree().root.size = Vector2i(1280, 720)
	var editor := UICustomizationEditor.open(self)
	editor.show_tab(true)
	await settle()
	var hud := editor.hud_preview
	var id := hud.get_instance_id()
	var crosshair := GameData.crosshair_color
	var cyan := Color(0.2, 0.9, 1.0, 0.98)
	editor.hud_color_picker.color_changed.emit(cyan)
	expect(UICustomization.get_hud_color().is_equal_approx(cyan), "real colour picker updates fixed HUD preference")
	expect(editor.hud_color_picker.color.is_equal_approx(cyan), "colour button shows selected fixed colour")
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_RIGHT
	arrow.pressed = true
	editor.hud_color_picker.grab_focus()
	editor._input(arrow)
	expect(UICustomization.hud.is_empty(), "focused colour controls do not move HUD via arrow keys")
	editor.hud_color_picker.get_popup().popup_centered(Vector2i(320, 400))
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._input(escape)
	expect(not editor.closing, "Escape belongs to open colour popup, not editor cancel")
	editor.hud_color_picker.get_popup().hide()
	expect(hud._money_label.get_theme_color("font_color").is_equal_approx(cyan), "live money tint")
	expect(hud._hp_label.get_theme_color("font_color").is_equal_approx(cyan), "live health tint")
	expect(hud._inv_icons[2].modulate.r == cyan.r, "knife silhouette participates in tint")
	expect((hud._radar_panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color.is_equal_approx(cyan), "radar border tint")
	expect(GameData.crosshair_color == crosshair, "HUD colour never changes crosshair preference")
	await capture("hud_color_fixed")
	for child in editor.inspector.get_children():
		if child is CheckBox and child.text.begins_with("RGB"):
			child.button_pressed = true
		if child is HSlider and child.max_value == 30:
			child.value = 6.0
	expect(UICustomization.hud_appearance.rgb and editor.hud_color_picker.disabled, "real RGB checkbox selects automatic mode")
	expect(UICustomization.hud_appearance.rgb_period == 6.0, "RGB speed slider works")
	var node_count := hud.get_child_count()
	var first := UICustomization.get_hud_color()
	UICustomization._process(1.5)
	await settle()
	var second := UICustomization.get_hud_color()
	expect(not first.is_equal_approx(second), "automatic RGB advances over time")
	expect(hud._hp_label.get_theme_color("font_color").is_equal_approx(second), "editor preview animates despite disabled gameplay process")
	expect(hud.get_instance_id() == id and hud.get_child_count() == node_count, "RGB never rebuilds HUD tree")
	expect(UICustomization.hud.is_empty(), "RGB does not dirty layout positions")
	hud._on_hp_armor(12, 0, false)
	hud._on_ammo_updated(0, 90)
	for tick in range(12):
		UICustomization._process(0.5)
		hud.update_hud_color()
		expect(hud._hp_label.get_theme_color("font_color") == CSHud.RED_WARN, "critical health stays red through RGB")
		expect(hud._ammo_label.get_theme_color("font_color") == CSHud.RED_WARN, "empty ammo stays red through RGB")
	hud._on_hp_armor(100, 100, true)
	hud._on_ammo_updated(30, 90)
	await capture("hud_color_rgb")
	var saved := UICustomization.hud_appearance.duplicate(true)
	editor.preference_path = "user://hud_color_test.cfg"
	editor.save_and_close()
	await settle()
	UICustomization.reset_hud_appearance()
	UICustomization.load_preferences("user://hud_color_test.cfg")
	expect(UICustomization.hud_appearance.rgb and UICustomization.hud_appearance.rgb_period == saved.rgb_period, "saved RGB mode and speed survive disk roundtrip")
	expect(UICustomization.hud_appearance.color.is_equal_approx(cyan), "fixed fallback colour survives RGB save")
	editor = UICustomizationEditor.open(self)
	editor.show_tab(true)
	editor.set_hud_rgb(false)
	expect(UICustomization.get_hud_color().is_equal_approx(cyan), "RGB off restores chosen fixed colour")
	editor.set_hud_color(Color.MAGENTA)
	editor.cancel()
	await settle()
	expect(UICustomization.hud_appearance.rgb and UICustomization.hud_appearance.color.is_equal_approx(cyan), "Cancel rolls back mode and fixed colour together")
	editor = UICustomizationEditor.open(self)
	editor.show_tab(true)
	editor.reset_tab()
	expect(UICustomization.hud_appearance == UICustomization.HUD_APPEARANCE_DEFAULTS, "reset HUD tab restores default gold and disables RGB")
	editor.cancel()
	await settle()
	UICustomization.restore({"hud": {}})
	expect(UICustomization.hud_appearance == UICustomization.HUD_APPEARANCE_DEFAULTS, "old preference files migrate to static gold")
	UICustomization.restore({"hud_appearance": {"color": Color(NAN, 0, 0), "rgb": "yes", "rgb_period": INF}})
	expect(UICustomization.hud_appearance == UICustomization.HUD_APPEARANCE_DEFAULTS, "invalid appearance data rejected safely")
	UICustomization.restore({"hud_appearance": {"rgb_period": -5}})
	expect(UICustomization.hud_appearance.rgb_period == 3.0, "RGB cycle cannot become zero or negative")
	UICustomization.restore({"hud_appearance": {"rgb_period": 500}})
	expect(UICustomization.hud_appearance.rgb_period == 30.0, "cycle upper bound")
	# Real match HUD follows the same clock and settings after closing the editor.
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 0
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world.team_menu.close_menu(false)
	world._on_player_team_chosen("CT", "sas", false)
	RoundManager.state_timer = 600
	world.player.weapon_ctrl.give_weapon("mp7", 16, 120)
	world.player.weapon_ctrl.equip_weapon_by_id("mp7")
	UICustomization.hud_appearance.rgb = true
	UICustomization.hud_appearance.rgb_period = 6.0
	UICustomization.changed.emit()
	await settle(60)
	expect(world.hud._money_label.get_theme_color("font_color").is_equal_approx(UICustomization.get_hud_color()), "real gameplay HUD animates without editor")
	await capture("hud_color_gameplay")
	get_tree().root.size = Vector2i(1024, 768)
	editor = UICustomizationEditor.open(self)
	editor.show_tab(true)
	await settle()
	expect(editor.hud_color_picker.get_global_rect().position.x >= 0 and editor.hud_color_picker.get_global_rect().end.x < 1024, "4:3 colour controls stay inside inspector")
	await capture("hud_color_editor_4x3")
	editor.cancel()
	world.queue_free()
	await settle()
	GameData.low_ammo_warning = old_warning
	UICustomization.restore(original)
	DirAccess.remove_absolute("user://hud_color_test.cfg")
	print("[HUD COLOR] %s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
