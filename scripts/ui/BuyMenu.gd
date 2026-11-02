class_name BuyMenu
extends CanvasLayer
## CS:GO-style buy screen (task 23):
##   LEFT   - radial wheel with white weapon silhouettes, gold centre emblem
##   CENTRE - live 3D preview of your own character holding the hovered weapon
##   RIGHT  - weapon card: name + rarity bar, price, ammo, CS:GO stat bars
##            (with green/red difference against the weapon you already own)
##   TOP    - money, "Buy Time Remaining", team
##   BOTTOM - current loadout strip + control hints
## Mouse: hover a sector, LEFT click buys / opens, RIGHT click or the centre
## emblem goes back, the wheel rotates the selection. Number keys still work.

signal menu_closed()

const WHEEL_BG := Color(0.055, 0.062, 0.075, 0.84)
const WHEEL_BG_ALT := Color(0.072, 0.080, 0.095, 0.84)
const WHEEL_HOVER := Color(0.30, 0.33, 0.38, 0.90)
const WHEEL_LINE := Color(0.62, 0.66, 0.72, 0.22)
const GOLD := Color(0.86, 0.70, 0.33, 1.0)
const GOLD_DARK := Color(0.42, 0.33, 0.14, 1.0)
const ACCENT := Color(0.95, 0.70, 0.22, 1.0)
const GREEN_MONEY := Color(0.47, 0.86, 0.38, 1.0)
const RED_PRICE := Color(0.93, 0.33, 0.30, 1.0)
const TEXT_WHITE := Color(0.94, 0.95, 0.97, 1.0)
const TEXT_DIM := Color(0.64, 0.68, 0.74, 0.95)
const TEXT_FAINT := Color(0.50, 0.54, 0.60, 0.85)
const SHADOW := Color(0.0, 0.0, 0.0, 0.75)
const PANEL_BG := Color(0.035, 0.042, 0.054, 0.86)
const PANEL_LINE := Color(0.60, 0.65, 0.72, 0.16)
const BAR_BG := Color(0.17, 0.19, 0.22, 0.95)
const BAR_FILL := Color(0.86, 0.88, 0.91, 1.0)
const CT_TINT := Color(0.40, 0.62, 0.92, 1.0)
const T_TINT := Color(0.90, 0.66, 0.26, 1.0)

## [id, title, icon vgui, rarity colour]
const CATEGORIES: Array = [
	[1, "PISTOLS", "640_deagle", Color(0.37, 0.60, 0.85, 1.0)],
	[2, "HEAVY", "640_m249", Color(0.55, 0.40, 0.88, 1.0)],
	[3, "SMGS", "640_mp5", Color(0.29, 0.41, 0.95, 1.0)],
	[4, "RIFLES", "640_ak47", Color(0.80, 0.33, 0.85, 1.0)],
	[5, "EQUIPMENT", "", Color(0.68, 0.72, 0.78, 1.0)],
	[6, "GRENADES", "640_hegrenade", Color(0.45, 0.72, 0.42, 1.0)],
]

const STAT_NAMES: Array = ["FIREPOWER", "RATE OF FIRE", "ACCURACY", "RECOIL CONTROL", "MOBILITY", "ARMOR PENETRATION"]

var player: PlayerController = null
var is_open: bool = false
var current_category: int = 0  # 0 = sections, 1..6 = items

var _bg: Control = null
var _wheel: Control = null
var _pv_container: SubViewportContainer = null
var _pv_viewport: SubViewport = null
var _pv_pivot: Node3D = null
var _pv_camera: Camera3D = null
var _pv_model: Node3D = null
var _pv_anim: AnimationPlayer = null
var _pv_skel: Skeleton3D = null
var _pv_hand: BoneAttachment3D = null
var _pv_upper_mask: PackedByteArray = PackedByteArray()
var _pv_tracks: Dictionary = {}  # anim name -> [Animation, [[track, bone, is_pos], ...]]
var _pv_anim_t: float = 0.0
var _pv_class: String = ""
var _pv_weapon: String = "?"
var _pv_lower_name: String = ""
var _pv_upper_name: String = ""

var _entries: Array = []  # {num, id, kind, name, price, vgui, desc, owned, action}
var _hover: int = -1
var _hover_center: bool = false
var _sel: int = -1  # last hovered entry: drives preview + stats card
var _hover_amt: PackedFloat32Array = PackedFloat32Array()
var _time: float = 0.0
var _open_t: float = 1.0
var _toast_t: float = 0.0
var _toast_text: String = ""
var _toast_col: Color = Color.WHITE
var _mouse_pos: Vector2 = Vector2.ZERO
var _icon_cache: Dictionary = {}
var _sil_cache: Dictionary = {}
var _stat_max: Dictionary = {}
var _warm_queue: Array = []


func _ready() -> void:
	layer = 12
	visible = false

	_bg = Control.new()
	_bg.name = "BuyBackground"
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(_draw_bg)
	add_child(_bg)

	_build_preview_viewport()

	_wheel = Control.new()
	_wheel.name = "BuyWheel"
	_wheel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wheel.mouse_filter = Control.MOUSE_FILTER_STOP
	_wheel.draw.connect(_draw_fg)
	_wheel.gui_input.connect(_on_wheel_gui_input)
	add_child(_wheel)

	_compute_stat_ranges()
	# pre-build the white silhouettes a few per frame so opening never hitches
	for rc in CATEGORIES:
		_warm_queue.append(String(rc[2]))
	for wid in GameData.weapons.keys():
		_warm_queue.append(String((GameData.weapons[wid] as Dictionary).get("vgui", "")))


# --- Open / close ---------------------------------------------------------------

func open_menu(p: PlayerController) -> void:
	player = p
	if not is_instance_valid(player) or not player.can_use_buy_menu():
		RoundManager.center_message.emit("You are not in a buy zone or buy time has expired!", 1.8)
		return
	is_open = true
	visible = true
	_open_t = 0.0
	_time = 0.0
	_toast_t = 0.0
	player.ui_blocking_input = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioManager.play_ui("launch_upmenu1.wav")
	_pv_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_ensure_preview_model()
	_show_category(0)
	_mouse_pos = get_viewport().get_mouse_position()
	_update_hover(_mouse_pos)
	_refresh_preview_weapon()


func close_menu() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	_pv_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(player):
		player.ui_blocking_input = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	AudioManager.play_ui("launch_dnmenu1.wav")
	menu_closed.emit()


func open_category(cat: int) -> void:
	AudioManager.play_ui("launch_select1.wav")
	_show_category(cat)
	_update_hover(_mouse_pos)
	_refresh_preview_weapon()


