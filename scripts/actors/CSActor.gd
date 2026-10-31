class_name CSActor
extends CharacterBody3D
## Shared Counter-Strike 1.5 Actor (base class for PlayerController and CSBot).
## Implements GoldSrc movement physics, Kevlar/Helmet hitgroup damage, economy/buying,
## weapon drops, flashbang blindness, and 3rd-person character animation.

signal health_armor_changed(hp: int, armor: int, helmet: bool)
signal money_changed(new_amount: int, delta_amount: int)
signal actor_died(victim: CSActor, killer: Node3D)

# GoldSrc physics constants scaled by 1/32 (1u = 0.03125m)
const GRAVITY_MPS2: float = 800.0 * (1.0 / 32.0)  # 25.0 m/s^2
const JUMP_VEL_MPS: float = 268.0 * (1.0 / 32.0)  # ~45u jump height (~58u crouch-jump!)
const GROUND_ACCEL: float = 5.6
const AIR_ACCEL: float = 10.0
const FRICTION: float = 4.2
const STOP_SPEED_MPS: float = 100.0 * (1.0 / 32.0)
const STAND_HEIGHT: float = 1.88
const CROUCH_HEIGHT: float = 1.08
const STEP_HEIGHT: float = 0.54
const MODEL_STAND_OFFSET_Y: float = 1.125
const MODEL_CROUCH_OFFSET_Y: float = 0.5625

var actor_name: String = "Player"
var team: String = "CT"  # "CT" or "T"
var class_id: String = "urban"
var is_human: bool = false
var is_alive: bool = false
var is_vip: bool = false

var health: int = 100
var armor: int = 0
var has_helmet: bool = false
var has_defuser: bool = false
var has_nvg: bool = false
var nvg_active: bool = false
var money: int = 800
var kills: int = 0
var deaths: int = 0

var is_crouching: bool = false
var is_walking: bool = false
var on_ladder: bool = false
var look_yaw: float = 0.0
var look_pitch: float = 0.0
var stamina_factor: float = 1.0  # CS 1.5 landing / bullet-tagging slowdown!
var flash_alpha: float = 0.0

var weapon_ctrl: WeaponController = null
var _col_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _body_root: Node3D = null
var _body_anim: AnimationPlayer = null
var _step_accum: float = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	wall_min_slide_angle = 0.0

	_col_shape = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.36
	_capsule.height = STAND_HEIGHT
	_col_shape.shape = _capsule
	_col_shape.position = Vector3(0.0, STAND_HEIGHT * 0.5, 0.0)
	add_child(_col_shape)

	_body_root = Node3D.new()
	_body_root.name = "CharacterModel"
	_body_root.position = Vector3(0.0, MODEL_STAND_OFFSET_Y, 0.0)
	add_child(_body_root)

	weapon_ctrl = WeaponController.new()
	weapon_ctrl.name = "WeaponController"
	add_child(weapon_ctrl)
	weapon_ctrl.setup_for_actor(self)

	RoundManager.register_actor(self)


func _exit_tree() -> void:
	RoundManager.unregister_actor(self)


func set_team_and_class(new_team: String, new_class: String) -> void:
	team = new_team
	class_id = new_class
	_rebuild_character_model()


func _rebuild_character_model() -> void:
	var old_children := _body_root.get_children()
	for c in old_children:
		_body_root.remove_child(c)
		c.queue_free()
	_body_anim = null
	var mdl_id := "vip" if is_vip else class_id
	var sc := GameData.get_model_scene("players/" + mdl_id)
	if sc:
		var inst := sc.instantiate()
		_configure_character_meshes(inst)
		_body_root.add_child(inst)
		_body_anim = _find_anim(inst)
		GameData.ensure_looping_animations(_body_anim)
		_play_body_anim("idle1")
	_body_root.position.y = MODEL_CROUCH_OFFSET_Y if is_crouching else MODEL_STAND_OFFSET_Y
	_body_root.visible = not is_human


func _configure_character_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				var styled := GameData.get_styled_model_material(mat, "char")
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_configure_character_meshes(c)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null


