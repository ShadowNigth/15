class_name BotNavigator
extends RefCounted
## Authentic YaPB-powered directed tactical graph & A* planner:
##   - Loads official human-curated YaPB (.graph) nodes, directed links, jump velocities,
##     corridor radii, node flags (Crouch, Ladder, Camp, Sniper, Goal, Rescue, NoHostage, Narrow),
##     and human-authored camp/sniper sightline sweep vectors!
##   - Supports YaPB FindPathType modes: Fast, Optimal, Safe (danger-avoiding), and Diversity (squad split)
##   - Tracks per-team Practice/Danger heatmaps across rounds + Camp/Sniper spot reservations.

# YaPB NodeFlag bitmasks (yapb/inc/graph.h)
const FLAG_BUTTON: int = 1 << 0
const FLAG_LIFT: int = 1 << 1
const FLAG_CROUCH: int = 1 << 2
const FLAG_CROSSING: int = 1 << 3
const FLAG_GOAL: int = 1 << 4
const FLAG_LADDER: int = 1 << 5
const FLAG_RESCUE: int = 1 << 6
const FLAG_CAMP: int = 1 << 7
const FLAG_NO_HOSTAGE: int = 1 << 8
const FLAG_DOUBLE_JUMP: int = 1 << 9
const FLAG_NARROW: int = 1 << 10
const FLAG_SNIPER: int = 1 << 28
const FLAG_T_ONLY: int = 1 << 29
const FLAG_CT_ONLY: int = 1 << 30

# Action flags that must NEVER be skipped by path string-pulling (yapb/src/navigate.cpp:2846)
const ACTION_FLAGS: int = FLAG_BUTTON | FLAG_LIFT | FLAG_CROUCH | FLAG_LADDER | FLAG_DOUBLE_JUMP | FLAG_NARROW

# YaPB PathFlag bitmasks
const LINK_JUMP: int = 1

# YaPB FindPathType modes
const PATH_FAST: int = 0
const PATH_OPTIMAL: int = 1
const PATH_SAFE: int = 2
const PATH_DIVERSITY: int = 3

var waypoints: Array[Vector3] = []
var wp_flags: PackedInt32Array = PackedInt32Array()
var wp_radius: PackedFloat32Array = PackedFloat32Array()
var nav_links: Array = []  # per-node Array of [dst_idx] or [dst_idx, link_flags, vx, vy, vz]
var wp_camp: Dictionary = {}  # int node_idx -> [Vector3 start_dir, Vector3 end_dir]

# Pre-indexed tactical point pools (yapb PointType)
var goal_nodes: PackedInt32Array = PackedInt32Array()
var camp_nodes: PackedInt32Array = PackedInt32Array()
var sniper_nodes: PackedInt32Array = PackedInt32Array()
var rescue_nodes: PackedInt32Array = PackedInt32Array()
var crossing_nodes: PackedInt32Array = PackedInt32Array()

# Per-team tactical danger / practice experience & congestion
var _danger_t: PackedFloat32Array = PackedFloat32Array()
var _danger_ct: PackedFloat32Array = PackedFloat32Array()
var _congestion: PackedFloat32Array = PackedFloat32Array()
var _occupied_by: Dictionary = {}  # node_idx -> actor instance_id


