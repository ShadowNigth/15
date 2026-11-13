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
func capture(label: String) -> void:
	for frame in 3: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	expect(get_viewport().get_texture().get_image().save_png("/tmp/modern-captures/" + label + ".png") == OK, "capture " + label)
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
			expect(pose.origin.is_finite() and pose.basis.determinant() > 0.001, "finite same-handed source pose")
	var visible_native := 0
	for mesh in SportGloves._find_meshes(replacement):
		if mesh.visible:
			visible_native += 1
			expect(mesh.skin != null and mesh.has_meta("native_source_skin"), "original native skin")
	expect(visible_native >= 2, "native forearms and gloves visible")
func run() -> void:
	NativeViewRig.enabled = true
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	GameData.select_glove("5033_10078")
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
	player.set_team_and_class("T", "leet")
	player._rebuild_viewmodel("ak47")
	player._vm_anim.play("idle")
	player._vm_anim.advance(0)
	player._vm_anim.pause()
	validate(player._vm_model_root)
	await capture("native_leet_ak47_idle")
	player.free()
	# Install every supported weapon/knife and agent, with original defaults and
	# Smoke Out. Exercise original animation resources, not synthetic tracks.
	for glove in ["classic", "5033_10078"]:
		GameData.select_glove(glove)
		for model in AgentViewArms.catalog().targets:
			for avatar in NativeViewRig.catalog().agents:
				var root := GameData.get_model_scene("weapons/" + String(model)).instantiate() as Node3D
				add_child(root)
				expect(NativeViewRig.install(root, model, avatar), "install " + model + "/" + avatar + "/" + glove)
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
