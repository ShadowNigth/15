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
var _last_pos: Vector3 = Vector3.ZERO
var _strafe_dir: float = 1.0
var _strafe_timer: float = 0.0
var _follow_target: Node3D = null
var _hold_pos_timer: float = 0.0
var _defusing_ref: PlantedC4 = null
var _bought_this_round: bool = false


func _ready() -> void:
	is_human = false
	super._ready()
	AudioManager.world_sound_emitted.connect(_on_world_sound)
	RoundManager.radio_order_issued.connect(_on_radio_order)


func spawn_for_round(pos: Vector3, yaw_rad: float, reset_weapons: bool) -> void:
	super.spawn_for_round(pos, yaw_rad, reset_weapons)
	target_enemy = null
	_nav_path.clear()
	_has_goal = false
	_follow_target = null
	_hold_pos_timer = 0.0
	_defusing_ref = null
	_bought_this_round = false
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

	# Buy HE grenade if spare cash
	if money >= 600 and randf() < 0.45:
		buy_weapon("hegrenade")


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

	# Reload safely when out of combat
	var cr := weapon_ctrl.get_clip_and_reserve()
	if cr.x == 0 and cr.y > 0 and not weapon_ctrl.is_reloading:
		weapon_ctrl.start_reload()
	elif target_enemy == null and cr.x > 0 and cr.y > 0:
		var csize := int(weapon_ctrl.get_current_spec().get("clip_size", 30))
		if cr.x < csize / 3 and not weapon_ctrl.is_reloading:
			weapon_ctrl.start_reload()

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
			if RoundManager.game_world.is_in_bombsite(global_position):
				if weapon_ctrl.current_weapon_id != "c4":
					weapon_ctrl.equip_slot(5)
				apply_goldsrc_movement(Vector3.ZERO, false, true, false, delta)
				weapon_ctrl.trigger_primary(true, delta)
				return

	# Priority 3: Engage Visible Enemy!
	if is_instance_valid(target_enemy) and target_enemy.is_alive:
		_engage_enemy(delta)
		return

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
		var d := my_eye.distance_to(a.global_position)
		if d > best_dist:
			continue
		var dir_to := (a.global_position + Vector3(0, 1.2, 0) - my_eye).normalized()
		# Field of view check (~135 deg cone, or 360 if very close < 4.5m)
		if d > 4.5 and my_fwd.dot(dir_to) < -0.22:
			continue
		if _can_see_actor(a):
			best_dist = d
			target_enemy = a
			var base_react := [0.42, 0.27, 0.17, 0.09][clampi(skill_level, 0, 3)]
			_reaction_timer = base_react * randf_range(0.85, 1.25)


func _can_see_actor(other: Node3D) -> bool:
	var a := get_eye_position()
	var b := other.global_position + Vector3(0.0, 1.35, 0.0)
	if RoundManager.is_line_blocked_by_smoke(a, b):
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _engage_enemy(delta: float) -> void:
	# Ensure gun equipped (not knife/C4 unless out of ammo)
	if weapon_ctrl.current_weapon_id in ["c4", "knife"]:
		if not weapon_ctrl.equip_slot(1):
			weapon_ctrl.equip_slot(2)

	var aim_height := 1.48 if skill_level >= 2 else 1.22
	if target_enemy.is_crouching:
		aim_height *= 0.65
	var aim_pt := target_enemy.global_position + Vector3(0.0, aim_height, 0.0)
	var track_spd := [5.0, 7.5, 11.0, 16.0][clampi(skill_level, 0, 3)]
	_look_smoothly_toward(aim_pt, delta * track_spd)

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = randf_range(0.45, 1.1)
		_strafe_dir = -_strafe_dir

	var dist := global_position.distance_to(target_enemy.global_position)
	var crouch_shoot := dist > 14.0 and skill_level >= 1
	var strafe_vec := Vector3.ZERO
	if not crouch_shoot:
		var right := Basis(Vector3.UP, look_yaw).x
		strafe_vec = right * _strafe_dir

	apply_goldsrc_movement(strafe_vec, false, crouch_shoot, false, delta)

	if _reaction_timer > 0.0:
		_reaction_timer -= delta
		return

	var to_tgt := (aim_pt - get_eye_position()).normalized()
	if get_look_forward().dot(to_tgt) > 0.94:
		# Tap / burst control at medium-long range
		if dist > 20.0 and weapon_ctrl.shots_fired > 4:
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
			if is_instance_valid(h) and h.is_alive and not h.is_rescued:
				if h.leader == self:
					var rz: Array = gw.get("rescue_zones")
					if not rz.is_empty() and (_nav_path.is_empty() or _goal_pos.distance_to((rz[0] as AABB).get_center()) > 3.0):
						_set_nav_goal(nav, (rz[0] as AABB).get_center())
					return
				elif h.leader == null:
					if global_position.distance_to(h.global_position) < 2.2:
						h.interact(self)
					elif _nav_path.is_empty() or not _has_goal:
						_set_nav_goal(nav, h.global_position)
					return

	# General patrol across bombsites / hostages / map waypoints
	if _nav_path.is_empty() or not _has_goal:
		var bsites2: Array = gw.get("bombsites")
		if not bsites2.is_empty() and randf() < 0.65:
			var s_aabb: AABB = bsites2[randi() % bsites2.size()]
			_set_nav_goal(nav, s_aabb.get_center() + Vector3(randf_range(-3.5, 3.5), 0, randf_range(-3.5, 3.5)))
		else:
			_set_nav_goal(nav, nav.get_random_waypoint())


func _set_nav_goal(nav: BotNavigator, dest: Vector3) -> void:
	_goal_pos = dest
	_has_goal = true
	_nav_path = nav.find_path(global_position, dest)


func _follow_navigation_path(delta: float) -> void:
	if _hold_pos_timer > 0.0 or _nav_path.is_empty():
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		return

	var wp := _nav_path[0]
	var flat_d := Vector2(wp.x - global_position.x, wp.z - global_position.z).length()
	if flat_d < 1.15:
		_nav_path.remove_at(0)
		if _nav_path.is_empty():
			_has_goal = false
			apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
			return
		wp = _nav_path[0]

	var move_dir := Vector3(wp.x - global_position.x, 0.0, wp.z - global_position.z)
	if move_dir.length_squared() > 0.001:
		move_dir = move_dir.normalized()

	_look_smoothly_toward(wp + Vector3(0.0, 1.45, 0.0), delta * 6.5)

	# Stuck detection -> jump or repath!
	var want_jump := false
	if not RoundManager.is_movement_frozen():
		if global_position.distance_to(_last_pos) < 0.12 * delta * 60.0:
			_stuck_timer += delta
			if _stuck_timer > 0.45:
				want_jump = true
			if _stuck_timer > 1.35:
				_stuck_timer = 0.0
				_nav_path.clear()
				_has_goal = false
		else:
			_stuck_timer = 0.0
		_last_pos = global_position

	apply_goldsrc_movement(move_dir, want_jump, false, false, delta)


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
	if global_position.distance_to(spos) <= radius and randf() < 0.45:
		_look_smoothly_toward(spos + Vector3(0, 1.2, 0), 0.35)


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
