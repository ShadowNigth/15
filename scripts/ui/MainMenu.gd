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

# 3D Arsenal Viewer widgets
var _viewer_viewport: SubViewport = null
var _viewer_pivot: Node3D = null
var _viewer_anim: AnimationPlayer = null
var _viewer_stats_lbl: Label = null
var _viewer_current_wid: String = "ak47"


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
	_add_won_button(menu_vbox, "3D Arsenal & Models", func():
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


func _start_selected_game() -> void:
	if _bot_spin:
		GameData.bot_count = int(_bot_spin.value)
	if _diff_opt:
		GameData.bot_difficulty = _diff_opt.selected
	if _money_opt:
		GameData.start_money = _money_opt.get_selected_id()
	AudioManager.play_ui("launch_select2.wav")
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

	wlist.item_selected.connect(func(idx: int):
		var meta := String(wlist.get_item_metadata(idx))
		if meta.begins_with("player:"):
			_load_viewer_player(meta.trim_prefix("player:"))
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

	_viewer_stats_lbl = Label.new()
	_viewer_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_viewer_stats_lbl.add_theme_font_size_override("font_size", 12)
	_viewer_stats_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	right.add_child(_viewer_stats_lbl)


func _clear_viewer_pivot() -> void:
	var old_c := _viewer_pivot.get_children()
	for c in old_c:
		_viewer_pivot.remove_child(c)
		c.queue_free()
	_viewer_anim = null


func _style_viewer_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "char")
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_style_viewer_meshes(c)


func _load_viewer_weapon(wid: String) -> void:
	_viewer_current_wid = wid
	_clear_viewer_pivot()
	_viewer_pivot.rotation = Vector3.ZERO
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var sc := GameData.get_model_scene("weapons/" + String(spec.get("v_model", "v_ak47")))
	if sc:
		var inst := sc.instantiate()
		_style_viewer_meshes(inst)
		inst.position = Vector3(-0.08, 0.12, 0.65)
		inst.rotation_degrees = Vector3(0.0, 25.0, 0.0)
		_viewer_pivot.add_child(inst)
		_viewer_anim = _find_anim_recursive(inst)
		if _viewer_anim and not _viewer_anim.get_animation_list().is_empty():
			_viewer_anim.play(_viewer_anim.get_animation_list()[0])

	_viewer_stats_lbl.text = "%s  |  Price: $%d  |  Damage: %d  |  MaxSpeed (cs_i386.so): %.0f u/s  |  Cycle: %.3fs\n%s" % [
		String(spec.get("name", wid)),
		int(spec.get("price", 0)),
		int(spec.get("damage", 0)),
		float(spec.get("max_speed", 250.0)),
		float(spec.get("cycle_time", 0.1)),
		String(spec.get("description", "")),
	]


func _load_viewer_player(cid: String) -> void:
	_viewer_current_wid = ""
	_clear_viewer_pivot()
	var sc := GameData.get_model_scene("players/" + cid)
	if sc:
		var inst := sc.instantiate()
		_style_viewer_meshes(inst)
		inst.scale = Vector3(0.50, 0.50, 0.50)
		inst.position = Vector3(0.0, 0.12, 0.0)
		_viewer_pivot.add_child(inst)
		_viewer_anim = _find_anim_recursive(inst)
		if _viewer_anim:
			GameData.ensure_looping_animations(_viewer_anim)
			for a in _viewer_anim.get_animation_list():
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
