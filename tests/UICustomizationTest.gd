extends Node
var checks := 0
var failures := 0

func expect(value: bool, text: String) -> void:
	checks += 1
	print("[UI EDITOR] %s: %s" % ["OK" if value else "FAIL", text])
	if not value:
		failures += 1

func _ready() -> void:
	get_tree().create_timer(120).timeout.connect(func(): get_tree().quit(1))
	run.call_deferred()

func capture(name: String) -> void:
	for i in range(3):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute("/tmp/dm-polish-review")
		expect(get_viewport().get_texture().get_image().save_png("/tmp/dm-polish-review/" + name + ".png") == OK, "Captured " + name)

func run() -> void:
	var initial := UICustomization.snapshot()
	UICustomization.reset_crosshair()
	UICustomization.hud.clear()
	var editor := UICustomizationEditor.open(self)
	await get_tree().process_frame
	expect(UICustomizationEditor.open(self) == editor, "One modal instance")
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Mouse available")
	editor.set_crosshair("dot", true)
	editor.set_crosshair("t_shape", true)
	editor.set_crosshair("length", 14.0)
	GameData.crosshair_color = Color(0, 0.9, 1, 0.8)
	editor.simulation = true
	editor.populate_inspector()
	expect(UICustomization.crosshair.dot and UICustomization.crosshair.t_shape, "Live crosshair options")
	await capture("editor_crosshair")
	editor.show_tab(true)
	await get_tree().process_frame
	await get_tree().process_frame
	expect(editor.hud_preview.layout_elements.size() == 10, "Ten real HUD groups")
	expect(not editor.hud_preview.layout_elements.values().has(editor.hud_preview._flash_rect), "Flash overlay cannot be hidden")
	expect(not editor.hud_preview.layout_elements.values().has(editor.hud_preview._scope_root), "Scope stays protected")
	expect(editor.hud_preview._ammo_label.text == "30", "Numerical ammunition preview")
	expect(editor.hud_preview.layout_elements.equipment.size.y == 268, "Equipment bounds include inventory above ammunition")
	for id in UICustomizationEditor.NAMES:
		editor.select_element(id)
		editor.update_layout("scale", 1.2)
		editor.update_layout("opacity", 0.55)
		editor.move_element(Vector2(400, 200))
		var target: Control = editor.hud_preview.layout_elements[id]
		expect(is_equal_approx(target.scale.x, 1.2), "Scale applied: " + id)
		expect(is_equal_approx(target.modulate.a, 0.55), "Opacity applied: " + id)
		expect(target.position.x >= 0 and target.position.y >= 0, "Visible bounds: " + id)
		editor.update_layout("visible", false)
		expect(not target.visible, "Visibility applied: " + id)
		editor.update_layout("visible", true)
	editor.reset_tab()
	editor.select_element("radar")
	var target: Control = editor.hud_preview.layout_elements.radar
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = target.position + Vector2(10, 10)
	editor.handles._gui_input(click)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(240, 170)
	editor.handles._gui_input(motion)
	expect(UICustomization.hud.has("radar") and target.position.distance_to(Vector2(230, 160)) < 2, "Actual drag handler moves radar")
	click.pressed = false
	editor.handles._gui_input(click)
	expect(not editor.handles.dragging, "Mouse release ends drag")
	editor.move_element(Vector2(-9999, -9999))
	expect(target.position == Vector2.ZERO, "Drag clamped at top-left")
	editor.move_element(Vector2(9999, 9999))
	expect(target.position.x + target.size.x <= 1281 and target.position.y + target.size.y <= 721, "Drag clamped at bottom-right")
	editor.move_element(Vector2(230, 160))
	editor.update_layout("scale", 1.15)
	editor.populate_inspector()
	await capture("editor_hud")
	preview_resize(editor)
	editor.show_tab(false)
	editor.set_crosshair("dot", true)
	editor.show_tab(true)
	await get_tree().process_frame
	expect(is_instance_valid(editor.hud_preview), "Rapid tab changes preserve a usable preview")
	var saved := UICustomization.snapshot()
	expect(UICustomization.save_preferences("user://ui_test.cfg") == OK, "Config file saved")
	UICustomization.reset_crosshair()
	UICustomization.hud.clear()
	UICustomization.load_preferences("user://ui_test.cfg")
	var loaded := UICustomization.snapshot()
	var same: bool = loaded.crosshair == saved.crosshair and loaded.color.is_equal_approx(saved.color) and loaded.dynamic == saved.dynamic and loaded.hud.keys() == saved.hud.keys()
	for id in saved.hud:
		var a: Dictionary = loaded.hud[id]
		var b: Dictionary = saved.hud[id]
		same = same and Vector2(a.position).is_equal_approx(b.position) and is_equal_approx(a.scale, b.scale) and is_equal_approx(a.opacity, b.opacity) and a.visible == b.visible
	expect(same, "Full disk round-trip (ConfigFile float precision)")
	editor.cancel()
	await get_tree().process_frame
	expect(UICustomization.hud.is_empty(), "Cancel restores layout before editor")
	expect(not UICustomization.crosshair.dot and not UICustomization.crosshair.t_shape, "Cancel restores crosshair")
	UICustomization.restore({"crosshair": {"gap": 999.0, "width": -9.0}, "hud": {"radar": {"scale": 99.0, "opacity": -9.0, "position": Vector2(-9, 9)}, "invalid": 4}})
	expect(UICustomization.crosshair.gap == 30 and UICustomization.crosshair.width == 1, "Invalid crosshair ranges clamped")
	expect(UICustomization.hud.radar.scale == 2.5 and UICustomization.hud.radar.opacity == 0.2, "Invalid HUD ranges clamped")
	expect(UICustomization.hud.radar.position == Vector2(0, 1) and not UICustomization.hud.has("invalid"), "Malformed layout handled")
	UICustomization.restore(initial)
	var menu := MainMenu.new()
	add_child(menu)
	expect(menu._options_panel != null, "WON configuration builds with editor entry")
	menu.queue_free()
	await get_tree().process_frame
	# Real game integration: UI blocking remains active until the command menu closes.
	GameData.bot_count = 0
	GameData.game_mode = "classic"
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban", false)
	world.team_menu.close_menu(false)
	world.pause_menu.open_pause()
	world.player.ui_blocking_input = true
	var weapon := world.player.weapon_ctrl.current_weapon_id
	var actual_hud: CSHud = world.hud
	editor = UICustomizationEditor.open(world.pause_menu)
	editor.show_tab(true)
	await get_tree().process_frame
	editor.select_element("health")
	editor.update_layout("opacity", 0.45)
	expect(is_equal_approx(actual_hud.layout_elements.health.modulate.a, 0.45), "Real gameplay HUD updates live")
	expect(world.player.ui_blocking_input and world.pause_menu.is_open, "Gameplay controls remain blocked")
	expect(world.player.weapon_ctrl.current_weapon_id == weapon, "No equipment changes")
	editor.cancel()
	await get_tree().process_frame
	expect(world.pause_menu.is_open and world.player.ui_blocking_input, "Cancel returns to pause, not gameplay")
	editor = UICustomizationEditor.open(world.pause_menu)
	editor.preference_path = "user://ui_test.cfg"
	editor.set_crosshair("dot", true)
	editor.save_and_close()
	await get_tree().process_frame
	expect(not is_instance_valid(editor), "Save button closes the editor")
	expect(UICustomization.crosshair.dot, "Save keeps applied settings")
	UICustomization.reset_crosshair()
	UICustomization.load_preferences("user://ui_test.cfg")
	expect(UICustomization.crosshair.dot, "Saved editor settings reload")
	world.queue_free()
	await get_tree().process_frame
	UICustomization.restore(initial)
	DirAccess.remove_absolute("user://ui_test.cfg")
	print("[UI EDITOR] %s: %d checks; %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func preview_resize(editor: UICustomizationEditor) -> void:
	var previous := editor.preview_viewport.size_2d_override
	editor.preview_viewport.size_2d_override = Vector2i(960, 720)
	editor.hud_preview.apply_custom_layout()
	var target: Control = editor.hud_preview.layout_elements.radar
	expect(target.position.x + target.size.x * target.scale.x <= 961, "Normalized layout stays on screen at 4:3")
	editor.preview_viewport.size_2d_override = previous
	editor.hud_preview.apply_custom_layout()
