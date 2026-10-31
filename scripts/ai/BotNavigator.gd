class_name BotNavigator
extends RefCounted
## Fast A* tactical pathfinder over the extracted BSP Hull-1 waypoint graph.

var waypoints: Array[Vector3] = []
var adj: Array = []
var _astar: AStar3D = AStar3D.new()


func setup_from_map(map_data: Dictionary) -> void:
	waypoints.clear()
	adj.clear()
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
		for nb in neighbors:
			var j := int(nb)
			if j >= 0 and j < raw_wp.size() and not _astar.are_points_connected(i, j):
				_astar.connect_points(i, j, true)


func find_path(from_pos: Vector3, to_pos: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if waypoints.is_empty():
		out.append(to_pos)
		return out
	var s_id := _astar.get_closest_point(from_pos)
	var e_id := _astar.get_closest_point(to_pos)
	if s_id < 0 or e_id < 0:
		out.append(to_pos)
		return out
	var packed := _astar.get_point_path(s_id, e_id)
	for v in packed:
		out.append(v)
	out.append(to_pos)
	return out


func get_random_waypoint() -> Vector3:
	if waypoints.is_empty():
		return Vector3.ZERO
	return waypoints[randi() % waypoints.size()]
