class_name WeaponController
extends Node
## Authentic Counter-Strike 1.5 weapon mechanics:
##   - Exact cs_i386.so GetMaxSpeed, cycle_time, damage, armor_ratio, range_modifier
##   - Cubic spray accuracy (shots_fired^3 / 200) + recoil punch kickback
##   - Detachable silencer (M4A1, USP), Glock18 3-round burst, Sniper/Tactical zoom
##   - Pump/Auto shotgun shell-by-shell reload interruptible by firing
##   - Wallbang bullet penetration, Knife slash & 195-dmg backstab, Grenades, C4 plant

signal weapon_switched(weapon_id: String, spec: Dictionary)
signal ammo_updated(clip: int, reserve: int)
signal fired_shot(weapon_id: String, silenced: bool)
signal zoom_changed(fov_deg: float, scoped_overlay: bool)
signal plant_progress_changed(ratio: float)

var actor = null  # CSActor owner (duck-typed to avoid cyclic class_name reference)
var current_weapon_id: String = "knife"
var last_weapon_id: String = "knife"

# Per-weapon state stored on the actor's inventory:
# slots[1] = primary_id or "", slots[2] = secondary_id or "", slots[3] = "knife", slots[5] = "c4" or ""
var slots: Dictionary = {1: "", 2: "", 3: "knife", 5: ""}
var grenades: Dictionary = {"hegrenade": 0, "flashbang": 0, "smokegrenade": 0}
var current_grenade_id: String = ""
var clips: Dictionary = {}
var ammo_pool: Dictionary = {}
var silenced_state: Dictionary = {"m4a1": false, "usp": false}
var burst_state: Dictionary = {"glock18": false}

var zoom_index: int = -1  # -1 = unzoomed (90 deg)
var fire_cooldown: float = 0.0
var reload_timer: float = 0.0
var is_reloading: bool = false
var is_attaching_silencer: bool = false
var shots_fired: int = 0
var decay_timer: float = 0.0
var burst_remaining: int = 0
var burst_tick: float = 0.0
var plant_progress: float = 0.0

var _grenade_pin_pulled: bool = false
var _grenade_pin_timer: float = 0.0
var _grenade_want_release: bool = false
var _grenade_lob_mode: bool = false
var _post_throw_switch_timer: float = 0.0
var _knife_combo_idx: int = 0

# View punch recoil angles (degrees: x=pitch up, y=yaw side)
var punch_angles: Vector2 = Vector2.ZERO


func setup_for_actor(owner_actor: CharacterBody3D) -> void:
	actor = owner_actor


func reset_loadout(team: String, is_vip: bool = false) -> void:
	slots = {1: "", 2: "", 3: "knife", 5: ""}
	grenades = {"hegrenade": 0, "flashbang": 0, "smokegrenade": 0}
	clips.clear()
	ammo_pool.clear()
	_reset_states()

	if is_vip:
		give_weapon("usp", 12, 24)
	elif team == "CT":
		give_weapon("usp", 12, 24)
	else:
		give_weapon("glock18", 20, 40)

	equip_slot(2)


func clear_all_weapons() -> void:
	slots = {1: "", 2: "", 3: "knife", 5: ""}
	grenades = {"hegrenade": 0, "flashbang": 0, "smokegrenade": 0}
	clips.clear()
	ammo_pool.clear()
	_reset_states()
	current_weapon_id = "knife"


func _reset_states() -> void:
	is_reloading = false
	is_attaching_silencer = false
	reload_timer = 0.0
	fire_cooldown = 0.0
	shots_fired = 0
	burst_remaining = 0
	plant_progress = 0.0
	_grenade_pin_pulled = false
	_grenade_pin_timer = 0.0
	_grenade_want_release = false
	_grenade_lob_mode = false
	_post_throw_switch_timer = 0.0
	punch_angles = Vector2.ZERO
	_clear_zoom()


func give_weapon(wid: String, start_clip: int = -1, bonus_reserve: int = 0) -> void:
	if not GameData.weapons.has(wid):
		return
	var spec: Dictionary = GameData.weapons[wid]
	if bool(spec.get("grenade", false)):
		var max_g := int(spec.get("max_ammo", 1))
		grenades[wid] = mini(max_g, int(grenades.get(wid, 0)) + 1)
		return

	var sl := int(spec.get("slot", 1))
	slots[sl] = wid
	var csize := int(spec.get("clip_size", -1))
	if csize > 0:
		clips[wid] = start_clip if start_clip >= 0 else csize
	var atype := String(spec.get("ammo_type", "none"))
	if atype != "none" and bonus_reserve > 0:
		var max_a := int(spec.get("max_ammo", 90))
		ammo_pool[atype] = mini(max_a, int(ammo_pool.get(atype, 0)) + bonus_reserve)


func get_current_spec() -> Dictionary:
	return GameData.weapons.get(current_weapon_id, GameData.weapons.get("knife", {}))


func get_max_speed_gs() -> float:
	var spec := get_current_spec()
	if zoom_index >= 0:
		return float(spec.get("zoomed_speed", spec.get("max_speed", 250.0)))
	return float(spec.get("max_speed", 250.0))


func get_clip_and_reserve() -> Vector2i:
	var spec := get_current_spec()
	if bool(spec.get("grenade", false)):
		return Vector2i(int(grenades.get(current_weapon_id, 0)), 0)
	var csize := int(spec.get("clip_size", -1))
	if csize < 0:
		return Vector2i(-1, -1)
	var atype := String(spec.get("ammo_type", "none"))
	return Vector2i(int(clips.get(current_weapon_id, 0)), int(ammo_pool.get(atype, 0)))


