class_name BuyMenu
extends CanvasLayer
## Authentic Counter-Strike 1.5 VGUI Buy Menu (supports both mouse and B-4-1 / B-8-2 hotkeys!).

signal menu_closed()

const AMBER := Color(1.0, 0.68, 0.12)
const PANEL_BG := Color(0.04, 0.04, 0.04, 0.86)

var player: PlayerController = null
var is_open: bool = false
var current_category: int = 0  # 0 = Root categories, 1..5 = Weapon cat, 8 = Equipment

var _root_panel: PanelContainer = null
var _title_lbl: Label = null
var _money_lbl: Label = null
var _items_vbox: VBoxContainer = null
var _preview_img: TextureRect = null
var _preview_desc: Label = null
var _current_entries: Array = []  # Array of {num: int, label: String, price: int, action: Callable, vgui: String, desc: String}


func _ready() -> void:
	layer = 12
	visible = false
	_build_ui()


func _build_ui() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	_root_panel = PanelContainer.new()
	_root_panel.anchor_left = 0.5
	_root_panel.anchor_right = 0.5
	_root_panel.anchor_top = 0.5
	_root_panel.anchor_bottom = 0.5
	_root_panel.offset_left = -380
	_root_panel.offset_right = 380
	_root_panel.offset_top = -255
	_root_panel.offset_bottom = 255
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	_root_panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(_root_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	_root_panel.add_child(main_vbox)

	var header := HBoxContainer.new()
	_title_lbl = Label.new()
	_title_lbl.text = "SHOP BY CATEGORY"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.add_theme_color_override("font_color", AMBER)
	_money_lbl = Label.new()
	_money_lbl.add_theme_font_size_override("font_size", 20)
	_money_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.35))
	header.add_child(_title_lbl)
	header.add_child(_money_lbl)
	main_vbox.add_child(header)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	main_vbox.add_child(body)

	_items_vbox = VBoxContainer.new()
	_items_vbox.custom_minimum_size = Vector2(330, 0)
	_items_vbox.add_theme_constant_override("separation", 6)
	body.add_child(_items_vbox)

	var right_vbox := VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 10)
	body.add_child(right_vbox)

	_preview_img = TextureRect.new()
	_preview_img.custom_minimum_size = Vector2(280, 130)
	_preview_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right_vbox.add_child(_preview_img)

	_preview_desc = Label.new()
	_preview_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_desc.add_theme_font_size_override("font_size", 14)
	_preview_desc.add_theme_color_override("font_color", Color(0.9, 0.86, 0.72))
	right_vbox.add_child(_preview_desc)


func open_menu(p: PlayerController) -> void:
	player = p
	if not is_instance_valid(player) or not player.can_use_buy_menu():
		RoundManager.center_message.emit("You are not in a buy zone or buy time has expired!", 1.8)
		return
	is_open = true
	visible = true
	player.ui_blocking_input = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_category(0)


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if is_instance_valid(player):
		player.ui_blocking_input = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	menu_closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE or kc == KEY_0 or kc == KEY_B:
			get_viewport().set_input_as_handled()
			close_menu()
			return
		var num := -1
		if kc >= KEY_1 and kc <= KEY_9:
			num = kc - KEY_0
		if num > 0:
			for entry in _current_entries:
				if int(entry["num"]) == num:
					get_viewport().set_input_as_handled()
					(entry["action"] as Callable).call()
					return


