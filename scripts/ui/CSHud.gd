class_name CSHud
extends CanvasLayer
## Authentic Counter-Strike 1.5 HUD built programmatically with extracted GoldSrc sprites.

const AMBER := Color(1.0, 0.63, 0.0, 0.92)
const RED_WARN := Color(1.0, 0.18, 0.12, 0.95)
const GREEN_HUD := Color(0.18, 0.95, 0.25, 0.92)
const CT_COLOR := Color(0.58, 0.80, 1.0, 1.0)
const T_COLOR := Color(1.0, 0.32, 0.28, 1.0)

var player: PlayerController = null

var _nvg_rect: ColorRect = null
var _scope_root: Control = null
var _smoke_rect: ColorRect = null
var _flash_rect: ColorRect = null
var _crosshair_ctrl: Control = null
var _radar_ctrl: Control = null

var _hp_label: Label = null
var _armor_label: Label = null
var _timer_label: Label = null
var _money_label: Label = null
var _money_delta_label: Label = null
var _ammo_label: Label = null
var _weapon_name_label: Label = null
var _center_label: Label = null
var _spec_label: Label = null
var _progress_bar: ProgressBar = null
var _progress_title: Label = null

var _icon_buyzone: TextureRect = null
var _icon_c4: TextureRect = null
var _icon_defuser: TextureRect = null
var _weapon_banner_icon: TextureRect = null
var _weapon_banner_panel: PanelContainer = null

var _killfeed_vbox: VBoxContainer = null
var _radio_vbox: VBoxContainer = null

var _center_timer: float = 0.0
var _money_delta_timer: float = 0.0
var _banner_timer: float = 0.0
var _c4_blink_phase: float = 0.0
var _pain_flash_alpha: float = 0.0
var _crosshair_gap_cur: float = 5.0
var _damage_arcs: Array = []
var _is_bomb_planted: bool = false
var _bomb_pos: Vector3 = Vector3.ZERO


