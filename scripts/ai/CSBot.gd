class_name CSBot
extends CSActor
## Authentic YaPB-Powered Counter-Strike 1.5 Bot AI:
##   - Navigates official human-curated YaPB (.graph) directed waypoint graphs across all 26 maps
##   - Personalities (Rusher, Normal, Careful/Sniper) driving weapon buys, route diversity & danger avoidance
##   - Executes YaPB Jump-Links (ballistic launch velocity + crouch-jump), Crouch vents, Ladders & Doors
##   - Holds human-authored Camp & Sniper sightlines (start/end sweep vectors + node reservation)
##   - Full DE (plant/guard/defuse C4), CS (hostage-safe escort & defense), and AS (VIP escort/ambush) tactics
##   - Counter-strafed rifle bursts, recoil compensation, reload cover-seeking, grenades & squad callouts

const BOT_NAMES: Array[String] = [
	"[POD]Gooseman", "[POD]Cliffe", "HeatoN", "Potti", "SpawN", "elemeNt",
	"Ksharp", "Johnny_R", "shaGuar", "moto", "fisker", "ahl",
	"vesslan", "Bullseye", "rambo", "Method", "XeqtR", "bds",
]

const PERSONALITY_RUSHER: int = 0
const PERSONALITY_NORMAL: int = 1
const PERSONALITY_CAREFUL: int = 2

var skill_level: int = 1  # 0=Easy, 1=Normal, 2=Hard, 3=Expert
var personality: int = PERSONALITY_NORMAL
var target_enemy: CSActor = null

# YaPB directed node-graph navigation state
var traffic := TeammateTraffic.new()
var bomb_role: String = "none"
var _bomb_role_node: int = -1
var _bomb_role_epoch: int = 0

var _node_path: PackedInt32Array = PackedInt32Array()
var _prev_node_idx: int = -1
var _goal_node_idx: int = -1
var _goal_pos: Vector3 = Vector3.ZERO
var _has_goal: bool = false
var _cur_node_offset: Vector3 = Vector3.ZERO
var _cur_node_elapsed: float = 0.0
var _nav_clock: float = 0.0
var _banned_nodes: Dictionary = {}
var _rechoice_count: int = 0
var _air_crouch_timer: float = 0.0
var _diversity_seed: int = 0

# YaPB Camp / Sniper sightline state
var _camping_node_idx: int = -1
var _camp_timer: float = 0.0
var _camp_cooldown: float = 0.0
var _camp_sweep_timer: float = 0.0
var _camp_look_alt: bool = false

# Timers & combat state
var _reaction_timer: float = 0.0
var _think_timer: float = 0.0
var _stuck_timer: float = 0.0
var _jump_cooldown: float = 0.0
var _crouch_burst_timer: float = 0.0
var _escape_timer: float = 0.0
var _escape_dir: Vector3 = Vector3.ZERO
var _smoothed_move_dir: Vector3 = Vector3.ZERO
var _rollout_delay: float = 0.0
var _vent_crouch_timer: float = 0.0
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
var _last_bought_primary: String = ""

# AS squad coordination / extraction state
var _vip_escape_node: int = -1
var _vip_route_rethink: float = 0.0
var _vip_direct_active: bool = false
var _vip_direct_goal: Vector3 = Vector3.ZERO
var _vip_direct_elapsed: float = 0.0
var _vip_escort_slot: int = 0
var _vip_escort_direct_active: bool = false
var _vip_escort_direct_goal: Vector3 = Vector3.ZERO
var _vip_escort_direct_elapsed: float = 0.0
var _vip_escort_repath: float = 0.0
var _vip_escort_wait_since: float = -1.0
var _vip_route_history := PackedInt32Array()
var _vip_breadcrumb_active: bool = false
var _contact_report_cd: float = 0.0
var _cover_dir: Vector3 = Vector3.ZERO
var _cover_check_timer: float = 0.0

# C4 blast escape & equipment-preservation state
var _bomb_escape_active: bool = false
var _bomb_flee_node: int = -1
var _bomb_flee_min_dist: float = 0.0

# Critical-HP disengage (fall back instead of suicide-trading the duel)
var _disengage_timer: float = 0.0
var _disengage_dir: Vector3 = Vector3.ZERO
var _disengage_check_cd: float = 0.0

# Team economy: freezetime weapon-share gift pickup task
var _share_checked: bool = false
var _pending_share_drop: DroppedWeapon = null

# Hostage pickup / escort mission state. The final metres to an NPC or a real
# rescue brush are a direct objective, not an approximation to its nearest node.
const HOSTAGE_DIRECT_PICKUP: int = 0
const HOSTAGE_DIRECT_RESCUE: int = 1
const HOSTAGE_DIRECT_REGROUP: int = 2
var _hostage_target: HostageNPC = null
var _hostage_rescue_zone_idx: int = -1
var _hostage_repath: float = 0.0
var _hostage_direct_active: bool = false
var _hostage_direct_mode: int = HOSTAGE_DIRECT_PICKUP
var _hostage_direct_target: HostageNPC = null
var _hostage_direct_goal: Vector3 = Vector3.ZERO
var _hostage_direct_elapsed: float = 0.0
var _hostage_direct_stuck: float = 0.0


func _ready() -> void:
	is_human = false
	super._ready()
	_avoid_side = 1.0 if randf() < 0.5 else -1.0
	_assign_personality()
	AudioManager.world_sound_emitted.connect(_on_world_sound)
	RoundManager.radio_order_issued.connect(_on_radio_order)
	RoundManager.freeze_ended.connect(_on_bot_freeze_ended)


func _assign_personality() -> void:
	if actor_name in ["Johnny_R", "Ksharp", "Method", "vesslan"]:
		personality = PERSONALITY_CAREFUL
	elif actor_name in ["HeatoN", "SpawN", "shaGuar", "fisker", "moto"]:
		personality = PERSONALITY_RUSHER
	else:
		personality = randi() % 3


func _on_bot_freeze_ended() -> void:
	if not is_alive or is_vip:
		return
	_assign_personality()
	_diversity_seed = randi()
	_rollout_delay = randf_range(0.0, 0.42)
	# YaPB opening Knife sprint (250 u/s) out of spawn!
	var knife_chance: float = 0.90 if personality == PERSONALITY_RUSHER else (0.72 if personality == PERSONALITY_NORMAL else 0.50)
	if randf() < knife_chance:
		_knife_rush_timer = randf_range(2.6, 4.8)


func spawn_for_round(pos: Vector3, yaw_rad: float, reset_weapons: bool) -> void:
	traffic.reset()
	bomb_role = "none"
	_bomb_role_node = -1
	_bomb_role_epoch = 0
	super.spawn_for_round(pos, yaw_rad, reset_weapons)
	_release_camp_spot()
	target_enemy = null
	_node_path = PackedInt32Array()
	_prev_node_idx = -1
	_goal_node_idx = -1
	_has_goal = false
	_cur_node_offset = Vector3.ZERO
	_cur_node_elapsed = 0.0
	_nav_clock = 0.0
	_banned_nodes.clear()
	_rechoice_count = 0
	_air_crouch_timer = 0.0
	_diversity_seed = randi()
	_camp_timer = 0.0
	_camp_cooldown = 0.0
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
	_smoothed_move_dir = Vector3.ZERO
	_rollout_delay = 0.0
	_vent_crouch_timer = 0.0
	_grenade_cooldown = randf_range(3.0, 9.0)
	_last_pos = global_position
	_think_timer = randf_range(0.08, 0.35)
	_bomb_escape_active = false
	_bomb_flee_node = -1
	_bomb_flee_min_dist = 0.0
	_disengage_timer = 0.0
	_disengage_check_cd = randf_range(0.5, 1.2)
	_share_checked = false
	_pending_share_drop = null
	_vip_escape_node = -1
	_vip_route_rethink = 0.0
	_vip_direct_active = false
	_vip_direct_goal = Vector3.ZERO
	_vip_direct_elapsed = 0.0
	_vip_escort_slot = 0
	_vip_escort_direct_active = false
	_vip_escort_direct_goal = Vector3.ZERO
	_vip_escort_direct_elapsed = 0.0
	_vip_escort_repath = 0.0
	_vip_escort_wait_since = -1.0
	_vip_route_history = PackedInt32Array()
	_vip_breadcrumb_active = false
	_contact_report_cd = 0.0
	_cover_dir = Vector3.ZERO
	_cover_check_timer = 0.0
	_hostage_target = null
	_hostage_rescue_zone_idx = -1
	_hostage_repath = 0.0
	_hostage_direct_active = false
	_hostage_direct_mode = HOSTAGE_DIRECT_PICKUP
	_hostage_direct_target = null
	_hostage_direct_goal = Vector3.ZERO
	_hostage_direct_elapsed = 0.0
	_hostage_direct_stuck = 0.0


func _release_camp_spot() -> void:
	if _camping_node_idx >= 0 and is_instance_valid(RoundManager.game_world):
		var nav: BotNavigator = RoundManager.game_world.get("bot_navigator")
		if nav != null:
			nav.release_actor_claims(self)
	_camping_node_idx = -1
	_camp_timer = 0.0


func _die(killer: Node3D, weapon_id: String, headshot: bool, kill_context: Dictionary = {}) -> void:
	if is_instance_valid(RoundManager.game_world):
		var nav: BotNavigator = RoundManager.game_world.get("bot_navigator")
		if nav != null:
			nav.release_actor_claims(self)
			nav.report_team_damage(team, global_position, 125.0)
	_camping_node_idx = -1
	super._die(killer, weapon_id, headshot, kill_context)


func _primary_class(wid: String) -> String:
	if wid in ["awp", "scout", "g3sg1", "sg550"]:
		return "sniper"
	if wid in ["m3", "xm1014", "mag7", "sawedoff"]:
		return "shotgun"
	if wid in ["m249", "negev"]:
		return "lmg"
	if wid in ["ak47", "m4a1", "m4a4", "aug", "sg552", "famas", "galil"]:
		return "rifle"
	return "smg"


func _primary_market_weight(
	wid: String,
	price: int,
	buy_budget: int,
	team_snipers: int,
	team_primary_counts: Dictionary,
	team_class_counts: Dictionary
) -> float:
	var weapon_class := _primary_class(wid)
	var weight := 1.0
	match weapon_class:
		"rifle":
			weight = 1.30 if personality != PERSONALITY_CAREFUL else 1.12
		"smg":
			weight = 1.34 if personality == PERSONALITY_RUSHER else (0.78 if personality == PERSONALITY_CAREFUL else 1.02)
		"shotgun":
			weight = 0.78 if personality == PERSONALITY_RUSHER else (0.28 if personality == PERSONALITY_CAREFUL else 0.52)
		"lmg":
			weight = 0.28 if personality == PERSONALITY_RUSHER else 0.20
		"sniper":
			weight = 0.22
			if wid == "scout":
				weight = 0.36
			if personality == PERSONALITY_CAREFUL:
				weight *= 2.75
			elif personality == PERSONALITY_RUSHER:
				weight *= 0.42
			if team_snipers >= 2:
				return 0.0

	# Strong diminishing returns for identical squad loadouts. This is a soft
	# composition rule, not a rotation: every legal affordable weapon remains
	# possible, while duplicates and repeated personal buys become uncommon.
	var same_count := int(team_primary_counts.get(wid, 0))
	weight *= pow(0.38, float(same_count))
	var same_class := int(team_class_counts.get(weapon_class, 0))
	if weapon_class in ["shotgun", "lmg"] and same_class >= 1:
		weight *= pow(0.45, float(same_class))
	if wid == _last_bought_primary:
		weight *= 0.24
	if float(price) > float(buy_budget) * 0.88:
		weight *= 0.82
	return maxf(0.0, weight)


func _build_primary_market(
	buy_budget: int,
	team_snipers: int,
	team_primary_counts: Dictionary,
	team_class_counts: Dictionary
) -> Array[Dictionary]:
	var market: Array[Dictionary] = []
	for wid_value in GameData.weapons.keys():
		var wid := String(wid_value)
		var spec: Dictionary = GameData.weapons[wid]
		if int(spec.get("slot", 0)) != 1 or bool(spec.get("grenade", false)):
			continue
		var weapon_team := String(spec.get("team", "ANY"))
		if weapon_team != "ANY" and weapon_team != team:
			continue
		var price := int(spec.get("price", 0))
		if price <= 0 or price > buy_budget:
			continue
		var weight := _primary_market_weight(
			wid, price, buy_budget, team_snipers, team_primary_counts, team_class_counts
		)
		if weight > 0.001:
			market.append({"id": wid, "weight": weight})
	return market


func _take_weighted_primary(market: Array[Dictionary]) -> String:
	if market.is_empty():
		return ""
	var total := 0.0
	for entry in market:
		total += float(entry.get("weight", 0.0))
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for candidate in market:
		roll -= float(candidate.get("weight", 0.0))
		if roll <= 0.0:
			return String(candidate.get("id", ""))
	return String(market.back().get("id", ""))


func _perform_bot_buy() -> void:
	_bought_this_round = true
	if is_vip or not can_use_buy_menu():
		return

	# --- Team economy survey: how many teammates are broke & how many snipers already deployed? ---
	var team_mates: Array[CSActor] = []
	var team_broke: int = 0
	var team_snipers: int = 0
	var team_primary_counts: Dictionary = {}
	var team_class_counts: Dictionary = {}
	for a in RoundManager.actors:
		if not is_instance_valid(a) or a == self:
			continue
		if String(a.get("team")) != team:
			continue
		var tm_a := a as CSActor
		if tm_a == null or not is_instance_valid(tm_a) or tm_a.is_vip:
			continue
		team_mates.append(tm_a)
		if tm_a.money < 1600:
			team_broke += 1
		var tm_p := String(tm_a.weapon_ctrl.slots.get(1, ""))
		if not tm_p.is_empty():
			team_primary_counts[tm_p] = int(team_primary_counts.get(tm_p, 0)) + 1
			var tm_class := _primary_class(tm_p)
			team_class_counts[tm_class] = int(team_class_counts.get(tm_class, 0)) + 1
		if tm_p in ["awp", "g3sg1", "sg550", "scout"]:
			team_snipers += 1

	var has_primary: bool = not String(weapon_ctrl.slots.get(1, "")).is_empty()
	var force_full_save: bool = money < 1500

	# CT defusal kit on DE maps when affordable (huge round-win value; reserve the $200 first!)
	var kit_cost: int = 0
	if team == "CT" and RoundManager.map_mode == "de" and not has_defuser and money >= 1200:
		kit_cost = 200

	# Plan the armor budget AFTER the primary so Kevlar never eats the rifle fund!
	var armor_budget: int = 0
	if armor < 100 and not force_full_save:
		if money - kit_cost >= 3300:
			armor_budget = 1000  # kevlar + helmet
		elif money - kit_cost >= 2100:
			armor_budget = 650  # kevlar vest only

	if kit_cost > 0:
		buy_equipment("defuser")

	# Weighted squad-aware primary market. Unlike the old first-affordable list,
	# an expensive AK/M4 no longer wins every purchase merely by appearing first.
	if not has_primary:
		var buy_budget: int = money - armor_budget - kit_cost

		# Pure eco: never buy a weapon under $1500 — the starting pistol survives, a rifle comes next round
		if money < 1500:
			force_full_save = true
		elif (
			money < 2500
			and team_broke >= maxi(1, team_mates.size() - 1)
			and personality != PERSONALITY_RUSHER
			and randf() < 0.55
		):
			# The whole team is broke and a rifle is one saved round away — keep the wallet closed!
			force_full_save = true

		if not force_full_save:
			var market := _build_primary_market(
				buy_budget, team_snipers, team_primary_counts, team_class_counts
			)
			while not market.is_empty():
				var wid := _take_weighted_primary(market)
				if wid.is_empty():
					break
				if buy_weapon(wid):
					_last_bought_primary = wid
					break
				for i in range(market.size() - 1, -1, -1):
					if String(market[i].get("id", "")) == wid:
						market.remove_at(i)

	# Armor top-up AFTER the weapon so the rifle is never starved by the vest!
	# On a forced save, only survivors rebuy a vest — protecting a carried rifle is an investment!
	if armor < 100 and (not force_full_save or has_primary):
		if money >= 1000:
			buy_equipment("kevlar_helmet")
		elif money >= 650:
			buy_equipment("kevlar")

	# Sniper bots pair AWP/Scout with a Desert Eagle when rich!
	var cur_p := String(weapon_ctrl.slots.get(1, ""))
	if cur_p in ["awp", "scout"] and money >= 900 and randf() < 0.65:
		buy_weapon("revolver" if randf() < 0.30 else "deagle")
	elif cur_p == "m4a1" and randf() < 0.55:
		weapon_ctrl.silenced_state["m4a1"] = true

	buy_ammo_for_slot(1, true)
	buy_ammo_for_slot(2, true)

	# Grenades only when not on a forced save (nades are a luxury on eco rounds)
	if not force_full_save:
		if money >= 550 and randf() < 0.58:
			buy_weapon("hegrenade")
		if money >= 450 and randf() < 0.36:
			buy_weapon("smokegrenade")
		if money >= 350 and randf() < 0.40:
			buy_weapon("flashbang")
		if money >= 650 and randf() < 0.30:
			buy_weapon("molotov" if team == "T" else "incendiary")
		if money >= 250 and randf() < 0.16:
			buy_weapon("decoy")


