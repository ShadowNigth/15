class_name CSHud
extends CanvasLayer
## Counter-Strike 2 style HUD for the CS 1.5 remake:
##   - Top-center scoreboard (CT score | round timer | T score + alive pips)
##   - Top-left circular radar with the real map overview & player arrow
##   - Top-right KILL FEED CARDS (dark rounded cards: killer / weapon icon / headshot / victim)
##   - Bottom-left HP & Armor plates, bottom-right money / weapon / ammo (CS2 layout)
##   - Bottom-center team emblem on a divider line with ANIMATED KILL CARDS:
##     each enemy kill pops a numbered card above the emblem (1-5 fan out with
##     weapon pips, ace on the fifth, from 6 a counter card) plus a light beam
##     and glow-ring flash — the CS2 kill card effect
##   - CS2 gold typography with team-blue CT and team-gold T accents

const HUD_WHITE := Color(0.97, 0.85, 0.46, 0.98)
const HUD_DIM := Color(0.82, 0.74, 0.48, 0.72)
const RED_WARN := Color(0.95, 0.28, 0.24, 0.98)
const GREEN_MONEY := Color(0.55, 0.86, 0.45, 0.98)
const CT_COLOR := Color(0.47, 0.70, 0.98, 1.0)
const T_COLOR := Color(0.95, 0.78, 0.38, 1.0)
const GREEN_HUD := Color(0.45, 0.90, 0.50, 0.95)
const PANEL_BG := Color(0.055, 0.06, 0.075, 0.72)
const PANEL_BORDER := Color(1.0, 1.0, 1.0, 0.07)
# CS2 huddeathnotice exact styles: red ring on your kills, dark red plate on your death
const KILL_RING_RED := Color(0.88, 0.0, 0.0, 0.95)
const KILL_PLATE_DARKRED := Color(0.36, 0.05, 0.04, 0.78)

var player: PlayerController = null
var preview_mode := false
var _accent_labels: Array[Label] = []
var _last_hud_color := Color.TRANSPARENT
var _shown_clip: int = -1
var layout_elements: Dictionary = {}
var _layout_defaults: Dictionary = {}

var _nvg_rect: ColorRect = null
var _scope_root: Control = null
var _scope_blur_rect: ColorRect = null
var _scope_blur_cur: float = 0.0
var _smoke_rect: ColorRect = null
var _flash_rect: ColorRect = null
var _crosshair_ctrl: Control = null
var _radar_panel: Panel = null
var _radar_ctrl: Control = null

var _score_panel: Panel = null
var _score_ctrl: Control = null

var _hp_label: Label = null
var _armor_label: Label = null
var _hp_icon: TextureRect = null
var _ap_icon: TextureRect = null
var _money_label: Label = null
var _money_delta_label: Label = null
var _native_ammo_icon: TextureRect = null
var _ammo_label: Label = null
var _ammo_reserve_label: Label = null
var _weapon_name_label: Label = null
var _weapon_icon: TextureRect = null
var _center_label: Label = null
var _spec_label: Label = null
var _progress_bar: ProgressBar = null
var _progress_title: Label = null

var _icon_buyzone: TextureRect = null
var _icon_c4: TextureRect = null
var _icon_defuser: TextureRect = null

var _inv_icons: Array[TextureRect] = []
var _knife_icon_id: String = ""
var _location_label: Label

var _killfeed_vbox: VBoxContainer = null
var _radio_vbox: VBoxContainer = null

var _center_timer: float = 0.0
var _money_delta_timer: float = 0.0
var _c4_blink_phase: float = 0.0
var _crosshair_gap_cur: float = 5.0
var _damage_arcs: Array = []
var _is_bomb_planted: bool = false
var _bomb_pos: Vector3 = Vector3.ZERO
var _score_refresh_timer: float = 0.0
var _inv_refresh_timer: float = 0.0
var _ct_alive: int = 5
var _t_alive: int = 5

# HP/Armor display dedupe (player signal + spectator-target polling share one path)
var _shown_hp: int = -1
var _shown_ap: int = -1
var _shown_helmet: bool = false

var _killcards: KillCardDisplay = null

# Cached map overview for the circular radar
var _ov_tex: Texture2D = null
var _ov_affine: Array = []
var _ov_rot: int = 0
var _ov_fit_off: Vector2 = Vector2.ZERO