func _ready() -> void:
	layer = 5
	_build_hud_tree()

	RoundManager.center_message.connect(_on_center_message)
	RoundManager.kill_logged.connect(_on_kill_logged)
	RoundManager.chat_radio_message.connect(_on_radio_chat)
	RoundManager.bomb_state_changed.connect(_on_bomb_state_changed)


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

	# 4. Top-Left Circular Radar (with overview map + dots)
	_radar_ctrl = Control.new()
	_radar_ctrl.position = Vector2(18, 18)
	_radar_ctrl.size = Vector2(156, 156)
	_radar_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radar_ctrl.draw.connect(_draw_radar)
	root.add_child(_radar_ctrl)

	# 5. Left Status Icons (Buyzone, C4, Defuser)
	var left_icons := VBoxContainer.new()
	left_icons.position = Vector2(22, 195)
	left_icons.add_theme_constant_override("separation", 10)
	left_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(left_icons)

	_icon_buyzone = _make_hud_icon("buyzone", GREEN_HUD)
	_icon_c4 = _make_hud_icon("c4", GREEN_HUD)
	_icon_defuser = _make_hud_icon("defuser", GREEN_HUD)
	left_icons.add_child(_icon_buyzone)
	left_icons.add_child(_icon_c4)
	left_icons.add_child(_icon_defuser)

	# 6. Top Weapon Switch Banner
	_weapon_banner_panel = PanelContainer.new()
	_weapon_banner_panel.anchor_left = 0.5
	_weapon_banner_panel.anchor_right = 0.5
	_weapon_banner_panel.offset_left = -105
	_weapon_banner_panel.offset_right = 105
	_weapon_banner_panel.offset_top = 18
	_weapon_banner_panel.offset_bottom = 78
	_weapon_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.65)
	sb.border_color = AMBER
	sb.set_border_width_all(1)
	_weapon_banner_panel.add_theme_stylebox_override("panel", sb)
	_weapon_banner_icon = TextureRect.new()
	_weapon_banner_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_banner_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_banner_icon.modulate = AMBER
	_weapon_banner_panel.add_child(_weapon_banner_icon)
	_weapon_banner_panel.visible = false
	root.add_child(_weapon_banner_panel)

	# 7. Top-Right Killfeed
	_killfeed_vbox = VBoxContainer.new()
	_killfeed_vbox.anchor_left = 1.0
	_killfeed_vbox.anchor_right = 1.0
	_killfeed_vbox.offset_left = -410
	_killfeed_vbox.offset_right = -18
	_killfeed_vbox.offset_top = 18
	_killfeed_vbox.offset_bottom = 200
	_killfeed_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_killfeed_vbox)

	# 8. Center CS 1.5 Round / Bomb Announcement Label + Plant/Defuse Bar
	_center_label = _make_label("", 24, AMBER)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.anchor_left = 0.2
	_center_label.anchor_right = 0.8
	_center_label.anchor_top = 0.30
	_center_label.anchor_bottom = 0.42
	root.add_child(_center_label)

	_spec_label = _make_label("", 18, Color(0.95, 0.9, 0.7))
	_spec_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spec_label.anchor_left = 0.25
	_spec_label.anchor_right = 0.75
	_spec_label.anchor_top = 0.80
	_spec_label.anchor_bottom = 0.86
	root.add_child(_spec_label)

	var prog_box := VBoxContainer.new()
	prog_box.anchor_left = 0.36
	prog_box.anchor_right = 0.64
	prog_box.anchor_top = 0.58
	prog_box.anchor_bottom = 0.65
	prog_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prog_box)

	_progress_title = _make_label("", 16, AMBER)
	_progress_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prog_box.add_child(_progress_title)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(260, 16)
	_progress_bar.visible = false
	prog_box.add_child(_progress_bar)

	# 9. Bottom-Left Radio / Chat Feed
	_radio_vbox = VBoxContainer.new()
	_radio_vbox.anchor_top = 1.0
	_radio_vbox.anchor_bottom = 1.0
	_radio_vbox.offset_left = 22
	_radio_vbox.offset_right = 520
	_radio_vbox.offset_top = -235
	_radio_vbox.offset_bottom = -95
	_radio_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_radio_vbox)

	# 10. Bottom GoldSrc Bar: HP + Armor | Round Timer | Money + Ammo
	var bot_left := HBoxContainer.new()
	bot_left.anchor_top = 1.0
	bot_left.anchor_bottom = 1.0
	bot_left.offset_left = 24
	bot_left.offset_right = 360
	bot_left.offset_top = -66
	bot_left.offset_bottom = -16
	bot_left.add_theme_constant_override("separation", 24)
	bot_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bot_left)

	var hp_row := HBoxContainer.new()
	var cross_ic := _make_hud_icon("cross", AMBER, Vector2(24, 24))
	_hp_label = _make_label("100", 32, AMBER)
	hp_row.add_child(cross_ic)
	hp_row.add_child(_hp_label)
	bot_left.add_child(hp_row)

	var ap_row := HBoxContainer.new()
	var shield_lbl := _make_label("AP ", 20, AMBER)
	_armor_label = _make_label("0", 32, AMBER)
	ap_row.add_child(shield_lbl)
	ap_row.add_child(_armor_label)
	bot_left.add_child(ap_row)

	# Center Timer
	var timer_row := HBoxContainer.new()
	timer_row.anchor_left = 0.5
	timer_row.anchor_right = 0.5
	timer_row.anchor_top = 1.0
	timer_row.anchor_bottom = 1.0
	timer_row.offset_left = -75
	timer_row.offset_right = 75
	timer_row.offset_top = -64
	timer_row.offset_bottom = -16
	timer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	timer_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw_ic := _make_hud_icon("stopwatch", AMBER, Vector2(24, 24))
	_timer_label = _make_label("02:15", 30, AMBER)
	timer_row.add_child(sw_ic)
	timer_row.add_child(_timer_label)
	root.add_child(timer_row)

	# Bottom Right: Money above Ammo
	var bot_right := VBoxContainer.new()
	bot_right.anchor_left = 1.0
	bot_right.anchor_right = 1.0
	bot_right.anchor_top = 1.0
	bot_right.anchor_bottom = 1.0
	bot_right.offset_left = -320
	bot_right.offset_right = -24
	bot_right.offset_top = -196
	bot_right.offset_bottom = -20
	bot_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bot_right.alignment = BoxContainer.ALIGNMENT_END
	bot_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bot_right)

	_money_delta_label = _make_label("", 20, GREEN_HUD)
	_money_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bot_right.add_child(_money_delta_label)

	_money_label = _make_label("$ 800", 28, AMBER)
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bot_right.add_child(_money_label)

	_weapon_name_label = _make_label("USP .45", 14, Color(1.0, 0.78, 0.35, 0.85))
	_weapon_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bot_right.add_child(_weapon_name_label)

	_ammo_label = _make_label("12 | 24", 32, AMBER)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bot_right.add_child(_ammo_label)

	# 11. Inside-Smoke Volumetric Immersion Overlay + Flashbang Fullscreen Whiteout
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


