class_name BuyMenu
extends CanvasLayer
## CS:GO-style RADIAL buy menu, fully mouse-driven: hover a sector, left
## click to buy, right click / centre disc / wheel to go back, wheel-rotate
## to sweep the selection. Number keys still work. Animated open + pulsing
## hover glow, weapon-icon cards, price chips, big item preview in the
## centre disc. Same purchase backends, buy-zone/time and economy rules.

signal menu_closed()

const RING_BG := Color(0.055, 0.07, 0.095, 0.90)
const RING_BG2 := Color(0.085, 0.105, 0.14, 0.92)
const RING_HOVER := Color(0.16, 0.21, 0.29, 0.96)
const RING_HOVER2 := Color(0.23, 0.30, 0.40, 0.97)
const RING_BORDER := Color(0.55, 0.60, 0.68, 0.30)
const HOVER_BORDER := Color(0.95, 0.66, 0.16, 1.0)
const HOVER_GLOW := Color(0.95, 0.66, 0.16, 0.35)
const CENTER_BG := Color(0.03, 0.04, 0.055, 0.96)
const CENTER_BG2 := Color(0.05, 0.065, 0.09, 0.96)
const ACCENT := Color(0.95, 0.66, 0.16, 1.0)
const GREEN_MONEY := Color(0.44, 0.87, 0.42, 1.0)
const RED_PRICE := Color(0.95, 0.33, 0.29, 1.0)
const TEXT_WHITE := Color(0.95, 0.96, 0.98, 1.0)
const TEXT_DIM := Color(0.66, 0.71, 0.78, 0.95)
const SHADOW := Color(0.0, 0.0, 0.0, 0.75)
const CARD_BG := Color(0.02, 0.03, 0.045, 0.80)
const CHIP_BG := Color(0.04, 0.055, 0.075, 0.92)
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
var _hover_center: bool = false
var _last_status_sec: int = -1
var _hover_sound_cache: int = -1
var _time: float = 0.0
var _open_t: float = 1.0
var _deny_t: float = 0.0
var _deny_text: String = ""
var _mouse_pos: Vector2 = Vector2.ZERO
var _icon_cache: Dictionary = {}


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
	_open_t = 0.0
	_time = 0.0
	if is_instance_valid(player):
		player.ui_blocking_input = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioManager.play_ui("launch_upmenu1.wav")
	_show_category(0)
	# Start hover wherever the cursor already is so the wheel reacts at once.
	_mouse_pos = get_viewport().get_mouse_position()
	_update_hover(_mouse_pos)


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


func _process(delta: float) -> void:
	if not is_open:
		return
	_time += delta
	if _open_t < 1.0:
		_open_t = minf(1.0, _open_t + delta * 6.0)
		_wheel.modulate.a = pow(_open_t, 0.6)
	if _deny_t > 0.0:
		_deny_t = maxf(0.0, _deny_t - delta)
	var sec := int(ceilf(float(RoundManager.buy_time_left)))
	if sec != _last_status_sec:
		_last_status_sec = sec
	_wheel.queue_redraw()


