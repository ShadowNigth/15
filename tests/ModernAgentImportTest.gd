extends Node3D
var checks := 0
var failures := 0
var actors: Array[Node3D] = []
var animations: Array[AnimationPlayer] = []
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[MODERN IMPORT] " + message)
func find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := find_anim(child)
		if result:
			return result
	return null
func find_rig(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := find_rig(child)
		if result:
			return result
	return null
func capture(label: String) -> void:
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("MODERN_CAPTURE_DIR")
	if not path.is_empty():
		DirAccess.make_dir_recursive_absolute(path)
		expect(get_viewport().get_texture().get_image().save_png(path.path_join(label+".png")) == OK, "save " + label)
func _ready() -> void:
	_run.call_deferred()
func _run() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	env_node.environment = env
	add_child(env_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.5
	add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(3.2, 2.0, 4.4)
	add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	for i in 2:
		var id := "sas" if i == 0 else "phoenix"
		var scene := load("res://assets/models/modern/"+id+".glb") as PackedScene
		expect(scene != null, "load " + id)
		if scene == null:
			continue
		var actor := scene.instantiate() as Node3D
		actor.position.x = -0.8 if i == 0 else 0.8
		add_child(actor)
		actors.append(actor)
		var anim := find_anim(actor)
		var rig := find_rig(actor)
		expect(anim != null and rig != null, "animation and skeleton " + id)
		if anim == null or rig == null:
			continue
		animations.append(anim)
		expect(anim.has_animation("idle_rifle") and anim.has_animation("run_n_rifle"), "required clips")
		expect(anim.get_animation_list().size() >= 21, "21 locomotion clips")
		var head := rig.find_bone("head_0")
		expect(head >= 0 and rig.find_bone("hand_R") >= 0, "native attachments")
		anim.play("idle_rifle")
		anim.seek(0.3, true)
		rig.force_update_all_bone_transforms()
		var head_pos := rig.global_transform * rig.get_bone_global_pose(head).origin
		expect(head_pos.is_finite() and head_pos.y > 1.2 and head_pos.y < 2.2, "metre-space head height " + str(head_pos))
		var idle_hand := rig.get_bone_global_pose(rig.find_bone("hand_R")).origin
		anim.play("run_n_rifle")
		anim.seek(0.2, true)
		rig.force_update_all_bone_transforms()
		var run_hand := rig.get_bone_global_pose(rig.find_bone("hand_R")).origin
		expect(idle_hand.distance_to(run_hand) > 0.01, "native run deforms skeleton")
		for clip in anim.get_animation_list():
			anim.play(clip)
			anim.seek(anim.current_animation_length * 0.4, true)
			rig.force_update_all_bone_transforms()
			expect((rig.global_transform * rig.get_bone_global_pose(head).origin).is_finite(), "finite pose " + clip)
		anim.play("idle_rifle")
		anim.seek(0.3, true)
	await capture("modern_idle")
	for anim in animations:
		anim.play("run_n_rifle")
		anim.seek(0.15, true)
	await capture("modern_run")
	for anim in animations:
		anim.play("idle_crouch_rifle")
		anim.seek(0.3, true)
	await capture("modern_crouch")
	print("PASS: Modern agent import ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
