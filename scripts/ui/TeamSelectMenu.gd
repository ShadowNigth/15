class_name TeamSelectMenu
extends CanvasLayer
## Two cosmetic classic actors over the live map. Team is chosen; class is random.
## No CSActor instances: previews must never register combatants or run weapon AI.
signal team_class_chosen(team_str: String, class_str: String)

const COLORS := {"T": Color("dfba70"), "CT": Color("a9c7dc")}
const PREVIEW_CLASSES := {"T": "terror", "CT": "sas"}
var is_open: bool = false
var _committing: bool = false
var _rng := RandomNumberGenerator.new()
var _buttons: Dictionary = {}
var _viewports: Dictionary = {}
var _animations: Dictionary = {}
var _emblems: Dictionary = {}
var _models: Dictionary = {}
var _cameras: Dictionary = {}
var _root: Control

func _ready() -> void:
	layer = 14
	visible = false
	_rng.randomize() # Private RNG: opening/hovering never consumes gameplay randomness.
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
void fragment() {
 vec3 tint = mix(vec3(0.16, 0.115, 0.055), vec3(0.045, 0.10, 0.17), UV.x);
 float edge = pow(abs(UV.x - 0.5) * 2.0, 2.0);
 COLOR = vec4(tint, 0.24 + 0.20 * UV.y + 0.12 * edge);
}"""
	var material := ShaderMaterial.new()
	material.shader = shader
	shade.material = material
	_root.add_child(shade)
	for tm in ["T", "CT"]:
		_build_choice(tm)
	(_buttons["T"] as Button).focus_neighbor_right = (_buttons["CT"] as Button).get_path()
	(_buttons["CT"] as Button).focus_neighbor_left = (_buttons["T"] as Button).get_path()

func _build_choice(tm: String) -> void:
	var button := Button.new()
	button.name = "Choose" + tm
	button.text = ""
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.anchor_left = 0.04 if tm == "T" else 0.54
	button.anchor_right = 0.46 if tm == "T" else 0.96
	button.anchor_top = 0.06
	button.anchor_bottom = 0.98
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color(COLORS[tm], 0.6)
	focus.border_width_bottom = 2
	button.add_theme_stylebox_override("focus", focus)
	_root.add_child(button)
	_buttons[tm] = button

	var container := SubViewportContainer.new()
	container.name = "Character"
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.anchor_top = 0.22
	container.stretch = true
	button.add_child(container)
	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	_viewports[tm] = viewport

	var emblem := TextureRect.new()
	emblem.texture = load("res://assets/ui/teams/" + tm.to_lower() + ".svg")
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.anchor_left = 0.35
	emblem.anchor_right = 0.65
	emblem.anchor_top = 0.02
	emblem.anchor_bottom = 0.20
	button.add_child(emblem)
	_emblems[tm] = emblem
	button.pressed.connect(_choose_team.bind(tm))
	button.mouse_entered.connect(func():
		if is_open:
			AudioManager.play_ui("launch_glow1.wav")
			_set_highlight(tm, true)
	)
	button.mouse_exited.connect(func(): _set_highlight(tm, button.has_focus()))
	button.focus_entered.connect(func(): _set_highlight(tm, true))
	button.focus_exited.connect(func(): _set_highlight(tm, false))

func _set_highlight(tm: String, highlighted: bool) -> void:
	(_emblems[tm] as TextureRect).modulate = Color(1.25, 1.25, 1.25) if highlighted else Color.WHITE

func _build_preview(tm: String) -> void:
	var viewport := _viewports[tm] as SubViewport
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.83, 0.87, 0.93)
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-25, -25, 0)
	key.light_color = Color(1.0, 0.91, 0.77) if tm == "T" else Color(0.82, 0.91, 1.0)
	key.light_energy = 1.8
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.2, 1.8, 2.3)
	fill.omni_range = 8.0
	fill.light_energy = 1.5
	stage.add_child(fill)
	var camera := Camera3D.new()
	camera.fov = 39.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(0, 1.10, 3.7), Vector3(0, 1.08, 0), Vector3.UP)
	camera.current = true
	_cameras[tm] = camera
	var scene := GameData.get_model_scene("players/" + String(PREVIEW_CLASSES[tm]))
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	stage.add_child(model)
	# Classic clips are authored around the GoldSrc hull centre, not the feet.
	model.position.y = 0.0
	model.rotation.y = PI + (-0.14 if tm == "T" else 0.14)
	_models[tm] = model
	_style_meshes(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	var animation := players[0] as AnimationPlayer
	_animations[tm] = animation
	# Lower-body idle tracks keep the native upper-body rifle stance applied here.
	var aim := "ref_aim_ak47" if tm == "T" else "ref_aim_carbine"
	if animation.has_animation(aim):
		animation.play(aim)
		animation.advance(0.0)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		var hand_name := "hand_R" if ModernAgentPose.is_modern(skeleton) else "Bip01 R Hand"
		if skeleton.find_bone(hand_name) >= 0:
			var hand := BoneAttachment3D.new()
			hand.bone_name = hand_name
			skeleton.add_child(hand)
			var weapon := GameData.get_model_scene("weapons/p_ak47" if tm == "T" else "weapons/p_m4a1")
			if weapon != null:
				var prop := weapon.instantiate()
				hand.add_child(prop)
				if ModernAgentPose.is_modern(skeleton):
					ModernAgentPose.fit_prop(prop, ModernAgentPose.role(tm), "ak47" if tm == "T" else "m4a1")
				_style_meshes(prop)
	if animation.has_animation("idle1"):
		# Do not mutate the shared imported animation resource.
		var idle := _combined_idle(animation, skeletons[0] as Skeleton3D, aim)
		idle.loop_mode = Animation.LOOP_LINEAR
		var library := AnimationLibrary.new()
		library.add_animation("idle", idle)
		animation.add_animation_library("team_preview", library)
		animation.play("team_preview/idle")
		animation.advance(0.0)

func _combined_idle(player: AnimationPlayer, skeleton: Skeleton3D, aim_name: String) -> Animation:
	# GoldSrc splits gait and weapon aim. Playing them sequentially resets the
	# unkeyed upper body to a T-pose; combine disjoint tracks in a PRIVATE clip.
	var idle := player.get_animation("idle1").duplicate() as Animation
	var upper: Array[int] = []
	var spine := skeleton.find_bone("spine_0" if ModernAgentPose.is_modern(skeleton) else "Bip01 Spine")
	for bone in range(skeleton.get_bone_count()):
		var ancestor := bone
		while ancestor >= 0:
			if ancestor == spine:
				upper.append(bone)
				break
			ancestor = skeleton.get_bone_parent(ancestor)
	for track in range(idle.get_track_count() - 1, -1, -1):
		var bone := skeleton.find_bone(String(idle.track_get_path(track).get_concatenated_subnames()))
		if bone in upper:
			idle.remove_track(track)
	if player.has_animation(aim_name):
		var aim := player.get_animation(aim_name)
		for track in range(aim.get_track_count()):
			var bone := skeleton.find_bone(String(aim.track_get_path(track).get_concatenated_subnames()))
			if bone in upper:
				aim.copy_track(track, idle)
	return idle

func _style_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh := node as MeshInstance3D
		if mesh.mesh != null:
			for index in range(mesh.mesh.get_surface_count()):
				var styled := GameData.get_styled_model_material(mesh.get_active_material(index), "char")
				if styled != null:
					mesh.set_surface_override_material(index, styled)
	for child in node.get_children():
		_style_meshes(child)

func open_menu() -> void:
	if is_open:
		return
	_committing = false
	is_open = true
	visible = true
	GameplayInputGate.acquire(self)
	for tm in _buttons:
		(_buttons[tm] as Button).disabled = false
		if not _models.has(tm):
			_build_preview(tm)
		(_viewports[tm] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if _animations.has(tm):
			(_animations[tm] as AnimationPlayer).active = true

func close_menu(capture_mouse: bool = true) -> void:
	is_open = false
	GameplayInputGate.release(self, capture_mouse)
	visible = false
	for tm in _buttons:
		(_buttons[tm] as Button).release_focus()
		_set_highlight(tm, false)
		(_viewports[tm] as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _animations.has(tm):
			(_animations[tm] as AnimationPlayer).active = false

func _choose_team(tm: String) -> void:
	if not is_open or _committing or tm not in ["T", "CT"]:
		return
	var classes: Array = GameData.classes.get(tm, [])
	if classes.is_empty():
		return
	var chosen: Dictionary = classes[_rng.randi_range(0, classes.size() - 1)]
	var cid := String(chosen.get("id", ""))
	if cid.is_empty() or cid == "vip":
		return
	_committing = true
	for button in _buttons.values():
		(button as Button).disabled = true
	AudioManager.play_ui("launch_select1.wav")
	close_menu()
	team_class_chosen.emit(tm, cid)

func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_1 or code == KEY_2:
		get_viewport().set_input_as_handled()
		_choose_team("T" if code == KEY_1 else "CT")
	elif code == KEY_ESCAPE or code == KEY_0:
		get_viewport().set_input_as_handled()
		close_menu()