func open_category(cat: int) -> void:
	AudioManager.play_ui("launch_select1.wav")
	_show_category(cat)
	# keep hover in sync right after the entries change
	_update_hover(_mouse_pos)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position
		_update_hover(_mouse_pos)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		get_viewport().set_input_as_handled()
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if _hover >= 0:
					_activate(_hover)
				elif _hover_center:
					_go_back()
			MOUSE_BUTTON_RIGHT:
				_go_back()
			MOUSE_BUTTON_WHEEL_UP:
				_rotate_hover(-1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_rotate_hover(1)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE or kc == KEY_0 or kc == KEY_B:
			get_viewport().set_input_as_handled()
			if current_category > 0 and kc != KEY_B:
				_show_category(0)
				_update_hover(_mouse_pos)
			else:
				close_menu()
			return
		if kc >= KEY_1 and kc <= KEY_9:
			var num := kc - KEY_0
			if num >= 1 and num <= _entries.size():
				get_viewport().set_input_as_handled()
				_activate(num - 1)


func _go_back() -> void:
	if current_category > 0:
		AudioManager.play_ui("launch_dnmenu1.wav")
		_show_category(0)
		_update_hover(_mouse_pos)
	else:
		close_menu()


func _rotate_hover(dir: int) -> void:
	var n := _entries.size()
	if n <= 0:
		return
	if _hover < 0:
		_hover = 0 if dir > 0 else n - 1
	else:
		_hover = (_hover + dir + n) % n
	_hover_center = false
	_hover_sound_cache = _hover
	AudioManager.play_ui("launch_glow1.wav")
	_wheel.queue_redraw()


# --- Wheel state --------------------------------------------------------------

func _show_category(cat: int) -> void:
	current_category = cat
	_entries.clear()
	_hover = -1
	_hover_center = false
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
	var new_center := false
	var n := _entries.size()
	if n > 0 and _wheel != null:
		var c := _wheel.size * 0.5
		var r_out := _ring_out()
		var r_in := r_out * 0.40
		var rel := mouse_pos - c
		var r := rel.length()
		if r <= r_in - 4.0:
			new_center = true
		elif r <= r_out + 24.0:
			var ang := atan2(rel.y, rel.x) + PI * 0.5
			if ang < 0.0:
				ang += TAU
			new_hover = int(floor(ang / (TAU / float(n)))) % n
	var changed := new_hover != _hover or new_center != _hover_center
	_hover = new_hover
	_hover_center = new_center
	if changed:
		if _hover >= 0 and _hover_sound_cache != _hover:
			_hover_sound_cache = _hover
			AudioManager.play_ui("launch_glow1.wav")
		_wheel.queue_redraw()


func _activate(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	(_entries[idx]["action"] as Callable).call()
	# purchases rebuild the list; re-anchor hover to the cursor
	_update_hover(_mouse_pos)


# --- Drawing ------------------------------------------------------------------

func _ring_out() -> float:
	return minf(_wheel.size.x, _wheel.size.y) * 0.40


func _tex_for(vgui: String) -> Texture2D:
	if vgui.is_empty():
		return null
	if not _icon_cache.has(vgui):
		_icon_cache[vgui] = GameData.get_texture("res://assets/ui/vgui/%s.png" % vgui.to_lower())
	return _icon_cache[vgui] as Texture2D


func _text(pos: Vector2, txt: String, size: int, col: Color, width: float = 0.0,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, shadow: bool = true) -> void:
	var font := _wheel.get_theme_default_font()
	if shadow:
		_wheel.draw_string(font, pos + Vector2(1.0, 1.5), txt, align, width, size, SHADOW)
	_wheel.draw_string(font, pos, txt, align, width, size, col)


func _chip(rect: Rect2, bg: Color, txt: String, size: int, col: Color) -> void:
	_wheel.draw_rect(rect, bg, true)
	_wheel.draw_rect(rect, Color(col.r, col.g, col.b, 0.55), false, 1.0)
	_text(rect.position + Vector2(0.0, rect.size.y - 5.0), txt, size, col,
		rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, false)


func _sector_poly(a0: float, a1: float, r0: float, r1: float, c: Vector2) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var segs := 16
	for s2 in range(segs + 1):
		var ang := lerpf(a0, a1, float(s2) / float(segs))
		poly.append(c + Vector2(cos(ang), sin(ang)) * r1)
	for s2 in range(segs, -1, -1):
		var ang := lerpf(a0, a1, float(s2) / float(segs))
		poly.append(c + Vector2(cos(ang), sin(ang)) * r0)
	return poly


func _draw_wheel() -> void:
	var sz := _wheel.size
	var c := sz * 0.5

	# Dim + vignette (gameplay stays faintly visible like CS:GO's wheel)
	_wheel.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.012, 0.016, 0.026, 0.62))
	var vr := maxf(sz.x, sz.y) * 0.62
	for i in range(5):
		var rr := vr - float(i) * vr * 0.09
		_wheel.draw_arc(c, rr, 0.0, TAU, 48, Color(0.0, 0.0, 0.0, 0.05), 26.0)

	# HUD chips: buy time (top-left), money + team (top-right)
	var bt := float(RoundManager.buy_time_left)
	var status := "BUY TIME  %d:%02d" % [int(bt / 60.0), int(bt) % 60]
	var status_col := TEXT_DIM
	if bt <= 0.0:
		status = "BUY TIME EXPIRED"
		status_col = RED_PRICE
	_chip(Rect2(Vector2(22.0, 24.0), Vector2(170.0, 30.0)), CHIP_BG, status, 14, status_col)

	var money := int(player.money) if is_instance_valid(player) else 0
	var team_col := CT_TINT
	var team_txt := "COUNTER-TERRORISTS"
	if is_instance_valid(player) and player.team != "CT":
		team_col = T_TINT
		team_txt = "TERRORISTS"
	_chip(Rect2(Vector2(sz.x - 216.0, 24.0), Vector2(194.0, 30.0)), CHIP_BG,
		"$ %d" % money, 17, GREEN_MONEY)
	_chip(Rect2(Vector2(sz.x - 216.0, 60.0), Vector2(194.0, 24.0)), CHIP_BG, team_txt, 12, team_col)

	# Section title pill (top-centre)
	var title := "BUY MENU" if current_category == 0 else ""
	if current_category > 0:
		for rc in CATEGORIES:
			if int(rc[0]) == current_category:
				title = String(rc[1])
	var tw := 240.0
	_chip(Rect2(c - Vector2(tw * 0.5, 22.0), Vector2(tw, 32.0)), Color(0.04, 0.05, 0.07, 0.94),
		title, 18, ACCENT)

	var n := _entries.size()
	var r_out := _ring_out()
	var r_in := r_out * 0.40
	if n == 0:
		_wheel.draw_circle(c, r_in - 6.0, CENTER_BG)
		_wheel.draw_arc(c, r_in - 6.0, 0.0, TAU, 96, RING_BORDER, 1.5)
		_text(c + Vector2(-110.0, 6.0), "Nothing to buy here", 16, TEXT_DIM, 220.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		_draw_bottom_hints(c, sz)
		return

	var step := TAU / float(n)
	var pulse := 0.62 + 0.38 * sin(_time * 5.2)

	# subtle wheel backdrop ring
	_wheel.draw_arc(c, r_out + 10.0, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.45), 6.0)
	_wheel.draw_arc(c, r_in - 10.0, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.35), 5.0)

	for i in range(n):
		var e: Dictionary = _entries[i]
		var a0 := -PI * 0.5 + float(i) * step
		var a1 := a0 + step
		var a_mid := (a0 + a1) * 0.5
		var hovered := i == _hover

		# sector body: two-tone band for depth
		var poly := _sector_poly(a0 + 0.004, a1 - 0.004, r_in, r_out, c)
		_wheel.draw_colored_polygon(poly, RING_HOVER2 if hovered else RING_BG2)
		var poly_in := _sector_poly(a0 + 0.004, a1 - 0.004, r_in, (r_in + r_out) * 0.5, c)
		_wheel.draw_colored_polygon(poly_in, RING_HOVER if hovered else RING_BG)

		# borders + separators
		_wheel.draw_arc(c, r_out, a0 + 0.004, a1 - 0.004, 10,
			HOVER_BORDER if hovered else RING_BORDER, 2.5 if hovered else 1.0)
		_wheel.draw_arc(c, r_in, a0 + 0.004, a1 - 0.004, 10,
			HOVER_BORDER if hovered else RING_BORDER, 2.5 if hovered else 1.0)
		var radial := Vector2(cos(a0), sin(a0))
		_wheel.draw_line(c + radial * r_in, c + radial * r_out,
			HOVER_BORDER if hovered else RING_BORDER, 2.0 if hovered else 1.0)
		if hovered:
			_wheel.draw_arc(c, (r_in + r_out) * 0.5, a0 + 0.02, a1 - 0.02, 10,
				Color(HOVER_GLOW.r, HOVER_GLOW.g, HOVER_GLOW.b, 0.35 * pulse), 3.0)

		# sector content
		var dir := Vector2(cos(a_mid), sin(a_mid))
		var mid := c + dir * ((r_in + r_out) * 0.5)
		var price := int(e["price"])
		var price_txt := ""
		var price_col := GREEN_MONEY
		if price >= 0:
			price_txt = "$%d" % price
			price_col = GREEN_MONEY if (is_instance_valid(player) and player.money >= price) else RED_PRICE

		if price == -2:
			# root section tile: name + item count
			var name_off := Vector2(-80.0, -4.0) if hovered else Vector2(-80.0, -2.0)
			_text(mid + name_off, String(e["name"]), 18 if hovered else 17, TEXT_WHITE, 160.0,
				HORIZONTAL_ALIGNMENT_CENTER)
			_text(mid + Vector2(-80.0, 20.0), String(e["desc"]), 12, TEXT_DIM, 160.0,
				HORIZONTAL_ALIGNMENT_CENTER)
		else:
			# item slot: icon card + name + price chip
			var icon_sz := Vector2(132.0, 50.0) if hovered else Vector2(124.0, 46.0)
			var icon_rect := Rect2(mid - icon_sz * 0.5 + Vector2(0.0, -14.0), icon_sz)
			var card := icon_rect.grow(7.0)
			_wheel.draw_rect(card, Color(CARD_BG.r, CARD_BG.g, CARD_BG.b,
				0.92 if hovered else 0.72), true)
			if hovered:
				_wheel.draw_rect(card, Color(HOVER_BORDER.r, HOVER_BORDER.g, HOVER_BORDER.b, 0.85),
					false, 1.5)
			var tex := _tex_for(String(e["vgui"]))
			if tex != null:
				_wheel.draw_texture_rect(tex, icon_rect, false,
					Color(1.0, 1.0, 1.0, 1.0) if hovered else Color(0.9, 0.92, 0.95, 0.96))
			else:
				_text(icon_rect.position + Vector2(4.0, icon_rect.size.y - 14.0), String(e["name"]),
					13, TEXT_WHITE, icon_rect.size.x - 8.0, HORIZONTAL_ALIGNMENT_CENTER)
			_text(mid + Vector2(-80.0, 36.0), String(e["name"]), 12,
				ACCENT if hovered else TEXT_WHITE, 160.0, HORIZONTAL_ALIGNMENT_CENTER)
			if price >= 0:
				_chip(Rect2(mid + Vector2(-38.0, 44.0), Vector2(76.0, 21.0)),
					Color(CHIP_BG.r, CHIP_BG.g, CHIP_BG.b, 0.95), price_txt, 13, price_col)

		# hotkey badge on the inner rim
		var badge_pos := c + dir * (r_in + 20.0)
		_wheel.draw_circle(badge_pos, 11.0, Color(0.02, 0.03, 0.05, 0.9))
		_wheel.draw_arc(badge_pos, 11.0, 0.0, TAU, 24,
			HOVER_BORDER if hovered else RING_BORDER, 1.4)
		_text(badge_pos + Vector2(-10.0, 5.0), str(int(e["num"])), 13,
			ACCENT if hovered else TEXT_DIM, 20.0, HORIZONTAL_ALIGNMENT_CENTER, false)

	# centre disc
	var center_r := r_in - 10.0
	_wheel.draw_circle(c, center_r + 4.0, Color(0.0, 0.0, 0.0, 0.55))
	_wheel.draw_circle(c, center_r, CENTER_BG)
	_wheel.draw_circle(c + Vector2(0.0, -center_r * 0.22), center_r * 0.62, CENTER_BG2)
	_wheel.draw_arc(c, center_r, 0.0, TAU, 96,
		HOVER_BORDER if _hover_center else RING_BORDER, 2.5 if _hover_center else 1.5)
	if _hover_center:
		_wheel.draw_arc(c, center_r + 3.0, 0.0, TAU, 96,
			Color(HOVER_GLOW.r, HOVER_GLOW.g, HOVER_GLOW.b, 0.5 * pulse), 3.0)

	if _deny_t > 0.0:
		_text(c + Vector2(-130.0, -6.0), _deny_text, 17, RED_PRICE, 260.0,
			HORIZONTAL_ALIGNMENT_CENTER)
	elif _hover >= 0 and _hover < _entries.size():
		var he: Dictionary = _entries[_hover]
		# big preview icon
		var htex := _tex_for(String(he["vgui"]))
		if htex != null:
			var pr := Rect2(c + Vector2(-78.0, -78.0), Vector2(156.0, 58.0))
			_wheel.draw_texture_rect(htex, pr, false, Color(1.0, 1.0, 1.0, 0.95))
		_text(c + Vector2(-130.0, 6.0), String(he["name"]), 17, TEXT_WHITE, 260.0,
			HORIZONTAL_ALIGNMENT_CENTER)
		var hprice := int(he["price"])
		if hprice >= 0:
			var ok := is_instance_valid(player) and player.money >= hprice
			_chip(Rect2(c + Vector2(-62.0, 16.0), Vector2(124.0, 24.0)), CHIP_BG,
				("$%d" % hprice) + ("" if ok else "  NO FUNDS"), 14,
				GREEN_MONEY if ok else RED_PRICE)
		elif String(he["desc"]) != "":
			_text(c + Vector2(-130.0, 32.0), String(he["desc"]), 12, TEXT_DIM, 260.0,
				HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_text(c + Vector2(-130.0, -20.0), title, 21, ACCENT, 260.0, HORIZONTAL_ALIGNMENT_CENTER)
		_wheel.draw_rect(Rect2(c + Vector2(-40.0, -8.0), Vector2(80.0, 2.0)), ACCENT, true)
		if current_category == 0:
			_text(c + Vector2(-130.0, 22.0), "Move the mouse over a section", 13, TEXT_DIM, 260.0,
				HORIZONTAL_ALIGNMENT_CENTER)
		else:
			_text(c + Vector2(-130.0, 22.0), "Move the mouse over an item", 13, TEXT_DIM, 260.0,
				HORIZONTAL_ALIGNMENT_CENTER)

	# back affordance inside the disc when nested
	if current_category > 0 and _hover < 0:
		_text(c + Vector2(-70.0, center_r - 26.0), "◄  BACK", 13, TEXT_DIM, 140.0,
			HORIZONTAL_ALIGNMENT_CENTER)

	_draw_bottom_hints(c, sz)


func _draw_bottom_hints(c: Vector2, sz: Vector2) -> void:
	var hint := "Left-click  Buy    ·    Right-click / centre / wheel  Back    ·    B  Exit" \
		if current_category > 0 else \
		"Left-click  Select section    ·    Right-click  Exit    ·    B / ESC  Exit"
	var bar := Rect2(Vector2(c.x - 300.0, sz.y - 44.0), Vector2(600.0, 30.0))
	_wheel.draw_rect(bar, Color(0.03, 0.04, 0.06, 0.92), true)
	_wheel.draw_rect(bar, Color(0.55, 0.60, 0.68, 0.22), false, 1.0)
	_text(bar.position + Vector2(0.0, 21.0), hint, 14, TEXT_DIM, bar.size.x,
		HORIZONTAL_ALIGNMENT_CENTER, false)


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
		_flash_deny(wid)


func _purchase_eq(eid: String) -> void:
	if is_instance_valid(player) and player.buy_equipment(eid):
		AudioManager.play_ui("launch_select2.wav")
		_show_category(current_category)
	else:
		_denieq(eid)


func _buy_ammo(sl: int) -> void:
	if is_instance_valid(player):
		player.buy_ammo_for_slot(sl, true)
		AudioManager.play_ui("launch_select2.wav")
	_show_category(current_category)


func _denieq(eid: String) -> void:
	var price := 0
	if GameData.equipment.has(eid):
		price = int((GameData.equipment[eid] as Dictionary).get("price", 0))
	_set_deny(price)


func _flash_deny(wid: String) -> void:
	var price := 0
	if GameData.weapons.has(wid):
		price = int((GameData.weapons[wid] as Dictionary).get("price", 0))
	_set_deny(price)


func _set_deny(price: int) -> void:
	AudioManager.play_ui("launch_deny2.wav")
	_deny_t = 1.4
	if is_instance_valid(player) and price > 0 and player.money < price:
		_deny_text = "NOT ENOUGH MONEY"
	else:
		_deny_text = "CAN'T BUY NOW"
	_wheel.queue_redraw()