func setup_from_map(map_data: Dictionary) -> void:
	waypoints.clear()
	nav_links.clear()
	wp_camp.clear()
	_occupied_by.clear()

	var raw_wp: Array = map_data.get("waypoints", [])
	var n: int = raw_wp.size()
	wp_flags.resize(n)
	wp_flags.fill(0)
	wp_radius.resize(n)
	wp_radius.fill(0.0)
	_danger_t.resize(n)
	_danger_t.fill(0.0)
	_danger_ct.resize(n)
	_danger_ct.fill(0.0)
	_congestion.resize(n)
	_congestion.fill(0.0)

	var raw_flags: Array = map_data.get("wp_flags", [])
	var raw_rad: Array = map_data.get("wp_radius", [])
	var raw_links: Array = map_data.get("nav_links", [])
	var raw_adj: Array = map_data.get("nav_adj", [])
	var raw_camp: Dictionary = map_data.get("wp_camp", {})

	var goals_tmp: Array[int] = []
	var camps_tmp: Array[int] = []
	var snipers_tmp: Array[int] = []
	var rescues_tmp: Array[int] = []
	var cross_tmp: Array[int] = []

	for i in range(n):
		var p: Array = raw_wp[i]
		waypoints.append(Vector3(float(p[0]), float(p[1]), float(p[2])))
		var fl: int = int(raw_flags[i]) if i < raw_flags.size() else 0
		wp_flags[i] = fl
		wp_radius[i] = float(raw_rad[i]) if i < raw_rad.size() else 0.35

		if (fl & FLAG_GOAL) != 0:
			goals_tmp.append(i)
		if (fl & FLAG_CAMP) != 0:
			camps_tmp.append(i)
		if (fl & FLAG_SNIPER) != 0:
			snipers_tmp.append(i)
		if (fl & FLAG_RESCUE) != 0:
			rescues_tmp.append(i)
		if (fl & FLAG_CROSSING) != 0:
			cross_tmp.append(i)

		if i < raw_links.size():
			nav_links.append(raw_links[i])
		elif i < raw_adj.size():
			var fallback_links: Array = []
			for nb in raw_adj[i]:
				fallback_links.append([int(nb)])
			nav_links.append(fallback_links)
		else:
			nav_links.append([])

	for k in raw_camp.keys():
		var idx_c: int = int(k)
		var arr_c: Array = raw_camp[k]
		if arr_c.size() >= 6:
			var d_s := Vector3(float(arr_c[0]), float(arr_c[1]), float(arr_c[2])).normalized()
			var d_e := Vector3(float(arr_c[3]), float(arr_c[4]), float(arr_c[5])).normalized()
			wp_camp[idx_c] = [d_s, d_e]

	goal_nodes = PackedInt32Array(goals_tmp)
	camp_nodes = PackedInt32Array(camps_tmp)
	sniper_nodes = PackedInt32Array(snipers_tmp)
	rescue_nodes = PackedInt32Array(rescues_tmp)
	crossing_nodes = PackedInt32Array(cross_tmp)


func reset_round_weights() -> void:
	_occupied_by.clear()
	for i in range(_congestion.size()):
		_congestion[i] = 0.0
		# Preserve 70% of learned team combat danger across rounds (YaPB practice memory!)
		_danger_t[i] *= 0.70
		_danger_ct[i] *= 0.70


func report_team_damage(victim_team: String, victim_pos: Vector3, amount: float) -> void:
	var idx := get_nearest_node(victim_pos)
	if idx < 0:
		return
	var boost: float = clampf(amount * 1.4, 10.0, 180.0)
	if victim_team == "T":
		_danger_t[idx] = minf(450.0, _danger_t[idx] + boost)
		for lnk in nav_links[idx]:
			var nb: int = int((lnk as Array)[0])
			if nb >= 0 and nb < _danger_t.size():
				_danger_t[nb] = minf(450.0, _danger_t[nb] + boost * 0.45)
	else:
		_danger_ct[idx] = minf(450.0, _danger_ct[idx] + boost)
		for lnk in nav_links[idx]:
			var nb2: int = int((lnk as Array)[0])
			if nb2 >= 0 and nb2 < _danger_ct.size():
				_danger_ct[nb2] = minf(450.0, _danger_ct[nb2] + boost * 0.45)


func report_blocked_segment(_from_pos: Vector3, blocked_wp: Vector3) -> void:
	var idx := get_nearest_node(blocked_wp)
	if idx >= 0 and idx < _congestion.size():
		_congestion[idx] = minf(60.0, _congestion[idx] + 12.0)


func claim_node(node_idx: int, actor: Object) -> void:
	if node_idx >= 0 and actor != null:
		_occupied_by[node_idx] = actor.get_instance_id()


func release_actor_claims(actor: Object) -> void:
	if actor == null:
		return
	var aid: int = actor.get_instance_id()
	var to_erase: Array[int] = []
	for k in _occupied_by.keys():
		if int(_occupied_by[k]) == aid:
			to_erase.append(int(k))
	for k2 in to_erase:
		_occupied_by.erase(k2)


func is_node_occupied(node_idx: int, ignore_actor: Object = null) -> bool:
	if not _occupied_by.has(node_idx):
		return false
	if ignore_actor != null and int(_occupied_by[node_idx]) == ignore_actor.get_instance_id():
		return false
	return true


