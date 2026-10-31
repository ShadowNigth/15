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
	var dep := String(spec.get("deploy_sound", ""))
	if not dep.is_empty() and is_instance_valid(actor):
		AudioManager.play_3d(dep, actor.global_position, -5.0, 16.0)

	weapon_switched.emit(current_weapon_id, spec)
	_emit_ammo()
	return true


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

	# Interruptible shotgun reload!
	if is_reloading and bool(spec.get("shotgun_reload", false)) and int(clips.get(current_weapon_id, 0)) > 0:
		is_reloading = false
		reload_timer = 0.0

	if is_reloading or is_attaching_silencer or fire_cooldown > 0.0:
		return
	if holding and not bool(spec.get("automatic", false)):
		return

	if current_weapon_id == "knife":
		_swing_knife(false)
		return

	if bool(spec.get("grenade", false)):
		_throw_grenade(current_weapon_id)
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
	if plant_progress > 0.0:
		plant_progress = 0.0
		plant_progress_changed.emit(0.0)


func trigger_secondary() -> void:
	if not is_instance_valid(actor) or not bool(actor.get("is_alive")):
		return
	if is_reloading or is_attaching_silencer or fire_cooldown > 0.0:
		return

	var spec := get_current_spec()
	if current_weapon_id == "knife":
		if not RoundManager.is_movement_frozen():
			_swing_knife(true)
		return

	# Detachable silencer (M4A1, USP)
	if bool(spec.get("silencer", false)):
		is_attaching_silencer = true
		reload_timer = 2.8
		var cur_sil := bool(silenced_state.get(current_weapon_id, false))
		var swav := ""
		if current_weapon_id == "m4a1":
			swav = "weapons/m4a1_silencer_off.wav" if cur_sil else "weapons/m4a1_silencer_on.wav"
		else:
			swav = "weapons/usp_silencer_off.wav" if cur_sil else "weapons/usp_silencer_on.wav"
		AudioManager.play_3d(swav, actor.global_position, -3.0, 16.0)
		if actor.has_method("play_viewmodel_anim"):
			actor.play_viewmodel_anim("detach_silencer" if cur_sil else "add_silencer")
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
	if bool(spec.get("shotgun_reload", false)):
		reload_timer = 0.52
	else:
		reload_timer = float(spec.get("reload_time", 2.5))

	var rwav := String(spec.get("reload_sound", ""))
	if not rwav.is_empty() and is_instance_valid(actor):
		AudioManager.play_3d(rwav, actor.global_position, -3.5, 18.0, 1.0, 12.0, String(actor.get("team")))
	if actor.has_method("play_viewmodel_anim"):
		var sil := bool(silenced_state.get(current_weapon_id, false))
		actor.play_viewmodel_anim("reload" if (sil or not spec.get("silencer", false)) else "reload_unsil")


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
			if cur + 1 < csize and res - 1 > 0:
				reload_timer = 0.48
				AudioManager.play_3d("weapons/m3_insertshell.wav", actor.global_position, -4.0, 16.0)
				return
		is_reloading = false
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

	for _hop in range(pen_left + 1):
		if rem_dist <= 0.1 or cur_dmg <= 1.0:
			break
		var q := PhysicsRayQueryParameters3D.create(cur_from, cur_from + dir * rem_dist)
		q.collision_mask = 1 | 2  # World (1) + Actors/Hostages (2)
		q.exclude = exclude_rids
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			break

		var hit_pos: Vector3 = hit["position"]
		var hit_nrm: Vector3 = hit["normal"]
		var traveled_gs := origin.distance_to(hit_pos) / GameData.SCALE
		var dmg_at_dist := cur_dmg * pow(range_mod, traveled_gs / 500.0)
		var col = hit["collider"]

		if col is Node3D and col.has_method("take_bullet_damage"):
			var hgroup := _determine_hitgroup(col, hit_pos)
			col.call("take_bullet_damage", actor, dmg_at_dist, armor_ratio, hgroup, current_weapon_id, hit_pos)
			exclude_rids.append((col as CollisionObject3D).get_rid())
			cur_dmg *= 0.65
			var step := origin.distance_to(hit_pos)
			rem_dist = max_dist - step
			cur_from = hit_pos + dir * 0.25
			continue

		if col is HostageNPC:
			(col as HostageNPC).take_damage(actor, dmg_at_dist)
			break

		# World or func_breakable impact
		if col is Node and col.has_meta("breakable"):
			var brk = col.get_meta("breakable")
			if is_instance_valid(brk) and brk.has_method("apply_damage"):
				brk.apply_damage(dmg_at_dist, hit_pos)

		_spawn_wall_puff(hit_pos, hit_nrm)

		# CS 1.5 Wallbanging: test thin wall exit within 0.65m (~21 GoldSrc units)
		if pen_left <= 0:
			break
		var probe_start: Vector3 = hit_pos + dir * 0.62
		var back_q := PhysicsRayQueryParameters3D.create(probe_start, hit_pos + dir * 0.02)
		back_q.collision_mask = 1
		var exit_hit: Dictionary = space.intersect_ray(back_q)
		if exit_hit.is_empty():
			break  # Wall thicker than penetration depth
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


