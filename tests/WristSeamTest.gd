extends Node3D
var checks := 0
var failures := 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[WRIST SEAM] " + message)
func _ready() -> void:
	run.call_deferred()
func capture(label: String) -> void:
	for frame in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	expect(get_viewport().get_texture().get_image().save_png("/tmp/modern-captures/" + label + ".png") == OK, "render " + label)
func point(mesh: MeshInstance3D, arrays: Array, vertex: int, rig: Skeleton3D) -> Vector3:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / vertices.size()
	var result := Vector3.ZERO
	for slot in stride:
		var offset := vertex * stride + slot
		if weights[offset] <= 0: continue
		var bind := bones[offset]
		var name := String(mesh.skin.get_bind_name(bind))
		var bone := AgentViewArms._bone(rig, name) if not name.is_empty() else mesh.skin.get_bind_bone(bind)
		result += (rig.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
	return result
func validate(root: Node3D, baseline: Node3D, label: String) -> void:
	var rig := SportGloves._find_skeleton(root)
	rig.force_update_all_bone_transforms()
	var reference: MeshInstance3D = null
	var reference_arrays: Array = []
	for mesh in SportGloves._find_meshes(baseline):
		for surface in mesh.mesh.get_surface_count():
			if mesh.mesh.surface_get_material(surface).resource_name == "ct_arms.bmp":
				reference = mesh
				reference_arrays = mesh.mesh.surface_get_arrays(surface)
	expect(reference != null, "original authored wrist reference " + label)
	if reference == null: return
	for side in ["L", "R"]:
		var prefix: String = "v_weapon.Bip01_" + String(side) + "_"
		var wrist := Transform3D.IDENTITY
		var elbow := Transform3D.IDENTITY
		for bind in reference.skin.get_bind_count():
			var name := String(reference.skin.get_bind_name(bind)).replace(".", "_")
			if name == (prefix + "Hand").replace(".", "_"): wrist = reference.skin.get_bind_pose(bind).affine_inverse()
			if name == (prefix + "Forearm").replace(".", "_"): elbow = reference.skin.get_bind_pose(bind).affine_inverse()
		var direction := (wrist.origin - elbow.origin).normalized()
		var reference_points := PackedVector3Array()
		var rv: PackedVector3Array = reference_arrays[Mesh.ARRAY_VERTEX]
		var rb: PackedInt32Array = reference_arrays[Mesh.ARRAY_BONES]
		var rw: PackedFloat32Array = reference_arrays[Mesh.ARRAY_WEIGHTS]
		var rs: int = rb.size() / rv.size()
		for vertex in rv.size():
			var dominant := 0
			for slot in rs:
				if rw[vertex * rs + slot] > rw[vertex * rs + dominant]: dominant = slot
			var bind := rb[vertex * rs + dominant]
			var name := String(reference.skin.get_bind_name(bind))
			var original_bone := AgentViewArms._bone(rig, name) if not name.is_empty() else reference.skin.get_bind_bone(bind)
			if not ("_" + String(side) + "_") in rig.get_bone_name(original_bone): continue
			var along := (rv[vertex] - wrist.origin).dot(direction)
			if along < -0.065 or along > 0.025 or rv[vertex].distance_to(wrist.origin) > 0.12: continue
			reference_points.append(point(reference, reference_arrays, vertex, rig))
		var count := 0
		var worst := 0.0
		for mesh in SportGloves._find_meshes(root):
			if not mesh.has_meta("agent_arms"): continue
			expect(mesh.get_meta("wrist_seam_fit", "") == "authored-cuff-v4", "destination rig wrist fit active " + label)
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var stride: int = binds.size() / vertices.size()
				for vertex in vertices.size():
					var dominant := 0
					for slot in stride:
						if weights[vertex * stride + slot] > weights[vertex * stride + dominant]: dominant = slot
					var bone := mesh.skin.get_bind_bone(binds[vertex * stride + dominant])
					if not ("_" + String(side) + "_") in rig.get_bone_name(bone): continue
					var along := (vertices[vertex] - wrist.origin).dot(direction)
					if along < -0.04 or along > 0.02 or vertices[vertex].distance_to(wrist.origin) > 0.12: continue
					count += 1
					var posed := point(mesh, arrays, vertex, rig)
					var nearest := INF
					for original in reference_points: nearest = minf(nearest, posed.distance_to(original))
					worst = maxf(worst, nearest)
		# Measure against the original forearm envelope through the actual pose,
		# not just finite/bounded vertices or successful model installation.
		expect(count > 0 and not reference_points.is_empty(), "both cuff boundaries sampled " + label + side)
		expect(worst < 0.001, "animated cuff stays in original wrist envelope " + label + side + " distance=" + str(worst))
func run() -> void:
	expect(WristSeamFit.enabled, "production wrist repair enabled by default")
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.12, 0.15, 0.18)
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
	GameData.select_glove("classic")
	for faction in ["CT", "T"]:
		for info in GameData.classes[faction]:
			player.set_team_and_class(faction, String(info.id))
			var avatar := ModernAgentPose.role(faction, String(info.id))
			for weapon in ["glock18", "ak47", "knife"]:
				GameData.select_knife("karambit")
				if weapon != "knife": player.weapon_ctrl.give_weapon(weapon)
				player.weapon_ctrl.equip_weapon_by_id(weapon)
				player._rebuild_viewmodel(weapon)
				var baseline := GameData.get_model_scene("weapons/" + player._cur_vm_model_name).instantiate() as Node3D
				var clips: Array = player._available_inspection_clips()
				for name in player._vm_anim.get_animation_list():
					if name == "idle" or name == "reload": clips.append(name)
				for clip in clips:
					player._vm_anim.play(clip)
					player._vm_anim.pause()
					for fraction in [0.1, 0.5, 0.9]:
						player._vm_anim.seek(player._vm_anim.get_animation(clip).length * fraction, true)
						validate(player._vm_model_root, baseline, avatar + weapon + clip + str(fraction))
						if fraction == 0.5 and ((avatar == "sas" and weapon == "glock18" and clip == "reload") or (avatar in ["sas", "leet", "phoenix"] and weapon == "knife")):
							await capture("wrist_seam_" + avatar + "_" + weapon + "_" + String(clip).replace("/", "_"))
				baseline.free()
	player.free()
	print("[WRIST SEAM] ", "PASS: " if failures == 0 else "FAIL: ", checks, " checks; ", failures, " failures")
	get_tree().quit(0 if failures == 0 else 1)
