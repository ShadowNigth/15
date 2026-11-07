class_name MainMenu
extends Control
## Counter-Strike 1.5 Classic WON-Style Main Menu (Responsive 16:9 / 4:3 Layout):
##   - Full uncropped splash.png artwork + authentic UI sounds (launch_glow1.wav, launch_select1.wav)
##   - Compact Create Game dialog across ALL 26 CS 1.5 maps with side-by-side radar, scrollable briefing & Bot setup
##   - 3D Arsenal & Model Inspector turntable (preview extracted v_* weapons & player models)
##   - Configuration & Controls dialog (sensitivity, Invert Mouse Y, cl_righthand, dynamic crosshair, volume)

const AMBER := Color(1.0, 0.72, 0.16)
const AMBER_DIM := Color(0.88, 0.60, 0.15)
const PANEL_BG := Color(0.04, 0.04, 0.04, 0.92)

var _starting_match := false
var _play_panel: PanelContainer = null
var _arsenal_panel: PanelContainer = null
var _options_panel: PanelContainer = null

var _map_item_list: ItemList = null
var _filtered_maps: Array = []
var _overview_tex_rect: TextureRect = null
var _map_title_lbl: Label = null
var _map_briefing_lbl: Label = null
var _bot_spin: SpinBox = null
var _diff_opt: OptionButton = null
var _money_opt: OptionButton = null
var _glove_opt: OptionButton = null
var _knife_opt: OptionButton = null

# 3D Arsenal Viewer widgets
var _viewer_viewport: SubViewport = null
var _viewer_pivot: Node3D = null
var _viewer_anim: AnimationPlayer = null
var _viewer_animation_opt: OptionButton = null
var _viewer_stats_lbl: Label = null
var _viewer_current_wid: String = "ak47"
var _skin_opt: OptionButton = null
var _syncing_skin_options := false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_main_screen()
	_build_play_dialog()
	_build_arsenal_dialog()
	_build_options_dialog()


func _build_main_screen() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg_dark := ColorRect.new()
	bg_dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_dark.color = Color(0.02, 0.02, 0.02)
	add_child(bg_dark)

	var splash_tex := GameData.get_texture("res://assets/ui/shell/splash.png")

	# Dimmed widescreen backdrop fill so 16:9 sidebars blend naturally without cropping main logo
	var splash_backdrop := TextureRect.new()
	splash_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash_backdrop.texture = splash_tex
	splash_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash_backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splash_backdrop.modulate = Color(0.24, 0.22, 0.18, 0.85)
	add_child(splash_backdrop)

	# Full uncropped 4:3 Counter-Strike 1.5 Retail splash artwork centered cleanly!
	var splash := TextureRect.new()
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	splash.texture = splash_tex
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(splash)

	# Sleek WON left menu column
	var left_shade := ColorRect.new()
	left_shade.anchor_bottom = 1.0
	left_shade.offset_right = 290
	left_shade.color = Color(0.0, 0.0, 0.0, 0.62)
	add_child(left_shade)

	var menu_vbox := VBoxContainer.new()
	menu_vbox.anchor_top = 0.34
	menu_vbox.anchor_bottom = 0.90
	menu_vbox.offset_left = 26
	menu_vbox.offset_right = 272
	menu_vbox.add_theme_constant_override("separation", 8)
	add_child(menu_vbox)

	var ver_lbl := Label.new()
	ver_lbl.text = "COUNTER-STRIKE 1.5 RETAIL"
	ver_lbl.add_theme_font_size_override("font_size", 13)
	ver_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.42, 0.92))
	menu_vbox.add_child(ver_lbl)

	_add_won_button(menu_vbox, "Play CS 1.5 (LAN / Bots)", func(): _show_subpanel(_play_panel))
	_add_won_button(menu_vbox, "Quick Match: de_dust2", func():
		GameData.selected_map = "de_dust2"
		_start_selected_game()
	)
	_add_won_button(menu_vbox, "3D Arsenal, Skins & Models", func():
		_show_subpanel(_arsenal_panel)
		_load_viewer_weapon("ak47")
	)
	_add_won_button(menu_vbox, "Configuration & Controls", func(): _show_subpanel(_options_panel))
	_add_won_button(menu_vbox, "Quit Game", func(): get_tree().quit())

	var footer := Label.new()
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = 20
	footer.offset_right = 920
	footer.offset_top = -26
	footer.offset_bottom = -6
	footer.text = "Counter-Strike 1.5 Retail (Godot 4)  •  26 BSP Maps  •  27 Weapons (cs_i386.so)  •  Offline Bots IA"
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.82, 0.80, 0.72, 0.78))
	add_child(footer)