## Bottom-center CS2 kill-card display: divider line + team emblem on the bottom
## HUD. Every enemy eliminated this round pops an animated numbered card above
## the emblem (kills 1-5 fan out with weapon pips and an ace-styled fifth; from
## kill 6 a single counter card), with a vertical light beam, rising sparks and
## an expanding glow-ring flash — CS2's animated kill cards.
class KillCardDisplay extends Control:
	var hud_color := Color(0.97, 0.85, 0.46, 0.98)
	const EMBLEM_R: float = 17.0
	const CARD_W: float = 18.0
	const CARD_H: float = 30.0
	const FAN_DX: float = 14.0
	const FLASH_DUR: float = 0.7

	var team: String = ""
	var kills: int = 0
	var cards: Array[Dictionary] = []
	const COMBO_WINDOW := 4.0
	var combo_left := 0.0
	var combo_age := 0.0
	var combo_count := 0
	var combo_label := ""
	var latest_flags: Dictionary = {}
	var flash_age: float = FLASH_DUR


	func end_chain() -> void:
		combo_count = 0
		combo_left = 0.0
		combo_label = ""
		latest_flags.clear()
		queue_redraw()


	func reset_round() -> void:
		kills = 0
		combo_count = 0
		combo_left = 0.0
		combo_label = ""
		latest_flags.clear()
		cards.clear()
		flash_age = FLASH_DUR
		queue_redraw()


	## Counts one enemy kill for the local player this round and fires the flash.
	func register_kill(icon: Texture2D, flags: Dictionary = {}) -> void:
		combo_count = combo_count + 1 if combo_left > 0.0 else 1
		combo_left = COMBO_WINDOW
		combo_age = 0.0
		latest_flags = flags.duplicate(true)
		combo_label = "DOUBLE KILL" if combo_count == 2 else "TRIPLE KILL" if combo_count == 3 else "QUADRA KILL" if combo_count == 4 else "%dX MULTI KILL" % combo_count if combo_count >= 5 else ""
		kills += 1
		var new_card: Dictionary = {
			"num": kills, "icon": icon, "pop": 0.0,
			"pos": Vector2(0.0, 8.0), "rot": 0.0,
		}
		if RoundManager.map_mode == "dm" and cards.size() >= 5:
			cards.pop_front()
		if kills > 5 and RoundManager.map_mode != "dm":
			# Past the ace, CS2 collapses the fan into one counter card
			cards.clear()
			new_card["counter"] = true
		cards.append(new_card)
		flash_age = 0.0
		queue_redraw()


	func _process(delta: float) -> void:
		var dirty := false
		if combo_left > 0.0:
			combo_left = maxf(0.0, combo_left - delta)
			combo_age += delta
			dirty = true
		if flash_age < FLASH_DUR + 0.05:
			flash_age += delta
			dirty = true
		if cards.is_empty():
			if dirty:
				queue_redraw()
			return
		var n := cards.size()
		var counter: bool = cards[0].get("counter", false) == true
		for i in n:
			var card: Dictionary = cards[i]
			var tgt := Vector2.ZERO
			var tgt_rot := 0.0
			if not counter:
				var off := float(i) - (float(n) - 1.0) * 0.5
				tgt = Vector2(off * FAN_DX, absf(off) * 1.5)
				tgt_rot = deg_to_rad(off * 7.0)
			var pv: Vector2 = card["pos"]
			var rv: float = card["rot"]
			pv = pv.lerp(tgt, minf(1.0, delta * 11.0))
			rv = lerpf(rv, tgt_rot, minf(1.0, delta * 11.0))
			if (pv - tgt).length_squared() > 0.04 or absf(rv - tgt_rot) > 0.004:
				dirty = true
			else:
				pv = tgt
				rv = tgt_rot
			card["pos"] = pv
			card["rot"] = rv
			var pop := float(card["pop"])
			if pop < 1.0:
				card["pop"] = minf(1.0, pop + delta * 4.5)
				dirty = true
		if dirty:
			queue_redraw()


	func _draw() -> void:
		if team != "CT" and team != "T":
			return
		var ct := team == "CT"
		var accent := Color(hud_color, 0.9)
		var hot := Color(0.85, 0.92, 1.0) if ct else Color(1.0, 0.87, 0.55)
		var cx := size.x * 0.5
		var cy := size.y - 41.0
		var font := get_theme_default_font()

		# Divider line running between the HP/Armor plates and the ammo block
		var x0 := cx - 104.0
		var x1 := cx + 104.0
		if x1 - x0 > 60.0:
			draw_rect(Rect2(x0, cy - 1.0, x1 - x0, 2.0), Color(1.0, 1.0, 1.0, 0.20))

		# Kill flash: vertical light beam, sparks and expanding glow ring
		var fp: float = clampf(flash_age / FLASH_DUR, 0.0, 1.0)
		var flare := 0.0
		if flash_age < FLASH_DUR:
			var rise := minf(1.0, fp * 3.2)
			var fade := 1.0 - fp
			var bh := 78.0 * rise
			draw_rect(Rect2(cx - 4.5, cy - bh, 9.0, bh + 12.0), Color(hot.r, hot.g, hot.b, 0.16 * fade))
			draw_rect(Rect2(cx - 1.5, cy - bh, 3.0, bh + 12.0), Color(1.0, 1.0, 1.0, 0.85 * fade))
			var sparks: Array[Vector2] = [
				Vector2(-0.55, -1.0), Vector2(0.5, -0.95),
				Vector2(-0.2, -1.2), Vector2(0.8, -0.75),
			]
			for i in sparks.size():
				var dv: Vector2 = sparks[i]
				var sp := dv.normalized() * (24.0 + 46.0 * rise) * (0.8 + 0.2 * float(i % 2))
				var sq := 3.0 * (1.0 - fp * 0.55)
				draw_rect(Rect2(cx + sp.x - sq * 0.5, cy + sp.y - sq * 0.5, sq, sq), Color(1.0, 1.0, 0.95, 0.9 * fade))
			draw_arc(Vector2(cx, cy), EMBLEM_R + 15.0 * fp, 0.0, TAU, 44, Color(hot.r, hot.g, hot.b, 0.9 * fade), 2.5 * fade + 0.5, true)
			flare = pow(1.0 - fp, 1.8) * 0.9

		# Distinct multikill headline: short impact, stable hold, then a readable fade.
		if combo_label != "" and combo_left > 0.0:
			var title_alpha := minf(1.0, combo_left / 0.65)
			var punch := 1.0 + 0.22 * exp(-combo_age * 9.0) * sin(combo_age * 23.0)
			var title_size := int(24.0 * punch)
			var title_pos := Vector2(cx - 180, cy - 112 - 5.0 * exp(-combo_age * 8.0))
			draw_string(font, title_pos + Vector2(1, 2), combo_label, HORIZONTAL_ALIGNMENT_CENTER, 360, title_size, Color(0, 0, 0, title_alpha))
			draw_string(font, title_pos, combo_label, HORIZONTAL_ALIGNMENT_CENTER, 360, title_size, Color(hot.r, hot.g, hot.b, title_alpha))
		if combo_left > 0.0:
			var badges: Array[String] = []
			for flag in KillContext.FLAGS:
				if bool(latest_flags.get(flag, false)):
					badges.append(flag)
			var bx := cx - float(badges.size()) * 13.0
			for flag in badges:
				var badge_texture := KillContext.icon(flag)
				if badge_texture != null:
					draw_texture_rect(badge_texture, Rect2(bx, cy - 99, 21, 16), false, Color(1, 1, 1, minf(1.0, combo_left / 0.65)))
				bx += 26

		# Team emblem: dark disc, bright flare on kill, team ring, team letters
		draw_circle(Vector2(cx, cy), EMBLEM_R, Color(0.04, 0.04, 0.055, 0.9))
		if flare > 0.01:
			draw_circle(Vector2(cx, cy), EMBLEM_R - 0.5, Color(1.0, 1.0, 1.0, flare))
		var mark_a := clampf(1.0 - flare * 1.2, 0.0, 1.0)
		draw_arc(Vector2(cx, cy), EMBLEM_R, 0.0, TAU, 44, Color(accent.r, accent.g, accent.b, accent.a * mark_a), 1.7, true)
		var team_col := Color(1.0, 1.0, 1.0, 0.92 * mark_a)
		var emblem := load("res://assets/ui/teams/" + team.to_lower() + ".svg") as Texture2D
		if emblem != null:
			draw_texture_rect(emblem, Rect2(cx - 15, cy - 15, 30, 30), false, Color(hud_color.r / (0.663 if ct else 0.875), hud_color.g / (0.78 if ct else 0.729), hud_color.b / (0.863 if ct else 0.439), mark_a))

		# Numbered kill cards fanning out above the emblem
		var n := cards.size()
		for i in n:
			var card: Dictionary = cards[i]
			var pop := float(card["pop"])
			var back := pop - 1.0
			var eb := 1.0 + 2.70158 * back * back * back + 1.70158 * back * back
			var scl: float = (0.45 + 0.55 * maxf(0.0, eb)) * (1.18 if i == n - 1 and flash_age < FLASH_DUR else 1.0)
			var counter: bool = card.get("counter", false) == true
			var cw: float = 26.0 if counter else CARD_W
			var off_pos: Vector2 = card["pos"]
			var pivot := Vector2(cx, cy - EMBLEM_R - 6.0) + off_pos
			var rot: float = card["rot"]
			draw_set_transform(pivot, rot, Vector2(scl, scl))
			var card_rect := Rect2(-cw * 0.5, -CARD_H, cw, CARD_H)
			var is_ace := RoundManager.map_mode != "dm" and (not counter) and n == 5 and i == 4
			var csb := StyleBoxFlat.new()
			csb.set_corner_radius_all(3)
			csb.set_border_width_all(1)
			if is_ace:
				csb.bg_color = Color(0.13, 0.10, 0.03, 0.94)
				csb.border_color = Color(1.0, 0.82, 0.3, 0.95)
			else:
				csb.bg_color = Color(0.03, 0.03, 0.045, 0.92)
				csb.border_color = Color(accent.r, accent.g, accent.b, 0.55)
			draw_style_box(csb, card_rect)
			var icon: Variant = card.get("icon")
			if icon is Texture2D:
				var tex := icon as Texture2D
				var ts := tex.get_size()
				var isc := minf(14.0 / maxf(ts.x, 1.0), 9.0 / maxf(ts.y, 1.0))
				var iw := ts.x * isc
				var ih := ts.y * isc
				draw_texture_rect(tex, Rect2(-7.0 + (14.0 - iw) * 0.5, -CARD_H + 4.0 + (9.0 - ih) * 0.5, iw, ih), false, Color(1.0, 1.0, 1.0, 0.95))
			var num := str(card["num"])
			var num_col := Color(1.0, 0.86, 0.45) if is_ace else Color(0.95, 0.96, 0.99)
			var tw := cw - 4.0
			var num_size := 14 if counter else 13
			draw_string(font, Vector2(-tw * 0.5, -5.0), num, HORIZONTAL_ALIGNMENT_CENTER, tw, num_size, Color(0.0, 0.0, 0.0, 0.8))
			draw_string(font, Vector2(-tw * 0.5, -6.0), num, HORIZONTAL_ALIGNMENT_CENTER, tw, num_size, num_col)


