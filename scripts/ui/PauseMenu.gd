class_name PauseMenu
extends CanvasLayer
## In-Game Pause / Command Menu (Esc key): Resume, Change Team, Add/Remove Bots, Restart Round, Main Menu.

signal resume_requested()
signal change_team_requested()
signal add_bot_requested(team_str: String)
signal restart_round_requested()
signal exit_to_main_menu_requested()

const AMBER := Color(1.0, 0.68, 0.12)

var is_open: bool = false


func _ready() -> void:
	layer = 16
	visible = false

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.55)
	add_child(bg)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -190
	panel.offset_right = 190
	panel.offset_top = -180
	panel.offset_bottom = 180
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.94)
	sb.border_color = AMBER
	sb.set_border_width_all(2)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "COUNTER-STRIKE 1.5"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", AMBER)
	vbox.add_child(title)

	_make_btn(vbox, "Resume Game", func(): close_pause(); resume_requested.emit())
	_make_btn(vbox, "Editor de mira y HUD", func(): UICustomizationEditor.open(self))
	_make_btn(vbox, "Choose Team (M)", func(): close_pause(); change_team_requested.emit())
	_make_btn(vbox, "+ Add CT Bot", func(): add_bot_requested.emit("CT"))
	_make_btn(vbox, "+ Add Terrorist Bot", func(): add_bot_requested.emit("T"))
	_make_btn(vbox, "Restart Match (sv_restart 1)", func(): close_pause(); restart_round_requested.emit())
	_make_btn(vbox, "Disconnect to Main Menu", func(): close_pause(); exit_to_main_menu_requested.emit())


func _make_btn(parent: VBoxContainer, txt: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_color_override("font_color", AMBER)
	b.pressed.connect(func():
		AudioManager.play_ui("launch_select1.wav")
		cb.call()
	)
	parent.add_child(b)


func open_pause() -> void:
	is_open = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func close_pause() -> void:
	is_open = false
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
