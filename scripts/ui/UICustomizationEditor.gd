class_name UICustomizationEditor
extends CanvasLayer
## One modal editor, shared by the WON options and the in-game command menu.
const NAMES := {"radar": "Radar", "status": "Compra / C4 / kit", "score": "Marcador y reloj", "killfeed": "Registro de bajas", "announcements": "Mensajes de ronda", "spectator": "Espectador", "progress": "Plantar / desactivar", "radio": "Radio y chat", "health": "Vida y armadura", "equipment": "Dinero, arma y munición"}
var before: Dictionary
var selected := "radar"
var hud_mode := false
var hud_preview: CSHud
var preview_viewport: SubViewport
var inspector: VBoxContainer
var preview_column: VBoxContainer
var handles: LayoutHandles
var message: Label
var simulation := false
var elapsed := 0.0
var old_mouse_mode: int
var closing := false
var preference_path := UICustomization.PATH
var _populating := false

static func open(parent: Node) -> UICustomizationEditor:
	for node in parent.get_tree().get_nodes_in_group("ui_customization_editor"):
		return node as UICustomizationEditor
	var editor := UICustomizationEditor.new()
	parent.add_child(editor)
	return editor

func _ready() -> void:
	add_to_group("ui_customization_editor")
	layer = 40
	before = UICustomization.snapshot()
	old_mouse_mode = Input.mouse_mode
	GameplayInputGate.acquire(self)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.018, 0.024, 0.031, 0.98)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "CONFIGURACIÓN  /  MIRA Y HUD"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.72, 0.16))
	column.add_child(title)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	button(tabs, "Mira", func(): show_tab(false))
	button(tabs, "HUD", func(): show_tab(true))
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	column.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 292
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector.add_theme_constant_override("separation", 8)
	scroll.add_child(inspector)
	preview_column = VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(preview_column)
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var footer := HBoxContainer.new()
	column.add_child(footer)
	button(footer, "Guardar", save_and_close)
	button(footer, "Cancelar / Esc", cancel)
	button(footer, "Restaurar esta pestaña", reset_tab)
	show_tab(false)

func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.custom_minimum_size.y = 34
	control.pressed.connect(action)
	parent.add_child(control)
	return control

func clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func show_tab(is_hud: bool) -> void:
	hud_mode = is_hud
	clear_children(preview_column)
	hud_preview = null
	handles = null
	if hud_mode:
		build_hud_preview()
	else:
		var canvas := Control.new()
		canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
		canvas.draw.connect(func():
			canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), Color(0.12, 0.15, 0.17))
			for x in range(0, int(canvas.size.x), 40):
				canvas.draw_line(Vector2(x, 0), Vector2(x, canvas.size.y), Color(1, 1, 1, 0.035))
			for y in range(0, int(canvas.size.y), 40):
				canvas.draw_line(Vector2(0, y), Vector2(canvas.size.x, y), Color(1, 1, 1, 0.035))
			var gap: float = UICustomization.crosshair.gap
			if simulation and GameData.dynamic_crosshair:
				gap += (sin(elapsed * 3) * 0.5 + 0.5) * 16
			CrosshairPainter.paint(canvas, canvas.size * 0.5, gap)
		)
		preview_column.add_child(canvas)
	message.text = "Arrastra los recuadros. Flechas: ajuste fino; Mayús: 10 px. Los ocultos siguen seleccionables." if hud_mode else "Vista previa con el mismo dibujado de la partida. No cambia la puntería, el retroceso ni la mira telescópica."
	populate_inspector()

func slider(text: String, low: float, high: float, step: float, value: float, action: Callable) -> void:
	var label := Label.new()
	label.text = "%s: %.2f" % [text, value]
	inspector.add_child(label)
	var control := HSlider.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.value = value
	control.value_changed.connect(func(v: float):
		label.text = "%s: %.2f" % [text, v]
		action.call(v)
	)
	inspector.add_child(control)

func check(text: String, value: bool, action: Callable) -> void:
	var control := CheckBox.new()
	control.text = text
	control.button_pressed = value
	control.toggled.connect(action)
	inspector.add_child(control)