func _ready() -> void:
	layer = 5
	_build_hud_tree()
	_load_radar_overview()
	UICustomization.changed.connect(apply_custom_layout)
	UICustomization.changed.connect(update_hud_color.bind(true))
	update_hud_color(true)
	get_viewport().size_changed.connect(apply_custom_layout)
	apply_custom_layout.call_deferred()

	if preview_mode:
		return

	RoundManager.center_message.connect(_on_center_message)
	RoundManager.kill_detailed.connect(_on_kill_logged)
	RoundManager.chat_radio_message.connect(_on_radio_chat)
	RoundManager.bomb_state_changed.connect(_on_bomb_state_changed)
	RoundManager.round_started.connect(_on_round_started)


func bind_player(p: PlayerController) -> void:
	player = p
	player.health_armor_changed.connect(_on_hp_armor)
	player.money_changed.connect(_on_money)
	player.defuse_progress_changed.connect(_on_defuse_progress)
	player.scoped_overlay_changed.connect(_on_scope_changed)
	player.nvg_toggled.connect(_on_nvg_toggled)
	player.spectator_target_changed.connect(_on_spec_changed)
	player.weapon_ctrl.weapon_switched.connect(_on_weapon_switched)
	player.weapon_ctrl.ammo_updated.connect(_on_ammo_updated)
	player.weapon_ctrl.plant_progress_changed.connect(_on_plant_progress)
	player.damaged_from.connect(_on_player_damaged)

	_on_hp_armor(player.health, player.armor, player.has_helmet)
	_on_money(player.money, 0)
	var cr := player.weapon_ctrl.get_clip_and_reserve()
	_on_ammo_updated(cr.x, cr.y)
	_refresh_inventory_icons()


