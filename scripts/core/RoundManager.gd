extends Node
## Manages Counter-Strike 1.5 match state, round loop, economy, win conditions,
## active actors, planted C4, hostages, smoke clouds, and radio commands.

signal round_started(round_num: int)
signal freeze_ended()
signal round_ended(winner_team: String, reason_text: String)
signal kill_logged(killer_name: String, killer_team: String, victim_name: String, victim_team: String, weapon_id: String, headshot: bool)
signal center_message(msg: String, duration: float)
signal chat_radio_message(sender_name: String, sender_team: String, text: String)
signal bomb_state_changed(is_planted: bool, site_pos: Vector3)
signal radio_order_issued(sender: Node3D, team: String, action: String, pos: Vector3)

enum State { WAITING, FREEZE, LIVE, ROUND_OVER }

var state: State = State.WAITING
var round_number: int = 0
var ct_score: int = 0
var t_score: int = 0
var ct_loss_streak: int = 0
var t_loss_streak: int = 0

var state_timer: float = 0.0
var buy_time_left: float = 0.0
var map_mode: String = "de"  # "de", "cs", "as"
var current_map_data: Dictionary = {}

# Active match entities
var game_world: Node3D = null
var actors: Array = []  # Array of CSActor
var hostages: Array = []  # Array of HostageNPC
var dropped_items: Array = []
var smoke_clouds: Array = []  # Array of {pos: Vector3, radius: float, expire: float}
var smoke_volumes: Array = []  # Array of SmokeCloudVolume
var incendiary_areas: Array = []  # Active procedural fires, for tactical path costs
var planted_c4: Node3D = null
var hostages_rescued_this_round: int = 0
var total_hostages_in_round: int = 0


func reset_match(map_data: Dictionary, world_node: Node3D) -> void:
	game_world = world_node
	current_map_data = map_data
	map_mode = String(map_data.get("mode", "de"))
	round_number = 0
	ct_score = 0
	t_score = 0
	ct_loss_streak = 0
	t_loss_streak = 0
	actors.clear()
	hostages.clear()
	dropped_items.clear()
	smoke_clouds.clear()
	smoke_volumes.clear()
	incendiary_areas.clear()
	planted_c4 = null
	state = State.WAITING


func register_actor(actor: Node3D) -> void:
	if not actors.has(actor):
		actors.append(actor)


func unregister_actor(actor: Node3D) -> void:
	actors.erase(actor)


func register_incendiary(area: Node3D) -> void:
	if not incendiary_areas.has(area):
		incendiary_areas.append(area)


func unregister_incendiary(area: Node3D) -> void:
	incendiary_areas.erase(area)


func get_incendiary_danger_at(world_pos: Vector3) -> float:
	var danger := 0.0
	for area in incendiary_areas:
		if is_instance_valid(area) and area.has_method("navigation_danger_at"):
			danger = maxf(danger, float(area.call("navigation_danger_at", world_pos)))
	return danger


## Kill a bomb still ticking when a round closes or restarts. Without this the
## PlantedC4 node kept running with only its reference dropped, survived into
## the next round and exploded seconds into it — an instant T win.
func _clear_stale_planted_c4() -> void:
	if planted_c4 == null:
		return
	var stale: Variant = planted_c4
	planted_c4 = null
	if is_instance_valid(stale):
		var c4_node := stale as Node
		if c4_node != null:
			if c4_node.get_parent() != null:
				c4_node.get_parent().remove_child(c4_node)
			c4_node.queue_free()
	bomb_state_changed.emit(false, Vector3.ZERO)


func start_new_round() -> void:
	if not is_instance_valid(game_world):
		return
	round_number += 1
	hostages_rescued_this_round = 0
	smoke_clouds.clear()
	for sv in smoke_volumes.duplicate():
		if is_instance_valid(sv):
			var sv_node := sv as Node
			if sv_node.get_parent():
				sv_node.get_parent().remove_child(sv_node)
			sv_node.queue_free()
	smoke_volumes.clear()
	for area in incendiary_areas.duplicate():
		if is_instance_valid(area):
			var area_node := area as Node
			if area_node.get_parent():
				area_node.get_parent().remove_child(area_node)
			area_node.queue_free()
	incendiary_areas.clear()
	_clear_stale_planted_c4()
	planted_c4 = null
	bomb_state_changed.emit(false, Vector3.ZERO)

	if game_world.has_method("prepare_round_entities"):
		game_world.call("prepare_round_entities", round_number == 1)

	total_hostages_in_round = hostages.size()
	state = State.FREEZE
	state_timer = maxf(0.5, GameData.freeze_time)
	buy_time_left = 90.0
	round_started.emit(round_number)
	center_message.emit("Round %d - Prepare to Fight!" % round_number, 2.5)


