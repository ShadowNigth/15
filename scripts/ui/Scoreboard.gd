class_name Scoreboard
extends CanvasLayer
## Classic Counter-Strike 1.5 Translucent VGUI Scoreboard (Tab key).

var _panel: PanelContainer = null
var _header_lbl: Label = null
var _rows_vbox: VBoxContainer = null
var _refresh_accum: float = 0.0


func _ready() -> void:
	layer = 13
	visible = false

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -350
	_panel.offset_right = 350
	_panel.offset_top = -240
	_panel.offset_bottom = 240
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.02, 0.84)
	sb.border_color = Color(1.0, 0.65, 0.08, 0.85)
	sb.set_border_width_all(1)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_header_lbl = Label.new()
	_header_lbl.add_theme_font_size_override("font_size", 19)
	_header_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.15))
	vbox.add_child(_header_lbl)

	var rows_scroll := ScrollContainer.new()
	rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(rows_scroll)

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_vbox.add_theme_constant_override("separation", 3)
	rows_scroll.add_child(_rows_vbox)


func _process(delta: float) -> void:
	var want_show := Input.is_action_pressed("scoreboard")
	if want_show != visible:
		visible = want_show
		if visible:
			_refresh()
			_refresh_accum = 0.0
	elif visible:
		_refresh_accum += delta
		if _refresh_accum >= 0.25:
			_refresh_accum = 0.0
			_refresh()


func _refresh() -> void:
	var mname := String(RoundManager.current_map_data.get("name", "de_dust2"))
	_header_lbl.text = "Counter-Strike 1.5  —  Map: %s  |  Round %d" % [mname, RoundManager.round_number]

	var old_rows := _rows_vbox.get_children()
	for c in old_rows:
		_rows_vbox.remove_child(c)
		c.queue_free()

	_add_team_section("Counter-Terrorists", "CT", RoundManager.ct_score, Color(0.58, 0.82, 1.0))
	_add_team_section("Terrorists", "T", RoundManager.t_score, Color(1.0, 0.36, 0.32))


func _add_team_section(title: String, tm: String, score: int, col: Color) -> void:
	var th := Label.new()
	th.text = "%s   —   Wins: %d" % [title, score]
	th.add_theme_font_size_override("font_size", 16)
	th.add_theme_color_override("font_color", col)
	_rows_vbox.add_child(th)

	var list := []
	for a in RoundManager.actors:
		if is_instance_valid(a) and String(a.get("team")) == tm:
			list.append(a)
	list.sort_custom(func(x, y): return int(x.get("kills")) > int(y.get("kills")))

	for a in list:
		var row := HBoxContainer.new()
		var status := ""
		if not bool(a.get("is_alive")):
			status = "DEAD"
		elif bool(a.get("is_vip")):
			status = "VIP"
		elif String((a as CSActor).weapon_ctrl.slots.get(5, "")) == "c4":
			status = "BOMB"

		var nl := Label.new()
		nl.text = String(a.get("actor_name"))
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_color_override("font_color", col)
		var sl := Label.new()
		sl.text = "%-8s  K: %2d   D: %2d   %s" % [status, int(a.get("kills")), int(a.get("deaths")), "LOCAL" if bool(a.get("is_human")) else "BOT"]
		sl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
		row.add_child(nl)
		row.add_child(sl)
		_rows_vbox.add_child(row)
