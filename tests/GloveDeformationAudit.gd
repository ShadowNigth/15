extends Node3D
## CPU skinning comparison. Numerical edge lengths do not prove visual grip/contact.
var failures := 0
var cases := 0

func find_animation(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer: return n
	for child in n.get_children():
		var result := find_animation(child)
		if result: return result
	return null

func cpu_skin(arrays: Array, skin: Skin, rig: Skeleton3D) -> PackedVector3Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count := bones.size() / vertices.size()
	var transforms: Array[Transform3D] = []
	for bind in skin.get_bind_count():
		var name := String(skin.get_bind_name(bind))
		var bone := rig.find_bone(name) if not name.is_empty() else skin.get_bind_bone(bind)
		transforms.append(rig.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
	var result := PackedVector3Array()
	result.resize(vertices.size())
	for i in vertices.size():
		var v := Vector3.ZERO
		for j in count:
			var k := i * count + j
			if weights[k] > 0.00001: v += (transforms[bones[k]] * vertices[i]) * weights[k]
		result[i] = v
	return result

func measure(source: PackedVector3Array, posed: PackedVector3Array, indices: PackedInt32Array) -> Array:
	var ratios := PackedFloat32Array()
	var max_elongation := 0.0
	for triangle in range(0, indices.size(), 3):
		for edge in 3:
			var a := indices[triangle + edge]
			var b := indices[triangle + (edge + 1) % 3]
			var original := source[a].distance_to(source[b])
			if original < 0.001: continue
			var current := posed[a].distance_to(posed[b])
			ratios.append(current / original)
			max_elongation = maxf(max_elongation, current - original)
	ratios.sort()
	return [ratios[mini(ratios.size() - 1, int(float(ratios.size() - 1) * 0.99))], max_elongation * 1000.0]

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	for option in ["5033_10078", "amphibious_ft"]:
		GameData.select_glove(option)
		var model := String(GameData.get_selected_glove().native_model)
		var source := (load(String(NativeViewRig.catalog().gloves[model].model)) as PackedScene).instantiate()
		add_child(source)
		var original_mesh := SportGloves._find_meshes(source)[0]
		var original_rig := original_mesh.get_node(original_mesh.skeleton) as Skeleton3D
		for weapon in ["v_ak47", "v_glock18", "v_awp", "v_knife"]:
			var root := GameData.get_model_scene("weapons/" + weapon).instantiate() as Node3D
			add_child(root)
			if not NativeViewRig.install(root, weapon, "sas"):
				push_error("Cannot install " + model + " " + weapon)
				failures += 1
				root.free()
				continue
			var native := root.get_meta("native_view_rig") as NativeViewRig
			var animation := find_animation(root)
			for clip in ["idle", "inspect", "reload"]:
				if animation == null:
					push_error("Missing animation player " + weapon)
					failures += 1
					continue
				if not animation.has_animation(clip): continue
				for phase in [0.0, 0.5, 0.95]:
					animation.play(clip)
					animation.pause()
					animation.seek(animation.get_animation(clip).length * phase, true)
					native.sync_pose()
					for mesh in SportGloves._find_meshes(native):
						if not mesh.visible: continue
						var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
						for surface in mesh.mesh.get_surface_count():
							var mat := mesh.mesh.surface_get_material(surface)
							var name := String(mat.resource_name)
							if not name.begins_with("glove_"): continue
							var original_surface := -1
							for s in original_mesh.mesh.get_surface_count():
								if original_mesh.mesh.surface_get_material(s).resource_name == mat.resource_name: original_surface = s
							if original_surface < 0:
								failures += 1
								continue
							var source_arrays := original_mesh.mesh.surface_get_arrays(original_surface)
							var baseline := original_mesh.mesh.surface_get_arrays(original_surface)
							var side := "L" if name.ends_with("_left") else "R"
							if not NativeViewRig._swap_glove_surface(baseline, original_mesh.skin, original_rig, side, 0.0):
								failures += 1
								continue
							var before := measure(source_arrays[Mesh.ARRAY_VERTEX], cpu_skin(baseline, mesh.skin, rig), source_arrays[Mesh.ARRAY_INDEX])
							var after := measure(source_arrays[Mesh.ARRAY_VERTEX], cpu_skin(mesh.mesh.surface_get_arrays(surface), mesh.skin, rig), source_arrays[Mesh.ARRAY_INDEX])
							cases += 1
							print("GLOVE EDGE ", model, " ", weapon, " ", clip, " ", side, " phase ", phase, " p99 ", before[0], " -> ", after[0], " max mm ", before[1], " -> ", after[1])
							if not (float(after[0]) < float(before[0]) and float(after[1]) < float(before[1])):
								push_error("No improvement in " + model + " " + weapon + " " + clip + " " + side)
								failures += 1
			root.free()
		source.free()
	if cases != 132:
		push_error("Expected 132 cases, got " + str(cases))
		failures += 1
	print("GLOVE DEFORMATION AUDIT: ", cases, " cases, ", failures, " failures")
	get_tree().quit(1 if failures else 0)