func _add_won_button(parent: VBoxContainer, txt: String, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = txt
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(236, 34)
	btn.add_theme_font_size_override("font_size", 15)
	btn.add_theme_color_override("font_color", AMBER_DIM)
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.94, 0.58))

	var sb_n := StyleBoxFlat.new()
	sb_n.bg_color = Color(0.08, 0.06, 0.02, 0.72)
	sb_n.border_color = Color(1.0, 0.65, 0.12, 0.48)
	sb_n.border_width_left = 3
	sb_n.content_margin_left = 12
	sb_n.content_margin_right = 8
	sb_n.content_margin_top = 4
	sb_n.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", sb_n)

	var sb_h := sb_n.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.26, 0.17, 0.03, 0.90)
	sb_h.border_color = Color(1.0, 0.85, 0.25, 1.0)
	btn.add_theme_stylebox_override("hover", sb_h)

	btn.mouse_entered.connect(func(): AudioManager.play_ui("launch_glow1.wav"))
	btn.pressed.connect(func():
		AudioManager.play_ui("launch_select1.wav")
		cb.call()
	)
	parent.add_child(btn)


func _make_modal_panel(title_txt: String) -> Array:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.25
	panel.anchor_right = 0.97
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	panel.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var h := HBoxContainer.new()
	var tl := Label.new()
	tl.text = title_txt
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 17)
	tl.add_theme_color_override("font_color", AMBER)
	var close_b := Button.new()
	close_b.text = "X Close"
	close_b.custom_minimum_size = Vector2(78, 28)
	close_b.add_theme_font_size_override("font_size", 13)
	close_b.pressed.connect(func():
		AudioManager.play_ui("launch_dnmenu1.wav")
		panel.visible = false
	)
	h.add_child(tl)
	h.add_child(close_b)
	vbox.add_child(h)
	return [panel, vbox]


func _show_subpanel(target: PanelContainer) -> void:
	for p in [_play_panel, _arsenal_panel, _options_panel]:
		if p:
			p.visible = (p == target)


