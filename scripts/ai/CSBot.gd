class_name CSBot
extends CSActor
## Tactical Counter-Strike 1.5 Bot AI (PodBot / CSBot inspired):
##   - Economy buy logic during freeze time (rifles, SMGs, Kevlar+Helmet, Defuser, HE)
##   - A* navigation across all 26 BSP maps with stuck-jump/crouch recovery
##   - Full DE (plant/guard/defuse C4), CS (lead/defend hostages), and AS (escort/hunt VIP) tactics
##   - Realistic reaction times, burst shooting, strafing, flashbang blindness, smoke occlusion, radio orders

const BOT_NAMES: Array[String] = [
	"[POD]Gooseman", "[POD]Cliffe", "HeatoN", "Potti", "SpawN", "elemeNt",
	"Ksharp", "Johnny_R", "shaGuar", "moto", "fisker", "ahl",
	"vesslan", "Bullseye", "rambo", "Method", "XeqtR", "bds",
]

var skill_level: int = 1  # 0=Easy, 1=Normal, 2=Hard, 3=Expert
var target_enemy: CSActor = null
var _reaction_timer: float = 0.0
var _think_timer: float = 0.0
var _nav_path: Array[Vector3] = []
var _goal_pos: Vector3 = Vector3.ZERO
var _has_goal: bool = false
var _stuck_timer: float = 0.0
var _jump_cooldown: float = 0.0
var _crouch_burst_timer: float = 0.0
var _escape_timer: float = 0.0
var _escape_dir: Vector3 = Vector3.ZERO
var _grenade_cooldown: float = 0.0
var _avoid_side: float = 1.0
var _last_pos: Vector3 = Vector3.ZERO
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
var _burst_stop_timer: float = 0.0
var _burst_pause_timer: float = 0.0
var _knife_rush_timer: float = 0.0
var _stealth_walk_timer: float = 0.0
var _corner_check_timer: float = 0.0
var _corner_yaw_offset: float = 0.0
var _sound_investigate_pos: Vector3 = Vector3.ZERO
var _sound_investigate_timer: float = 0.0
var _last_enemy_pos: Vector3 = Vector3.ZERO
var _last_enemy_seen_age: float = 99.0
var _follow_target: Node3D = null
var _hold_pos_timer: float = 0.0
var _defusing_ref: PlantedC4 = null
var _bought_this_round: bool = false


func _ready() -> void:
	is_human = false
	super._ready()
	_avoid_side = 1.0 if randf() < 0.5 else -1.0
	AudioManager.world_sound_emitted.connect(_on_world_sound)
	RoundManager.radio_order_issued.connect(_on_radio_order)
	RoundManager.freeze_ended.connect(_on_bot_freeze_ended)


func _on_bot_freeze_ended() -> void:
	if not is_alive or is_vip:
		return
	# Classic CS 1.5 / PodBot opening rush: pull out Knife (250 u/s) for first 3-5 seconds out of spawn!
	if randf() < 0.78:
		_knife_rush_timer = randf_range(2.6, 4.6)


func spawn_for_round(pos: Vector3, yaw_rad: float, reset_weapons: bool) -> void:
	super.spawn_for_round(pos, yaw_rad, reset_weapons)
	target_enemy = null
	_nav_path.clear()
	_has_goal = false
	_follow_target = null
	_hold_pos_timer = 0.0
	_defusing_ref = null
	_bought_this_round = false
	_stuck_timer = 0.0
	_jump_cooldown = 0.0
	_crouch_burst_timer = 0.0
	_burst_stop_timer = 0.0
	_burst_pause_timer = 0.0
	_knife_rush_timer = 0.0
	_stealth_walk_timer = 0.0
	_corner_check_timer = randf_range(0.8, 2.2)
	_corner_yaw_offset = 0.0
	_sound_investigate_timer = 0.0
	_last_enemy_seen_age = 99.0
	_escape_timer = 0.0
	_escape_dir = Vector3.ZERO
	_grenade_cooldown = randf_range(3.0, 9.0)
	_last_pos = global_position
	_think_timer = randf_range(0.1, 0.45)