func _make_hud_icon(entry: String, tint: Color, sz: Vector2 = Vector2(32, 32)) -> TextureRect:
	var icon_rect := TextureRect.new()
	icon_rect.texture = GameData.get_hud_atlas(entry, 320)
	icon_rect.custom_minimum_size = sz
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.modulate = tint
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon_rect


func _make_label(txt: String, fsize: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	_c4_blink_phase += delta * 6.0

	if _center_timer > 0.0:
		_center_timer -= delta
		if _center_timer <= 0.0:
			_center_label.text = ""

	if _money_delta_timer > 0.0:
		_money_delta_timer -= delta
		if _money_delta_timer <= 0.0:
			_money_delta_label.text = ""

	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_weapon_banner_panel.visible = false

	if _pain_flash_alpha > 0.0:
		_pain_flash_alpha = maxf(0.0, _pain_flash_alpha - delta * 2.4)

	for di in range(_damage_arcs.size() - 1, -1, -1):
		var arc_d := _damage_arcs[di] as Dictionary
		var next_a: float = float(arc_d["alpha"]) - delta * 1.15
		if next_a <= 0.01:
			_damage_arcs.remove_at(di)
		else:
			arc_d["alpha"] = next_a

	# Timer formatting
	var secs := maxi(0, int(ceil(RoundManager.state_timer)))
	if is_instance_valid(RoundManager.planted_c4):
		secs = maxi(0, int(ceil((RoundManager.planted_c4 as PlantedC4).time_left)))
		_timer_label.add_theme_color_override("font_color", RED_WARN if sin(_c4_blink_phase * 2.0) > 0.0 else AMBER)
	else:
		_timer_label.add_theme_color_override("font_color", RED_WARN if secs <= 10 else AMBER)
	var mins := int(floor(float(secs) / 60.0))
	_timer_label.text = "%02d:%02d" % [mins, secs % 60]

	if is_instance_valid(player):
		var smoke_d := RoundManager.get_smoke_density_at(player.get_eye_position()) if player.is_alive else 0.0
		_smoke_rect.color.a = lerpf(_smoke_rect.color.a, clampf(smoke_d * 0.97, 0.0, 0.97), minf(1.0, delta * 9.0))
		var fl_raw: float = clampf(player.flash_alpha, 0.0, 1.35)
		_flash_rect.color.a = clampf(pow(fl_raw, 0.78), 0.0, 1.0)
		_icon_buyzone.visible = player.can_use_buy_menu()
		var carries_c4 := String(player.weapon_ctrl.slots.get(5, "")) == "c4"
		_icon_c4.visible = carries_c4
		if carries_c4 and is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_bombsite"):
			if bool(RoundManager.game_world.call("is_in_bombsite", player.global_position)):
				_icon_c4.modulate = RED_WARN if sin(_c4_blink_phase * 2.5) > 0.0 else GREEN_HUD
			else:
				_icon_c4.modulate = GREEN_HUD
		_icon_defuser.visible = player.has_defuser

		var target_gap := 5.0
		if GameData.dynamic_crosshair and player.is_alive:
			var spd := Vector2(player.velocity.x, player.velocity.z).length()
			target_gap += spd * 1.35 + float(player.weapon_ctrl.shots_fired) * 1.65 + player.weapon_ctrl.punch_angles.length() * 0.85
			if not player.is_on_floor():
				target_gap += 9.0
			elif player.is_crouching:
				target_gap *= 0.72
		_crosshair_gap_cur = lerpf(_crosshair_gap_cur, target_gap, minf(1.0, 22.0 * delta))

	_crosshair_ctrl.queue_redraw()
	_radar_ctrl.queue_redraw()


func _draw_crosshair() -> void:
	if not is_instance_valid(player):
		return
	var sz := _crosshair_ctrl.size
	var center := sz * 0.5

	# 1. Subtle crimson pain flash & low-HP warning edge vignette
	var low_hp_pulse: float = 0.0
	if player.is_alive and player.health <= 25:
		low_hp_pulse = (0.5 + 0.5 * sin(_c4_blink_phase * 1.35)) * 0.14
	var vig_a: float = clampf(_pain_flash_alpha * 0.34 + low_hp_pulse, 0.0, 0.42)
	if vig_a > 0.005:
		var edge_w: float = minf(sz.x, sz.y) * 0.09
		var vcol := Color(0.88, 0.06, 0.04, vig_a)
		_crosshair_ctrl.draw_rect(Rect2(0.0, 0.0, sz.x, edge_w), vcol)
		_crosshair_ctrl.draw_rect(Rect2(0.0, sz.y - edge_w, sz.x, edge_w), vcol)
		_crosshair_ctrl.draw_rect(Rect2(0.0, edge_w, edge_w, sz.y - edge_w * 2.0), vcol)
		_crosshair_ctrl.draw_rect(Rect2(sz.x - edge_w, edge_w, edge_w, sz.y - edge_w * 2.0), vcol)

	# 2. Classic CS 1.5 Directional Damage Indicator Arcs around reticle
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
				# Screen angle: forward (-Z) -> -PI/2 (top), right (+X) -> 0 (right), back (+Z) -> +PI/2 (bottom)
				var ang: float = atan2(local_v.z, local_v.x)
				_crosshair_ctrl.draw_arc(center, arc_r, ang - 0.42, ang + 0.42, 20, acol, 6.5)
			else:
				_crosshair_ctrl.draw_arc(center, arc_r, 0.0, TAU, 40, Color(1.0, 0.16, 0.10, a_val * 0.55), 5.0)

	if not player.is_alive or _scope_root.visible:
		return

	var gap := _crosshair_gap_cur
	var seg := 8.0
	var col := GameData.crosshair_color
	var shadow := Color(0.0, 0.0, 0.0, col.a * 0.55)
	_crosshair_ctrl.draw_line(center + Vector2(-gap - seg, 0), center + Vector2(-gap, 0), shadow, 3.2)
	_crosshair_ctrl.draw_line(center + Vector2(gap, 0), center + Vector2(gap + seg, 0), shadow, 3.2)
	_crosshair_ctrl.draw_line(center + Vector2(0, -gap - seg), center + Vector2(0, -gap), shadow, 3.2)
	_crosshair_ctrl.draw_line(center + Vector2(0, gap), center + Vector2(0, gap + seg), shadow, 3.2)
	_crosshair_ctrl.draw_line(center + Vector2(-gap - seg, 0), center + Vector2(-gap, 0), col, 1.8)
	_crosshair_ctrl.draw_line(center + Vector2(gap, 0), center + Vector2(gap + seg, 0), col, 1.8)
	_crosshair_ctrl.draw_line(center + Vector2(0, -gap - seg), center + Vector2(0, -gap), col, 1.8)
	_crosshair_ctrl.draw_line(center + Vector2(0, gap), center + Vector2(0, gap + seg), col, 1.8)


func _draw_sniper_scope() -> void:
	var sz := _scope_root.size
	var c := sz * 0.5
	var r := minf(sz.x, sz.y) * 0.43
	var blk := Color(0, 0, 0, 0.96)
	# Outer dark letterboxes + crosshair lines
	_scope_root.draw_rect(Rect2(0, 0, c.x - r, sz.y), blk)
	_scope_root.draw_rect(Rect2(c.x + r, 0, sz.x - (c.x + r), sz.y), blk)
	_scope_root.draw_rect(Rect2(c.x - r, 0, r * 2.0, maxf(0.0, c.y - r)), blk)
	_scope_root.draw_rect(Rect2(c.x - r, c.y + r, r * 2.0, maxf(0.0, sz.y - (c.y + r))), blk)
	_scope_root.draw_arc(c, r, 0.0, TAU, 96, Color(0, 0, 0, 1.0), 6.0)
	_scope_root.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0, 0, 0, 0.9), 1.5)
	_scope_root.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y + r), Color(0, 0, 0, 0.9), 1.5)
	_scope_root.draw_circle(c, 2.5, Color(1.0, 0.15, 0.1, 0.9))