func equip_slot(slot_num: int) -> bool:
	if slot_num == 4:
		var order := ["hegrenade", "flashbang", "smokegrenade"]
		var start_i := 0
		if current_weapon_id in order:
			start_i = (order.find(current_weapon_id) + 1) % order.size()
		for k in range(order.size()):
			var gid: String = order[(start_i + k) % order.size()]
			if int(grenades.get(gid, 0)) > 0:
				return equip_weapon_by_id(gid)
		return false

	var wid := String(slots.get(slot_num, ""))
	if wid.is_empty():
		return false
	return equip_weapon_by_id(wid)


func equip_weapon_by_id(wid: String) -> bool:
	if wid.is_empty() or not GameData.weapons.has(wid):
		return false
	if wid != current_weapon_id:
		last_weapon_id = current_weapon_id
	current_weapon_id = wid
	_reset_states()
	fire_cooldown = 0.65  # CS 1.5 deploy delay

	var spec := get_current_spec()
	var v_name := String(spec.get("v_model", "v_" + current_weapon_id))
	var has_draw_ev := _viewmodel_has_events(v_name, "draw") or _viewmodel_has_events(v_name, "deploy")
	var dep := String(spec.get("deploy_sound", ""))
	if not dep.is_empty() and is_instance_valid(actor) and (not bool(actor.get("is_human")) or not has_draw_ev):
		AudioManager.play_3d(dep, actor.global_position, -5.0, 16.0)

	weapon_switched.emit(current_weapon_id, spec)
	_emit_ammo()
	return true


func _viewmodel_has_events(v_name: String, seq_prefix: String) -> bool:
	var mmeta: Dictionary = GameData.models_meta.get("weapons/" + v_name, {})
	var evs: Dictionary = mmeta.get("seq_events", {})
	for k in evs.keys():
		if String(k).to_lower().begins_with(seq_prefix.to_lower()):
			return true
	return false


func _get_viewmodel_seq_duration(v_name: String, seq_name: String, fallback: float) -> float:
	var mmeta: Dictionary = GameData.models_meta.get("weapons/" + v_name, {})
	var durs: Dictionary = mmeta.get("seq_durations", {})
	if durs.has(seq_name):
		return maxf(0.35, float(durs[seq_name]))
	for k in durs.keys():
		if String(k).to_lower().begins_with(seq_name.to_lower()):
			return maxf(0.35, float(durs[k]))
	return fallback


func quick_switch_last() -> void:
	if last_weapon_id.is_empty() or last_weapon_id == current_weapon_id:
		return
	var spec: Dictionary = GameData.weapons.get(last_weapon_id, {})
	if bool(spec.get("grenade", false)):
		if int(grenades.get(last_weapon_id, 0)) > 0:
			equip_weapon_by_id(last_weapon_id)
		return
	var sl := int(spec.get("slot", 3))
	if String(slots.get(sl, "")) == last_weapon_id:
		equip_weapon_by_id(last_weapon_id)


func _clear_zoom() -> void:
	if zoom_index != -1:
		zoom_index = -1
		zoom_changed.emit(GameData.fov, false)


func _emit_ammo() -> void:
	var cr := get_clip_and_reserve()
	ammo_updated.emit(cr.x, cr.y)


func _process(delta: float) -> void:
	if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
		return

	# Smooth recoil punch recovery
	punch_angles = punch_angles.move_toward(Vector2.ZERO, 22.0 * delta)

	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	# Delayed switch after grenade throw so player sees the full 'throw' viewmodel animation!
	if _post_throw_switch_timer > 0.0:
		_post_throw_switch_timer -= delta
		if _post_throw_switch_timer <= 0.0:
			var prev_gid := current_weapon_id
			if int(grenades.get(prev_gid, 0)) > 0:
				equip_weapon_by_id(prev_gid)
			elif not equip_slot(1):
				if not equip_slot(2):
					if not equip_slot(4):
						equip_slot(3)
		return

	# Grenade pin-pull -> release throw state machine
	if _grenade_pin_pulled:
		_grenade_pin_timer = maxf(0.0, _grenade_pin_timer - delta)
		if _grenade_want_release and _grenade_pin_timer <= 0.0:
			_grenade_pin_pulled = false
			_grenade_want_release = false
			_launch_grenade_now(current_weapon_id)
			return

	# Burst-fire follow-up shots (Glock18)
	if burst_remaining > 0:
		burst_tick -= delta
		if burst_tick <= 0.0:
			burst_remaining -= 1
			burst_tick = 0.055
			_execute_bullet_shot(get_current_spec(), true)

	# Decay shots_fired when not shooting
	if fire_cooldown <= 0.0 and shots_fired > 0:
		decay_timer += delta
		if decay_timer >= 0.22:
			decay_timer = 0.0
			shots_fired = maxi(0, shots_fired - 2)

	# Reloading / Silencer toggle timer
	if is_reloading or is_attaching_silencer:
		reload_timer -= delta
		if reload_timer <= 0.0:
			if is_attaching_silencer:
				is_attaching_silencer = false
				silenced_state[current_weapon_id] = not bool(silenced_state.get(current_weapon_id, false))
				weapon_switched.emit(current_weapon_id, get_current_spec())
			elif is_reloading:
				_finish_reload_step()

	# Decay C4 plant progress if player released fire
	if current_weapon_id != "c4" and plant_progress > 0.0:
		plant_progress = 0.0
		plant_progress_changed.emit(0.0)


