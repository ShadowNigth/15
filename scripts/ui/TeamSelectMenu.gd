class_name TeamSelectMenu
extends CanvasLayer
## Authentic Counter-Strike 1.5 Team & Appearance Selection VGUI (M key).

signal team_class_chosen(team_str: String, class_str: String)

const AMBER := Color(1.0, 0.68, 0.12)

var is_open: bool = false
var _title_lbl: Label = null
var _list_vbox: VBoxContainer = null
var _portrait: TextureRect = null
var _bio_lbl: Label = null
var _hotkeys: Array = []


func _ready() -> void:
	layer = 14
	visible = false
	_build_ui()


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -350
	panel.offset_right = 350
	panel.offset_top = -225
	panel.offset_bottom = 225
	panel.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.03, 0.88)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.add_theme_color_override("font_color", AMBER)
	vbox.add_child(_title_lbl)

	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	_list_vbox = VBoxContainer.new()
	_list_vbox.custom_minimum_size = Vector2(280, 0)
	_list_vbox.add_theme_constant_override("separation", 8)
	hbox.add_child(_list_vbox)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	hbox.add_child(right_vbox)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(210, 135)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right_vbox.add_child(_portrait)

	var bio_scroll := ScrollContainer.new()
	bio_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bio_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bio_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_vbox.add_child(bio_scroll)

	_bio_lbl = Label.new()
	_bio_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bio_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bio_lbl.add_theme_font_size_override("font_size", 12)
	_bio_lbl.add_theme_color_override("font_color", Color(0.88, 0.85, 0.74))
	bio_scroll.add_child(_bio_lbl)


func open_menu() -> void:
	is_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_team_step()


func close_menu() -> void:
	is_open = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE or kc == KEY_0:
			get_viewport().set_input_as_handled()
			close_menu()
			return
		if kc >= KEY_1 and kc <= KEY_9:
			var n := kc - KEY_0
			for hk in _hotkeys:
				if int(hk["num"]) == n:
					get_viewport().set_input_as_handled()
					(hk["cb"] as Callable).call()
					return


func _show_team_step() -> void:
	_clear_list()
	_title_lbl.text = "SELECT A TEAM"
	_portrait.texture = GameData.get_texture("res://assets/ui/vgui/640_banner.png")
	_bio_lbl.text = String(RoundManager.current_map_data.get("briefing", "Choose Terrorist Force or Counter-Terrorist Force."))

	_add_btn(1, "Terrorist Force", func(): _show_class_step("T"), "640_t_random", "Plant the C4 or guard hostages.")
	_add_btn(2, "Counter-Terrorist Force", func(): _show_class_step("CT"), "640_ct_random", "Defuse the C4, rescue hostages, or escort the VIP.")
	_add_btn(5, "Auto-Select", func(): _show_class_step("CT" if randi() % 2 == 0 else "T"), "", "Automatically join a team.")


func _show_class_step(tm: String) -> void:
	_clear_list()
	_title_lbl.text = "SELECT APPEARANCE (%s)" % tm
	var clist: Array = GameData.classes.get(tm, [])
	for cinfo in clist:
		var cid := String(cinfo["id"])
		_add_btn(
			int(cinfo["num"]),
			String(cinfo["name"]),
			func(): _confirm_choice(tm, cid),
			String(cinfo.get("vgui", "")),
			String(cinfo.get("description", ""))
		)
	_add_btn(5, "Auto-Select Appearance", func():
		var pick: Dictionary = clist[randi() % clist.size()]
		_confirm_choice(tm, String(pick["id"]))
	, "", "Randomly select a faction model.")


func _clear_list() -> void:
	_hotkeys.clear()
	for c in _list_vbox.get_children():
		c.queue_free()


func _add_btn(num: int, text: String, cb: Callable, vgui: String, bio: String) -> void:
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%d. %s" % [num, text]
	b.add_theme_color_override("font_color", AMBER)
	b.pressed.connect(func():
		AudioManager.play_ui("launch_select1.wav")
		cb.call()
	)
	b.mouse_entered.connect(func():
		AudioManager.play_ui("launch_glow1.wav")
		if not vgui.is_empty():
			_portrait.texture = GameData.get_texture("res://assets/ui/vgui/%s.png" % vgui.to_lower())
		if not bio.is_empty():
			_bio_lbl.text = bio
	)
	_list_vbox.add_child(b)
	_hotkeys.append({"num": num, "cb": cb})


func _confirm_choice(tm: String, cid: String) -> void:
	close_menu()
	team_class_chosen.emit(tm, cid)
