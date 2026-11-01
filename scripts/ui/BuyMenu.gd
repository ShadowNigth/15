class_name BuyMenu
extends CanvasLayer
## CS:GO-style RADIAL buy menu: a wheel of category/item sectors around a
## dark centre disc (weapon icons on the ring, name + price under each slot).
## Mouse (hover by angle, click to buy) or number keys 1-9; 0/ESC goes back,
## B exits. Same purchase backends, buy-zone/time and economy rules as before.

signal menu_closed()

const RING_BG := Color(0.05, 0.065, 0.09, 0.82)
const RING_HOVER := Color(0.14, 0.19, 0.26, 0.92)
const RING_BORDER := Color(0.55, 0.60, 0.68, 0.30)
const HOVER_BORDER := Color(0.93, 0.64, 0.18, 0.95)
const CENTER_BG := Color(0.03, 0.04, 0.055, 0.94)
const ACCENT := Color(0.93, 0.64, 0.18, 1.0)
const GREEN_MONEY := Color(0.42, 0.85, 0.40, 1.0)
const RED_PRICE := Color(0.93, 0.32, 0.28, 1.0)
const TEXT_WHITE := Color(0.94, 0.95, 0.97, 1.0)
const TEXT_DIM := Color(0.68, 0.72, 0.78, 0.95)
const CT_TINT := Color(0.36, 0.58, 0.90, 1.0)
const T_TINT := Color(0.88, 0.64, 0.24, 1.0)

const CATEGORIES: Array = [
	[1, "PISTOLS"],
	[2, "HEAVY"],
	[3, "SMGS"],
	[4, "RIFLES"],
	[5, "GEAR"],
	[6, "GRENADES"],
]

var player: PlayerController = null
var is_open: bool = false
var current_category: int = 0  # 0 = section wheel, 1..6 = items of a section

var _wheel: Control = null
var _entries: Array = []  # wheel sectors: {num, name, price, vgui, desc, action}
var _hover: int = -1
var _last_status_sec: int = -1
var _hover_sound_cache: int = -1


func _ready() -> void:
	layer = 12
	visible = false
	_wheel = Control.new()
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_STOP
	_wheel.draw.connect(_draw_wheel)
	add_child(_wheel)


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


func _process(_delta: float) -> void:
	if not is_open:
		return
	var sec := int(ceilf(float(RoundManager.buy_time_left)))
	if sec != _last_status_sec:
		_last_status_sec = sec
		_wheel.queue_redraw()


func open_category(cat: int) -> void:
	AudioManager.play_ui("launch_select1.wav")
	_show_category(cat)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		_update_hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and _hover >= 0:
			get_viewport().set_input_as_handled()
			_activate(_hover)
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
			if num >= 1 and num <= _entries.size():
				get_viewport().set_input_as_handled()
				_activate(num - 1)


# --- Wheel state --------------------------------------------------------------

func _show_category(cat: int) -> void:
	current_category = cat
	_entries.clear()
	_hover = -1
	_hover_sound_cache = -1
	if cat == 0:
		for rc in CATEGORIES:
			var cid := int(rc[0])
			_entries.append({
				"num": cid,
				"name": String(rc[1]),
				"price": -2,  # section marker
				"vgui": "",
				"desc": "%d ITEMS" % _category_count(cid),
				"action": func(): open_category(cid),
			})
	else:
		var specs := _category_specs(cat)
		for i in range(specs.size()):
			var e: Dictionary = specs[i]
			_entries.append({
				"num": i + 1,
				"name": String(e["name"]),
				"price": int(e["price"]),
				"vgui": String(e["vgui"]),
				"desc": String(e["desc"]),
				"action": (e["action"] as Callable),
			})
	_wheel.queue_redraw()


func _update_hover(mouse_pos: Vector2) -> void:
	var new_hover := -1
	var n := _entries.size()
	if n > 0 and _wheel != null:
		var c := _wheel.size * 0.5
		var r_out := minf(_wheel.size.x, _wheel.size.y) * 0.36
		var r_in := r_out * 0.40
		var rel := mouse_pos - c
		var r := rel.length()
		if r >= r_in and r <= r_out + 18.0:
			var ang := atan2(rel.y, rel.x) + PI * 0.5
			if ang < 0.0:
				ang += TAU
			new_hover = int(floor(ang / (TAU / float(n)))) % n
	if new_hover != _hover:
		_hover = new_hover
		if _hover >= 0 and _hover_sound_cache != _hover:
			_hover_sound_cache = _hover
			AudioManager.play_ui("launch_glow1.wav")
		_wheel.queue_redraw()