func _process(delta: float) -> void:
	if not _warm_queue.is_empty():
		var vg := String(_warm_queue.pop_back())
		if not vg.is_empty():
			_silhouette(vg)
	if not is_open:
		return
	_time += delta
	if _open_t < 1.0:
		_open_t = minf(1.0, _open_t + delta * 5.0)
	if _toast_t > 0.0:
		_toast_t = maxf(0.0, _toast_t - delta)
	# smooth per-sector hover pop
	var k := clampf(delta * 14.0, 0.0, 1.0)
	for i in range(_hover_amt.size()):
		var target := 1.0 if i == _hover else 0.0
		_hover_amt[i] = lerpf(_hover_amt[i], target, k)
	_layout_preview()
	_animate_preview(delta)
	_bg.queue_redraw()
	_wheel.queue_redraw()


# --- Input ------------------------------------------------------------------------

func _on_wheel_gui_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		_mouse_pos = (event as InputEventMouseMotion).position
		_update_hover(_mouse_pos)
		_wheel.accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_wheel.accept_event()
		if not mb.pressed:
			return
		_mouse_pos = mb.position
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_update_hover(_mouse_pos)
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


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = (event as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE or kc == KEY_0 or kc == KEY_B:
			get_viewport().set_input_as_handled()
			if current_category > 0 and kc != KEY_B:
				_go_back()
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
		_refresh_preview_weapon()
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
	_sel = _hover
	AudioManager.play_ui("launch_glow1.wav")
	_refresh_preview_weapon()


func _activate(idx: int) -> void:
	if idx < 0 or idx >= _entries.size():
		return
	(_entries[idx]["action"] as Callable).call()
	_update_hover(_mouse_pos)
	_refresh_preview_weapon()


# --- Layout helpers ---------------------------------------------------------------

func _screen() -> Vector2:
	return _wheel.size if _wheel != null else Vector2(1280.0, 720.0)


func _wheel_center() -> Vector2:
	var sz := _screen()
	return Vector2(sz.x * 0.235, sz.y * 0.50)


func _ring_out() -> float:
	var sz := _screen()
	return minf(sz.y * 0.335, sz.x * 0.205)


func _ring_in() -> float:
	return _ring_out() * 0.33


func _preview_rect() -> Rect2:
	var sz := _screen()
	return Rect2(Vector2(sz.x * 0.445, sz.y * 0.09), Vector2(sz.x * 0.25, sz.y * 0.76))


func _panel_rect() -> Rect2:
	var sz := _screen()
	return Rect2(Vector2(sz.x * 0.705, sz.y * 0.30), Vector2(sz.x * 0.27, sz.y * 0.52))


# --- Wheel state -------------------------------------------------------------------

func _show_category(cat: int) -> void:
	current_category = cat
	_entries.clear()
	_hover = -1
	_hover_center = false
	_sel = -1
	if cat == 0:
		for rc in CATEGORIES:
			var cid := int(rc[0])
			_entries.append({
				"num": cid,
				"id": "",
				"kind": "section",
				"name": String(rc[1]),
				"price": -2,
				"vgui": String(rc[2]),
				"desc": "%d ITEMS" % _category_specs(cid).size(),
				"owned": false,
				"action": func(): open_category(cid),
			})
	else:
		var specs := _category_specs(cat)
		for i in range(specs.size()):
			var e: Dictionary = specs[i]
			e["num"] = i + 1
			_entries.append(e)
	_hover_amt.resize(_entries.size())
	_hover_amt.fill(0.0)


func _update_hover(mouse_pos: Vector2) -> void:
	var new_hover := -1
	var new_center := false
	var n := _entries.size()
	if n > 0 and _wheel != null:
		var rel := mouse_pos - _wheel_center()
		var r := rel.length()
		if r <= _ring_in() - 2.0:
			new_center = true
		elif r <= _ring_out() + 34.0:
			var ang := atan2(rel.y, rel.x) + PI * 0.5
			if ang < 0.0:
				ang += TAU
			new_hover = int(floor(ang / (TAU / float(n)))) % n
	var changed := new_hover != _hover or new_center != _hover_center
	_hover = new_hover
	_hover_center = new_center
	if changed and _hover >= 0:
		AudioManager.play_ui("launch_glow1.wav")
		if _sel != _hover:
			_sel = _hover
			_refresh_preview_weapon()


# --- Icons ---------------------------------------------------------------------------

func _tex_for(vgui: String) -> Texture2D:
	if vgui.is_empty():
		return null
	if not _icon_cache.has(vgui):
		_icon_cache[vgui] = GameData.get_texture("res://assets/ui/vgui/%s.png" % vgui.to_lower())
	return _icon_cache[vgui] as Texture2D


## White silhouette of a VGUI icon, cropped to its used rect (CS:GO look).
func _silhouette(vgui: String) -> Texture2D:
	if vgui.is_empty():
		return null
	if _sil_cache.has(vgui):
		return _sil_cache[vgui] as Texture2D
	var src := _tex_for(vgui)
	var out: Texture2D = null
	if src != null:
		var img := src.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			var used := img.get_used_rect()
			if used.size.x > 2 and used.size.y > 2:
				img = img.get_region(used)
			var data := img.get_data()
			var nbytes := data.size()
			# brightest opaque pixel -> normalise so the icon keeps its engraved detail
			var max_l := 1
			var i := 0
			while i + 3 < nbytes:
				if data[i + 3] > 128:
					max_l = maxi(max_l, int(float(data[i] * 3 + data[i + 1] * 6 + data[i + 2]) * 0.1))
				i += 4
			i = 0
			while i + 3 < nbytes:
				var a := data[i + 3]
				var lum := float(data[i] * 3 + data[i + 1] * 6 + data[i + 2]) / 10.0
				var v := int(255.0 * (1.0 - (1.0 - clampf(lum / float(max_l), 0.0, 1.0)) * 0.42))
				data[i] = v
				data[i + 1] = v
				data[i + 2] = v
				if a < 40:
					data[i + 3] = 0  # drop the faint grey matte around the CS 1.5 icons
				i += 4
			var white := Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
			out = ImageTexture.create_from_image(white)
	_sil_cache[vgui] = out
	return out


## Fits a texture into a box keeping its aspect ratio.
func _fit_rect(tex: Texture2D, box: Rect2) -> Rect2:
	var ts := Vector2(tex.get_width(), tex.get_height())
	if ts.x <= 0.0 or ts.y <= 0.0:
		return box
	var s := minf(box.size.x / ts.x, box.size.y / ts.y)
	var dsz := ts * s
	return Rect2(box.position + (box.size - dsz) * 0.5, dsz)


## Vector glyphs for gear that has no VGUI icon.
func _draw_glyph(ci: Control, kind: String, box: Rect2, col: Color) -> void:
	var c := box.get_center()
	var h := minf(box.size.x * 0.5, box.size.y)
	match kind:
		"kevlar", "kevlar_helmet":
			var w := h * 0.62
			var pts := PackedVector2Array([
				c + Vector2(-w * 0.55, -h * 0.48), c + Vector2(-w * 0.18, -h * 0.40),
				c + Vector2(0.0, -h * 0.28), c + Vector2(w * 0.18, -h * 0.40),
				c + Vector2(w * 0.55, -h * 0.48), c + Vector2(w * 0.62, h * 0.30),
				c + Vector2(0.0, h * 0.50), c + Vector2(-w * 0.62, h * 0.30),
			])
			if kind == "kevlar_helmet":
				var off := Vector2(-w * 0.55, 0.0)
				for i in range(pts.size()):
					pts[i] += off
			ci.draw_colored_polygon(pts, col)
			if kind == "kevlar_helmet":
				var hc := c + Vector2(w * 0.70, h * 0.05)
				ci.draw_circle(hc, h * 0.36, col)
				ci.draw_rect(Rect2(hc + Vector2(-h * 0.46, h * 0.02), Vector2(h * 0.92, h * 0.12)), col)
		"defuser":
			ci.draw_rect(Rect2(c + Vector2(-h * 0.70, -h * 0.30), Vector2(h * 1.0, h * 0.60)), col)
			ci.draw_line(c + Vector2(h * 0.30, -h * 0.10), c + Vector2(h * 0.95, -h * 0.40), col, 3.0)
			ci.draw_line(c + Vector2(h * 0.30, h * 0.10), c + Vector2(h * 0.95, h * 0.40), col, 3.0)
		"nightvision":
			ci.draw_circle(c + Vector2(-h * 0.40, 0.0), h * 0.30, col)
			ci.draw_circle(c + Vector2(h * 0.40, 0.0), h * 0.30, col)
			ci.draw_rect(Rect2(c + Vector2(-h * 0.40, -h * 0.12), Vector2(h * 0.80, h * 0.24)), col)
		_:
			# ammo: three cartridges
			for i in range(3):
				var x := c.x + (float(i) - 1.0) * h * 0.36
				ci.draw_rect(Rect2(Vector2(x - h * 0.11, c.y - h * 0.20), Vector2(h * 0.22, h * 0.62)), col)
				ci.draw_circle(Vector2(x, c.y - h * 0.20), h * 0.11, col)


func _draw_entry_icon(ci: Control, e: Dictionary, box: Rect2, col: Color) -> void:
	var sil := _silhouette(String(e["vgui"]))
	if sil != null:
		ci.draw_texture_rect(sil, _fit_rect(sil, box), false, col)
	elif String(e["kind"]) == "section":
		_draw_glyph(ci, "kevlar_helmet", box, col)
	else:
		_draw_glyph(ci, String(e["id"]), box, col)


# --- Text helpers ---------------------------------------------------------------------

func _text(ci: Control, pos: Vector2, txt: String, fs: int, col: Color, width: float = -1.0,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, shadow: bool = true) -> void:
	var font := ci.get_theme_default_font()
	if shadow:
		ci.draw_string(font, pos + Vector2(1.0, 1.5), txt, align, width, fs, SHADOW)
	ci.draw_string(font, pos, txt, align, width, fs, col)


func _sector_poly(a0: float, a1: float, r0: float, r1: float, c: Vector2) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var segs := 20
	for s2 in range(segs + 1):
		var ang := lerpf(a0, a1, float(s2) / float(segs))
		poly.append(c + Vector2(cos(ang), sin(ang)) * r1)
	for s2 in range(segs, -1, -1):
		var ang := lerpf(a0, a1, float(s2) / float(segs))
		poly.append(c + Vector2(cos(ang), sin(ang)) * r0)
	return poly


# --- Drawing: background layer (below the 3D preview) ------------------------------------

func _draw_bg() -> void:
	var sz := _bg.size
	var fade := _ease_open()
	_bg.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.010, 0.013, 0.020, 0.66 * fade))
	# soft vignette
	var c := sz * 0.5
	var vr := maxf(sz.x, sz.y) * 0.60
	for i in range(6):
		var rr := vr - float(i) * vr * 0.08
		_bg.draw_arc(c, rr, 0.0, TAU, 64, Color(0.0, 0.0, 0.0, 0.05 * fade), 30.0)

	# top bar
	_bg.draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, 54.0)), Color(0.02, 0.025, 0.035, 0.78 * fade))
	_bg.draw_line(Vector2(0.0, 54.0), Vector2(sz.x, 54.0), PANEL_LINE, 1.0)

	# preview stage: floor glow + ellipse shadow under the character
	var pr := _preview_rect()
	var floor_c := Vector2(pr.get_center().x, pr.position.y + pr.size.y * 0.885)
	for i in range(8):
		var t := float(i) / 7.0
		var rx := pr.size.x * (0.46 - t * 0.30)
		_draw_ellipse(_bg, floor_c, rx, rx * 0.16, Color(0.30, 0.34, 0.40, 0.035 * fade))
	_draw_ellipse(_bg, floor_c, pr.size.x * 0.20, pr.size.x * 0.035, Color(0.0, 0.0, 0.0, 0.45 * fade))

	# stats panel
	var pn := _panel_rect()
	_bg.draw_rect(pn, Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, PANEL_BG.a * fade))
	_bg.draw_rect(pn, PANEL_LINE, false, 1.0)

	# bottom loadout strip
	_bg.draw_rect(Rect2(Vector2(0.0, sz.y - 92.0), Vector2(sz.x, 92.0)), Color(0.02, 0.025, 0.035, 0.74 * fade))
	_bg.draw_line(Vector2(0.0, sz.y - 92.0), Vector2(sz.x, sz.y - 92.0), PANEL_LINE, 1.0)


