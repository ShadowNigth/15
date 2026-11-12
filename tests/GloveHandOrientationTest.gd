extends Node3D
var checks := 0
var failures := 0
var bot_navigator: BotNavigator = null
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[GLOVE HANDS] " + message)
func _ready() -> void:
	_run.call_deferred()
func capture(label: String, viewport: Viewport = null) -> void:
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	var target := get_viewport() if viewport == null else viewport
	expect(target.get_texture().get_image().save_png("/tmp/modern-captures/"+label+".png")==OK,"render " + label)
func test_anatomy() -> void:
	var definition: Dictionary = AgentViewArms.catalog().agents.sport
	expect(definition.get("retarget", "") == "anatomical-same-side-v3", "fresh native source integration")
	var scene := load(String(definition.model)) as PackedScene
	var source := scene.instantiate() as Node3D
	var mesh: MeshInstance3D = SportGloves._find_meshes(source)[0]
	expect(mesh.mesh.get_surface_count() == 2, "two independent native glove surfaces")
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		expect(vertices.size() > 1000, "native hand detail preserved")
		for point in vertices:
			expect(point.is_finite(), "finite rebuilt vertex")
	source.free()
func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	test_anatomy()
	var saved_glove := GameData.selected_glove_id
	var saved_knife := GameData.selected_knife_id
	var saved_hand := GameData.right_hand
	expect(GameData.select_glove("cs2go_5030_10046"),"reported Bronze Morph finish")
	var menu := load("res://scenes/MainMenu.tscn").instantiate() as MainMenu
	add_child(menu)
	for frame in 4: await get_tree().process_frame
	menu._open_arsenal()
	menu._load_viewer_gloves()
	var display_hands := 0
	for mesh in SportGloves._find_meshes(menu._viewer_pivot):
		if mesh.has_meta("arsenal_glove_pose"):
			display_hands += 1
			expect(mesh.skin == null, "display pose independent of gameplay rig")
			expect(mesh.mesh.get_aabb().size.length() > 0.01, "complete display hand")
	expect(display_hands == 2, "two independently positioned palm-down gloves")
	for frame in 20: await get_tree().process_frame
	await capture("glove_bronze_arsenal_full")
	await capture("glove_bronze_arsenal",menu._viewer_viewport)
	menu._inspect_gloves()
	menu._glove_tween.pause()
	menu._glove_tween.custom_step(0.9)
	await capture("glove_bronze_arsenal_inspect",menu._viewer_viewport)
	menu._glove_tween.custom_step(0.8)
	await capture("glove_bronze_arsenal_palm",menu._viewer_viewport)
	menu.free()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16,0.20,0.24)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,0.5,100)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.25
	add_child(floor_body)
	var player := PlayerController.new()
	add_child(player)
	player.set_team_and_class("CT","sas")
	player.spawn_for_round(Vector3.ZERO,0,true)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.weapon_ctrl.set_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for glove in ["cs2go_5030_10046","cs2go_5030_10045"]:
		GameData.select_glove(glove)
		GameData.right_hand = true
		GameData.select_knife("original")
		player.weapon_ctrl.give_weapon("glock18",20,120)
		player.weapon_ctrl.equip_weapon_by_id("glock18")
		player._rebuild_viewmodel("glock18")
		player._vm_anim.play("idle")
		player._vm_anim.seek(0.1,true)
		player._vm_anim.pause()
		await capture("glove_"+glove+"_glock")
		for choice in ["original","karambit","push"]:
			GameData.select_knife(choice)
			player.weapon_ctrl.equip_weapon_by_id("knife")
			player._rebuild_viewmodel("knife")
			var clips := player._available_inspection_clips()
			expect(not clips.is_empty(),"retained knife inspection " + choice)
			if clips.is_empty(): continue
			var clip: String = clips[0]
			player._vm_anim.play(clip)
			player._vm_anim.pause()
			for phase in [0.15,0.5,0.85]:
				player._vm_anim.seek(player._vm_anim.get_animation(clip).length*phase,true)
				var rig := SportGloves._find_skeleton(player._vm_model_root)
				rig.force_update_all_bone_transforms()
				for mesh in SportGloves._find_meshes(player._vm_model_root):
					if mesh.get_meta("agent_arms","") != "sport": continue
					expect(mesh.get_meta("handedness","")=="exchanged-models-v4","new anatomical conversion active")
				if choice=="original" and phase==0.5:
					await capture("glove_"+glove+"_inspect")
		GameData.right_hand = false
		player._rebuild_viewmodel("knife")
		expect(player._is_viewmodel_mirrored(),"native knife still follows left-hand preference")
	GameData.select_glove(saved_glove)
	GameData.select_knife(saved_knife)
	GameData.right_hand = saved_hand
	print("[GLOVE HANDS] PASS: %d checks; %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