func _perform_bot_buy() -> void:
	_bought_this_round = true
	if is_vip or not can_use_buy_menu():
		return

	# CT buys defusal kit on DE maps when affordable
	if team == "CT" and RoundManager.map_mode == "de" and money >= 1200 and randf() < 0.75:
		buy_equipment("defuser")

	# Armor priority
	if money >= 3800:
		buy_equipment("kevlar_helmet")
	elif money >= 1900:
		buy_equipment("kevlar")

	# Primary weapon purchase if slot 1 empty
	if String(weapon_ctrl.slots.get(1, "")).is_empty():
		var choices: Array[String] = []
		if team == "T":
			if money >= 4750 and randf() < 0.22:
				choices = ["awp"]
			elif money >= 2600:
				choices = ["ak47", "sg552"]
			elif money >= 1500:
				choices = ["mp5navy", "mac10", "ump45", "m3"]
		else:
			if money >= 4750 and randf() < 0.22:
				choices = ["awp"]
			elif money >= 3150:
				choices = ["m4a1", "aug"]
			elif money >= 1500:
				choices = ["mp5navy", "tmp", "ump45", "m3"]

		for wid in choices:
			if buy_weapon(wid):
				break

		# Attach silencer on M4A1/USP half the time for authentic CS 1.5 feel!
		var cur_p := String(weapon_ctrl.slots.get(1, ""))
		if cur_p == "m4a1" and randf() < 0.55:
			weapon_ctrl.silenced_state["m4a1"] = true

	# Refill ammo!
	buy_ammo_for_slot(1, true)
	buy_ammo_for_slot(2, true)

	# Buy HE / Smoke grenade if spare cash
	if money >= 600 and randf() < 0.48:
		buy_weapon("hegrenade")
	if money >= 500 and randf() < 0.25:
		buy_weapon("smokegrenade")


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if not _bought_this_round and RoundManager.can_buy_now():
		_perform_bot_buy()

	# Blinded by Flashbang!
	if flash_alpha > 0.65:
		var blind_move := Basis(Vector3.UP, look_yaw) * Vector3(_strafe_dir * 0.5, 0.0, 0.3)
		apply_goldsrc_movement(blind_move.normalized(), false, false, false, delta)
		return

	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = randf_range(0.14, 0.26)
		_scan_for_enemies()
		_update_tactical_objective()

	if _hold_pos_timer > 0.0:
		_hold_pos_timer -= delta
	if _knife_rush_timer > 0.0:
		_knife_rush_timer = maxf(0.0, _knife_rush_timer - delta)
	if _stealth_walk_timer > 0.0:
		_stealth_walk_timer = maxf(0.0, _stealth_walk_timer - delta)
	if _sound_investigate_timer > 0.0:
		_sound_investigate_timer = maxf(0.0, _sound_investigate_timer - delta)
	if _grenade_cooldown > 0.0:
		_grenade_cooldown = maxf(0.0, _grenade_cooldown - delta)
	_last_enemy_seen_age += delta

	# Reload safely when out of combat
	var cr := weapon_ctrl.get_clip_and_reserve()
	if target_enemy == null:
		if cr.x == 0 and cr.y > 0 and not weapon_ctrl.is_reloading:
			weapon_ctrl.start_reload()
		elif cr.x > 0 and cr.y > 0:
			var csize := int(weapon_ctrl.get_current_spec().get("clip_size", 30))
			if cr.x < int(float(csize) * 0.34) and not weapon_ctrl.is_reloading:
				weapon_ctrl.start_reload()
		# Clear sniper scope when navigating out of combat
		if weapon_ctrl.zoom_stage > 0:
			weapon_ctrl._clear_zoom()

	# Priority 1: CT Defusing Planted C4 when clear!
	if team == "CT" and target_enemy == null and is_instance_valid(RoundManager.planted_c4):
		var c4 := RoundManager.planted_c4 as PlantedC4
		if c4 and global_position.distance_to(c4.global_position) <= 2.3:
			if c4.defuser_actor == null or c4.defuser_actor == self:
				_defusing_ref = c4
				_look_smoothly_toward(c4.global_position + Vector3(0, 0.1, 0), delta * 8.0)
				c4.begin_or_continue_defuse(self, delta)
				apply_goldsrc_movement(Vector3.ZERO, false, true, false, delta)
				return

	if _defusing_ref != null:
		if is_instance_valid(_defusing_ref):
			_defusing_ref.cancel_defuse(self)
		_defusing_ref = null

	# Priority 2: T Planting C4 when inside Bombsite!
	if team == "T" and target_enemy == null and String(weapon_ctrl.slots.get(5, "")) == "c4":
		if RoundManager.state == RoundManager.State.LIVE and is_instance_valid(RoundManager.game_world):
			if bool(RoundManager.game_world.call("is_in_bombsite", global_position)):
				if weapon_ctrl.current_weapon_id != "c4":
					weapon_ctrl.equip_slot(5)
				apply_goldsrc_movement(Vector3.ZERO, false, true, false, delta)
				weapon_ctrl.trigger_primary(true, delta)
				return

	# Priority 3: Engage Visible Enemy!
	if is_instance_valid(target_enemy) and target_enemy.is_alive:
		_knife_rush_timer = 0.0
		_stealth_walk_timer = 0.0
		_last_enemy_pos = target_enemy.global_position
		_last_enemy_seen_age = 0.0
		_engage_enemy(delta)
		return

	# Priority 3.5: Flush out an enemy that just ducked behind cover with an HE grenade!
	if _last_enemy_seen_age > 0.25 and _last_enemy_seen_age < 1.85 and _grenade_cooldown <= 0.0 and health > 40:
		var d_last := global_position.distance_to(_last_enemy_pos)
		if d_last > 8.5 and d_last < 23.0 and int(weapon_ctrl.grenades.get("hegrenade", 0)) > 0 and randf() < 0.08:
			_grenade_cooldown = 14.0
			if weapon_ctrl.equip_weapon_by_id("hegrenade"):
				weapon_ctrl.fire_cooldown = 0.0
				_look_smoothly_toward(_last_enemy_pos + Vector3(0.0, 2.1, 0.0), 1.0)
				weapon_ctrl.trigger_primary(false, delta)
				return

	# Weapon discipline during navigation: Knife rush out of spawn, then draw Primary Rifle before contact!
	if not weapon_ctrl.is_reloading:
		if _knife_rush_timer > 0.0 and _sound_investigate_timer <= 0.0 and not is_vip:
			if weapon_ctrl.current_weapon_id != "knife":
				weapon_ctrl.equip_slot(3)
		elif weapon_ctrl.current_weapon_id in ["knife", "c4", "hegrenade", "flashbang", "smokegrenade"]:
			if not weapon_ctrl.equip_slot(1):
				weapon_ctrl.equip_slot(2)

	# Priority 4: Navigate toward tactical goal!
	_follow_navigation_path(delta)


