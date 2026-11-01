class_name BuyMenu
extends CanvasLayer
## CS:GO-style buy menu: fullscreen dark overlay, a row of category tiles
## (PISTOLS / HEAVY / SMGS / RIFLES / GEAR / GRENADES) and item cards with
## weapon previews, price tags and positional hotkey badges. Works with the
## mouse and with number keys (B-4-1 style navigation still resolves through
## positional numbering).

signal menu_closed()

const BG := Color(0.028, 0.038, 0.052, 0.90)
const CARD_BG := Color(0.10, 0.13, 0.17, 0.97)
const CARD_HOVER := Color(0.17, 0.22, 0.29, 0.98)
const CARD_PRESSED := Color(0.22, 0.28, 0.36, 0.98)
const CARD_BORDER := Color(0.45, 0.52, 0.60, 0.35)
const ACCENT := Color(0.93, 0.64, 0.18, 1.0)
const GREEN_MONEY := Color(0.42, 0.85, 0.40, 1.0)
const RED_PRICE := Color(0.93, 0.32, 0.28, 1.0)
const TEXT_WHITE := Color(0.93, 0.94, 0.96, 1.0)
const TEXT_DIM := Color(0.62, 0.66, 0.72, 1.0)
const CT_TINT := Color(0.36, 0.58, 0.90, 1.0)
const T_TINT := Color(0.88, 0.64, 0.24, 1.0)

var player: PlayerController = null
var is_open: bool = false
var current_category: int = 0  # 0 = category tiles, 1..6 = category contents

var _title_lbl: Label = null
var _money_lbl: Label = null
var _team_lbl: Label = null
var _status_lbl: Label = null
var _hint_lbl: Label = null
var _cards_slot: CenterContainer = null
var _entries: Array = []  # [{num: int, action: Callable}] positional hotkeys


func _ready() -> void:
	layer = 12
	visible = false
	_build_ui()


func _build_ui() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 52)
	margin.add_theme_constant_override("margin_right", 52)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	overlay.add_child(margin)

	var main := VBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(main)

	# --- Header: title left, money right ---
	var header := HBoxContainer.new()
	_title_lbl = Label.new()
	_title_lbl.text = "BUY MENU"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_font_size_override("font_size", 26)
	_title_lbl.add_theme_color_override("font_color", TEXT_WHITE)
	header.add_child(_title_lbl)
	_team_lbl = Label.new()
	_team_lbl.add_theme_font_size_override("font_size", 15)
	_team_lbl.add_theme_color_override("font_color", CT_TINT)
	header.add_child(_team_lbl)
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(18, 0)
	header.add_child(spacer1)
	_money_lbl = Label.new()
	_money_lbl.text = "$ 0"
	_money_lbl.add_theme_font_size_override("font_size", 30)
	_money_lbl.add_theme_color_override("font_color", GREEN_MONEY)
	header.add_child(_money_lbl)
	main.add_child(header)

	var sub := HBoxContainer.new()
	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 14)
	_status_lbl.add_theme_color_override("font_color", TEXT_DIM)
	sub.add_child(_status_lbl)
	main.add_child(sub)

	# --- Center: category tiles / item cards ---
	var gap_top := Control.new()
	gap_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(gap_top)
	_cards_slot = CenterContainer.new()
	_cards_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(_cards_slot)
	var gap_bottom := Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(gap_bottom)

	# --- Footer: hints + exit ---
	var footer := HBoxContainer.new()
	_hint_lbl = Label.new()
	_hint_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_lbl.add_theme_font_size_override("font_size", 14)
	_hint_lbl.add_theme_color_override("font_color", TEXT_DIM)
	footer.add_child(_hint_lbl)
	var exit_btn := Button.new()
	exit_btn.text = "  EXIT  [B]  "
	exit_btn.pressed.connect(close_menu)
	exit_btn.mouse_entered.connect(func(): AudioManager.play_ui("launch_glow1.wav"))
	_style_button(exit_btn, Vector2(130, 34))
	footer.add_child(exit_btn)
	main.add_child(footer)