func _spawn_wall_puff(pos: Vector3, normal: Vector3) -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	var puff := Sprite3D.new()
	puff.texture = GameData.get_texture("res://assets/sprites/wall_puff%d.png" % randi_range(1, 4))
	puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	puff.pixel_size = 0.0045
	puff.modulate = Color(0.85, 0.85, 0.82, 0.8)
	RoundManager.game_world.add_child(puff)
	puff.global_position = pos + normal * 0.04
	var tw := puff.create_tween()
	tw.tween_property(puff, "modulate:a", 0.0, 0.35)
	tw.tween_callback(puff.queue_free)

	if randf() < 0.35:
		AudioManager.play_3d("weapons/ric%d.wav" % randi_range(1, 5), pos, -9.0, 18.0)


func _swing_knife(heavy_stab: bool) -> void:
	var spec := get_current_spec()
	fire_cooldown = float(spec.get("alt_cycle_time", 1.1)) if heavy_stab else float(spec.get("cycle_time", 0.4))
	var reach := (float(spec.get("alt_range", 36.0)) if heavy_stab else float(spec.get("range", 52.0))) * GameData.SCALE
	fired_shot.emit("knife", true)

	var eye: Vector3 = actor.call("get_eye_position")
	var aim_b: Basis = actor.call("get_aim_basis", Vector2.ZERO)
	var dir: Vector3 = -aim_b.z
	var space: PhysicsDirectSpaceState3D = (actor as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * reach)
	q.collision_mask = 1 | 2
	q.exclude = [(actor as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)

	if hit.is_empty():
		AudioManager.play_3d("weapons/knife_slash%d.wav" % randi_range(1, 2), actor.global_position, -3.0, 14.0)
		return

	var col = hit["collider"]
	var hpos: Vector3 = hit["position"]
	if col is Node3D and col.has_method("take_bullet_damage"):
		var dmg := 65.0 if heavy_stab else 20.0
		if heavy_stab:
			var target_fwd: Vector3 = -(col as Node3D).global_transform.basis.z
			if dir.dot(target_fwd) > 0.45:
				dmg = 195.0  # Classic CS 1.5 Backstab!
		col.call("take_bullet_damage", actor, dmg, 1.7, 2, "knife", hpos)
		var kwav := "weapons/knife_stab.wav" if heavy_stab else ("weapons/knife_hit%d.wav" % randi_range(1, 4))
		AudioManager.play_3d(kwav, hpos, 0.0, 20.0)
		return

	if col is Node and col.has_meta("breakable"):
		var brk = col.get_meta("breakable")
		if is_instance_valid(brk) and brk.has_method("apply_damage"):
			brk.apply_damage(45.0 if heavy_stab else 20.0, hpos)

	AudioManager.play_3d("weapons/knife_hitwall1.wav", hpos, -3.0, 16.0)


func _throw_grenade(gid: String) -> void:
	var count := int(grenades.get(gid, 0))
	if count <= 0 or not is_instance_valid(RoundManager.game_world):
		return
	grenades[gid] = count - 1
	fire_cooldown = 0.75

	AudioManager.play_3d("weapons/pinpull.wav", actor.global_position, -3.0, 14.0)
	AudioManager.play_radio("radio/ct_fireinhole.wav")
	RoundManager.chat_radio_message.emit(String(actor.get("actor_name")), String(actor.get("team")), "(RADIO): Fire in the hole!")

	var eye: Vector3 = actor.call("get_eye_position")
	var aim_b: Basis = actor.call("get_aim_basis", Vector2.ZERO)
	var fwd: Vector3 = -aim_b.z
	var proj := GrenadeProjectile.new()
	RoundManager.game_world.add_child(proj)
	proj.global_position = eye + fwd * 0.45
	var actor_vel: Vector3 = (actor as CharacterBody3D).velocity
	var throw_v: Vector3 = fwd * 21.5 + Vector3(0, 2.6, 0) + actor_vel * 0.45
	proj.setup_grenade(gid, actor, throw_v)

	# Switch back to best available weapon
	if not equip_slot(1):
		if not equip_slot(2):
			equip_slot(3)


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