func _physics_process(delta: float) -> void:
	bot_ladder_dir = 0.0
	bot_ladder_anchor_valid = false
	if not is_alive:
		return
	_nav_clock += delta

	if not _share_checked and RoundManager.state == RoundManager.State.FREEZE:
		_share_checked = true
		_maybe_share_loadout()

	if not _bought_this_round and RoundManager.can_buy_now():
		_perform_bot_buy()

	# Blinded by Flashbang (YaPB TaskId::Blind)!
	if flash_alpha > 0.65:
		var blind_move := Basis(Vector3.UP, look_yaw) * Vector3(_strafe_dir * 0.5, 0.0, 0.3)
		apply_goldsrc_movement(blind_move.normalized(), false, false, false, delta)
		return

	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = randf_range(0.12, 0.22)
		_scan_for_enemies()
		_update_tactical_objective()

	if _hold_pos_timer > 0.0:
		_hold_pos_timer = maxf(0.0, _hold_pos_timer - delta)
	if _camp_cooldown > 0.0:
		_camp_cooldown = maxf(0.0, _camp_cooldown - delta)
	if _knife_rush_timer > 0.0:
		_knife_rush_timer = maxf(0.0, _knife_rush_timer - delta)
	if _stealth_walk_timer > 0.0:
		_stealth_walk_timer = maxf(0.0, _stealth_walk_timer - delta)
	if _sound_investigate_timer > 0.0:
		_sound_investigate_timer = maxf(0.0, _sound_investigate_timer - delta)
	if _grenade_cooldown > 0.0:
		_grenade_cooldown = maxf(0.0, _grenade_cooldown - delta)
	if _air_crouch_timer > 0.0:
		_air_crouch_timer = maxf(0.0, _air_crouch_timer - delta)
	if _disengage_check_cd > 0.0:
		_disengage_check_cd = maxf(0.0, _disengage_check_cd - delta)
	if _vip_route_rethink > 0.0:
		_vip_route_rethink = maxf(0.0, _vip_route_rethink - delta)
	if _contact_report_cd > 0.0:
		_contact_report_cd = maxf(0.0, _contact_report_cd - delta)
	if _cover_check_timer > 0.0:
		_cover_check_timer = maxf(0.0, _cover_check_timer - delta)
	if _vip_escort_repath > 0.0:
		_vip_escort_repath = maxf(0.0, _vip_escort_repath - delta)
	if _hostage_repath > 0.0:
		_hostage_repath = maxf(0.0, _hostage_repath - delta)
	_last_enemy_seen_age += delta

	# Priority 0.5: FLEE the C4 blast zone with the knife out — equipment preservation!
	# Exception: an enemy that cuts across the escape path must be fought instead
	# of ignored (both teams meet while running away from the blast).
	if _bomb_escape_active:
		var path_blocker: bool = is_instance_valid(target_enemy) and target_enemy.is_alive
		if not path_blocker:
			target_enemy = null
			if _defusing_ref != null:
				if is_instance_valid(_defusing_ref):
					_defusing_ref.cancel_defuse(self)
				_defusing_ref = null
			_knife_rush_timer = 0.0
			_stealth_walk_timer = 0.0
			if not weapon_ctrl.is_reloading and weapon_ctrl.current_weapon_id != "knife":
				weapon_ctrl.equip_slot(3)
			_follow_navigation_path(delta)
			return
		# Otherwise fall through: engage the blocker below (gun auto-equips there)

	# Reload safely when out of combat
	var cr := weapon_ctrl.get_clip_and_reserve()
	if target_enemy == null:
		if cr.x == 0 and cr.y > 0 and not weapon_ctrl.is_reloading:
			weapon_ctrl.start_reload()
		elif cr.x > 0 and cr.y > 0:
			var csize := int(weapon_ctrl.get_current_spec().get("clip_size", 30))
			if cr.x < int(float(csize) * 0.34) and not weapon_ctrl.is_reloading:
				weapon_ctrl.start_reload()
		if _camp_timer <= 0.0 and weapon_ctrl.zoom_index >= 0:
			weapon_ctrl.clear_zoom()

	# Priority 1: CT Defusing Planted C4 when clear (YaPB TaskId::DefuseBomb)!
	if team == "CT" and target_enemy == null and is_instance_valid(RoundManager.planted_c4):
		var c4 := RoundManager.planted_c4 as PlantedC4
		var defuse_nav: BotNavigator = RoundManager.game_world.get("bot_navigator") if is_instance_valid(RoundManager.game_world) else null
		if c4 and global_position.distance_to(c4.global_position) <= 2.35 and UseSelection.visible(self, c4.global_position+Vector3.UP*0.15) and BombSquad.elect_defuser(c4, RoundManager.actors, defuse_nav) == self:
			if c4.defuser_actor == null or c4.defuser_actor == self:
				_release_camp_spot()
				_defusing_ref = c4
				_look_smoothly_toward(c4.global_position + Vector3(0.0, 0.1, 0.0), delta * 8.0)
				c4.begin_or_continue_defuse(self, delta)
				apply_goldsrc_movement(Vector3.ZERO, false, true, false, delta)
				return

	if _defusing_ref != null:
		if is_instance_valid(_defusing_ref):
			_defusing_ref.cancel_defuse(self)
		_defusing_ref = null

	# Priority 2: T Planting C4 when inside Bombsite (YaPB TaskId::PlantBomb)!
	if team == "T" and target_enemy == null and String(weapon_ctrl.slots.get(5, "")) == "c4":
		if RoundManager.state == RoundManager.State.LIVE and is_instance_valid(RoundManager.game_world):
			if bool(RoundManager.game_world.call("is_in_bombsite", global_position)):
				_release_camp_spot()
				if weapon_ctrl.current_weapon_id != "c4":
					weapon_ctrl.equip_slot(5)
				apply_goldsrc_movement(Vector3.ZERO, false, true, false, delta)
				weapon_ctrl.trigger_primary(true, delta)
				return

	# Priority 2.5: Critical-HP tactical disengage — break contact & fall back to save the loadout!
	if _disengage_timer > 0.0:
		_disengage_timer -= delta
		var dis_dir := _blend_move_dir(_smoothed_move_dir, _disengage_dir, delta)
		_smoothed_move_dir = dis_dir
		_look_smoothly_toward(global_position + _disengage_dir * 9.0 + Vector3(0.0, 1.3, 0.0), delta * 5.5)
		if _is_utility_weapon(weapon_ctrl.current_weapon_id):
			if not weapon_ctrl.equip_slot(1):
				weapon_ctrl.equip_slot(2)
		apply_goldsrc_movement(dis_dir, false, false, false, delta)
		_last_pos = global_position
		return

	# Priority 3: Engage Visible Enemy (YaPB TaskId::Attack)!
	if is_instance_valid(target_enemy) and target_enemy.is_alive:
		_knife_rush_timer = 0.0
		_stealth_walk_timer = 0.0
		_camp_timer = 0.0
		_last_enemy_pos = target_enemy.global_position
		_last_enemy_seen_age = 0.0
		_engage_enemy(delta)
		return

	# Priority 3.5: Flush out an enemy that just ducked behind cover with an HE grenade!
	if _last_enemy_seen_age > 0.25 and _last_enemy_seen_age < 1.85 and _grenade_cooldown <= 0.0 and health > 40:
		var d_last := global_position.distance_to(_last_enemy_pos)
		if d_last > 8.5 and d_last < 23.0 and randf() < 0.09:
			var flush_grenades := ["hegrenade", "molotov" if team == "T" else "incendiary"]
			for gid in flush_grenades:
				if int(weapon_ctrl.grenades.get(gid, 0)) <= 0:
					continue
				_grenade_cooldown = 14.0
				if weapon_ctrl.equip_weapon_by_id(gid):
					weapon_ctrl.fire_cooldown = 0.0
					_look_smoothly_toward(_last_enemy_pos + Vector3(0.0, 2.1, 0.0), 1.0)
					weapon_ctrl.trigger_primary(false, delta)
					return

	# Priority 4: finish unobstructed mission approaches instead of stopping at
	# the nearest graph node (VIP brush, moving escort slot, hostage or rescue).
	if is_vip and _vip_direct_active:
		_follow_vip_direct_path(delta)
		return
	if _vip_escort_direct_active:
		_follow_vip_escort_direct(delta)
		return
	if _hostage_direct_active:
		_follow_hostage_direct(delta)
		return

	# Priority 4.5: Active YaPB Camp / Sniper Sightline Holding (TaskId::Camp)!
	if _camp_timer > 0.0 and _camping_node_idx >= 0:
		_execute_camp_behavior(delta)
		return

	# Weapon discipline during navigation: Knife rush out of spawn, then draw Primary Rifle before contact!
	# Assigned escorts also use the knife to match the lighter VIP while catching up.
	if _is_assigned_vip_escort():
		var vip := _find_live_vip()
		if is_instance_valid(vip):
			_update_vip_escort_weapon(vip)
	elif not weapon_ctrl.is_reloading:
		if _knife_rush_timer > 0.0 and _sound_investigate_timer <= 0.0 and not is_vip:
			if weapon_ctrl.current_weapon_id != "knife":
				weapon_ctrl.equip_slot(3)
		elif _is_utility_weapon(weapon_ctrl.current_weapon_id):
			if not weapon_ctrl.equip_slot(1):
				weapon_ctrl.equip_slot(2)

	# Priority 5: Navigate along YaPB directed node graph!
	_follow_navigation_path(delta)


func _execute_camp_behavior(delta: float) -> void:
	_camp_timer -= delta
	if _camp_timer <= 0.0 or (is_instance_valid(RoundManager.planted_c4) and team == "CT"):
		_camp_cooldown = 9.0
		_release_camp_spot()
		return

	if not weapon_ctrl.is_reloading and _is_utility_weapon(weapon_ctrl.current_weapon_id):
		if not weapon_ctrl.equip_slot(1):
			weapon_ctrl.equip_slot(2)

	var wid := weapon_ctrl.current_weapon_id
	var is_sniper := wid in ["awp", "scout", "g3sg1", "sg550"]
	if is_sniper and weapon_ctrl.zoom_index < 0 and not weapon_ctrl.is_reloading:
		weapon_ctrl.trigger_secondary()

	var crouch_camp := false
	var look_target := global_position + get_look_forward() * 12.0 + Vector3(0.0, 1.4, 0.0)
	if is_instance_valid(RoundManager.game_world):
		var nav: BotNavigator = RoundManager.game_world.get("bot_navigator")
		if nav != null:
			var nflags := nav.get_node_flags(_camping_node_idx)
			crouch_camp = (nflags & BotNavigator.FLAG_CROUCH) != 0
			var cdirs := nav.get_camp_dirs(_camping_node_idx)
			if cdirs.size() >= 2:
				_camp_sweep_timer -= delta
				if _camp_sweep_timer <= 0.0:
					_camp_sweep_timer = randf_range(2.2, 4.2)
					_camp_look_alt = not _camp_look_alt
				var aim_dir: Vector3 = cdirs[1] if _camp_look_alt else cdirs[0]
				look_target = get_eye_position() + aim_dir * 18.0

	if _sound_investigate_timer > 0.0:
		look_target = _sound_investigate_pos + Vector3(0.0, 1.4, 0.0)

	_look_smoothly_toward(look_target, delta * 4.5)
	apply_goldsrc_movement(Vector3.ZERO, false, crouch_camp, false, delta)
	_last_pos = global_position


func _scan_for_enemies() -> void:
	# While disengaging at critical HP, no new duel commitments!
	if _disengage_timer > 0.0:
		target_enemy = null
		return
	if is_instance_valid(target_enemy) and target_enemy.is_alive and _can_see_actor(target_enemy):
		if not is_vip or global_position.distance_to(target_enemy.global_position) <= 12.0:
			return
	target_enemy = null

	# Fleeing the blast: only enemies that cut across the escape path at close
	# range get committed to — but they DO get committed (both teams must fight
	# when they run into each other), instead of being ignored entirely.
	var max_d: float = 24.0 if _bomb_escape_active else (12.0 if is_vip else 105.0)
	var best_score := 1e9
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
		if d > max_d:
			continue
		var dir_to: Vector3 = (a_actor.global_position + Vector3(0.0, 1.2, 0.0) - my_eye).normalized()
		var cos_ang: float = my_fwd.dot(dir_to)
		if d > 4.8 and cos_ang < -0.20:
			continue
		if _can_see_actor(a_actor):
			# YaPB target priority: closer + closer to crosshair + VIP/C4 priority
			var threat_score: float = d - cos_ang * 6.0
			if a_actor.is_vip:
				threat_score -= 18.0
			if threat_score < best_score:
				best_score = threat_score
				target_enemy = a_actor
				var base_react: float = float([0.38, 0.24, 0.15, 0.08][clampi(skill_level, 0, 3)])
				_reaction_timer = base_react * randf_range(0.85, 1.20)

	if is_instance_valid(target_enemy) and _contact_report_cd <= 0.0:
		_contact_report_cd = 1.6
		if is_instance_valid(RoundManager.game_world):
			var nav: BotNavigator = RoundManager.game_world.get("bot_navigator")
			if nav != null:
				nav.report_team_contact(team, target_enemy.global_position, 0.85)
		for raw in RoundManager.actors:
			var mate := raw as CSBot
			if is_instance_valid(mate) and mate != self and mate.is_alive and mate.team == team:
				if mate.target_enemy == null and mate.global_position.distance_to(global_position) < 24.0:
					mate.notify_squad_contact(target_enemy.global_position)


func _is_utility_weapon(wid: String) -> bool:
	if wid in ["knife", "c4", "taser"]:
		return true
	return bool((GameData.weapons.get(wid, {}) as Dictionary).get("grenade", false))


func _can_see_actor(other: Node3D) -> bool:
	var a := get_eye_position()
	var b := other.global_position + Vector3(0.0, 1.35, 0.0)
	if RoundManager.get_smoke_density_at(a) > 0.55 or RoundManager.is_line_blocked_by_smoke(a, b):
		return false
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


