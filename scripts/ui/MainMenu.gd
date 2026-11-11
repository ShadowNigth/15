class_name MainMenu
extends Control
## CS2-inspired local main menu and categorized arsenal; classic gameplay/assets preserved.
##   - Full uncropped splash.png artwork + authentic UI sounds (launch_glow1.wav, launch_select1.wav)
##   - Compact Create Game dialog across ALL 26 CS 1.5 maps with side-by-side radar, scrollable briefing & Bot setup
##   - 3D Arsenal & Model Inspector turntable (preview extracted v_* weapons & player models)
##   - Configuration & Controls dialog (sensitivity, Invert Mouse Y, cl_righthand, dynamic crosshair, volume)

const AMBER := Color(1.0, 0.72, 0.16)
const AMBER_DIM := Color(0.88, 0.60, 0.15)
const PANEL_BG := Color(0.055, 0.070, 0.085, 0.99)

var _starting_match := false
var _play_panel: PanelContainer = null
var _arsenal_panel: PanelContainer = null
var _options_panel: PanelContainer = null

var _map_item_list: ItemList = null
var _filtered_maps: Array = []
var _overview_tex_rect: TextureRect = null
var _map_title_lbl: Label = null
var _map_briefing_lbl: Label = null
var _game_mode_opt: OptionButton
var _dm_weapon_opt: OptionButton
var _bot_spin: SpinBox = null
var _diff_opt: OptionButton = null
var _money_opt: OptionButton = null
var _glove_opt: OptionButton = null
var _knife_opt: OptionButton = null

# 3D Arsenal Viewer widgets
var _viewer_viewport: SubViewport = null
var _viewer_pivot: Node3D = null
var _viewer_camera: Camera3D
var _viewer_anim: AnimationPlayer = null
var _viewer_animation_opt: OptionButton = null
var _viewer_stats_lbl: Label = null
var _viewer_current_wid: String = "ak47"
var _skin_opt: OptionButton = null
var _syncing_skin_options := false

var _arsenal_entries: Array[Dictionary] = []
var _arsenal_selected_meta: String = "ak47"
var _arsenal_list: ItemList
var _arsenal_search: LineEdit
var _arsenal_category: OptionButton
var _arsenal_count: Label
var _arsenal_title: Label
var _arsenal_kind: Label
var _arsenal_tabs: TabContainer
var _agent_arms_opt: OptionButton
var _preview_agent_class := "sas"
var _preview_agent_team := "CT"
var _home_background: MenuBackdrop
var _modal_shade: ColorRect


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_preview_agent_class = GameData.view_agent_class
	_preview_agent_team = GameData.view_agent_team
	_install_menu_theme()
	_build_main_screen()
	_build_play_dialog()
	_build_arsenal_dialog()
	_build_options_dialog()


func _menu_box(color: Color, border: Color = Color(0.22, 0.27, 0.31)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(12)
	return box

func _install_menu_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 15
	for type_name in ["Button", "OptionButton", "LineEdit", "SpinBox", "ItemList", "TabContainer"]:
		theme.set_color("font_color", type_name, Color(0.89, 0.92, 0.94))
	for type_name in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type_name, _menu_box(Color(0.10, 0.13, 0.16)))
		theme.set_stylebox("hover", type_name, _menu_box(Color(0.18, 0.22, 0.25), AMBER))
		theme.set_stylebox("pressed", type_name, _menu_box(Color(0.27, 0.23, 0.15), AMBER))
		theme.set_stylebox("focus", type_name, _menu_box(Color(0, 0, 0, 0), AMBER))
		theme.set_color("font_hover_color", type_name, AMBER)
	theme.set_stylebox("normal", "LineEdit", _menu_box(Color(0.04, 0.06, 0.08)))
	theme.set_stylebox("focus", "LineEdit", _menu_box(Color(0, 0, 0, 0), AMBER))
	theme.set_stylebox("panel", "ItemList", _menu_box(Color(0.045, 0.06, 0.075)))
	theme.set_stylebox("selected", "ItemList", _menu_box(Color(0.32, 0.25, 0.13), AMBER))
	theme.set_stylebox("selected_focus", "ItemList", _menu_box(Color(0.32, 0.25, 0.13), AMBER))
	theme.set_stylebox("panel", "TabContainer", _menu_box(Color(0.07, 0.09, 0.11)))
	theme.set_stylebox("tab_selected", "TabContainer", _menu_box(Color(0.23, 0.20, 0.13), AMBER))
	theme.set_stylebox("tab_unselected", "TabContainer", _menu_box(Color(0.10, 0.13, 0.16)))

