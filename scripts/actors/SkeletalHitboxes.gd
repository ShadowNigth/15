class_name SkeletalHitboxes
extends Node3D
## Bullet-only capsules follow actual animated bones; movement uses its old hull.
var actor: Node3D
var skeleton: Skeleton3D
var entries: Array[Dictionary] = []
var body_scale: float = 1.0
const REGIONS := [
	["head_0", "head_0", 0.115, 1], ["spine_1", "spine_3", 0.15, 2],
	["pelvis", "spine_1", 0.17, 3],
	["arm_upper_L", "arm_lower_L", 0.075, 4], ["arm_lower_L", "hand_L", 0.065, 4],
	["arm_upper_R", "arm_lower_R", 0.075, 5], ["arm_lower_R", "hand_R", 0.065, 5],
	["leg_upper_L", "leg_lower_L", 0.10, 6], ["leg_lower_L", "ankle_L", 0.085, 6],
	["leg_upper_R", "leg_lower_R", 0.10, 7], ["leg_lower_R", "ankle_R", 0.085, 7]]

const CLASSIC_BONES := {
	"head_0": "Bip01 Head", "pelvis": "Bip01 Pelvis", "spine_1": "Bip01 Spine1", "spine_3": "Bip01 Spine3",
	"arm_upper_L": "Bip01 L UpperArm", "arm_lower_L": "Bip01 L Forearm", "hand_L": "Bip01 L Hand",
	"arm_upper_R": "Bip01 R UpperArm", "arm_lower_R": "Bip01 R Forearm", "hand_R": "Bip01 R Hand",
	"leg_upper_L": "Bip01 L Thigh", "leg_lower_L": "Bip01 L Calf", "ankle_L": "Bip01 L Foot",
	"leg_upper_R": "Bip01 R Thigh", "leg_lower_R": "Bip01 R Calf", "ankle_R": "Bip01 R Foot"}

func setup(owner_actor: Node3D, rig: Skeleton3D, visual_scale: float = 1.0) -> void:
	body_scale = visual_scale
	actor = owner_actor
	skeleton = rig
	actor.add_to_group("skeletal_bullet_actors")
	for region in REGIONS:
		var first := rig.find_bone(CLASSIC_BONES.get(region[0], region[0]) if rig.find_bone("Bip01 Pelvis") >= 0 else region[0])
		var second := rig.find_bone(CLASSIC_BONES.get(region[1], region[1]) if rig.find_bone("Bip01 Pelvis") >= 0 else region[1])
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
		shape.radius = region[2] * body_scale
		shape.height = shape.radius * 2.0
		collider.shape = shape
		area.add_child(collider)
		entries.append({"area": area, "shape": shape, "a": first, "b": second, "radius": shape.radius, "hitgroup": int(region[3])})
		if int(region[3]) == 1:
			fit_head(entries[-1])
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
		if entry.has("head_center"):
			var frame := skeleton.global_transform * skeleton.get_bone_global_pose(entry["a"])
			var center: Vector3 = frame * entry["head_center"]
			var axis: Vector3 = (frame.basis * entry["head_axis"]).normalized()
			a = center - axis * float(entry["head_segment"]) * 0.5
			b = center + axis * float(entry["head_segment"]) * 0.5
		elif entry["a"] == entry["b"]:
			# Fallback offset rotates with the head, not with world-up.
			var frame := skeleton.global_transform * skeleton.get_bone_global_pose(entry["a"])
			a = frame * Vector3(0, 0.035, 0)
			b = a
		var distance := a.distance_to(b)
		var shape: CapsuleShape3D = entry["shape"]
		shape.height = maxf(entry["radius"] * 2.0, distance + entry["radius"] * 2.0)
		var rotation := Quaternion(Vector3.UP, (b - a).normalized()) if distance > 0.0001 else Quaternion.IDENTITY
		area.global_transform = Transform3D(Basis(rotation), (a + b) * 0.5)

func fit_head(entry: Dictionary) -> void:
	var head: int = entry["a"]
	var bounds := AABB()
	var samples := 0
	var rest_inverse := skeleton.get_bone_global_rest(head).affine_inverse()
	for raw in actor._body_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := raw as MeshInstance3D
		if mesh.skin == null or mesh.mesh == null or mesh.has_meta("first_person_lower_body"):
			continue
		var head_bindings: Array[bool] = []
		for bind in mesh.skin.get_bind_count():
			var name := String(mesh.skin.get_bind_name(bind))
			var bone := skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(bind)
			var descendant := bone == head
			while bone >= 0 and not descendant:
				bone = skeleton.get_bone_parent(bone)
				descendant = bone == head
			head_bindings.append(descendant)
		var transform := rest_inverse * skeleton.global_transform.affine_inverse() * mesh.global_transform
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if bones.is_empty(): continue
			var stride: int = bones.size() / maxi(1, vertices.size())
			for vertex in vertices.size():
				var influence := 0.0
				for slot in stride:
					var offset := vertex * stride + slot
					if bones[offset] < head_bindings.size() and head_bindings[bones[offset]]:
						influence += weights[offset]
				if influence < 0.65: continue
				var point := transform * vertices[vertex]
				bounds = AABB(point, Vector3.ZERO) if samples == 0 else bounds.expand(point)
				samples += 1
	if samples < 12: return
	var scale := (skeleton.global_transform * skeleton.get_bone_global_rest(head)).basis.get_scale().abs()
	var size := bounds.size * scale
	var axis_index := size.max_axis_index()
	var axis := Vector3.ZERO
	axis[axis_index] = 1.0
	var widths: Array[float] = []
	for index in 3:
		if index != axis_index: widths.append(size[index])
	var radius := clampf(maxf(widths[0], widths[1]) * 0.48, 0.065 * body_scale, 0.145 * body_scale)
	var height := clampf(size[axis_index], radius * 2.0, 0.34 * body_scale)
	entry["radius"] = radius
	entry["head_center"] = bounds.get_center()
	entry["head_axis"] = axis
	entry["head_segment"] = maxf(0, height - radius * 2.0)
	entry["fitted_vertices"] = samples
	(entry["shape"] as CapsuleShape3D).radius = radius


static func exclusions(tree: SceneTree, shooter: CollisionObject3D) -> Array[RID]:
	var result: Array[RID] = [shooter.get_rid()]
	for support in tree.get_nodes_in_group("weapon_ray_excluded_support"):
		if support is CollisionObject3D and support.is_inside_tree():
			result.append(support.get_rid())
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
