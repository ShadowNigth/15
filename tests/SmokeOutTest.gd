extends Node3D
var checks := 0
var failures := 0
var bot_navigator: BotNavigator = null
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[SMOKE OUT] " + message)
func _ready() -> void:
	run.call_deferred()
func capture(label: String, viewport: Viewport = null) -> void:
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	var target := get_viewport() if viewport == null else viewport
	expect(target.get_texture().get_image().save_png("/tmp/modern-captures/" + label + ".png") == OK, "capture " + label)
func validate(root: Node3D, avatar: String) -> void:
	var rig := SportGloves._find_skeleton(root)
	rig.force_update_all_bone_transforms()
	var gloves := 0
	var sleeves := 0
	for mesh in SportGloves._find_meshes(root):
		if mesh.get_meta("native_glove", "") == "moto_smoke_out":
			gloves += 1
			expect(mesh.mesh.get_surface_count() == 2, "only native left/right glove surfaces, no source bare arms")
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				expect(material.albedo_texture != null, "native Smoke Out paint")
				var side := "_L_" if material.resource_name.ends_with("left") else "_R_"
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var matching := true
				for slot in bones.size():
					if weights[slot] > 0.00001: matching = matching and side in rig.get_bone_name(mesh.skin.get_bind_bone(bones[slot]))
				expect(matching, "native glove stays on its matching hand, no swap/reflection")
		if mesh.has_meta("cuff_fit"):
			sleeves += 1
			var bare := WristSeamFit.is_bare(avatar)
			expect(mesh.get_meta("cuff_layer") == ("inside_glove" if bare else "outside_glove"), "correct layering " + avatar)
			var fit: Dictionary = mesh.get_meta("cuff_fit")
			for side in ["L", "R"]:
				var profile: Dictionary = fit.profiles[side]
				expect(not profile.points.is_empty(), "actual selected glove cuff measured " + avatar + side)
				for sample in profile.points:
					var along: float = float(profile.start) + 0.018
					var rest: Vector3 = fit.wrists[side] + fit.axes[side] * along + sample.direction * sample.radius
					var fitted := WristSeamFit.layer_point(rest, fit.wrists[side], fit.axes[side], profile, bare)
					var delta: Vector3 = fitted - fit.wrists[side] - fit.axes[side] * along
					expect(delta.length() < float(sample.radius) - 0.004 if bare else delta.length() > float(sample.radius) + 0.004, "skin inside / sleeve outside cuff clearance")
	expect(gloves == 1 and sleeves == 1, "one independent glove pair and agent arms")
func run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	expect(GameData.select_glove("5033_10078"), "requested Moto Smoke Out selectable")
	expect(not GameData.select_glove("cs2go_5030_10046"), "removed Sport batch stays removed")
	var menu := load("res://scenes/MainMenu.tscn").instantiate() as MainMenu
	add_child(menu)
	await get_tree().process_frame
	menu._open_arsenal()
	menu._load_viewer_gloves()
	await capture("smoke_out_arsenal")
	await capture("smoke_out_detail", menu._viewer_viewport)
	menu._inspect_gloves()
	menu._glove_tween.pause()
	menu._glove_tween.custom_step(0.9)
	await capture("smoke_out_arsenal_inspect", menu._viewer_viewport)
	menu.free()
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
	for avatar in ["sas", "leet", "terror", "urban"]:
		player.set_team_and_class("T" if avatar in ["leet", "terror"] else "CT", avatar)
		for weapon in ["ak47", "glock18", "knife"]:
			GameData.select_knife("karambit")
			if weapon != "knife": player.weapon_ctrl.give_weapon(weapon)
			player.weapon_ctrl.equip_weapon_by_id(weapon)
			player._rebuild_viewmodel(weapon)
			validate(player._vm_model_root, ModernAgentPose.role(player.team, avatar))
			for clip in ["idle", "inspect", "reload"]:
				if not player._vm_anim.has_animation(clip): continue
				player._vm_anim.play(clip)
				player._vm_anim.pause()
				for phase in [0.15, 0.5, 0.85]:
					player._vm_anim.seek(player._vm_anim.get_animation(clip).length * phase, true)
					if phase == 0.5 and ((weapon == "ak47" and clip == "idle") or (weapon == "knife" and clip == "inspect")):
						await capture("smoke_out_" + avatar + "_" + weapon + "_" + clip)
	player.free()
	print("[SMOKE OUT] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