func _draw_ellipse(ci: Control, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in range(40):
		var a := TAU * float(i) / 40.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


func _ease_open() -> float:
	return 1.0 - pow(1.0 - _open_t, 3.0)


# --- Drawing: foreground (wheel, header, stats, loadout) ------------------------------------

func _draw_fg() -> void:
	var sz := _wheel.size
	_draw_header(sz)
	_draw_wheel_ring()
	_draw_stats_panel()
	_draw_loadout(sz)
	_draw_toast(sz)


func _draw_header(sz: Vector2) -> void:
	var money := int(player.money) if is_instance_valid(player) else 0
	_text(_wheel, Vector2(26.0, 37.0), "$%d" % money, 26, GREEN_MONEY)

	var bt := float(RoundManager.buy_time_left)
	var title := "Buy Time Remaining  %d:%02d" % [int(bt / 60.0), int(bt) % 60]
	var tcol := TEXT_WHITE
	if bt <= 0.0:
		title = "Buy Time Expired"
		tcol = RED_PRICE
	_text(_wheel, Vector2(0.0, 34.0), title, 17, tcol, sz.x, HORIZONTAL_ALIGNMENT_CENTER)

	var team_ct := not is_instance_valid(player) or player.team == "CT"
	var team_txt := "COUNTER-TERRORISTS" if team_ct else "TERRORISTS"
	var team_col := CT_TINT if team_ct else T_TINT
	_wheel.draw_rect(Rect2(Vector2(sz.x - 236.0, 18.0), Vector2(4.0, 22.0)), team_col)
	_text(_wheel, Vector2(sz.x - 226.0, 35.0), team_txt, 15, team_col, 210.0)

	# section breadcrumb above the wheel
	var crumb := "BUY MENU"
	if current_category > 0:
		crumb = "BUY MENU  /  " + _category_title(current_category)
	var wc := _wheel_center()
	_text(_wheel, Vector2(wc.x - 220.0, wc.y - _ring_out() - 30.0), crumb, 16, TEXT_DIM, 440.0,
		HORIZONTAL_ALIGNMENT_CENTER)


func _draw_wheel_ring() -> void:
	var c := _wheel_center()
	var eo := _ease_open()
	var r_out := _ring_out() * (0.86 + 0.14 * eo)
	var r_in := _ring_in() * (0.86 + 0.14 * eo)
	var n := _entries.size()

	# outer shadow + base disc
	_wheel.draw_circle(c, r_out + 8.0, Color(0.0, 0.0, 0.0, 0.40 * eo))
	if n == 0:
		_wheel.draw_circle(c, r_out, WHEEL_BG)
		_text(_wheel, c + Vector2(-120.0, r_in + 40.0), "Nothing to buy here", 15, TEXT_DIM, 240.0,
			HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var step := TAU / float(n)
		var cat_col := _category_color(current_category)
		for i in range(n):
			var e: Dictionary = _entries[i]
			var ha := _hover_amt[i] if i < _hover_amt.size() else 0.0
			var a0 := -PI * 0.5 + float(i) * step
			var a1 := a0 + step
			var a_mid := (a0 + a1) * 0.5
			var dir := Vector2(cos(a_mid), sin(a_mid))
			var pop := dir * (6.0 * ha)
			var base_col := WHEEL_BG if i % 2 == 0 else WHEEL_BG_ALT
			var fill := base_col.lerp(WHEEL_HOVER, ha)
			_wheel.draw_colored_polygon(_sector_poly(a0, a1, r_in, r_out + 4.0 * ha, c + pop), fill)
			# separators
			var rad := Vector2(cos(a0), sin(a0))
			_wheel.draw_line(c + rad * r_in, c + rad * r_out, WHEEL_LINE, 1.0)
			# hover rim (category coloured on item wheels, gold on sections)
			if ha > 0.02:
				var rim := GOLD if current_category == 0 else cat_col
				_wheel.draw_arc(c + pop, r_out + 4.0 * ha, a0 + 0.01, a1 - 0.01, 24,
					Color(rim.r, rim.g, rim.b, ha), 3.0, true)
				_wheel.draw_arc(c + pop, r_in + 1.0, a0 + 0.01, a1 - 0.01, 16,
					Color(1.0, 1.0, 1.0, 0.25 * ha), 1.5, true)

			# content
			var mid := c + pop + dir * lerpf(r_in, r_out, 0.56)
			var price := int(e["price"])
			var affordable := price < 0 or (is_instance_valid(player) and player.money >= price)
			var owned := bool(e["owned"])
			var icon_col := Color(1.0, 1.0, 1.0, 0.80 + 0.20 * ha)
			if owned:
				icon_col = Color(0.55, 0.60, 0.66, 0.85)
			elif not affordable:
				icon_col = Color(0.85, 0.42, 0.40, 0.80)
			var span := minf(r_out - r_in, 2.0 * lerpf(r_in, r_out, 0.56) * sin(step * 0.5)) * 0.92
			var iw := clampf(span, 60.0, 150.0) * (1.0 + 0.08 * ha)
			var icon_box := Rect2(mid - Vector2(iw * 0.5, iw * 0.24) + Vector2(0.0, -8.0), Vector2(iw, iw * 0.42))
			_draw_entry_icon(_wheel, e, icon_box, icon_col)

			var label := String(e["name"])
			var label_col := TEXT_WHITE.lerp(ACCENT, ha) if not owned else TEXT_FAINT
			_text(_wheel, Vector2(mid.x - 85.0, icon_box.end.y + 15.0), label, 13, label_col, 170.0,
				HORIZONTAL_ALIGNMENT_CENTER)
			var sub := ""
			var sub_col := TEXT_DIM
			if String(e["kind"]) == "section":
				sub = String(e["desc"])
			elif owned:
				sub = "OWNED"
				sub_col = TEXT_FAINT
			elif price >= 0:
				sub = "$%d" % price
				sub_col = GREEN_MONEY if affordable else RED_PRICE
			if not sub.is_empty():
				_text(_wheel, Vector2(mid.x - 85.0, icon_box.end.y + 31.0), sub, 12, sub_col, 170.0,
					HORIZONTAL_ALIGNMENT_CENTER)
			# hotkey number near the inner rim
			var kp := c + pop + dir * (r_in + 15.0)
			_text(_wheel, kp + Vector2(-10.0, 5.0), str(int(e["num"])), 12,
				ACCENT if ha > 0.5 else TEXT_FAINT, 20.0, HORIZONTAL_ALIGNMENT_CENTER, false)
		# outer ring line
		_wheel.draw_arc(c, r_out, 0.0, TAU, 96, WHEEL_LINE, 1.2, true)

	# centre emblem (gold coin)
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	var er := r_in - 6.0
	_wheel.draw_circle(c, r_in, Color(0.02, 0.025, 0.03, 0.92))
	_wheel.draw_circle(c, er, GOLD_DARK)
	_wheel.draw_circle(c, er * 0.88, GOLD.lerp(Color.WHITE, 0.15 if _hover_center else 0.0))
	_wheel.draw_circle(c, er * 0.70, GOLD_DARK)
	_wheel.draw_arc(c, er, 0.0, TAU, 64, Color(1.0, 0.92, 0.65, 0.65), 1.5, true)
	if _hover_center:
		_wheel.draw_arc(c, r_in + 2.0, 0.0, TAU, 64, Color(GOLD.r, GOLD.g, GOLD.b, 0.45 + 0.4 * pulse), 3.0, true)
	var emb_col := Color(1.0, 0.93, 0.70, 1.0)
	if current_category > 0:
		var ar := er * 0.36
		_wheel.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-ar, 0.0), c + Vector2(ar * 0.55, -ar * 0.85), c + Vector2(ar * 0.55, ar * 0.85),
		]), emb_col)
	elif is_instance_valid(player):
		var emb := "CT" if player.team == "CT" else "T"
		_text(_wheel, c + Vector2(-er, 7.0), emb, int(clampf(er * 0.55, 12.0, 26.0)),
			emb_col, er * 2.0, HORIZONTAL_ALIGNMENT_CENTER)
	if _hover_center:
		var tip := "BACK" if current_category > 0 else "CLOSE"
		_text(_wheel, c + Vector2(-60.0, er + 22.0), tip, 12, ACCENT, 120.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_stats_panel() -> void:
	var pn := _panel_rect()
	var x0 := pn.position.x + 18.0
	var w := pn.size.x - 36.0
	var y := pn.position.y + 34.0

	var e: Dictionary = {}
	if _sel >= 0 and _sel < _entries.size():
		e = _entries[_sel]
	var wid := ""
	if not e.is_empty() and String(e["kind"]) == "weapon":
		wid = String(e["id"])
	elif e.is_empty() and is_instance_valid(player) and player.weapon_ctrl != null:
		wid = String(player.weapon_ctrl.current_weapon_id)

	if e.is_empty() and wid.is_empty():
		_text(_wheel, Vector2(x0, y), "Hover an item to inspect it", 15, TEXT_DIM, w)
		return

	# header: name + rarity bar
	var title := ""
	var subtitle := ""
	var rarity := _category_color(current_category)
	if not e.is_empty():
		title = String(e["name"])
		if String(e["kind"]) == "section":
			subtitle = String(e["desc"])
			rarity = _category_color(int(e["num"]))
		else:
			subtitle = _category_title(current_category)
	else:
		var spec0: Dictionary = GameData.weapons.get(wid, {})
		title = String(spec0.get("name", wid))
		subtitle = "CURRENTLY EQUIPPED"
		rarity = _category_color(_cat_for_weapon(wid))
	_text(_wheel, Vector2(x0, y), title.to_upper(), 22, TEXT_WHITE, w)
	_wheel.draw_rect(Rect2(Vector2(x0, y + 10.0), Vector2(w, 4.0)), rarity)
	_text(_wheel, Vector2(x0, y + 32.0), subtitle, 12, TEXT_DIM, w)
	y += 50.0

	if not e.is_empty() and String(e["kind"]) == "section":
		var sv := _silhouette(String(e["vgui"]))
		var box := Rect2(Vector2(x0, y), Vector2(w, 80.0))
		if sv != null:
			_wheel.draw_texture_rect(sv, _fit_rect(sv, box), false, Color(1.0, 1.0, 1.0, 0.9))
		else:
			_draw_glyph(_wheel, "kevlar_helmet", box, Color(1.0, 1.0, 1.0, 0.9))
		_text(_wheel, Vector2(x0, y + 112.0), "Click to open this section", 13, TEXT_DIM, w)
		return

	# price / ownership line
	var price := int(e["price"]) if not e.is_empty() else -1
	if price >= 0:
		var ok := is_instance_valid(player) and player.money >= price
		_text(_wheel, Vector2(x0, y), "$%d" % price, 20, GREEN_MONEY if ok else RED_PRICE, w)
		if not e.is_empty() and bool(e["owned"]):
			_text(_wheel, Vector2(x0, y), "OWNED", 14, TEXT_FAINT, w, HORIZONTAL_ALIGNMENT_RIGHT)
		elif not ok:
			_text(_wheel, Vector2(x0, y), "NOT ENOUGH MONEY", 12, RED_PRICE, w, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 26.0

	if wid.is_empty():
		# gear / ammo description
		var box2 := Rect2(Vector2(x0, y), Vector2(w, 70.0))
		_draw_entry_icon(_wheel, e, box2, Color(1.0, 1.0, 1.0, 0.9))
		_text_wrapped(Vector2(x0, y + 98.0), String(e["desc"]), 13, TEXT_DIM, w, 4)
		return

	var spec: Dictionary = GameData.weapons.get(wid, {})
	if bool(spec.get("grenade", false)) or int(spec.get("buy_cat", 0)) == 8:
		var box3 := Rect2(Vector2(x0, y), Vector2(w, 64.0))
		var sg := _silhouette(String(spec.get("vgui", "")))
		if sg != null:
			_wheel.draw_texture_rect(sg, _fit_rect(sg, box3), false, Color(1.0, 1.0, 1.0, 0.9))
		var have := 0
		if is_instance_valid(player) and player.weapon_ctrl != null:
			have = int(player.weapon_ctrl.grenades.get(wid, 0))
		_text(_wheel, Vector2(x0, y + 92.0), "CARRYING  %d / %d" % [have, int(spec.get("max_ammo", 1))],
			13, TEXT_DIM, w)
		return

	# ammo line
	var clip := int(spec.get("clip_size", 0))
	var reserve := int(spec.get("max_ammo", 0))
	if clip > 0:
		_text(_wheel, Vector2(x0, y), "AMMO", 12, TEXT_DIM, w)
		_text(_wheel, Vector2(x0, y), "%d / %d" % [clip, reserve], 13, TEXT_WHITE, w, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 22.0

	# stat bars with diff against the weapon owned in the same slot
	var vals := _weapon_stats(spec)
	var cmp: Array = []
	var owned_id := ""
	if is_instance_valid(player) and player.weapon_ctrl != null:
		owned_id = String(player.weapon_ctrl.slots.get(int(spec.get("slot", 1)), ""))
	if not owned_id.is_empty() and owned_id != wid and GameData.weapons.has(owned_id):
		cmp = _weapon_stats(GameData.weapons[owned_id])
	var bar_h := 7.0
	for si in range(STAT_NAMES.size()):
		_text(_wheel, Vector2(x0, y + 4.0), String(STAT_NAMES[si]), 11, TEXT_DIM, w)
		var by := y + 10.0
		var br := Rect2(Vector2(x0, by), Vector2(w, bar_h))
		_wheel.draw_rect(br, BAR_BG)
		var v: float = vals[si]
		if cmp.is_empty():
			_wheel.draw_rect(Rect2(br.position, Vector2(w * v, bar_h)), BAR_FILL)
		else:
			var ov: float = cmp[si]
			var lo := minf(v, ov)
			_wheel.draw_rect(Rect2(br.position, Vector2(w * lo, bar_h)), BAR_FILL)
			if v > ov:
				_wheel.draw_rect(Rect2(br.position + Vector2(w * ov, 0.0), Vector2(w * (v - ov), bar_h)), GREEN_MONEY)
			elif ov > v:
				_wheel.draw_rect(Rect2(br.position + Vector2(w * v, 0.0), Vector2(w * (ov - v), bar_h)),
					Color(RED_PRICE.r, RED_PRICE.g, RED_PRICE.b, 0.75))
		# 10% ticks
		for t in range(1, 10):
			var tx := x0 + w * float(t) / 10.0
			_wheel.draw_line(Vector2(tx, by), Vector2(tx, by + bar_h), Color(0.0, 0.0, 0.0, 0.45), 1.0)
		y += 30.0
	if not cmp.is_empty():
		var oname := String((GameData.weapons[owned_id] as Dictionary).get("name", owned_id))
		_text(_wheel, Vector2(x0, y + 6.0), "Compared with your " + oname, 11, TEXT_FAINT, w)


func _text_wrapped(pos: Vector2, txt: String, fs: int, col: Color, width: float, max_lines: int) -> void:
	var font := _wheel.get_theme_default_font()
	var words := txt.split(" ", false)
	var line := ""
	var lines: Array = []
	for wd in words:
		var trial := wd if line.is_empty() else line + " " + wd
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x > width and not line.is_empty():
			lines.append(line)
			line = wd
		else:
			line = trial
	if not line.is_empty():
		lines.append(line)
	for i in range(mini(lines.size(), max_lines)):
		_text(_wheel, pos + Vector2(0.0, float(i) * (float(fs) + 5.0)), String(lines[i]), fs, col, width)


func _draw_loadout(sz: Vector2) -> void:
	var y0 := sz.y - 92.0
	_text(_wheel, Vector2(26.0, y0 + 22.0), "YOUR LOADOUT", 11, TEXT_FAINT, 200.0)
	if is_instance_valid(player) and player.weapon_ctrl != null:
		var wc: WeaponController = player.weapon_ctrl
		var items: Array = []
		for sl in [1, 2]:
			var id := String(wc.slots.get(sl, ""))
			if not id.is_empty() and GameData.weapons.has(id):
				items.append([String((GameData.weapons[id] as Dictionary).get("vgui", "")), "", id])
		for gid in ["hegrenade", "flashbang", "smokegrenade"]:
			var cnt := int(wc.grenades.get(gid, 0))
			if cnt > 0 and GameData.weapons.has(gid):
				items.append([String((GameData.weapons[gid] as Dictionary).get("vgui", "")),
					("x%d" % cnt) if cnt > 1 else "", gid])
		var x := 26.0
		for it in items:
			var sil := _silhouette(String(it[0]))
			var box := Rect2(Vector2(x, y0 + 30.0), Vector2(110.0, 34.0))
			if sil != null:
				_wheel.draw_texture_rect(sil, _fit_rect(sil, box), false, Color(1.0, 1.0, 1.0, 0.85))
			if not String(it[1]).is_empty():
				_text(_wheel, Vector2(x + 96.0, y0 + 66.0), String(it[1]), 12, TEXT_DIM)
			x += 124.0
		# gear status
		var gear: Array = []
		if player.armor > 0:
			gear.append("kevlar_helmet" if player.has_helmet else "kevlar")
		if player.has_defuser:
			gear.append("defuser")
		if player.has_nvg:
			gear.append("nightvision")
		for g in gear:
			_draw_glyph(_wheel, String(g), Rect2(Vector2(x, y0 + 32.0), Vector2(60.0, 30.0)),
				Color(1.0, 1.0, 1.0, 0.85))
			x += 70.0
		if player.armor > 0:
			_text(_wheel, Vector2(x, y0 + 54.0), "ARMOR %d" % player.armor, 12, TEXT_DIM)

	var hint := "LEFT CLICK  buy    ·    RIGHT CLICK / CENTRE  back    ·    WHEEL  rotate    ·    B  close" \
		if current_category > 0 else \
		"LEFT CLICK  open section    ·    RIGHT CLICK  close    ·    1-6  quick select    ·    B / ESC  close"
	_text(_wheel, Vector2(sz.x * 0.42, sz.y - 22.0), hint, 12, TEXT_FAINT, sz.x * 0.56,
		HORIZONTAL_ALIGNMENT_RIGHT, false)


func _draw_toast(sz: Vector2) -> void:
	if _toast_t <= 0.0:
		return
	var a := clampf(_toast_t / 0.35, 0.0, 1.0)
	var font := _wheel.get_theme_default_font()
	var tw := font.get_string_size(_toast_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x + 40.0
	var r := Rect2(Vector2((sz.x - tw) * 0.5, 66.0), Vector2(tw, 32.0))
	_wheel.draw_rect(r, Color(0.03, 0.035, 0.045, 0.92 * a))
	_wheel.draw_rect(Rect2(r.position, Vector2(4.0, r.size.y)), Color(_toast_col.r, _toast_col.g, _toast_col.b, a))
	_text(_wheel, r.position + Vector2(0.0, 22.0), _toast_text, 16,
		Color(_toast_col.r, _toast_col.g, _toast_col.b, a), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _toast(txt: String, col: Color) -> void:
	_toast_text = txt
	_toast_col = col
	_toast_t = 1.6


# --- Stats -------------------------------------------------------------------------------

func _compute_stat_ranges() -> void:
	var mx := {"dmg": 1.0, "rof": 1.0, "spread": 0.001, "recoil": 0.001, "speed": 1.0, "pen": 1.0}
	for wid in GameData.weapons.keys():
		var s: Dictionary = GameData.weapons[wid]
		if int(s.get("price", 0)) <= 0 or int(s.get("buy_cat", 0)) == 8:
			continue
		mx["dmg"] = maxf(float(mx["dmg"]), float(s.get("damage", 0)))
		mx["rof"] = maxf(float(mx["rof"]), 1.0 / maxf(0.03, float(s.get("cycle_time", 0.1))))
		mx["spread"] = maxf(float(mx["spread"]), float(s.get("spread_base", 0.01)))
		mx["recoil"] = maxf(float(mx["recoil"]), float(s.get("recoil_up", 0.0)))
		mx["speed"] = maxf(float(mx["speed"]), float(s.get("max_speed", 250.0)))
		mx["pen"] = maxf(float(mx["pen"]), float(s.get("armor_ratio", 1.0)))
	_stat_max = mx


func _weapon_stats(s: Dictionary) -> Array:
	if _stat_max.is_empty():
		_compute_stat_ranges()
	var dmg := float(s.get("damage", 0)) / float(_stat_max["dmg"])
	var rof := (1.0 / maxf(0.03, float(s.get("cycle_time", 0.1)))) / float(_stat_max["rof"])
	var acc := 1.0 - float(s.get("spread_base", 0.01)) / float(_stat_max["spread"]) * 0.9
	var rec := 1.0 - float(s.get("recoil_up", 0.0)) / float(_stat_max["recoil"]) * 0.9
	var mob := float(s.get("max_speed", 250.0)) / float(_stat_max["speed"])
	var pen := float(s.get("armor_ratio", 1.0)) / float(_stat_max["pen"])
	return [clampf(dmg, 0.04, 1.0), clampf(rof, 0.04, 1.0), clampf(acc, 0.04, 1.0),
		clampf(rec, 0.04, 1.0), clampf(mob, 0.04, 1.0), clampf(pen, 0.04, 1.0)]


# --- 3D character preview ---------------------------------------------------------------

func _build_preview_viewport() -> void:
	_pv_container = SubViewportContainer.new()
	_pv_container.name = "CharacterPreview"
	_pv_container.stretch = true
	_pv_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pv_container)

	_pv_viewport = SubViewport.new()
	_pv_viewport.own_world_3d = true
	_pv_viewport.transparent_bg = true
	_pv_viewport.handle_input_locally = false
	_pv_viewport.msaa_3d = Viewport.MSAA_4X
	_pv_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_pv_container.add_child(_pv_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.64)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	_pv_viewport.add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.light_color = Color(1.0, 0.96, 0.90)
	key.rotation = Vector3(deg_to_rad(-28.0), deg_to_rad(-35.0), 0.0)
	_pv_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.85
	rim.light_color = Color(0.62, 0.74, 1.0)
	rim.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(150.0), 0.0)
	_pv_viewport.add_child(rim)

	_pv_camera = Camera3D.new()
	_pv_camera.fov = 30.0
	_pv_camera.near = 0.05
	_pv_camera.far = 50.0
	_pv_camera.position = Vector3(0.0, 0.10, 5.6)
	_pv_camera.current = true
	_pv_viewport.add_child(_pv_camera)
	_pv_camera.look_at_from_position(_pv_camera.position, Vector3(0.0, 0.02, 0.0), Vector3.UP)

	_pv_pivot = Node3D.new()
	_pv_pivot.name = "Turntable"
	_pv_viewport.add_child(_pv_pivot)


func _layout_preview() -> void:
	var pr := _preview_rect()
	if _pv_container.position != pr.position:
		_pv_container.position = pr.position
	if _pv_container.size != pr.size:
		_pv_container.size = pr.size
	_pv_container.modulate.a = _ease_open()


func _preview_class_id() -> String:
	if not is_instance_valid(player):
		return "urban"
	if player.is_vip:
		return "vip"
	return String(player.class_id)


func _ensure_preview_model() -> void:
	var cid := _preview_class_id()
	if cid == _pv_class and _pv_model != null:
		return
	if _pv_model != null:
		_pv_pivot.remove_child(_pv_model)
		_pv_model.queue_free()
	_pv_model = null
	_pv_anim = null
	_pv_skel = null
	_pv_hand = null
	_pv_tracks.clear()
	_pv_upper_name = ""
	_pv_lower_name = ""
	_pv_weapon = "?"
	_pv_class = cid
	var sc := GameData.get_model_scene("players/" + cid)
	if sc == null:
		sc = GameData.get_model_scene("players/" + ("urban" if player.team == "CT" else "terror"))
	if sc == null:
		return
	var inst := sc.instantiate() as Node3D
	if inst == null:
		return
	_pv_model = inst
	_style_meshes(inst)
	_pv_pivot.add_child(inst)
	_pv_anim = _find_node_of(inst, "AnimationPlayer") as AnimationPlayer
	_pv_skel = _find_node_of(inst, "Skeleton3D") as Skeleton3D
	if _pv_anim != null:
		# Same approach as CSActor: the AnimationPlayer stays inactive and the
		# GoldSrc gait (lower body) + aim (upper body) clips are sampled by hand.
		_pv_anim.stop()
		_pv_anim.active = false
	if _pv_skel != null:
		_build_preview_mask()
		_pv_lower_name = _anim_named(_pv_anim, "idle1")
		if _pv_skel.find_bone("Bip01 R Hand") >= 0:
			_pv_hand = BoneAttachment3D.new()
			_pv_hand.bone_name = "Bip01 R Hand"
			_pv_skel.add_child(_pv_hand)
		_animate_preview(0.0)


func _style_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var styled := GameData.get_styled_model_material(mi.mesh.surface_get_material(s), "char")
				if styled:
					mi.set_surface_override_material(s, styled)
	for ch in n.get_children():
		_style_meshes(ch)


func _find_node_of(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for ch in n.get_children():
		var f := _find_node_of(ch, cls)
		if f != null:
			return f
	return null


func _anim_named(ap: AnimationPlayer, short_name: String) -> String:
	if ap == null:
		return ""
	if ap.has_animation(short_name):
		return short_name
	for a in ap.get_animation_list():
		var s := String(a)
		if s.ends_with("/" + short_name):
			return s
	return ""


## Weapon shown in the character's hand: hovered weapon, else what you hold.
func _refresh_preview_weapon() -> void:
	var wid := ""
	if _sel >= 0 and _sel < _entries.size():
		var e: Dictionary = _entries[_sel]
		if String(e["kind"]) == "weapon":
			wid = String(e["id"])
	if wid.is_empty() and is_instance_valid(player) and player.weapon_ctrl != null:
		wid = String(player.weapon_ctrl.current_weapon_id)
	_set_preview_weapon(wid)


func _set_preview_weapon(wid: String) -> void:
	if wid == _pv_weapon or _pv_model == null:
		return
	_pv_weapon = wid
	if _pv_hand != null:
		for ch in _pv_hand.get_children():
			_pv_hand.remove_child(ch)
			ch.queue_free()
		if GameData.weapons.has(wid):
			var spec: Dictionary = GameData.weapons[wid]
			var v_name := String(spec.get("v_model", ""))
			var p_name := ("p_" + v_name.substr(2)) if v_name.begins_with("v_") else ("p_" + wid)
			var p_sc := GameData.get_model_scene("weapons/" + p_name)
			if p_sc != null:
				var p_inst := p_sc.instantiate()
				_style_meshes(p_inst)
				_pv_hand.add_child(p_inst)
	if _pv_anim != null and is_instance_valid(player):
		var ext := String(player.call("_get_weapon_anim_ext", wid)) if not wid.is_empty() else "carbine"
		var an := _anim_named(_pv_anim, "ref_aim_" + ext)
		if an.is_empty():
			an = _anim_named(_pv_anim, "ref_aim_carbine")
		_pv_upper_name = an


func _animate_preview(delta: float) -> void:
	if _pv_pivot == null:
		return
	# 3/4 turntable facing the camera with a slow idle sway (model faces -Z at yaw 0)
	_pv_pivot.rotation.y = PI + 0.42 + sin(_time * 0.55) * 0.16
	if _pv_skel == null or _pv_anim == null:
		return
	_pv_anim_t += delta
	_apply_preview_clip(_pv_lower_name, 0)
	_apply_preview_clip(_pv_upper_name, 1)


## Upper body = Bip01 Spine and everything below it in the hierarchy.
func _build_preview_mask() -> void:
	var nb := _pv_skel.get_bone_count()
	_pv_upper_mask.resize(nb)
	_pv_upper_mask.fill(0)
	var spine := _pv_skel.find_bone("Bip01 Spine")
	if spine < 0:
		return
	_pv_upper_mask[spine] = 1
	for bi in range(nb):
		var cur := _pv_skel.get_bone_parent(bi)
		var guard := 0
		while cur >= 0 and guard < 96:
			guard += 1
			if _pv_upper_mask[cur] == 1:
				_pv_upper_mask[bi] = 1
				break
			cur = _pv_skel.get_bone_parent(cur)


## mode 0 = lower-body bones only, 1 = upper-body bones only.
func _apply_preview_clip(anim_name: String, mode: int) -> void:
	if anim_name.is_empty():
		return
	if not _pv_tracks.has(anim_name):
		var res: Animation = null
		if _pv_anim.has_animation(anim_name):
			res = _pv_anim.get_animation(anim_name)
		var entries: Array = []
		if res != null:
			for ti in range(res.get_track_count()):
				var tt := res.track_get_type(ti)
				if tt != Animation.TYPE_POSITION_3D and tt != Animation.TYPE_ROTATION_3D:
					continue
				var bname := String(res.track_get_path(ti).get_concatenated_subnames())
				var bidx := _pv_skel.find_bone(bname)
				if bidx >= 0:
					entries.append([ti, bidx, tt == Animation.TYPE_POSITION_3D])
		_pv_tracks[anim_name] = [res, entries]
	var pack: Array = _pv_tracks[anim_name]
	var anim_res := pack[0] as Animation
	if anim_res == null:
		return
	var t := fposmod(_pv_anim_t, maxf(0.05, anim_res.length))
	var has_mask := _pv_upper_mask.size() == _pv_skel.get_bone_count()
	for entry in (pack[1] as Array):
		var e := entry as Array
		var ti2 := int(e[0])
		var bi2 := int(e[1])
		if has_mask:
			if mode == 0 and _pv_upper_mask[bi2] == 1:
				continue
			if mode == 1 and _pv_upper_mask[bi2] == 0:
				continue
		if bool(e[2]):
			_pv_skel.set_bone_pose_position(bi2, anim_res.position_track_interpolate(ti2, t))
		else:
			_pv_skel.set_bone_pose_rotation(bi2, anim_res.rotation_track_interpolate(ti2, t))


# --- Catalogue -----------------------------------------------------------------------------

func _category_title(cat: int) -> String:
	for rc in CATEGORIES:
		if int(rc[0]) == cat:
			return String(rc[1])
	return "BUY MENU"


func _category_color(cat: int) -> Color:
	for rc in CATEGORIES:
		if int(rc[0]) == cat:
			var col: Color = rc[3]
			return col
	return GOLD


func _cat_for_weapon(wid: String) -> int:
	if not GameData.weapons.has(wid):
		return 0
	match int((GameData.weapons[wid] as Dictionary).get("buy_cat", 0)):
		1: return 1
		2, 5: return 2
		3: return 3
		4: return 4
		8: return 6
	return 0


## Purchase entries for a category, already team-filtered & ordered.
func _category_specs(cat: int) -> Array:
	var out: Array = []
	if not is_instance_valid(player):
		return out
	match cat:
		1, 2, 3, 4, 6:
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
					"kind": "weapon",
					"name": String(spec.get("name", wid2)),
					"price": int(spec.get("price", 0)),
					"vgui": String(spec.get("vgui", "")),
					"desc": "",
					"owned": _owns_weapon(wid2, spec),
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
				var eprice := int(eq.get("price", 0))
				if eqid == "kevlar_helmet" and player.armor >= 100 and not player.has_helmet:
					eprice = int(eq.get("upgrade_price", eprice))
				out.append({
					"id": eqid,
					"kind": "gear",
					"name": String(eq.get("name", eid)),
					"price": eprice,
					"vgui": "",
					"desc": _short_desc(String(eq.get("description", ""))),
					"owned": _owns_gear(eqid),
					"action": func(): _purchase_eq(eqid),
				})
			out.append({
				"id": "ammo1",
				"kind": "ammo",
				"name": "Primary Ammo",
				"price": -1,
				"vgui": "",
				"desc": "Refills your primary weapon reserve.",
				"owned": false,
				"action": func(): _buy_ammo(1),
			})
			out.append({
				"id": "ammo2",
				"kind": "ammo",
				"name": "Secondary Ammo",
				"price": -1,
				"vgui": "",
				"desc": "Refills your secondary weapon reserve.",
				"owned": false,
				"action": func(): _buy_ammo(2),
			})
	return out


func _owns_weapon(wid: String, spec: Dictionary) -> bool:
	if not is_instance_valid(player) or player.weapon_ctrl == null:
		return false
	var wc: WeaponController = player.weapon_ctrl
	if int(spec.get("buy_cat", 0)) == 8:
		return int(wc.grenades.get(wid, 0)) >= int(spec.get("max_ammo", 1))
	return String(wc.slots.get(int(spec.get("slot", 1)), "")) == wid


func _owns_gear(eid: String) -> bool:
	if not is_instance_valid(player):
		return false
	match eid:
		"kevlar":
			return player.armor >= 100
		"kevlar_helmet":
			return player.armor >= 100 and player.has_helmet
		"defuser":
			return player.has_defuser
		"nightvision":
			return player.has_nvg
	return false


## Turns the classic CS 1.5 info block ("Price\t: $650\nDescription\t: ...")
## into a caption.
func _short_desc(raw: String) -> String:
	var flat := raw.replace("\t", " ").replace("\n", " ")
	var di := flat.find("Description")
	if di >= 0:
		flat = flat.substr(di + 11).lstrip(": ").strip_edges()
	flat = " ".join(flat.split(" ", false))
	return flat


# --- Purchases -------------------------------------------------------------------------------

func _purchase_weapon(wid: String) -> void:
	if is_instance_valid(player) and player.buy_weapon(wid):
		player.buy_ammo_for_slot(1, true)
		player.buy_ammo_for_slot(2, true)
		AudioManager.play_ui("launch_select2.wav")
		var nm := String((GameData.weapons[wid] as Dictionary).get("name", wid))
		_toast("PURCHASED  " + nm.to_upper(), GREEN_MONEY)
		_rebuild_keep_selection()
	else:
		_flash_deny(wid)


func _purchase_eq(eid: String) -> void:
	if is_instance_valid(player) and player.buy_equipment(eid):
		AudioManager.play_ui("launch_select2.wav")
		var nm := String((GameData.equipment[eid] as Dictionary).get("name", eid))
		_toast("PURCHASED  " + nm.to_upper(), GREEN_MONEY)
		_rebuild_keep_selection()
	else:
		_deny_eq(eid)


func _buy_ammo(sl: int) -> void:
	if is_instance_valid(player) and player.buy_ammo_for_slot(sl, true):
		AudioManager.play_ui("launch_select2.wav")
		_toast("AMMO REFILLED", GREEN_MONEY)
	else:
		_set_deny(0)
	_rebuild_keep_selection()


func _rebuild_keep_selection() -> void:
	var keep_sel := _sel
	var keep_hover := _hover
	_show_category(current_category)
	if keep_sel >= 0 and keep_sel < _entries.size():
		_sel = keep_sel
	if keep_hover >= 0 and keep_hover < _entries.size():
		_hover = keep_hover
		_hover_amt[keep_hover] = 1.0
	_pv_weapon = "?"


func _deny_eq(eid: String) -> void:
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
	if is_instance_valid(player) and price > 0 and player.money < price:
		_toast("NOT ENOUGH MONEY", RED_PRICE)
	else:
		_toast("CAN'T BUY THAT NOW", RED_PRICE)