func trigger_primary(holding: bool, delta: float) -> void:
	if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
		return
	if _post_throw_switch_timer > 0.0:
		return
	var spec := get_current_spec()

	# C4 Planting on Bombsite during LIVE round
	if current_weapon_id == "c4":
		if RoundManager.state != RoundManager.State.LIVE:
			return
		if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_bombsite"):
			var act_body := actor as CharacterBody3D
			if bool(RoundManager.game_world.call("is_in_bombsite", act_body.global_position)) and act_body.is_on_floor():
				if plant_progress == 0.0:
					AudioManager.play_3d("weapons/c4_click.wav", actor.global_position, -2.0, 18.0)
					if actor.has_method("play_viewmodel_sequence"):
						actor.call("play_viewmodel_sequence", ["pressbutton"])
				plant_progress += delta
				plant_progress_changed.emit(clampf(plant_progress / 3.0, 0.0, 1.0))
				if plant_progress >= 3.0:
					plant_progress = 0.0
					plant_progress_changed.emit(0.0)
					_complete_c4_plant()
				return
		plant_progress = 0.0
		plant_progress_changed.emit(0.0)
		return

	if RoundManager.is_movement_frozen():
		return

	# Grenade hold-pin / release-throw for human player (instant throw for AI bots)
	if bool(spec.get("grenade", false)):
		if _grenade_pin_pulled:
			return
		if is_reloading or fire_cooldown > 0.0:
			return
		if int(grenades.get(current_weapon_id, 0)) <= 0:
			return
		if bool(actor.get("is_human")):
			_grenade_pin_pulled = true
			_grenade_pin_timer = 0.36
			_grenade_want_release = false
			_grenade_lob_mode = false
			AudioManager.play_3d("weapons/pinpull.wav", actor.global_position, -3.0, 14.0)
			if actor.has_method("play_viewmodel_sequence"):
				actor.call("play_viewmodel_sequence", ["pullpin"])
		else:
			_throw_grenade(current_weapon_id)
		return

	# Interruptible shotgun reload!
	if is_reloading and bool(spec.get("shotgun_reload", false)) and int(clips.get(current_weapon_id, 0)) > 0:
		is_reloading = false
		reload_timer = 0.0

	if is_reloading or is_attaching_silencer or fire_cooldown > 0.0:
		return
	if holding and not bool(spec.get("automatic", false)) and current_weapon_id != "knife":
		return

	if current_weapon_id == "knife":
		_swing_knife(false)
		return

	var cur_clip := int(clips.get(current_weapon_id, 0))
	if cur_clip <= 0:
		var dry := "weapons/dryfire_pistol.wav" if int(spec.get("slot", 1)) == 2 else "weapons/dryfire_rifle.wav"
		AudioManager.play_3d(dry, actor.global_position, -4.0, 14.0)
		fire_cooldown = 0.25
		start_reload()
		return

	# Glock18 3-round burst mode
	if current_weapon_id == "glock18" and bool(burst_state.get("glock18", false)):
		_execute_bullet_shot(spec, true)
		burst_remaining = mini(2, int(clips.get("glock18", 0)))
		burst_tick = 0.055
		fire_cooldown = 0.5
		return

	_execute_bullet_shot(spec, false)


func release_primary() -> void:
	if _grenade_pin_pulled and not _grenade_lob_mode:
		_grenade_want_release = true
		if _grenade_pin_timer <= 0.0:
			_grenade_pin_pulled = false
			_grenade_want_release = false
			_launch_grenade_now(current_weapon_id)
	if plant_progress > 0.0:
		plant_progress = 0.0
		plant_progress_changed.emit(0.0)
		if current_weapon_id == "c4" and is_instance_valid(actor) and actor.has_method("play_viewmodel_sequence"):
			actor.call("play_viewmodel_sequence", ["idle1", "idle"])


func release_secondary() -> void:
	if _grenade_pin_pulled and _grenade_lob_mode:
		_grenade_want_release = true
		if _grenade_pin_timer <= 0.0:
			_grenade_pin_pulled = false
			_grenade_want_release = false
			_launch_grenade_now(current_weapon_id)