func _scan_for_enemies() -> void:
	if is_instance_valid(target_enemy) and target_enemy.is_alive and _can_see_actor(target_enemy):
		return
	target_enemy = null

	var best_dist := 95.0
	var my_eye := get_eye_position()
	var my_fwd := get_look_forward()

	for a in RoundManager.actors:
		if not is_instance_valid(a) or a == self or not bool(a.get("is_alive")):
			continue
		if String(a.get("team")) == team:
			continue
		var a_actor := a as CSActor
		if a_actor == null:
			continue
		var d: float = my_eye.distance_to(a_actor.global_position)
		if d > best_dist:
			continue
		var dir_to: Vector3 = (a_actor.global_position + Vector3(0, 1.2, 0) - my_eye).normalized()
		# Field of view check (~135 deg cone, or 360 if very close < 4.5m)
		if d > 4.5 and my_fwd.dot(dir_to) < -0.22:
			continue
		if _can_see_actor(a_actor):
			best_dist = d
			target_enemy = a_actor
			var base_react: float = float([0.42, 0.27, 0.17, 0.09][clampi(skill_level, 0, 3)])
			_reaction_timer = base_react * randf_range(0.85, 1.25)


func _can_see_actor(other: Node3D) -> bool:
	var a := get_eye_position()
	var b := other.global_position + Vector3(0.0, 1.35, 0.0)
	if RoundManager.get_smoke_density_at(a) > 0.55 or RoundManager.is_line_blocked_by_smoke(a, b):
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _engage_enemy(delta: float) -> void:
	var dist := global_position.distance_to(target_enemy.global_position)

	# Occasional tactical Smoke / HE grenade toss at medium-long range
	if _grenade_cooldown <= 0.0 and dist > 12.0 and dist < 25.0 and health > 50 and randf() < 0.025:
		if int(weapon_ctrl.grenades.get("hegrenade", 0)) > 0:
			_grenade_cooldown = 13.0
			if weapon_ctrl.equip_weapon_by_id("hegrenade"):
				weapon_ctrl.fire_cooldown = 0.0
				_look_smoothly_toward(target_enemy.global_position + Vector3(0.0, 2.2, 0.0), 1.0)
				weapon_ctrl.trigger_primary(false, delta)
				return
		elif dist > 16.0 and int(weapon_ctrl.grenades.get("smokegrenade", 0)) > 0 and randf() < 0.35:
			_grenade_cooldown = 16.0
			if weapon_ctrl.equip_weapon_by_id("smokegrenade"):
				weapon_ctrl.fire_cooldown = 0.0
				var mid_pt := global_position.lerp(target_enemy.global_position, 0.55) + Vector3(0.0, 1.8, 0.0)
				_look_smoothly_toward(mid_pt, 1.0)
				weapon_ctrl.trigger_primary(false, delta)
				return

	# Ensure combat gun equipped; quick-switch to sidearm if primary runs dry in close quarters!
	if weapon_ctrl.current_weapon_id in ["c4", "knife", "hegrenade", "flashbang", "smokegrenade"]:
		if not weapon_ctrl.equip_slot(1):
			weapon_ctrl.equip_slot(2)
	else:
		var cr := weapon_ctrl.get_clip_and_reserve()
		if cr.x == 0:
			var cur_slot := int(weapon_ctrl.get_current_spec().get("slot", 1))
			var sec_id := String(weapon_ctrl.slots.get(2, ""))
			if cur_slot == 1 and dist < 13.5 and not sec_id.is_empty() and int(weapon_ctrl.clips.get(sec_id, 0)) > 0:
				# Classic CS 1.5 pro reflex: whip out USP/Glock/Deagle instead of reloading in enemy's face!
				weapon_ctrl.equip_slot(2)
			elif cr.y > 0 and not weapon_ctrl.is_reloading:
				weapon_ctrl.start_reload()

	var wid := weapon_ctrl.current_weapon_id
	var is_sniper := wid in ["awp", "scout", "g3sg1", "sg550"]

	# Sniper Bot scopes in at medium/long range before taking the shot!
	if is_sniper and dist > 11.0 and weapon_ctrl.zoom_stage == 0 and not weapon_ctrl.is_reloading and weapon_ctrl.fire_cooldown <= 0.15:
		weapon_ctrl.trigger_secondary()

	var aim_height := 1.48 if skill_level >= 2 else 1.24
	if target_enemy.is_crouching:
		aim_height *= 0.65
	# Subtle velocity lead & organic micro-imperfection scaled inversely by bot skill
	var spread_err := float([0.22, 0.13, 0.06, 0.02][clampi(skill_level, 0, 3)])
	var lead := target_enemy.velocity * 0.045 + Vector3(sin(Time.get_ticks_msec() * 0.007) * spread_err, 0.0, cos(Time.get_ticks_msec() * 0.006) * spread_err)
	var aim_pt := target_enemy.global_position + Vector3(0.0, aim_height, 0.0) + lead
	var track_spd: float = float([5.5, 8.2, 12.0, 17.0][clampi(skill_level, 0, 3)])
	_look_smoothly_toward(aim_pt, delta * track_spd)

	# PodBot / CSBot 3-phase combat footwork:
	#   1) Evasive lateral strafe (_strafe_timer)
	#   2) Counter-strafe plant / crouch-peek (_burst_stop_timer) for dead-accurate rifle bursts!
	if _burst_pause_timer > 0.0:
		_burst_pause_timer = maxf(0.0, _burst_pause_timer - delta)

	if _crouch_burst_timer > 0.0:
		_crouch_burst_timer = maxf(0.0, _crouch_burst_timer - delta)

	if _burst_stop_timer > 0.0:
		_burst_stop_timer = maxf(0.0, _burst_stop_timer - delta)
	else:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_dir = -_strafe_dir
			_strafe_timer = randf_range(0.42, 0.86)
			if dist > 7.5 and not weapon_ctrl.is_reloading:
				# Plant feet for counter-strafed burst!
				_burst_stop_timer = randf_range(0.26, 0.48) if not is_sniper else randf_range(0.38, 0.62)
				if skill_level >= 2 and dist > 16.0 and randf() < 0.28:
					_crouch_burst_timer = _burst_stop_timer + 0.18

	var crouch_shoot := _crouch_burst_timer > 0.0
	var strafe_vec := Vector3.ZERO
	if weapon_ctrl.is_reloading:
		# Dodge aggressively sideways/backwards toward cover while reloading!
		var right_rel := Basis(Vector3.UP, look_yaw).x
		var back_rel := Basis(Vector3.UP, look_yaw).z * (0.55 if dist < 12.0 else 0.0)
		strafe_vec = _steer_around_obstacles((right_rel * _strafe_dir + back_rel).normalized())
	elif not crouch_shoot and (_burst_stop_timer <= 0.0 or dist < 6.5):
		var right := Basis(Vector3.UP, look_yaw).x
		var fwd_adjust := Vector3.ZERO
		if wid == "knife":
			fwd_adjust = -Basis(Vector3.UP, look_yaw).z * 0.95
		elif dist < 3.6:
			fwd_adjust = Basis(Vector3.UP, look_yaw).z * 0.45
		strafe_vec = _steer_around_obstacles((right * _strafe_dir + fwd_adjust).normalized())

	apply_goldsrc_movement(strafe_vec, false, crouch_shoot, false, delta)

	if _reaction_timer > 0.0:
		_reaction_timer -= delta
		return

	if _burst_pause_timer > 0.0:
		return

	var to_tgt := (aim_pt - get_eye_position()).normalized()
	var align_req := 0.965 if (dist > 20.0 or is_sniper) else 0.925
	if get_look_forward().dot(to_tgt) > align_req:
		# Authentic CS 1.5 burst discipline: pause briefly to reset recoil after 3-5 shots at range!
		var max_burst := 100
		if dist > 23.0:
			max_burst = 3
		elif dist > 11.5:
			max_burst = 5
		if weapon_ctrl.shots_fired >= max_burst:
			_burst_pause_timer = randf_range(0.18, 0.30)
			return
		weapon_ctrl.trigger_primary(false, delta)