func _build_play_dialog() -> void:
	var res := _make_modal_panel("CREATE GAME — SELECT MAP & BOTS (ALL 26 CS 1.5 MAPS)")
	_play_panel = res[0]
	var vbox: VBoxContainer = res[1]

	# Mode filter bar
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	vbox.add_child(filter_row)
	for f in [["ALL", "All Maps (26)"], ["de", "Bomb/Defuse (DE)"], ["cs", "Hostage (CS)"], ["as", "VIP Escort (AS)"]]:
		var fb := Button.new()
		fb.text = f[1]
		fb.add_theme_font_size_override("font_size", 13)
		fb.custom_minimum_size = Vector2(0, 28)
		var mode_code: String = f[0]
		fb.pressed.connect(func(): _populate_map_list(mode_code))
		filter_row.add_child(fb)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	vbox.add_child(body)

	_map_item_list = ItemList.new()
	_map_item_list.custom_minimum_size = Vector2(205, 0)
	_map_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_item_list.add_theme_font_size_override("font_size", 13)
	_map_item_list.item_selected.connect(_on_map_selected)
	body.add_child(_map_item_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)

	_map_title_lbl = Label.new()
	_map_title_lbl.add_theme_font_size_override("font_size", 16)
	_map_title_lbl.add_theme_color_override("font_color", AMBER)
	right.add_child(_map_title_lbl)

	# Side-by-side Radar Overview + Scrollable Map Briefing (never overflows vertically!)
	var info_split := HBoxContainer.new()
	info_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_split.add_theme_constant_override("separation", 12)
	right.add_child(info_split)

	var ov_frame := PanelContainer.new()
	var ov_sb := StyleBoxFlat.new()
	ov_sb.bg_color = Color(0.02, 0.02, 0.02, 0.9)
	ov_sb.border_color = Color(0.45, 0.35, 0.12, 0.7)
	ov_sb.set_border_width_all(1)
	ov_frame.add_theme_stylebox_override("panel", ov_sb)
	ov_frame.custom_minimum_size = Vector2(215, 145)
	info_split.add_child(ov_frame)

	_overview_tex_rect = TextureRect.new()
	_overview_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overview_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ov_frame.add_child(_overview_tex_rect)

	var brief_scroll := ScrollContainer.new()
	brief_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brief_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	brief_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_split.add_child(brief_scroll)

	_map_briefing_lbl = Label.new()
	_map_briefing_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_briefing_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_briefing_lbl.add_theme_font_size_override("font_size", 12)
	_map_briefing_lbl.add_theme_color_override("font_color", Color(0.86, 0.84, 0.76))
	brief_scroll.add_child(_map_briefing_lbl)

	# Compact Match Settings Grid
	var settings_grid := GridContainer.new()
	settings_grid.columns = 2
	settings_grid.add_theme_constant_override("h_separation", 14)
	settings_grid.add_theme_constant_override("v_separation", 5)
	right.add_child(settings_grid)

	var bl := Label.new()
	bl.text = "Number of Bots IA:"
	bl.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(bl)
	_bot_spin = SpinBox.new()
	_bot_spin.min_value = 0
	_bot_spin.max_value = 19
	_bot_spin.value = GameData.bot_count
	settings_grid.add_child(_bot_spin)

	var dl := Label.new()
	dl.text = "Bot Skill Level:"
	dl.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(dl)
	_diff_opt = OptionButton.new()
	for s in ["Easy", "Normal", "Hard", "Expert"]:
		_diff_opt.add_item(s)
	_diff_opt.selected = GameData.bot_difficulty
	settings_grid.add_child(_diff_opt)

	var ml := Label.new()
	ml.text = "Starting Money:"
	ml.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(ml)
	_money_opt = OptionButton.new()
	_money_opt.add_item("$800 (Classic Competitive)", 800)
	_money_opt.add_item("$3500 (Mid Round)", 3500)
	_money_opt.add_item("$16000 (Full Buy Practice)", 16000)
	_money_opt.selected = 0
	settings_grid.add_child(_money_opt)

	var gl := Label.new()
	gl.text = "First-person Gloves:"
	gl.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(gl)
	_glove_opt = OptionButton.new()
	_glove_opt.custom_minimum_size.x = 260.0
	_populate_glove_options(_glove_opt)
	settings_grid.add_child(_glove_opt)

	var knife_label := Label.new()
	knife_label.text = "Knife model:"
	knife_label.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(knife_label)
	_knife_opt = OptionButton.new()
	_knife_opt.custom_minimum_size.x = 260.0
	for raw in GameData.get_knife_options():
		var option := raw as Dictionary
		var index := _knife_opt.item_count
		_knife_opt.add_item(String(option["name"]))
		_knife_opt.set_item_metadata(index, String(option["id"]))
		if String(option["id"]) == GameData.selected_knife_id:
			_knife_opt.select(index)
	_knife_opt.item_selected.connect(func(index: int):
		_select_knife_for_match(String(_knife_opt.get_item_metadata(index)))
	)
	settings_grid.add_child(_knife_opt)

	var start_btn := Button.new()
	start_btn.text = "LAUNCH MATCH  >>"
	start_btn.custom_minimum_size = Vector2(0, 38)
	start_btn.add_theme_font_size_override("font_size", 16)
	start_btn.add_theme_color_override("font_color", Color(0.28, 1.0, 0.38))
	var sb_launch := StyleBoxFlat.new()
	sb_launch.bg_color = Color(0.06, 0.22, 0.08, 0.90)
	sb_launch.border_color = Color(0.30, 0.95, 0.40, 0.95)
	sb_launch.set_border_width_all(2)
	start_btn.add_theme_stylebox_override("normal", sb_launch)
	var sb_launch_h := sb_launch.duplicate() as StyleBoxFlat
	sb_launch_h.bg_color = Color(0.10, 0.34, 0.14, 0.96)
	start_btn.add_theme_stylebox_override("hover", sb_launch_h)
	start_btn.pressed.connect(_start_selected_game)
	right.add_child(start_btn)

	_populate_map_list("ALL")


func _populate_map_list(mode_filter: String) -> void:
	_map_item_list.clear()
	_filtered_maps.clear()
	var sel_idx := 0
	for m in GameData.maps_index:
		if mode_filter != "ALL" and String(m.get("mode", "")) != mode_filter:
			continue
		var idx := _filtered_maps.size()
		_filtered_maps.append(m)
		var mname := String(m["name"])
		_map_item_list.add_item("%s  [%s]" % [mname, String(m.get("mode", "de")).to_upper()])
		if mname == "de_dust2":
			sel_idx = idx

	if not _filtered_maps.is_empty():
		_map_item_list.select(sel_idx)
		_on_map_selected(sel_idx)


func _on_map_selected(idx: int) -> void:
	if idx < 0 or idx >= _filtered_maps.size():
		return
	var m: Dictionary = _filtered_maps[idx]
	var mname := String(m["name"])
	GameData.selected_map = mname
	_map_title_lbl.text = "%s  —  Mode: %s  (Nav Waypoints: %d)" % [
		mname.to_upper(),
		String(m.get("mode", "de")).to_upper(),
		int(m.get("waypoints", 0)),
	]
	_map_briefing_lbl.text = String(m.get("briefing", "Counter-Strike 1.5 classic map."))
	var ov: Dictionary = GameData.overviews.get(mname, {})
	_overview_tex_rect.texture = GameData.get_texture(String(ov.get("image", "")))


func _populate_glove_options(button: OptionButton) -> void:
	button.clear()
	var classic_id := String(GameData.sport_gloves.get("classic_id", "classic"))
	var classic_index := button.item_count
	button.add_item("Original Counter-Strike Gloves")
	button.set_item_metadata(classic_index, classic_id)
	for raw in GameData.get_glove_options():
		var option := raw as Dictionary
		var index := button.item_count
		button.add_item(String(option.get("name", "Sport Gloves")))
		button.set_item_metadata(index, String(option.get("id", "")))
	_sync_glove_option()