func _play_body_anim(keyword: String) -> void:
	if not _body_anim:
		return
	var kw := keyword.to_lower()
	var anims := _body_anim.get_animation_list()
	var chosen := ""
	# 1. Exact case-insensitive match first (prevents 'run' matching 'crouchrun' or 'idle' matching 'crouch_idle'!)
	for aname in anims:
		if aname.to_lower() == kw:
			chosen = aname
			break
	# 2. Prefix match (excluding crouch sequences when standing)
	if chosen.is_empty():
		for aname in anims:
			var low := aname.to_lower()
			if not kw.begins_with("crouch") and "crouch" in low:
				continue
			if low.begins_with(kw):
				chosen = aname
				break
	# 3. Substring fallback
	if chosen.is_empty():
		for aname in anims:
			var low := aname.to_lower()
			if not kw.begins_with("crouch") and "crouch" in low:
				continue
			if kw in low:
				chosen = aname
				break
	if not chosen.is_empty() and (_body_anim.current_animation != chosen or not _body_anim.is_playing()):
		_body_anim.play(chosen)


func spawn_for_round(pos: Vector3, yaw_rad: float, reset_weapons: bool) -> void:
	var was_alive := is_alive
	is_alive = true
	health = 100
	flash_alpha = 0.0
	stamina_factor = 1.0
	is_crouching = false
	velocity = Vector3.ZERO

	# Snap GoldSrc waist-origin spawn entities (+36u above floor) cleanly down onto the BSP floor!
	var floor_pos := pos
	if is_inside_tree() and get_world_3d():
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0.0, 0.45, 0.0), pos - Vector3(0.0, 2.25, 0.0))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit:
			floor_pos = (hit["position"] as Vector3) + Vector3(0.0, 0.03, 0.0)
		else:
			floor_pos = pos + Vector3(0.0, 0.04, 0.0)

	global_position = floor_pos
	look_yaw = yaw_rad
	look_pitch = 0.0
	# Keep CharacterBody3D root unrotated so child Camera3D and _body_root never double-rotate!
	rotation = Vector3.ZERO
	_col_shape.disabled = false
	_update_hull_height(false)

	if is_vip:
		armor = 200
		has_helmet = true
		weapon_ctrl.reset_loadout("CT", true)
	elif reset_weapons or not was_alive:
		armor = 0
		has_helmet = false
		has_defuser = false
		has_nvg = false
		nvg_active = false
		weapon_ctrl.reset_loadout(team, false)
	else:
		# Survived previous round: refill active weapon clip if player has reserve, keep gear!
		weapon_ctrl.slots[5] = ""
		weapon_ctrl._reset_states()
		if not weapon_ctrl.equip_slot(1):
			weapon_ctrl.equip_slot(2)

	_rebuild_character_model()
	_body_root.visible = not is_human
	health_armor_changed.emit(health, armor, has_helmet)


func add_money(delta_amt: int) -> void:
	var max_m := int(GameData.economy.get("max_money", 16000))
	var old_m := money
	money = clampi(money + delta_amt, 0, max_m)
	money_changed.emit(money, money - old_m)


func get_eye_position() -> Vector3:
	var eye_h := 1.08 if is_crouching else 1.85
	return global_position + Vector3(0.0, eye_h, 0.0)


func get_look_forward() -> Vector3:
	var b := Basis.from_euler(Vector3(look_pitch, look_yaw, 0.0), EULER_ORDER_YXZ)
	return -b.z


func get_aim_basis(punch_deg: Vector2) -> Basis:
	var pitch := look_pitch + deg_to_rad(punch_deg.x * 1.45)
	var yaw := look_yaw + deg_to_rad(punch_deg.y * 1.1)
	return Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


func apply_flashbang(duration: float) -> void:
	flash_alpha = clampf(maxf(flash_alpha, duration * 0.42), 0.0, 2.2)


func _update_hull_height(crouch_want: bool) -> void:
	if crouch_want == is_crouching:
		return
	if not crouch_want and is_crouching:
		# Verify head clearance before standing up!
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0, CROUCH_HEIGHT, 0),
			global_position + Vector3(0, STAND_HEIGHT + 0.05, 0)
		)
		q.collision_mask = 1
		if not space.intersect_ray(q).is_empty():
			return
	is_crouching = crouch_want
	var h := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	_capsule.height = h
	_col_shape.position.y = h * 0.5
	if _body_root:
		_body_root.position.y = MODEL_CROUCH_OFFSET_Y if is_crouching else MODEL_STAND_OFFSET_Y