func _find_cover_direction(threat_pos: Vector3) -> Vector3:
	var away := global_position - threat_pos
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = -get_look_forward()
		away.y = 0.0
	away = away.normalized()
	var best_dir := away
	var best_score := -1e9
	var space := get_world_3d().direct_space_state
	var threat_eye := threat_pos + Vector3(0.0, 1.30, 0.0)
	var angle_offset := randf() * TAU
	for i in range(8):
		var angle := angle_offset + float(i) * TAU / 8.0
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var candidate := global_position + direction * 3.1
		if not _has_wide_corridor_sight(global_position, candidate):
			continue
		var cover_query := PhysicsRayQueryParameters3D.create(candidate + Vector3(0.0, 1.28, 0.0), threat_eye)
		cover_query.collision_mask = 1
		var covered := not space.intersect_ray(cover_query).is_empty()
		var score := direction.dot(away) * 1.8 + (6.0 if covered else 0.0) + randf() * 0.22
		score -= RoundManager.get_incendiary_danger_at(candidate) * 9.0
		if score > best_score:
			best_score = score
			best_dir = direction
	return _steer_around_obstacles(best_dir)


func _engage_enemy(delta: float) -> void:
	var dist := global_position.distance_to(target_enemy.global_position)

	# Critical HP vs a live enemy at range: sometimes break contact instead of suicide-trading!
	if (
		health <= 26
		and personality != PERSONALITY_RUSHER
		and dist > 8.5
		and _disengage_timer <= 0.0
		and _disengage_check_cd <= 0.0
	):
		_disengage_check_cd = randf_range(0.55, 1.15)
		if randf() < 0.34:
			var away := global_position - target_enemy.global_position
			away.y = 0.0
			if away.length_squared() < 0.01:
				away = -get_look_forward()
			_disengage_dir = _steer_around_obstacles(away.normalized())
			_disengage_timer = randf_range(1.5, 2.6)
			_last_enemy_pos = target_enemy.global_position
			_last_enemy_seen_age = 0.0
			target_enemy = null
			return

	# Tactical Smoke / HE / incendiary / decoy toss at medium-long range
	if _grenade_cooldown <= 0.0 and dist > 12.5 and dist < 25.0 and health > 50 and randf() < 0.025:
		var attack_grenades := ["hegrenade", "molotov" if team == "T" else "incendiary", "decoy"]
		var threw_attack := false
		for gid in attack_grenades:
			if int(weapon_ctrl.grenades.get(gid, 0)) <= 0:
				continue
			_grenade_cooldown = 13.0
			if weapon_ctrl.equip_weapon_by_id(gid):
				weapon_ctrl.fire_cooldown = 0.0
				_look_smoothly_toward(target_enemy.global_position + Vector3(0.0, 2.2, 0.0), 1.0)
				weapon_ctrl.trigger_primary(false, delta)
				threw_attack = true
				break
		if threw_attack:
			return
		if dist > 16.0 and int(weapon_ctrl.grenades.get("smokegrenade", 0)) > 0 and randf() < 0.35:
			_grenade_cooldown = 16.0
			if weapon_ctrl.equip_weapon_by_id("smokegrenade"):
				weapon_ctrl.fire_cooldown = 0.0
				var mid_pt := global_position.lerp(target_enemy.global_position, 0.55) + Vector3(0.0, 1.8, 0.0)
				_look_smoothly_toward(mid_pt, 1.0)
				weapon_ctrl.trigger_primary(false, delta)
				return

	# Ensure combat gun equipped; quick-switch to pistol if primary runs dry in close quarters!
	if _is_utility_weapon(weapon_ctrl.current_weapon_id):
		if not weapon_ctrl.equip_slot(1):
			weapon_ctrl.equip_slot(2)
	else:
		var cr := weapon_ctrl.get_clip_and_reserve()
		if cr.x == 0:
			var cur_slot := int(weapon_ctrl.get_current_spec().get("slot", 1))
			var sec_id := String(weapon_ctrl.slots.get(2, ""))
			if cur_slot == 1 and dist < 14.0 and not sec_id.is_empty() and int(weapon_ctrl.clips.get(sec_id, 0)) > 0:
				weapon_ctrl.equip_slot(2)
			elif cr.y > 0 and not weapon_ctrl.is_reloading:
				weapon_ctrl.start_reload()

	var wid := weapon_ctrl.current_weapon_id
	var is_sniper := wid in ["awp", "scout", "g3sg1", "sg550"]

	if is_sniper and dist > 10.5 and weapon_ctrl.zoom_index < 0 and not weapon_ctrl.is_reloading and weapon_ctrl.fire_cooldown <= 0.15:
		weapon_ctrl.trigger_secondary()

	var aim_height := 1.48 if skill_level >= 2 else 1.26
	if target_enemy.is_crouching:
		aim_height *= 0.64
	var spread_err := float([0.20, 0.11, 0.05, 0.018][clampi(skill_level, 0, 3)])
	var lead := target_enemy.velocity * 0.05 + Vector3(
		sin(Time.get_ticks_msec() * 0.007) * spread_err,
		0.0,
		cos(Time.get_ticks_msec() * 0.006) * spread_err
	)
	var aim_pt := target_enemy.global_position + Vector3(0.0, aim_height, 0.0) + lead

	# YaPB Recoil Compensation: skilled bots pull crosshair down against weapon punch_angles!
	var recoil_comp: float = float([0.20, 0.48, 0.75, 0.94][clampi(skill_level, 0, 3)])
	var punch := weapon_ctrl.punch_angles
	var comp_pt := aim_pt - Vector3(0.0, sin(deg_to_rad(punch.x * 1.35)) * dist * recoil_comp, 0.0)
	var track_spd: float = float([6.0, 9.0, 13.5, 18.5][clampi(skill_level, 0, 3)])
	_look_smoothly_toward(comp_pt, delta * track_spd)

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
			_strafe_timer = randf_range(0.40, 0.82)
			if dist > 7.5 and not weapon_ctrl.is_reloading:
				_burst_stop_timer = randf_range(0.26, 0.48) if not is_sniper else randf_range(0.38, 0.62)
				if skill_level >= 2 and dist > 15.5 and randf() < 0.30:
					_crouch_burst_timer = _burst_stop_timer + 0.18

	var crouch_shoot := _crouch_burst_timer > 0.0
	var strafe_vec := Vector3.ZERO
	if weapon_ctrl.is_reloading or (health < 28 and personality != PERSONALITY_RUSHER):
		# YaPB SeekCover with actual world visibility: reload behind a wall or
		# obstacle when one is reachable, rather than dodging blindly in the open.
		if _cover_check_timer <= 0.0 or _cover_dir.length_squared() < 0.01:
			_cover_dir = _find_cover_direction(target_enemy.global_position)
			_cover_check_timer = randf_range(0.72, 1.18)
		strafe_vec = _cover_dir
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
	var align_req := 0.965 if (dist > 20.0 or is_sniper) else 0.920
	if get_look_forward().dot(to_tgt) > align_req:
		var max_burst := 100
		if dist > 23.0:
			max_burst = 3
		elif dist > 11.5:
			max_burst = 5
		if weapon_ctrl.shots_fired >= max_burst:
			_burst_pause_timer = randf_range(0.17, 0.28)
			return
		weapon_ctrl.trigger_primary(false, delta)


func _is_leading_hostage() -> bool:
	if team != "CT" or RoundManager.map_mode != "cs":
		return false
	for h in RoundManager.hostages:
		var h_npc := h as HostageNPC
		if is_instance_valid(h_npc) and h_npc.is_alive and not h_npc.is_rescued and h_npc.leader == self:
			return true
	return false


func _uses_sniper() -> bool:
	var p_id := String(weapon_ctrl.slots.get(1, ""))
	return p_id in ["awp", "scout", "g3sg1", "sg550"]


func _pick_path_mode() -> int:
	if is_vip or String(weapon_ctrl.slots.get(5, "")) == "c4" or health < 40 or personality == PERSONALITY_CAREFUL:
		return BotNavigator.PATH_SAFE
	if personality == PERSONALITY_RUSHER:
		return BotNavigator.PATH_DIVERSITY
	return BotNavigator.PATH_DIVERSITY if randf() < 0.65 else BotNavigator.PATH_OPTIMAL


func _find_dropped_c4() -> DroppedWeapon:
	for it in RoundManager.dropped_items:
		var dw_v: Variant = it
		if not is_instance_valid(dw_v):
			continue
		var dw := dw_v as DroppedWeapon
		if dw != null and dw.item_id == "c4":
			return dw
	return null


func _find_live_vip() -> CSActor:
	for raw in RoundManager.actors:
		var actor := raw as CSActor
		if is_instance_valid(actor) and actor.is_alive and actor.is_vip:
			return actor
	return null


func _is_assigned_vip_escort() -> bool:
	return RoundManager.map_mode == "as" and team == "CT" and not is_vip and _vip_escort_slot >= 0 and _vip_escort_slot < 3


func _record_vip_route_node(node_idx: int) -> void:
	if not is_vip or RoundManager.map_mode != "as" or node_idx < 0:
		return
	if _vip_route_history.is_empty() or _vip_route_history[_vip_route_history.size() - 1] != node_idx:
		_vip_route_history.append(node_idx)


func _vip_escort_proximity(radius: float) -> Vector2i:
	var escorts: Array[CSBot] = []
	for raw in RoundManager.actors:
		var bot := raw as CSBot
		if is_instance_valid(bot) and bot != self and bot.is_alive and bot.team == "CT" and not bot.is_vip:
			escorts.append(bot)
	escorts.sort_custom(func(a: CSBot, b: CSBot) -> bool: return a.get_instance_id() < b.get_instance_id())
	var close := 0
	var designated := mini(3, escorts.size())
	for i in range(designated):
		if escorts[i].global_position.distance_to(global_position) <= radius:
			close += 1
	return Vector2i(designated, close)


func _update_vip_escape(nav: BotNavigator, gw: Node3D) -> void:
	var zones: Array = gw.get("escape_zones")
	if zones.is_empty():
		# Defensive fallback for third-party/incomplete AS conversions. All shipped
		# AS maps now contain their real func_vip_safetyzone volumes.
		if _node_path.is_empty() or not _has_goal:
			_plan_to_node(nav, nav.pick_roam_node(global_position, team), false, BotNavigator.PATH_SAFE)
		return

	# Do not cross the extraction brush alone while a living escort group is
	# still completing the same stairs/ladders. The bounded wait preserves round
	# momentum and is skipped when combat has left fewer than two escorts alive.
	if _vip_escape_node >= 0 and not bool(gw.call("is_in_escape_zone", global_position)):
		var proximity := _vip_escort_proximity(16.0)
		var near_threshold := global_position.distance_to(_vip_direct_goal) < 9.0
		if proximity.x >= 2 and proximity.y < 2 and near_threshold:
			if _vip_escort_wait_since < 0.0:
				_vip_escort_wait_since = _nav_clock
			if _nav_clock - _vip_escort_wait_since < 15.0:
				_vip_direct_active = false
				_node_path = PackedInt32Array()
				_has_goal = false
				_hold_pos_timer = maxf(_hold_pos_timer, 0.30)
				return
		elif proximity.y >= 2 or not near_threshold:
			_vip_escort_wait_since = -1.0
	if bool(gw.call("is_in_escape_zone", global_position)):
		_vip_direct_active = false
		return
	if _vip_direct_active:
		return

	# Keep a working route instead of restarting it every few seconds. Periodic
	# replans could snap back to a node behind the VIP and undo real progress.
	# Re-evaluate an established path for new incendiary danger; physical blocks
	# are handled by the follower's ordinary stuck recovery and directed links.
	if not _node_path.is_empty() and _has_goal:
		if _vip_route_rethink > 0.0:
			return
		var route_threatened := false
		for route_node in _node_path:
			if RoundManager.get_incendiary_danger_at(nav.get_node_pos(route_node)) > 0.72:
				route_threatened = true
				break
		if not route_threatened:
			_vip_route_rethink = 0.8
			return

	# YaPB's goal node is often on the edge of a large helicopter/vehicle brush.
	# Finish the last metres towards the actual extraction centre when a wide,
	# physical corridor confirms that doing so cannot cross a wall.
	if _node_path.is_empty() and _vip_escape_node >= 0:
		var finish_delta := _vip_direct_goal - global_position
		finish_delta.y = 0.0
		if finish_delta.length() < 13.5 and _has_wide_corridor_sight(global_position, _vip_direct_goal):
			_vip_direct_active = true
			_vip_direct_elapsed = 0.0
			_has_goal = false
			_stuck_timer = 0.0
			return

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() else null
	var best_node := -1
	var best_center := Vector3.ZERO
	var best_cost := 1e12
	for zone_index in range(zones.size()):
		var zone := zones[zone_index] as AABB
		var center := zone.get_center()
		var candidates: Array[int] = []
		var nearest := nav.get_nearest_node(center, null, 7.0)
		if nearest >= 0:
			candidates.append(nearest)
		var authored := nav.pick_goal_node_near(center, 24.0)
		if authored >= 0 and not candidates.has(authored):
			candidates.append(authored)
		var expanded := zone.grow(0.75)
		for goal_node in nav.goal_nodes:
			if not candidates.has(goal_node) and expanded.has_point(nav.get_node_pos(goal_node)):
				candidates.append(goal_node)

		for node_idx in candidates:
			var path := nav.plan_node_path(
				global_position, node_idx, team, BotNavigator.PATH_SAFE, false,
				space, _diversity_seed, _banned_nodes
			)
			if path.is_empty() or path[path.size() - 1] != node_idx:
				continue
			var cost := nav.get_path_tactical_cost(path, team)
			cost += nav.get_node_pos(node_idx).distance_to(center) * 0.35
			# Tiny stable preference difference prevents identical choices when two
			# routes are genuinely equivalent; safety and travel dominate the score.
			cost += float((absi(_diversity_seed) + zone_index * 17) % 11) * 0.08
			if cost < best_cost:
				best_cost = cost
				best_node = node_idx
				best_center = center

	if best_node >= 0:
		_vip_escape_node = best_node
		_vip_direct_goal = best_center
		_vip_direct_elapsed = 0.0
		_vip_route_rethink = randf_range(2.4, 3.8)
		_plan_to_node(nav, best_node, false, BotNavigator.PATH_SAFE)
		return

	# No complete candidate path: retain motion and retry from the next node
	# instead of freezing forever. The direct-approach/stuck systems can replan.
	var nearest_zone := zones[0] as AABB
	var nearest_distance := global_position.distance_to(nearest_zone.get_center())
	for raw_zone in zones:
		var zone := raw_zone as AABB
		var distance := global_position.distance_to(zone.get_center())
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_zone = zone
	_vip_direct_goal = nearest_zone.get_center()
	_plan_to_world_pos(nav, _vip_direct_goal, false, BotNavigator.PATH_SAFE)
	_vip_escape_node = _goal_node_idx
	_vip_route_rethink = 1.0


func _follow_vip_direct_path(delta: float) -> void:
	if not _vip_direct_active:
		return
	_vip_direct_elapsed += delta
	var raw_dir := _vip_direct_goal - global_position
	raw_dir.y = 0.0
	if raw_dir.length() < 0.38:
		_vip_direct_active = false
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		return
	raw_dir = raw_dir.normalized()
	if RoundManager.get_incendiary_danger_at(global_position + raw_dir * 1.1) > 0.78:
		_vip_direct_active = false
		_vip_escape_node = -1
		_vip_route_rethink = 0.0
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		return
	var move_dir := _steer_around_obstacles(raw_dir)
	_smoothed_move_dir = _blend_move_dir(_smoothed_move_dir, move_dir, delta * 10.0)
	_look_smoothly_toward(global_position + raw_dir * 5.0 + Vector3(0.0, 1.4, 0.0), delta * 7.0)
	apply_goldsrc_movement(_smoothed_move_dir, false, false, false, delta)
	var moved := global_position.distance_to(_last_pos)
	_stuck_timer = _stuck_timer + delta if moved < 0.35 * delta else maxf(0.0, _stuck_timer - delta * 2.0)
	_last_pos = global_position
	if _vip_direct_elapsed > 5.5 or _stuck_timer > 0.75:
		_vip_direct_active = false
		_vip_escape_node = -1
		_vip_route_rethink = 0.0
		_stuck_timer = 0.0


