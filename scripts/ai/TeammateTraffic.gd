class_name TeammateTraffic
extends RefCounted
## Original actor-space negotiation. Does not change capsule masks or GoldSrc physics.
var mode: String = "clear"
var peer: WeakRef
var intent := Vector3.ZERO
var retreat := Vector3.ZERO
var _side := Vector3.ZERO
var _stalled_time: float = 0.0
var _retry_time: float = 0.0

func reset() -> void:
	mode = "clear"
	peer = null
	intent = Vector3.ZERO
	retreat = Vector3.ZERO
	_side = Vector3.ZERO
	_stalled_time = 0.0
	_retry_time = 0.0

static func priority(actor: CSActor) -> int:
	if actor.is_human:
		return 100
	if actor.is_vip:
		return 80
	var planted := RoundManager.planted_c4 as PlantedC4
	if planted != null and planted.defuser_actor == actor:
		return 90
	if actor.has_method("_is_leading_hostage") and bool(actor.call("_is_leading_hostage")):
		return 70
	if actor.weapon_ctrl != null and String(actor.weapon_ctrl.slots.get(5, "")) == "c4":
		return 60
	return 0

func safe_motion(actor: CSActor, direction: Vector3, distance: float = 0.95) -> bool:
	if direction.length_squared() < 0.01 or actor.test_move(actor.global_transform, direction * distance):
		return false
	# A lateral escape is never permitted off a bridge/ledge or onto another floor.
	var end := actor.global_position + direction * distance
	var query := PhysicsRayQueryParameters3D.create(end + Vector3.UP * 0.32, end - Vector3.UP * 0.65, 1)
	var floor_hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not floor_hit.is_empty() and (floor_hit.normal as Vector3).y >= 0.7

func steer(actor: CSActor, desired: Vector3, actors: Array, delta: float = 1.0/60.0) -> Vector3:
	intent = desired
	if _retry_time > 0.0:
		_retry_time = maxf(0.0, _retry_time-delta)
		mode = "retry"
		return desired
	mode = "clear"
	if actor.on_ladder or not actor.is_on_floor() or desired.length_squared() < 0.01:
		peer = null
		return desired
	var heading := Vector3(desired.x, 0, desired.z).normalized()
	var other: CSActor = null
	var nearest := 2.8
	for candidate in actors:
		var mate := candidate as CSActor
		if not is_instance_valid(mate) or mate == actor or not mate.is_alive or mate.team != actor.team or absf(mate.global_position.y-actor.global_position.y) > 0.65:
			continue
		var gap := mate.global_position-actor.global_position
		gap.y = 0
		var ahead := gap.dot(heading)
		if ahead > -0.1 and ahead < nearest and (gap-heading*ahead).length() < 0.77:
			nearest = ahead
			other = mate
	# Keep retreating in the same direction until the advancing peer has passed.
	var retained: CSActor = peer.get_ref() as CSActor if peer != null else null
	if is_instance_valid(retained) and retained.is_alive and retained.team == actor.team and actor.global_position.distance_to(retained.global_position) < 3.0:
		var relative := retained.global_position-actor.global_position
		if relative.dot(retreat) < 0.2 and absf(relative.y) < 0.65:
			other = retained
	if other == null:
		_stalled_time = 0.0
		peer = null
		return desired
	# A virtual encounter must never deadlock a mission. After sustained lack
	# of progress between bots, hand intent briefly back to native navigation.
	# This does not move/teleport actors, change their masks or force a human back.
	if Vector2(actor.velocity.x, actor.velocity.z).length() < 0.15:
		_stalled_time += delta
	else:
		_stalled_time = maxf(0.0, _stalled_time-delta*0.5)
	if _stalled_time > 2.5 and not other.is_human:
		_stalled_time = 0.0
		_retry_time = 0.9
		peer = null
		mode = "retry"
		return desired
	var gap := other.global_position-actor.global_position
	gap.y = 0
	var mate_intent := Vector3(other.velocity.x, 0, other.velocity.z)
	if other.has_method("get_traffic_intent"):
		var planned: Vector3 = other.call("get_traffic_intent")
		if planned.length_squared() > 0.01:
			mate_intent = planned
	if mate_intent.dot(heading) > 0.2 and peer == null:
		mode = "follow"
		return desired if gap.length() > 1.8 else Vector3.ZERO
	var yields := priority(actor) < priority(other) or (priority(actor) == priority(other) and actor.get_instance_id() > other.get_instance_id())
	if not yields:
		mode = "wait" if gap.length() < 2.1 else "advance"
		return Vector3.ZERO if mode == "wait" else desired
	if peer == null or peer.get_ref() != other:
		peer = weakref(other)
		_side = Vector3.ZERO
		retreat = -heading
	# Step to the actor's right, then left; keep the side until there is clearance.
	if _side.length_squared() > 0.01 and safe_motion(actor, _side):
		mode = "sidestep"
		return _side
	var side := heading.cross(Vector3.UP).normalized()
	for choice in [side, -side]:
		if safe_motion(actor, choice):
			mode = "sidestep"
			_side = choice
			return choice
	mode = "yield"
	return retreat if safe_motion(actor, retreat, 0.55) else Vector3.ZERO