func _cs2_panel_style(corner: int = 8, bg: Color = PANEL_BG, border_col: Color = PANEL_BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(corner)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


func _make_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	if col == HUD_WHITE or col == HUD_DIM:
		l.set_meta("hud_dim", col == HUD_DIM)
		_accent_labels.append(l)
		col = _accent(col == HUD_DIM)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_hud_icon(entry: String, tint: Color, sz: Vector2 = Vector2(22, 22)) -> TextureRect:
	var icon_rect := TextureRect.new()
	icon_rect.texture = GameData.get_hud_atlas(entry, 320)
	icon_rect.custom_minimum_size = sz
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.modulate = tint
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon_rect


func _load_radar_overview() -> void:
	var ov: Dictionary = GameData.overviews.get(GameData.selected_map, {})
	_ov_tex = GameData.get_texture(String(ov.get("image", "")))
	_ov_affine = ov.get("affine", [])
	_ov_rot = int(ov.get("rotated", 0))


func _build_hud_tree() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# 1. Nightvision Green Phosphor Overlay
	_nvg_rect = ColorRect.new()
	_nvg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_nvg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nvg_sh := load("res://assets/shaders/nvg_overlay.gdshader") as Shader
	if nvg_sh:
		var sm := ShaderMaterial.new()
		sm.shader = nvg_sh
		_nvg_rect.material = sm
		_nvg_rect.visible = false
	root.add_child(_nvg_rect)

	# 1b. Scope movement blur (CS:GO style: view turns slightly difuse when
	# you move while scoped). Sits below the scope overlay so the reticle and
	# tube stay sharp while the world behind them blurs.
	_scope_blur_rect = ColorRect.new()
	_scope_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_blur_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scope_blur_sh := load("res://assets/shaders/scope_blur.gdshader") as Shader
	if scope_blur_sh:
		var scope_blur_mat := ShaderMaterial.new()
		scope_blur_mat.shader = scope_blur_sh
		_scope_blur_rect.material = scope_blur_mat
	_scope_blur_rect.visible = false
	root.add_child(_scope_blur_rect)

	# 2. Sniper Scope Overlay
	_scope_root = Control.new()
	_scope_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scope_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scope_root.visible = false
	_scope_root.draw.connect(_draw_sniper_scope)
	root.add_child(_scope_root)

	# 3. Dynamic Crosshair
	_crosshair_ctrl = Control.new()
	_crosshair_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_ctrl.draw.connect(_draw_crosshair)
	root.add_child(_crosshair_ctrl)

	# 4. Top-Left CS2 Square Radar: rounded dark panel + real map overview + blips
	_radar_panel = Panel.new()
	_radar_panel.position = Vector2(14, 14)
	_radar_panel.size = Vector2(186, 186)
	_radar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_radar_panel.add_theme_stylebox_override("panel", _cs2_panel_style(93, Color(0.03, 0.035, 0.025, 0.85), HUD_WHITE))
	_radar_panel.draw.connect(func(): _radar_panel.draw_arc(Vector2(93, 93), 91, 0, TAU, 96, _accent(), 2, true))
	root.add_child(_radar_panel)

	_radar_ctrl = Control.new()
	_radar_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_radar_ctrl.offset_left = 5.0
	_radar_ctrl.offset_top = 5.0
	_radar_ctrl.offset_right = -5.0
	_radar_ctrl.offset_bottom = -5.0
	_radar_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_ctrl.draw.connect(_draw_radar)
	_radar_panel.add_child(_radar_ctrl)

	_location_label = _make_label(GameData.selected_map.replace("_", " ").to_upper(), 13, HUD_WHITE)
	_location_label.position = Vector2(18, 203)
	root.add_child(_location_label)

	# 5. Left Status Icons (Buyzone, C4, Defuser) under the radar
	var left_icons := VBoxContainer.new()
	left_icons.position = Vector2(18, 203)
	left_icons.add_theme_constant_override("separation", 8)
	left_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left_icons)
	_location_label.reparent(left_icons, false)

	_icon_buyzone = _make_hud_icon("buyzone", GREEN_HUD, Vector2(18, 18))
	_icon_c4 = _make_hud_icon("smallc4", GREEN_HUD, Vector2(18, 18))
	_icon_defuser = _make_hud_icon("defuser", GREEN_HUD, Vector2(18, 18))
	left_icons.add_child(_icon_buyzone)
	left_icons.add_child(_icon_c4)
	left_icons.add_child(_icon_defuser)

	# 6. Top-Center CS2 Scoreboard: CT score | timer | T score + alive pips
	_score_panel = Panel.new()
	_score_panel.anchor_left = 0.5
	_score_panel.anchor_right = 0.5
	_score_panel.offset_left = -244
	_score_panel.offset_right = 244
	_score_panel.offset_top = 0
	_score_panel.offset_bottom = 60
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	root.add_child(_score_panel)

	_score_ctrl = Control.new()
	_score_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_score_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_ctrl.draw.connect(_draw_scoreboard)
	_score_panel.add_child(_score_ctrl)

	# 7. Top-Right CS2 Kill Feed CARDS (first row below the scoreboard, CS2 y=75)
	_killfeed_vbox = VBoxContainer.new()
	_killfeed_vbox.anchor_left = 1.0
	_killfeed_vbox.anchor_right = 1.0
	_killfeed_vbox.offset_left = -470
	_killfeed_vbox.offset_right = -10
	_killfeed_vbox.offset_top = 75
	_killfeed_vbox.offset_bottom = 320
	_killfeed_vbox.add_theme_constant_override("separation", 3)
	_killfeed_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_killfeed_vbox)

	# 8. Center Round / Bomb Announcement + Plant/Defuse Bar
	_center_label = _make_label("", 26, HUD_WHITE)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.anchor_left = 0.2
	_center_label.anchor_right = 0.8
	_center_label.anchor_top = 0.26
	_center_label.anchor_bottom = 0.40
	root.add_child(_center_label)

	_spec_label = _make_label("", 17, HUD_WHITE)
	_spec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spec_label.anchor_left = 0.25
	_spec_label.anchor_right = 0.75
	_spec_label.anchor_top = 0.86
	_spec_label.anchor_bottom = 0.92
	root.add_child(_spec_label)

	var prog_box := VBoxContainer.new()
	prog_box.anchor_left = 0.36
	prog_box.anchor_right = 0.64
	prog_box.anchor_top = 0.56
	prog_box.anchor_bottom = 0.64
	prog_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prog_box)

	_progress_title = _make_label("", 16, HUD_WHITE)
	_progress_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog_box.add_child(_progress_title)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(280, 14)
	var pb_sb := StyleBoxFlat.new()
	pb_sb.bg_color = Color(0.05, 0.055, 0.07, 0.8)
	pb_sb.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("background", pb_sb)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = Color(0.93, 0.94, 0.96, 0.95)
	pb_fill.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("fill", pb_fill)
	_progress_bar.visible = false
	prog_box.add_child(_progress_bar)

	# 9. Top-Left Radio / Chat Feed (CS2: under the radar & status icons)
	_radio_vbox = VBoxContainer.new()
	_radio_vbox.position = Vector2(16, 304)
	_radio_vbox.custom_minimum_size = Vector2(430, 150)
	_radio_vbox.add_theme_constant_override("separation", 4)
	_radio_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_radio_vbox)

	# Reference layout: money at the far left, compact vitals left of centre.
	var bl_root := Control.new()
	bl_root.anchor_right = 0.5
	bl_root.anchor_top = 1.0
	bl_root.anchor_bottom = 1.0
	bl_root.offset_left = 18
	bl_root.offset_right = -130
	bl_root.offset_top = -76
	bl_root.offset_bottom = -14
	bl_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bl_root)
	_money_label = _make_label("$800", 26, HUD_WHITE)
	_money_label.position = Vector2(0, 13)
	bl_root.add_child(_money_label)
	_money_delta_label = _make_label("", 16, GREEN_MONEY)
	_money_delta_label.position = Vector2(0, -20)
	bl_root.add_child(_money_delta_label)
	var hp_row := HBoxContainer.new()
	hp_row.anchor_left = 1.0
	hp_row.anchor_right = 1.0
	hp_row.offset_left = -100
	hp_row.offset_right = 0
	hp_row.offset_top = 20
	hp_row.offset_bottom = 62
	hp_row.add_theme_constant_override("separation", 9)
	bl_root.add_child(hp_row)
	_hp_icon = _make_hud_icon("cross", HUD_WHITE, Vector2(19, 19))
	_hp_label = _make_label("100", 34, HUD_WHITE)
	hp_row.add_child(_hp_icon)
	hp_row.add_child(_hp_label)
	var ap_row := HBoxContainer.new()
	ap_row.anchor_left = 1.0
	ap_row.anchor_right = 1.0
	ap_row.offset_left = -96
	ap_row.offset_right = 0
	ap_row.offset_top = 0
	ap_row.offset_bottom = 20
	ap_row.add_theme_constant_override("separation", 5)
	bl_root.add_child(ap_row)
	_ap_icon = _make_hud_icon("suit_full", HUD_WHITE, Vector2(15, 15))
	_armor_label = _make_label("0", 14, HUD_DIM)
	ap_row.add_child(_ap_icon)
	ap_row.add_child(_armor_label)

	# One editable equipment group still contains both ammunition and inventory.
	var equipment_group := Control.new()
	equipment_group.anchor_left = 0.72
	equipment_group.anchor_right = 1.0
	equipment_group.anchor_top = 1.0
	equipment_group.anchor_bottom = 1.0
	equipment_group.offset_left = 0
	equipment_group.offset_right = -18
	equipment_group.offset_top = -282
	equipment_group.offset_bottom = -14
	equipment_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(equipment_group)
	var ammo_row := HBoxContainer.new()
	ammo_row.anchor_top = 1.0
	ammo_row.anchor_bottom = 1.0
	ammo_row.offset_top = -46
	ammo_row.offset_bottom = 0
	ammo_row.offset_right = 180
	ammo_row.add_theme_constant_override("separation", 6)
	equipment_group.add_child(ammo_row)
	_ammo_label = _make_label("12", 34, HUD_WHITE)
	_ammo_reserve_label = _make_label("| 24", 18, HUD_DIM)
	_ammo_reserve_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	ammo_row.add_child(_ammo_label)
	ammo_row.add_child(_ammo_reserve_label)
	_weapon_name_label = _make_label("", 16, HUD_WHITE)
	_weapon_name_label.anchor_left = 1.0
	_weapon_name_label.anchor_right = 1.0
	_weapon_name_label.offset_left = -200
	_weapon_name_label.offset_right = 0
	_weapon_name_label.offset_top = 0
	_weapon_name_label.offset_bottom = 20
	_weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	equipment_group.add_child(_weapon_name_label)
	_weapon_icon = TextureRect.new()
	_weapon_icon.visible = false # Active weapon is highlighted in the strip, not duplicated.
	equipment_group.add_child(_weapon_icon)
	var inv_col := VBoxContainer.new()
	inv_col.anchor_left = 1.0
	inv_col.anchor_right = 1.0
	inv_col.offset_left = -128
	inv_col.offset_right = 0
	inv_col.offset_top = 24
	inv_col.offset_bottom = 224
	inv_col.add_theme_constant_override("separation", 5)
	inv_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipment_group.add_child(inv_col)
	var outline_shader := Shader.new()
	outline_shader.code = """shader_type canvas_item;
varying vec4 icon_tint;
void vertex() { icon_tint = COLOR; }
void fragment() {
 vec4 tint = icon_tint;
 vec4 tex = texture(TEXTURE, UV);
 vec2 step_uv = TEXTURE_PIXEL_SIZE * 2.0;
 float border = tex.a;
 for (int x = -1; x <= 1; x++) {
  for (int y = -1; y <= 1; y++) {
   border = max(border, texture(TEXTURE, UV + vec2(float(x), float(y)) * step_uv).a);
  }
 }
 COLOR = vec4(mix(vec3(0.015), tex.rgb * tint.rgb, tex.a), border * tint.a);
}"""
	var outline_material := ShaderMaterial.new()
	outline_material.shader = outline_shader
	for slot in range(5):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inv_col.add_child(row)
		var inv_ic := TextureRect.new()
		inv_ic.custom_minimum_size = Vector2(103, 30)
		inv_ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		inv_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		inv_ic.modulate = HUD_WHITE
		inv_ic.material = outline_material
		inv_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(inv_ic)
		row.add_child(_make_label(str(slot + 1), 13, HUD_DIM))
		_inv_icons.append(inv_ic)
	_killcards = KillCardDisplay.new()
	_killcards.set_anchors_preset(Control.PRESET_FULL_RECT)
	_killcards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_killcards)
	for entry in [["radar", _radar_panel], ["status", left_icons], ["score", _score_panel], ["killfeed", _killfeed_vbox], ["announcements", _center_label], ["spectator", _spec_label], ["progress", prog_box], ["radio", _radio_vbox], ["health", bl_root], ["equipment", equipment_group]]:
		register_layout_element(entry[0], entry[1])

	# 12. Inside-Smoke Volumetric Immersion Overlay + Flashbang Fullscreen Whiteout
	_smoke_rect = ColorRect.new()
	_smoke_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_smoke_rect.color = Color(0.73, 0.75, 0.77, 0.0)
	_smoke_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_smoke_rect)

	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash_rect)