func _draw_radar() -> void:
	var c := _radar_ctrl.size * 0.5
	var r := c.x - 4.0
	_radar_ctrl.draw_circle(c, r, Color(0.03, 0.16, 0.06, 0.62))
	_radar_ctrl.draw_arc(c, r, 0.0, TAU, 48, Color(0.25, 0.85, 0.35, 0.72), 1.6)
	_radar_ctrl.draw_line(Vector2(c.x, c.y - r), Vector2(c.x, c.y), Color(0.3, 0.9, 0.4, 0.45), 1.0)
	_radar_ctrl.draw_line(Vector2(c.x - r, c.y), Vector2(c.x + r, c.y), Color(0.2, 0.6, 0.3, 0.25), 1.0)

	if not is_instance_valid(player):
		return

	var scale_px_per_m := r / 38.0
	var ppos := player.global_position
	var pyaw := player.look_yaw

	for a in RoundManager.actors:
		if not is_instance_valid(a) or a == player or not bool(a.get("is_alive")):
			continue
		if String(a.get("team")) != player.team:
			continue
		var pt := _world_to_radar(a.global_position, ppos, pyaw, scale_px_per_m, r - 4.0)
		var dcol := Color(0.35, 0.95, 1.0) if bool(a.get("is_vip")) else Color(0.3, 1.0, 0.4)
		_radar_ctrl.draw_circle(c + pt, 3.2, dcol)

	for h in RoundManager.hostages:
		if is_instance_valid(h) and h.is_alive and not h.is_rescued:
			var hp := _world_to_radar(h.global_position, ppos, pyaw, scale_px_per_m, r - 4.0)
			_radar_ctrl.draw_circle(c + hp, 3.0, Color(0.4, 0.8, 1.0))

	if _is_bomb_planted and sin(_c4_blink_phase * 2.5) > -0.2:
		var bp := _world_to_radar(_bomb_pos, ppos, pyaw, scale_px_per_m, r - 4.0)
		_radar_ctrl.draw_circle(c + bp, 4.5, RED_WARN)