func _menu_label(text: String, font_size: int, color: Color = Color(0.9, 0.93, 0.95)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _nav_button(text: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(110, 42)
	button.mouse_entered.connect(func(): AudioManager.play_ui("launch_glow1.wav"))
	button.pressed.connect(func():
		AudioManager.play_ui("launch_select1.wav")
		callback.call()
	)
	if primary:
		button.add_theme_stylebox_override("normal", _menu_box(AMBER, AMBER))
		button.add_theme_color_override("font_color", Color(0.07, 0.08, 0.09))
	return button

func _open_arsenal() -> void:
	_show_subpanel(_arsenal_panel)
	if _viewer_pivot.get_child_count() == 0:
		_load_viewer_weapon("ak47")
	_refresh_arsenal_list()
	_arsenal_search.grab_focus()

func _build_main_screen() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_home_background = MenuBackdrop.new()
	_home_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_home_background)
	var atmosphere := ColorRect.new()
	atmosphere.set_anchors_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient := Shader.new()
	gradient.code = "shader_type canvas_item; void fragment(){float edge=pow(abs(UV.x-0.5)*2.0,2.0); float bottom=smoothstep(0.55,1.0,UV.y); COLOR=vec4(0.015,0.025,0.035,0.16+edge*0.3+bottom*0.2);}"
	var atmosphere_material := ShaderMaterial.new()
	atmosphere_material.shader = gradient
	atmosphere.material = atmosphere_material
	add_child(atmosphere)
	_build_home_agent()
	var top := PanelContainer.new()
	top.anchor_right = 1.0
	top.offset_bottom = 76
	top.add_theme_stylebox_override("panel", _menu_box(Color(0.09, 0.11, 0.12, 0.65), Color(1, 1, 1, 0.08)))
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	top.add_child(row)
	row.add_child(_home_nav("⌂", _close_panels))
	row.add_child(_home_nav("AJUSTES", func(): _show_subpanel(_options_panel)))
	row.add_child(_home_nav("SALIR", func(): get_tree().quit()))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_home_nav("INVENTARIO", _open_arsenal))
	row.add_child(_home_nav("EQUIPAMIENTO", _open_arsenal))
	row.add_child(_home_nav("JUGAR", func(): _show_subpanel(_play_panel)))
	var end := Control.new()
	end.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(end)
	var profile := PanelContainer.new()
	profile.anchor_left = 0.0
	profile.anchor_right = 0.0
	profile.anchor_top = 1.0
	profile.anchor_bottom = 1.0
	profile.offset_left = 30
	profile.offset_right = 325
	profile.offset_top = -132
	profile.offset_bottom = -42
	profile.add_theme_stylebox_override("panel", _menu_box(Color(0.10, 0.12, 0.13, 0.6), Color(1, 1, 1, 0.12)))
	add_child(profile)
	var identity := _menu_label("COUNTER-STRIKE / RETAIL\n26 MAPAS  ·  43 ARMAS  ·  BOTS LOCALES", 15)
	identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	profile.add_child(identity)
	var launch := _nav_button("JUGAR  →", func(): _show_subpanel(_play_panel), true)
	launch.anchor_left = 1.0
	launch.anchor_right = 1.0
	launch.anchor_top = 1.0
	launch.anchor_bottom = 1.0
	launch.offset_left = -260
	launch.offset_right = -30
	launch.offset_top = -118
	launch.offset_bottom = -46
	launch.add_theme_font_size_override("font_size", 24)
	add_child(launch)
	var scene_name := _menu_label("ESCENARIO EN VIVO  /  PERSONALÍZALO EN AJUSTES", 12, Color(0.8, 0.85, 0.88))
	scene_name.offset_left = 30
	scene_name.offset_top = 92
	add_child(scene_name)
	var footer := _menu_label("CS / RETAIL     •     SIN CONEXIÓN", 11)
	footer.anchor_top = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_left = 20
	footer.offset_top = -26
	add_child(footer)
	_modal_shade = ColorRect.new()
	_modal_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_shade.color = Color(0.01, 0.02, 0.03, 0.55)
	_modal_shade.visible = false
	add_child(_modal_shade)

func _home_nav(text: String, callback: Callable) -> Button:
	var button := _nav_button(text, callback)
	button.custom_minimum_size = Vector2(0, 38)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	return button