func apply_goldsrc_movement(wish_dir_world: Vector3, want_jump: bool, want_crouch: bool, want_walk: bool, delta: float) -> void:
	_update_hull_height(want_crouch)
	is_walking = want_walk

	stamina_factor = move_toward(stamina_factor, 1.0, 0.85 * delta)
	if flash_alpha > 0.0:
		flash_alpha = maxf(0.0, flash_alpha - delta * 0.42)

	if RoundManager.is_movement_frozen():
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY_MPS2 * delta
		move_and_slide()
		return

	# Check ladder zone
	on_ladder = false
	if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_on_ladder"):
		on_ladder = bool(RoundManager.game_world.call("is_on_ladder", global_position + Vector3(0, 0.9, 0)))

	var max_spd := weapon_ctrl.get_max_speed_gs() * GameData.SCALE * stamina_factor
	if is_crouching:
		max_spd *= 0.34
	elif is_walking:
		max_spd *= 0.52

	if on_ladder:
		var climb_spd := 5.2
		if wish_dir_world.length_squared() > 0.01:
			var fwd := get_look_forward()
			velocity.x = wish_dir_world.x * 3.0
			velocity.z = wish_dir_world.z * 3.0
			velocity.y = climb_spd * (1.0 if fwd.y > -0.2 else -1.0)
		else:
			velocity = Vector3.ZERO
		if want_jump:
			velocity = get_look_forward() * 5.5 + Vector3(0, 3.0, 0)
		move_and_slide()
		_tick_footsteps(delta, true)
		return

	var grounded := is_on_floor()
	if grounded:
		# PM_Friction
		var hvel := Vector2(velocity.x, velocity.z)
		var spd := hvel.length()
		if spd > 0.001:
			var ctrl := maxf(spd, STOP_SPEED_MPS)
			var drop := ctrl * FRICTION * delta
			var news := maxf(0.0, spd - drop) / spd
			velocity.x *= news
			velocity.z *= news

		# SV_Accelerate
		if wish_dir_world.length_squared() > 0.001:
			var cur_proj := velocity.dot(wish_dir_world)
			var add_spd := max_spd - cur_proj
			if add_spd > 0.0:
				var acc_spd := minf(add_spd, GROUND_ACCEL * max_spd * delta)
				velocity.x += wish_dir_world.x * acc_spd
				velocity.z += wish_dir_world.z * acc_spd

		if want_jump:
			velocity.y = JUMP_VEL_MPS * stamina_factor
			stamina_factor = maxf(0.68, stamina_factor - 0.22)  # CS 1.5 stamina anti-bhop cap!
	else:
		# SV_AirAccelerate (GoldSrc air-strafe physics!)
		if wish_dir_world.length_squared() > 0.001:
			var air_cap := minf(max_spd, 30.0 * GameData.SCALE)
			var cur_proj := velocity.dot(wish_dir_world)
			var add_spd := air_cap - cur_proj
			if add_spd > 0.0:
				var acc_spd := minf(add_spd, AIR_ACCEL * max_spd * delta)
				velocity.x += wish_dir_world.x * acc_spd
				velocity.z += wish_dir_world.z * acc_spd
		velocity.y -= GRAVITY_MPS2 * delta

	var prev_vy := velocity.y
	var pre_step_vel := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()

	# GoldSrc PM_StepMove: smoothly climb 90-degree BSP stairs, curbs & crate ledges (up to 18u = 0.54m)
	if grounded and is_on_wall() and pre_step_vel.length_squared() > 0.02:
		_try_step_up(pre_step_vel * delta, pre_step_vel)

	# Fall damage & landing sound (GoldSrc > 580u/s = 18.1 m/s)
	if not grounded and is_on_floor():
		if prev_vy < -18.2:
			var fall_dmg := int((absf(prev_vy) - 18.0) * 11.0)
			if fall_dmg > 0:
				AudioManager.play_3d("player/pl_fallpain%d.wav" % randi_range(1, 3), global_position, 0.0, 22.0)
				_apply_raw_hp_loss(null, fall_dmg, "world", false)
		elif prev_vy < -6.5 and not is_walking and not is_crouching:
			AudioManager.play_3d("player/pl_jumpland2.wav", global_position, -5.0, 20.0, 1.0, 14.0, team)
			stamina_factor = maxf(0.65, stamina_factor - 0.18)

	# Auto-open sliding/rotating BSP doors on touch
	for si in range(get_slide_collision_count()):
		var kc := get_slide_collision(si)
		var col := kc.get_collider()
		if col is Node and col.has_meta("door"):
			var door = col.get_meta("door")
			if is_instance_valid(door) and door.has_method("interact"):
				door.interact(self)

	_tick_footsteps(delta, false)
	_update_third_person_anim()

	# Check VIP escape zone on as_* maps!
	if is_vip and is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_escape_zone"):
		if bool(RoundManager.game_world.call("is_in_escape_zone", global_position)):
			RoundManager.notify_vip_escaped(self)