func _sync_glove_option() -> void:
	if _glove_opt == null:
		return
	for index in range(_glove_opt.item_count):
		if String(_glove_opt.get_item_metadata(index)) == GameData.selected_glove_id:
			_glove_opt.select(index)
			return


func _start_selected_game() -> void:
	if _starting_match:
		return
	_starting_match = true
	if _knife_opt and _knife_opt.selected >= 0:
		GameData.select_knife(String(_knife_opt.get_item_metadata(_knife_opt.selected)))
	if _glove_opt and _glove_opt.selected >= 0:
		GameData.select_glove(String(_glove_opt.get_item_metadata(_glove_opt.selected)))
	if _bot_spin:
		GameData.bot_count = int(_bot_spin.value)
	if _diff_opt:
		GameData.bot_difficulty = _diff_opt.selected
	if _money_opt:
		GameData.start_money = _money_opt.get_selected_id()
	AudioManager.play_ui("launch_select2.wav")
	var loading := Label.new()
	loading.text = "Loading match resources..."
	loading.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	loading.add_theme_font_size_override("font_size", 24)
	add_child(loading)
	var paths := GameData.prepare_match_resources()
	var progress := GameData.poll_match_resources(paths)
	while progress.x < paths.size():
		loading.text = "Loading match resources: %d / %d" % [progress.x, paths.size()]
		await get_tree().process_frame
		progress = GameData.poll_match_resources(paths)
	if progress.y > 0:
		loading.text = "Resource load failed. Check project imports before starting."
		_starting_match = false
		return
	get_tree().change_scene_to_file("res://scenes/GameWorld.tscn")