func _update_tactical_objective() -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	var gw := RoundManager.game_world
	var nav: BotNavigator = gw.get("bot_navigator")
	if nav == null:
		return

	# Radio order follow
	if is_instance_valid(_follow_target) and bool(_follow_target.get("is_alive")):
		if global_position.distance_to(_follow_target.global_position) > 3.8:
			_set_nav_goal(nav, _follow_target.global_position)
		return

	if _hold_pos_timer > 0.0:
		_nav_path.clear()
		return

	# Urgent objective: Planted C4!
	if is_instance_valid(RoundManager.planted_c4):
		var c4_pos := RoundManager.planted_c4.global_position
		if team == "CT":
			if not _has_goal or _goal_pos.distance_to(c4_pos) > 2.5 or _nav_path.is_empty():
				_set_nav_goal(nav, c4_pos)
			return
		else:
			if not _has_goal or _goal_pos.distance_to(c4_pos) > 9.0:
				_set_nav_goal(nav, c4_pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)))
			return

	# VIP Escape mode (as_*)
	if is_vip:
		var ez: Array = gw.get("escape_zones")
		if not ez.is_empty() and (_nav_path.is_empty() or not _has_goal):
			_set_nav_goal(nav, (ez[0] as AABB).get_center())
		return

	# Bomb Carrier T -> head to Bombsite A or B!
	if team == "T" and String(weapon_ctrl.slots.get(5, "")) == "c4":
		var bsites: Array = gw.get("bombsites")
		if not bsites.is_empty() and (_nav_path.is_empty() or not _has_goal):
			var site_aabb: AABB = bsites[randi() % bsites.size()]
			_set_nav_goal(nav, site_aabb.get_center())
		return

	# Hostage Rescue CT -> rescue nearest unrescued hostage or escort to rescue zone!
	if team == "CT" and RoundManager.map_mode == "cs":
		for h in RoundManager.hostages:
			var h_npc := h as HostageNPC
			if is_instance_valid(h_npc) and h_npc.is_alive and not h_npc.is_rescued:
				if h_npc.leader == self:
					var rz: Array = gw.get("rescue_zones")
					if not rz.is_empty() and (_nav_path.is_empty() or _goal_pos.distance_to((rz[0] as AABB).get_center()) > 3.0):
						_set_nav_goal(nav, (rz[0] as AABB).get_center())
					return
				elif h_npc.leader == null:
					if global_position.distance_to(h_npc.global_position) < 2.2:
						h_npc.interact(self)
					elif _nav_path.is_empty() or not _has_goal:
						_set_nav_goal(nav, h_npc.global_position)
					return

	# General patrol across bombsites / hostages / map waypoints
	if _nav_path.is_empty() or not _has_goal:
		var bsites2: Array = gw.get("bombsites")
		if not bsites2.is_empty() and randf() < 0.65:
			var s_aabb: AABB = bsites2[randi() % bsites2.size()]
			_set_nav_goal(nav, s_aabb.get_center() + Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.5, 3.5)))
		else:
			_set_nav_goal(nav, nav.get_random_waypoint(global_position))


