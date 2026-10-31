class_name RadioMenu
extends CanvasLayer
## Classic Counter-Strike 1.5 Z / X / C Radio Menus (keys 1-9, 0 to Exit).

var player: PlayerController = null
var active_group: String = ""
var _panel: PanelContainer = null
var _vbox: VBoxContainer = null
var _items: Array = []


func _ready() -> void:
	layer = 11
	visible = false

	_panel = PanelContainer.new()
	_panel.anchor_top = 0.34
	_panel.anchor_bottom = 0.72
	_panel.offset_left = 22
	_panel.offset_right = 300
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.03, 0.76)
	sb.border_color = Color(1.0, 0.65, 0.1, 0.85)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(_vbox)


func toggle_radio(group_key: String, p: PlayerController) -> void:
	if visible and active_group == group_key:
		close_radio()
		return
	if not is_instance_valid(p) or not p.is_alive:
		return
	player = p
	active_group = group_key
	var gdata: Dictionary = GameData.radio_menus.get(group_key, {})
	if gdata.is_empty():
		return

	for c in _vbox.get_children():
		c.queue_free()
	_items = gdata.get("items", [])

	var title := Label.new()
	title.text = String(gdata.get("title", "Radio"))
	title.add_theme_color_override("font_color", Color(1.0, 0.72, 0.18))
	title.add_theme_font_size_override("font_size", 15)
	_vbox.add_child(title)

	for it in _items:
		var lbl := Label.new()
		lbl.text = "%d. %s" % [int(it["num"]), String(it["label"])]
		lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84))
		lbl.add_theme_font_size_override("font_size", 14)
		_vbox.add_child(lbl)

	var ex := Label.new()
	ex.text = "0. Exit"
	ex.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	ex.add_theme_font_size_override("font_size", 14)
	_vbox.add_child(ex)
	visible = true


func close_radio() -> void:
	visible = false
	active_group = ""


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		if kc == KEY_0 or kc == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close_radio()
			return
		if kc >= KEY_1 and kc <= KEY_9:
			var n := kc - KEY_0
			for it in _items:
				if int(it["num"]) == n:
					get_viewport().set_input_as_handled()
					if is_instance_valid(player):
						RoundManager.send_radio_command(player, String(it["label"]), String(it["sound"]), String(it["action"]))
					close_radio()
					return