func _process(delta: float) -> void:
	_c4_blink_phase += delta * 6.0
	_update_scope_blur(delta)

	if _killcards != null:
		var pteam := String(player.team) if is_instance_valid(player) else ""
		if _killcards.team != pteam:
			_killcards.team = pteam
			_killcards.queue_redraw()

	if _center_timer > 0.0:
		_center_timer -= delta
		if _center_timer <= 0.0:
			_center_label.text = ""

	if _money_delta_timer > 0.0:
		_money_delta_timer -= delta
		if _money_delta_timer <= 0.0:
			_money_delta_label.text = ""

	for di in range(_damage_arcs.size() - 1, -1, -1):
		var arc_d := _damage_arcs[di] as Dictionary
		var next_a: float = float(arc_d["alpha"]) - delta * 1.15
		if next_a <= 0.01:
			_damage_arcs.remove_at(di)
		else:
			arc_d["alpha"] = next_a

	# Top-center round timer is drawn by _draw_scoreboard(); just wake it each frame
	_score_ctrl.queue_redraw()

	if is_instance_valid(player):
		if not GameData.low_ammo_warning:
			_ammo_label.add_theme_color_override("font_color", _accent())
		var smoke_d := RoundManager.get_smoke_density_at(player.get_eye_position()) if player.is_alive else 0.0
		_smoke_rect.color.a = lerpf(_smoke_rect.color.a, clampf(smoke_d * 0.97, 0.0, 0.97), minf(1.0, delta * 9.0))
		var fl_raw: float = clampf(player.flash_alpha, 0.0, 1.35)
		_flash_rect.color.a = clampf(pow(fl_raw, 0.78), 0.0, 1.0)
		_icon_buyzone.visible = player.can_use_buy_menu()
		var carries_c4 := String(player.weapon_ctrl.slots.get(5, "")) == "c4"
		_icon_c4.visible = carries_c4
		if carries_c4 and is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_bombsite"):
			if bool(RoundManager.game_world.call("is_in_bombsite", player.global_position)):
				_icon_c4.modulate = RED_WARN if sin(_c4_blink_phase * 2.5) > 0.0 else _accent()
			else:
				_icon_c4.modulate = _accent()
		_icon_defuser.visible = player.has_defuser

		var target_gap: float = UICustomization.crosshair.gap
		if GameData.dynamic_crosshair and player.is_alive:
			var spd := Vector2(player.velocity.x, player.velocity.z).length()
			target_gap += spd * 1.35 + float(player.weapon_ctrl.shots_fired) * 1.65 + player.weapon_ctrl.punch_angles.length() * 0.85
			if not player.is_on_floor():
				target_gap += 9.0
			elif player.is_crouching:
				target_gap *= 0.72
		_crosshair_gap_cur = lerpf(_crosshair_gap_cur, target_gap, minf(1.0, 22.0 * delta))

	if RoundManager.map_mode == "dm" and is_instance_valid(player):
		if not player.is_alive and RoundManager.dm_respawns.has(player):
			_weapon_name_label.text = "Respawn in %.1fs" % float(RoundManager.dm_respawns[player])
		elif player.dm_protection > 0.0:
			_weapon_name_label.text = "Spawn protection %.1fs — fire to cancel" % player.dm_protection
		else:
			_weapon_name_label.text = String(player.weapon_ctrl.get_current_spec().get("name", ""))

	# Team alive pips + inventory refresh (cheap periodic)
	_score_refresh_timer -= delta
	if _score_refresh_timer <= 0.0:
		_score_refresh_timer = 0.4
		var ct_n := 0
		var t_n := 0
		for a in RoundManager.actors:
			if not is_instance_valid(a) or not bool(a.get("is_alive")):
				continue
			if String(a.get("team")) == "CT":
				ct_n += 1
			else:
				t_n += 1
		_ct_alive = ct_n
		_t_alive = t_n

	if _knife_icon_id != GameData.selected_knife_id:
		_refresh_inventory_icons()
		if is_instance_valid(player) and player.weapon_ctrl.current_weapon_id == "knife":
			_on_weapon_switched("knife", player.weapon_ctrl.get_current_spec())

	_inv_refresh_timer -= delta
	if _inv_refresh_timer <= 0.0:
		_inv_refresh_timer = 0.5
		_refresh_inventory_icons()

	# While dead, the HP/Armor plates must show the SPECTATED BOT's vitals (CS2 behaviour)!
	if is_instance_valid(player):
		var vst: Variant = player if player.is_alive else player.spectator_target
		if is_instance_valid(vst):
			var vit_src := vst as CSActor
			_apply_vitals(vit_src.health, vit_src.armor, vit_src.has_helmet)

	update_hud_color()
	_crosshair_ctrl.queue_redraw()
	_radar_ctrl.queue_redraw()


func _accent(dim: bool = false) -> Color:
	var tint := UICustomization.get_hud_color()
	return Color(tint, 0.72) if dim else tint

func update_hud_color(force: bool = false) -> void:
	var tint := _accent()
	if not force and tint == _last_hud_color:
		return
	_last_hud_color = tint
	for index in range(_accent_labels.size() - 1, -1, -1):
		var label := _accent_labels[index]
		if not is_instance_valid(label):
			_accent_labels.remove_at(index)
			continue
		label.add_theme_color_override("font_color", _accent(bool(label.get_meta("hud_dim", false))))
	# Warnings and team identities are semantic: never cycle them through RGB.
	_hp_label.add_theme_color_override("font_color", RED_WARN if _shown_hp >= 0 and _shown_hp <= 25 else tint)
	_armor_label.add_theme_color_override("font_color", tint if _shown_ap > 0 or preview_mode else _accent(true))
	if GameData.low_ammo_warning and _shown_clip >= 0 and _shown_clip <= 5:
		_ammo_label.add_theme_color_override("font_color", RED_WARN if _shown_clip == 0 else Color(0.98, 0.82, 0.35, 0.98))
	_hp_icon.modulate = tint
	_ap_icon.modulate = tint if _shown_ap > 0 or preview_mode else Color(tint, 0.35)
	for icon in _inv_icons:
		icon.modulate = Color(tint, icon.modulate.a)
	var radar_style := _radar_panel.get_theme_stylebox("panel") as StyleBoxFlat
	radar_style.border_color = tint
	var progress_style := _progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
	progress_style.bg_color = tint
	_killcards.hud_color = tint
	_killcards.queue_redraw()
	_radar_panel.queue_redraw()
	_score_ctrl.queue_redraw()

func _refresh_inventory_icons() -> void:
	_knife_icon_id = GameData.selected_knife_id
	if not is_instance_valid(player):
		return
	for i in range(5):
		var wid := String(player.weapon_ctrl.slots.get(i + 1, ""))
		if i == 3:
			if int(player.weapon_ctrl.grenades.get(player.weapon_ctrl.current_weapon_id, 0)) > 0:
				wid = player.weapon_ctrl.current_weapon_id
			elif wid.is_empty():
				for grenade in player.weapon_ctrl.grenades:
					if int(player.weapon_ctrl.grenades[grenade]) > 0:
						wid = grenade
						break
		var ic: TextureRect = _inv_icons[i]
		ic.get_parent().visible = not wid.is_empty()
		if wid.is_empty():
			ic.texture = null
			ic.modulate = Color(1, 1, 1, 0.16)
		else:
			var wh := _archi_weapon_texture(wid)
			if not wh:
				wh = GameData.get_weapon_hud_atlas(wid, "weapon_s_640")
			if not wh:
				wh = GameData.get_weapon_hud_atlas(wid, "weapon_640")
			ic.texture = wh
			# Grey out the non-equipped slots, full white for the active weapon
			var cur := String(player.weapon_ctrl.current_weapon_id)
			ic.modulate = _accent() if wid == cur else Color(_accent(), 0.72)