func _set_nav_goal(nav: BotNavigator, dest: Vector3) -> void:
	_goal_pos = dest
	_has_goal = true
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if (is_inside_tree() and get_world_3d()) else null
	_nav_path = nav.find_path(global_position, dest, space)


func _follow_navigation_path(delta: float) -> void:
	if _jump_cooldown > 0.0:
		_jump_cooldown = maxf(0.0, _jump_cooldown - delta)

	# Active open-corridor unstick maneuver: walk cleanly out into open space before repathing!
	if _escape_timer > 0.0:
		_escape_timer -= delta
		var esc_move := _steer_around_obstacles(_escape_dir)
		_look_smoothly_toward(global_position + esc_move * 3.5 + Vector3(0.0, 1.45, 0.0), delta * 8.0)
		apply_goldsrc_movement(esc_move, false, false, false, delta)
		_last_pos = global_position
		if _escape_timer <= 0.0 and is_instance_valid(RoundManager.game_world):
			var nav_r: BotNavigator = RoundManager.game_world.get("bot_navigator")
			if nav_r != null:
				_set_nav_goal(nav_r, _goal_pos if _has_goal else nav_r.get_random_waypoint(global_position))
		return

	if _hold_pos_timer > 0.0 or _nav_path.is_empty():
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return

	# Path string-pulling: if next+1 waypoint is already in clear same-level sight, advance smoothly!
	if _nav_path.size() >= 2 and is_inside_tree() and get_world_3d():
		var wp_next := _nav_path[1]
		if absf(wp_next.y - global_position.y) < 1.05 and global_position.distance_to(wp_next) < 7.5:
			var sp := get_world_3d().direct_space_state
			var q_sc := PhysicsRayQueryParameters3D.create(
				global_position + Vector3(0.0, 0.85, 0.0),
				wp_next + Vector3(0.0, 0.75, 0.0)
			)
			q_sc.collision_mask = 1
			if sp.intersect_ray(q_sc).is_empty():
				_nav_path.remove_at(0)

	var wp := _nav_path[0]
	var flat_d := Vector2(wp.x - global_position.x, wp.z - global_position.z).length()
	var vert_d := absf(wp.y - global_position.y)
	if flat_d < 1.35 and vert_d < 2.2:
		_nav_path.remove_at(0)
		_stuck_timer = 0.0
		if _nav_path.is_empty():
			_has_goal = false
			apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
			_last_pos = global_position
			return
		wp = _nav_path[0]

	var raw_dir := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
	if raw_dir.length_squared() > 0.001:
		raw_dir = raw_dir.normalized()

	var move_dir := _steer_around_obstacles(raw_dir)

	# PodBot scripted pre-aiming: aim at chest/head height along upcoming corridor or toward heard enemy sound!
	_corner_check_timer -= delta
	if _corner_check_timer <= 0.0:
		_corner_check_timer = randf_range(1.1, 2.4)
		if randf() < 0.36 and _knife_rush_timer <= 0.0:
			_corner_yaw_offset = deg_to_rad(randf_range(-24.0, 24.0))
		else:
			_corner_yaw_offset = 0.0

	var look_pt: Vector3
	if _sound_investigate_timer > 0.0:
		look_pt = _sound_investigate_pos + Vector3(0.0, 1.42, 0.0)
	else:
		var ahead_wp := _nav_path[mini(1, _nav_path.size() - 1)]
		var look_dir := Vector3(ahead_wp.x - global_position.x, 0.0, ahead_wp.z - global_position.z)
		if look_dir.length_squared() < 0.04:
			look_dir = move_dir
		else:
			look_dir = look_dir.normalized()
		look_dir = look_dir.rotated(Vector3.UP, _corner_yaw_offset)
		look_pt = global_position + look_dir * 4.5 + Vector3(0.0, 1.48, 0.0)
	_look_smoothly_toward(look_pt, delta * 8.5)

	var want_jump := false
	if not RoundManager.is_movement_frozen():
		var moved_dist := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length()
		if moved_dist < 1.15 * delta:
			_stuck_timer += delta
			if _stuck_timer > 0.32 and _jump_cooldown <= 0.0 and is_on_floor():
				if _is_jumpable_ledge(raw_dir):
					want_jump = true
					_jump_cooldown = 1.95
			if _stuck_timer > 0.52:
				_stuck_timer = 0.0
				_avoid_side = -_avoid_side
				if is_instance_valid(RoundManager.game_world):
					var nav_b: BotNavigator = RoundManager.game_world.get("bot_navigator")
					if nav_b != null:
						nav_b.report_blocked_segment(global_position, wp)
				_escape_dir = _pick_open_escape_direction(raw_dir)
				_escape_timer = 0.68
				_nav_path.clear()
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.2)
		_last_pos = global_position

	var want_silent_walk := _stealth_walk_timer > 0.0 and _knife_rush_timer <= 0.0 and not want_jump
	apply_goldsrc_movement(move_dir, want_jump, false, want_silent_walk, delta)