func _has_vip_escort_floor_path(from_p: Vector3, to_p: Vector3) -> bool:
	if absf(to_p.y - from_p.y) > 1.10:
		return false
	var flat := to_p - from_p
	flat.y = 0.0
	var distance := flat.length()
	if distance < 0.05:
		return true
	var steps := maxi(1, int(ceil(distance / 0.65)))
	var previous_y := from_p.y
	var space := get_world_3d().direct_space_state
	for i in range(1, steps + 1):
		var probe := from_p.lerp(to_p, float(i) / float(steps))
		var query := PhysicsRayQueryParameters3D.create(probe + Vector3(0.0, 0.60, 0.0), probe - Vector3(0.0, 1.40, 0.0))
		query.collision_mask = 1
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var floor_y := (hit["position"] as Vector3).y
		var normal := hit.get("normal", Vector3.UP) as Vector3
		if normal.y < 0.45 or absf(floor_y - previous_y) > 0.62:
			return false
		previous_y = floor_y
	return true


func _start_vip_escort_direct(goal: Vector3) -> void:
	_vip_escort_direct_goal = goal
	_vip_breadcrumb_active = false
	_vip_escort_direct_elapsed = 0.0
	_vip_escort_direct_active = true
	_node_path = PackedInt32Array()
	_has_goal = false
	_hold_pos_timer = 0.0
	_stuck_timer = 0.0


func _update_vip_escort_weapon(vip: CSActor) -> void:
	if weapon_ctrl.is_reloading:
		return
	var catch_up := global_position.distance_to(vip.global_position) > 4.5 and _sound_investigate_timer <= 0.0
	if catch_up:
		if weapon_ctrl.current_weapon_id != "knife":
			weapon_ctrl.equip_slot(3)
	elif _is_utility_weapon(weapon_ctrl.current_weapon_id):
		if not weapon_ctrl.equip_slot(1):
			weapon_ctrl.equip_slot(2)


func _follow_vip_escort_direct(delta: float) -> void:
	var vip := _find_live_vip()
	if not is_instance_valid(vip):
		_vip_escort_direct_active = false
		return
	_update_vip_escort_weapon(vip)
	_vip_escort_direct_elapsed += delta
	var raw_dir := _vip_escort_direct_goal - global_position
	raw_dir.y = 0.0
	var distance := raw_dir.length()
	if distance < 0.82:
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return
	raw_dir /= maxf(distance, 0.001)
	var move_dir := _steer_around_obstacles(raw_dir)
	_smoothed_move_dir = _blend_move_dir(_smoothed_move_dir, move_dir, delta * 12.0)
	if not _has_vip_escort_floor_path(global_position, global_position + _smoothed_move_dir * 1.10):
		_vip_escort_direct_active = false
		_vip_escort_repath = 0.65
		_stuck_timer = 0.0
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return
	_look_smoothly_toward(vip.global_position + Vector3(0.0, 1.35, 0.0), delta * 8.0)
	apply_goldsrc_movement(_smoothed_move_dir, false, false, false, delta)
	var moved := global_position.distance_to(_last_pos)
	_stuck_timer = _stuck_timer + delta if moved < 0.35 * delta else maxf(0.0, _stuck_timer - delta * 2.0)
	_last_pos = global_position
	# A moving VIP can turn a previously open formation slot into a wall-corner
	# shortcut. Return to A* instead of pushing indefinitely against geometry.
	if _vip_escort_direct_elapsed > 3.0 or _stuck_timer > 0.55 or distance > 16.0:
		_vip_escort_direct_active = false
		_vip_escort_repath = 0.65
		_stuck_timer = 0.0


func _follow_vip_breadcrumbs(nav: BotNavigator, vip: CSActor) -> bool:
	var vip_bot := vip as CSBot
	if vip_bot == null:
		return false
	var route := PackedInt32Array()
	for node_idx in vip_bot._vip_route_history:
		if route.is_empty() or route[route.size() - 1] != node_idx:
			route.append(node_idx)
	for node_idx in vip_bot._node_path:
		if route.is_empty() or route[route.size() - 1] != node_idx:
			route.append(node_idx)
	if route.is_empty():
		return false

	if _vip_breadcrumb_active:
		if not _node_path.is_empty() and route.find(_node_path[0]) >= 0:
			return true
		_node_path = PackedInt32Array()
		_has_goal = false
	_vip_breadcrumb_active = false

	# Merge with the closest few points of the VIP's actual route, then retain
	# its suffix. Only this short merge needs a fresh A* search.
	var candidates: Array[int] = []
	for i in range(route.size()):
		candidates.append(i)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		var da := global_position.distance_squared_to(nav.get_node_pos(route[a]))
		var db := global_position.distance_squared_to(nav.get_node_pos(route[b]))
		return da < db
	)
	var space := get_world_3d().direct_space_state
	for candidate_i in range(mini(4, candidates.size())):
		var route_idx := candidates[candidate_i]
		var merge_node := route[route_idx]
		var prefix := nav.plan_node_path(global_position, merge_node, team, BotNavigator.PATH_FAST, false, space, _diversity_seed, _banned_nodes)
		if prefix.is_empty() or prefix[prefix.size() - 1] != merge_node:
			continue
		var combined := PackedInt32Array()
		combined.append_array(prefix)
		for j in range(route_idx + 1, route.size()):
			if combined.is_empty() or combined[combined.size() - 1] != route[j]:
				combined.append(route[j])
		if combined.is_empty():
			continue
		_node_path = combined
		_goal_node_idx = combined[combined.size() - 1]
		_goal_pos = vip.global_position
		_has_goal = true
		_prev_node_idx = nav.get_nearest_node(global_position, space, 3.6, true)
		_advance_to_node_entry(nav, _node_path[0])
		_vip_breadcrumb_active = true
		return true
	return false


func _update_as_squad_objective(nav: BotNavigator, gw: Node3D) -> bool:
	var vip := _find_live_vip()
	if not is_instance_valid(vip):
		return false
	var zones: Array = gw.get("escape_zones")

	if team == "CT":
		var escorts: Array[CSBot] = []
		for raw in RoundManager.actors:
			var bot := raw as CSBot
			if is_instance_valid(bot) and bot.is_alive and bot.team == "CT" and not bot.is_vip:
				escorts.append(bot)
		escorts.sort_custom(func(a: CSBot, b: CSBot) -> bool: return a.get_instance_id() < b.get_instance_id())
		_vip_escort_slot = escorts.find(self)
		if _vip_escort_slot >= 0 and _vip_escort_slot < mini(3, escorts.size()):
			_hostage_direct_active = false
			if _camp_timer > 0.0:
				_release_camp_spot()
			var forward := vip.get_look_forward()
			forward.y = 0.0
			if forward.length_squared() < 0.01:
				forward = Vector3.FORWARD
			forward = forward.normalized()
			var right := forward.cross(Vector3.UP).normalized()
			var offsets: Array[Vector3] = [
				-forward * 2.3 - right * 1.7,
				-forward * 2.7 + right * 1.7,
				forward * 3.8,
			]
			var formation_pos := vip.global_position + offsets[_vip_escort_slot]
			var formation_distance := global_position.distance_to(formation_pos)
			# Nearby escorts track the moving formation directly. This avoids
			# repeatedly snapping back to an old node while the VIP advances.
			if _vip_escort_repath <= 0.0 and formation_distance < 12.0 and _has_wide_corridor_sight(global_position, formation_pos) and _has_vip_escort_floor_path(global_position, formation_pos):
				if not _vip_escort_direct_active or _vip_escort_direct_goal.distance_to(formation_pos) > 0.45:
					_start_vip_escort_direct(formation_pos)
				else:
					_vip_escort_direct_goal = formation_pos
			else:
				_vip_escort_direct_active = false
				# Reuse the VIP's actual directed route before considering an
				# independent pursuit. This preserves deck/ladder transitions.
				var following_breadcrumbs := _follow_vip_breadcrumbs(nav, vip)
				if not following_breadcrumbs:
					var vip_goal_node := nav.get_nearest_node(vip.global_position, null, 6.5)
					if vip_goal_node >= 0 and (_node_path.is_empty() or not _has_goal or (_vip_route_rethink <= 0.0 and vip_goal_node != _goal_node_idx)):
						_plan_to_node(nav, vip_goal_node, false, BotNavigator.PATH_FAST)
						_goal_pos = vip.global_position
						_vip_route_rethink = 8.0
					if not _has_goal:
						_plan_to_world_pos(nav, formation_pos, false, BotNavigator.PATH_SAFE)
			return true
		_vip_escort_direct_active = false
		_vip_breadcrumb_active = false

		# Additional CTs move ahead and hold extraction approaches instead of
		# stacking in one formation. They remain available for normal combat.
		if not zones.is_empty() and (_node_path.is_empty() or not _has_goal):
			var zone := zones[absi(_diversity_seed) % zones.size()] as AABB
			var advance := nav.pick_camp_or_sniper_node(zone.get_center(), "CT", _uses_sniper(), 24.0, self)
			if advance >= 0:
				_plan_to_node(nav, advance, false, _pick_path_mode())
			else:
				_plan_to_world_pos(nav, zone.get_center(), false, BotNavigator.PATH_SAFE)
		return true

	if team == "T":
		# Hunt only last actually observed contact; never read the VIP's hidden
		# live position. Otherwise split between spawn pressure and extraction
		# ambushes using static map knowledge available to every player.
		if _last_enemy_seen_age < 4.5 and health >= 42:
			if _node_path.is_empty() or _goal_pos.distance_to(_last_enemy_pos) > 3.5:
				_plan_to_world_pos(nav, _last_enemy_pos, false, BotNavigator.PATH_OPTIMAL)
			return true
		if _node_path.is_empty() or not _has_goal:
			var ambush := personality == PERSONALITY_CAREFUL or _uses_sniper() or absi(_diversity_seed) % 3 == 0
			if ambush and not zones.is_empty():
				var zone := zones[absi(_diversity_seed) % zones.size()] as AABB
				var nest := nav.pick_camp_or_sniper_node(zone.get_center(), "T", _uses_sniper(), 30.0, self)
				if nest >= 0:
					_plan_to_node(nav, nest, false, _pick_path_mode())
				else:
					_plan_to_world_pos(nav, zone.get_center(), false, _pick_path_mode())
			else:
				var raw_map: Dictionary = gw.get("map_data")
				var spawn_list: Array = raw_map.get("vip_spawns", [])
				if spawn_list.is_empty():
					spawn_list = raw_map.get("ct_spawns", [])
				if not spawn_list.is_empty():
					var entry: Dictionary = spawn_list[absi(_diversity_seed) % spawn_list.size()]
					var p: Array = entry.get("pos", [0.0, 0.0, 0.0])
					_plan_to_world_pos(nav, Vector3(float(p[0]), float(p[1]), float(p[2])), false, _pick_path_mode())
		return true
	return false


func _clear_hostage_direct() -> void:
	_hostage_direct_active = false
	_hostage_direct_target = null
	_hostage_direct_elapsed = 0.0
	_hostage_direct_stuck = 0.0


func _start_hostage_direct(mode: int, target: HostageNPC, goal: Vector3) -> void:
	_hostage_direct_mode = mode
	_hostage_direct_target = target
	_hostage_direct_goal = goal
	_hostage_direct_elapsed = 0.0
	_hostage_direct_stuck = 0.0
	_hostage_direct_active = true
	_node_path = PackedInt32Array()
	_has_goal = false
	_hold_pos_timer = 0.0
	_stuck_timer = 0.0


func _follow_hostage_direct(delta: float) -> void:
	if not _hostage_direct_active:
		return
	_hostage_direct_elapsed += delta
	var target := _hostage_direct_target
	if _hostage_direct_mode in [HOSTAGE_DIRECT_PICKUP, HOSTAGE_DIRECT_REGROUP]:
		if not is_instance_valid(target) or not target.is_alive or target.is_rescued:
			_clear_hostage_direct()
			return
		if _hostage_direct_mode == HOSTAGE_DIRECT_PICKUP and target.leader != null and target.leader != self:
			_clear_hostage_direct()
			return
		_hostage_direct_goal = target.global_position
	elif not _is_leading_hostage():
		_clear_hostage_direct()
		return

	var raw_dir := _hostage_direct_goal - global_position
	raw_dir.y = 0.0
	var distance := raw_dir.length()
	if _hostage_direct_mode == HOSTAGE_DIRECT_PICKUP and distance < 2.12:
		target.interact(self)
		_hostage_target = target
		_clear_hostage_direct()
		_node_path = PackedInt32Array()
		_has_goal = false
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return
	if _hostage_direct_mode == HOSTAGE_DIRECT_REGROUP and distance < 2.35:
		_clear_hostage_direct()
		_hostage_repath = 0.0
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return
	if _hostage_direct_mode == HOSTAGE_DIRECT_RESCUE and distance < 0.72:
		_clear_hostage_direct()
		_hold_pos_timer = 0.26
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return

	raw_dir /= maxf(distance, 0.001)
	if RoundManager.get_incendiary_danger_at(global_position + raw_dir * 1.1) > 0.82:
		_clear_hostage_direct()
		_hostage_repath = 0.0
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		return
	var move_dir := _steer_around_obstacles(raw_dir)
	_smoothed_move_dir = _blend_move_dir(_smoothed_move_dir, move_dir, delta * 12.0)
	_look_smoothly_toward(global_position + raw_dir * 4.0 + Vector3(0.0, 1.35, 0.0), delta * 8.0)
	apply_goldsrc_movement(_smoothed_move_dir, false, false, false, delta)
	var moved := global_position.distance_to(_last_pos)
	_hostage_direct_stuck = _hostage_direct_stuck + delta if moved < 0.32 * delta else maxf(0.0, _hostage_direct_stuck - delta * 2.0)
	_last_pos = global_position
	if _hostage_direct_elapsed > 5.0 or _hostage_direct_stuck > 0.58 or distance > 15.5:
		_clear_hostage_direct()
		_hostage_repath = 0.0


func _led_hostages() -> Array[HostageNPC]:
	var result: Array[HostageNPC] = []
	if team != "CT" or RoundManager.map_mode != "cs":
		return result
	for raw in RoundManager.hostages:
		var hostage := raw as HostageNPC
		if is_instance_valid(hostage) and hostage.is_alive and not hostage.is_rescued and hostage.leader == self:
			result.append(hostage)
	return result


func _hostage_claimed_by_other(candidate: HostageNPC) -> bool:
	for raw in RoundManager.actors:
		var bot := raw as CSBot
		if is_instance_valid(bot) and bot != self and bot.is_alive and bot.team == "CT" and bot._hostage_target == candidate:
			return true
	return false