func _world_to_radar(target: Vector3, origin: Vector3, yaw: float, scale_f: float, max_r: float) -> Vector2:
	var rel := target - origin
	var local_v := Basis(Vector3.UP, -yaw) * rel
	var v2 := Vector2(local_v.x, local_v.z) * scale_f
	if v2.length() > max_r:
		v2 = v2.normalized() * max_r
	return v2


func _on_hp_armor(hp: int, ap: int, helmet: bool) -> void:
	_hp_label.text = str(hp)
	_hp_label.add_theme_color_override("font_color", RED_WARN if hp <= 25 else AMBER)
	_armor_label.text = ("%d [H]" % ap) if (helmet and ap > 0) else str(ap)


func _on_money(amount: int, delta_amt: int) -> void:
	_money_label.text = "$ %d" % amount
	if delta_amt != 0:
		_money_delta_label.text = ("+$%d" % delta_amt) if delta_amt > 0 else ("-$%d" % abs(delta_amt))
		_money_delta_label.add_theme_color_override("font_color", GREEN_HUD if delta_amt > 0 else RED_WARN)
		_money_delta_timer = 2.4


func _on_weapon_switched(wid: String, spec: Dictionary) -> void:
	var title := String(spec.get("name", wid.to_upper()))
	if bool(spec.get("silencer", false)) and is_instance_valid(player):
		if bool(player.weapon_ctrl.silenced_state.get(wid, false)):
			title += " [SILENCED]"
	_weapon_name_label.text = title

	var whud := GameData.get_weapon_hud_atlas(wid, "weapon_s_640")
	if not whud:
		whud = GameData.get_weapon_hud_atlas(wid, "weapon_640")
	if whud:
		_weapon_banner_icon.texture = whud
		_weapon_banner_panel.visible = true
		_banner_timer = 1.6