func trigger_secondary() -> void:
	if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
		return
	if is_reloading or is_attaching_silencer or fire_cooldown > 0.0 or _post_throw_switch_timer > 0.0:
		return

	var spec := get_current_spec()
	if bool(spec.get("grenade", false)):
		if RoundManager.is_movement_frozen() or _grenade_pin_pulled:
			return
		if int(grenades.get(current_weapon_id, 0)) <= 0:
			return
		_grenade_pin_pulled = true
		_grenade_pin_timer = 0.32
		_grenade_want_release = false
		_grenade_lob_mode = true
		AudioManager.play_3d("weapons/pinpull.wav", actor.global_position, -3.0, 14.0)
		if actor.has_method("play_viewmodel_sequence"):
			actor.call("play_viewmodel_sequence", ["pullpin"])
		return

	if current_weapon_id == "knife":
		if not RoundManager.is_movement_frozen():
			_swing_knife(true)
		return

	# Detachable silencer (M4A1, USP)
	if bool(spec.get("silencer", false)):
		is_attaching_silencer = true
		var cur_sil := bool(silenced_state.get(current_weapon_id, false))
		var target_anim := "detach_silencer" if cur_sil else "add_silencer"
		var v_name := String(spec.get("v_model", "v_" + current_weapon_id))
		reload_timer = _get_viewmodel_seq_duration(v_name, target_anim, 2.4)
		if not bool(actor.get("is_human")) or not _viewmodel_has_events(v_name, target_anim):
			var swav := ""
			if current_weapon_id == "m4a1":
				swav = "weapons/m4a1_silencer_off.wav" if cur_sil else "weapons/m4a1_silencer_on.wav"
			else:
				swav = "weapons/usp_silencer_off.wav" if cur_sil else "weapons/usp_silencer_on.wav"
			AudioManager.play_3d(swav, actor.global_position, -3.0, 16.0)
		if actor.has_method("play_viewmodel_sequence"):
			actor.call("play_viewmodel_sequence", [target_anim])
		return

	# Glock18 burst fire toggle
	if bool(spec.get("burst", false)):
		var next_b := not bool(burst_state.get(current_weapon_id, false))
		burst_state[current_weapon_id] = next_b
		fire_cooldown = 0.25
		if actor.get("is_human"):
			RoundManager.center_message.emit(
				"Switched to burst-fire mode" if next_b else "Switched to semi-automatic", 1.5
			)
		return

	# Sniper / AUG / SG552 Scope Zoom
	var zfovs: Array = spec.get("zoom_fovs", [])
	if not zfovs.is_empty():
		zoom_index += 1
		if zoom_index >= zfovs.size():
			_clear_zoom()
		else:
			var fdeg := float(zfovs[zoom_index])
			zoom_changed.emit(fdeg, bool(spec.get("sniper_scope", false)))
		AudioManager.play_3d("weapons/zoom.wav", actor.global_position, -4.0, 14.0)
		fire_cooldown = 0.22


func clear_zoom() -> void:
	_clear_zoom()


func start_reload() -> void:
	if is_reloading or is_attaching_silencer:
		return
	var spec := get_current_spec()
	var csize := int(spec.get("clip_size", -1))
	if csize <= 0 or bool(spec.get("grenade", false)):
		return
	var cur := int(clips.get(current_weapon_id, 0))
	var atype := String(spec.get("ammo_type", "none"))
	var res := int(ammo_pool.get(atype, 0))
	if cur >= csize or res <= 0:
		return

	_clear_zoom()
	is_reloading = true
	var v_name := String(spec.get("v_model", "v_" + current_weapon_id))
	var sil := bool(silenced_state.get(current_weapon_id, false))
	var rel_anim := "reload" if (sil or not bool(spec.get("silencer", false))) else "reload_unsil"
	if bool(spec.get("shotgun_reload", false)):
		reload_timer = 0.52
	else:
		reload_timer = _get_viewmodel_seq_duration(v_name, rel_anim, float(spec.get("reload_time", 2.5)))

	var rwav := String(spec.get("reload_sound", ""))
	var human_has_ev := bool(actor.get("is_human")) and _viewmodel_has_events(v_name, rel_anim)
	if not rwav.is_empty() and is_instance_valid(actor) and not human_has_ev:
		AudioManager.play_3d(rwav, actor.global_position, -3.5, 18.0, 1.0, 12.0, String(actor.get("team")))
	elif human_has_ev and is_instance_valid(actor):
		# Emit audible world cue so nearby enemy Bots can still hear human reloads!
		AudioManager.world_sound_emitted.emit(actor.global_position, 12.0, String(actor.get("team")))

	if is_instance_valid(actor) and actor.has_method("trigger_upper_body_action"):
		actor.call("trigger_upper_body_action", "reload")

	if actor.has_method("play_viewmodel_sequence"):
		if bool(spec.get("shotgun_reload", false)):
			actor.call("play_viewmodel_sequence", ["start_reload", "reload"])
		else:
			if bool(spec.get("silencer", false)) and not sil:
				actor.call("play_viewmodel_sequence", ["reload_unsil", "reload"])
			else:
				actor.call("play_viewmodel_sequence", ["reload"])


func _finish_reload_step() -> void:
	var spec := get_current_spec()
	var csize := int(spec.get("clip_size", 30))
	var atype := String(spec.get("ammo_type", "none"))
	var cur := int(clips.get(current_weapon_id, 0))
	var res := int(ammo_pool.get(atype, 0))

	if bool(spec.get("shotgun_reload", false)):
		if cur < csize and res > 0:
			clips[current_weapon_id] = cur + 1
			ammo_pool[atype] = res - 1
			_emit_ammo()
			if actor.has_method("play_viewmodel_sequence"):
				actor.call("play_viewmodel_sequence", ["insert"])
			if cur + 1 < csize and res - 1 > 0:
				reload_timer = 0.48
				AudioManager.play_3d("weapons/m3_insertshell.wav", actor.global_position, -4.0, 16.0)
				return
		is_reloading = false
		if actor.has_method("play_viewmodel_sequence"):
			actor.call("play_viewmodel_sequence", ["after_reload"])
		AudioManager.play_3d("weapons/m3_pump.wav", actor.global_position, -4.0, 16.0)
		return

	var needed := mini(csize - cur, res)
	clips[current_weapon_id] = cur + needed
	ammo_pool[atype] = res - needed
	is_reloading = false
	_emit_ammo()