func _build_arsenal_dialog() -> void:
	var res := _make_modal_panel("3D ARSENAL & STUDIO MODEL INSPECTOR (cs_i386.so + .mdl)")
	_arsenal_panel = res[0]
	var vbox: VBoxContainer = res[1]

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	vbox.add_child(body)

	var wlist := ItemList.new()
	wlist.custom_minimum_size = Vector2(200, 0)
	wlist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wlist.add_theme_font_size_override("font_size", 13)
	var ids := GameData.weapons.keys()
	ids.sort()
	for wid in ids:
		var sp: Dictionary = GameData.weapons[wid]
		var idx := wlist.add_item("%s ($%d)" % [String(sp.get("name", wid)), int(sp.get("price", 0))])
		wlist.set_item_metadata(idx, wid)
	for tm in ["CT", "T"]:
		for cinfo in GameData.classes.get(tm, []):
			var idx2 := wlist.add_item("[Player %s] %s" % [tm, String(cinfo["name"])])
			wlist.set_item_metadata(idx2, "player:" + String(cinfo["id"]))
	for raw in GameData.get_knife_options():
		var knife_option := raw as Dictionary
		if String(knife_option["id"]) == "original":
			continue
		var knife_idx := wlist.add_item("[Knife] " + String(knife_option["name"]))
		wlist.set_item_metadata(knife_idx, "knife:" + String(knife_option["id"]))
	var glove_idx := wlist.add_item("[Gloves] Original Counter-Strike")
	wlist.set_item_metadata(glove_idx, "glove:" + String(GameData.sport_gloves.get("classic_id", "classic")))
	for raw in GameData.get_glove_options():
		var option := raw as Dictionary
		var idx3 := wlist.add_item("[Gloves] %s — %s" % [String(option.get("family", "Sport")), String(option.get("wear_code", ""))])
		wlist.set_item_metadata(idx3, "glove:" + String(option.get("id", "")))

	for resource in ["ct", "t", "hostage", "defuser_item", "chicken"]:
		var native_idx := wlist.add_item("[Native review] " + resource)
		wlist.set_item_metadata(native_idx, "native:" + resource)

	wlist.item_selected.connect(func(idx: int):
		var meta := String(wlist.get_item_metadata(idx))
		if meta.begins_with("native:"):
			_load_viewer_native(meta.trim_prefix("native:"))
		elif meta.begins_with("player:"):
			_load_viewer_player(meta.trim_prefix("player:"))
		elif meta.begins_with("knife:"):
			_select_knife_for_match(meta.trim_prefix("knife:"))
		elif meta.begins_with("glove:"):
			_select_glove_for_match(meta.trim_prefix("glove:"))
		else:
			_load_viewer_weapon(meta)
	)
	body.add_child(wlist)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(280, 180)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(svc)

	_viewer_viewport = SubViewport.new()
	_viewer_viewport.own_world_3d = true
	_viewer_viewport.transparent_bg = true
	svc.add_child(_viewer_viewport)

	var vcam := Camera3D.new()
	_viewer_viewport.add_child(vcam)
	vcam.look_at_from_position(Vector3(0.0, 0.35, 1.35), Vector3(0.0, 0.15, 0.0), Vector3.UP)

	var vlight := DirectionalLight3D.new()
	vlight.rotation_degrees = Vector3(-35, 35, 0)
	vlight.light_energy = 1.4
	_viewer_viewport.add_child(vlight)

	var valight := OmniLight3D.new()
	valight.position = Vector3(-1.2, 1.0, 1.5)
	valight.light_energy = 1.2
	_viewer_viewport.add_child(valight)

	_viewer_pivot = Node3D.new()
	_viewer_viewport.add_child(_viewer_pivot)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	var fire_btn := Button.new()
	fire_btn.text = "Test Fire Sound & Anim"
	fire_btn.pressed.connect(_test_viewer_fire)
	var rel_btn := Button.new()
	rel_btn.text = "Play Reload / Run Anim"
	rel_btn.pressed.connect(func():
		if _viewer_anim:
			for a in _viewer_anim.get_animation_list():
				if "reload" in a.to_lower() or a.to_lower() == "run":
					_viewer_anim.play(a)
					break
	)
	btn_row.add_child(fire_btn)
	btn_row.add_child(rel_btn)
	right.add_child(btn_row)

	var animation_row := HBoxContainer.new()
	var animation_label := Label.new()
	animation_label.text = "Preview animation:"
	animation_row.add_child(animation_label)
	_viewer_animation_opt = OptionButton.new()
	_viewer_animation_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewer_animation_opt.item_selected.connect(func(index: int):
		if _viewer_anim != null and index >= 0:
			_viewer_anim.stop()
			_viewer_anim.speed_scale = 1.0
			_viewer_anim.play(String(_viewer_animation_opt.get_item_metadata(index)))
			_viewer_anim.advance(0.0)
	)
	animation_row.add_child(_viewer_animation_opt)
	right.add_child(animation_row)

	var audio_row := HBoxContainer.new()
	var audio_options := OptionButton.new()
	audio_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_options.clip_text = true
	audio_options.fit_to_longest_item = false
	audio_options.get_popup().max_size = Vector2i(0, 500)
	audio_options.tooltip_text = "All 649 pinned source recordings, including languages and effects without a current gameplay equivalent."
	var manifest: Dictionary = GameData._load_json("res://data/native_audio_manifest.json")
	for entry in manifest.get("files", []):
		audio_options.add_item(String(entry["path"]).trim_prefix("native/"))
		audio_options.set_item_metadata(audio_options.item_count - 1, entry["path"])
	var audition := AudioStreamPlayer.new()
	audio_row.add_child(audition)
	var listen := Button.new()
	listen.text = "Listen"
	listen.pressed.connect(func():
		audition.stop()
		audition.stream = GameData.get_sound(String(audio_options.get_item_metadata(audio_options.selected)))
		audition.volume_db = -5.0 + GameData.master_volume_db + GameData.sound_gain_db(String(audio_options.get_item_metadata(audio_options.selected)))
		audition.play()
	)
	var stop_audio := Button.new()
	stop_audio.text = "Stop"
	stop_audio.pressed.connect(audition.stop)
	audio_row.add_child(audio_options)
	audio_row.add_child(listen)
	audio_row.add_child(stop_audio)
	right.add_child(audio_row)
	_arsenal_panel.visibility_changed.connect(func():
		if not _arsenal_panel.visible:
			audition.stop()
	)

	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 8)
	var skin_label := Label.new()
	skin_label.text = "Weapon finish (next match):"
	skin_label.add_theme_font_size_override("font_size", 12)
	skin_row.add_child(skin_label)
	_skin_opt = OptionButton.new()
	_skin_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_opt.add_theme_font_size_override("font_size", 12)
	_skin_opt.item_selected.connect(_on_viewer_skin_selected)
	skin_row.add_child(_skin_opt)
	right.add_child(skin_row)

	_viewer_stats_lbl = Label.new()
	_viewer_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_viewer_stats_lbl.add_theme_font_size_override("font_size", 12)
	_viewer_stats_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	right.add_child(_viewer_stats_lbl)


func _select_knife_for_match(option_id: String) -> void:
	if not GameData.select_knife(option_id):
		return
	if _knife_opt != null:
		for index in range(_knife_opt.item_count):
			if String(_knife_opt.get_item_metadata(index)) == option_id:
				_knife_opt.select(index)
	AudioManager.play_ui("launch_select1.wav")
	if _viewer_pivot != null:
		_load_viewer_weapon("knife")


func _select_glove_for_match(option_id: String) -> void:
	if not GameData.select_glove(option_id):
		return
	_sync_glove_option()
	AudioManager.play_ui("launch_select1.wav")
	_load_viewer_weapon("ak47")