func _best_hostage_rescue(nav: BotNavigator, gw: Node3D) -> Dictionary:
	var zones: Array = gw.get("rescue_zones")
	if zones.is_empty():
		return {}
	var space := get_world_3d().direct_space_state
	var best: Dictionary = {}
	var best_cost := 1e12
	for zone_idx in range(zones.size()):
		var zone := zones[zone_idx] as AABB
		var center := zone.get_center()
		var candidates: Array[int] = []
		var nearest := nav.get_nearest_node(center, space, 8.0)
		if nearest >= 0:
			candidates.append(nearest)
		for node_idx in nav.rescue_nodes:
			if not candidates.has(node_idx) and nav.get_node_pos(node_idx).distance_to(center) < 28.0:
				candidates.append(node_idx)
		# Rescue flags can lie below a trigger or omit a ramp landing entirely.
		# Any physically intersecting node is a legitimate safe-route endpoint.
		for node_idx in range(nav.waypoints.size()):
			if not candidates.has(node_idx) and GameWorld.capsule_overlaps_zone(nav.get_node_pos(node_idx), 1.90, 0.36, zone):
				candidates.append(node_idx)
		for node_idx in candidates:
			var node_pos := nav.get_node_pos(node_idx)
			var node_in_zone := GameWorld.capsule_overlaps_zone(node_pos, 1.90, 0.36, zone)
			var direct_goal := node_pos if node_in_zone else center
			if not node_in_zone:
				var flat := Vector2(node_pos.x - center.x, node_pos.z - center.z).length()
				if flat > 14.5 or not _has_wide_corridor_sight(node_pos, center):
					continue
			var path := nav.plan_node_path(global_position, node_idx, team, BotNavigator.PATH_SAFE, true, space, _diversity_seed, _banned_nodes, false)
			if path.is_empty() or path[path.size() - 1] != node_idx:
				continue
			var cost := nav.get_path_tactical_cost(path, team)
			cost += node_pos.distance_to(center) * 0.22
			if zone_idx == _hostage_rescue_zone_idx:
				cost -= 1.5
			if cost < best_cost:
				best_cost = cost
				best = {"zone": zone_idx, "node": node_idx, "goal": direct_goal}
	return best


func _update_ct_hostage_objective(nav: BotNavigator, gw: Node3D, live_hostages: Array[HostageNPC]) -> bool:
	var led := _led_hostages()
	if not led.is_empty():
		_hostage_target = led[0]
		var lagging: HostageNPC = led[0]
		var lagging_distance := -1.0
		for hostage in led:
			var distance := global_position.distance_to(hostage.global_position)
			if distance > lagging_distance:
				lagging = hostage
				lagging_distance = distance
		# Never finish the escort alone. Return to a blocked or distant hostage,
		# then resume the rescue with a fresh follower path.
		if lagging_distance > 7.0 or (lagging.needs_navigation_help() and lagging_distance > 2.8):
			if _hostage_direct_mode != HOSTAGE_DIRECT_REGROUP:
				_clear_hostage_direct()
			if lagging_distance < 6.5 and _has_wide_corridor_sight(global_position, lagging.global_position):
				if not _hostage_direct_active or _hostage_direct_target != lagging:
					_start_hostage_direct(HOSTAGE_DIRECT_REGROUP, lagging, lagging.global_position)
			elif _hostage_repath <= 0.0 and (_node_path.is_empty() or not _has_goal or _goal_pos.distance_to(lagging.global_position) > 2.0):
				_clear_hostage_direct()
				_plan_to_world_pos(nav, lagging.global_position, false, BotNavigator.PATH_FAST)
				_hostage_repath = 0.65
			return true

		if not _hostage_direct_active and bool(gw.call("is_in_rescue_zone", global_position + Vector3(0.0, 0.95, 0.0))):
			_node_path = PackedInt32Array()
			_has_goal = false
			_hold_pos_timer = maxf(_hold_pos_timer, 0.28)
			return true

		# Keep a valid safe route instead of solving every rescue candidate on
		# each 0.12–0.22 s think tick. Lagging followers are handled above and
		# still interrupt the route immediately when they need help.
		if not _hostage_direct_active and _hostage_rescue_zone_idx >= 0 and _has_goal and not _node_path.is_empty():
			return true

		var best := _best_hostage_rescue(nav, gw)
		if best.is_empty():
			# Third-party incomplete graphs retain motion while safer candidates
			# are re-evaluated instead of freezing beside the followers.
			if _node_path.is_empty():
				var zones: Array = gw.get("rescue_zones")
				if not zones.is_empty():
					_plan_to_world_pos(nav, (zones[0] as AABB).get_center(), true, BotNavigator.PATH_SAFE)
			return true
		var zone_idx := int(best["zone"])
		var rescue_goal := best["goal"] as Vector3
		var rescue_distance := global_position.distance_to(rescue_goal)
		if rescue_distance < 14.5 and _has_wide_corridor_sight(global_position, rescue_goal):
			if not _hostage_direct_active or _hostage_direct_mode != HOSTAGE_DIRECT_RESCUE or _hostage_direct_goal.distance_to(rescue_goal) > 0.45:
				_hostage_rescue_zone_idx = zone_idx
				_start_hostage_direct(HOSTAGE_DIRECT_RESCUE, null, rescue_goal)
			return true
		_clear_hostage_direct()
		if _node_path.is_empty() or not _has_goal or zone_idx != _hostage_rescue_zone_idx:
			_hostage_rescue_zone_idx = zone_idx
			_plan_to_node(nav, int(best["node"]), true, BotNavigator.PATH_SAFE)
		return true

	if _hostage_direct_mode != HOSTAGE_DIRECT_PICKUP:
		_clear_hostage_direct()
	var best_free: HostageNPC = null
	var best_free_distance := 1e12
	for hostage in live_hostages:
		if hostage.leader != null or _hostage_claimed_by_other(hostage):
			continue
		var distance := global_position.distance_to(hostage.global_position)
		if distance < best_free_distance:
			best_free_distance = distance
			best_free = hostage
	if is_instance_valid(best_free):
		if _hostage_target != best_free:
			_clear_hostage_direct()
			_hostage_rescue_zone_idx = -1
		_hostage_target = best_free
		if best_free_distance < 2.12:
			best_free.interact(self)
			_clear_hostage_direct()
			_node_path = PackedInt32Array()
			_has_goal = false
		elif best_free_distance < 6.5 and _has_wide_corridor_sight(global_position, best_free.global_position):
			if not _hostage_direct_active or _hostage_direct_mode != HOSTAGE_DIRECT_PICKUP or _hostage_direct_target != best_free:
				_start_hostage_direct(HOSTAGE_DIRECT_PICKUP, best_free, best_free.global_position)
		else:
			_clear_hostage_direct()
			if _hostage_repath <= 0.0 and (_node_path.is_empty() or not _has_goal or _goal_pos.distance_to(best_free.global_position) > 1.75):
				_plan_to_world_pos(nav, best_free.global_position, false, BotNavigator.PATH_FAST)
				_hostage_repath = 0.65
		return true

	_hostage_target = null
	_clear_hostage_direct()
	# Other CTs already lead every remaining hostage. Secure a real rescue
	# brush rather than crowding a follower or waiting beside an untouched NPC.
	var zones: Array = gw.get("rescue_zones")
	if not zones.is_empty():
		var nearest_zone := zones[0] as AABB
		var nearest_distance := global_position.distance_to(nearest_zone.get_center())
		for raw_zone in zones:
			var zone := raw_zone as AABB
			var distance := global_position.distance_to(zone.get_center())
			if distance < nearest_distance:
				nearest_zone = zone
				nearest_distance = distance
		if not bool(gw.call("is_in_rescue_zone", global_position + Vector3(0.0, 0.95, 0.0))) and (_node_path.is_empty() or not _has_goal):
			_plan_to_world_pos(nav, nearest_zone.get_center(), false, BotNavigator.PATH_SAFE)
		return true
	return false


func _update_tactical_objective() -> void:
	_update_bomb_escape_state()

	# Priority 0: sprint outside the C4 lethal ring — saving the loadout beats a lost round!
	if _bomb_escape_active:
		_update_bomb_flee_path()
		return

	# Never overwrite or cancel an active open-corridor escape maneuver!
	if _escape_timer > 0.0:
		return
	if not is_instance_valid(RoundManager.game_world):
		return
	var gw := RoundManager.game_world
	var nav: BotNavigator = gw.get("bot_navigator")
	if nav == null or nav.waypoints.is_empty():
		return

	# Expire old temporary node bans on the gameplay clock. Real wall time runs
	# far slower than fixed-step QA and is not deterministic during frame stalls.
	if not _banned_nodes.is_empty():
		var expired: Array[int] = []
		for k in _banned_nodes.keys():
			if float(_banned_nodes[k]) <= _nav_clock:
				expired.append(int(k))
		for ek in expired:
			_banned_nodes.erase(ek)

	# Radio order follow (the VIP never abandons extraction to become a follower)
	if not is_vip and not is_instance_valid(RoundManager.planted_c4) and is_instance_valid(_follow_target) and bool(_follow_target.get("is_alive")):
		if global_position.distance_to(_follow_target.global_position) > 3.8:
			_plan_to_world_pos(nav, _follow_target.global_position, false)
		return

	# Weapon-share pickup task: fetch a teammate's gifted primary before rolling out!
	if is_instance_valid(_pending_share_drop) and not is_instance_valid(RoundManager.planted_c4):
		var gift_pos: Vector3 = _pending_share_drop.global_position
		if global_position.distance_to(gift_pos) <= 1.65:
			var gift_take := _pending_share_drop
			_pending_share_drop = null
			try_pickup_dropped(gift_take)
		else:
			if _node_path.is_empty() or not _has_goal or _goal_pos.distance_to(gift_pos) > 1.4:
				_plan_to_world_pos(nav, gift_pos, false, BotNavigator.PATH_FAST)
			return
	elif _pending_share_drop != null:
		_pending_share_drop = null

	# Recover the dropped bomb (Terrorists): the round is lost unless someone
	# fetches the C4 backpack — the closest free T commits to the pickup.
	if team == "T" and String(weapon_ctrl.slots.get(5, "")).is_empty():
		if not is_instance_valid(RoundManager.planted_c4):
			var drop_c4 := _find_dropped_c4()
			if drop_c4 != null:
				var dc4_pos := drop_c4.global_position
				var my_d := global_position.distance_to(dc4_pos)
				var nearest := true
				for m in RoundManager.actors:
					var mate := m as CSActor
					if mate == null or mate == self or not mate.is_alive:
						continue
					if mate.team != "T":
						continue
					if mate.is_human:
						continue
					var mate_d := mate.global_position.distance_to(dc4_pos)
					if mate_d < my_d - 0.01 or (absf(mate_d-my_d) <= 0.01 and mate.get_instance_id() < get_instance_id()):
						nearest = false
						break
				if nearest:
					if my_d <= 1.6:
						try_pickup_dropped(drop_c4)
					elif _node_path.is_empty() or not _has_goal or _goal_pos.distance_to(dc4_pos) > 1.5:
						_plan_to_world_pos(nav, dc4_pos, false, BotNavigator.PATH_FAST)
					return

	# Extraction outranks camping/hold commands for the VIP itself.
	if is_vip and RoundManager.map_mode == "as":
		_update_vip_escape(nav, gw)
		return

	if (_hold_pos_timer > 0.0 or _camp_timer > 0.0) and not is_instance_valid(RoundManager.planted_c4):
		return

	# One reachable CT takes the keypad; the rest hold separate graph positions.
	if is_instance_valid(RoundManager.planted_c4):
		var bomb := RoundManager.planted_c4 as PlantedC4
		_hold_pos_timer = 0.0
		_camp_timer = 0.0
		var epoch := bomb.get_instance_id()
		var selected := BombSquad.elect_defuser(bomb, RoundManager.actors, nav) if team == "CT" else null
		var role := "defuse" if selected == self else ("cover" if team == "CT" else "guard")
		if _bomb_role_epoch != epoch or bomb_role != role:
			_release_camp_spot()
			_bomb_role_node = -1
			_has_goal = false
			_node_path.clear()
			_bomb_role_epoch = epoch
		bomb_role = role
		if role == "defuse":
			if not _has_goal or _node_path.is_empty() or _goal_pos.distance_to(bomb.global_position) > 2.4:
				_plan_to_world_pos(nav, bomb.global_position, false, BotNavigator.PATH_FAST)
		else:
			if _bomb_role_node >= 0 and _banned_nodes.has(_bomb_role_node):
				_release_camp_spot()
				_bomb_role_node = -1
			if _bomb_role_node < 0:
				_bomb_role_node = BombSquad.objective_node(self, bomb.global_position, nav, RoundManager.actors)
				if _bomb_role_node >= 0:
					nav.claim_node(_bomb_role_node, self)
					_camping_node_idx = _bomb_role_node
			if _bomb_role_node >= 0 and (not _has_goal or _node_path.is_empty()) and global_position.distance_to(nav.get_node_pos(_bomb_role_node)) > 1.3:
				_plan_to_node(nav, _bomb_role_node, false, BotNavigator.PATH_SAFE)
		return
	bomb_role = "none"
	_bomb_role_node = -1

	# Assassination squad roles: CT formation/advance escort, T hunt/ambush.
	if RoundManager.map_mode == "as" and _update_as_squad_objective(nav, gw):
		return

	# Bomb Carrier T -> head to a YaPB Goal node inside Bombsite A or B!
	if team == "T" and String(weapon_ctrl.slots.get(5, "")) == "c4":
		var bsites: Array = gw.get("bombsites")
		if not bsites.is_empty() and (_node_path.is_empty() or not _has_goal):
			var site_aabb: AABB = bsites[absi(_diversity_seed) % bsites.size()]
			var g_bomb := nav.pick_goal_node_near(site_aabb.get_center(), 14.0)
			_plan_to_node(nav, g_bomb, false, BotNavigator.PATH_SAFE)
		return

	# Two nearby T bots support the carrier; other Ts keep independent flank routes.
	if team == "T" and RoundManager.map_mode == "de":
		var support := BombSquad.escort_slot(self, RoundManager.actors)
		if not support.is_empty():
			bomb_role = "escort"
			var carrier := support.carrier as CSActor
			if global_position.distance_to(carrier.global_position) > 5.0 and (_node_path.is_empty() or _goal_pos.distance_to(carrier.global_position) > 4.0):
				_plan_to_world_pos(nav, carrier.global_position, false, BotNavigator.PATH_SAFE)
			return

	# Hostage Rescue Mode (cs_*)
	if RoundManager.map_mode == "cs":
		var live_hostages: Array[HostageNPC] = []
		for h in RoundManager.hostages:
			var h_npc := h as HostageNPC
			if is_instance_valid(h_npc) and h_npc.is_alive and not h_npc.is_rescued:
				live_hostages.append(h_npc)

		if team == "CT" and not live_hostages.is_empty():
			if _update_ct_hostage_objective(nav, gw, live_hostages):
				return
		elif team == "T" and not live_hostages.is_empty():
			if (_node_path.is_empty() or not _has_goal) and (personality == PERSONALITY_CAREFUL or _uses_sniper() or randf() < 0.45):
				var guard_h: HostageNPC = live_hostages[randi() % live_hostages.size()]
				var camp_h := nav.pick_camp_or_sniper_node(guard_h.global_position, "T", _uses_sniper(), 26.0, self)
				if camp_h >= 0:
					_plan_to_node(nav, camp_h, false, _pick_path_mode())
					return

	# Pursue recent enemy contact or heard gunfire/footsteps (YaPB TaskId::Hunt)!
	if _last_enemy_seen_age < 4.5 and health >= 42 and personality != PERSONALITY_CAREFUL:
		if _node_path.is_empty() or _goal_pos.distance_to(_last_enemy_pos) > 4.0:
			_plan_to_world_pos(nav, _last_enemy_pos, false, BotNavigator.PATH_OPTIMAL)
		return
	if _sound_investigate_timer > 0.4 and (_node_path.is_empty() or _goal_pos.distance_to(_sound_investigate_pos) > 4.5):
		_plan_to_world_pos(nav, _sound_investigate_pos, false, BotNavigator.PATH_OPTIMAL)
		return

	if RoundManager.map_mode == "dm":
		if _node_path.is_empty() or not _has_goal:
			_plan_to_node(nav, nav.pick_roam_node(global_position, team), false, BotNavigator.PATH_FAST)
		return

	# DE Mode CT Bombsite Defense & Sniper Nest Selection + T Split-Push!
	if _node_path.is_empty() or not _has_goal:
		var bsites2: Array = gw.get("bombsites")
		if _uses_sniper() and _camp_cooldown <= 0.0 and randf() < 0.65:
			var snp_idx := nav.pick_camp_or_sniper_node(global_position, team, true, 65.0, self)
			if snp_idx >= 0:
				_plan_to_node(nav, snp_idx, false, BotNavigator.PATH_SAFE)
				return
		if not bsites2.is_empty():
			var s_aabb: AABB = bsites2[randi() % bsites2.size()]
			if team == "CT" and _camp_cooldown <= 0.0 and randf() < 0.58:
				var def_camp := nav.pick_camp_or_sniper_node(s_aabb.get_center(), "CT", _uses_sniper(), 22.0, self)
				if def_camp >= 0:
					_plan_to_node(nav, def_camp, false, _pick_path_mode())
					return
			var g_site := nav.pick_goal_node_near(s_aabb.get_center(), 16.0)
			if g_site >= 0 and randf() < 0.72:
				_plan_to_node(nav, g_site, false, _pick_path_mode())
				return
		var roam_idx := nav.pick_roam_node(global_position, team)
		_plan_to_node(nav, roam_idx, false, _pick_path_mode())


