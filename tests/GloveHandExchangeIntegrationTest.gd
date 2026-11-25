extends Node3D

var checks := 0
var failures := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 20: push_error(message)

func find_animation(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node as AnimationPlayer
	for child in node.get_children():
		var result := find_animation(child)
		if result: return result
	return null

func _ready() -> void:
	run.call_deferred()

func run() -> void:
	var options := GameData.get_glove_options()
	for option in options:
		expect(GameData.select_glove(String(option.id)), "select " + String(option.id))
		var root := GameData.get_model_scene("weapons/v_ak47").instantiate() as Node3D
		add_child(root)
		var installed := NativeViewRig.install(root, "v_ak47", "sas")
		expect(installed, "install " + String(option.id))
		if installed:
			var native := root.get_meta("native_view_rig") as NativeViewRig
			var surfaces := 0
			for mesh in SportGloves._find_meshes(native):
				if not mesh.visible: continue
				var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
				for surface in mesh.mesh.get_surface_count():
					var material := mesh.get_active_material(surface) as BaseMaterial3D
					var name := String(material.resource_name)
					if not name.begins_with("glove_"): continue
					surfaces += 1
					var side := "L" if name.ends_with("_left") else "R"
					var other := "R" if side == "L" else "L"
					expect(material.albedo_texture == GameData.get_texture(String(option.native_textures.get(name, ""))), "original surface retains its texture")
					var arrays := mesh.mesh.surface_get_arrays(surface)
					var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
					var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
					for i in bones.size():
						if weights[i] <= 0.00001: continue
						var bind := String(mesh.skin.get_bind_name(bones[i]))
						if bind.is_empty(): bind = String(rig.get_bone_name(mesh.skin.get_bind_bone(bones[i])))
						expect(bind.contains("_" + other), "glove surface must follow opposite hand")
			expect(surfaces == 2, "both glove surfaces present")
			var animation := find_animation(root)
			if animation:
				for clip in ["idle", "inspect", "reload"]:
					if not animation.has_animation(clip): continue
					animation.play(clip)
					animation.pause()
					for phase in [0.0, 0.5, 0.95]:
						animation.seek(animation.get_animation(clip).length * phase, true)
						native.sync_pose()
						for binding in native.bindings:
							var skeleton: Skeleton3D = binding.rig
							for side in ["L", "R"]:
								var hand := skeleton.find_bone("hand_" + side)
								if hand >= 0: expect(skeleton.get_bone_global_pose(hand).origin.is_finite(), "finite animated hand")
		root.free()
	# Representative clips on other weapon families also use the swapped rig.
	for glove in ["5033_10078", "amphibious_ft"]:
		GameData.select_glove(glove)
		for model in ["v_glock18", "v_awp", "v_knife"]:
			var root := GameData.get_model_scene("weapons/" + model).instantiate() as Node3D
			add_child(root)
			var installed := NativeViewRig.install(root, model, "sas")
			expect(installed, "install " + glove + " " + model)
			if installed:
				var native := root.get_meta("native_view_rig") as NativeViewRig
				var animation := find_animation(root)
				if animation:
					for clip in ["idle", "inspect", "reload"]:
						if not animation.has_animation(clip): continue
						animation.play(clip)
						animation.pause()
						for phase in [0.0, 0.5, 0.95]:
							animation.seek(animation.get_animation(clip).length * phase, true)
							native.sync_pose()
							for binding in native.bindings:
								var skeleton: Skeleton3D = binding.rig
								for side in ["L", "R"]:
									var hand := skeleton.find_bone("hand_" + side)
									if hand >= 0: expect(skeleton.get_bone_global_pose(hand).origin.is_finite(), "finite " + model + " hand")
			root.free()
	print("GLOVE EXCHANGE INTEGRATION: ", options.size(), " finishes, ", checks, " checks, ", failures, " failures")
	get_tree().quit(1 if failures else 0)