func _draw_scoreboard() -> void:
	var font := _score_ctrl.get_theme_default_font()
	var cx := _score_ctrl.size.x * 0.5
	var seconds := maxi(0, int(ceil(RoundManager.state_timer)))
	if is_instance_valid(RoundManager.planted_c4):
		seconds = maxi(0, int(ceil((RoundManager.planted_c4 as PlantedC4).time_left)))
	_score_ctrl.draw_rect(Rect2(cx - 37, 0, 74, 55), Color(0.015, 0.025, 0.035, 0.7))
	var timer := "%d:%02d" % [seconds / 60, seconds % 60]
	_score_ctrl.draw_string(font, Vector2(cx - 27, 23), timer, HORIZONTAL_ALIGNMENT_CENTER, 54, 21, RED_WARN if seconds <= 10 else _accent())
	_score_ctrl.draw_string(font, Vector2(cx - 26, 46), str(RoundManager.ct_score), HORIZONTAL_ALIGNMENT_CENTER, 20, 17, CT_COLOR)
	_score_ctrl.draw_string(font, Vector2(cx + 6, 46), str(RoundManager.t_score), HORIZONTAL_ALIGNMENT_CENTER, 20, 17, T_COLOR)
	for tm in ["CT", "T"]:
		var actors: Array = []
		for actor in RoundManager.actors:
			if is_instance_valid(actor) and actor.team == tm:
				actors.append(actor)
		var tile := minf(34.0, 196.0 / maxf(5, actors.size()))
		for index in range(actors.size()):
			var actor: CSActor = actors[index]
			var x := cx - 43 - (index + 1) * tile if tm == "CT" else cx + 43 + index * tile
			var rectangle := Rect2(x, 2, tile - 3, 32)
			var color := CT_COLOR if tm == "CT" else T_COLOR
			_score_ctrl.draw_rect(rectangle, Color(color, 0.3 if actor.is_alive else 0.08))
			var portrait := GameData.get_texture("res://assets/ui/vgui/640_%s.png" % actor.class_id)
			if portrait != null:
				_score_ctrl.draw_texture_rect_region(portrait, rectangle.grow(-2), Rect2(20, 0, 88, 88), Color(1, 1, 1, 1.0 if actor.is_alive else 0.18))
			_score_ctrl.draw_line(rectangle.end - Vector2(rectangle.size.x, 0), rectangle.end, color, 2)
			if not actor.is_alive:
				_score_ctrl.draw_line(rectangle.position, rectangle.end, Color(0.8, 0.3, 0.25), 1)
			else:
				_score_ctrl.draw_rect(Rect2(x, 36, (tile - 3) * clampf(actor.health / 100.0, 0, 1), 2), color)
	if RoundManager.map_mode == "dm":
		_score_ctrl.draw_string(font, Vector2(cx - 43, 65), "DM / %d" % GameData.dm_frag_limit, HORIZONTAL_ALIGNMENT_CENTER, 86, 11, _accent(true))


func _draw_crosshair() -> void:
	if not is_instance_valid(player):
		return
	var sz := _crosshair_ctrl.size
	var center := sz * 0.5

	# CS2-style directional damage indicators around the reticle
	if player.is_alive and not _damage_arcs.is_empty():
		var arc_r: float = minf(sz.x, sz.y) * 0.165
		for item in _damage_arcs:
			var d_arc := item as Dictionary
			var a_val: float = clampf(float(d_arc["alpha"]), 0.0, 1.0)
			var acol := Color(1.0, 0.14, 0.10, a_val * 0.82)
			if bool(d_arc["directional"]):
				var src_p: Vector3 = d_arc["pos"]
				var rel_w: Vector3 = src_p - player.global_position
				var local_v: Vector3 = Basis(Vector3.UP, -player.look_yaw) * rel_w
				var ang: float = atan2(local_v.z, local_v.x)
				_crosshair_ctrl.draw_arc(center, arc_r, ang - 0.42, ang + 0.42, 20, acol, 6.5)
			else:
				_crosshair_ctrl.draw_arc(center, arc_r, 0.0, TAU, 40, Color(1.0, 0.16, 0.10, a_val * 0.55), 5.0)

	if not player.is_alive or _scope_root.visible:
		return

	CrosshairPainter.paint(_crosshair_ctrl, center, _crosshair_gap_cur)


func _draw_sniper_scope() -> void:
	# CS:GO-style sniper scope: pure-black surround, circle ~75% of screen
	# height, thin white cross with a small centre gap, tube vignette + ring.
	var sz := _scope_root.size
	var c := sz * 0.5
	var r := sz.y * 0.375
	var blk := Color(0, 0, 0, 1.0)
	_scope_root.draw_rect(Rect2(0, 0, c.x - r, sz.y), blk)
	_scope_root.draw_rect(Rect2(c.x + r, 0, sz.x - (c.x + r), sz.y), blk)
	_scope_root.draw_rect(Rect2(c.x - r, 0, r * 2.0, maxf(0.0, c.y - r)), blk)
	_scope_root.draw_rect(Rect2(c.x - r, c.y + r, r * 2.0, maxf(0.0, sz.y - (c.y + r))), blk)
	# Fill the four corner bulges between the circle and its bounding box
	var corner_specs: Array = [
		[Vector2(c.x - r, c.y - r), PI, PI * 1.5],
		[Vector2(c.x - r, c.y + r), PI * 0.5, PI],
		[Vector2(c.x + r, c.y + r), 0.0, PI * 0.5],
		[Vector2(c.x + r, c.y - r), PI * 1.5, TAU],
	]
	for cs in corner_specs:
		var poly := PackedVector2Array()
		poly.append(cs[0])
		var a0: float = cs[1]
		var a1: float = cs[2]
		for seg in range(13):
			var ang: float = lerpf(a0, a1, float(seg) / 12.0)
			poly.append(c + Vector2(cos(ang), sin(ang)) * r)
		_scope_root.draw_colored_polygon(poly, blk)
	# CS:GO tube: soft inner vignette fading into the view, dark scope wall
	# around the circle and a thin outer edge highlight.
	var vig_w := maxf(7.0, r * 0.05)
	_scope_root.draw_arc(c, r - 1.5, 0.0, TAU, 128, Color(0, 0, 0, 0.17), vig_w)
	_scope_root.draw_arc(c, r - vig_w, 0.0, TAU, 128, Color(0, 0, 0, 0.10), vig_w)
	_scope_root.draw_arc(c, r - vig_w * 2.0, 0.0, TAU, 128, Color(0, 0, 0, 0.05), vig_w)
	var ring_w := maxf(4.0, r * 0.042)
	_scope_root.draw_arc(c, r + ring_w * 0.5 - 1.0, 0.0, TAU, 128, Color(0.07, 0.075, 0.09, 0.98), ring_w)
	_scope_root.draw_arc(c, r + ring_w + 1.5, 0.0, TAU, 128, Color(0.60, 0.63, 0.68, 0.30), 1.6)
	_scope_root.draw_arc(c, r - 0.5, 0.0, TAU, 128, Color(0, 0, 0, 0.9), 2.2)
	# Thin white cross with centre gap (CS2 reticle)
	var line_col := Color(1.0, 1.0, 1.0, 0.92)
	var lw: float = maxf(1.6, sz.y * 0.0021)
	var gap: float = r * 0.055
	_scope_root.draw_line(Vector2(c.x - r, c.y), Vector2(c.x - gap, c.y), line_col, lw)
	_scope_root.draw_line(Vector2(c.x + gap, c.y), Vector2(c.x + r, c.y), line_col, lw)
	_scope_root.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y - gap), line_col, lw)
	_scope_root.draw_line(Vector2(c.x, c.y + gap), Vector2(c.x, c.y + r), line_col, lw)


## World (GS plan units) -> radar-control pixels via the per-map fitted affine.
func _ov_world_to_px(gx: float, gy: float) -> Vector2:
	if _ov_affine.size() >= 4:
		var b := float(_ov_affine[0])
		var a := float(_ov_affine[1])
		var d := float(_ov_affine[2])
		var c := float(_ov_affine[3])
		if _ov_rot == 1:
			return Vector2(b * gy + a, d * gx + c)
		return Vector2(b * gx + a, d * gy + c)
	return Vector2.ZERO