func _build_home_agent() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.stretch = true
	add_child(container)
	var view := SubViewport.new()
	view.own_world_3d = true
	view.transparent_bg = true
	container.add_child(view)
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.fov = 35
	camera.look_at_from_position(Vector3(0, 1.05, 4.25), Vector3(0, 0.98, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -30, 0)
	light.light_energy = 1.6
	view.add_child(light)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2, 2, 2)
	fill.light_energy = 1.7
	view.add_child(fill)
	var scene := GameData.get_model_scene("players/sas")
	if not scene:
		return
	var model := scene.instantiate() as Node3D
	view.add_child(model)
	model.position.y = 0.0
	model.rotation.y = PI + 0.15
	_style_viewer_meshes(model)
	var animation := _find_anim_recursive(model)
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if animation and not rigs.is_empty():
		var rig := rigs[0] as Skeleton3D
		var clip: String = ModernAgentPose.table("sas", "m4a1").get("clips", {}).get("idle", "")
		if animation.has_animation(clip):
			animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			animation.play(clip)
			animation.advance(0)
		# Native agent origins differ from classic actors. Frame the evaluated
		# skeleton instead of applying gameplay's classic origin offset.
		var ankle := rig.find_bone("ankle_L")
		var head := rig.find_bone("head_0")
		if ankle >= 0 and head >= 0:
			var foot_y := (model.global_transform.affine_inverse() * rig.global_transform * rig.get_bone_global_pose(ankle).origin).y
			var head_y := (model.global_transform.affine_inverse() * rig.global_transform * rig.get_bone_global_pose(head).origin).y
			var factor := 1.7 / maxf(0.1, head_y - foot_y)
			model.scale = Vector3.ONE * factor
			model.position.y = -foot_y * factor + 0.06
		var attachment := BoneAttachment3D.new()
		attachment.bone_name = "hand_R"
		rig.add_child(attachment)
		var weapon := GameData.get_model_scene("weapons/p_m4a1")
		if weapon:
			var prop := weapon.instantiate() as Node3D
			attachment.add_child(prop)
			_style_viewer_meshes(prop)
			ModernAgentPose.fit_prop(prop, "sas", "m4a1")
		ModernPreviewGrip.attach(model, rig, animation, "sas", "m4a1")

func _close_panels() -> void:
	for panel in [_play_panel, _arsenal_panel, _options_panel]:
		if panel != null:
			panel.hide()
	_modal_shade.hide()

func _input(event: InputEvent) -> void:
	# Escape also works while a search field or popup owns GUI focus.
	_unhandled_key_input(event)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _modal_shade.visible:
		_close_panels()
		get_viewport().set_input_as_handled()


func _make_modal_panel(title_txt: String) -> Array:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.035
	panel.anchor_right = 0.965
	panel.anchor_top = 0.12
	panel.anchor_bottom = 0.95
	panel.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(0.27, 0.32, 0.36)
	sb.set_border_width_all(1)
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
	close_b.text = "VOLVER  /  ESC"
	close_b.custom_minimum_size = Vector2(78, 28)
	close_b.add_theme_font_size_override("font_size", 13)
	close_b.pressed.connect(func():
		AudioManager.play_ui("launch_dnmenu1.wav")
		_close_panels()
	)
	h.add_child(tl)
	h.add_child(close_b)
	vbox.add_child(h)
	return [panel, vbox]


func _show_subpanel(target: PanelContainer) -> void:
	_modal_shade.show()
	for p in [_play_panel, _arsenal_panel, _options_panel]:
		if p:
			p.visible = (p == target)