func _show_category(cat: int) -> void:
	current_category = cat
	_current_entries.clear()
	for c in _items_vbox.get_children():
		c.queue_free()

	_money_lbl.text = "$ %d" % (player.money if is_instance_valid(player) else 0)
	_preview_img.texture = null
	_preview_desc.text = "Use mouse or classic CS 1.5 number keys (1-8, 0 to Cancel)."

	if cat == 0:
		_title_lbl.text = "BUY ITEM (CS 1.5)"
		var root_cats := [
			[1, "Handguns (Secondary)", func(): _show_category(1)],
			[2, "Shotguns", func(): _show_category(2)],
			[3, "Sub-Machine Guns (SMG)", func(): _show_category(3)],
			[4, "Assault & Sniper Rifles", func(): _show_category(4)],
			[5, "Machine Guns", func(): _show_category(5)],
			[6, "Primary Ammo (Full)", func(): _buy_ammo_and_close(1)],
			[7, "Secondary Ammo (Full)", func(): _buy_ammo_and_close(2)],
			[8, "Equipment (Kevlar / Grenades / Kit)", func(): _show_category(8)],
		]
		for rc in root_cats:
			_add_entry_button(int(rc[0]), String(rc[1]), -1, true, rc[2], "", "")
	elif cat in [1, 2, 3, 4, 5]:
		var titles := {1: "HANDGUNS", 2: "SHOTGUNS", 3: "SUB-MACHINE GUNS", 4: "RIFLES", 5: "MACHINE GUNS"}
		_title_lbl.text = String(titles[cat])
		var list := []
		for wid in GameData.weapons.keys():
			var spec: Dictionary = GameData.weapons[wid]
			if int(spec.get("buy_cat", 0)) != cat:
				continue
			var wteam := String(spec.get("team", "ANY"))
			if wteam != "ANY" and wteam != player.team:
				continue
			list.append(spec)
		list.sort_custom(func(a, b): return int(a.get("buy_num", 0)) < int(b.get("buy_num", 0)))
		for spec in list:
			var wid2 := String(spec["id"])
			var price := int(spec.get("price", 0))
			var num := int(spec.get("buy_num", 1))
			_add_entry_button(
				num,
				String(spec.get("name", wid2)),
				price,
				player.money >= price,
				func(): _purchase_weapon(wid2),
				String(spec.get("vgui", "")),
				String(spec.get("description", ""))
			)
	elif cat == 8:
		_title_lbl.text = "EQUIPMENT"
		var eq_order := ["kevlar", "kevlar_helmet", "flashbang", "hegrenade", "smokegrenade", "defuser", "nightvision"]
		for eid in eq_order:
			if GameData.equipment.has(eid):
				var eq: Dictionary = GameData.equipment[eid]
				if String(eq.get("team", "ANY")) != "ANY" and String(eq.get("team")) != player.team:
					continue
				var p := int(eq.get("price", 0))
				_add_entry_button(
					int(eq.get("buy_num", 1)),
					String(eq.get("name", eid)),
					p,
					player.money >= p,
					func(): _purchase_eq(eid),
					"",
					String(eq.get("description", ""))
				)
			elif GameData.weapons.has(eid):
				var gs: Dictionary = GameData.weapons[eid]
				var gp := int(gs.get("price", 200))
				_add_entry_button(
					int(gs.get("buy_num", 3)),
					String(gs.get("name", eid)),
					gp,
					player.money >= gp,
					func(): _purchase_weapon(eid),
					String(gs.get("vgui", "")),
					String(gs.get("description", ""))
				)

	_add_entry_button(0, "Cancel / Back" if cat > 0 else "Exit", -1, true, func():
		if cat > 0:
			_show_category(0)
		else:
			close_menu()
	, "", "")


func _add_entry_button(num: int, label: String, price: int, affordable: bool, cb: Callable, vgui: String, desc: String) -> void:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text = ("%d. %s   ($%d)" % [num, label, price]) if price >= 0 else ("%d. %s" % [num, label])
	btn.disabled = not affordable
	btn.add_theme_color_override("font_color", AMBER if affordable else Color(0.5, 0.35, 0.3))
	btn.pressed.connect(cb)
	btn.mouse_entered.connect(func():
		AudioManager.play_ui("launch_glow1.wav")
		if not vgui.is_empty():
			_preview_img.texture = GameData.get_texture("res://assets/ui/vgui/%s.png" % vgui.to_lower())
		if not desc.is_empty():
			_preview_desc.text = desc
	)
	_items_vbox.add_child(btn)
	_current_entries.append({"num": num, "action": cb})


func _purchase_weapon(wid: String) -> void:
	if is_instance_valid(player) and player.buy_weapon(wid):
		player.buy_ammo_for_slot(1, true)
		player.buy_ammo_for_slot(2, true)
		close_menu()
	else:
		AudioManager.play_ui("launch_deny2.wav")


func _purchase_eq(eid: String) -> void:
	if is_instance_valid(player) and player.buy_equipment(eid):
		close_menu()
	else:
		AudioManager.play_ui("launch_deny2.wav")


func _buy_ammo_and_close(sl: int) -> void:
	if is_instance_valid(player):
		player.buy_ammo_for_slot(sl, true)
	close_menu()
