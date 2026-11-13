extends Node3D
var checks := 0
var failures := 0
var bot_navigator: BotNavigator = null
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[NATIVE VIEW] " + message)
func _ready() -> void:
	run.call_deferred()
func capture(label: String, viewport: Viewport = null) -> void:
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	var target_view := get_viewport() if viewport == null else viewport
	expect(target_view.get_texture().get_image().save_png("/tmp/modern-captures/" + label + ".png") == OK, "capture " + label)
func validate(root: Node3D) -> void:
	var replacement := root.get_meta("native_view_rig", null) as NativeViewRig
	expect(replacement != null, "independent source rig installed")
	if replacement == null: return
	replacement.sync_pose()
	expect(not replacement.bindings.is_empty(), "source bones driven")
	for binding in replacement.bindings:
		var rig: Skeleton3D = binding.rig
		expect(rig != replacement.target, "not attached to the legacy skin")
		expect(rig.find_bone("hand_L") >= 0 and rig.find_bone("hand_R") >= 0, "native hand names retained")
		for driver in binding.drivers:
			var pose := rig.get_bone_global_pose(driver.source)
			var expected: Transform3D = rig.global_transform.affine_inverse() * replacement.target.global_transform * replacement.target.get_bone_global_pose(driver.target) * driver.correction
			if binding.preserve_palm and String(rig.get_bone_name(driver.source)).begins_with("finger_"):
				var parent := rig.get_bone_parent(driver.source)
				if parent >= 0:
					var rest: Transform3D = binding.rests[driver.source]
					var parent_rest: Transform3D = binding.rests[parent]
					var expected_offset := parent_rest.affine_inverse() * rest.origin
					expected.origin = rig.get_bone_global_pose(parent) * expected_offset
					var actual_offset := rig.get_bone_global_pose(parent).affine_inverse() * pose.origin
					expect(actual_offset.distance_to(expected_offset) < 0.0001, "Moto retains native palm spacing and phalanx length")
			expect(pose.origin.is_finite() and absf(pose.basis.determinant()) > 0.001, "finite nonsingular source pose")
			expect(pose.origin.distance_to(expected.origin) < 0.001 and pose.basis.determinant() * expected.basis.determinant() > 0, "source pose matches driven trajectory and inherited mirror")
	var visible_native := 0
	for mesh in SportGloves._find_meshes(replacement):
		if mesh.visible:
			visible_native += mesh.mesh.get_surface_count()
			expect(mesh.skin != null and mesh.has_meta("native_source_skin"), "original native skin")
	expect(visible_native >= 2, "native forearms and gloves visible")