func _execute_bullet_shot(spec: Dictionary, is_burst_subshot: bool) -> void:
	var cur_clip := int(clips.get(current_weapon_id, 0))
	if cur_clip <= 0:
		return
	clips[current_weapon_id] = cur_clip - 1
	shots_fired += 1
	decay_timer = 0.0

	var ctime := float(spec.get("cycle_time", 0.1))
	if zoom_index >= 0 and spec.has("zoomed_cycle_time"):
		ctime = float(spec["zoomed_cycle_time"])
	if not is_burst_subshot:
		fire_cooldown = ctime

	var is_sil := bool(silenced_state.get(current_weapon_id, false)) and bool(spec.get("silencer", false))
	var wav_list: Array = spec.get("silenced_sounds", []) if is_sil else spec.get("fire_sounds", [])
	if wav_list.is_empty():
		wav_list = spec.get("fire_sounds", [])
	if not wav_list.is_empty():
		var wpath := String(wav_list[randi() % wav_list.size()])
		var hear_r := 14.0 if (is_sil or bool(spec.get("quiet", false))) else 52.0
		var vol := -2.5 if is_sil else 1.5
		AudioManager.play_3d(wpath, actor.global_position, vol, 70.0, randf_range(0.98, 1.02), hear_r, String(actor.get("team")))

	fired_shot.emit(current_weapon_id, is_sil)
	if is_instance_valid(actor) and actor.has_method("trigger_upper_body_action"):
		actor.call("trigger_upper_body_action", "shoot")
	_spawn_brass_casing(spec)
	_emit_ammo()

	# Calculate authentic CS 1.5 spread
	var spread := float(spec.get("spread_base", 0.01))
	if bool(spec.get("sniper_scope", false)) and zoom_index == -1:
		spread = float(spec.get("spread_unscoped", 0.06))
	var horiz_spd := Vector2(actor.velocity.x, actor.velocity.z).length() / GameData.SCALE
	if horiz_spd > 15.0:
		spread += float(spec.get("spread_move", 0.07)) * clampf(horiz_spd / 220.0, 0.2, 1.35)
	if not actor.is_on_floor():
		spread *= 2.35
	elif bool(actor.get("is_crouching")):
		spread *= 0.68

	# Cubic spray inaccuracy from cs_i386.so!
	var cubic := float(shots_fired * shots_fired * shots_fired) / 210.0
	spread += clampf(cubic * 0.0085, 0.0, 0.075)

	var pellets := int(spec.get("pellets", 1))
	var base_dmg := float(spec.get("silenced_damage", spec.get("damage", 30))) if is_sil else float(spec.get("damage", 30))
	var armor_ratio := float(spec.get("armor_ratio", 1.2))
	var max_range_m := float(spec.get("range", 4096.0)) * GameData.SCALE
	var range_mod := float(spec.get("range_modifier", 0.95))
	var pen := int(spec.get("penetration", 1))

	var eye_pos: Vector3 = actor.call("get_eye_position")
	var aim_basis: Basis = actor.call("get_aim_basis", punch_angles)

	for _p in range(pellets):
		var rx := randfn(0.0, spread)
		var ry := randfn(0.0, spread)
		var dir := (-aim_basis.z + aim_basis.x * rx + aim_basis.y * ry).normalized()
		_fire_penetrating_ray(eye_pos, dir, max_range_m, base_dmg, armor_ratio, range_mod, pen)

	# Apply KickBack view punch
	var up_kick := float(spec.get("recoil_up", 1.8))
	var lat_kick := float(spec.get("recoil_lat", 0.5))
	punch_angles.x = clampf(punch_angles.x + up_kick, -14.0, 16.0)
	punch_angles.y = clampf(punch_angles.y + randf_range(-lat_kick, lat_kick), -7.0, 7.0)

	# Bolt-action sniper unzooms briefly after shot just like CS 1.5!
	if current_weapon_id in ["awp", "scout"] and zoom_index >= 0:
		_clear_zoom()