func _build_play_dialog() -> void:
	var res := _make_modal_panel("JUGAR  /  MAPAS Y BOTS")
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
	var setup_scroll := ScrollContainer.new()
	setup_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	setup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(setup_scroll)
	setup_scroll.add_child(right)

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

	var mode_label := Label.new()
	mode_label.text = "Modo de juego:"
	settings_grid.add_child(mode_label)
	_game_mode_opt = OptionButton.new()
	_game_mode_opt.add_item("Classic — DE / CS / AS")
	_game_mode_opt.add_item("Team Deathmatch (bots)")
	_game_mode_opt.selected = 1 if GameData.game_mode == "deathmatch" else 0
	settings_grid.add_child(_game_mode_opt)

	var movement_label := Label.new()
	movement_label.text = "Movimiento:"
	settings_grid.add_child(movement_label)
	var movement_options := OptionButton.new()
	movement_options.name = "MovementProfile"
	movement_options.add_item("Estilo CS2 — experimental")
	movement_options.add_item("GoldSrc — clásico")
	movement_options.select(0 if GameData.movement_profile == "cs2_experimental" else 1)
	movement_options.tooltip_text = "Primera etapa: aceleración, frenado y counter-strafe en suelo. No es Rubikon ni subtick. Afecta al jugador y a los bots."
	movement_options.item_selected.connect(func(index: int): GameData.movement_profile = "cs2_experimental" if index == 0 else "goldsrc")
	settings_grid.add_child(movement_options)
	var loadout_label := Label.new()
	loadout_label.text = "Arma en DM:"
	settings_grid.add_child(loadout_label)
	_dm_weapon_opt = OptionButton.new()
	for wid in ["ak47", "m4a1", "aug", "sg552", "mp5navy", "p90", "awp", "m3", "galil", "famas"]:
		if GameData.weapons.has(wid):
			var index := _dm_weapon_opt.item_count
			_dm_weapon_opt.add_item(GameData.weapons[wid].get("name", wid))
			_dm_weapon_opt.set_item_metadata(index, wid)
			if wid == GameData.dm_primary:
				_dm_weapon_opt.select(index)
	settings_grid.add_child(_dm_weapon_opt)
	_dm_weapon_opt.disabled = _game_mode_opt.selected != 1
	_game_mode_opt.item_selected.connect(func(index: int): _dm_weapon_opt.disabled = index != 1)
	_game_mode_opt.tooltip_text = "Team DM: 40 team frags or 10 minutes; respawn after 3 seconds, 2 seconds of protection."

	var bl := Label.new()
	bl.text = "Cantidad de bots:"
	bl.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(bl)
	_bot_spin = SpinBox.new()
	_bot_spin.min_value = 0
	_bot_spin.max_value = 19
	_bot_spin.value = GameData.bot_count
	settings_grid.add_child(_bot_spin)

	var dl := Label.new()
	dl.text = "Dificultad:"
	dl.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(dl)
	_diff_opt = OptionButton.new()
	for s in ["Easy", "Normal", "Hard", "Expert"]:
		_diff_opt.add_item(s)
	_diff_opt.selected = GameData.bot_difficulty
	settings_grid.add_child(_diff_opt)

	var ml := Label.new()
	ml.text = "Dinero inicial:"
	ml.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(ml)
	_money_opt = OptionButton.new()
	_money_opt.add_item("$800 (Classic Competitive)", 800)
	_money_opt.add_item("$3500 (Mid Round)", 3500)
	_money_opt.add_item("$16000 (Full Buy Practice)", 16000)
	_money_opt.selected = 0
	settings_grid.add_child(_money_opt)

	var gl := Label.new()
	gl.text = "Guantes:"
	gl.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(gl)
	_glove_opt = OptionButton.new()
	_glove_opt.custom_minimum_size.x = 180.0
	_populate_glove_options(_glove_opt)
	settings_grid.add_child(_glove_opt)

	var knife_label := Label.new()
	knife_label.text = "Cuchillo:"
	knife_label.add_theme_font_size_override("font_size", 13)
	settings_grid.add_child(knife_label)
	_knife_opt = OptionButton.new()
	_knife_opt.custom_minimum_size.x = 180.0
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

	for option in [_game_mode_opt, _dm_weapon_opt, _diff_opt, _money_opt, _glove_opt, _knife_opt]:
		option.fit_to_longest_item = false
		option.clip_text = true
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.get_popup().max_size = Vector2i(680, 500)

	var start_btn := Button.new()
	start_btn.text = "INICIAR PARTIDA  →"
	start_btn.custom_minimum_size = Vector2(0, 38)
	start_btn.add_theme_font_size_override("font_size", 16)
	start_btn.add_theme_color_override("font_color", Color(0.06, 0.08, 0.10))
	var sb_launch := StyleBoxFlat.new()
	sb_launch.bg_color = AMBER
	sb_launch.border_color = AMBER
	sb_launch.set_border_width_all(2)
	start_btn.add_theme_stylebox_override("normal", sb_launch)
	var sb_launch_h := sb_launch.duplicate() as StyleBoxFlat
	sb_launch_h.bg_color = Color(1.0, 0.82, 0.35)
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
	GameData.game_mode = "deathmatch" if _game_mode_opt != null and _game_mode_opt.selected == 1 else "classic"
	if _dm_weapon_opt != null:
		GameData.dm_primary = String(_dm_weapon_opt.get_item_metadata(_dm_weapon_opt.selected))
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
	get_tree().change_scene_to_file("res://scenes/GameWorld.tscn")