func _style_button(btn: Button, min_size: Vector2, font_size: int = 16) -> void:
	btn.custom_minimum_size = min_size
	btn.clip_text = true
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_stylebox_override("normal", _card_style(CARD_BG, CARD_BORDER, 1))
	btn.add_theme_stylebox_override("hover", _card_style(CARD_HOVER, ACCENT, 2))
	btn.add_theme_stylebox_override("pressed", _card_style(CARD_PRESSED, ACCENT, 2))
	btn.add_theme_stylebox_override("focus", _card_style(CARD_HOVER, Color(1, 1, 1, 0.55), 1))
	btn.add_theme_stylebox_override("disabled", _card_style(Color(0.07, 0.08, 0.10, 0.9), Color(0.3, 0.33, 0.37, 0.3), 1))
	btn.add_theme_color_override("font_color", TEXT_WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_color_override("font_disabled_color", Color(0.5, 0.53, 0.57, 0.7))


func _card_style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	return sb


func open_menu(p: PlayerController) -> void:
	player = p
	if not is_instance_valid(player) or not player.can_use_buy_menu():
		RoundManager.center_message.emit("You are not in a buy zone or buy time has expired!", 1.8)
		return
	is_open = true
	visible = true
	player.ui_blocking_input = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioManager.play_ui("launch_upmenu1.wav")
	_show_category(0)


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if is_instance_valid(player):
		player.ui_blocking_input = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	AudioManager.play_ui("launch_dnmenu1.wav")
	menu_closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE or kc == KEY_0 or kc == KEY_B:
			get_viewport().set_input_as_handled()
			if current_category > 0 and kc != KEY_B:
				_show_category(0)
			else:
				close_menu()
			return
		if kc >= KEY_1 and kc <= KEY_9:
			var num := kc - KEY_0
			for entry in _entries:
				if int(entry["num"]) == num:
					get_viewport().set_input_as_handled()
					(entry["action"] as Callable).call()
					return


func open_category(cat: int) -> void:
	AudioManager.play_ui("launch_select1.wav")
	_show_category(cat)


# --- Menu contents ------------------------------------------------------------

const CATEGORIES: Array = [
	[1, "PISTOLS"],
	[2, "HEAVY"],
	[3, "SMGS"],
	[4, "RIFLES"],
	[5, "GEAR"],
	[6, "GRENADES"],
]


func _show_category(cat: int) -> void:
	current_category = cat
	_entries.clear()
	for c in _cards_slot.get_children():
		c.queue_free()

	var money := int(player.money) if is_instance_valid(player) else 0
	_money_lbl.text = "$ %d" % money
	_title_lbl.text = "BUY MENU" if cat == 0 else String(_cat_title(cat))
	if is_instance_valid(player):
		_team_lbl.text = "COUNTER-TERRORISTS" if player.team == "CT" else "TERRORISTS"
		_team_lbl.add_theme_color_override("font_color", CT_TINT if player.team == "CT" else T_TINT)
	var bt: float = RoundManager.buy_time_left
	if bt > 0.0:
		_status_lbl.text = "BUY TIME REMAINING   %d:%02d" % [int(bt / 60.0), int(bt) % 60]
		_status_lbl.add_theme_color_override("font_color", TEXT_DIM)
	else:
		_status_lbl.text = "BUY TIME EXPIRED"
		_status_lbl.add_theme_color_override("font_color", RED_PRICE)
	_hint_lbl.text = "1-9  Buy    ·    0 / ESC  Back    ·    Mouse to navigate" if cat > 0 \
		else "1-6  Select category    ·    Mouse to navigate    ·    B / ESC  Exit"

	if cat == 0:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 14)
		for rc in CATEGORIES:
			var cid := int(rc[0])
			var count := _category_count(cid)
			box.add_child(_tile_button(cid, String(rc[1]), "%d ITEMS" % count))
			_entries.append({"num": cid, "action": func(): open_category(cid)})
		_cards_slot.add_child(box)
		return

	var specs := _category_specs(cat)
	var n := specs.size()
	if n == 0:
		_hint_lbl.text = "Nothing to buy here.   ·   0 / ESC  Back"
		return
	if n <= 6:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		for i in range(n):
			hbox.add_child(_card_from_spec(cat, specs[i], i + 1, money))
			_entries.append({"num": i + 1, "action": (specs[i]["action"] as Callable)})
		_cards_slot.add_child(hbox)
	else:
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		for i in range(n):
			grid.add_child(_card_from_spec(cat, specs[i], i + 1, money))
			_entries.append({"num": i + 1, "action": (specs[i]["action"] as Callable)})
		_cards_slot.add_child(grid)