func run() -> void:
	NativeViewRig.enabled = true
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	GameData.select_glove("5033_10078")
	expect(GameData.get_selected_glove().get("texture_layout", "") == "opposite-hand-palm-back-v1", "Smoke Out: left/right exchange and palm/back reversal")
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15, 0.19, 0.23)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	var player := PlayerController.new()
	add_child(player)
	player.set_team_and_class("CT", "sas")
	player.spawn_for_round(Vector3.ZERO, 0, true)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.weapon_ctrl.set_process(false)
	player.weapon_ctrl.give_weapon("ak47")
	player.weapon_ctrl.equip_weapon_by_id("ak47")
	player._rebuild_viewmodel("ak47")
	print("[NATIVE VIEW] AK clips: ", player._vm_anim.get_animation_list())
	for action in ["idle", "shoot", "reload", "inspect"]:
		var clip := ""
		for candidate in player._vm_anim.get_animation_list():
			if String(candidate).begins_with(action):
				clip = candidate
				break
		expect(not clip.is_empty(), "AK existing animation " + action)
		if clip.is_empty(): continue
		player._vm_anim.play(clip)
		player._vm_anim.pause()
		for phase in [0.0, 0.25, 0.5, 0.75, 0.95]:
			player._vm_anim.seek(player._vm_anim.get_animation(clip).length * phase, true)
			validate(player._vm_model_root)
			if phase == 0.5: await capture("native_ak47_" + action)
			if action in ["reload", "inspect"] and phase in [0.0, 0.95]:
				var suffix := "start" if phase == 0.0 else "end"
				await capture("native_ak47_" + action + "_" + suffix)
	player.set_team_and_class("T", "leet")
	player._rebuild_viewmodel("ak47")
	player._vm_anim.play("idle")
	player._vm_anim.advance(0)
	player._vm_anim.pause()
	validate(player._vm_model_root)
	await capture("native_leet_ak47_idle")
	player.set_team_and_class("CT", "sas")
	GameData.select_knife("karambit")
	player.weapon_ctrl.equip_weapon_by_id("knife")
	player._rebuild_viewmodel("knife")
	player._vm_anim.play("inspect")
	player._vm_anim.pause()
	for phase in [0.0, 0.5, 0.95]:
		player._vm_anim.seek(player._vm_anim.get_animation("inspect").length * phase, true)
		validate(player._vm_model_root)
		var suffix := "start" if phase == 0.0 else ("mid" if phase == 0.5 else "end")
		await capture("native_karambit_inspect_" + suffix)
	GameData.select_glove("amphibious_ft")
	player.set_team_and_class("T", "leet")
	player.weapon_ctrl.equip_weapon_by_id("ak47")
	player._rebuild_viewmodel("ak47")
	player._vm_anim.play("idle")
	player._vm_anim.advance(0)
	player._vm_anim.pause()
	validate(player._vm_model_root)
	await capture("native_existing_sport_ak47")
	GameData.select_glove("5033_10078")
	player.free()
	var menu := load("res://scenes/MainMenu.tscn").instantiate() as MainMenu
	add_child(menu)
	await get_tree().process_frame
	menu._open_arsenal()
	menu._load_viewer_gloves()
	await capture("native_arsenal_gloves", menu._viewer_viewport)
	# Multi-angle Arsenal takes: same native preview pose, different orbit
	# positions so the formed palm, fingers and swapped artwork can be checked
	# from the front, both profiles, the reverse side and above/below.
	var arsenal_views := {
		"left": Vector3(-0.18, -1.05, 0.0),
		"right": Vector3(-0.18, 1.05, 0.0),
		"back": Vector3(0.0, PI, 0.0),
		"top": Vector3(-1.15, 0.0, 0.0),
		"bottom": Vector3(1.15, 0.0, 0.0),
	}
	for view_name in arsenal_views:
		var view_rotation: Vector3 = arsenal_views[view_name]
		menu._viewer_pivot.rotation = view_rotation
		await capture("native_arsenal_gloves_" + view_name, menu._viewer_viewport)
	menu._viewer_pivot.rotation = Vector3(-0.32, 0.42, 0.0)
	menu._viewer_camera.position = Vector3(0, 0, menu._inspection_home_distance * 0.58)
	await capture("native_arsenal_gloves_closeup", menu._viewer_viewport)
	menu._viewer_pivot.rotation = Vector3.ZERO
	menu._viewer_camera.position = Vector3(0, 0, menu._inspection_home_distance)
	for root in menu._viewer_pivot.get_children():
		if not root.has_meta("native_view_rig"): continue
		var native := root.get_meta("native_view_rig") as NativeViewRig
		expect(native.glove_preview, "Moto preview is independent of the closed knife grip")
		for phase in [0.0, 0.2, 0.5, 0.8, 1.0]:
			native.preview_phase = phase
			native.sync_pose()
			for binding in native.bindings:
				if not binding.preserve_palm: continue
				var rig: Skeleton3D = binding.rig
				for bone in rig.get_bone_count():
					var name := String(rig.get_bone_name(bone))
					if not (name.contains("_L") or name.contains("_R")): continue
					var side := "L" if name.contains("_L") else "R"
					var hand := rig.find_bone("hand_" + side)
					var hand_rest: Transform3D = binding.rests[hand]
					var rest: Transform3D = binding.rests[bone]
					var original := hand_rest.affine_inverse() * rest
					var actual := rig.get_bone_global_pose(hand).affine_inverse() * rig.get_bone_global_pose(bone)
					expect(actual.origin.distance_to(original.origin) < 0.0001, "preview keeps native 3D shape, not a squashed weapon pose")
	for root in menu._viewer_pivot.get_children():
		if not root.has_meta("native_view_rig"): continue
		var native := root.get_meta("native_view_rig") as NativeViewRig
		for phase in [0.0, 0.5, 1.0]:
			native.preview_phase = phase
			native.sync_pose()
			var suffix := "start" if phase == 0.0 else ("mid" if phase == 0.5 else "end")
			await capture("native_arsenal_inspect_" + suffix, menu._viewer_viewport)
	menu._inspect_gloves()
	menu._glove_tween.pause()
	menu._glove_tween.custom_step(0.9)
	await capture("native_arsenal_inspect", menu._viewer_viewport)
	menu.free()
	# Every pre-existing optional Sport finish keeps its ID, matching native
	# model, paint, wear and independent skin instead of silently using defaults.
	for option in GameData.get_glove_options():
		expect(GameData.select_glove(String(option.id)), "retained finish selectable " + String(option.id))
		for avatar in ["sas", "leet"]:
			var root := GameData.get_model_scene("weapons/v_ak47").instantiate() as Node3D
			add_child(root)
			expect(NativeViewRig.install(root, "v_ak47", avatar), "retained native finish " + String(option.id) + avatar)
			validate(root)
			for mesh in SportGloves._find_meshes(root):
				if not mesh.visible or not mesh.has_meta("native_source_skin"): continue
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as BaseMaterial3D
					if material.resource_name.begins_with("glove_"):
						expect(material.albedo_texture == GameData.get_texture(String(option.native_textures.get(material.resource_name, ""))), "selected finish texture, not default")
			root.free()
	if "--pilot-only" in OS.get_cmdline_user_args():
		print("[NATIVE VIEW] ", "PASS: " if failures == 0 else "FAIL: ", checks, " pilot checks; ", failures, " failures")
		get_tree().quit(0 if failures == 0 else 1)
		return
	# Install every supported weapon/knife and agent, with original defaults and
	# Smoke Out. Exercise original animation resources, not synthetic tracks.
	var models: Array = AgentViewArms.catalog().targets.keys()
	for option in GameData.get_knife_options():
		if not String(option.v_model) in models: models.append(String(option.v_model))
	for glove in ["classic", "5033_10078", "amphibious_ft"]:
		GameData.select_glove(glove)
		for model in models:
			for avatar in NativeViewRig.catalog().agents:
				var root := GameData.get_model_scene("weapons/" + String(model)).instantiate() as Node3D
				add_child(root)
				expect(NativeViewRig.install(root, GameData.get_knife_glove_model(model), avatar), "install " + model + "/" + avatar + "/" + glove)
				var animation := find_animation(root)
				if animation != null:
					for clip in animation.get_animation_list():
						if clip == "RESET": continue
						animation.play(clip)
						animation.pause()
						animation.seek(animation.get_animation(clip).length * 0.5, true)
						validate(root)
				root.free()
	print("[NATIVE VIEW] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
func find_animation(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer: return root as AnimationPlayer
	for child in root.get_children():
		var result := find_animation(child)
		if result != null: return result
	return null