func _process(delta: float) -> void:
	if state == State.WAITING or not is_instance_valid(game_world):
		return

	# Expire smoke clouds
	var now := Time.get_ticks_msec() * 0.001
	for i in range(smoke_clouds.size() - 1, -1, -1):
		if float(smoke_clouds[i]["expire"]) <= now:
			smoke_clouds.remove_at(i)

	if buy_time_left > 0.0:
		buy_time_left = maxf(0.0, buy_time_left - delta)

	state_timer -= delta
	match state:
		State.FREEZE:
			if state_timer <= 0.0:
				state = State.LIVE
				state_timer = GameData.round_time
				freeze_ended.emit()
				var go_wavs := ["radio/letsgo.wav", "radio/moveout.wav", "radio/locknload.wav", "radio/com_go.wav"]
				AudioManager.play_radio(go_wavs[randi() % go_wavs.size()])
		State.LIVE:
			if state_timer <= 0.0 and planted_c4 == null:
				_on_time_expired()
		State.ROUND_OVER:
			if state_timer <= 0.0:
				start_new_round()


func is_movement_frozen() -> bool:
	return state == State.FREEZE


func can_buy_now() -> bool:
	return (state == State.FREEZE or state == State.LIVE) and buy_time_left > 0.0


func register_smoke_volume(vol: Node3D) -> void:
	if not smoke_volumes.has(vol):
		smoke_volumes.append(vol)


func unregister_smoke_volume(vol: Node3D) -> void:
	smoke_volumes.erase(vol)


func apply_world_explosion_physics(blast_pos: Vector3, blast_radius: float, weapon_peak_speed: float = 16.5, smoke_strength: float = 1.0) -> void:
	for item in dropped_items:
		if is_instance_valid(item) and item.has_method("apply_explosion_impulse"):
			item.call("apply_explosion_impulse", blast_pos, blast_radius, weapon_peak_speed)
	for sv in smoke_volumes:
		if is_instance_valid(sv) and sv.has_method("apply_explosion_impulse"):
			sv.call("apply_explosion_impulse", blast_pos, blast_radius, smoke_strength)
	if is_instance_valid(game_world):
		var brks: Array = game_world.get("breakables") if game_world.get("breakables") != null else []
		for brk in brks:
			if is_instance_valid(brk) and brk.has_method("apply_explosion_impulse"):
				brk.call("apply_explosion_impulse", blast_pos, blast_radius * 0.92, 95.0 * smoke_strength)
	for h in hostages:
		if is_instance_valid(h) and h.has_method("notify_nearby_danger"):
			h.call("notify_nearby_danger", blast_pos, blast_radius * 1.35)


func apply_world_bullet_wake(seg_a: Vector3, seg_b: Vector3, strength: float = 1.0) -> void:
	for sv in smoke_volumes:
		if is_instance_valid(sv) and sv.has_method("apply_bullet_wake"):
			sv.call("apply_bullet_wake", seg_a, seg_b, strength)
	var ab: Vector3 = seg_b - seg_a
	var len_sq: float = ab.length_squared()
	if len_sq > 0.01:
		for h in hostages:
			if is_instance_valid(h) and h.has_method("notify_nearby_danger"):
				var hp: Vector3 = (h as Node3D).global_position + Vector3(0.0, 1.0, 0.0)
				var t: float = clampf((hp - seg_a).dot(ab) / len_sq, 0.0, 1.0)
				if (seg_a + ab * t).distance_squared_to(hp) < 12.25:
					h.call("notify_nearby_danger", seg_a, 6.0)


func add_smoke_cloud(pos: Vector3, radius: float = 4.6, duration: float = 18.0) -> void:
	var now := Time.get_ticks_msec() * 0.001
	smoke_clouds.append({"pos": pos, "radius": radius, "start": now, "expire": now + duration})


