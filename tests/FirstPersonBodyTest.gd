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
	test_waist_cap()
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
	add_child(floor)
	var player := PlayerController.new()
	add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.weapon_ctrl.set_physics_process(false)
	var glove := GameData.selected_glove_id
	GameData.select_glove("cs2go_5030_1417")
	for faction in ["CT", "T"]:
		for info in GameData.classes[faction]:
			player.set_team_and_class(faction, String(info.id))
			player.spawn_for_round(Vector3.ZERO, 0, true)
			player.look_pitch = -1.25
			expect(player._body_root.visible, "local body remains visible after respawn " + info.id)
			expect(player._first_person_body != null and not player._first_person_body.parts.is_empty(), "agent has actual lower-body geometry " + info.id)
			expect(player.camera.cull_mask & FirstPersonBody.LOCAL_LAYER != 0, "world camera sees own legs")
			expect(player._vm_camera.cull_mask & FirstPersonBody.LOCAL_LAYER == 0, "weapon camera never draws legs")
			for part in player._first_person_body.parts:
				expect(part.skin != null and part.get_node(part.skeleton) == player._skel, "legs share actual animated agent skeleton")
				expect(part.layers == FirstPersonBody.LOCAL_LAYER, "local copy excluded from other actor camera masks")
				expect(part.mesh.get_surface_count() > 0, "lower body triangles exist")
			for tick in 30:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0 / 60)
			await capture("local_body_" + info.id + "_idle")
			for tick in 45:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.FORWARD, false, false, false, 1.0 / 60)
			await capture("local_body_" + info.id + "_walk")
			for tick in 20:
				await get_tree().physics_frame
				player.apply_goldsrc_movement(Vector3.ZERO, false, true, false, 1.0 / 60)
			await capture("local_body_" + info.id + "_crouch")
			expect(player.is_crouching, "physical crouch retained with visible legs")
			player._first_person_body.sync(player._body_root, false)
			for part in player._first_person_body.parts:
				expect(not part.visible, "local lower body hidden in death/spectator")
			player._first_person_body.sync(player._body_root, true)
	GameData.selected_glove_id = glove
	player.free()
	print("[LOCAL BODY] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)

func test_waist_cap() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for ring in 2:
		for index in 8:
			var angle := TAU * float(index) / 8.0
			vertices.append(Vector3(cos(angle), float(ring), sin(angle)))
			normals.append(Vector3.UP)
			bones.append_array(PackedInt32Array([2, 0, 0, 0]))
			weights.append_array(PackedFloat32Array([1, 0, 0, 0]))
	for index in 8:
		var next := (index + 1) % 8
		indices.append_array(PackedInt32Array([index, next, index + 8, next, next + 8, index + 8]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var capped := FirstPersonBody.cap_waist(arrays, 4)
	expect((capped[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 17, "waist closure adds only upper loop center, never foot cap")
	expect((capped[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == 72, "waist closure fills all eight boundary edges")
	expect((capped[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array)[64] == 1.0, "waist cap retains normalized pelvis skinning")
	var capped_vertices: PackedVector3Array = capped[Mesh.ARRAY_VERTEX]
	var capped_indices: PackedInt32Array = capped[Mesh.ARRAY_INDEX]
	var a := capped_vertices[capped_indices[48]]
	var b := capped_vertices[capped_indices[49]]
	var c := capped_vertices[capped_indices[50]]
	expect((b - a).cross(c - a).y < 0, "waist cap uses Godot clockwise front faces visible from above")
