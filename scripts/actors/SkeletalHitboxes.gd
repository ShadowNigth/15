class_name SkeletalHitboxes
extends Node3D
## Bullet-only capsules follow actual animated bones; movement uses its old hull.
var actor: Node3D
var skeleton: Skeleton3D
var entries: Array[Dictionary] = []
const REGIONS := [
	["head_0", "head_0", 0.115, 1], ["spine_1", "spine_3", 0.15, 2],
	["pelvis", "spine_1", 0.17, 3],
	["arm_upper_L", "arm_lower_L", 0.075, 4], ["arm_lower_L", "hand_L", 0.065, 4],
	["arm_upper_R", "arm_lower_R", 0.075, 5], ["arm_lower_R", "hand_R", 0.065, 5],
	["leg_upper_L", "leg_lower_L", 0.10, 6], ["leg_lower_L", "ankle_L", 0.085, 6],
	["leg_upper_R", "leg_lower_R", 0.10, 7], ["leg_lower_R", "ankle_R", 0.085, 7]]

func setup(owner_actor: Node3D, rig: Skeleton3D) -> void:
	actor = owner_actor
	skeleton = rig
	actor.add_to_group("skeletal_bullet_actors")
	for region in REGIONS:
		var first := rig.find_bone(region[0])
		var second := rig.find_bone(region[1])
		if first < 0 or second < 0:
			continue
		var area := Area3D.new()
		area.collision_layer = 16
		area.collision_mask = 0
		area.monitoring = false
		area.set_meta("bullet_actor", actor)
		area.set_meta("hitgroup", region[3])
		add_child(area)
		var collider := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = region[2]
		shape.height = region[2] * 2.0
		collider.shape = shape
		area.add_child(collider)
		entries.append({"area": area, "shape": shape, "a": first, "b": second, "radius": region[2]})
	sync_pose()

func sync_pose() -> void:
	if not is_instance_valid(skeleton):
		return
	skeleton.force_update_all_bone_transforms()
	for entry in entries:
		var area: Area3D = entry["area"]
		area.collision_layer = 16 if actor.is_alive else 0
		var a: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(entry["a"]).origin
		var b: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(entry["b"]).origin
		if entry["a"] == entry["b"]:
			a += Vector3.UP * 0.035
			b = a
		var distance := a.distance_to(b)
		var shape: CapsuleShape3D = entry["shape"]
		shape.height = maxf(entry["radius"] * 2.0, distance + entry["radius"] * 2.0)
		var rotation := Quaternion(Vector3.UP, (b - a).normalized()) if distance > 0.0001 else Quaternion.IDENTITY
		area.global_transform = Transform3D(Basis(rotation), (a + b) * 0.5)

static func exclusions(tree: SceneTree, shooter: CollisionObject3D) -> Array[RID]:
	var result: Array[RID] = [shooter.get_rid()]
	for candidate in tree.get_nodes_in_group("skeletal_bullet_actors"):
		if not is_instance_valid(candidate) or not candidate.is_inside_tree():
			continue
		result.append(candidate.get_rid())
		if candidate == shooter:
			var boxes: SkeletalHitboxes = candidate.get_node_or_null("SkeletalHitboxes")
			if boxes:
				for entry in boxes.entries:
					result.append(entry["area"].get_rid())
	return result

static func exclude_target(result: Array[RID], target: Node3D) -> void:
	if target is CollisionObject3D:
		result.append(target.get_rid())
	var boxes: SkeletalHitboxes = target.get_node_or_null("SkeletalHitboxes")
	if boxes:
		for entry in boxes.entries:
			result.append(entry["area"].get_rid())