func get_smoke_density_at(pt: Vector3) -> float:
	var best := 0.0
	for sv in smoke_volumes:
		if is_instance_valid(sv) and sv.has_method("get_density_at"):
			best = maxf(best, float(sv.call("get_density_at", pt)))
	if not smoke_clouds.is_empty():
		var now := Time.get_ticks_msec() * 0.001
		for sc in smoke_clouds:
			var c: Vector3 = sc["pos"]
			var r: float = float(sc["radius"])
			var d := pt.distance_to(c)
			if d > r * 1.15:
				continue
			var age := now - float(sc.get("start", now - 1.0))
			var rem := float(sc["expire"]) - now
			var time_fac := clampf(age / 0.85, 0.0, 1.0) * clampf(rem / 2.8, 0.0, 1.0)
			var radial := 1.0 - smoothstep(r * 0.42, r * 1.12, d)
			best = maxf(best, radial * time_fac)
	return clampf(best, 0.0, 1.0)


func is_line_blocked_by_smoke(a: Vector3, b: Vector3) -> bool:
	for sv in smoke_volumes:
		if is_instance_valid(sv) and sv.has_method("blocks_segment"):
			if bool(sv.call("blocks_segment", a, b)):
				return true
	if smoke_clouds.is_empty():
		return false
	var now := Time.get_ticks_msec() * 0.001
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.001:
		return false
	for sc in smoke_clouds:
		if now - float(sc.get("start", now - 1.0)) < 0.35:
			continue
		var c: Vector3 = sc["pos"]
		var r: float = float(sc["radius"])
		var t := clampf((c - a).dot(ab) / len_sq, 0.0, 1.0)
		var closest := a + ab * t
		if closest.distance_squared_to(c) <= r * r:
			return true
	return false


func notify_actor_killed(victim: Node3D, killer: Node3D, weapon_id: String, headshot: bool) -> void:
	var v_name := String(victim.get("actor_name"))
	var v_team := String(victim.get("team"))
	var k_name := v_name
	var k_team := v_team

	if is_instance_valid(killer) and killer != victim:
		k_name = String(killer.get("actor_name"))
		k_team = String(killer.get("team"))
		if k_team == v_team:
			killer.set("kills", int(killer.get("kills")) - 1)
			if killer.has_method("add_money"):
				killer.call("add_money", int(GameData.economy.get("teamkill_penalty", -3300)))
		else:
			killer.set("kills", int(killer.get("kills")) + 1)
			if killer.has_method("add_money"):
				killer.call("add_money", int(GameData.economy.get("kill_reward", 300)))

	victim.set("deaths", int(victim.get("deaths")) + 1)
	kill_logged.emit(k_name, k_team, v_name, v_team, weapon_id, headshot)

	if state != State.LIVE and state != State.FREEZE:
		return

	# VIP assassination check
	if map_mode == "as" and bool(victim.get("is_vip")):
		end_round("T", "The VIP has been assassinated!", "radio/terwin.wav", 3250)
		return

	_check_team_elimination()


func _check_team_elimination() -> void:
	if state == State.ROUND_OVER:
		return
	var ct_alive := 0
	var t_alive := 0
	var ct_total := 0
	var t_total := 0
	for a in actors:
		if not is_instance_valid(a):
			continue
		var tm := String(a.get("team"))
		if tm == "CT":
			ct_total += 1
			if bool(a.get("is_alive")):
				ct_alive += 1
		elif tm == "T":
			t_total += 1
			if bool(a.get("is_alive")):
				t_alive += 1

	if ct_total == 0 or t_total == 0:
		return

	if ct_alive == 0 and t_alive == 0:
		if planted_c4 != null:
			end_round("T", "Terrorists Win!", "radio/terwin.wav", 3250)
		else:
			end_round("DRAW", "Round Draw!", "radio/rounddraw.wav", 1500)
	elif ct_alive == 0:
		end_round("T", "Terrorists Win!", "radio/terwin.wav", 3250)
	elif t_alive == 0 and planted_c4 == null:
		end_round("CT", "Counter-Terrorists Win!", "radio/ctwin.wav", 3250)


func notify_bomb_planted(c4_node: Node3D, pos: Vector3) -> void:
	planted_c4 = c4_node
	state_timer = GameData.c4_timer
	AudioManager.play_radio("radio/bombpl.wav")
	center_message.emit("The bomb has been planted!", 3.5)
	bomb_state_changed.emit(true, pos)