func _pick_open_escape_direction(blocked_dir: Vector3) -> Vector3:
	if not is_inside_tree() or not get_world_3d():
		return -blocked_dir
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 0.92, 0.0)
	var best_dir := -blocked_dir
	var best_score := -1e9
	var base := blocked_dir if blocked_dir.length_squared() > 0.01 else Vector3.FORWARD
	for i in range(8):
		var ang := deg_to_rad(float(i) * 45.0)
		var cand := base.rotated(Vector3.UP, ang).normalized()
		var q := PhysicsRayQueryParameters3D.create(origin, origin + cand * 4.5)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var free_d := 4.5 if hit.is_empty() else origin.distance_to(hit["position"] as Vector3)
		# Prefer wide-open directions angled away from the blocked wall!
		var away_bonus := (1.0 - cand.dot(base)) * 0.85
		var score := free_d + away_bonus + randf_range(-0.15, 0.15)
		if score > best_score:
			best_score = score
			best_dir = cand
	return best_dir


func _steer_around_obstacles(desired_dir: Vector3) -> Vector3:
	if desired_dir.length_squared() < 0.001 or not is_inside_tree() or not get_world_3d():
		return desired_dir

	var steer := desired_dir
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 0.92, 0.0)

	# 5-ray whisker fan (center, +-32 deg, +-62 deg) so bots smoothly round wall corners & parapets
	var q_mid := PhysicsRayQueryParameters3D.create(origin, origin + desired_dir * 1.45)
	q_mid.collision_mask = 1
	var hit_mid := space.intersect_ray(q_mid)
	if not hit_mid.is_empty():
		var angles := [34.0 * _avoid_side, -34.0 * _avoid_side, 64.0 * _avoid_side, -64.0 * _avoid_side]
		var found_open := false
		for deg_a in angles:
			var cand_dir := desired_dir.rotated(Vector3.UP, deg_to_rad(float(deg_a)))
			var qc := PhysicsRayQueryParameters3D.create(origin, origin + cand_dir * 1.75)
			qc.collision_mask = 1
			if space.intersect_ray(qc).is_empty():
				steer = cand_dir
				found_open = true
				break
		if not found_open:
			var nrm := hit_mid["normal"] as Vector3
			nrm.y = 0.0
			var slide := (desired_dir - nrm * desired_dir.dot(nrm))
			if slide.length_squared() > 0.04:
				steer = slide.normalized()
			else:
				steer = desired_dir.rotated(Vector3.UP, deg_to_rad(115.0 * _avoid_side))

	# Strong separation + right-hand passing rule so Bots never bunch up shoulder-to-shoulder
	for a in RoundManager.actors:
		if not is_instance_valid(a) or a == self or not bool(a.get("is_alive")):
			continue
		var a_node := a as Node3D
		if a_node == null:
			continue
		var diff := global_position - a_node.global_position
		diff.y = 0.0
		var dsq := diff.length_squared()
		if dsq > 0.0001 and dsq < 2.40:
			var dist := sqrt(dsq)
			var away := diff / dist
			var tangent := Vector3(-away.z, 0.0, away.x) * _avoid_side
			var push := (1.55 - minf(1.55, dist)) * 1.15
			steer += away * push + tangent * (push * 0.45)

	steer.y = 0.0
	return steer.normalized() if steer.length_squared() > 0.001 else desired_dir


