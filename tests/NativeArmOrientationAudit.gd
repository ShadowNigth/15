extends Node3D
## Check the production rig, not the historical AgentViewArms pipeline.
## These numerical tests do not establish anatomical appearance or contact.
var checks := 0
var failures := 0
var max_wrist_gap := 0.0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
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
	var avatars: Dictionary = NativeViewRig.catalog().agents
	for avatar in avatars:
		for option in ["5033_10078", "amphibious_ft"]:
			GameData.select_glove(option)
			for model in ["v_ak47", "v_glock18", "v_awp", "v_knife"]:
				var root := GameData.get_model_scene("weapons/" + model).instantiate() as Node3D
				add_child(root)
				var installed := NativeViewRig.install(root, model, avatar)
				expect(installed, "install " + avatar + " " + option + " " + model)
				if installed:
					var native := root.get_meta("native_view_rig") as NativeViewRig
					var anim := find_animation(root)
					for clip in ["idle", "inspect"]:
						if anim == null or not anim.has_animation(clip): continue
						anim.play(clip)
						anim.pause()
						anim.seek(anim.get_animation(clip).length * 0.5, true)
						native.sync_pose()
						for binding in native.bindings:
							var rig: Skeleton3D = binding.rig
							var space := rig.global_transform.affine_inverse() * native.target.global_transform
							for driver in binding.drivers:
								var name := String(rig.get_bone_name(driver.source))
								if not (name.begins_with("hand_") or name.begins_with("arm_lower_") or name.begins_with("arm_upper_")): continue
								var pose := rig.get_bone_global_pose(driver.source)
								var original: Transform3D = space * native.target.get_bone_global_pose(driver.target) * driver.correction
								expect(pose.origin.is_finite() and absf(pose.basis.determinant()) > 0.001, "invalid arm pose " + name)
								expect(pose.basis.determinant() * original.basis.determinant() > 0.0, "arm transform changed handedness " + name)
						if native.bindings.size() >= 2:
							var a: Skeleton3D = native.bindings[0].rig
							var b: Skeleton3D = native.bindings[1].rig
							for side in ["L", "R"]:
								var ai := a.find_bone("hand_" + side)
								var bi := b.find_bone("hand_" + side)
								if ai >= 0 and bi >= 0:
									var pa := a.global_transform * a.get_bone_global_pose(ai).origin
									var pb := b.global_transform * b.get_bone_global_pose(bi).origin
									max_wrist_gap = maxf(max_wrist_gap, pa.distance_to(pb))
				root.free()
	print("NATIVE ARM ORIENTATION: ", checks, " checks, ", failures, " failures; max wrist anchor separation mm ", max_wrist_gap * 1000.0)
	get_tree().quit(1 if failures else 0)