func _draw_radar() -> void:
	var sz := _radar_ctrl.size
	if _ov_tex == null:
		return
	var tw := float(_ov_tex.get_width())
	var th := float(_ov_tex.get_height())
	if tw < 1.0 or th < 1.0:
		return
	var fit := minf(sz.x / tw, sz.y / th)
	_ov_fit_off = Vector2((sz.x - tw * fit) * 0.5, (sz.y - th * fit) * 0.5)
	_radar_ctrl.draw_texture_rect(_ov_tex, Rect2(_ov_fit_off, Vector2(tw * fit, th * fit)), false)

	if not is_instance_valid(player):
		return
	var ppos := player.global_position
	var pgs := Vector2(ppos.x / GameData.SCALE, ppos.z / GameData.SCALE)
	var ppx := _ov_world_to_px(pgs.x, pgs.y) * fit + _ov_fit_off

	# Teammate blips (team colored), VIP highlighted
	for a in RoundManager.actors:
		if not is_instance_valid(a) or a == player or not bool(a.get("is_alive")):
			continue
		if String(a.get("team")) != player.team:
			continue
		var ap: Vector3 = a.global_position
		var p := _ov_world_to_px(ap.x / GameData.SCALE, ap.z / GameData.SCALE) * fit + _ov_fit_off
		if bool(a.get("is_vip")):
			_radar_ctrl.draw_circle(p, 5.0, Color(0.45, 0.92, 1.0))
			_radar_ctrl.draw_arc(p, 6.5, 0.0, TAU, 16, Color(0.45, 0.92, 1.0, 0.6), 1.4)
		else:
			var mate_col := CT_COLOR if player.team == "CT" else T_COLOR
			_radar_ctrl.draw_circle(p, 3.6, Color(mate_col.r, mate_col.g, mate_col.b, 0.95))

	# Hostages
	for h in RoundManager.hostages:
		if is_instance_valid(h) and h.is_alive and not h.is_rescued:
			var hp_pos: Vector3 = h.global_position
			var ph := _ov_world_to_px(hp_pos.x / GameData.SCALE, hp_pos.z / GameData.SCALE) * fit + _ov_fit_off
			_radar_ctrl.draw_circle(ph, 3.4, Color(0.4, 0.85, 1.0))

	# Blinking planted bomb
	if _is_bomb_planted and sin(_c4_blink_phase * 2.5) > -0.2:
		var pb := _ov_world_to_px(_bomb_pos.x / GameData.SCALE, _bomb_pos.z / GameData.SCALE) * fit + _ov_fit_off
		_radar_ctrl.draw_circle(pb, 5.0, RED_WARN)
		_radar_ctrl.draw_arc(pb, 7.0, 0.0, TAU, 20, Color(1.0, 0.3, 0.25, 0.55), 1.5)

	# Player arrow (CS2 style): white triangle pointing along view direction
	var fwd := player.get_look_forward()
	var b_coef := float(_ov_affine[0]) if _ov_affine.size() >= 4 else 1.0
	var d_coef := float(_ov_affine[2]) if _ov_affine.size() >= 4 else -1.0
	var dir_px := Vector2(b_coef * (fwd.z if _ov_rot == 1 else fwd.x), d_coef * (fwd.x if _ov_rot == 1 else fwd.z))
	if dir_px.length_squared() < 0.0001:
		dir_px = Vector2(0, -1)
	dir_px = dir_px.normalized()
	var perp := Vector2(-dir_px.y, dir_px.x)
	var tip := ppx + dir_px * 7.5
	var back := ppx - dir_px * 4.0
	var tri := PackedVector2Array([tip, back + perp * 4.6, back - perp * 4.6])
	_radar_ctrl.draw_colored_polygon(tri, Color(1.0, 1.0, 1.0, 0.96))
	_radar_ctrl.draw_polyline(PackedVector2Array([tip, back + perp * 4.6, back - perp * 4.6, tip]), Color(0, 0, 0, 0.7), 1.2)


func _on_hp_armor(hp: int, ap: int, helmet: bool) -> void:
	_apply_vitals(hp, ap, helmet)


## Single dedupe'd writer for the HP/Armor plates (player signal + spectator polling).
func _apply_vitals(hp: int, ap: int, helmet: bool) -> void:
	if hp == _shown_hp and ap == _shown_ap and helmet == _shown_helmet:
		return
	_shown_hp = hp
	_shown_ap = ap
	_shown_helmet = helmet
	_hp_label.text = str(hp)
	_hp_label.add_theme_color_override("font_color", RED_WARN if hp <= 25 else _accent())
	_armor_label.text = str(ap)
	_armor_label.add_theme_color_override("font_color", _accent() if ap > 0 else _accent(true))
	var ap_entry := "suithelmet_full" if helmet else "suit_full"
	var ap_tex := GameData.equipment_icon("vesthelm" if helmet else "vest")
	if ap_tex == null:
		ap_tex = GameData.get_hud_atlas(ap_entry, 320)
	if ap_tex:
		_ap_icon.texture = ap_tex
	_ap_icon.modulate = _accent() if ap > 0 else Color(_accent(), 0.35)


func _on_money(amount: int, delta_amt: int) -> void:
	_money_label.text = "$%d" % amount
	if delta_amt != 0:
		_money_delta_label.text = ("+$%d" % delta_amt) if delta_amt > 0 else ("-$%d" % abs(delta_amt))
		_money_delta_label.add_theme_color_override("font_color", GREEN_MONEY if delta_amt > 0 else RED_WARN)
		_money_delta_timer = 2.4


func _archi_weapon_texture(wid: String) -> Texture2D:
	var native_icon := GameData.equipment_icon(wid)
	if native_icon != null:
		return native_icon
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var vgui := String(spec.get("vgui", ""))
	if vgui.is_empty():
		return null
	return GameData.get_texture("res://assets/ui/vgui/%s.png" % vgui.to_lower())


func _on_weapon_switched(wid: String, spec: Dictionary) -> void:
	var title := String(spec.get("name", wid.to_upper()))
	if bool(spec.get("silencer", false)) and is_instance_valid(player):
		if bool(player.weapon_ctrl.silenced_state.get(wid, false)):
			title += " (S)"
	_weapon_name_label.text = title

	var whud := _archi_weapon_texture(wid)
	if not whud:
		whud = GameData.get_weapon_hud_atlas(wid, "weapon_s_640")
	if not whud:
		whud = GameData.get_weapon_hud_atlas(wid, "weapon_640")
	if whud:
		_weapon_icon.texture = whud
	_refresh_inventory_icons()


func _on_ammo_updated(clip: int, reserve: int) -> void:
	_shown_clip = clip
	if clip < 0:
		_ammo_label.text = ""
		_ammo_reserve_label.text = ""
	else:
		_ammo_label.text = str(clip)
		_ammo_reserve_label.text = "| %d" % reserve
		if not GameData.low_ammo_warning:
			_ammo_label.add_theme_color_override("font_color", _accent())
		elif clip == 0:
			_ammo_label.add_theme_color_override("font_color", RED_WARN)
		elif clip <= 5:
			_ammo_label.add_theme_color_override("font_color", Color(0.98, 0.82, 0.35, 0.98))
		else:
			_ammo_label.add_theme_color_override("font_color", _accent())


func _on_center_message(msg: String, dur: float) -> void:
	_center_label.text = msg
	_center_timer = dur


func _on_plant_progress(ratio: float) -> void:
	_progress_bar.visible = ratio > 0.01
	_progress_title.text = "Planting C4 [7355608]..." if ratio > 0.01 else ""
	_progress_bar.value = ratio


func _on_defuse_progress(ratio: float) -> void:
	_progress_bar.visible = ratio > 0.01
	_progress_title.text = "Defusing Bomb..." if ratio > 0.01 else ""
	_progress_bar.value = ratio


func _on_scope_changed(active: bool) -> void:
	_scope_root.visible = active
	_scope_root.queue_redraw()
	if not active:
		_scope_blur_cur = 0.0
		if _scope_blur_rect != null:
			_scope_blur_rect.visible = false


## CS:GO movement blur: while the scope is up and the player moves, the world
## behind the reticle gets slightly difuse (radius grows with speed, decays
## back to zero when standing still or unscoping).
func _update_scope_blur(delta: float) -> void:
	if _scope_blur_rect == null or not (_scope_blur_rect.material is ShaderMaterial):
		return
	var target := 0.0
	if _scope_root.visible and is_instance_valid(player) and player.is_alive:
		var spd := Vector2(player.velocity.x, player.velocity.z).length()
		target = clampf((spd - 0.4) / 5.6, 0.0, 1.0)
	_scope_blur_cur = lerpf(_scope_blur_cur, target, clampf(9.0 * delta, 0.0, 1.0))
	var mat := _scope_blur_rect.material as ShaderMaterial
	mat.set_shader_parameter("u_strength", _scope_blur_cur * 3.4)
	_scope_blur_rect.visible = _scope_blur_cur > 0.04


