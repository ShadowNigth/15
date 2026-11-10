class_name ClassicPoseFit
extends RefCounted
## Small, reversible corrections of the existing classic rig; no mesh scaling,
## replacement animations, weapon transforms, or actor/capsule displacement.
var _saved: Dictionary = {}
var _skeleton: Skeleton3D
var _grip := Vector3.ZERO
var _weapon: String = ""
var _has_grip: bool = false

func restore() -> void:
	if is_instance_valid(_skeleton):
		for bone in _saved:
			var pose: Transform3D = _saved[bone]
			_skeleton.set_bone_pose_position(bone, pose.origin)
			_skeleton.set_bone_pose_rotation(bone, pose.basis.get_rotation_quaternion())
			_skeleton.set_bone_pose_scale(bone, pose.basis.get_scale())
	_saved.clear()

func _remember(bone: int) -> void:
	if not _saved.has(bone):
		_saved[bone] = _skeleton.get_bone_pose(bone)

func _rotate_to(bone: int, world_basis: Basis) -> void:
	_remember(bone)
	var parent := _skeleton.get_bone_parent(bone)
	var parent_basis := _skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	_skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse()*world_basis).orthonormalized().get_rotation_quaternion())

func solve_chain(root: int, middle: int, tip: int, target: Vector3) -> bool:
	if mini(root, mini(middle, tip)) < 0:
		return false
	var a := _skeleton.get_bone_global_pose(root).origin
	var b := _skeleton.get_bone_global_pose(middle).origin
	var c := _skeleton.get_bone_global_pose(tip).origin
	var first := a.distance_to(b)
	var second := b.distance_to(c)
	var axis := target-a
	if first < 0.001 or second < 0.001 or axis.length() < 0.001:
		return false
	var reach := clampf(axis.length(), absf(first-second)+0.001, first+second-0.001)
	axis = axis.normalized()
	var bend := b-a-axis*(b-a).dot(axis)
	if bend.length_squared() < 0.00001:
		bend = Vector3.FORWARD-axis*Vector3.FORWARD.dot(axis)
	if bend.length_squared() < 0.00001:
		return false
	var along := (first*first-second*second+reach*reach)/(2.0*reach)
	var knee := a+axis*along+bend.normalized()*sqrt(maxf(0.0, first*first-along*along))
	var old_tip_basis := _skeleton.get_bone_global_pose(tip).basis
	_rotate_to(root, Basis(Quaternion((b-a).normalized(), (knee-a).normalized()))*_skeleton.get_bone_global_pose(root).basis)
	b = _skeleton.get_bone_global_pose(middle).origin
	c = _skeleton.get_bone_global_pose(tip).origin
	var endpoint := a+axis*reach
	_rotate_to(middle, Basis(Quaternion((c-b).normalized(), (endpoint-b).normalized()))*_skeleton.get_bone_global_pose(middle).basis)
	_rotate_to(tip, old_tip_basis)
	return true

func fit(actor, skeleton: Skeleton3D, native_action: bool) -> void:
	_skeleton = skeleton
	if not actor.is_alive or not actor.is_on_floor() or actor.on_ladder or actor.in_water:
		return
	# Do not pin the animated swing foot during a run or alter native crouch poses.
	if Vector2(actor.velocity.x, actor.velocity.z).length() < 0.7 and not actor.is_crouching:
		for side in ["L", "R"]:
			var foot := skeleton.find_bone("Bip01 %s Foot" % side)
			if foot < 0:
				continue
			var ankle := skeleton.global_transform*skeleton.get_bone_global_pose(foot).origin
			var query := PhysicsRayQueryParameters3D.create(ankle+Vector3.UP*0.18, ankle-Vector3.UP*0.28, 1)
			var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
				continue
			var offset := clampf((hit.position as Vector3).y+0.055-ankle.y, -0.10, 0.10)
			if absf(offset) > 0.008:
				solve_chain(skeleton.find_bone("Bip01 %s Thigh" % side), skeleton.find_bone("Bip01 %s Calf" % side), foot, skeleton.to_local(ankle+Vector3.UP*offset))
	var wid: String = actor.weapon_ctrl.current_weapon_id
	if _weapon != wid:
		_weapon = wid
		_has_grip = false
	if native_action or wid in ["knife", "elite", "c4"] or bool(actor.weapon_ctrl.get_current_spec().get("grenade", false)):
		return
	var right := skeleton.find_bone("Bip01 R Hand")
	var left := skeleton.find_bone("Bip01 L Hand")
	if right < 0 or left < 0:
		return
	var anchor := skeleton.get_bone_global_pose(right)
	var hand := skeleton.get_bone_global_pose(left).origin
	if not _has_grip:
		_grip = anchor.affine_inverse()*hand
		_has_grip = true
	var target := anchor*_grip
	# Never pull a hand across an incompatible authored pose or a one-handed pistol.
	if int(actor.weapon_ctrl.get_current_spec().get("slot", 0)) == 1 and target.distance_to(hand) > 0.006 and target.distance_to(hand) < 0.12:
		solve_chain(skeleton.find_bone("Bip01 L UpperArm"), skeleton.find_bone("Bip01 L Forearm"), left, target)


func fit_modern_support(skeleton: Skeleton3D, target_world: Vector3) -> bool:
	_skeleton = skeleton
	return solve_chain(skeleton.find_bone("arm_upper_L"), skeleton.find_bone("arm_lower_L"), skeleton.find_bone("hand_L"), skeleton.to_local(target_world))
