class_name GlovePalmRoll
extends Node3D
## Cosmetic-only post-pose half-turn. Original weapon/agent rig is never edited.
var source_rig: Skeleton3D
var displays: Array[Dictionary] = []

func configure(source: MeshInstance3D, rig: Skeleton3D) -> void:
	source_rig = rig
	process_priority = 50
	for surface in source.mesh.get_surface_count():
		var material := source.get_active_material(surface)
		var side := "R" if material.resource_name.ends_with("left") else "L"
		var prefix := "v_weapon.Bip01_" + side + "_"
		var wrist := AgentViewArms._bone(rig, prefix + "Hand")
		var middle := AgentViewArms._bone(rig, prefix + "Finger2")
		var display_rig := Skeleton3D.new()
		display_rig.name = "RolledGloveRig" + side
		add_child(display_rig)
		for bone in rig.get_bone_count():
			display_rig.add_bone(rig.get_bone_name(bone))
			display_rig.set_bone_parent(bone, rig.get_bone_parent(bone))
			display_rig.set_bone_rest(bone, rig.get_bone_rest(bone))
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.mesh.surface_get_arrays(surface))
		mesh.surface_set_material(0, material)
		var hand := MeshInstance3D.new()
		hand.name = "RolledGlove" + side
		hand.mesh = mesh
		hand.skin = source.skin
		hand.layers = source.layers
		hand.cast_shadow = source.cast_shadow
		for key in source.get_meta_list(): hand.set_meta(key, source.get_meta(key))
		hand.set_meta("palm_roll_degrees", 180)
		add_child(hand)
		hand.skeleton = hand.get_path_to(display_rig)
		displays.append({"rig": display_rig, "wrist": wrist, "middle": middle})
	source.hide()
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	if not is_instance_valid(source_rig):
		return
	source_rig.force_update_all_bone_transforms()
	for entry in displays:
		var rig: Skeleton3D = entry.rig
		rig.global_transform = source_rig.global_transform
		var wrist: int = entry.wrist
		var middle: int = entry.middle
		if wrist < 0 or middle < 0:
			continue
		var roll := AgentViewArms._palm_roll(source_rig.get_bone_global_pose(wrist).origin, source_rig.get_bone_global_pose(middle).origin)
		# Transform every posed bone by the SAME rigid transform, so weighted
		# finger seams stay together and the complete animated glove is rolled.
		for bone in rig.get_bone_count():
			rig.set_bone_global_pose_override(bone, roll * source_rig.get_bone_global_pose(bone), 1.0, true)
		rig.force_update_all_bone_transforms()