func _on_ammo_updated(clip: int, reserve: int) -> void:
	if clip < 0:
		_ammo_label.text = "---"
	else:
		_ammo_label.text = "%d | %d" % [clip, reserve]


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


func _on_nvg_toggled(active: bool) -> void:
	_nvg_rect.visible = active


func _on_spec_changed(tname: String) -> void:
	_spec_label.text = ("Spectating: " + tname + "  [Mouse1: Next]") if not tname.is_empty() else ""


func _on_bomb_state_changed(planted: bool, pos: Vector3) -> void:
	_is_bomb_planted = planted
	_bomb_pos = pos


func _on_player_damaged(source_pos: Vector3, dmg_amount: int, directional: bool) -> void:
	var strength: float = clampf(0.45 + float(dmg_amount) / 55.0, 0.45, 1.0)
	_pain_flash_alpha = clampf(maxf(_pain_flash_alpha, strength), 0.0, 1.0)
	while _damage_arcs.size() >= 6:
		_damage_arcs.pop_front()
	_damage_arcs.append({
		"pos": source_pos,
		"directional": directional,
		"alpha": strength,
	})


func _on_kill_logged(kname: String, kteam: String, vname: String, vteam: String, wid: String, hs: bool) -> void:
	while _killfeed_vbox.get_child_count() >= 5:
		_killfeed_vbox.get_child(0).queue_free()

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 6)

	var kl := _make_label(kname, 14, CT_COLOR if kteam == "CT" else T_COLOR)
	var wl := _make_label("[%s%s]" % [wid.to_upper(), " HS" if hs else ""], 13, AMBER)
	var vl := _make_label(vname, 14, CT_COLOR if vteam == "CT" else T_COLOR)
	row.add_child(kl)
	row.add_child(wl)
	row.add_child(vl)
	_killfeed_vbox.add_child(row)

	var tw := row.create_tween()
	tw.tween_interval(6.0)
	tw.tween_property(row, "modulate:a", 0.0, 1.0)
	tw.tween_callback(row.queue_free)


func _on_radio_chat(sname: String, steam: String, txt: String) -> void:
	while _radio_vbox.get_child_count() >= 5:
		_radio_vbox.get_child(0).queue_free()
	var col := CT_COLOR if steam == "CT" else T_COLOR
	var lbl := _make_label("%s %s" % [sname, txt], 14, col)
	_radio_vbox.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_interval(6.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.0)
	tw.tween_callback(lbl.queue_free)