func _is_jumpable_ledge(fwd_dir: Vector3) -> bool:
	if fwd_dir.length_squared() < 0.001 or not is_inside_tree() or not get_world_3d():
		return false
	var space := get_world_3d().direct_space_state
	var low_from := global_position + Vector3(0.0, 0.68, 0.0)
	var high_from := global_position + Vector3(0.0, 1.68, 0.0)
	var q_low := PhysicsRayQueryParameters3D.create(low_from, low_from + fwd_dir * 1.05)
	q_low.collision_mask = 1
	var q_high := PhysicsRayQueryParameters3D.create(high_from, high_from + fwd_dir * 1.15)
	q_high.collision_mask = 1
	return (not space.intersect_ray(q_low).is_empty()) and space.intersect_ray(q_high).is_empty()


func _look_smoothly_toward(world_pt: Vector3, weight: float) -> void:
	var diff := world_pt - get_eye_position()
	var hlen := Vector2(diff.x, diff.z).length()
	if hlen < 0.01:
		return
	var target_yaw := atan2(-diff.x, -diff.z)
	var target_pitch := clampf(atan2(diff.y, hlen), deg_to_rad(-75.0), deg_to_rad(75.0))
	look_yaw = lerp_angle(look_yaw, target_yaw, clampf(weight, 0.0, 1.0))
	look_pitch = lerpf(look_pitch, target_pitch, clampf(weight, 0.0, 1.0))


func _on_world_sound(spos: Vector3, radius: float, steam: String) -> void:
	if not is_alive or steam == team or target_enemy != null:
		return
	var d := global_position.distance_to(spos)
	if d <= radius:
		_knife_rush_timer = 0.0
		if randf() < 0.65:
			_sound_investigate_pos = spos
			_sound_investigate_timer = randf_range(1.4, 2.6)
		# Skilled CS 1.5 Bots shift-walk silently when creeping up on nearby footsteps/reloads!
		if skill_level >= 1 and d < 15.5 and d > 4.0 and not is_instance_valid(RoundManager.planted_c4) and randf() < 0.55:
			_stealth_walk_timer = randf_range(1.3, 2.5)


func _on_radio_order(sender: Node3D, steam: String, action: String, pos: Vector3) -> void:
	if not is_alive or steam != team or sender == self:
		return
	match action:
		"follow_me", "cover_me":
			if global_position.distance_to(pos) < 24.0:
				_follow_target = sender
				_hold_pos_timer = 0.0
		"hold_position":
			if global_position.distance_to(pos) < 20.0:
				_follow_target = null
				_hold_pos_timer = 15.0
		"go", "storm_front":
			_follow_target = null
			_hold_pos_timer = 0.0