func _activate(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	(_entries[idx]["action"] as Callable).call()


# --- Drawing ------------------------------------------------------------------

func _draw_wheel() -> void:
	var sz := _wheel.size
	var c := sz * 0.5
	var font := _wheel.get_theme_default_font()
	# Dim the scene behind (gameplay stays faintly visible like CS:GO's wheel)
	_wheel.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.015, 0.02, 0.03, 0.55))

	var money := int(player.money) if is_instance_valid(player) else 0
	var team_col := CT_TINT
	var team_txt := "COUNTER-TERRORISTS"
	if is_instance_valid(player) and player.team != "CT":
		team_col = T_TINT
		team_txt = "TERRORISTS"
	_wheel.draw_string(font, Vector2(sz.x - 250.0, 46.0), "$ %d" % money,
		HORIZONTAL_ALIGNMENT_RIGHT, 230.0, 30, GREEN_MONEY)
	_wheel.draw_string(font, Vector2(sz.x - 250.0, 70.0), team_txt,
		HORIZONTAL_ALIGNMENT_RIGHT, 230.0, 14, team_col)
	var bt := float(RoundManager.buy_time_left)
	var status := "BUY TIME %d:%02d" % [int(bt / 60.0), int(bt) % 60]
	var status_col := TEXT_DIM
	if bt <= 0.0:
		status = "BUY TIME EXPIRED"
		status_col = RED_PRICE
	_wheel.draw_string(font, Vector2(28.0, 46.0), status, HORIZONTAL_ALIGNMENT_LEFT, 260.0, 16, status_col)

	var n := _entries.size()
	var r_out := minf(sz.x, sz.y) * 0.36
	var r_in := r_out * 0.40
	if n == 0:
		_wheel.draw_circle(c, r_in - 6.0, CENTER_BG)
		_wheel.draw_arc(c, r_in - 6.0, 0.0, TAU, 96, RING_BORDER, 1.5)
		_wheel.draw_string(font, c + Vector2(-90.0, 6.0), "Nothing to buy here",
			HORIZONTAL_ALIGNMENT_CENTER, 180.0, 16, TEXT_DIM)
		return

	var step := TAU / float(n)
	for i in range(n):
		var e: Dictionary = _entries[i]
		var a0 := -PI * 0.5 + float(i) * step
		var a1 := a0 + step
		var a_mid := (a0 + a1) * 0.5
		# Ring sector
		var poly := PackedVector2Array()
		var segs := 14
		for s2 in range(segs + 1):
			var ang := lerpf(a0, a1, float(s2) / float(segs))
			poly.append(c + Vector2(cos(ang), sin(ang)) * r_out)
		for s2 in range(segs, -1, -1):
			var ang := lerpf(a0, a1, float(s2) / float(segs))
			poly.append(c + Vector2(cos(ang), sin(ang)) * r_in)
		var hovered := i == _hover
		_wheel.draw_colored_polygon(poly, RING_HOVER if hovered else RING_BG)
		_wheel.draw_arc(c, r_out, a0, a1, 8, HOVER_BORDER if hovered else RING_BORDER, 2.0 if hovered else 1.0)
		_wheel.draw_arc(c, r_in, a0, a1, 8, HOVER_BORDER if hovered else RING_BORDER, 2.0 if hovered else 1.0)
		var radial := Vector2(cos(a0), sin(a0))
		_wheel.draw_line(c + radial * r_in, c + radial * r_out, HOVER_BORDER if hovered else RING_BORDER, 2.0 if hovered else 1.0)

		# Sector content
		var dir := Vector2(cos(a_mid), sin(a_mid))
		var mid := c + dir * ((r_in + r_out) * 0.5)
		var price := int(e["price"])
		var price_txt := ""
		var price_col := GREEN_MONEY
		if price >= 0:
			price_txt = "$%d" % price
			price_col = GREEN_MONEY if (is_instance_valid(player) and player.money >= price) else RED_PRICE
		if price == -2:
			# Root section tile: big name + item count
			_wheel.draw_string(font, mid + Vector2(-70.0, -6.0), String(e["name"]),
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, 17, TEXT_WHITE)
			_wheel.draw_string(font, mid + Vector2(-70.0, 16.0), String(e["desc"]),
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, 12, TEXT_DIM)
		else:
			# Item slot: weapon icon (or name for gear) + price
			var img_path := String(e["vgui"])
			var icon_rect := Rect2(mid + Vector2(-62.0, -34.0), Vector2(124.0, 46.0))
			if not img_path.is_empty():
				var tex := GameData.get_texture("res://assets/ui/vgui/%s.png" % img_path.to_lower())
				if tex != null:
					_wheel.draw_texture_rect(tex, icon_rect, false)
				else:
					_wheel.draw_string(font, mid + Vector2(-70.0, -8.0), String(e["name"]),
						HORIZONTAL_ALIGNMENT_CENTER, 140.0, 13, TEXT_WHITE)
			else:
				_wheel.draw_string(font, mid + Vector2(-72.0, -6.0), String(e["name"]),
					HORIZONTAL_ALIGNMENT_CENTER, 144.0, 13, TEXT_WHITE)
			_wheel.draw_string(font, mid + Vector2(-70.0, 26.0), price_txt,
				HORIZONTAL_ALIGNMENT_CENTER, 140.0, 14, price_col)
		# Hotkey badge near the inner rim
		var badge_pos := c + dir * (r_in + 22.0)
		_wheel.draw_string(font, badge_pos + Vector2(-12.0, 5.0), str(int(e["num"])),
			HORIZONTAL_ALIGNMENT_CENTER, 24.0, 14, ACCENT)

	# Centre disc
	_wheel.draw_circle(c, r_in - 8.0, CENTER_BG)
	_wheel.draw_arc(c, r_in - 8.0, 0.0, TAU, 96, RING_BORDER, 1.5)
	var title := "BUY MENU" if current_category == 0 else ""
	if current_category > 0:
		for rc in CATEGORIES:
			if int(rc[0]) == current_category:
				title = String(rc[1])
	_wheel.draw_string(font, c + Vector2(-110.0, -14.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, 220.0, 20, ACCENT)
	if _hover >= 0 and _hover < _entries.size():
		var he: Dictionary = _entries[_hover]
		_wheel.draw_string(font, c + Vector2(-110.0, 12.0), String(he["name"]),
			HORIZONTAL_ALIGNMENT_CENTER, 220.0, 15, TEXT_WHITE)
		var hprice := int(he["price"])
		if hprice >= 0:
			var ok := is_instance_valid(player) and player.money >= hprice
			_wheel.draw_string(font, c + Vector2(-110.0, 34.0), ("$%d" % hprice) + ("" if ok else "  (NO FUNDS)"),
				HORIZONTAL_ALIGNMENT_CENTER, 220.0, 13, GREEN_MONEY if ok else RED_PRICE)
		elif String(he["desc"]) != "":
			_wheel.draw_string(font, c + Vector2(-110.0, 34.0), String(he["desc"]),
				HORIZONTAL_ALIGNMENT_CENTER, 220.0, 12, TEXT_DIM)
	else:
		_wheel.draw_string(font, c + Vector2(-110.0, 14.0), "Select an item",
			HORIZONTAL_ALIGNMENT_CENTER, 220.0, 13, TEXT_DIM)

	# Hints
	var hints := "1-9  Select    ·    0 / ESC  Back    ·    B  Exit" if current_category > 0 \
		else "1-6  Select section    ·    B / ESC  Exit"
	_wheel.draw_string(font, Vector2(c.x - 260.0, sz.y - 22.0), hints,
		HORIZONTAL_ALIGNMENT_CENTER, 520.0, 14, TEXT_DIM)


# --- Catalogue ----------------------------------------------------------------

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
				"name": "Primary Ammo",
				"price": -1,
				"vgui": "",
				"desc": "Refills your primary weapon reserve.",
				"action": func(): _buy_ammo(1),
			})
			out.append({
				"id": "ammo2",
				"name": "Secondary Ammo",
				"price": -1,
				"vgui": "",
				"desc": "Refills your secondary weapon reserve.",
				"action": func(): _buy_ammo(2),
			})
	return out


## Turns the classic CS 1.5 info block ("Price\t: $650\nDescription\t: ...")
## into a one-line caption.
func _short_desc(raw: String) -> String:
	var flat := raw.replace("\t", " ").replace("\n", " ")
	var di := flat.find("Description")
	if di >= 0:
		flat = flat.substr(di + 11).lstrip(": ").strip_edges()
	flat = " ".join(flat.split(" ", false))
	if flat.length() > 62:
		flat = flat.substr(0, 62) + "…"
	return flat


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
