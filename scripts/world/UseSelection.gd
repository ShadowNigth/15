class_name UseSelection
extends RefCounted
## Aim-selected use. World blockers always win over nearby fallback pickups.
static func drop_allowed(actor: CSActor, drop: DroppedWeapon) -> bool:
	if drop.is_queued_for_deletion() or actor.is_vip or drop._pickup_cooldown > 0.0 or (drop.pickup_lock_actor == actor and drop.pickup_lock_time > 0.0):
		return false
	if drop.item_id == "c4":
		return actor.team == "T" and String(actor.weapon_ctrl.slots.get(5, "")).is_empty()
	if drop.item_id == "defuser":
		return actor.team == "CT" and not actor.has_defuser
	var spec: Dictionary = GameData.weapons.get(drop.item_id, {})
	if spec.is_empty():
		return false
	if bool(spec.get("grenade", false)):
		return int(actor.weapon_ctrl.grenades.get(drop.item_id, 0)) < int(spec.get("max_ammo", 1))
	return int(spec.get("slot", 0)) in [1, 2] and String(actor.weapon_ctrl.slots.get(int(spec.slot), "")) != drop.item_id

static func visible(actor: CSActor, point: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(actor.get_eye_position(), point, 1)
	q.exclude = [actor.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

static func select(actor: CSActor) -> Dictionary:
	var eye := actor.get_eye_position()
	var forward := actor.get_look_forward()
	var space := actor.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye+forward*2.8, 1 | 2 | 4)
	q.exclude = [actor.get_rid()]
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		var collider: Node = hit.collider
		if collider is DroppedWeapon and drop_allowed(actor, collider):
			return {"kind": "drop", "target": collider}
		if collider is HostageNPC:
			return {"kind": "hostage", "target": collider}
		if collider.has_meta("door"):
			return {"kind": "door", "target": collider.get_meta("door")}
		if collider.has_meta("button_target"):
			return {"kind": "button", "target": collider}
	# Ground items need a small aim cone, not a point-perfect ray onto a thin rifle.
	var best: DroppedWeapon = null
	var best_score := INF
	for raw in RoundManager.dropped_items:
		var drop := raw as DroppedWeapon
		if not is_instance_valid(drop) or not drop_allowed(actor, drop):
			continue
		var to_item := drop.global_position-eye
		var distance := Vector2(drop.global_position.x-actor.global_position.x, drop.global_position.z-actor.global_position.z).length()
		if distance > 2.3 or to_item.length_squared() < 0.001 or forward.dot(to_item.normalized()) < 0.88:
			continue
		if not visible(actor, drop.global_position+Vector3.UP*0.06):
			continue
		var score := to_item.length() + (1.0-forward.dot(to_item.normalized()))*5.0
		if score < best_score:
			best = drop
			best_score = score
	return {"kind": "drop", "target": best} if best != null else {}