func _cat_title(cat: int) -> String:
	for rc in CATEGORIES:
		if int(rc[0]) == cat:
			return String(rc[1])
	return "BUY"


## Turns the classic CS 1.5 info block ("Price\t: $650\nDescription\t: ...")
## into a one-line card caption.
func _short_desc(raw: String) -> String:
	var flat := raw.replace("\t", " ").replace("\n", " ")
	var di := flat.find("Description")
	if di >= 0:
		flat = flat.substr(di + 11).lstrip(": ").strip_edges()
	flat = " ".join(flat.split(" ", false))
	if flat.length() > 62:
		flat = flat.substr(0, 62) + "…"
	return flat


func _category_count(cat: int) -> int:
	return _category_specs(cat).size()


## Returns the purchase entries for a category as
## [{id, name, price, vgui, desc, action}] already team-filtered & ordered.
func _category_specs(cat: int) -> Array:
	var out: Array = []
	if not is_instance_valid(player):
		return out
	match cat:
		1, 3, 4, 2, 6:
			var want_cats: Array = []
			match cat:
				1: want_cats = [1]
				2: want_cats = [2, 5]  # CS:GO HEAVY = shotguns + machine guns
				3: want_cats = [3]
				4: want_cats = [4]
				6: want_cats = [8]     # grenades live in buy_cat 8
			var list: Array = []
			for wid in GameData.weapons.keys():
				var spec: Dictionary = GameData.weapons[wid]
				if int(spec.get("buy_cat", 0)) not in want_cats:
					continue
				var wteam := String(spec.get("team", "ANY"))
				if wteam != "ANY" and wteam != player.team:
					continue
				list.append(spec)
			list.sort_custom(func(a, b):
				var ka := int(a.get("buy_cat", 0)) * 100 + int(a.get("buy_num", 0))
				var kb := int(b.get("buy_cat", 0)) * 100 + int(b.get("buy_num", 0))
				return ka < kb
			)
			for spec in list:
				var wid2 := String(spec["id"])
				out.append({
					"id": wid2,
					"name": String(spec.get("name", wid2)),
					"price": int(spec.get("price", 0)),
					"vgui": String(spec.get("vgui", "")),
					"desc": "",
					"action": func(): _purchase_weapon(wid2),
				})
		5:
			var eq_order := ["kevlar", "kevlar_helmet", "defuser", "nightvision"]
			for eid in eq_order:
				if not GameData.equipment.has(eid):
					continue
				var eq: Dictionary = GameData.equipment[eid]
				var eteam := String(eq.get("team", "ANY"))
				if eteam != "ANY" and eteam != player.team:
					continue
				var eqid := String(eid)
				out.append({
					"id": eqid,
					"name": String(eq.get("name", eid)),
					"price": int(eq.get("price", 0)),
					"vgui": "",
					"desc": _short_desc(String(eq.get("description", ""))),
					"action": func(): _purchase_eq(eqid),
				})
			out.append({
				"id": "ammo1",
				"name": "Primary Ammo (Full)",
				"price": -1,
				"vgui": "",
				"desc": "Refills your primary weapon reserve.",
				"action": func(): _buy_ammo(1),
			})
			out.append({
				"id": "ammo2",
				"name": "Secondary Ammo (Full)",
				"price": -1,
				"vgui": "",
				"desc": "Refills your secondary weapon reserve.",
				"action": func(): _buy_ammo(2),
			})
	return out