func _tick_footsteps(delta: float, climbing_ladder: bool) -> void:
	if climbing_ladder:
		if velocity.length() > 1.2:
			_step_accum += delta * 2.4
			if _step_accum >= 1.0:
				_step_accum = 0.0
				AudioManager.play_footstep("L", global_position, team)
		return

	if not is_on_floor() or is_crouching or is_walking:
		return
	var hspd := Vector2(velocity.x, velocity.z).length()
	if hspd < 3.6:
		return
	_step_accum += hspd * delta * 0.42
	if _step_accum >= 1.0:
		_step_accum = 0.0
		var mchar := _sample_floor_material()
		AudioManager.play_footstep(mchar, global_position, team)


func _try_step_up(horiz_motion: Vector3, preserve_hvel: Vector3) -> void:
	var up_vec := Vector3(0.0, STEP_HEIGHT, 0.0)
	if test_move(global_transform, up_vec):
		return
	var raised_xf := global_transform.translated(up_vec)
	var step_dir := horiz_motion.normalized() * maxf(horiz_motion.length(), 0.08)
	if test_move(raised_xf, step_dir):
		return
	global_position += up_vec + step_dir
	move_and_collide(Vector3(0.0, -STEP_HEIGHT - 0.06, 0.0))
	velocity.x = preserve_hvel.x
	velocity.z = preserve_hvel.z


func _sample_floor_material() -> String:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 0.2, 0), global_position - Vector3(0, 0.45, 0))
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit and hit["collider"] is Node:
		var p := (hit["collider"] as Node).get_parent()
		if p is MeshInstance3D:
			var mi := p as MeshInstance3D
			if mi.mesh and mi.mesh.get_surface_count() > 0:
				var m := mi.get_surface_override_material(0)
				if not m:
					m = mi.mesh.surface_get_material(0)
				if m:
					return GameData.get_material_char(m.resource_name)
	return "C"


func _update_third_person_anim() -> void:
	if not _body_root.visible:
		return
	_body_root.rotation.y = look_yaw
	_body_root.position.y = MODEL_CROUCH_OFFSET_Y if is_crouching else MODEL_STAND_OFFSET_Y
	var hspd := Vector2(velocity.x, velocity.z).length()
	if is_crouching:
		_play_body_anim("crouchrun" if hspd > 0.8 else "crouch_idle")
	elif not is_on_floor():
		_play_body_anim("jump")
	elif hspd > 4.0:
		_play_body_anim("run")
	elif hspd > 0.55:
		_play_body_anim("walk")
	else:
		_play_body_anim("idle1")


func take_bullet_damage(
	attacker: Node3D,
	raw_dmg: float,
	armor_ratio: float,
	hitgroup: int,
	weapon_id: String,
	hit_pos: Vector3
) -> void:
	if not is_alive:
		return
	if is_instance_valid(attacker) and attacker != self and String(attacker.get("team")) == team and not GameData.friendly_fire:
		return

	var mult := 1.0
	match hitgroup:
		1:
			mult = 4.0  # Headshot
		2:
			mult = 1.0  # Chest/Arm
		3:
			mult = 1.25  # Stomach
		4:
			mult = 0.75  # Leg

	var dmg := raw_dmg * mult
	var armored_part := (hitgroup in [2, 3]) or (hitgroup == 1 and has_helmet)

	if armored_part and armor > 0:
		var new_dmg := dmg * (armor_ratio * 0.5)
		var armor_loss := int((dmg - new_dmg) * 0.5)
		if armor_loss > armor:
			armor_loss = armor
			new_dmg = dmg - float(armor) * 2.0
		armor = maxi(0, armor - maxi(1, armor_loss))
		dmg = new_dmg
		var awav := "player/bhit_helmet-1.wav" if hitgroup == 1 else "player/bhit_kevlar-1.wav"
		AudioManager.play_3d(awav, hit_pos, 0.0, 26.0)
	else:
		var fwav := ("player/headshot%d.wav" % randi_range(1, 3)) if hitgroup == 1 else ("player/bhit_flesh-%d.wav" % randi_range(1, 3))
		AudioManager.play_3d(fwav, hit_pos, 0.0, 26.0)

	# CS 1.5 bullet tagging slowdown
	stamina_factor = clampf(stamina_factor - 0.28, 0.42, 1.0)
	_apply_raw_hp_loss(attacker, maxi(1, int(dmg)), weapon_id, hitgroup == 1)


