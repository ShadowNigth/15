extends Node3D
var checks := 0
var failures := 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[LOCAL BODY] " + message)
func _ready() -> void:
	run.call_deferred()
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	expect(get_viewport().get_texture().get_image().save_png("/tmp/modern-captures/" + label + ".png") == OK, "actual Godot body capture " + label)
func run() -> void:
	test_lower_body()
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.22, 0.26, 0.30)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	add_child(environment)
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.2, 100)
	collision.shape = box
	floor.position.y = -0.1
	floor.add_child(collision)
	var floor_visual := MeshInstance3D.new()
	var floor_box := BoxMesh.new()
	floor_box.size = box.size
	floor_visual.mesh = floor_box
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.36, 0.40, 0.42)
	floor_visual.material_override = floor_material
	floor.add_child(floor_visual)
	add_child(floor)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	light.shadow_enabled = true
	light.light_energy = 0.8
	add_child(light)
	var player := PlayerController.new()
	add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.weapon_ctrl.set_physics_process(false)
	var glove := GameData.selected_glove_id
	GameData.select_glove("classic")
	for faction in ["CT", "T"]:
		for info in GameData.classes[faction]:
			player.set_team_and_class(faction, String(info.id))
			player.spawn_for_round(Vector3.ZERO, 0, true)
			player.look_pitch = -1.25
			player.weapon_ctrl.give_weapon("glock18", 20, 120)
			player.weapon_ctrl.equip_weapon_by_id("glock18")
			expect(player._body_root.visible, "local body remains visible after respawn " + info.id)
			expect(player._first_person_body != null and not player._first_person_body.parts.is_empty(), "agent has actual lower-body geometry " + info.id)
			expect(player.camera.cull_mask & FirstPersonBody.LOCAL_LAYER != 0, "world camera sees own legs")
			expect(player._vm_camera.cull_mask & FirstPersonBody.LOCAL_LAYER == 0, "weapon camera never draws legs")
			for part in player._first_person_body.parts:
				expect(part.skin != null and part.get_node(part.skeleton) == player._first_person_body.local_rig, "legs use synchronized agent pose skeleton")
				expect(part.layers == FirstPersonBody.LOCAL_LAYER, "local copy excluded from other actor camera masks")
				expect(part.mesh.get_surface_count() > 0, "lower body triangles exist")
			for tick in 30:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0 / 60)
			await capture("local_body_" + info.id + "_idle")
			for pitch in [70, 89]:
				player.look_pitch = -deg_to_rad(float(pitch))
				await capture("local_body_" + info.id + "_down_" + str(pitch))
			player.look_pitch = -1.25
			for tick in 45:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.FORWARD, false, false, false, 1.0 / 60)
			await capture("local_body_" + info.id + "_walk")
			var body := player._first_person_body
			expect(body.local_rig.get_bone_count() == player._skel.get_bone_count(), "local pose includes all agent joints")
			var identical := true
			for index in player._skel.get_bone_count():
				identical = identical and body.local_rig.get_bone_pose_rotation(index).is_equal_approx(player._skel.get_bone_pose_rotation(index))
			expect(identical, "local legs copy exact gait without a second animation clock")

			for tick in 20:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.ZERO, false, true, false, 1.0 / 60)
			await capture("local_body_" + info.id + "_crouch")
			expect(player.is_crouching, "physical crouch retained with visible legs")
			for tick in 20:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0 / 60)
			var ground_y := player.global_position.y
			for tick in 15:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.FORWARD, tick == 0, false, false, 1.0 / 60)
			expect(player.global_position.y > ground_y + 0.15, "actual jump retains attached lower body " + info.id)
			await capture("local_body_" + info.id + "_jump")

			player._first_person_body.sync(player._body_root, false)
			for part in player._first_person_body.parts:
				expect(not part.visible, "local lower body hidden in death/spectator")
			player._first_person_body.sync(player._body_root, true)
	GameData.selected_glove_id = glove
	player.free()
	print("[LOCAL BODY] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)

func test_lower_body() -> void:
	expect(FirstPersonBody.lower_bone("spine_2"), "continuous torso prevents an exposed waist opening")
	expect(FirstPersonBody.lower_bone("spine_0"), "lower abdomen remains attached to pelvis")
	expect(FirstPersonBody.lower_bone("clavicle_L"), "mixed chest weights kept to avoid a cut-off torso")
	expect(not GameData.select_glove("cs2go_5030_10046"), "removed native gloves cannot be equipped")
	expect(GameData.select_glove("classic"), "original gloves restored")
	for option in GameData.get_glove_options():
		expect(not bool(option.get("native_uv", false)), "removed gloves absent from Arsenal")
	expect(not FirstPersonBody.lower_bone("head_0") and not FirstPersonBody.lower_bone("arm_upper_L"), "no duplicate head or first-person arms")
	var scene := GameData.get_model_scene("players/sas").instantiate() as Node3D
	add_child(scene)
	var rig := SportGloves._find_skeleton(scene)
	for mesh in SportGloves._find_meshes(scene):
		var filtered := FirstPersonBody.filtered(mesh, rig)
		if filtered == null:
			continue
		for surface in filtered.get_surface_count():
			var arrays := filtered.surface_get_arrays(surface)
			var vertices_match := false
			var uv_match := false
			for original_surface in mesh.mesh.get_surface_count():
				var original := mesh.mesh.surface_get_arrays(original_surface)
				if arrays[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX]:
					vertices_match = true
					uv_match = arrays[Mesh.ARRAY_TEX_UV] == original[Mesh.ARRAY_TEX_UV]
			expect(vertices_match, "body contains only untouched original vertices, never a fabricated waist fan")
			expect(uv_match, "original torso and trouser UVs preserved")
	scene.free()