func _on_nvg_toggled(active: bool) -> void:
	_nvg_rect.visible = active


func _on_spec_changed(tname: String) -> void:
	if tname.is_empty():
		_spec_label.text = ""
	elif tname.begins_with("Killed by"):
		_spec_label.text = tname
	else:
		_spec_label.text = "Spectating: " + tname + "  [Mouse1: Next]"


func _on_bomb_state_changed(planted: bool, pos: Vector3) -> void:
	_is_bomb_planted = planted
	_bomb_pos = pos


func _on_player_damaged(source_pos: Vector3, dmg_amount: int, directional: bool) -> void:
	var strength: float = clampf(0.45 + float(dmg_amount) / 55.0, 0.45, 1.0)
	while _damage_arcs.size() >= 6:
		_damage_arcs.pop_front()
	_damage_arcs.append({
		"pos": source_pos,
		"directional": directional,
		"alpha": strength,
	})


## Fresh round: the bottom-center CS2 kill-card counter starts over.
func _on_round_started(_round_num: int) -> void:
	if _killcards != null:
		_killcards.reset_round()


## CS2 huddeathnotice-style kill feed:
##   plain kill  -> black plate @0.55, no border
##   YOUR kill   -> black plate @0.72 + red #e10000 ring, lingers 7.5s
##   YOUR death  -> dark red plate, lingers 7.5s
##   rows are ~31px tall, first row right under the scoreboard, max 5, 1s fade
func _on_kill_logged(kname: String, kteam: String, vname: String, vteam: String, wid: String, hs: bool, context: Dictionary = {}) -> void:
	while _killfeed_vbox.get_child_count() >= 5:
		var oldest := _killfeed_vbox.get_child(0)
		_killfeed_vbox.remove_child(oldest)
		oldest.queue_free()

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var is_my_kill := is_instance_valid(player) and kname == String(player.actor_name)
	var is_my_death := is_instance_valid(player) and vname == String(player.actor_name)
	if is_my_death and _killcards != null:
		_killcards.end_chain()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(3)
	if is_my_death:
		sb.bg_color = KILL_PLATE_DARKRED
		sb.border_color = Color(0.52, 0.07, 0.05, 0.9)
		sb.set_border_width_all(1)
	elif is_my_kill:
		sb.bg_color = Color(0.02, 0.02, 0.03, 0.72)
		sb.border_color = KILL_RING_RED
		sb.set_border_width_all(1)
	else:
		sb.bg_color = Color(0.02, 0.02, 0.03, 0.55)
		sb.set_border_width_all(0)
	sb.content_margin_left = 9.0
	sb.content_margin_right = 9.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	card.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)

	var kcol := CT_COLOR if kteam == "CT" else T_COLOR
	var kl := _make_label(kname, 16, kcol)
	row.add_child(kl)

	var w_icon := _killfeed_weapon_icon(wid)
	if w_icon:
		var wtr := TextureRect.new()
		wtr.texture = w_icon
		wtr.custom_minimum_size = Vector2(30, 15)
		wtr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		wtr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		wtr.modulate = Color(0.95, 0.96, 0.97, 0.98)
		wtr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(wtr)
	else:
		row.add_child(_make_label(wid.to_upper(), 13, HUD_DIM))

	# One authoritative badge per confirmed fact; no guessed flags at HUD time.
	var flags := KillContext.confirmed(context, hs)
	for flag in KillContext.FLAGS:
		if not flags[flag]:
			continue
		var badge := TextureRect.new()
		badge.texture = KillContext.icon(flag)
		badge.custom_minimum_size = Vector2(20, 18)
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.tooltip_text = KillContext.BADGES[flag][2]
		row.add_child(badge)

	var vcol := CT_COLOR if vteam == "CT" else T_COLOR
	var vl := _make_label(vname, 16, vcol)
	row.add_child(vl)

	_killfeed_vbox.add_child(card)

	# Bottom-center kill card: only real enemy kills count (no suicides/TKs)
	if _killcards != null and is_my_kill and kname != vname and vteam != kteam:
		_killcards.register_kill(_killfeed_weapon_icon(wid), flags)

	# Appear at once (CS2), linger 5s (7.5s for your own rows), fade over 1s
	var hold: float = 7.5 if (is_my_kill or is_my_death) else 5.0
	var tw := card.create_tween()
	tw.tween_interval(hold)
	tw.tween_property(card, "modulate:a", 0.0, 1.0)
	tw.tween_callback(_forget_kill_card.bind(card))


func _forget_kill_card(card: Node) -> void:
	# Detach synchronously so the child-count cap can never spin forever,
	# then let Godot free it safely outside the tree.
	if is_instance_valid(card) and card.get_parent() == _killfeed_vbox:
		_killfeed_vbox.remove_child(card)
	card.queue_free()


func _killfeed_weapon_icon(wid: String) -> Texture2D:
	var archi_icon := _archi_weapon_texture(wid)
	if archi_icon != null:
		return archi_icon
	var entry := ""
	match wid:
		"hegrenade":
			entry = "d_grenade"
		"smokegrenade":
			entry = "d_grenade"
		"flashbang":
			entry = "d_flashbang"
		"c4":
			entry = "smallc4"
		"defuser":
			entry = "defuser"
		"m3super90":
			entry = "d_m3"
		_:
			entry = "d_" + wid
	var tex := GameData.get_hud_atlas(entry, 320) as Texture2D
	if tex == null and wid == "smokegrenade":
		tex = GameData.get_hud_atlas("d_grenade", 320)
	return tex


func _on_radio_chat(sname: String, steam: String, txt: String) -> void:
	while _radio_vbox.get_child_count() >= 5:
		var oldest := _radio_vbox.get_child(0)
		_radio_vbox.remove_child(oldest)
		oldest.queue_free()
	var col := CT_COLOR if steam == "CT" else T_COLOR

	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.055, 0.06, 0.075, 0.62)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	card.add_theme_stylebox_override("panel", sb)

	var lbl := _make_label("%s  %s" % [sname, txt], 13, col)
	card.add_child(lbl)
	_radio_vbox.add_child(card)
	var tw := card.create_tween()
	tw.tween_interval(6.5)
	tw.tween_property(card, "modulate:a", 0.0, 1.0)
	tw.tween_callback(card.queue_free)


func register_layout_element(id: String, control: Control) -> void:
	layout_elements[id] = control
	_layout_defaults[id] = {"anchors": [control.anchor_left, control.anchor_top, control.anchor_right, control.anchor_bottom], "offsets": [control.offset_left, control.offset_top, control.offset_right, control.offset_bottom]}


func apply_custom_layout() -> void:
	if not is_inside_tree():
		return
	var area := get_viewport().get_visible_rect().size
	for id in layout_elements:
		var control: Control = layout_elements[id]
		var original: Dictionary = _layout_defaults[id]
		for i in range(4):
			control.set_anchor(i, original.anchors[i])
			control.set_offset(i, original.offsets[i])
		control.scale = Vector2.ONE
		control.modulate.a = 1.0
		control.visible = true
		if not UICustomization.hud.has(id):
			continue
		var entry: Dictionary = UICustomization.hud[id]
		var base_size := control.size
		var factor := minf(float(entry.scale), minf(area.x / maxf(base_size.x, 1), area.y / maxf(base_size.y, 1)))
		var free := (area - base_size * factor).max(Vector2.ZERO)
		control.set_anchors_preset(Control.PRESET_TOP_LEFT)
		control.position = Vector2(entry.position) * free
		control.size = base_size
		control.scale = Vector2.ONE * factor
		control.modulate.a = float(entry.opacity)
		control.visible = bool(entry.visible)