func apply_explosion_damage(attacker: Node3D, raw_dmg: float, weapon_id: String) -> void:
	if not is_alive:
		return
	var dmg := raw_dmg
	if armor > 0:
		var absorbed := minf(float(armor), dmg * 0.35)
		armor = maxi(0, armor - int(absorbed))
		dmg -= absorbed
	_apply_raw_hp_loss(attacker, maxi(1, int(dmg)), weapon_id, false)


func _apply_raw_hp_loss(attacker: Node3D, dmg_int: int, weapon_id: String, headshot: bool) -> void:
	health = maxi(0, health - dmg_int)
	health_armor_changed.emit(health, armor, has_helmet)
	if health <= 0:
		_die(attacker, weapon_id, headshot)


func _die(killer: Node3D, weapon_id: String, headshot: bool) -> void:
	is_alive = false
	_col_shape.set_deferred("disabled", true)
	AudioManager.play_3d("player/die%d.wav" % randi_range(1, 3), global_position, 1.0, 32.0)

	# Drop primary (or pistol if no primary), C4 backpack, and CT Defuse Kit!
	var drop_w := String(weapon_ctrl.slots.get(1, ""))
	if drop_w.is_empty():
		drop_w = String(weapon_ctrl.slots.get(2, ""))
	if not drop_w.is_empty():
		_spawn_drop_entity(drop_w)
	if String(weapon_ctrl.slots.get(5, "")) == "c4":
		_spawn_drop_entity("c4")
		weapon_ctrl.slots[5] = ""
	if has_defuser:
		has_defuser = false
		_spawn_drop_entity("defuser")

	_body_root.visible = true
	_play_body_anim("head" if headshot else "die_simple")

	RoundManager.notify_actor_killed(self, killer, weapon_id, headshot)
	actor_died.emit(self, killer)


func drop_current_weapon() -> void:
	if not is_alive:
		return
	var wid := weapon_ctrl.current_weapon_id
	var spec := weapon_ctrl.get_current_spec()
	var sl := int(spec.get("slot", 3))
	if sl not in [1, 2, 5]:
		return
	_spawn_drop_entity(wid)
	weapon_ctrl.slots[sl] = ""
	if not weapon_ctrl.equip_slot(1):
		if not weapon_ctrl.equip_slot(2):
			weapon_ctrl.equip_slot(3)


func _spawn_drop_entity(item_id: String) -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	var drop := DroppedWeapon.new()
	RoundManager.game_world.add_child(drop)
	drop.global_position = global_position + Vector3(0, 1.15, 0)
	var clip := int(weapon_ctrl.clips.get(item_id, 0))
	var res := 0
	if GameData.weapons.has(item_id):
		var at := String(GameData.weapons[item_id].get("ammo_type", "none"))
		res = int(weapon_ctrl.ammo_pool.get(at, 0))
	var throw_v := get_look_forward() * 5.2 + Vector3(0, 2.0, 0)
	drop.setup_drop(item_id, clip, res, throw_v, bool(weapon_ctrl.silenced_state.get(item_id, false)))
	RoundManager.dropped_items.append(drop)


func try_pickup_dropped(drop: DroppedWeapon) -> bool:
	if is_vip:
		return false
	var id := drop.item_id
	if id == "defuser":
		if team == "CT" and not has_defuser:
			has_defuser = true
			AudioManager.play_3d("items/kevlar.wav", global_position, -3.0, 14.0)
			return true
		return false
	if id == "c4":
		if team == "T" and String(weapon_ctrl.slots.get(5, "")).is_empty():
			weapon_ctrl.give_weapon("c4", 1, 0)
			AudioManager.play_3d("items/kevlar.wav", global_position, -3.0, 14.0)
			if is_human:
				RoundManager.center_message.emit("You picked up the bomb!", 2.0)
			return true
		return false
	if not GameData.weapons.has(id):
		return false
	var sl := int(GameData.weapons[id].get("slot", 1))
	if String(weapon_ctrl.slots.get(sl, "")).is_empty():
		weapon_ctrl.give_weapon(id, drop.clip_ammo, drop.reserve_ammo)
		weapon_ctrl.silenced_state[id] = drop.silenced
		AudioManager.play_3d("items/kevlar.wav", global_position, -3.0, 14.0)
		if sl == 1 and weapon_ctrl.current_weapon_id != "c4":
			weapon_ctrl.equip_slot(1)
		return true
	return false