func _build_arsenal_dialog() -> void:
	var res := _make_modal_panel("ARSENAL  /  INVENTARIO E INSPECCIÓN")
	_arsenal_panel = res[0]
	var vbox: VBoxContainer = res[1]

	var agent_row := HBoxContainer.new()
	agent_row.add_child(_menu_label("BRAZOS DEL AGENTE", 13))
	var agent_choice := OptionButton.new()
	_agent_arms_opt = agent_choice
	agent_choice.name = "AgentArmsSelector"
	for faction in ["CT", "T"]:
		for info in GameData.classes.get(faction, []):
			agent_choice.add_item(faction + " / " + String(info.name))
			agent_choice.set_item_metadata(agent_choice.item_count - 1, {"team": faction, "class": info.id})
			if info.id == _preview_agent_class:
				agent_choice.select(agent_choice.item_count - 1)
	agent_choice.item_selected.connect(func(index: int):
		var selected: Dictionary = agent_choice.get_item_metadata(index)
		_preview_agent_team = selected.team
		_preview_agent_class = selected["class"]
		GameData.view_agent_class = _preview_agent_class
		GameData.view_agent_team = _preview_agent_team
		if not _viewer_current_wid.is_empty():
			_load_viewer_weapon(_viewer_current_wid)
	)
	agent_row.add_child(agent_choice)
	vbox.add_child(agent_row)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	vbox.add_child(body)

	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 260
	library.add_theme_constant_override("separation", 10)
	body.add_child(library)
	library.add_child(_menu_label("TU COLECCIÓN", 13, AMBER))
	_arsenal_search = LineEdit.new()
	_arsenal_search.placeholder_text = "Buscar arma, modelo o equipo…"
	_arsenal_search.clear_button_enabled = true
	library.add_child(_arsenal_search)
	_arsenal_category = OptionButton.new()
	_arsenal_category.fit_to_longest_item = false
	for category in ["TODO", "RIFLES", "PISTOLAS", "SUBFUSILES", "FRANCOTIRADORES", "ESCOPETAS", "AMETRALLADORAS", "UTILIDAD", "CUCHILLOS", "GUANTES", "PERSONAJES", "EQUIPO"]:
		_arsenal_category.add_item(category)
	library.add_child(_arsenal_category)
	_arsenal_count = _menu_label("", 12, Color(0.57, 0.66, 0.72))
	library.add_child(_arsenal_count)
	_arsenal_list = ItemList.new()
	_arsenal_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_arsenal_list.add_theme_font_size_override("font_size", 14)
	_arsenal_list.add_theme_constant_override("v_separation", 12)
	_arsenal_list.clip_contents = true
	library.add_child(_arsenal_list)
	_build_arsenal_catalogue()
	_arsenal_search.text_changed.connect(func(_text: String): _refresh_arsenal_list())
	_arsenal_category.item_selected.connect(func(_index: int): _refresh_arsenal_list())
	_arsenal_list.item_selected.connect(_on_arsenal_item_selected)
	_refresh_arsenal_list()

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	_arsenal_kind = _menu_label("VISTA DE EQUIPAMIENTO", 12, AMBER)
	right.add_child(_arsenal_kind)
	_arsenal_title = _menu_label("Selecciona un objeto", 26)
	_arsenal_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(_arsenal_title)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(280, 180)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(svc)

	_viewer_viewport = SubViewport.new()
	_viewer_viewport.own_world_3d = true
	_viewer_viewport.transparent_bg = false
	var studio := WorldEnvironment.new()
	studio.environment = Environment.new()
	studio.environment.background_mode = Environment.BG_COLOR
	studio.environment.background_color = Color(0.14, 0.18, 0.22)
	studio.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	studio.environment.ambient_light_color = Color(0.65, 0.73, 0.80)
	studio.environment.ambient_light_energy = 1.0
	_viewer_viewport.add_child(studio)
	svc.add_child(_viewer_viewport)

	var vcam := Camera3D.new()
	_viewer_camera = vcam
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
	var front_fill := OmniLight3D.new()
	front_fill.position = Vector3(1.3, 0.6, 1.2)
	front_fill.light_energy = 2.2
	front_fill.omni_range = 5.0
	_viewer_viewport.add_child(front_fill)

	_viewer_pivot = Node3D.new()
	_viewer_viewport.add_child(_viewer_pivot)

	_arsenal_tabs = TabContainer.new()
	_arsenal_tabs.custom_minimum_size.y = 180
	right.add_child(_arsenal_tabs)
	var finish_tab := VBoxContainer.new()
	finish_tab.name = "Acabados"
	_arsenal_tabs.add_child(finish_tab)
	var animation_tab := VBoxContainer.new()
	animation_tab.name = "Animaciones"
	_arsenal_tabs.add_child(animation_tab)
	var sound_tab := VBoxContainer.new()
	sound_tab.name = "Sonidos"
	_arsenal_tabs.add_child(sound_tab)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.name = "Detalles"
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_arsenal_tabs.add_child(detail_scroll)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	var fire_btn := Button.new()
	fire_btn.text = "PROBAR DISPARO"
	fire_btn.pressed.connect(_test_viewer_fire)
	var rel_btn := Button.new()
	rel_btn.text = "RECARGA / MOVIMIENTO"
	rel_btn.pressed.connect(func():
		if _viewer_anim:
			for a in _viewer_anim.get_animation_list():
				if "reload" in a.to_lower() or a.to_lower() == "run":
					_viewer_anim.play(a)
					break
	)
	btn_row.add_child(fire_btn)
	btn_row.add_child(rel_btn)
	animation_tab.add_child(btn_row)

	var animation_row := HBoxContainer.new()
	var animation_label := Label.new()
	animation_label.text = "Secuencia"
	animation_row.add_child(animation_label)
	_viewer_animation_opt = OptionButton.new()
	_viewer_animation_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewer_animation_opt.fit_to_longest_item = false
	_viewer_animation_opt.clip_text = true
	_viewer_animation_opt.item_selected.connect(func(index: int):
		if _viewer_anim != null and index >= 0:
			_viewer_anim.stop()
			_viewer_anim.speed_scale = 1.0
			_viewer_anim.play(String(_viewer_animation_opt.get_item_metadata(index)))
			_viewer_anim.advance(0.0)
	)
	animation_row.add_child(_viewer_animation_opt)
	animation_tab.add_child(animation_row)

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
	listen.text = "ESCUCHAR"
	listen.pressed.connect(func():
		audition.stop()
		audition.stream = GameData.get_sound(String(audio_options.get_item_metadata(audio_options.selected)))
		audition.volume_db = -5.0 + GameData.master_volume_db + GameData.sound_gain_db(String(audio_options.get_item_metadata(audio_options.selected)))
		audition.play()
	)
	var stop_audio := Button.new()
	stop_audio.text = "DETENER"
	stop_audio.pressed.connect(audition.stop)
	audio_row.add_child(audio_options)
	audio_row.add_child(listen)
	audio_row.add_child(stop_audio)
	sound_tab.add_child(audio_row)
	_arsenal_tabs.tab_changed.connect(func(_tab: int): audition.stop())
	_arsenal_panel.visibility_changed.connect(func():
		if not _arsenal_panel.visible:
			audition.stop()
	)

	var skin_row := HBoxContainer.new()
	skin_row.add_theme_constant_override("separation", 8)
	var skin_label := Label.new()
	skin_label.text = "Acabado para la próxima partida"
	skin_label.add_theme_font_size_override("font_size", 12)
	skin_row.add_child(skin_label)
	_skin_opt = OptionButton.new()
	_skin_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skin_opt.fit_to_longest_item = false
	_skin_opt.clip_text = true
	_skin_opt.add_theme_font_size_override("font_size", 12)
	_skin_opt.item_selected.connect(_on_viewer_skin_selected)
	skin_row.add_child(_skin_opt)
	finish_tab.add_child(skin_row)

	_viewer_stats_lbl = Label.new()
	_viewer_stats_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewer_stats_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_viewer_stats_lbl.add_theme_font_size_override("font_size", 12)
	_viewer_stats_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.76))
	detail_scroll.add_child(_viewer_stats_lbl)


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
		if mi.has_meta("native_view_cosmetic"):
			return
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
	var default_label := "Original" if not options.is_empty() else "Original — sin acabados alternativos"
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
	_set_arsenal_heading(String(GameData.weapons.get(wid, {}).get("name", wid)), _weapon_category(wid))
	_viewer_current_wid = wid
	if _viewer_camera != null:
		_viewer_camera.fov = 48.0
		_viewer_camera.look_at_from_position(Vector3(0.85, 0.45, 1.25), Vector3(-0.08, -0.03, 0.35), Vector3.UP)
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
		AgentViewArms.apply(inst, String(spec.get("v_model", "v_ak47")), _preview_agent_team, _preview_agent_class)
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
	_preview_agent_class = cid
	_preview_agent_team = "CT" if cid in ["urban", "gsg9", "sas", "gign"] else "T"
	GameData.view_agent_class = _preview_agent_class
	GameData.view_agent_team = _preview_agent_team
	if _agent_arms_opt != null:
		for index in _agent_arms_opt.item_count:
			if String(_agent_arms_opt.get_item_metadata(index).get("class", "")) == cid:
				_agent_arms_opt.select(index)
	_set_arsenal_heading(String(GameData.modern_agents.get("agents", {}).get(ModernAgentPose.role("CT" if cid in ["urban", "gsg9", "sas", "gign"] else "T", cid), {}).get("name", cid)), "AGENTES CT / T")
	if _viewer_camera != null:
		_viewer_camera.fov = 65.0
		_viewer_camera.look_at_from_position(Vector3(0.0, 0.35, 1.35), Vector3(0.0, 0.3, 0.0), Vector3.UP)
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
		ModernAgentPose.prepare_model(inst, ModernAgentPose.role("CT" if cid in ["urban", "gsg9", "sas", "gign"] else "T", cid))
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
				var hand_name := "hand_R" if ModernAgentPose.is_modern(sk) else "Bip01 R Hand"
				if ModernAgentPose.is_modern(sk):
					inst.position.y -= CSActor.MODEL_STAND_OFFSET_Y * 0.5
				if sk and sk.find_bone(hand_name) >= 0 and cid not in ["hostage", "scientist"]:
					var ba := BoneAttachment3D.new()
					ba.bone_name = hand_name
					sk.add_child(ba)
					var wmdl := "p_usp" if cid == "vip" else ("p_m4a1" if is_ct_mdl else "p_ak47")
					var wsc := GameData.get_model_scene("weapons/" + wmdl)
					if wsc:
						var wi := wsc.instantiate()
						_style_viewer_meshes(wi)
						ba.add_child(wi)
						if ModernAgentPose.is_modern(sk):
							ModernAgentPose.fit_prop(wi, ModernAgentPose.role("CT" if is_ct_mdl else "T", cid), "m4a1" if is_ct_mdl else "ak47")
			for a in anim_list:
				if a.to_lower() == "idle1" or a.to_lower().begins_with("idle"):
					_viewer_anim.play(a)
					break
		if not skel_list.is_empty() and ModernAgentPose.is_modern(skel_list[0]) and _viewer_anim:
			var is_ct := cid in ["urban", "gsg9", "sas", "gign"]
			ModernPreviewGrip.attach(inst, skel_list[0], _viewer_anim, ModernAgentPose.role("CT" if is_ct else "T", cid), "m4a1" if is_ct else "ak47")
	_viewer_stats_lbl.text = "Agentes modernos — CS2 agent appearance, native animation packs" if cid not in ["hostage", "scientist", "vip"] else "Classic mission character: " + cid


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
	var res := _make_modal_panel("AJUSTES  /  CONTROLES Y AUDIO")
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

	var background_label := Label.new()
	background_label.text = "Fondo del menú de inicio"
	grid.add_child(background_label)
	var backgrounds := OptionButton.new()
	backgrounds.name = "MenuBackgroundSelector"
	for text in MenuBackdrop.LABELS:
		backgrounds.add_item(text)
	backgrounds.select(MenuBackdrop.MAPS.find(_home_background.selection))
	backgrounds.item_selected.connect(func(index: int): _home_background.change_background(MenuBackdrop.MAPS[index]))
	grid.add_child(backgrounds)
	var motion_label := Label.new()
	motion_label.text = "Movimiento del fondo"
	grid.add_child(motion_label)
	var motion := CheckBox.new()
	motion.button_pressed = _home_background.motion
	motion.toggled.connect(func(enabled: bool):
		_home_background.motion = enabled
		_home_background.save_preferences()
	)
	grid.add_child(motion)

	var editor_button := Button.new()
	editor_button.text = "Editor de mira y HUD"
	editor_button.pressed.connect(func(): UICustomizationEditor.open(self))
	content.add_child(editor_button)

	var cosmetic_labels := ["Original casings + native ejection timing", "Low-ammunition warning colors", "Native dropped defuse-kit model"]
	var keys: Array = GameData.COSMETIC_KEYS.duplicate()
	keys.erase("native_ammo_icons")
	keys.erase("ambient_chickens_enabled")
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
	_set_arsenal_heading("Kit de desactivación", "EQUIPO")
	if resource != "defuser_item":
		return
	if _viewer_camera != null:
		_viewer_camera.fov = 65.0
		_viewer_camera.look_at_from_position(Vector3(0.0, 0.35, 1.35), Vector3(0.0, 0.15, 0.0), Vector3.UP)
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
	_viewer_stats_lbl.text += "Original dropped defuse-kit model; animated character entries removed."