func _plan_to_world_pos(nav: BotNavigator, dest: Vector3, hostage_safe: bool, mode: int = -1) -> void:
	var g_idx := nav.get_nearest_node(dest, null, 6.5)
	if g_idx >= 0:
		_plan_to_node(nav, g_idx, hostage_safe, mode if mode >= 0 else _pick_path_mode())
		_goal_pos = dest


func _plan_to_node(nav: BotNavigator, goal_idx: int, hostage_safe: bool, mode: int = -1) -> void:
	if goal_idx < 0 or goal_idx >= nav.waypoints.size():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if (is_inside_tree() and get_world_3d()) else null
	var use_mode: int = mode if mode >= 0 else _pick_path_mode()
	_goal_node_idx = goal_idx
	_goal_pos = nav.get_node_pos(goal_idx)
	_has_goal = true
	_node_path = nav.plan_node_path(global_position, goal_idx, team, use_mode, hostage_safe, space, _diversity_seed, _banned_nodes)
	_prev_node_idx = nav.get_nearest_node(global_position, space, 3.6, true)
	if not _node_path.is_empty():
		_advance_to_node_entry(nav, _node_path[0])


func _advance_to_node_entry(nav: BotNavigator, next_idx: int) -> void:
	_cur_node_elapsed = 0.0
	# Extraction routes favour reproducible waypoint centres over roam jitter.
	if is_vip:
		_cur_node_offset = Vector3.ZERO
		return
	var fl := nav.get_node_flags(next_idx)
	var rad := nav.get_node_radius(next_idx)
	var lnk := nav.get_link_info(_prev_node_idx, next_idx)
	var is_jump_lnk: bool = lnk.size() >= 2 and (int(lnk[1]) & BotNavigator.LINK_JUMP) != 0
	# YaPB SetPathOrigin: ONLY apply gentle wander offset in wide open areas, NEVER on narrow/jump/crouch/ladder nodes!
	if not is_jump_lnk and (fl & BotNavigator.ACTION_FLAGS) == 0 and rad >= 0.55:
		var max_r := minf(rad * 0.35, 0.42)
		var ang := randf() * TAU
		_cur_node_offset = Vector3(cos(ang) * max_r, 0.0, sin(ang) * max_r)
	else:
		_cur_node_offset = Vector3.ZERO


func _follow_navigation_path(delta: float) -> void:
	if _jump_cooldown > 0.0:
		_jump_cooldown = maxf(0.0, _jump_cooldown - delta)
	if _vent_crouch_timer > 0.0:
		_vent_crouch_timer = maxf(0.0, _vent_crouch_timer - delta)
	if _rollout_delay > 0.0 and not RoundManager.is_movement_frozen():
		_rollout_delay = maxf(0.0, _rollout_delay - delta)
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return

	if not is_instance_valid(RoundManager.game_world):
		return
	var nav: BotNavigator = RoundManager.game_world.get("bot_navigator")
	if nav == null:
		return

	# Active open-corridor unstick maneuver
	if _escape_timer > 0.0:
		_escape_timer -= delta
		var esc_raw := _steer_around_obstacles(_escape_dir)
		_smoothed_move_dir = _blend_move_dir(_smoothed_move_dir, esc_raw, delta * 10.0)
		_look_smoothly_toward(global_position + _smoothed_move_dir * 3.5 + Vector3(0.0, 1.45, 0.0), delta * 7.5)
		var esc_jump := false
		if _jump_cooldown <= 0.0 and is_on_floor() and _is_jumpable_ledge(_smoothed_move_dir):
			esc_jump = true
			_jump_cooldown = 1.25
			_air_crouch_timer = 0.55
		apply_goldsrc_movement(_smoothed_move_dir, esc_jump, _vent_crouch_timer > 0.0 or (_air_crouch_timer > 0.0 and not is_on_floor()), false, delta)
		_last_pos = global_position
		if _escape_timer <= 0.0:
			_diversity_seed = randi()
			# Extraction is an explicit mission goal, not a roaming preference.
			# Generic stuck recovery must never replace it with a random waypoint:
			# doing so made the VIP tour the map between repeated rescue replans.
			if is_vip and _vip_escape_node >= 0:
				_rechoice_count = 0
				_banned_nodes.erase(_vip_escape_node)
				_plan_to_node(nav, _vip_escape_node, false, BotNavigator.PATH_DIVERSITY)
			elif _rechoice_count >= 2 or _goal_node_idx < 0 or _banned_nodes.has(_goal_node_idx):
				_rechoice_count = 0
				_has_goal = false
				_plan_to_node(nav, nav.pick_roam_node(global_position, team), false, BotNavigator.PATH_DIVERSITY)
			else:
				_plan_to_node(nav, _goal_node_idx, _is_leading_hostage(), BotNavigator.PATH_DIVERSITY)
		return

	if _hold_pos_timer > 0.0 or _node_path.is_empty():
		_smoothed_move_dir = _smoothed_move_dir.lerp(Vector3.ZERO, minf(1.0, 10.0 * delta))
		apply_goldsrc_movement(Vector3.ZERO, false, false, false, delta)
		_last_pos = global_position
		return

	var cur_id: int = _node_path[0]
	var cur_flags: int = nav.get_node_flags(cur_id)
	var lnk_cur := nav.get_link_info(_prev_node_idx, cur_id)
	var is_jump_link: bool = lnk_cur.size() >= 2 and (int(lnk_cur[1]) & BotNavigator.LINK_JUMP) != 0

	# Safe YaPB String-Pulling (yapb/src/navigate.cpp:2840):
	# ONLY shortcut cur_id -> next_id when directly connected in the directed graph, NO action/jump flags,
	# nearly flat elevation, and wide capsule-shoulder line-of-sight!
	if _node_path.size() >= 2 and not is_jump_link and (cur_flags & BotNavigator.ACTION_FLAGS) == 0:
		var next_id: int = _node_path[1]
		var next_flags: int = nav.get_node_flags(next_id)
		if (next_flags & BotNavigator.ACTION_FLAGS) == 0 and nav.are_directly_linked(cur_id, next_id):
			var p_next := nav.get_node_pos(next_id)
			if absf(p_next.y - global_position.y) < 0.32 and global_position.distance_to(p_next) < 5.0:
				if _has_wide_corridor_sight(global_position, p_next):
					_record_vip_route_node(cur_id)
					_prev_node_idx = cur_id
					_node_path.remove_at(0)
					cur_id = _node_path[0]
					cur_flags = nav.get_node_flags(cur_id)
					_advance_to_node_entry(nav, cur_id)
					lnk_cur = nav.get_link_info(_prev_node_idx, cur_id)
					is_jump_link = lnk_cur.size() >= 2 and (int(lnk_cur[1]) & BotNavigator.LINK_JUMP) != 0

	var wp: Vector3 = nav.get_node_pos(cur_id) + _cur_node_offset
	var flat_d: float = Vector2(wp.x - global_position.x, wp.z - global_position.z).length()
	var signed_dy: float = wp.y - global_position.y
	var vert_d: float = absf(signed_dy)

	# Tight arrival on ladders/jumps; NEVER mark an upper ledge reached from
	# below. Ground-only narrow nodes need capsule clearance: a 0.54 m radius
	# can be smaller than the collision-free orbit around their centre.
	var ground_narrow := (cur_flags & BotNavigator.ACTION_FLAGS) == BotNavigator.FLAG_NARROW and not is_jump_link
	var touch_r: float = 0.90 if ground_narrow else (0.54 if ((cur_flags & BotNavigator.ACTION_FLAGS) != 0 or is_jump_link) else 1.15)
	var max_vert_touch: float = (0.68 if signed_dy > 0.0 else 2.1) if (cur_flags & BotNavigator.FLAG_LADDER) != 0 else (0.68 if signed_dy > 0.0 else 1.45)
	var previous_is_ladder := (nav.get_node_flags(_prev_node_idx) & BotNavigator.FLAG_LADDER) != 0
	var leaving_ladder_top := previous_is_ladder and (cur_flags & BotNavigator.FLAG_LADDER) == 0 and wp.y >= nav.get_node_pos(_prev_node_idx).y - 0.8
	# A capsule beside/below the top platform can be within the arrival sphere
	# while still falling. Finish the vault and actually land before advancing.
	var arrival_supported := not leaving_ladder_top or is_on_floor()
	if flat_d < touch_r and vert_d < max_vert_touch and arrival_supported:
		_record_vip_route_node(cur_id)
		_prev_node_idx = cur_id
		_node_path.remove_at(0)
		_stuck_timer = 0.0
		_rechoice_count = 0
		if _node_path.is_empty():
			_has_goal = false
			_try_enter_camp_at_node(nav, cur_id)
			apply_goldsrc_movement(Vector3.ZERO, false, is_crouching and _camp_timer > 0.0, false, delta)
			_last_pos = global_position
			return
		cur_id = _node_path[0]
		cur_flags = nav.get_node_flags(cur_id)
		_advance_to_node_entry(nav, cur_id)
		lnk_cur = nav.get_link_info(_prev_node_idx, cur_id)
		is_jump_link = lnk_cur.size() >= 2 and (int(lnk_cur[1]) & BotNavigator.LINK_JUMP) != 0
		wp = nav.get_node_pos(cur_id) + _cur_node_offset
		flat_d = Vector2(wp.x - global_position.x, wp.z - global_position.z).length()
		signed_dy = wp.y - global_position.y
		vert_d = absf(signed_dy)

	# Multi-story Metal Ladder Climbing. A waypoint at the current height is a
	# horizontal entry/exit except across the top lip, which needs the vault.
	var near_ladder_top := false
	if on_ladder:
		if (cur_flags & BotNavigator.FLAG_LADDER) != 0:
			bot_ladder_anchor = nav.get_node_pos(cur_id)
			bot_ladder_anchor_valid = true
		elif (nav.get_node_flags(_prev_node_idx) & BotNavigator.FLAG_LADDER) != 0:
			bot_ladder_anchor = nav.get_node_pos(_prev_node_idx)
			bot_ladder_anchor_valid = true
		var actor_h := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
		var ladder_info: Dictionary = RoundManager.game_world.call("get_ladder_info", global_position, actor_h)
		var ladder_top := float(ladder_info.get("top_y", global_position.y + 2.0))
		var ladder_normal: Vector3 = ladder_info.get("normal", Vector3.ZERO)
		var ladder_center: Vector3 = ladder_info.get("center", global_position)
		# Only vault onto the platform behind the rungs after climbing. A level
		# approach on the exposed side is an entry, not a top exit (OilRig).
		near_ladder_top = global_position.y >= ladder_top - 0.85 and wp.y >= ladder_top - 0.40 and ((nav.get_node_flags(_prev_node_idx) & BotNavigator.FLAG_LADDER) != 0 or bot_ladder_dir > 0.1) and (wp - ladder_center).dot(ladder_normal) < -0.20
		if absf(signed_dy) < 0.35 and flat_d > 0.20 and not near_ladder_top:
			bot_ladder_dir = 0.0
		else:
			# At the top lip, keep climbing through the vault even when the exit
			# node is level. Switching to horizontal input here can hit the rungs.
			bot_ladder_dir = 1.0 if signed_dy >= -0.30 else -1.0

	# Pure-pursuit corner rounding ONLY on flat, non-action, non-jump links
	var steer_target: Vector3 = wp
	if not is_vip and not on_ladder and not is_jump_link and (cur_flags & BotNavigator.ACTION_FLAGS) == 0 and _node_path.size() >= 2 and flat_d < 2.0:
		var next_id2: int = _node_path[1]
		if (nav.get_node_flags(next_id2) & BotNavigator.ACTION_FLAGS) == 0 and nav.are_directly_linked(cur_id, next_id2):
			var wp2 := nav.get_node_pos(next_id2)
			if absf(wp2.y - wp.y) < 0.30:
				var corner_blend := clampf((2.0 - flat_d) / 2.0, 0.0, 0.38)
				steer_target = wp.lerp(wp2, corner_blend)

	var raw_dir := Vector3(steer_target.x - global_position.x, 0.0, steer_target.z - global_position.z)
	if raw_dir.length_squared() > 0.001:
		raw_dir = raw_dir.normalized()

	# Ladder waypoints can be horizontally beyond the rungs. Enter the real
	# brush before ascending/descending; once on_ladder, CSActor takes over.
	# Upward entries aim at the brush centre because two rungs may share X/Z.
	var ladder_entry_exact := false
	if not on_ladder and absf(signed_dy) > 0.68 and (nav.get_node_flags(_prev_node_idx) & BotNavigator.FLAG_LADDER) != 0:
		var previous_wp := nav.get_node_pos(_prev_node_idx)
		for raw_ladder in RoundManager.game_world.ladder_volumes:
			var ladder: Dictionary = raw_ladder
			var raw_box := ladder["raw_aabb"] as AABB
			var climb_box := ladder["climb_aabb"] as AABB
			if not climb_box.has_point(previous_wp):
				continue
			var entry := Vector3.ZERO
			if signed_dy < 0.0:
				if previous_wp.y < raw_box.end.y - 1.6 or previous_wp.y > raw_box.end.y + 0.8:
					continue
				if wp.y < raw_box.position.y - 0.8 or wp.y > raw_box.end.y:
					continue
				entry = previous_wp - global_position
			else:
				if previous_wp.y < raw_box.position.y - 0.8 or previous_wp.y > raw_box.end.y + 0.8:
					continue
				if wp.y < raw_box.position.y - 0.8 or wp.y > raw_box.end.y + 0.8:
					continue
				entry = raw_box.get_center() - global_position
			entry.y = 0.0
			if entry.length_squared() > 0.006:
				raw_dir = entry.normalized()
				ladder_entry_exact = true
			break

	# Do NOT let obstacle whiskers deflect away from a climbable step/ledge when heading to a higher node!
	var is_climb_step: bool = (not on_ladder) and (is_jump_link or (signed_dy > 0.44 and signed_dy < 1.90 and flat_d < 2.6 and _is_jumpable_ledge(raw_dir)))
	# Narrow/action waypoints already encode the safe corridor. Objective actors
	# use exact input there; obstacle steering remains for open combat/roaming.
	var precision_route: bool = (is_vip or _vip_breadcrumb_active or is_instance_valid(_hostage_target)) and ((cur_flags & BotNavigator.ACTION_FLAGS) != 0 or _node_path.size() <= 2)
	var exact_input: bool = on_ladder or is_climb_step or precision_route or ladder_entry_exact
	# Precision removes lateral steering, not world interaction. Authored
	# crouch routes can pass through breakable windows (e.g. the 747 cabin).
	# Still open doors/clear panels, then keep the exact waypoint direction.
	var obstacle_dir := _steer_around_obstacles(raw_dir)
	var target_move_dir := raw_dir if exact_input else obstacle_dir
	_smoothed_move_dir = target_move_dir if exact_input else _blend_move_dir(_smoothed_move_dir, target_move_dir, delta * 12.5)
	var move_dir := _smoothed_move_dir

	# YaPB Jump-Link & Ledge Crouch-Jump Execution:
	# Launch right at the ledge lip (flat_d < 2.15 or ledge face within 1.25m) and allow clean retries!
	var want_jump := false
	if is_climb_step and _jump_cooldown <= 0.0 and (is_on_floor() or on_ladder) and not RoundManager.is_movement_frozen():
		if flat_d < 2.15 or _is_jumpable_ledge(raw_dir):
			want_jump = true
			_jump_cooldown = 0.78
			_air_crouch_timer = 0.60
			if lnk_cur.size() >= 5 and Vector2(float(lnk_cur[2]), float(lnk_cur[4])).length_squared() > 0.25:
				velocity.x = float(lnk_cur[2])
				velocity.z = float(lnk_cur[4])
			elif raw_dir.length_squared() > 0.01:
				velocity.x = raw_dir.x * 6.8
				velocity.z = raw_dir.z * 6.8

	# Auto-crouch on YaPB FLAG_CROUCH nodes or low vents/ducts!
	# An ascending capsule can also hit the edge of a ladder's roof opening.
	# Probe with the real hull; retain the duck until this climb exits the brush.
	var ladder_needs_duck := on_ladder and bot_ladder_dir > 0.1 and test_move(global_transform, Vector3.UP * 0.45)
	if (cur_flags & BotNavigator.FLAG_CROUCH) != 0 or ladder_needs_duck or (not on_ladder and _needs_crouch_clearance(move_dir)):
		_vent_crouch_timer = 0.35

	# Pre-aiming along upcoming YaPB corridor or toward heard enemy sound
	_corner_check_timer -= delta
	if _corner_check_timer <= 0.0:
		_corner_check_timer = randf_range(1.4, 2.8)
		if randf() < 0.28 and _knife_rush_timer <= 0.0:
			_corner_yaw_offset = deg_to_rad(randf_range(-16.0, 16.0))
		else:
			_corner_yaw_offset = 0.0

	var look_pt: Vector3
	if _sound_investigate_timer > 0.0:
		look_pt = _sound_investigate_pos + Vector3(0.0, 1.42, 0.0)
	else:
		var ahead_id: int = _node_path[mini(1, _node_path.size() - 1)]
		var ahead_wp := nav.get_node_pos(ahead_id)
		var look_dir := Vector3(ahead_wp.x - global_position.x, 0.0, ahead_wp.z - global_position.z)
		if look_dir.length_squared() < 0.04:
			look_dir = move_dir
		else:
			look_dir = look_dir.normalized()
		look_dir = (look_dir * 0.65 + move_dir * 0.35).normalized().rotated(Vector3.UP, _corner_yaw_offset)
		look_pt = global_position + look_dir * 4.5 + Vector3(0.0, 1.48, 0.0)
	_look_smoothly_toward(look_pt, delta * 7.5)

	if not RoundManager.is_movement_frozen():
		_cur_node_elapsed += delta
		var moved_dist := global_position.distance_to(_last_pos)
		if on_ladder and absf(velocity.y) > 0.55:
			_stuck_timer = 0.0
		elif traffic.mode in ["wait", "yield", "follow", "sidestep"]:
			_stuck_timer = 0.0
			_cur_node_elapsed = 0.0
		elif moved_dist < 1.05 * delta:
			_stuck_timer += delta
			if _stuck_timer > 0.24 and _jump_cooldown <= 0.0 and is_on_floor():
				if _is_jumpable_ledge(raw_dir) or _is_jumpable_ledge(move_dir):
					want_jump = true
					_jump_cooldown = 1.05
					_air_crouch_timer = 0.58
					velocity.x = raw_dir.x * 6.5
					velocity.z = raw_dir.z * 6.5
				elif _needs_crouch_clearance(move_dir):
					_vent_crouch_timer = 0.65
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta * 2.2)

		# YaPB FindValidNode Timeout + Node Ban: NEVER remain stuck on any node for > 3.2s!
		var reach_deadline: float = maxf(3.2, flat_d * 0.65 + 1.8) if not on_ladder else 7.5
		if _stuck_timer > 0.56 or _cur_node_elapsed > reach_deadline:
			_stuck_timer = 0.0
			_cur_node_elapsed = 0.0
			_rechoice_count += 1
			_avoid_side = -_avoid_side
			if is_vip:
				# Retry through A* from the actual blocked position. A long random
				# escape maneuver can throw the VIP back across a directed junction.
				_banned_nodes[cur_id] = _nav_clock + 3.0
				_node_path = PackedInt32Array()
				_has_goal = false
				_vip_route_rethink = 0.0
				_smoothed_move_dir = Vector3.ZERO
				move_dir = Vector3.ZERO
			else:
				_banned_nodes[cur_id] = _nav_clock + 18.0
				nav.report_blocked_segment(global_position, wp)
				_escape_dir = _pick_open_escape_direction(raw_dir)
				_escape_timer = 0.92
				_node_path = PackedInt32Array()
		_last_pos = global_position

	# Dismount only near the exit waypoint's height. Testing merely "target is
	# below" kicks the bot off at the top of a long descent.
	if on_ladder and not near_ladder_top and absf(bot_ladder_dir) > 0.1 and (cur_flags & BotNavigator.FLAG_LADDER) == 0 and absf(signed_dy) < 0.75 and flat_d > 0.35:
		want_jump = true

	var crouch_air: bool = (_air_crouch_timer > 0.0 and not is_on_floor())
	var want_crouch: bool = (_vent_crouch_timer > 0.0 and (not on_ladder or ladder_needs_duck)) or (on_ladder and is_crouching) or crouch_air
	var approaching_ladder: bool = (cur_flags & BotNavigator.FLAG_LADDER) != 0 and not on_ladder and flat_d < 1.8
	var want_silent_walk: bool = (approaching_ladder or (_stealth_walk_timer > 0.0 and _knife_rush_timer <= 0.0)) and not want_jump and not want_crouch
	apply_goldsrc_movement(move_dir, want_jump, want_crouch, want_silent_walk, delta)


