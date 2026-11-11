extends Node
## Real Control layout, catalogue routing and animated native preview regression.
var checks: int = 0
var failures: int = 0
var menu: MainMenu

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[MENU QA] " + label)

func settle() -> void:
	for i in range(4):
		await get_tree().process_frame

func capture(label: String) -> void:
	var output := OS.get_environment("MENU_CAPTURE_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(output)
	await settle()
	RenderingServer.force_draw(false)
	expect(get_tree().root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK, "framebuffer " + label)

func inside(outer: Rect2, inner: Rect2) -> bool:
	return outer.grow(2.0).encloses(inner)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_tree().root.size = Vector2i(1280, 720)
	menu = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await settle()
	expect(not menu._modal_shade.visible and not menu._arsenal_panel.visible, "home opens without modal")
	expect(menu._home_background.camera != null, "live 3D background initialized")
	var original := menu._home_background.selection
	for map_id in MenuBackdrop.MAPS:
		menu._home_background.change_background(map_id, false)
		await settle()
		expect(menu._home_background.selection == map_id and menu._home_background.viewport.get_child_count() == 1, "background replacement without retained worlds " + map_id)
		await capture("menu_background_" + map_id)
	menu._home_background.change_background(original, false)
	menu._home_background.motion = true
	var before := menu._home_background.camera.rotation
	menu._home_background._process(1.0)
	expect(not menu._home_background.camera.rotation.is_equal_approx(before), "cinematic background moves")
	menu._home_background.motion = false
	before = menu._home_background.camera.rotation
	menu._home_background._process(1.0)
	expect(menu._home_background.camera.rotation.is_equal_approx(before), "reduced motion stops camera")
	menu._home_background.motion = true
	await capture("menu_home")
	menu._open_arsenal()
	await settle()
	expect(menu._arsenal_panel.visible and menu._modal_shade.visible, "arsenal opens above modal shield")
	expect(menu._viewer_anim != null and menu._viewer_anim.is_playing(), "native weapon preview animated")
	expect(menu._arsenal_tabs.get_tab_count() == 4, "finishes animations sound and details separated")
	expect(menu._arsenal_list.item_count == menu._arsenal_entries.size(), "all catalogue items available")
	var seen: Dictionary = {}
	for entry in menu._arsenal_entries:
		seen[entry.meta] = true
	for wid in GameData.weapons:
		expect(seen.has(wid), "weapon retained " + String(wid))
	for entry in menu._arsenal_entries:
		if String(entry.meta).begins_with("native:"):
			expect(entry.meta == "native:defuser_item", "removed native characters remain absent")
	await capture("menu_arsenal")
	for category_index in range(1, menu._arsenal_category.item_count):
		menu._arsenal_category.select(category_index)
		menu._refresh_arsenal_list()
		var category := menu._arsenal_category.get_item_text(category_index)
		for item_index in range(menu._arsenal_list.item_count):
			var meta := String(menu._arsenal_list.get_item_metadata(item_index))
			var found := false
			for entry in menu._arsenal_entries:
				if String(entry.meta) == meta and String(entry.category) == category:
					found = true
			expect(found, "category isolation " + category)
	menu._arsenal_category.select(0)
	menu._arsenal_search.text = "ak47"
	menu._refresh_arsenal_list()
	expect(menu._arsenal_list.item_count == 1 and menu._arsenal_list.get_item_metadata(0) == "ak47", "search by internal weapon ID")
	menu._on_arsenal_item_selected(0)
	expect(menu._viewer_current_wid == "ak47", "filtered selection routes to weapon preview")
	menu._arsenal_search.text = "no-such-item-9981"
	menu._refresh_arsenal_list()
	expect(menu._arsenal_list.item_count == 0 and menu._arsenal_count.text.begins_with("SIN RESULTADOS"), "explicit empty search state")
	menu._arsenal_search.text = ""
	menu._refresh_arsenal_list()
	expect(menu._arsenal_list.item_count == menu._arsenal_entries.size(), "clearing search restores collection")
	menu._arsenal_tabs.current_tab = 1
	await settle()
	expect(menu._viewer_animation_opt.item_count == menu._viewer_anim.get_animation_list().size(), "all native clips exposed")
	menu._test_viewer_fire()
	await settle()
	expect(menu._viewer_anim.is_playing(), "preview action plays after redesign")
	get_tree().root.size = Vector2i(1024, 768)
	await settle()
	var panel := menu._arsenal_panel.get_global_rect()
	expect(inside(Rect2(Vector2.ZERO, Vector2(1024, 768)), panel), "4:3 arsenal fits viewport")
	expect(inside(panel, menu._arsenal_list.get_global_rect()), "4:3 catalogue remains inside panel")
	expect(inside(panel, menu._arsenal_tabs.get_global_rect()), "4:3 tabs remain inside panel")
	expect(inside(panel, menu._viewer_animation_opt.get_global_rect()), "4:3 animation selector not clipped")
	await capture("menu_arsenal_4x3")
	# Non-weapon selection also survives filtering to zero results and back.
	var remembered := "native:defuser_item"
	menu._arsenal_selected_meta = remembered
	menu._arsenal_search.text = "no-such-item"
	menu._refresh_arsenal_list()
	menu._arsenal_search.text = ""
	menu._refresh_arsenal_list()
	var restored := menu._arsenal_list.get_selected_items()
	expect(not restored.is_empty() and menu._arsenal_list.get_item_metadata(restored[0]) == remembered, "equipment selection survives filtering")
	menu._load_viewer_player("sas")
	await settle()
	expect(menu._viewer_anim != null and menu._viewer_anim.is_playing(), "classic player preview remains animated")
	menu._show_subpanel(menu._options_panel)
	expect(not menu._arsenal_panel.visible and menu._options_panel.visible, "only one modal visible")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	menu._unhandled_key_input(escape)
	expect(not menu._modal_shade.visible and not menu._options_panel.visible, "Escape returns home and releases shield")
	menu._show_subpanel(menu._play_panel)
	await settle()
	expect(inside(Rect2(Vector2.ZERO, Vector2(1024, 768)), menu._play_panel.get_global_rect()), "play dialog still fits 4:3")
	menu._close_panels()
	await capture("menu_home_4x3")
	AudioManager.stop_all()
	if failures == 0:
		print("[MENU QA] PASS: %d checks" % checks)
	else:
		printerr("[MENU QA] FAIL: %d/%d" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
