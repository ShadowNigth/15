class_name BotNavigator
extends RefCounted
## Fast A* tactical pathfinder over the extracted Hull-1 connected waypoint graph,
## with connected-component reachability guarantees, doorway-aware LOS selection,
## and non-destructive dynamic congestion weighting (never severing spawn/corridor bridges!).

var waypoints: Array[Vector3] = []
var adj: Array = []
var _connected_ids: Array[int] = []
var _comp_id: PackedInt32Array = PackedInt32Array()
var _comp_size: PackedInt32Array = PackedInt32Array()
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
		_astar.add_point(i, v, 1.0)

	for i in range(mini(raw_wp.size(), raw_adj.size())):
		var neighbors: Array = raw_adj[i]
		adj.append(neighbors.duplicate())
		if not neighbors.is_empty():
			_connected_ids.append(i)
		for nb in neighbors:
			var j := int(nb)
			if j >= 0 and j < raw_wp.size() and not _astar.are_points_connected(i, j):
				_astar.connect_points(i, j, true)

	_rebuild_components()


func _rebuild_components() -> void:
	var n: int = waypoints.size()
	_comp_id.resize(n)
	_comp_id.fill(-1)
	_comp_size.resize(n)
	_comp_size.fill(0)
	var cid: int = 0
	for i in range(n):
		if _comp_id[i] != -1:
			continue
		var stack: Array[int] = [i]
		var members: Array[int] = []
		_comp_id[i] = cid
		while not stack.is_empty():
			var u: int = stack.pop_back()
			members.append(u)
			if u < adj.size():
				var nbs: Array = adj[u]
				for nb in nbs:
					var v: int = int(nb)
					if v >= 0 and v < n and _comp_id[v] == -1:
						_comp_id[v] = cid
						stack.append(v)
		var m_cnt: int = members.size()
		for m_idx in members:
			_comp_size[m_idx] = m_cnt
		cid += 1


func reset_round_weights() -> void:
	for i in range(waypoints.size()):
		_astar.set_point_weight_scale(i, 1.0)


func _find_best_waypoint(pos: Vector3, space: PhysicsDirectSpaceState3D, req_comp: int = -1) -> int:
	if waypoints.is_empty():
		return -1
	var best_id := -1
	var best_score := 1e9
	var cands: Array = []

	for idx in _connected_ids:
		if req_comp >= 0 and idx < _comp_id.size() and _comp_id[idx] != req_comp:
			continue
		var c_sz: int = _comp_size[idx] if idx < _comp_size.size() else 999
		if req_comp < 0 and c_sz < 24:
			continue
		var wp := waypoints[idx]
		var dy := absf(wp.y - pos.y)
		if req_comp < 0 and dy > 5.2:
			continue
		var d_flat := Vector2(wp.x - pos.x, wp.z - pos.z).length()
		if req_comp < 0 and d_flat > 24.0:
			continue
		var base_cost := d_flat + dy * (5.0 if req_comp < 0 else 2.2)
		cands.append([base_cost, idx])

	# Fallback if destination is far or actor spawned on an elevated drop-down helipad (e.g. as_oilrig)
	if cands.is_empty():
		for idx in _connected_ids:
			if req_comp >= 0 and idx < _comp_id.size() and _comp_id[idx] != req_comp:
				continue
			var c_sz2: int = _comp_size[idx] if idx < _comp_size.size() else 999
			var wp2 := waypoints[idx]
			var d2 := wp2.distance_to(pos) + (60.0 if (req_comp < 0 and c_sz2 < 24) else 0.0)
			if d2 < best_score:
				best_score = d2
				best_id = idx
		return best_id if best_id >= 0 else _astar.get_closest_point(pos)

	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var check_count := mini(cands.size(), 10)
	var from_eye := pos + Vector3(0.0, 0.92, 0.0)

	for k in range(check_count):
		var cost := float(cands[k][0])
		var wid := int(cands[k][1])
		if space != null and cost < 22.0:
			var to_eye := waypoints[wid] + Vector3(0.0, 0.72, 0.0)
			if _is_wall_blocking_ray(space, from_eye, to_eye):
				cost += 38.0
		if cost < best_score:
			best_score = cost
			best_id = wid
			if cost < 3.5:
				break

	return best_id if best_id >= 0 else int(cands[0][1])


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
	var s_id := _find_best_waypoint(from_pos, space, -1)
	if s_id < 0:
		return out
	var req_c: int = _comp_id[s_id] if s_id < _comp_id.size() else -1
	var e_id := _find_best_waypoint(to_pos, space, req_c)
	if e_id < 0:
		return out

	var packed := _astar.get_point_path(s_id, e_id)
	for v in packed:
		out.append(v)

	# Drop starting waypoint if we have already passed it on the way to packed[1]
	if out.size() >= 2:
		var to_first := out[0] - from_pos
		var seg := out[1] - out[0]
		to_first.y = 0.0
		seg.y = 0.0
		if to_first.length() < 2.2 and to_first.dot(seg) < 0.0:
			out.remove_at(0)

	if not out.is_empty():
		var last_wp := out[out.size() - 1]
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


func report_blocked_segment(_from_pos: Vector3, blocked_wp: Vector3) -> void:
	# Raise A* congestion cost on the congested node instead of severing choke-point edges!
	if waypoints.is_empty():
		return
	var v := _astar.get_closest_point(blocked_wp)
	if v >= 0:
		var cur_w := _astar.get_point_weight_scale(v)
		_astar.set_point_weight_scale(v, minf(9.0, cur_w + 1.75))


func get_random_waypoint(near_pos: Vector3 = Vector3.INF) -> Vector3:
	if not _connected_ids.is_empty():
		var req_c: int = -1
		if near_pos.is_finite():
			var s_id := _astar.get_closest_point(near_pos)
			if s_id >= 0 and s_id < _comp_id.size():
				req_c = _comp_id[s_id]
			for _attempt in range(18):
				var cid := _connected_ids[randi() % _connected_ids.size()]
				if req_c >= 0 and cid < _comp_id.size() and _comp_id[cid] != req_c:
					continue
				var wp := waypoints[cid]
				if wp.distance_to(near_pos) > 15.0:
					return wp
		var idx := _connected_ids[randi() % _connected_ids.size()]
		return waypoints[idx]
	if waypoints.is_empty():
		return Vector3.ZERO
	return waypoints[randi() % waypoints.size()]