func _try_enter_camp_at_node(nav: BotNavigator, node_idx: int) -> void:
	if bomb_role in ["cover", "guard", "escort"]:
		return
	if _camp_cooldown > 0.0 or is_vip or _is_leading_hostage() or _is_assigned_vip_escort():
		return
	if team == "T" and RoundManager.map_mode == "de" and not is_instance_valid(RoundManager.planted_c4) and String(weapon_ctrl.slots.get(5, "")) == "c4":
		return
	var fl := nav.get_node_flags(node_idx)
	if (fl & (BotNavigator.FLAG_CAMP | BotNavigator.FLAG_SNIPER)) == 0:
		return
	if (fl & BotNavigator.FLAG_SNIPER) != 0 and not _uses_sniper():
		return
	if team == "T" and (fl & BotNavigator.FLAG_CT_ONLY) != 0:
		return
	if team == "CT" and (fl & BotNavigator.FLAG_T_ONLY) != 0:
		return
	if nav.is_node_occupied(node_idx, self):
		return
	nav.claim_node(node_idx, self)
	_camping_node_idx = node_idx
	_camp_timer = randf_range(5.5, 11.5) if not _uses_sniper() else randf_range(8.0, 15.0)
	_camp_sweep_timer = randf_range(2.0, 3.8)
	_camp_look_alt = false


func _blend_move_dir(cur_d: Vector3, tgt_d: Vector3, rate: float) -> Vector3:
	if tgt_d.length_squared() < 0.001:
		return Vector3.ZERO
	if cur_d.length_squared() < 0.001:
		return tgt_d.normalized()
	var w := clampf(rate, 0.0, 1.0)
	var new_ang := lerp_angle(atan2(cur_d.x, cur_d.z), atan2(tgt_d.x, tgt_d.z), w)
	return Vector3(sin(new_ang), 0.0, cos(new_ang))


func _has_wide_corridor_sight(from_p: Vector3, to_p: Vector3) -> bool:
	var sp := get_world_3d().direct_space_state
	var delta_v := to_p - from_p
	delta_v.y = 0.0
	if delta_v.length_squared() < 0.04:
		return true
	var right_v := Vector3(-delta_v.z, 0.0, delta_v.x).normalized() * 0.44
	# Check BOTH shin height (+0.42m, catches waist-high parapets!) AND chest height (+1.05m)!
	for h_ofs in [0.42, 1.05]:
		for lat_ofs in [Vector3.ZERO, right_v, -right_v]:
			var q := PhysicsRayQueryParameters3D.create(
				from_p + lat_ofs + Vector3(0.0, float(h_ofs), 0.0),
				to_p + lat_ofs + Vector3(0.0, float(h_ofs), 0.0)
			)
			q.collision_mask = 1
			if not sp.intersect_ray(q).is_empty():
				return false
	return true


func _needs_crouch_clearance(fwd_dir: Vector3) -> bool:
	if fwd_dir.length_squared() < 0.001 or not is_inside_tree() or not get_world_3d():
		return false
	var sp := get_world_3d().direct_space_state
	var waist_p := global_position + Vector3(0.0, 0.56, 0.0)
	var head_p := global_position + Vector3(0.0, 1.66, 0.0)
	var q_head := PhysicsRayQueryParameters3D.create(head_p, head_p + fwd_dir * 1.15)
	q_head.collision_mask = 1
	var h_head := sp.intersect_ray(q_head)
	if h_head.is_empty():
		return false
	if h_head["collider"] is Node and (h_head["collider"] as Node).has_meta("door"):
		return false
	var q_waist := PhysicsRayQueryParameters3D.create(waist_p, waist_p + fwd_dir * 1.15)
	q_waist.collision_mask = 1
	return sp.intersect_ray(q_waist).is_empty()


func _pick_open_escape_direction(blocked_dir: Vector3) -> Vector3:
	if not is_inside_tree() or not get_world_3d():
		return -blocked_dir
	var space := get_world_3d().direct_space_state
	var shin := global_position + Vector3(0.0, 0.58, 0.0)
	var chest := global_position + Vector3(0.0, 1.05, 0.0)
	var best_dir := -blocked_dir
	var best_score := -1e9
	var base := blocked_dir if blocked_dir.length_squared() > 0.01 else Vector3.FORWARD
	for i in range(8):
		var ang := deg_to_rad(float(i) * 45.0)
		var cand := base.rotated(Vector3.UP, ang).normalized()
		var q_s := PhysicsRayQueryParameters3D.create(shin, shin + cand * 4.2)
		q_s.collision_mask = 1
		var h_s := space.intersect_ray(q_s)
		var q_c := PhysicsRayQueryParameters3D.create(chest, chest + cand * 4.2)
		q_c.collision_mask = 1
		var h_c := space.intersect_ray(q_c)
		var d_s := 4.2 if h_s.is_empty() else shin.distance_to(h_s["position"] as Vector3)
		var d_c := 4.2 if h_c.is_empty() else chest.distance_to(h_c["position"] as Vector3)
		var free_d := minf(d_s, d_c)
		var away_bonus := (1.0 - cand.dot(base)) * 0.85
		# Open air is not an escape route. Prefer a nearby walkable floor so a
		# stuck recovery on a ladder/top catwalk never throws the bot off a ledge.
		var floor_probe := global_position + cand * 1.15
		var floor_q := PhysicsRayQueryParameters3D.create(floor_probe + Vector3(0.0, 0.65, 0.0), floor_probe - Vector3(0.0, 1.45, 0.0))
		floor_q.collision_mask = 1
		var floor_hit := space.intersect_ray(floor_q)
		var floor_penalty := 0.0
		if floor_hit.is_empty() or (floor_hit.get("normal", Vector3.UP) as Vector3).y < 0.45:
			floor_penalty = 12.0
		var score := free_d + away_bonus + randf_range(-0.12, 0.12) - floor_penalty
		if score > best_score:
			best_score = score
			best_dir = cand
	return best_dir


func _steer_around_obstacles(desired_dir: Vector3) -> Vector3:
	if desired_dir.length_squared() < 0.001 or not is_inside_tree() or not get_world_3d():
		return desired_dir

	var steer := desired_dir
	var space := get_world_3d().direct_space_state
	# Dual-height probe: +0.62m catches waist-high parapets/crates; +1.05m catches mid-chest walls/doors!
	var shin_org := global_position + Vector3(0.0, 0.62, 0.0)
	var chest_org := global_position + Vector3(0.0, 1.05, 0.0)
	var right_sh := Vector3(-desired_dir.z, 0.0, desired_dir.x) * 0.36

	var q_mid := PhysicsRayQueryParameters3D.create(chest_org, chest_org + desired_dir * 1.45)
	q_mid.collision_mask = 1
	var hit_mid := space.intersect_ray(q_mid)
	if hit_mid.is_empty():
		var q_low := PhysicsRayQueryParameters3D.create(shin_org, shin_org + desired_dir * 1.25)
		q_low.collision_mask = 1
		hit_mid = space.intersect_ray(q_low)

	if hit_mid.is_empty():
		var q_l := PhysicsRayQueryParameters3D.create(chest_org - right_sh, chest_org - right_sh + desired_dir * 1.05)
		q_l.collision_mask = 1
		var h_l := space.intersect_ray(q_l)
		var q_r := PhysicsRayQueryParameters3D.create(chest_org + right_sh, chest_org + right_sh + desired_dir * 1.05)
		q_r.collision_mask = 1
		var h_r := space.intersect_ray(q_r)
		if not h_l.is_empty() and h_r.is_empty():
			steer = (desired_dir + right_sh.normalized() * 0.45).normalized()
		elif not h_r.is_empty() and h_l.is_empty():
			steer = (desired_dir - right_sh.normalized() * 0.45).normalized()
	else:
		var mid_col = hit_mid["collider"]
		if mid_col is Node and (mid_col as Node).has_meta("door"):
			var door_ref = (mid_col as Node).get_meta("door")
			if is_instance_valid(door_ref) and door_ref.has_method("force_open"):
				door_ref.call("force_open", self)
			steer = desired_dir
		elif mid_col is Node and (mid_col as Node).has_meta("button_target"):
			var btgt := String((mid_col as Node).get_meta("button_target"))
			if RoundManager.game_world != null:
				RoundManager.game_world.trigger_map_target(btgt, self)
			steer = desired_dir
		elif mid_col is Node and (mid_col as Node).has_meta("breakable"):
			var brk_ref = (mid_col as Node).get_meta("breakable")
			if is_instance_valid(brk_ref) and brk_ref.has_method("apply_damage"):
				brk_ref.call("apply_damage", 45.0, hit_mid["position"])
			steer = desired_dir
		else:
			var angles := [28.0 * _avoid_side, -28.0 * _avoid_side, 54.0 * _avoid_side, -54.0 * _avoid_side, 82.0 * _avoid_side, -82.0 * _avoid_side]
			var best_cand := desired_dir
			var best_clear := -1.0
			for deg_a in angles:
				var cand_dir := desired_dir.rotated(Vector3.UP, deg_to_rad(float(deg_a)))
				var qc := PhysicsRayQueryParameters3D.create(shin_org, shin_org + cand_dir * 2.15)
				qc.collision_mask = 1
				var hc := space.intersect_ray(qc)
				var clear_d := 2.15 if (hc.is_empty() or (hc["collider"] is Node and (hc["collider"] as Node).has_meta("door"))) else shin_org.distance_to(hc["position"] as Vector3)
				var align_score := clear_d - absf(float(deg_a)) * 0.012
				if clear_d > 1.35 and align_score > best_clear:
					best_clear = align_score
					best_cand = cand_dir
			if best_clear > 0.0:
				steer = best_cand
			else:
				var nrm := hit_mid["normal"] as Vector3
				nrm.y = 0.0
				var slide := (desired_dir - nrm * desired_dir.dot(nrm))
				if slide.length_squared() > 0.04:
					steer = slide.normalized()
				else:
					steer = desired_dir.rotated(Vector3.UP, deg_to_rad(115.0 * _avoid_side))

	# Legacy enemy separation; teammates use the common traffic negotiator (checks shin height +0.62m so bots NEVER push into parapets!)
	var sep_accum := Vector3.ZERO
	for a in RoundManager.actors:
		if not is_instance_valid(a) or a == self or not bool(a.get("is_alive")) or String(a.get("team")) == team:
			continue
		var a_node := a as Node3D
		if a_node == null or absf(a_node.global_position.y - global_position.y) > 1.6:
			continue
		var diff := global_position - a_node.global_position
		diff.y = 0.0
		var dsq := diff.length_squared()
		if dsq > 0.0001 and dsq < 1.25:
			var dist := sqrt(dsq)
			var away := diff / dist
			var tangent := Vector3(-away.z, 0.0, away.x) * _avoid_side
			var push := (1.12 - minf(1.12, dist)) * 0.36
			sep_accum += away * push + tangent * (push * 0.55)

	if sep_accum.length_squared() > 0.0004:
		if sep_accum.length() > 0.32:
			sep_accum = sep_accum.normalized() * 0.32
		var sep_dir := sep_accum.normalized()
		var q_wall := PhysicsRayQueryParameters3D.create(shin_org, shin_org + sep_dir * 1.05)
		q_wall.collision_mask = 1
		if space.intersect_ray(q_wall).is_empty():
			steer += sep_accum

	steer.y = 0.0
	return steer.normalized() if steer.length_squared() > 0.001 else desired_dir