func _fire_penetrating_ray(
	origin: Vector3,
	dir: Vector3,
	max_dist: float,
	base_dmg: float,
	armor_ratio: float,
	range_mod: float,
	pen_left: int
) -> void:
	var space: PhysicsDirectSpaceState3D = (actor as Node3D).get_world_3d().direct_space_state
	var cur_from: Vector3 = origin
	var cur_dmg: float = base_dmg
	var rem_dist: float = max_dist
	var exclude_rids: Array[RID] = [(actor as CollisionObject3D).get_rid()]
	var tracer_spawned := false
	var is_heavy_cal: bool = (base_dmg >= 48.0 or current_weapon_id in ["awp", "scout", "g3sg1", "sg550", "deagle", "m249"])
	var cal_scale: float = clampf(base_dmg / 30.0, 0.78, 1.45)

	for _hop in range(pen_left + 2):
		if rem_dist <= 0.1 or cur_dmg <= 1.0:
			break
		var ray_end: Vector3 = cur_from + dir * rem_dist
		var q := PhysicsRayQueryParameters3D.create(cur_from, ray_end)
		q.collision_mask = 1 | 2 | 4 | 8  # World (1) + Actors/Hostages (2) + Dropped Weapons (4) + Metal Ladders/Grates (8)
		q.exclude = exclude_rids
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			if not tracer_spawned and is_instance_valid(RoundManager.game_world):
				tracer_spawned = true
				ImpactEffects.spawn_bullet_tracer(RoundManager.game_world, _get_tracer_origin(origin, dir), origin + dir * minf(max_dist, 44.0), is_heavy_cal)
			RoundManager.apply_world_bullet_wake(cur_from, ray_end, clampf(base_dmg / 30.0, 0.5, 2.0))
			break

		var hit_pos: Vector3 = hit["position"]
		var hit_nrm: Vector3 = hit["normal"]
		if not tracer_spawned and is_instance_valid(RoundManager.game_world):
			tracer_spawned = true
			ImpactEffects.spawn_bullet_tracer(RoundManager.game_world, _get_tracer_origin(origin, dir), hit_pos, is_heavy_cal)

		RoundManager.apply_world_bullet_wake(cur_from, hit_pos, clampf(base_dmg / 30.0, 0.5, 2.0))
		var traveled_gs := origin.distance_to(hit_pos) / GameData.SCALE
		var dmg_at_dist := cur_dmg * pow(range_mod, traveled_gs / 500.0)
		var col = hit["collider"]

		if col is DroppedWeapon:
			(col as DroppedWeapon).apply_bullet_impulse(hit_pos, dir, dmg_at_dist)
			if is_instance_valid(RoundManager.game_world):
				ImpactEffects.spawn_surface_impact(RoundManager.game_world, hit_pos, hit_nrm, dir, "M", 0.85, col as Node3D)
			exclude_rids.append((col as CollisionObject3D).get_rid())
			cur_dmg *= 0.82
			var step_dw := origin.distance_to(hit_pos)
			rem_dist = max_dist - step_dw
			cur_from = hit_pos + dir * 0.08
			continue

		if col is Node3D and col.has_method("take_bullet_damage"):
			var hgroup := _determine_hitgroup(col, hit_pos)
			var is_friendly := (String(col.get("team")) == String(actor.get("team"))) and not GameData.friendly_fire
			var armored_hd := (hgroup == 1 and bool(col.get("has_helmet")) and int(col.get("armor")) > 0)
			if not is_friendly and is_instance_valid(RoundManager.game_world):
				ImpactEffects.spawn_blood_impact(RoundManager.game_world, space, hit_pos, dir, hgroup, armored_hd, dmg_at_dist)
			col.call("take_bullet_damage", actor, dmg_at_dist, armor_ratio, hgroup, current_weapon_id, hit_pos)
			exclude_rids.append((col as CollisionObject3D).get_rid())
			cur_dmg *= 0.65
			var step := origin.distance_to(hit_pos)
			rem_dist = max_dist - step
			cur_from = hit_pos + dir * 0.25
			continue

		if col is HostageNPC:
			if is_instance_valid(RoundManager.game_world):
				ImpactEffects.spawn_blood_impact(RoundManager.game_world, space, hit_pos, dir, 2, false, dmg_at_dist)
			(col as HostageNPC).take_damage(actor, dmg_at_dist)
			break

		# Layer 8 visual metal ladder / grate brush: spark & clank on metal rung, and let bullet pass through gaps!
		if col is StaticBody3D and (col as StaticBody3D).collision_layer == 8:
			var sb_col := col as StaticBody3D
			var lmat := String(sb_col.get_meta("surface_mat")) if sb_col.has_meta("surface_mat") else "L"
			_spawn_surface_hit_fx(hit_pos, hit_nrm, dir, sb_col, lmat, cal_scale)
			exclude_rids.append(sb_col.get_rid())
			cur_dmg *= 0.90
			cur_from = hit_pos + dir * 0.06
			rem_dist = max_dist - origin.distance_to(cur_from)
			continue

		# World, BSPDoor, or func_breakable impact
		var attach_target: Node3D = null
		var mat_override := ""
		var shattered_now := false
		if col is Node:
			if col.has_meta("breakable"):
				var brk = col.get_meta("breakable")
				if is_instance_valid(brk):
					attach_target = brk as Node3D
					if brk.has_method("apply_damage"):
						brk.apply_damage(dmg_at_dist, hit_pos)
					shattered_now = bool(brk.get("broken"))
			elif col.has_meta("door"):
				var dr_node = col.get_meta("door")
				if is_instance_valid(dr_node):
					attach_target = dr_node as Node3D
					mat_override = "M"

		var surf_char := _sample_collider_material(col, mat_override)
		if not shattered_now:
			_spawn_surface_hit_fx(hit_pos, hit_nrm, dir, attach_target, surf_char, cal_scale)
		else:
			# Bullet smashed right through fragile glass window / crate panel and continues!
			exclude_rids.append((col as CollisionObject3D).get_rid())
			cur_dmg *= 0.85
			cur_from = hit_pos + dir * 0.08
			rem_dist = max_dist - origin.distance_to(cur_from)
			continue

		# CS 1.5 Wallbanging: test thin wall exit within 0.65m (~21 GoldSrc units)
		if pen_left <= 0:
			break
		var probe_start: Vector3 = hit_pos + dir * 0.62
		var back_q := PhysicsRayQueryParameters3D.create(probe_start, hit_pos + dir * 0.02)
		back_q.collision_mask = 1
		var exit_hit: Dictionary = space.intersect_ray(back_q)
		if exit_hit.is_empty():
			break  # Wall thicker than penetration depth
		# Spawn exit bullet hole & puff on the back side of thin wall/door/crate!
		if is_instance_valid(RoundManager.game_world):
			ImpactEffects.spawn_surface_impact(RoundManager.game_world, exit_hit["position"], exit_hit["normal"], dir, surf_char, cal_scale * 0.85, attach_target)
		pen_left -= 1
		cur_dmg *= 0.55
		cur_from = exit_hit["position"] + dir * 0.05
		rem_dist = max_dist - origin.distance_to(cur_from)


