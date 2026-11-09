extends Node
## Real map/framebuffer, mouse/keyboard selection and independent faction randomisation.
var checks: int = 0
var failures: int = 0
var choices: Array = []
var menu: TeamSelectMenu

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[TEAM QA] " + label)

func settle(frames: int = 4) -> void:
	for i in range(frames):
		await get_tree().process_frame

func _ready() -> void:
	_run.call_deferred()

func capture(label: String) -> void:
	var output := OS.get_environment("TEAM_CAPTURE_DIR")
	if output.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(output)
	await settle()
	RenderingServer.force_draw(false)
	var image := get_tree().root.get_texture().get_image()
	expect(image.save_png(output.path_join(label + ".png")) == OK, "native framebuffer " + label)

func click(button: Button) -> void:
	var position := button.get_global_rect().position + button.size * Vector2(0.5, 0.65)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = position
		event.global_position = position
		event.pressed = pressed
		Input.parse_input_event(event)
		await settle(2)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await settle(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await settle(2)

func _run() -> void:
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_tree().root.size = Vector2i(1280, 720)
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 0
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	menu = world.team_menu
	menu.team_class_chosen.connect(func(tm: String, cid: String): choices.append([tm, cid]))
	await settle(12)
	expect(menu.is_open and menu.visible, "map entry directly shows two-team selector")
	expect(menu._buttons.size() == 2, "exactly two choices, no appearance or auto-team step")
	expect(GameplayInputGate.blocked(), "gameplay locked while selector is open")
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "visible cursor")
	expect(not world.hud.visible, "gameplay HUD hidden under clean team presentation")
	expect(menu._models.size() == 2 and menu._animations.size() == 2, "two genuine animated classic models")
	var count := RoundManager.actors.size()
	for tm in ["T", "CT"]:
		expect(menu._models[tm] is Node3D and not menu._models[tm] is CSActor, "cosmetic only " + tm)
		expect((menu._buttons[tm] as Button).text.is_empty(), "only emblem above character " + tm)
		expect((menu._animations[tm] as AnimationPlayer).is_playing(), "native idle playing " + tm)
		var animation := menu._animations[tm] as AnimationPlayer
		var before := animation.current_animation_position
		await settle(8)
		expect(not is_equal_approx(before, animation.current_animation_position), "native idle advances " + tm)
	await capture("team_selection")
	await click(menu._buttons["T"])
	expect(choices.size() == 1 and choices[0][0] == "T", "real character click joins T once")
	expect(world.player.team == "T" and world.player.class_id == choices[0][1], "choice reaches real player and starts match")
	expect(not menu.is_open and not menu.visible, "no second submenu after click")
	expect(not GameplayInputGate.blocked(), "modal ownership released on join")
	expect(not world.player.ui_blocking_input, "player input unblocked on join")
	menu._choose_team("CT")
	expect(choices.size() == 1, "stale or duplicate click cannot select twice")
	for tm in ["T", "CT"]:
		expect((menu._viewports[tm] as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden renderer sleeps " + tm)
		expect(not (menu._animations[tm] as AnimationPlayer).active, "hidden animator sleeps " + tm)
	menu.open_menu()
	get_tree().root.size = Vector2i(1024, 768)
	await settle(12)
	var left: Rect2 = menu._buttons["T"].get_global_rect()
	var right: Rect2 = menu._buttons["CT"].get_global_rect()
	expect(not left.intersects(right), "4:3 choices do not overlap")
	for tm in ["T", "CT"]:
		var rect: Rect2 = menu._buttons[tm].get_global_rect()
		expect(Rect2(Vector2.ZERO, Vector2(get_tree().root.size)).encloses(rect), "4:3 choice inside screen " + tm)
		expect(rect.encloses((menu._emblems[tm] as TextureRect).get_global_rect()), "4:3 emblem inside choice " + tm)
	await capture("team_selection_4x3")
	await key(KEY_2)
	expect(choices.size() == 2 and choices[1][0] == "CT", "keyboard chooses CT without appearance menu")
	expect(world.player.team == "CT" and world.player.class_id == choices[1][1], "random CT class reaches player")
	expect(RoundManager.actors.size() == count, "previews never register gameplay actors")
	# Sample selection without repeatedly respawning the actual player.
	menu.team_class_chosen.disconnect(world._on_player_team_chosen)
	menu._rng.seed = 92741
	var cached_ids := [menu._models["T"].get_instance_id(), menu._models["CT"].get_instance_id()]
	for tm in ["T", "CT"]:
		var valid: Array = []
		var seen: Dictionary = {}
		for entry in GameData.classes[tm]:
			valid.append(String(entry.id))
		for trial in range(128):
			menu.open_menu()
			var state := menu._rng.state
			menu.open_menu()
			menu._set_highlight(tm, true)
			expect(menu._rng.state == state, "opening/hover does not roll class")
			var previous := choices.size()
			menu._choose_team(tm)
			expect(choices.size() == previous + 1, "one confirmation per choice")
			var choice: Array = choices.back()
			expect(choice[0] == tm and choice[1] in valid and choice[1] != "vip", "random class belongs exclusively to chosen team")
			seen[choice[1]] = true
			menu._choose_team(tm)
			expect(choices.size() == previous + 1, "duplicate confirmation rejected")
		expect(seen.size() == valid.size(), "all four classic classes reachable " + tm)
	expect(cached_ids == [menu._models["T"].get_instance_id(), menu._models["CT"].get_instance_id()], "reopening reuses previews")
	menu.open_menu()
	await key(KEY_ESCAPE)
	expect(not menu.is_open and not GameplayInputGate.blocked(), "Escape closes and releases modal")
	expect(not world.player.ui_blocking_input and world.hud.visible, "Escape restores gameplay input and HUD")
	menu.open_menu()
	menu.close_menu(false)
	expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not GameplayInputGate.blocked(), "close_menu(false) remains compatible")
	menu.open_menu()
	world.queue_free()
	await settle()
	expect(not GameplayInputGate.blocked(), "scene teardown releases modal ownership")
	if failures == 0:
		print("[TEAM QA] PASS: %d checks" % checks)
	else:
		push_error("[TEAM QA] FAIL: %d of %d checks" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