# --- ECONOMY & BUYING ---

func can_use_buy_menu() -> bool:
	if not is_alive or is_vip or not RoundManager.can_buy_now():
		return false
	if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("is_in_buyzone"):
		return bool(RoundManager.game_world.call("is_in_buyzone", global_position, team))
	return true


func buy_weapon(wid: String) -> bool:
	if not can_use_buy_menu() or not GameData.weapons.has(wid):
		return false
	var spec: Dictionary = GameData.weapons[wid]
	var wteam := String(spec.get("team", "ANY"))
	if wteam != "ANY" and wteam != team:
		return false
	var price := int(spec.get("price", 0))
	if money < price:
		return false

	if bool(spec.get("grenade", false)):
		var max_g := int(spec.get("max_ammo", 1))
		if int(weapon_ctrl.grenades.get(wid, 0)) >= max_g:
			return false
		add_money(-price)
		weapon_ctrl.give_weapon(wid, 1, 0)
		AudioManager.play_3d("items/kevlar.wav", global_position, -3.0, 14.0)
		return true

	var sl := int(spec.get("slot", 1))
	if String(weapon_ctrl.slots.get(sl, "")) == wid:
		return false
	if not String(weapon_ctrl.slots.get(sl, "")).is_empty():
		_spawn_drop_entity(String(weapon_ctrl.slots[sl]))

	add_money(-price)
	var clip_sz := int(spec.get("clip_size", 30))
	weapon_ctrl.give_weapon(wid, clip_sz, clip_sz)
	weapon_ctrl.equip_weapon_by_id(wid)
	return true


func buy_equipment(eq_id: String) -> bool:
	if not can_use_buy_menu() or not GameData.equipment.has(eq_id):
		return false
	var eq: Dictionary = GameData.equipment[eq_id]
	var eteam := String(eq.get("team", "ANY"))
	if eteam != "ANY" and eteam != team:
		return false

	match eq_id:
		"kevlar":
			if armor >= 100 or money < 650:
				return false
			add_money(-650)
			armor = 100
			AudioManager.play_3d("items/kevlar.wav", global_position, -2.0, 14.0)
			health_armor_changed.emit(health, armor, has_helmet)
			return true
		"kevlar_helmet":
			if armor >= 100 and has_helmet:
				return false
			var cost := 350 if armor >= 100 else 1000
			if money < cost:
				return false
			add_money(-cost)
			armor = 100
			has_helmet = true
			AudioManager.play_3d("items/tr_kevlar.wav", global_position, -2.0, 14.0)
			health_armor_changed.emit(health, armor, has_helmet)
			return true
		"defuser":
			if has_defuser or money < 200:
				return false
			add_money(-200)
			has_defuser = true
			AudioManager.play_3d("items/kevlar.wav", global_position, -2.0, 14.0)
			return true
		"nightvision":
			if has_nvg or money < 1250:
				return false
			add_money(-1250)
			has_nvg = true
			AudioManager.play_3d("items/equip_nvg.wav", global_position, -2.0, 14.0)
			return true
	return false


func buy_ammo_for_slot(slot_num: int, fill_all: bool = false) -> bool:
	if not can_use_buy_menu():
		return false
	var wid := String(weapon_ctrl.slots.get(slot_num, ""))
	if wid.is_empty() or not GameData.weapons.has(wid):
		return false
	var spec: Dictionary = GameData.weapons[wid]
	var atype := String(spec.get("ammo_type", "none"))
	if not GameData.ammo_types.has(atype):
		return false
	var ainfo: Dictionary = GameData.ammo_types[atype]
	var max_a := int(spec.get("max_ammo", ainfo.get("max", 90)))
	var price := int(ainfo.get("price", 40))
	var clip_amt := int(ainfo.get("clip_amount", 30))

	var bought := false
	while int(weapon_ctrl.ammo_pool.get(atype, 0)) < max_a and money >= price:
		add_money(-price)
		weapon_ctrl.ammo_pool[atype] = mini(max_a, int(weapon_ctrl.ammo_pool.get(atype, 0)) + clip_amt)
		bought = true
		if not fill_all:
			break

	if bought:
		AudioManager.play_3d("weapons/clipin1.wav", global_position, -3.0, 14.0)
		weapon_ctrl._emit_ammo()
	return bought