func _determine_hitgroup(target: Node3D, hit_pos: Vector3) -> int:
	var rel_y := hit_pos.y - target.global_position.y
	var full_h := 1.35 if bool(target.get("is_crouching")) else 2.05
	var ratio := rel_y / full_h
	if ratio >= 0.77:
		return 1  # HEADSHOT!
	elif ratio >= 0.52:
		return 2  # Chest / Arms
	elif ratio >= 0.34:
		return 3  # Stomach
	return 4  # Legs


func _get_tracer_origin(eye_pos: Vector3, shot_dir: Vector3) -> Vector3:
	var aim_b: Basis = actor.call("get_aim_basis", punch_angles)
	var hand_sign: float = 1.0 if GameData.right_hand else -1.0
	if not bool(actor.get("is_human")):
		hand_sign = 1.0
	return eye_pos + aim_b.x * (0.16 * hand_sign) - aim_b.y * 0.10 + shot_dir * 0.35


func _sample_collider_material(col: Variant, fallback_char: String = "") -> String:
	if col is Node:
		var cnode := col as Node
		if cnode.has_meta("surface_mat"):
			return String(cnode.get_meta("surface_mat"))
		var p := cnode.get_parent()
		if p is MeshInstance3D:
			var mi := p as MeshInstance3D
			if mi.mesh and mi.mesh.get_surface_count() > 0:
				var m := mi.get_surface_override_material(0)
				if not m:
					m = mi.mesh.surface_get_material(0)
				if m:
					var mname := m.resource_name.to_lower()
					if "ladder" in mname or "rung" in mname:
						return "L"
					if "secdr" in mname or "fifties_dr" in mname or "babtech" in mname or "metal" in mname or "steel" in mname or "silo" in mname or "duct" in mname:
						return "M"
					if "wood" in mname or "crate" in mname or "plank" in mname or "cardbox" in mname:
						return "W"
					if "glass" in mname or "skkylite" in mname:
						return "Y"
					if "sand" in mname or "dust" in mname or "dirt" in mname or "ground" in mname or "mud" in mname or "grass" in mname:
						return "D"
					return GameData.get_material_char(m.resource_name)
	return fallback_char if not fallback_char.is_empty() else "C"


func _spawn_surface_hit_fx(
	pos: Vector3,
	normal: Vector3,
	bullet_dir: Vector3,
	attach_node: Node3D,
	surf_char: String,
	cal_scale: float
) -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	ImpactEffects.spawn_surface_impact(RoundManager.game_world, pos, normal, bullet_dir, surf_char, cal_scale, attach_node)

	if surf_char in ["M", "V", "L", "G"]:
		if randf() < 0.72:
			AudioManager.play_3d("weapons/ric_metal-%d.wav" % randi_range(1, 2), pos, -5.5, 22.0, randf_range(0.94, 1.08))
	elif surf_char in ["C", "T"]:
		if randf() < 0.42:
			var rwav := ("weapons/ric_conc-%d.wav" % randi_range(1, 2)) if randf() < 0.55 else ("weapons/ric%d.wav" % randi_range(1, 5))
			AudioManager.play_3d(rwav, pos, -7.5, 19.0, randf_range(0.95, 1.06))


