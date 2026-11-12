class_name ActorRagdoll
extends Node3D
## Real articulated rigid-body death simulation in metres, independent of rig units.
## The live movement capsule and alive bullet hitboxes are never reused or resized.
var rig: Skeleton3D
var owner_actor: Node3D
var links: Array[Dictionary] = []
var age := 0.0
var blood_spawned := false
const PARTS := [
	["pelvis", "spine_2", "", 0.14, 18.0],
	["spine_2", "neck_0", "pelvis", 0.17, 25.0],
	["head_0", "", "spine_2", 0.105, 5.0],
	["arm_upper_L", "arm_lower_L", "spine_2", 0.065, 3.0],
	["arm_lower_L", "hand_L", "arm_upper_L", 0.055, 2.0],
	["arm_upper_R", "arm_lower_R", "spine_2", 0.065, 3.0],
	["arm_lower_R", "hand_R", "arm_upper_R", 0.055, 2.0],
	["leg_upper_L", "leg_lower_L", "pelvis", 0.09, 8.0],
	["leg_lower_L", "ankle_L", "leg_upper_L", 0.07, 4.0],
	["leg_upper_R", "leg_lower_R", "pelvis", 0.09, 8.0],
	["leg_lower_R", "ankle_R", "leg_upper_R", 0.07, 4.0]]

func bone(name: String) -> int:
	var classic := {"spine_2":"Bip01 Spine2", "neck_0":"Bip01 Neck"}
	return rig.find_bone(classic.get(name, SkeletalHitboxes.CLASSIC_BONES.get(name, name)) if rig.find_bone("Bip01 Pelvis") >= 0 else name)

func start(actor, skeleton: Skeleton3D, initial_velocity: Vector3, impulse: Vector3) -> bool:
	owner_actor = actor
	rig = skeleton
	if not is_instance_valid(rig) or bone("pelvis") < 0:
		return false
	# All bone transforms must be sampled BEFORE any overrides are written.
	rig.force_update_all_bone_transforms()
	var by_name: Dictionary = {}
	var size_scale: float = actor.BOT_VISUAL_SCALE if not actor.is_human and not actor.is_vip and ModernAgentPose.is_modern(rig) else 1.0
	for part in PARTS:
		var index := bone(part[0])
		if index < 0: continue
		var bone_world := rig.global_transform * rig.get_bone_global_pose(index)
		var a := bone_world.origin
		var end := bone(part[1]) if not String(part[1]).is_empty() else -1
		var b: Vector3 = (rig.global_transform * rig.get_bone_global_pose(end)).origin if end >= 0 else a + Vector3.UP * 0.10 * size_scale
		var axis := b - a
		var body := RigidBody3D.new()
		body.name = "Ragdoll_" + String(part[0])
		body.mass = part[4]
		body.collision_layer = 4
		body.collision_mask = 1
		body.continuous_cd = true
		body.linear_damp = 0.65
		body.angular_damp = 2.4
		body.max_contacts_reported = 2
		body.contact_monitor = true
		var material := PhysicsMaterial.new()
		material.friction = 0.85
		material.bounce = 0.02
		body.physics_material_override = material
		body.set_meta("actor_ragdoll", self)
		add_child(body)
		body.top_level = true
		body.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, axis.normalized())) if axis.length() > 0.001 else Basis.IDENTITY, (a + b) * 0.5)
		var collider := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = float(part[3]) * size_scale
		capsule.height = maxf(capsule.radius * 2.0, axis.length() + capsule.radius * 0.7)
		collider.shape = capsule
		body.add_child(collider)
		body.linear_velocity = initial_velocity.limit_length(12.0)
		body.angular_velocity = Vector3(0.3, 0.0, -0.2)
		var entry := {"body":body, "bone":index, "offset":body.global_transform.affine_inverse() * bone_world, "anchor":a, "parent":part[2], "name":part[0]}
		links.append(entry)
		by_name[part[0]] = entry
	for entry in links:
		if not by_name.has(entry.parent): continue
		var joint := ConeTwistJoint3D.new()
		add_child(joint)
		joint.global_position = entry.anchor
		joint.node_a = joint.get_path_to(by_name[entry.parent].body)
		joint.node_b = joint.get_path_to(entry.body)
		joint.swing_span = deg_to_rad(65.0 if "arm" in entry.name or "leg" in entry.name else 35.0)
		joint.twist_span = deg_to_rad(30.0)
		joint.bias = 0.35
		joint.relaxation = 1.0
		joint.exclude_nodes_from_collision = true
	if links.is_empty(): return false
	add_to_group("actor_ragdolls")
	(links[0].body as RigidBody3D).apply_central_impulse(impulse.limit_length(65.0))
	return true

func sync_pose() -> void:
	if not is_instance_valid(rig): return
	var inverse := rig.global_transform.affine_inverse()
	for entry in links:
		var body: RigidBody3D = entry.body
		rig.set_bone_global_pose_override(entry.bone, inverse * body.global_transform * entry.offset, 1.0, true)
	rig.force_update_all_bone_transforms()

func _physics_process(delta: float) -> void:
	age += delta
	sync_pose()
	if not blood_spawned and age > 0.35 and not links.is_empty():
		var body: RigidBody3D = links[0].body
		if body.get_contact_count() > 0 and is_instance_valid(RoundManager.game_world):
			var ray := PhysicsRayQueryParameters3D.create(body.global_position, body.global_position - Vector3.UP * 0.8, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				ImpactEffects.spawn_death_blood_pool(RoundManager.game_world, hit.position, hit.normal)
				blood_spawned = true

func apply_bullet_impulse(body: RigidBody3D, position: Vector3, direction: Vector3, damage: float) -> void:
	body.sleeping = false
	body.apply_impulse(direction.normalized() * clampf(damage * 0.045, 0.5, 5.0), position - body.global_position)

func apply_explosion_impulse(center: Vector3, radius: float, speed: float = 16.5) -> void:
	for entry in links:
		var body: RigidBody3D = entry.body
		var direction := body.global_position - center
		var falloff := clampf(1.0 - direction.length() / maxf(radius, 0.01), 0.0, 1.0)
		if falloff <= 0.0: continue
		var ray := PhysicsRayQueryParameters3D.create(center, body.global_position, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		body.sleeping = false
		body.apply_central_impulse((direction.normalized() + Vector3.UP * 0.5) * minf(speed, 20.0) * body.mass * falloff * 0.45)

func stop() -> void:
	if is_instance_valid(rig):
		rig.clear_bones_global_pose_override()
	for entry in links:
		(entry.body as RigidBody3D).collision_layer = 0
		(entry.body as RigidBody3D).freeze = true
	set_physics_process(false)
