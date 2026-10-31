class_name BotNavigator
extends RefCounted
## Fast A* tactical pathfinder over the extracted Hull-1 connected waypoint graph,
## with physics line-of-sight waypoint selection and runtime blocked-edge pruning.

var waypoints: Array[Vector3] = []
var adj: Array = []
var _connected_ids: Array[int] = []
var _astar: AStar3D = AStar3D.new()


func setup_from_map(map_data: Dictionary) -> void:
	waypoints.clear()
	adj.clear()
	_connected_ids.clear()
	_astar.clear()

	var raw_wp: Array = map_data.get("waypoints", [])
	var raw_adj: Array = map_data.get("nav_adj", [])

	for i in range(raw_wp.size()):
		var p: Array = raw_wp[i]
		var v := Vector3(float(p[0]), float(p[1]), float(p[2]))
		waypoints.append(v)
		_astar.add_point(i, v)

	for i in range(mini(raw_wp.size(), raw_adj.size())):
		var neighbors: Array = raw_adj[i]
		adj.append(neighbors.duplicate())
		if not neighbors.is_empty():
			_connected_ids.append(i)
		for nb in neighbors:
			var j := int(nb)
			if j >= 0 and j < raw_wp.size() and not _astar.are_points_connected(i, j):
				_astar.connect_points(i, j, true)


func _find_best_waypoint(pos: Vector3, space: PhysicsDirectSpaceState3D) -> int:
	if waypoints.is_empty():
		return -1
	var best_id := -1
	var best_score := 1e9
	var cands: Array = []

	for idx in _connected_ids:
		var wp := waypoints[idx]
		var dy := absf(wp.y - pos.y)
		if dy > 4.5:
			continue
		var d_flat := Vector2(wp.x - pos.x, wp.z - pos.z).length()
		if d_flat > 22.0:
			continue
		var base_cost := d_flat + dy * 5.0
		cands.append([base_cost, idx])

	if cands.is_empty():
		return _astar.get_closest_point(pos)

	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var check_count := mini(cands.size(), 10)
	var from_eye := pos + Vector3(0.0, 0.92, 0.0)

	for k in range(check_count):
		var cost := float(cands[k][0])
		var wid := int(cands[k][1])
		if space != null:
			var to_eye := waypoints[wid] + Vector3(0.0, 0.72, 0.0)
			if _is_wall_blocking_ray(space, from_eye, to_eye):
				cost += 38.0
		if cost < best_score:
			best_score = cost
			best_id = wid
			if cost < 3.5:
				break

	return best_id if best_id >= 0 else _astar.get_closest_point(pos)


func _is_wall_blocking_ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var excl: Array[RID] = []
	for _step in range(3):
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.collision_mask = 1
		q.exclude = excl
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		var col = hit["collider"]
		if col is CollisionObject3D and ((col as Node).has_meta("door") or (col as Node).has_meta("breakable")):
			excl.append((col as CollisionObject3D).get_rid())
			continue
		return true
	return false


func find_path(from_pos: Vector3, to_pos: Vector3, space: PhysicsDirectSpaceState3D = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if waypoints.is_empty():
		out.append(to_pos)
		return out
	var s_id := _find_best_waypoint(from_pos, space)
	var e_id := _find_best_waypoint(to_pos, space)
	if s_id < 0 or e_id < 0:
		return out
	var packed := _astar.get_point_path(s_id, e_id)
	if packed.is_empty():
		if s_id < adj.size():
			var nbs: Array = adj[s_id]
			if not nbs.is_empty():
				var nb_id := int(nbs[randi() % nbs.size()])
				out.append(waypoints[nb_id])
		return out
	for v in packed:
		out.append(v)
	var last_wp := packed[packed.size() - 1]
	if last_wp.distance_to(to_pos) < 7.0 and absf(last_wp.y - to_pos.y) < 1.6:
		var clear_tail := true
		if space != null:
			clear_tail = not _is_wall_blocking_ray(
				space,
				last_wp + Vector3(0.0, 0.75, 0.0),
				to_pos + Vector3(0.0, 0.75, 0.0)
			)
		if clear_tail:
			out.append(to_pos)
	return out


func report_blocked_segment(from_pos: Vector3, blocked_wp: Vector3) -> void:
	if waypoints.is_empty():
		return
	var u := _astar.get_closest_point(from_pos)
	var v := _astar.get_closest_point(blocked_wp)
	if u < 0 or v < 0 or u == v:
		return
	if _astar.are_points_connected(u, v):
		var u_conns := _astar.get_point_connections(u)
		var v_conns := _astar.get_point_connections(v)
		if u_conns.size() > 1 and v_conns.size() > 1:
			_astar.disconnect_points(u, v, true)
			if u < adj.size():
				(adj[u] as Array).erase(v)
			if v < adj.size():
				(adj[v] as Array).erase(u)


func get_random_waypoint(near_pos: Vector3 = Vector3.INF) -> Vector3:
	if not _connected_ids.is_empty():
		if near_pos.is_finite():
			for _attempt in range(8):
				var cid := _connected_ids[randi() % _connected_ids.size()]
				var wp := waypoints[cid]
				if wp.distance_to(near_pos) > 8.0:
					return wp
		var idx := _connected_ids[randi() % _connected_ids.size()]
		return waypoints[idx]
	if waypoints.is_empty():
		return Vector3.ZERO
	return waypoints[randi() % waypoints.size()]