func _clear_viewer_pivot() -> void:
	var old_c := _viewer_pivot.get_children()
	for c in old_c:
		_viewer_pivot.remove_child(c)
		c.queue_free()
	_viewer_anim = null
	if _viewer_animation_opt != null:
		_viewer_animation_opt.clear()


func _populate_viewer_animations() -> void:
	if _viewer_animation_opt == null:
		return
	_viewer_animation_opt.clear()
	if _viewer_anim == null:
		return
	for clip in _viewer_anim.get_animation_list():
		_viewer_animation_opt.add_item(clip)
		_viewer_animation_opt.set_item_metadata(_viewer_animation_opt.item_count - 1, clip)
		if clip == "idle":
			_viewer_animation_opt.select(_viewer_animation_opt.item_count - 1)


func _style_viewer_meshes(n: Node, mode: String = "char", native_arms: bool = false, native_gun: bool = false) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var original := mi.get_active_material(s)
				var name_lower := original.resource_name.to_lower() if original != null else ""
				var arm_surface := name_lower.contains("glove") or name_lower == "ct_arms.bmp"
				var material_mode := "vm_flip" if (native_gun or (native_arms and arm_surface)) and mode == "vm" else mode
				var styled := GameData.get_styled_model_material(original, material_mode)
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_style_viewer_meshes(c, mode, native_arms, native_gun)


func _populate_viewer_skin_options(wid: String) -> void:
	if _skin_opt == null:
		return
	_syncing_skin_options = true
	_skin_opt.clear()
	var options := GameData.get_weapon_skin_options(wid)
	_skin_opt.disabled = options.is_empty()
	var original := String(GameData.weapon_skins.get("default", "original"))
	var original_index := _skin_opt.item_count
	var default_label := "Original HD" if not options.is_empty() else "Original HD — no curated finishes"
	if wid == "knife" and GameData.selected_knife_id != "original":
		for raw in GameData.get_knife_options():
			if String((raw as Dictionary)["id"]) == GameData.selected_knife_id:
				default_label = "Default — " + String((raw as Dictionary).get("default_finish", "Factory"))
	_skin_opt.add_item(default_label)
	_skin_opt.set_item_metadata(original_index, original)
	for raw in options:
		var option := raw as Dictionary
		var index := _skin_opt.item_count
		_skin_opt.add_item(String(option.get("menu_label", option.get("finish", option.get("name", "Weapon Finish")))))
		_skin_opt.set_item_metadata(index, String(option.get("id", "")))
	var selected := GameData.get_selected_weapon_skin_id(wid)
	for index in range(_skin_opt.item_count):
		if String(_skin_opt.get_item_metadata(index)) == selected:
			_skin_opt.select(index)
			break
	_syncing_skin_options = false


func _on_viewer_skin_selected(index: int) -> void:
	if _syncing_skin_options or _skin_opt == null or _viewer_current_wid.is_empty():
		return
	if index < 0 or index >= _skin_opt.item_count:
		return
	var wid := _viewer_current_wid
	if not GameData.select_weapon_skin(wid, String(_skin_opt.get_item_metadata(index))):
		return
	AudioManager.play_ui("launch_select1.wav")
	_load_viewer_weapon(wid)


func _load_viewer_weapon(wid: String) -> void:
	_viewer_current_wid = wid
	_populate_viewer_skin_options(wid)
	_clear_viewer_pivot()
	_viewer_pivot.rotation = Vector3.ZERO
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var sc := GameData.get_model_scene("weapons/" + String(spec.get("v_model", "v_ak47")))
	if sc:
		var inst := sc.instantiate()
		inst.position = Vector3(-0.08, 0.12, 0.65)
		inst.rotation_degrees = Vector3(0.0, 25.0, 0.0)
		_viewer_pivot.add_child(inst)
		SportGloves.apply(inst, String(spec.get("v_model", "v_ak47")))
		var vm_meta: Dictionary = GameData.models_meta.get("weapons/" + String(spec.get("v_model", "")), {})
		_style_viewer_meshes(inst, "vm", bool(vm_meta.get("native_cs2_animation", false)), bool(vm_meta.get("native_gun_animations", false)))
		_viewer_anim = _find_anim_recursive(inst)
		_populate_viewer_animations()
		if _viewer_anim and not _viewer_anim.get_animation_list().is_empty():
			_viewer_anim.play("idle" if _viewer_anim.has_animation("idle") else _viewer_anim.get_animation_list()[0])

	_viewer_stats_lbl.text = "%s  |  Price: $%d  |  Damage: %d  |  MaxSpeed (cs_i386.so): %.0f u/s  |  Cycle: %.3fs\n%s" % [
		String(spec.get("name", wid)),
		int(spec.get("price", 0)),
		int(spec.get("damage", 0)),
		float(spec.get("max_speed", 250.0)),
		float(spec.get("cycle_time", 0.1)),
		String(spec.get("description", "")),
	]
	_viewer_stats_lbl.text += "\nFirst-person gloves for the next match: " + GameData.get_glove_display_name()
	if not GameData.get_weapon_skin_options(wid).is_empty():
		_viewer_stats_lbl.text += "\nWeapon finish for the next match: " + GameData.get_weapon_skin_display_name(wid)