func get_node_pos(idx: int) -> Vector3:
	if idx >= 0 and idx < waypoints.size():
		return waypoints[idx]
	return Vector3.ZERO


func get_node_flags(idx: int) -> int:
	if idx >= 0 and idx < wp_flags.size():
		return wp_flags[idx]
	return 0


func get_node_radius(idx: int) -> float:
	if idx >= 0 and idx < wp_radius.size():
		return wp_radius[idx]
	return 0.0


func get_camp_dirs(idx: int) -> Array:
	return wp_camp.get(idx, [])


func get_link_info(from_idx: int, to_idx: int) -> Array:
	if from_idx < 0 or from_idx >= nav_links.size():
		return []
	var links_arr: Array = nav_links[from_idx]
	for entry in links_arr:
		var e := entry as Array
		if int(e[0]) == to_idx:
			return e
	return []


func are_directly_linked(from_idx: int, to_idx: int) -> bool:
	var info := get_link_info(from_idx, to_idx)
	if info.is_empty():
		return false
	if info.size() >= 2 and (int(info[1]) & LINK_JUMP) != 0:
		return false
	return true


func get_nearest_node(
	pos: Vector3,
	space: PhysicsDirectSpaceState3D = null,
	max_dy: float = 3.6,
	for_walk_start: bool = false
) -> int:
	var n: int = waypoints.size()
	if n == 0:
		return -1
	var best_id: int = -1
	var best_cost: float = 1e9
	var cands: Array = []

	for i in range(n):
		var wp: Vector3 = waypoints[i]
		var signed_dy: float = wp.y - pos.y
		var dy: float = absf(signed_dy)
		# Never snap an actor's walk-start onto a ledge/ramp-top above GoldSrc step height!
		if for_walk_start:
			if (wp_flags[i] & FLAG_LADDER) == 0 and signed_dy > 0.56:
				continue
			if signed_dy < -2.4:
				continue
		elif dy > max_dy:
			continue
		var d_xz: float = Vector2(wp.x - pos.x, wp.z - pos.z).length()
		if d_xz > 18.0:
			continue
		var score: float = d_xz + dy * 3.5 + (maxf(0.0, signed_dy) * 8.0 if for_walk_start else 0.0)
		cands.append([score, i])

	if cands.is_empty():
		for i in range(n):
			var wp2: Vector3 = waypoints[i]
			var s_dy2: float = wp2.y - pos.y
			var climb_pen: float = 35.0 if (for_walk_start and s_dy2 > 0.60 and (wp_flags[i] & FLAG_LADDER) == 0) else 0.0
			var d2: float = Vector2(wp2.x - pos.x, wp2.z - pos.z).length() + absf(s_dy2) * 2.8 + climb_pen
			if d2 < best_cost:
				best_cost = d2
				best_id = i
		return best_id

	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var check_n: int = mini(cands.size(), 10)
	var shin_from: Vector3 = pos + Vector3(0.0, 0.42, 0.0)
	var chest_from: Vector3 = pos + Vector3(0.0, 1.05, 0.0)
	for k in range(check_n):
		var sc: float = float(cands[k][0])
		var idx: int = int(cands[k][1])
		if space != null and sc < 18.0:
			var wp_k: Vector3 = waypoints[idx]
			# Both shin (+0.42m, catches retaining walls/parapets!) and chest (+1.05m) must be clear!
			if _is_solid_wall_between(space, chest_from, wp_k + Vector3(0.0, 1.00, 0.0)) or (
				for_walk_start and _is_solid_wall_between(space, shin_from, wp_k + Vector3(0.0, 0.42, 0.0))
			):
				sc += 48.0
		if sc < best_cost:
			best_cost = sc
			best_id = idx
			if sc < 1.8:
				break

	return best_id if best_id >= 0 else int(cands[0][1])