func _weapon_category(wid: String) -> String:
	if wid == "knife":
		return "CUCHILLOS"
	if wid in ["awp", "scout", "g3sg1", "sg550"]:
		return "FRANCOTIRADORES"
	if wid in ["m3", "xm1014", "mag7", "sawedoff"]:
		return "ESCOPETAS"
	if wid in ["m249", "negev"]:
		return "AMETRALLADORAS"
	if wid in ["ak47", "m4a1", "m4a4", "aug", "sg552", "famas", "galil"]:
		return "RIFLES"
	var spec: Dictionary = GameData.weapons.get(wid, {})
	if int(spec.get("slot", 0)) == 2:
		return "PISTOLAS"
	if int(spec.get("slot", 0)) == 1:
		return "SUBFUSILES"
	return "UTILIDAD"

func _build_arsenal_catalogue() -> void:
	_arsenal_entries.clear()
	var ids := GameData.weapons.keys()
	ids.sort()
	for wid in ids:
		var spec: Dictionary = GameData.weapons[wid]
		_arsenal_entries.append({"name": String(spec.get("name", wid)), "category": _weapon_category(String(wid)), "meta": String(wid)})
	for team in ["CT", "T"]:
		for info in GameData.classes.get(team, []):
			_arsenal_entries.append({"name": team + " / " + String(info["name"]), "category": "PERSONAJES", "meta": "player:" + String(info["id"])})
	for raw in GameData.get_knife_options():
		var option := raw as Dictionary
		if String(option["id"]) != "original":
			_arsenal_entries.append({"name": String(option["name"]), "category": "CUCHILLOS", "meta": "knife:" + String(option["id"])})
	_arsenal_entries.append({"name": "Guantes clásicos", "category": "GUANTES", "meta": "glove:" + String(GameData.sport_gloves.get("classic_id", "classic"))})
	for raw in GameData.get_glove_options():
		var option := raw as Dictionary
		_arsenal_entries.append({"name": "%s / %s" % [String(option.get("family", "Sport")), String(option.get("wear_code", ""))], "category": "GUANTES", "meta": "glove:" + String(option.get("id", ""))})
	_arsenal_entries.append({"name": "Kit de desactivación", "category": "EQUIPO", "meta": "native:defuser_item"})