func _tile_button(cid: int, title: String, sub: String) -> Button:
	var btn := Button.new()
	_style_button(btn, Vector2(178, 190), 16)
	btn.mouse_entered.connect(func(): AudioManager.play_ui("launch_glow1.wav"))
	btn.pressed.connect(func(): open_category(cid))
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 12.0
	vbox.offset_right = -12.0
	vbox.offset_top = 8.0
	vbox.offset_bottom = -8.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	var badge := Label.new()
	badge.text = str(cid)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(badge)
	var tl := Label.new()
	tl.text = title
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_size_override("font_size", 18)
	tl.add_theme_color_override("font_color", TEXT_WHITE)
	vbox.add_child(tl)
	var sl := Label.new()
	sl.text = sub
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.add_theme_font_size_override("font_size", 12)
	sl.add_theme_color_override("font_color", TEXT_DIM)
	vbox.add_child(sl)
	btn.add_child(vbox)
	return btn


func _card_from_spec(_cat: int, e: Dictionary, num: int, money: int) -> Button:
	var price := int(e["price"])
	var affordable: bool = price < 0 or money >= price
	var btn := Button.new()
	_style_button(btn, Vector2(176, 216), 13)
	btn.disabled = not affordable
	btn.mouse_entered.connect(func():
		AudioManager.play_ui("launch_glow1.wav")
	)
	btn.pressed.connect((e["action"] as Callable))

	var badge := Label.new()
	badge.text = str(num)
	badge.offset_left = 9.0
	badge.offset_top = 5.0
	badge.offset_right = 60.0
	badge.offset_bottom = 30.0
	badge.add_theme_font_size_override("font_size", 15)
	badge.add_theme_color_override("font_color", ACCENT if affordable else Color(0.55, 0.57, 0.6, 0.7))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(badge)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 12.0
	vbox.offset_right = -12.0
	vbox.offset_top = 28.0
	vbox.offset_bottom = -8.0
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	btn.add_child(vbox)

	var img_path := String(e["vgui"])
	if not img_path.is_empty():
		var tex := GameData.get_texture("res://assets/ui/vgui/%s.png" % img_path.to_lower())
		if tex != null:
			var img := TextureRect.new()
			img.texture = tex
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.size_flags_vertical = Control.SIZE_EXPAND_FILL
			img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vbox.add_child(img)

	var name_lbl := Label.new()
	name_lbl.text = String(e["name"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", TEXT_WHITE if affordable else Color(0.6, 0.62, 0.66, 0.8))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var desc := String(e["desc"])
	if not desc.is_empty() and img_path.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", TEXT_DIM)
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_lbl)

	var price_lbl := Label.new()
	if price >= 0:
		price_lbl.text = "$%d" % price
		price_lbl.add_theme_color_override("font_color", GREEN_MONEY if affordable else RED_PRICE)
	else:
		price_lbl.text = "REFILL"
		price_lbl.add_theme_color_override("font_color", GREEN_MONEY)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 17)
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(price_lbl)
	return btn


# --- Purchases -----------------------------------------------------------------

func _purchase_weapon(wid: String) -> void:
	if is_instance_valid(player) and player.buy_weapon(wid):
		player.buy_ammo_for_slot(1, true)
		player.buy_ammo_for_slot(2, true)
		AudioManager.play_ui("launch_select2.wav")
		_show_category(current_category)
	else:
		AudioManager.play_ui("launch_deny2.wav")


func _purchase_eq(eid: String) -> void:
	if is_instance_valid(player) and player.buy_equipment(eid):
		AudioManager.play_ui("launch_select2.wav")
		_show_category(current_category)
	else:
		AudioManager.play_ui("launch_deny2.wav")


func _buy_ammo(sl: int) -> void:
	if is_instance_valid(player):
		player.buy_ammo_for_slot(sl, true)
		AudioManager.play_ui("launch_select2.wav")
	_show_category(current_category)