func _is_solid_wall_between(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var excl: Array[RID] = []
	for _s in range(3):
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


## Directed A* planner matching YaPB's PlannerHeuristic (Fast / Optimal / Safe / Diversity + Hostage).
func plan_node_path(
	from_pos: Vector3,
	goal_idx: int,
	team: String = "T",
	path_mode: int = PATH_OPTIMAL,
	leading_hostage: bool = false,
	space: PhysicsDirectSpaceState3D = null,
	diversity_seed: int = 0,
	banned_nodes: Dictionary = {}
) -> PackedInt32Array:
	var n: int = waypoints.size()
	if n == 0 or goal_idx < 0 or goal_idx >= n:
		return PackedInt32Array()

	var start_idx: int = get_nearest_node(from_pos, space, 3.6, true)
	if start_idx < 0:
		return PackedInt32Array()
	if start_idx == goal_idx:
		return PackedInt32Array([goal_idx])

	var g_score := PackedFloat32Array()
	g_score.resize(n)
	g_score.fill(1e12)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var closed := PackedByteArray()
	closed.resize(n)
	closed.fill(0)

	# Binary min-heap over (f_score, node_idx)
	var heap_f: Array[float] = [0.0]
	var heap_n: Array[int] = [start_idx]
	g_score[start_idx] = 0.0
	var goal_pos: Vector3 = waypoints[goal_idx]
	var use_t_danger: bool = (team == "T")

	while not heap_n.is_empty():
		var u: int = heap_n[0]
		var last_i: int = heap_n.size() - 1
		if last_i == 0:
			heap_n.pop_back()
			heap_f.pop_back()
		else:
			heap_n[0] = heap_n[last_i]
			heap_f[0] = heap_f[last_i]
			heap_n.pop_back()
			heap_f.pop_back()
			# Sift down
			var pi: int = 0
			var hsz: int = heap_n.size()
			while true:
				var l: int = pi * 2 + 1
				var r: int = l + 1
				var sm: int = pi
				if l < hsz and heap_f[l] < heap_f[sm]:
					sm = l
				if r < hsz and heap_f[r] < heap_f[sm]:
					sm = r
				if sm == pi:
					break
				var tf: float = heap_f[pi]
				heap_f[pi] = heap_f[sm]
				heap_f[sm] = tf
				var tn: int = heap_n[pi]
				heap_n[pi] = heap_n[sm]
				heap_n[sm] = tn
				pi = sm

		if u == goal_idx:
			break
		if closed[u] != 0:
			continue
		closed[u] = 1

		var u_pos: Vector3 = waypoints[u]
		var u_g: float = g_score[u]
		var links_u: Array = nav_links[u]

		for entry in links_u:
			var e := entry as Array
			var v: int = int(e[0])
			if v < 0 or v >= n or closed[v] != 0:
				continue
			var lflags: int = int(e[1]) if e.size() >= 2 else 0
			var v_flags: int = wp_flags[v]

			# YaPB Hostage constraint: never route hostages over Jump links, Ladders, or NoHostage nodes!
			if leading_hostage:
				if (v_flags & (FLAG_NO_HOSTAGE | FLAG_LADDER)) != 0 or (lflags & LINK_JUMP) != 0:
					continue

			var step_d: float = u_pos.distance_to(waypoints[v])
			if (v_flags & FLAG_CROUCH) != 0:
				step_d *= 1.45
			if (v_flags & FLAG_LADDER) != 0:
				step_d *= 1.65
			if (lflags & LINK_JUMP) != 0:
				step_d += 2.8

			var danger_val: float = _danger_t[v] if use_t_danger else _danger_ct[v]
			var extra_cost: float = _congestion[v]
			if banned_nodes.has(v):
				extra_cost += 180.0
			if path_mode == PATH_OPTIMAL:
				extra_cost += danger_val * 0.22
			elif path_mode == PATH_SAFE:
				extra_cost += danger_val * 1.15
			elif path_mode == PATH_DIVERSITY:
				extra_cost += danger_val * 0.20
				if (v_flags & FLAG_CROSSING) != 0 or links_u.size() >= 3:
					var h_noise: int = ((v * 73856093) ^ (diversity_seed * 19349663)) & 1023
					extra_cost += (float(h_noise) / 1023.0) * 14.5

			var cand_g: float = u_g + step_d + extra_cost
			if cand_g < g_score[v]:
				g_score[v] = cand_g
				parent[v] = u
				var h_est: float = waypoints[v].distance_to(goal_pos)
				var f_val: float = cand_g + h_est
				# Sift up into min-heap
				var ci: int = heap_n.size()
				heap_n.append(v)
				heap_f.append(f_val)
				while ci > 0:
					var par_i: int = (ci - 1) >> 1
					if heap_f[ci] < heap_f[par_i]:
						var tf2: float = heap_f[ci]
						heap_f[ci] = heap_f[par_i]
						heap_f[par_i] = tf2
						var tn2: int = heap_n[ci]
						heap_n[ci] = heap_n[par_i]
						heap_n[par_i] = tn2
						ci = par_i
					else:
						break

	# If hostage-safe search couldn't reach, fall back to normal directed search
	if parent[goal_idx] == -1 and leading_hostage:
		return plan_node_path(from_pos, goal_idx, team, path_mode, false, space, diversity_seed, banned_nodes)
	if parent[goal_idx] == -1:
		return PackedInt32Array([start_idx])

	var rev: Array[int] = []
	var cur: int = goal_idx
	var guard: int = 0
	while cur != -1 and guard <= n:
		rev.append(cur)
		cur = parent[cur]
		guard += 1
	rev.reverse()

	# Drop start node if we already walked past it along the directed edge rev[0] -> rev[1]
	# UNLESS rev[0] or rev[1] has an action/jump flag!
	if rev.size() >= 2:
		var n0: int = rev[0]
		var n1: int = rev[1]
		var lnk01 := get_link_info(n0, n1)
		var is_jmp: bool = lnk01.size() >= 2 and (int(lnk01[1]) & LINK_JUMP) != 0
		if not is_jmp and ((wp_flags[n0] | wp_flags[n1]) & ACTION_FLAGS) == 0:
			var to_first := waypoints[n0] - from_pos
			var seg := waypoints[n1] - waypoints[n0]
			to_first.y = 0.0
			seg.y = 0.0
			if to_first.length() < 1.9 and to_first.dot(seg) < 0.0:
				rev.remove_at(0)

	return PackedInt32Array(rev)


## World-position convenience wrapper (used by HostageNPC and fallback callers).
func find_path(from_pos: Vector3, to_pos: Vector3, space: PhysicsDirectSpaceState3D = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if waypoints.is_empty():
		out.append(to_pos)
		return out
	var g_idx := get_nearest_node(to_pos, null, 6.0)
	if g_idx < 0:
		out.append(to_pos)
		return out
	var node_ids := plan_node_path(from_pos, g_idx, "CT", PATH_FAST, true, space, 0)
	for nid in node_ids:
		out.append(waypoints[nid])
	return out


func pick_camp_or_sniper_node(
	near_pos: Vector3,
	team: String,
	wants_sniper: bool,
	max_dist: float = 28.0,
	requester: Object = null
) -> int:
	var pool: PackedInt32Array = sniper_nodes if (wants_sniper and not sniper_nodes.is_empty()) else camp_nodes
	if pool.is_empty():
		return -1
	var cands: Array[int] = []
	for idx in pool:
		var fl: int = wp_flags[idx]
		if team == "T" and (fl & FLAG_CT_ONLY) != 0:
			continue
		if team == "CT" and (fl & FLAG_T_ONLY) != 0:
			continue
		if is_node_occupied(idx, requester):
			continue
		if waypoints[idx].distance_to(near_pos) <= max_dist:
			cands.append(idx)
	if cands.is_empty():
		return -1
	return cands[randi() % cands.size()]


func pick_goal_node_near(target_pos: Vector3, max_dist: float = 18.0) -> int:
	var cands: Array[int] = []
	for idx in goal_nodes:
		if waypoints[idx].distance_to(target_pos) <= max_dist:
			cands.append(idx)
	if not cands.is_empty():
		return cands[randi() % cands.size()]
	return get_nearest_node(target_pos, null, 8.0)


func pick_roam_node(from_pos: Vector3, team: String) -> int:
	var n: int = waypoints.size()
	if n == 0:
		return -1
	for _attempt in range(20):
		var idx: int = randi() % n
		var fl: int = wp_flags[idx]
		if (fl & FLAG_LADDER) != 0:
			continue
		if team == "T" and (fl & FLAG_CT_ONLY) != 0:
			continue
		if team == "CT" and (fl & FLAG_T_ONLY) != 0:
			continue
		if waypoints[idx].distance_to(from_pos) > 16.0:
			return idx
	return randi() % n