func _load_viewer_player(cid: String) -> void:
	_viewer_current_wid = ""
	_populate_viewer_skin_options("")
	_clear_viewer_pivot()
	var sc := GameData.get_model_scene("players/" + cid)
	if sc:
		var inst := sc.instantiate()
		_style_viewer_meshes(inst)
		inst.scale = Vector3(0.50, 0.50, 0.50)
		inst.position = Vector3(0.0, 0.12, 0.0)
		_viewer_pivot.add_child(inst)
		_viewer_anim = _find_anim_recursive(inst)
		_populate_viewer_animations()
		var skel_list := inst.find_children("*", "Skeleton3D", true, false)
		if _viewer_anim:
			GameData.ensure_looping_animations(_viewer_anim)
			# Apply upper-body rifle aim pose first so lower-only gait clips keep arms in rifle stance!
			var anim_list := _viewer_anim.get_animation_list()
			var is_ct_mdl := cid in ["urban", "gsg9", "sas", "gign", "vip"]
			var aim_cand := "ref_aim_onehanded" if cid == "vip" else ("ref_aim_carbine" if is_ct_mdl else "ref_aim_ak47")
			for a in anim_list:
				if a.to_lower() == aim_cand:
					_viewer_anim.play(a)
					_viewer_anim.advance(0.0)
					break
			if not skel_list.is_empty():
				var sk := skel_list[0] as Skeleton3D
				if sk and sk.find_bone("Bip01 R Hand") >= 0 and cid not in ["hostage", "scientist"]:
					var ba := BoneAttachment3D.new()
					ba.bone_name = "Bip01 R Hand"
					sk.add_child(ba)
					var wmdl := "p_usp" if cid == "vip" else ("p_m4a1" if is_ct_mdl else "p_ak47")
					var wsc := GameData.get_model_scene("weapons/" + wmdl)
					if wsc:
						var wi := wsc.instantiate()
						_style_viewer_meshes(wi)
						ba.add_child(wi)
			for a in anim_list:
				if a.to_lower() == "idle1" or a.to_lower().begins_with("idle"):
					_viewer_anim.play(a)
					break
	_viewer_stats_lbl.text = "Player Model: %s.glb (converted from cstrike/models/player/%s/%s.mdl)" % [cid, cid, cid]


func _test_viewer_fire() -> void:
	if not _viewer_current_wid.is_empty() and GameData.weapons.has(_viewer_current_wid):
		var sp: Dictionary = GameData.weapons[_viewer_current_wid]
		var fs: Array = sp.get("fire_sounds", [])
		if not fs.is_empty():
			AudioManager.play_2d(String(fs[0]), -2.0)
	if _viewer_anim:
		for a in _viewer_anim.get_animation_list():
			if "shoot" in a.to_lower():
				_viewer_anim.stop()
				_viewer_anim.play(a)
				break


