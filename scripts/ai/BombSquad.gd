class_name BombSquad
extends RefCounted
## Original deterministic election. Called on existing AI think steps, not per frame.
static func elect_defuser(bomb: PlantedC4, actors: Array, nav: BotNavigator = null) -> CSActor:
	if is_instance_valid(bomb.defuser_actor) and bool(bomb.defuser_actor.get("is_alive")):
		return bomb.defuser_actor as CSActor
	var saved: Variant = bomb.get_meta("squad_choice", null)
	if saved is WeakRef:
		var previous := (saved as WeakRef).get_ref() as CSActor
		if is_instance_valid(previous) and previous.is_alive and previous.team == "CT" and Engine.get_physics_frames() < int(bomb.get_meta("squad_until", 0)):
			return previous
	var best: CSActor = null
	var best_cost := INF
	for raw in actors:
		var actor := raw as CSActor
		if not is_instance_valid(actor) or not actor.is_alive or actor.team != "CT" or actor.is_human:
			continue
		var distance := actor.global_position.distance_to(bomb.global_position)
		var required := 5.0 if actor.has_defuser else 10.0
		var cost := distance / 5.0 + required
		if distance > 2.35 and nav != null:
			var goal := nav.get_nearest_node(bomb.global_position)
			var banned: Dictionary = actor.call("get_bomb_banned_nodes") if actor.has_method("get_bomb_banned_nodes") else {}
			var path := nav.plan_node_path(actor.global_position, goal, "CT", BotNavigator.PATH_FAST, false, actor.get_world_3d().direct_space_state, 0, banned)
			if goal < 0 or path.is_empty():
				continue
			cost = (actor.global_position.distance_to(nav.get_node_pos(path[0])) + nav.get_path_tactical_cost(path, "CT"))/5.0 + required
		if cost >= bomb.time_left - 0.15:
			continue
		if cost < best_cost - 0.8 or (best == null):
			best = actor
			best_cost = cost
		elif absf(cost-best_cost) <= 0.8 and actor.get_instance_id() < best.get_instance_id():
			best = actor
			best_cost = cost
	if best != null:
		bomb.set_meta("squad_choice", weakref(best))
		bomb.set_meta("squad_until", Engine.get_physics_frames() + 75)
	return best

static func objective_node(actor: CSActor, center: Vector3, nav: BotNavigator, actors: Array) -> int:
	var defuser := elect_defuser(RoundManager.planted_c4 as PlantedC4, actors) if actor.team == "CT" and is_instance_valid(RoundManager.planted_c4) else null
	var rank := 0
	var count := 0
	for raw in actors:
		var mate := raw as CSActor
		if is_instance_valid(mate) and mate.is_alive and not mate.is_human and mate.team == actor.team and mate != defuser:
			count += 1
			if mate.get_instance_id() < actor.get_instance_id():
				rank += 1
	var angle := TAU * float(rank) / maxf(1.0, float(count))
	var ideal := center + Vector3(cos(angle), 0, sin(angle))*6.0
	var best := -1
	var best_score := INF
	var banned: Dictionary = actor.call("get_bomb_banned_nodes") if actor.has_method("get_bomb_banned_nodes") else {}
	for i in range(nav.waypoints.size()):
		var p := nav.get_node_pos(i)
		var d := p.distance_to(center)
		if d < 3.0 or d > 11.0 or absf(p.y-center.y) > 2.0 or (nav.get_node_flags(i) & BotNavigator.ACTION_FLAGS) != 0 or banned.has(i):
			continue
		var score := p.distance_squared_to(ideal)
		if score >= best_score or nav.is_node_occupied(i, actor):
			continue
		var crowded := false
		for raw in actors:
			var mate := raw as CSActor
			if is_instance_valid(mate) and mate != actor and mate.is_alive and mate.team == actor.team and mate.has_method("get_bomb_guard_position"):
				var occupied: Vector3 = mate.call("get_bomb_guard_position", nav)
				if occupied.distance_squared_to(p) < 6.25:
					crowded = true
					break
		if crowded or nav.plan_node_path(actor.global_position, i, actor.team, BotNavigator.PATH_SAFE, false, null, 0, banned).is_empty():
			continue
		best = i
		best_score = score
	return best

static func escort_slot(actor: CSActor, actors: Array) -> Dictionary:
	var carrier: CSActor = null
	for raw in actors:
		var mate := raw as CSActor
		if is_instance_valid(mate) and mate.is_alive and mate.team == "T" and String(mate.weapon_ctrl.slots.get(5, "")) == "c4":
			carrier = mate
			break
	if carrier == null or carrier == actor:
		return {}
	var rank := 0
	var distance := actor.global_position.distance_squared_to(carrier.global_position)
	for raw in actors:
		var mate := raw as CSActor
		if not is_instance_valid(mate) or mate == carrier or mate == actor or not mate.is_alive or mate.team != "T" or mate.is_human:
			continue
		var other := mate.global_position.distance_squared_to(carrier.global_position)
		if other < distance - 0.01 or (absf(other-distance) <= 0.01 and mate.get_instance_id() < actor.get_instance_id()):
			rank += 1
	return {"carrier": carrier, "slot": rank} if rank < 2 else {}