func _is_jumpable_ledge(fwd_dir: Vector3) -> bool:
	if fwd_dir.length_squared() < 0.001 or not is_inside_tree() or not get_world_3d():
		return false
	var space := get_world_3d().direct_space_state
	# Check both shin (+0.42m) and waist (+0.85m) blocked while crouch-jump head (+1.78m) is clear!
	var shin_from := global_position + Vector3(0.0, 0.42, 0.0)
	var waist_from := global_position + Vector3(0.0, 0.85, 0.0)
	var high_from := global_position + Vector3(0.0, 1.78, 0.0)
	var q_high := PhysicsRayQueryParameters3D.create(high_from, high_from + fwd_dir * 1.28)
	q_high.collision_mask = 1
	if not space.intersect_ray(q_high).is_empty():
		return false
	var q_shin := PhysicsRayQueryParameters3D.create(shin_from, shin_from + fwd_dir * 1.20)
	q_shin.collision_mask = 1
	if not space.intersect_ray(q_shin).is_empty():
		return true
	var q_waist := PhysicsRayQueryParameters3D.create(waist_from, waist_from + fwd_dir * 1.20)
	q_waist.collision_mask = 1
	return not space.intersect_ray(q_waist).is_empty()


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
		if skill_level >= 1 and d < 15.5 and d > 4.0 and not is_instance_valid(RoundManager.planted_c4) and randf() < 0.55:
			_stealth_walk_timer = randf_range(1.3, 2.5)


func _on_radio_order(sender: Node3D, steam: String, action: String, pos: Vector3) -> void:
	if not is_alive or steam != team or sender == self:
		return
	match action:
		"follow_me", "cover_me":
			if global_position.distance_to(pos) < 24.0:
				_release_camp_spot()
				_follow_target = sender
				_hold_pos_timer = 0.0
		"hold_position":
			if global_position.distance_to(pos) < 20.0:
				_follow_target = null
				_hold_pos_timer = 15.0
		"go", "storm_front":
			_release_camp_spot()
			_follow_target = null
			_hold_pos_timer = 0.0


func _on_taken_damage_from(attacker: Node3D, hit_pos: Vector3) -> void:
	if not is_alive:
		return
	_knife_rush_timer = 0.0
	_hold_pos_timer = 0.0
	_release_camp_spot()
	_stealth_walk_timer = 0.0
	_strafe_dir = -_strafe_dir
	_strafe_timer = randf_range(0.35, 0.70)

	if is_instance_valid(RoundManager.game_world):
		var nav: BotNavigator = RoundManager.game_world.get("bot_navigator")
		if nav != null:
			nav.report_team_damage(team, global_position, 35.0)

	if attacker is CSActor:
		var enemy := attacker as CSActor
		if is_instance_valid(enemy) and enemy != self and enemy.team != team and enemy.is_alive:
			_last_enemy_pos = enemy.global_position
			_last_enemy_seen_age = 0.0
			_sound_investigate_pos = enemy.global_position
			_sound_investigate_timer = 3.5
			if is_vip:
				_vip_route_rethink = 0.0
			if target_enemy == null:
				var visible := _can_see_actor(enemy)
				if visible and (not is_vip or global_position.distance_to(enemy.global_position) <= 12.0):
					target_enemy = enemy
					var fast_react: float = float([0.22, 0.14, 0.09, 0.045][clampi(skill_level, 0, 3)])
					_reaction_timer = fast_react
				elif not visible:
					_look_smoothly_toward(enemy.global_position + Vector3(0.0, 1.35, 0.0), 0.58)
			for mate in RoundManager.actors:
				if mate is CSBot and mate != self and is_instance_valid(mate):
					var m_bot := mate as CSBot
					if m_bot.is_alive and m_bot.team == team and m_bot.target_enemy == null:
						if m_bot.global_position.distance_to(global_position) < 18.0:
							m_bot.notify_squad_contact(enemy.global_position)
			return

	_sound_investigate_pos = hit_pos
	_sound_investigate_timer = 2.5


func notify_squad_contact(threat_pos: Vector3) -> void:
	if not is_alive or target_enemy != null:
		return
	_knife_rush_timer = 0.0
	_sound_investigate_pos = threat_pos
	_sound_investigate_timer = maxf(_sound_investigate_timer, 2.8)
	_last_enemy_pos = threat_pos
	_last_enemy_seen_age = minf(_last_enemy_seen_age, 1.5)


# --- C4 BLAST ESCAPE: HP-scaled survival ring around the planted bomb (dmg = 500 * (1 - d/54)^1.65) ---

func _compute_blast_survive_ring() -> float:
	var hp_f := clampf(float(health) / 500.0, 0.02, 0.85)
	return clampf(54.0 * (1.0 - pow(hp_f, 1.0 / 1.65)) + 3.0, 26.0, 50.0)


func _update_bomb_escape_state() -> void:
	if not is_instance_valid(RoundManager.planted_c4):
		_bomb_escape_active = false
		_bomb_flee_node = -1
		return
	var c4 := RoundManager.planted_c4 as PlantedC4
	if c4 == null:
		_bomb_escape_active = false
		_bomb_flee_node = -1
		return

	var t_left: float = c4.time_left
	var d_bomb: float = global_position.distance_to(c4.global_position)
	var was_active := _bomb_escape_active

	if team == "CT":
		# Decide honestly whether the defuse is still mathematically possible:
		# travel (paths run ~1.35x straight-line at knife speed) + remaining defuse + margin
		var defuse_t: float = 5.0 if has_defuser else 10.0
		var margin: float = 0.9
		if _defusing_ref == c4 and c4.defuser_actor == self:
			# Already holding the keypad: only the REMAINING progress counts!
			defuse_t = maxf(0.1, float(c4.defuse_required) - float(c4.defuse_progress))
			margin = 0.15
		var travel_est: float = d_bomb * 0.235 + 0.55
		var teammate := BombSquad.elect_defuser(c4, RoundManager.actors)
		if teammate != null and teammate != self:
			defuse_t = (5.0 if teammate.has_defuser else 10.0)
			travel_est = teammate.global_position.distance_to(c4.global_position) * 0.235 + 0.55
			if c4.defuser_actor == teammate:
				defuse_t = maxf(0.1, c4.defuse_required-c4.defuse_progress)
				travel_est = 0.0
		_bomb_escape_active = t_left <= travel_est + defuse_t + margin
	else:
		if was_active:
			# Once committed to fleeing, finish the escape — never return to a ticking bomb post!
			_bomb_escape_active = true
		elif d_bomb >= _compute_blast_survive_ring() + 6.0:
			# Already outside the lethal ring -> keep the guard post
			_bomb_escape_active = false
		else:
			# Deterministic per-bot flee horizon (~9.5s rushers .. ~13s careful) — no threshold dithering
			var flee_horizon: float = 9.5 + float(personality) * 1.7 + float(absi(get_instance_id() % 13)) * 0.11
			_bomb_escape_active = t_left <= flee_horizon

	if _bomb_escape_active and not was_active:
		if is_instance_valid(RoundManager.game_world):
			var nav_v: Variant = RoundManager.game_world.get("bot_navigator")
			if is_instance_valid(nav_v):
				_begin_bomb_escape(nav_v as BotNavigator)
	elif not _bomb_escape_active and was_active:
		_bomb_flee_node = -1


func _begin_bomb_escape(nav: BotNavigator) -> void:
	_bomb_escape_active = true
	_bomb_flee_node = -1
	_release_camp_spot()
	_follow_target = null
	_hold_pos_timer = 0.0
	_camp_timer = 0.0
	_sound_investigate_timer = 0.0
	_disengage_timer = 0.0
	_knife_rush_timer = 0.0
	_stealth_walk_timer = 0.0
	target_enemy = null
	if is_instance_valid(RoundManager.planted_c4):
		var c4p: Vector3 = RoundManager.planted_c4.global_position
		_bomb_flee_min_dist = _compute_blast_survive_ring() + randf_range(4.0, 10.0)
		_bomb_flee_node = nav.pick_flee_node(global_position, c4p, _bomb_flee_min_dist, team)
	_has_goal = false
	_node_path = PackedInt32Array()
	_update_bomb_flee_path()


func _update_bomb_flee_path() -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	var nav: BotNavigator = RoundManager.game_world.get("bot_navigator")
	if nav == null or nav.waypoints.is_empty():
		return
	if _bomb_flee_node < 0 or _bomb_flee_node >= nav.waypoints.size():
		var c4p: Vector3 = global_position
		if is_instance_valid(RoundManager.planted_c4):
			c4p = RoundManager.planted_c4.global_position
		_bomb_flee_node = nav.pick_flee_node(global_position, c4p, _bomb_flee_min_dist, team)
		if _bomb_flee_node < 0:
			return
	if _node_path.is_empty() or not _has_goal or _goal_node_idx != _bomb_flee_node:
		_plan_to_node(nav, _bomb_flee_node, false, BotNavigator.PATH_FAST)


# --- TEAM ECONOMY: freezetime weapon sharing — a rich survivor gifts its primary to a broke teammate! ---

func _maybe_share_loadout() -> void:
	if is_vip or not is_alive or not RoundManager.can_buy_now():
		return
	if RoundManager.state != RoundManager.State.FREEZE:
		return
	var wid := String(weapon_ctrl.slots.get(1, ""))
	if wid.is_empty() or not GameData.weapons.has(wid):
		return
	var spec: Dictionary = GameData.weapons[wid]
	if bool(spec.get("grenade", false)):
		return

	# Only share when an equal-or-better rebuy PLUS full equipment is still affordable afterwards!
	var own_price := int(spec.get("price", 0))
	var equip_reserve: int = 1000  # kevlar + helmet
	if team == "CT" and RoundManager.map_mode == "de" and not has_defuser:
		equip_reserve += 200
	equip_reserve += 500  # ammo top-up / grenade buffer
	if money < own_price + equip_reserve:
		return

	# Find the most-broke teammate without a primary (bots & the human player alike)
	var best_rec: CSActor = null
	var best_money: int = 999999
	var rec_thresh: int = maxi(1800, int(float(own_price) * 0.55))
	for a in RoundManager.actors:
		if not is_instance_valid(a) or a == self:
			continue
		if String(a.get("team")) != team:
			continue
		var rec := a as CSActor
		if rec == null or not is_instance_valid(rec) or rec.is_vip:
			continue
		if not String(rec.weapon_ctrl.slots.get(1, "")).is_empty():
			continue
		if rec.money >= rec_thresh:
			continue
		if rec.has_meta("gift_round") and int(rec.get_meta("gift_round")) == RoundManager.round_number:
			continue
		if rec.money < best_money:
			best_money = rec.money
			best_rec = rec
	if best_rec == null:
		return

	best_rec.set_meta("gift_round", RoundManager.round_number)
	var clip_sz := int(spec.get("clip_size", 30))
	var atype := String(spec.get("ammo_type", "none"))
	var keep_reserve := int(weapon_ctrl.ammo_pool.get(atype, 0))
	var drop_g := drop_weapon_gift(best_rec, wid, clip_sz, 0)

	# Hand over the gun: donor keeps its reserve ammo & rebuys its own primary in _perform_bot_buy!
	weapon_ctrl.slots[1] = ""
	weapon_ctrl.clips.erase(wid)
	weapon_ctrl.silenced_state.erase(wid)
	if weapon_ctrl.current_weapon_id == wid:
		if not weapon_ctrl.equip_slot(2):
			weapon_ctrl.equip_slot(3)
	weapon_ctrl.ammo_pool[atype] = keep_reserve

	RoundManager.chat_radio_message.emit(actor_name, team, "(TEAM): Here, take this weapon!")
	if best_rec.is_human:
		RoundManager.center_message.emit("A teammate dropped a weapon for you!", 2.5)

	# Bot recipient: assign the freezetime pickup task so it fetches the gift before rolling out
	var rec_bot := best_rec as CSBot
	if rec_bot != null and is_instance_valid(drop_g):
		rec_bot._pending_share_drop = drop_g


func apply_goldsrc_movement(wish_dir_world: Vector3, want_jump: bool, want_crouch: bool, want_walk: bool, delta: float) -> void:
	var negotiated := traffic.steer(self, wish_dir_world, RoundManager.actors, delta)
	# Authored hostage/VIP approaches may negotiate a wait, never a lateral or
	# reverse detour off their precise staircase, doorway or extraction route.
	var precision_route := is_vip or _hostage_target_idx >= 0 or _is_leading_hostage() or _hostage_direct_active or _vip_escort_direct_active
	if precision_route and traffic.mode in ["sidestep", "yield"]:
		negotiated = Vector3.ZERO
	if traffic.mode in ["wait", "yield", "follow", "sidestep"]:
		want_jump = false
		_stuck_timer = 0.0
		_cur_node_elapsed = 0.0
	if traffic.mode == "retry":
		want_jump = false
	super.apply_goldsrc_movement(negotiated, want_jump, want_crouch, want_walk, delta)

func get_traffic_intent() -> Vector3:
	return traffic.intent

func get_bomb_banned_nodes() -> Dictionary:
	return _banned_nodes

func get_bomb_guard_position(nav: BotNavigator) -> Vector3:
	return nav.get_node_pos(_bomb_role_node) if bomb_role in ["cover", "guard"] and _bomb_role_node >= 0 else Vector3.INF