func _swing_knife(heavy_stab: bool) -> void:
	var spec := get_current_spec()
	fire_cooldown = float(spec.get("alt_cycle_time", 1.1)) if heavy_stab else float(spec.get("cycle_time", 0.4))
	var reach := (float(spec.get("alt_range", 36.0)) if heavy_stab else float(spec.get("range", 52.0))) * GameData.SCALE

	var eye: Vector3 = actor.call("get_eye_position")
	var aim_b: Basis = actor.call("get_aim_basis", Vector2.ZERO)
	var dir: Vector3 = -aim_b.z
	var space: PhysicsDirectSpaceState3D = (actor as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * reach)
	q.collision_mask = 1 | 2 | 4 | 8
	q.exclude = [(actor as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	var did_hit := not hit.is_empty()

	if is_instance_valid(actor) and actor.has_method("trigger_upper_body_action"):
		actor.call("trigger_upper_body_action", "shoot")

	if actor.has_method("play_viewmodel_sequence"):
		if heavy_stab:
			actor.call("play_viewmodel_sequence", ["stab"] if did_hit else ["stab_miss", "stab"])
		else:
			var slashes := ["midslash1", "midslash2", "slash1", "slash2"]
			var pick: String = slashes[_knife_combo_idx % slashes.size()]
			_knife_combo_idx += 1
			actor.call("play_viewmodel_sequence", [pick, "slash1", "slash2"])

	if not did_hit:
		AudioManager.play_3d("weapons/knife_slash%d.wav" % randi_range(1, 2), actor.global_position, -3.0, 14.0)
		return

	var col = hit["collider"]
	var hpos: Vector3 = hit["position"]
	if col is DroppedWeapon:
		(col as DroppedWeapon).apply_bullet_impulse(hpos, dir, 55.0 if heavy_stab else 28.0)
		return
	if col is Node3D and col.has_method("take_bullet_damage"):
		var dmg := 65.0 if heavy_stab else 20.0
		if heavy_stab:
			var target_fwd: Vector3 = (col.call("get_look_forward") as Vector3) if col.has_method("get_look_forward") else (-(col as Node3D).global_transform.basis.z)
			var flat_tf := Vector3(target_fwd.x, 0.0, target_fwd.z)
			var flat_dir := Vector3(dir.x, 0.0, dir.z)
			if flat_tf.length_squared() > 0.001 and flat_dir.length_squared() > 0.001:
				if flat_dir.normalized().dot(flat_tf.normalized()) > 0.45:
					dmg = 195.0  # Classic CS 1.5 Backstab!
		if (String(col.get("team")) != String(actor.get("team")) or GameData.friendly_fire) and is_instance_valid(RoundManager.game_world):
			ImpactEffects.spawn_blood_impact(RoundManager.game_world, space, hpos, dir, 2, false, dmg)
		col.call("take_bullet_damage", actor, dmg, 1.7, 2, "knife", hpos)
		var kwav := "weapons/knife_stab.wav" if heavy_stab else ("weapons/knife_hit%d.wav" % randi_range(1, 4))
		AudioManager.play_3d(kwav, hpos, 0.0, 20.0)
		return

	var attach_k: Node3D = null
	var k_override := ""
	if col is Node and col.has_meta("breakable"):
		var brk = col.get_meta("breakable")
		if is_instance_valid(brk):
			attach_k = brk as Node3D
			if brk.has_method("apply_damage"):
				brk.apply_damage(45.0 if heavy_stab else 20.0, hpos)
	elif col is Node and col.has_meta("door"):
		var dr_k = col.get_meta("door")
		if is_instance_valid(dr_k):
			attach_k = dr_k as Node3D
			k_override = "M"

	if is_instance_valid(RoundManager.game_world):
		var k_surf := _sample_collider_material(col, k_override)
		ImpactEffects.spawn_surface_impact(RoundManager.game_world, hpos, hit["normal"], dir, k_surf, 0.72, attach_k)

	AudioManager.play_3d("weapons/knife_hitwall1.wav", hpos, -3.0, 16.0)


func _throw_grenade(gid: String) -> void:
	AudioManager.play_3d("weapons/pinpull.wav", actor.global_position, -3.0, 14.0)
	_launch_grenade_now(gid)


func _launch_grenade_now(gid: String) -> void:
	var count := int(grenades.get(gid, 0))
	if count <= 0 or not is_instance_valid(RoundManager.game_world):
		return
	grenades[gid] = count - 1
	fire_cooldown = 0.75
	_emit_ammo()

	if actor.has_method("play_viewmodel_sequence"):
		actor.call("play_viewmodel_sequence", ["throw"])
	if is_instance_valid(actor) and actor.has_method("trigger_upper_body_action"):
		actor.call("trigger_upper_body_action", "shoot")

	AudioManager.play_radio("radio/ct_fireinhole.wav")
	RoundManager.chat_radio_message.emit(String(actor.get("actor_name")), String(actor.get("team")), "(RADIO): Fire in the hole!")

	var eye: Vector3 = actor.call("get_eye_position")
	var aim_b: Basis = actor.call("get_aim_basis", Vector2.ZERO)
	var fwd: Vector3 = -aim_b.z
	var proj := GrenadeProjectile.new()
	RoundManager.game_world.add_child(proj)
	proj.global_position = eye + fwd * 0.42
	var actor_vel: Vector3 = (actor as CharacterBody3D).velocity
	var speed_throw: float = 12.2 if _grenade_lob_mode else 21.5
	var up_lift: float = 1.95 if _grenade_lob_mode else 2.6
	_grenade_lob_mode = false
	var throw_v: Vector3 = fwd * speed_throw + Vector3(0.0, up_lift, 0.0) + actor_vel * 0.48
	proj.setup_grenade(gid, actor, throw_v)

	if bool(actor.get("is_human")):
		_post_throw_switch_timer = 0.30
	else:
		if not equip_slot(1):
			if not equip_slot(2):
				equip_slot(3)


func _spawn_brass_casing(spec: Dictionary) -> void:
	if not is_instance_valid(RoundManager.game_world) or not is_instance_valid(actor):
		return
	var sl := int(spec.get("slot", 1))
	if sl not in [1, 2]:
		return
	var shell_mdl := "rshell"
	if bool(spec.get("shotgun_reload", false)):
		shell_mdl = "rshell_big"
	elif sl == 2 or float(spec.get("max_speed", 220.0)) >= 245.0:
		shell_mdl = "pshell"

	var eye_p: Vector3 = actor.call("get_eye_position")
	var aim_b: Basis = actor.call("get_aim_basis", Vector2.ZERO)
	var side_sign := 1.0 if (not bool(actor.get("is_human")) or GameData.right_hand) else -1.0
	var start_pos := eye_p + (-aim_b.z * 0.36) + (aim_b.x * 0.22 * side_sign) - (aim_b.y * 0.12)
	var act_vel: Vector3 = (actor as CharacterBody3D).velocity
	var eject_vel: Vector3 = (
		aim_b.x * randf_range(2.3, 3.7) * side_sign
		+ Vector3(0.0, randf_range(1.6, 2.7), 0.0)
		- aim_b.z * randf_range(-0.5, 0.8)
		+ act_vel * 0.42
	)
	var delay_s := 0.42 if current_weapon_id in ["awp", "scout", "m3"] else 0.0
	ImpactEffects.spawn_physical_shell(RoundManager.game_world, shell_mdl, start_pos, eject_vel, delay_s)


func _complete_c4_plant() -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	slots[5] = ""
	var c4 := PlantedC4.new()
	c4.position = (actor as Node3D).global_position + Vector3(0, 0.04, 0)
	RoundManager.game_world.add_child(c4)
	RoundManager.notify_bomb_planted(c4, c4.global_position)
	if not equip_slot(1):
		if not equip_slot(2):
			equip_slot(3)