func populate_inspector() -> void:
	_populating = true
	clear_children(inspector)
	if hud_mode:
		var selector := OptionButton.new()
		for key in NAMES:
			selector.add_item(NAMES[key])
		selector.select(NAMES.keys().find(selected))
		selector.item_selected.connect(func(index: int): select_element(NAMES.keys()[index]))
		inspector.add_child(selector)
		var entry := current_layout()
		slider("Escala", 0.5, 2.5, 0.05, entry.scale, func(v: float): update_layout("scale", v))
		slider("Opacidad", 0.2, 1, 0.05, entry.opacity, func(v: float): update_layout("opacity", v))
		check("Mostrar elemento", entry.visible, func(v: bool): update_layout("visible", v))
		button(inspector, "Restaurar elemento", func():
			UICustomization.hud.erase(selected)
			UICustomization.changed.emit()
			populate_inspector()
		)
	else:
		for key in ["length", "gap", "width", "outline"]:
			var captions := {"length": "Largo", "gap": "Separación", "width": "Grosor", "outline": "Contorno"}
			var limits := {"length": Vector2(1, 30), "gap": Vector2(0, 30), "width": Vector2(1, 8), "outline": Vector2(0, 4)}
			slider(captions[key], limits[key].x, limits[key].y, 0.1, UICustomization.crosshair[key], func(v: float):
				UICustomization.crosshair[key] = v
				UICustomization.changed.emit()
			)
		check("Mostrar mira", UICustomization.crosshair.enabled, func(v: bool): set_crosshair("enabled", v))
		check("Punto central", UICustomization.crosshair.dot, func(v: bool): set_crosshair("dot", v))
		check("Forma de T", UICustomization.crosshair.t_shape, func(v: bool): set_crosshair("t_shape", v))
		check("Mira dinámica", GameData.dynamic_crosshair, func(v: bool): GameData.dynamic_crosshair = v; UICustomization.changed.emit())
		check("Simular movimiento / disparos", simulation, func(v: bool): simulation = v)
		var color_caption := Label.new()
		color_caption.text = "Color y transparencia"
		inspector.add_child(color_caption)
		var color := ColorPickerButton.new()
		color.color = GameData.crosshair_color
		color.text = "Color y transparencia"
		color.custom_minimum_size.y = 36
		color.color_changed.connect(func(v: Color): GameData.crosshair_color = v; UICustomization.changed.emit())
		inspector.add_child(color)
	_populating = false

func set_crosshair(key: String, value: Variant) -> void:
	UICustomization.crosshair[key] = value
	UICustomization.changed.emit()

func build_hud_preview() -> void:
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 16.0 / 9.0
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(aspect)
	var container := SubViewportContainer.new()
	container.stretch = true
	aspect.add_child(container)
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(1280, 720)
	preview_viewport.disable_3d = true
	preview_viewport.size_2d_override = Vector2i(1280, 720)
	preview_viewport.size_2d_override_stretch = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(preview_viewport)
	var background := ColorRect.new()
	background.color = Color(0.10, 0.13, 0.15)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_viewport.add_child(background)
	hud_preview = CSHud.new()
	hud_preview.preview_mode = true
	preview_viewport.add_child(hud_preview)
	hud_preview.set_process(false)
	hud_preview._hp_label.text = "100"
	hud_preview._armor_label.text = "100"
	hud_preview._money_label.text = "$ 3200"
	hud_preview._weapon_name_label.text = "AK-47"
	hud_preview._weapon_icon.texture = GameData.get_weapon_hud_atlas("ak47", "weapon_s_640")
	hud_preview._ammo_label.text = "30"
	hud_preview._ammo_reserve_label.text = "90"
	hud_preview._center_label.text = "Ronda de ejemplo"
	hud_preview._spec_label.text = "Espectando: compañero"
	hud_preview._progress_title.text = "Desactivando C4"
	hud_preview._progress_bar.visible = true
	hud_preview._progress_bar.value = 0.6
	for pair in [[hud_preview._killfeed_vbox, "Jugador    AK-47    Rival"], [hud_preview._radio_vbox, "[Radio] ¡Cubridme!"]]:
		var label := Label.new()
		label.text = pair[1]
		pair[0].add_child(label)
	var overlay := CanvasLayer.new()
	overlay.layer = 6
	preview_viewport.add_child(overlay)
	handles = LayoutHandles.new()
	handles.editor = self
	handles.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(handles)
	hud_preview.apply_custom_layout.call_deferred()