func _refresh_arsenal_list() -> void:
	var previous := _arsenal_selected_meta
	_arsenal_list.clear()
	var query := _arsenal_search.text.strip_edges().to_lower()
	var category := _arsenal_category.get_item_text(_arsenal_category.selected)
	for entry in _arsenal_entries:
		if category != "TODO" and category != String(entry.category):
			continue
		var searchable := (String(entry.name) + " " + String(entry.meta) + " " + String(entry.category)).to_lower()
		if not query.is_empty() and not searchable.contains(query):
			continue
		var index := _arsenal_list.add_item(String(entry.name))
		_arsenal_list.set_item_metadata(index, entry.meta)
		_arsenal_list.set_item_tooltip(index, String(entry.category) + " / " + String(entry.name))
		if String(entry.meta) == previous:
			_arsenal_list.select(index)
	_arsenal_count.text = "%d OBJETOS  /  %s" % [_arsenal_list.item_count, category] if _arsenal_list.item_count > 0 else "SIN RESULTADOS · Cambia la búsqueda"

func _on_arsenal_item_selected(index: int) -> void:
	var meta := String(_arsenal_list.get_item_metadata(index))
	_arsenal_selected_meta = meta
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
	for entry in _arsenal_entries:
		if String(entry.meta) == meta:
			_set_arsenal_heading(String(entry.name), String(entry.category))
			break

func _set_arsenal_heading(title: String, category: String) -> void:
	if _arsenal_title != null:
		_arsenal_title.text = title
	if _arsenal_kind != null:
		_arsenal_kind.text = category + "  /  INSPECCIÓN 3D"