func _find_anim_recursive(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim_recursive(c)
		if r:
			return r
	return null


func _process(delta: float) -> void:
	if _arsenal_panel and _arsenal_panel.visible and _viewer_pivot and _viewer_current_wid.is_empty():
		_viewer_pivot.rotate_y(delta * 0.85)


func _build_options_dialog() -> void:
	var res := _make_modal_panel("CONFIGURATION & CONTROLS")
	_options_panel = res[0]
	var vbox: VBoxContainer = res[1]

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)

	var cosmetic_labels := ["Original casings + native ejection timing", "Low-ammunition warning colors", "Ambient chickens (Italy / Inferno / Cobble)", "Native dropped defuse-kit model"]
	var keys: Array = GameData.COSMETIC_KEYS.duplicate()
	keys.erase("native_ammo_icons")
	for index in range(keys.size()):
		var label := Label.new()
		label.text = cosmetic_labels[index]
		grid.add_child(label)
		var check := CheckBox.new()
		var key: String = keys[index]
		check.button_pressed = GameData.get(key)
		check.toggled.connect(GameData.set_cosmetic_preference.bind(key))
		grid.add_child(check)

	var voice_label := Label.new()
	voice_label.text = "Radio voices:"
	grid.add_child(voice_label)
	var voice_options := OptionButton.new()
	voice_options.add_item("English (CT / T)")
	voice_options.add_item("Chinese (CT / T)")
	voice_options.select(1 if GameData.voice_language == "zh" else 0)
	voice_options.item_selected.connect(func(index: int): GameData.voice_language = "zh" if index == 1 else "en")
	grid.add_child(voice_options)

	var sl := Label.new()
	sl.text = "Mouse Sensitivity:"
	grid.add_child(sl)
	var sens_slider := HSlider.new()
	sens_slider.min_value = 0.04
	sens_slider.max_value = 0.60
	sens_slider.step = 0.01
	sens_slider.value = GameData.mouse_sensitivity
	sens_slider.custom_minimum_size = Vector2(220, 22)
	sens_slider.value_changed.connect(func(v: float): GameData.mouse_sensitivity = v)
	grid.add_child(sens_slider)

	var il := Label.new()
	il.text = "Invert Mouse Y-Axis:"
	grid.add_child(il)
	var inv_chk := CheckBox.new()
	inv_chk.button_pressed = GameData.invert_mouse_y
	inv_chk.toggled.connect(func(b: bool): GameData.invert_mouse_y = b)
	grid.add_child(inv_chk)

	var vl := Label.new()
	vl.text = "Master Volume (dB):"
	grid.add_child(vl)
	var vol_slider := HSlider.new()
	vol_slider.min_value = -24.0
	vol_slider.max_value = 6.0
	vol_slider.step = 1.0
	vol_slider.value = GameData.master_volume_db
	vol_slider.value_changed.connect(func(v: float): GameData.master_volume_db = v)
	grid.add_child(vol_slider)

	var rl := Label.new()
	rl.text = "Right-Handed Viewmodel (cl_righthand 1):"
	grid.add_child(rl)
	var rh_chk := CheckBox.new()
	rh_chk.button_pressed = GameData.right_hand
	rh_chk.toggled.connect(func(b: bool): GameData.right_hand = b)
	grid.add_child(rh_chk)

	var dl := Label.new()
	dl.text = "Dynamic Crosshair (cl_dynamiccrosshair 1):"
	grid.add_child(dl)
	var dc_chk := CheckBox.new()
	dc_chk.button_pressed = GameData.dynamic_crosshair
	dc_chk.toggled.connect(func(b: bool): GameData.dynamic_crosshair = b)
	grid.add_child(dc_chk)

	var keys_lbl := Label.new()
	keys_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	keys_lbl.add_theme_font_size_override("font_size", 12)
	keys_lbl.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
	keys_lbl.text = (
		"CLASSIC CS 1.5 KEYBINDS:\n" +
		"• WASD: Move   |   Space: Jump   |   Ctrl: Crouch   |   Shift: Silent Walk\n" +
		"• Mouse1: Fire / Plant C4   |   Mouse2: Zoom / Silencer (M4A1, USP) / Burst (Glock18) / Stab\n" +
		"• R: Reload   |   G: Drop Weapon   |   Q: Last Weapon   |   1-5: Weapon Slots\n" +
		"• B: Buy Menu (supports hotkeys e.g. B-4-1 AK47, B-4-3 M4A1, B-8-2 Kevlar+Helmet)\n" +
		"• , (Comma) / . (Period): Buy Primary / Secondary Ammo\n" +
		"• E: Defuse C4 / Rescue Hostage / Open Door   |   F: Flashlight   |   N: Nightvision\n" +
		"• M: Change Team   |   Z / X / C: Radio Commands   |   Tab: Scoreboard   |   Esc: Menu"
	)
	content.add_child(keys_lbl)


func _load_viewer_native(resource: String) -> void:
	_viewer_current_wid = ""
	_populate_viewer_skin_options("")
	_clear_viewer_pivot()
	var scene := GameData.get_model_scene("native/" + resource)
	if scene == null:
		return
	var instance := scene.instantiate() as Node3D
	_viewer_pivot.add_child(instance)
	instance.scale = Vector3.ONE * (0.5 if resource in ["ct", "t", "hostage"] else 1.8)
	instance.position.y = -0.35 if resource in ["ct", "t", "hostage"] else -0.15
	_viewer_anim = _find_anim_recursive(instance)
	_populate_viewer_animations()
	if _viewer_anim != null:
		for clip in _viewer_anim.get_animation_list():
			if clip in ["walk", "run"]:
				_viewer_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		if _viewer_anim.has_animation("walk"):
			_viewer_anim.play("walk")
	GameData.apply_native_world_material(instance, resource)
	_viewer_stats_lbl.text = "ScCsgoKnives native review: " + resource + "\n"
	if resource in ["ct", "t"]:
		_viewer_stats_lbl.text += "170 restored clips. Live CT/T use native gait + weapon poses; VIP keeps its distinct classic identity."
	elif resource == "hostage":
		_viewer_stats_lbl.text += "7 upstream adapted clips. Live hostage appearance replaced; physical rescue logic preserved."
	elif resource == "defuser_item":
		_viewer_stats_lbl.text += "CS2 waist tool pouch. Used for dropped kits; CT pickup, price and 5s / 10s defuse unchanged."
	else:
		_viewer_stats_lbl.text += "Native idle / walk / run. Ambient animals do not count as enemies or objectives."