func current_layout() -> Dictionary:
	if UICustomization.hud.has(selected):
		return UICustomization.hud[selected].duplicate(true)
	var pos := Vector2(0.5, 0.5)
	if is_instance_valid(hud_preview):
		var target: Control = hud_preview.layout_elements[selected]
		var free := (preview_viewport.get_visible_rect().size - target.size).max(Vector2.ONE)
		pos = (target.position / free).clamp(Vector2.ZERO, Vector2.ONE)
	return {"position": pos, "scale": 1.0, "opacity": 1.0, "visible": true}

func select_element(id: String) -> void:
	selected = id
	populate_inspector()

func update_layout(key: String, value: Variant) -> void:
	var entry := current_layout()
	entry[key] = value
	UICustomization.hud[selected] = entry
	UICustomization.changed.emit()

func move_element(position: Vector2) -> void:
	var target: Control = hud_preview.layout_elements[selected]
	var free := (preview_viewport.get_visible_rect().size - target.size * target.scale).max(Vector2.ONE)
	update_layout("position", (position / free).clamp(Vector2.ZERO, Vector2.ONE))

func reset_tab() -> void:
	if hud_mode:
		UICustomization.hud.clear()
		UICustomization.changed.emit()
	else:
		UICustomization.reset_crosshair()
	populate_inspector()

func save_and_close() -> void:
	if closing:
		return
	var result := UICustomization.save_preferences(preference_path)
	if result != OK:
		message.text = "No se pudo guardar (%s). Los cambios siguen en vista previa." % error_string(result)
		return
	closing = true
	queue_free()

func cancel() -> void:
	if closing:
		return
	UICustomization.restore(before)
	closing = true
	queue_free()

func _exit_tree() -> void:
	if not closing:
		UICustomization.restore(before)
	GameplayInputGate.release(self)

func _input(event: InputEvent) -> void:
	if closing:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			cancel()
		elif hud_mode and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			var movement := Vector2.ZERO
			match event.keycode:
				KEY_LEFT: movement.x = -1
				KEY_RIGHT: movement.x = 1
				KEY_UP: movement.y = -1
				KEY_DOWN: movement.y = 1
			var target: Control = hud_preview.layout_elements[selected]
			move_element(target.position + movement * (10 if event.shift_pressed else 1))
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	elapsed += delta
	if hud_mode and is_instance_valid(handles):
		handles.queue_redraw()
	elif preview_column.get_child_count() > 0:
		preview_column.get_child(0).queue_redraw()

class LayoutHandles extends Control:
	var editor: UICustomizationEditor
	var dragging := false
	var drag_offset := Vector2.ZERO

	func _draw() -> void:
		for id in editor.hud_preview.layout_elements:
			var target: Control = editor.hud_preview.layout_elements[id]
			var rect := Rect2(target.position, target.size * target.scale)
			var color := Color(1, 0.72, 0.16, 0.95) if id == editor.selected else Color(0.6, 0.75, 0.85, 0.45)
			draw_rect(rect, color, false, 2)
			draw_string(get_theme_default_font(), rect.position + Vector2(4, 14), editor.NAMES[id], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x, 12, color)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = false
			if event.pressed:
				var keys: Array = editor.hud_preview.layout_elements.keys()
				keys.reverse()
				for id in keys:
					var target: Control = editor.hud_preview.layout_elements[id]
					if Rect2(target.position, target.size * target.scale).grow(4).has_point(event.position):
						editor.select_element(id)
						drag_offset = event.position - target.position
						dragging = true
						break
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			editor.move_element(event.position - drag_offset)
			accept_event()