func notify_bomb_defused(defuser: Node3D) -> void:
	if state == State.ROUND_OVER:
		return
	planted_c4 = null
	bomb_state_changed.emit(false, Vector3.ZERO)
	if is_instance_valid(defuser) and defuser.has_method("add_money"):
		defuser.call("add_money", 300)
	AudioManager.play_radio("radio/bombdef.wav")
	end_round("CT", "The bomb has been defused!\nCounter-Terrorists Win!", "radio/ctwin.wav", 3250)


func notify_bomb_exploded() -> void:
	if state == State.ROUND_OVER:
		return
	planted_c4 = null
	bomb_state_changed.emit(false, Vector3.ZERO)
	end_round("T", "Target Succesfully Bombed!\nTerrorists Win!", "radio/terwin.wav", 3500)


func notify_hostage_rescued(rescuer: Node3D) -> void:
	hostages_rescued_this_round += 1
	AudioManager.play_radio("radio/rescued.wav")
	center_message.emit("A hostage has been rescued!", 2.5)
	if is_instance_valid(rescuer) and rescuer.has_method("add_money"):
		rescuer.call("add_money", int(GameData.economy.get("hostage_rescue_reward", 1000)))
	if total_hostages_in_round > 0 and hostages_rescued_this_round >= total_hostages_in_round:
		end_round("CT", "All Hostages Rescued!\nCounter-Terrorists Win!", "radio/ctwin.wav", 3250)


func notify_vip_escaped(vip_actor: Node3D) -> void:
	if state == State.ROUND_OVER:
		return
	AudioManager.play_radio("radio/vip.wav")
	if is_instance_valid(vip_actor) and vip_actor.has_method("add_money"):
		vip_actor.call("add_money", 1000)
	end_round("CT", "The VIP has escaped!\nCounter-Terrorists Win!", "radio/ctwin.wav", 3500)


func _on_time_expired() -> void:
	if map_mode == "de":
		end_round("CT", "Target has been saved!\nCounter-Terrorists Win!", "radio/ctwin.wav", 3250)
	elif map_mode == "cs":
		end_round("T", "Hostages have not been rescued!\nTerrorists Win!", "radio/terwin.wav", 3250)
	elif map_mode == "as":
		end_round("T", "VIP has not escaped!\nTerrorists Win!", "radio/terwin.wav", 3250)
	else:
		end_round("DRAW", "Round Draw!", "radio/rounddraw.wav", 1500)


func end_round(winner: String, banner_text: String, radio_wav: String, win_money: int) -> void:
	if state == State.ROUND_OVER:
		return
	state = State.ROUND_OVER
	state_timer = 4.5
	# Any bomb still planted dies with the round (defuse/explode paths already
	# cleared it; elimination/draw wins must clear it too).
	_clear_stale_planted_c4()

	if winner == "CT":
		ct_score += 1
		t_loss_streak = mini(t_loss_streak + 1, 4)
		ct_loss_streak = 0
	elif winner == "T":
		t_score += 1
		ct_loss_streak = mini(ct_loss_streak + 1, 4)
		t_loss_streak = 0

	var ct_reward := win_money if winner == "CT" else mini(3400, 1400 + ct_loss_streak * 500)
	var t_reward := win_money if winner == "T" else mini(3400, 1400 + t_loss_streak * 500)
	if winner == "T" and planted_c4 != null:
		ct_reward += 0
	elif winner == "CT" and map_mode == "de" and planted_c4 == null:
		# Bonus if T managed to plant earlier this round handled on defuse
		pass

	for a in actors:
		if not is_instance_valid(a) or not a.has_method("add_money"):
			continue
		var tm := String(a.get("team"))
		if tm == "CT":
			a.add_money(ct_reward)
		elif tm == "T":
			a.add_money(t_reward)

	AudioManager.play_radio(radio_wav)
	center_message.emit(banner_text, 4.0)
	round_ended.emit(winner, banner_text)


func send_radio_command(sender: Node3D, label: String, sound_rel: String, action: String) -> void:
	if not is_instance_valid(sender):
		return
	var tm := String(sender.get("team"))
	var sname := String(sender.get("actor_name"))
	AudioManager.play_radio(sound_rel, tm)
	chat_radio_message.emit(sname, tm, "(RADIO): " + label)
	radio_order_issued.emit(sender, tm, action, sender.global_position)
