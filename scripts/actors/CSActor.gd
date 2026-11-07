class_name CSActor
extends CharacterBody3D
## Shared Counter-Strike 1.5 Actor (base class for PlayerController and CSBot).
## Implements GoldSrc movement physics, Kevlar/Helmet hitgroup damage, economy/buying,
## weapon drops, flashbang blindness, and 3rd-person character animation.

signal health_armor_changed(hp: int, armor: int, helmet: bool)
signal money_changed(new_amount: int, delta_amount: int)
signal actor_died(victim: CSActor, killer: Node3D)
signal damaged_from(source_pos: Vector3, dmg_amount: int, directional: bool)

# GoldSrc physics constants scaled by 1/32 (1u = 0.03125m)
const GRAVITY_MPS2: float = 800.0 * (1.0 / 32.0)  # 25.0 m/s^2
const JUMP_VEL_MPS: float = 268.0 * (1.0 / 32.0)  # ~45u jump height (~58u crouch-jump!)
const GROUND_ACCEL: float = 7.2
const AIR_ACCEL: float = 11.0
const FRICTION: float = 4.6
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
var in_water: bool = false
var water_depth: float = 0.0
var _was_in_water: bool = false
var bot_ladder_dir: float = 0.0
var bot_ladder_anchor: Vector3 = Vector3.ZERO
var bot_ladder_anchor_valid: bool = false
var look_yaw: float = 0.0
var look_pitch: float = 0.0
var stamina_factor: float = 1.0  # CS 1.5 landing / bullet-tagging slowdown!
var flash_alpha: float = 0.0

var weapon_ctrl: WeaponController = null
var _col_shape: CollisionShape3D = null
var _capsule: CapsuleShape3D = null
var _bullet_hitboxes: SkeletalHitboxes = null
var _body_root: Node3D = null
var _body_anim: AnimationPlayer = null
var _skel: Skeleton3D = null
var _hand_attachment: BoneAttachment3D = null
var _held_weapon_model: Node3D = null
var _held_weapon_rest_transform: Transform3D = Transform3D.IDENTITY
var _tp_muzzle_sprite: Sprite3D = null
var _tp_muzzle_light: OmniLight3D = null
var _tp_muzzle_timer: float = 0.0
var _step_accum: float = 0.0

# GoldSrc StudioSetupBones / StudioEstimateGait runtime blending state
var _pelvis_bone_idx: int = -1
var _spine_bone_idx: int = -1
var _is_upper_bone: PackedByteArray = PackedByteArray()
var _anim_tracks_cache: Dictionary = {}  # anim_name -> Array of [track_idx, bone_idx, is_pos]
var _anim_res_map: Dictionary = {}  # lower_name -> Animation
var _gait_yaw: float = 0.0
var _gait_time: float = 0.0
var _cur_gait_key: String = "idle1"
var _prev_gait_key: String = "idle1"
var _prev_gait_time: float = 0.0
var _gait_blend_alpha: float = 1.0
var _upper_action_key: String = ""
var _upper_action_time: float = 0.0
var _upper_aim_time: float = 0.0
var _death_anim_key: String = ""
var _death_anim_time: float = 0.0
var _death_from_pos: Array[Vector3] = []
var _death_from_rot: Array[Quaternion] = []
var _corpse_vel: Vector3 = Vector3.ZERO
var _corpse_settled: bool = true
var _corpse_blood_spawned: bool = false
var _tp_recoil_pitch: float = 0.0
var _tp_flinch_angles: Vector2 = Vector2.ZERO
var _pain_sound_cd: float = 0.0
var _last_hitgroup: int = 2

# Sub-tick render interpolation & GoldSrc stair/crouch visual smoothing
var _prev_phys_pos: Vector3 = Vector3.ZERO
var _step_smooth_y: float = 0.0
var _visual_crouch_t: float = 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(46.0)
	wall_min_slide_angle = 0.0
	max_slides = 6

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
	weapon_ctrl.weapon_switched.connect(_on_actor_weapon_switched)

	RoundManager.register_actor(self)


func _exit_tree() -> void:
	RoundManager.unregister_actor(self)


func set_team_and_class(new_team: String, new_class: String) -> void:
	team = new_team
	class_id = new_class
	_rebuild_character_model()


func _rebuild_character_model() -> void:
	remove_from_group("skeletal_bullet_actors")
	if is_instance_valid(_bullet_hitboxes):
		for entry in _bullet_hitboxes.entries:
			entry["area"].collision_layer = 0
		remove_child(_bullet_hitboxes)
		_bullet_hitboxes.queue_free()
		_bullet_hitboxes = null
	var old_children := _body_root.get_children()
	for c in old_children:
		_body_root.remove_child(c)
		c.queue_free()
	_body_anim = null
	_skel = null
	_hand_attachment = null
	_held_weapon_model = null
	_held_weapon_rest_transform = Transform3D.IDENTITY
	_tp_muzzle_sprite = null
	_tp_muzzle_light = null
	_pelvis_bone_idx = -1
	_spine_bone_idx = -1
	_is_upper_bone = PackedByteArray()
	_anim_tracks_cache.clear()
	_anim_res_map.clear()
	_upper_action_key = ""
	_upper_action_time = 0.0
	_death_anim_key = ""
	_death_anim_time = 0.0
	_gait_yaw = look_yaw

	var mdl_id := "vip" if is_vip else class_id
	var sc := GameData.get_model_scene("players/" + mdl_id)
	if sc:
		var inst := sc.instantiate()
		_configure_character_meshes(inst)
		_body_root.add_child(inst)
		_body_anim = _find_anim(inst)
		_skel = _find_skeleton(inst)
		if _body_anim and _skel:
			_body_anim.active = false  # Driven directly by GoldSrc 2-layer Gait + Upper-Body blender!
			_build_skeleton_blend_tables()
			var rhand_idx := _skel.find_bone("Bip01 R Hand")
			if rhand_idx >= 0:
				_hand_attachment = BoneAttachment3D.new()
				_hand_attachment.name = "RightHandAttachment"
				_hand_attachment.bone_name = "Bip01 R Hand"
				_skel.add_child(_hand_attachment)

				_tp_muzzle_sprite = Sprite3D.new()
				_tp_muzzle_sprite.layers = 2
				var mtex := GameData.get_texture("res://assets/sprites/muzzleflash1.png")
				_tp_muzzle_sprite.texture = mtex
				_tp_muzzle_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				_tp_muzzle_sprite.shaded = false
				_tp_muzzle_sprite.pixel_size = 0.0048
				_tp_muzzle_sprite.modulate = Color(1.0, 0.90, 0.56, 0.96)
				_tp_muzzle_sprite.position = Vector3(-0.04, 0.06, -0.58)
				_tp_muzzle_sprite.visible = false
				_hand_attachment.add_child(_tp_muzzle_sprite)

				if not is_human:
					_tp_muzzle_light = OmniLight3D.new()
					_tp_muzzle_light.light_color = Color(1.0, 0.80, 0.42)
					_tp_muzzle_light.light_energy = 1.9
					_tp_muzzle_light.omni_range = 6.2
					_tp_muzzle_light.position = Vector3(-0.04, 0.08, -0.62)
					_tp_muzzle_light.visible = false
					_hand_attachment.add_child(_tp_muzzle_light)
		if weapon_ctrl:
			_update_held_weapon_model(weapon_ctrl.current_weapon_id)
		_evaluate_character_pose(0.0)
	_body_root.position.y = MODEL_CROUCH_OFFSET_Y if is_crouching else MODEL_STAND_OFFSET_Y
	_body_root.visible = not is_human
	if _skel != null:
		_bullet_hitboxes = SkeletalHitboxes.new()
		_bullet_hitboxes.name = "SkeletalHitboxes"
		add_child(_bullet_hitboxes)
		_bullet_hitboxes.setup(self, _skel)


func _build_skeleton_blend_tables() -> void:
	if _skel == null or _body_anim == null:
		return
	var nb := _skel.get_bone_count()
	_is_upper_bone.resize(nb)
	_is_upper_bone.fill(0)
	_pelvis_bone_idx = _skel.find_bone("Bip01 Pelvis")
	_spine_bone_idx = _skel.find_bone("Bip01 Spine")
	if _spine_bone_idx >= 0:
		_is_upper_bone[_spine_bone_idx] = 1
		for bi in range(nb):
			var cur := _skel.get_bone_parent(bi)
			var guard := 0
			while cur >= 0 and cur < nb and guard < 96:
				guard += 1
				if _is_upper_bone[cur] == 1:
					_is_upper_bone[bi] = 1
					break
				cur = _skel.get_bone_parent(cur)

	for aname in _body_anim.get_animation_list():
		var anim_res := _body_anim.get_animation(aname)
		if anim_res == null:
			continue
		var low := aname.to_lower()
		_anim_res_map[low] = anim_res
		var entries: Array = []
		var tc := anim_res.get_track_count()
		for ti in range(tc):
			var ttype := anim_res.track_get_type(ti)
			if ttype != Animation.TYPE_POSITION_3D and ttype != Animation.TYPE_ROTATION_3D:
				continue
			var bname := String(anim_res.track_get_path(ti).get_concatenated_subnames())
			var bidx := _skel.find_bone(bname)
			if bidx >= 0:
				entries.append([ti, bidx, ttype == Animation.TYPE_POSITION_3D])
		_anim_tracks_cache[low] = entries


func _get_weapon_anim_ext(wid: String) -> String:
	match wid:
		"ak47":
			return "ak47"
		"m4a1", "aug", "sg552", "ump45", "tmp":
			return "carbine"
		"mp5navy", "mac10", "p90":
			return "mp5"
		"awp", "scout", "g3sg1", "sg550":
			return "rifle"
		"m3", "xm1014":
			return "shotgun"
		"m249":
			return "m249"
		"elite":
			return "dualpistols"
		"usp", "glock18", "deagle", "p228", "fiveseven":
			return "onehanded"
		"knife":
			return "knife"
		"hegrenade", "flashbang", "smokegrenade":
			return "grenade"
		"c4":
			return "c4"
	return "carbine"


func trigger_upper_body_action(action_kind: String) -> void:
	if not is_alive or _anim_res_map.is_empty():
		return
	var wid := weapon_ctrl.current_weapon_id if weapon_ctrl else "usp"
	var ext := _get_weapon_anim_ext(wid)
	var pref := "crouch_" if is_crouching else "ref_"

	match action_kind:
		"shoot":
			var key := pref + "shoot_" + ext
			if ext == "dualpistols" and randf() < 0.5 and _anim_res_map.has(pref + "shoot2_dualpistols"):
				key = pref + "shoot2_dualpistols"
			if _anim_res_map.has(key):
				_upper_action_key = key
				_upper_action_time = 0.0
			var wspec: Dictionary = GameData.weapons.get(wid, {})
			var rec_u: float = float(wspec.get("recoil_up", 1.5))
			_tp_recoil_pitch = clampf(_tp_recoil_pitch + deg_to_rad(1.4 + rec_u * 1.15), 0.0, deg_to_rad(9.5))
			if _tp_muzzle_sprite and wid not in ["knife", "hegrenade", "flashbang", "smokegrenade", "c4"]:
				var is_sil := weapon_ctrl != null and bool(weapon_ctrl.silenced_state.get(wid, false))
				var is_rifle_w: bool = int(wspec.get("slot", 1)) == 1
				if not is_human and is_instance_valid(RoundManager.game_world):
					var mpos: Vector3 = _tp_muzzle_sprite.global_position
					ImpactEffects.spawn_barrel_smoke(RoundManager.game_world, mpos, is_rifle_w, 2, true)
				if not is_sil:
					_tp_muzzle_sprite.texture = GameData.get_texture("res://assets/sprites/muzzleflash%d.png" % randi_range(1, 4))
					_tp_muzzle_sprite.rotation.z = randf() * TAU
					var mscale: float = clampf(0.82 + rec_u * 0.14, 0.80, 1.35) * randf_range(0.92, 1.10)
					_tp_muzzle_sprite.scale = Vector3.ONE * mscale
					_tp_muzzle_sprite.visible = true
					if _tp_muzzle_light:
						_tp_muzzle_light.light_energy = 1.65 + rec_u * 0.25
						_tp_muzzle_light.visible = true
					_tp_muzzle_timer = 0.048
		"reload":
			var rkey := pref + "reload_" + ext
			if not _anim_res_map.has(rkey):
				rkey = "ref_reload_" + ext
			if _anim_res_map.has(rkey):
				_upper_action_key = rkey
				_upper_action_time = 0.0
		"flinch_head":
			if (_upper_action_key.is_empty() or "flinch" in _upper_action_key) and _anim_res_map.has("head_flinch"):
				_upper_action_key = "head_flinch"
				_upper_action_time = 0.0
		"flinch_gut":
			if (_upper_action_key.is_empty() or "flinch" in _upper_action_key) and _anim_res_map.has("gut_flinch"):
				_upper_action_key = "gut_flinch"
				_upper_action_time = 0.0


func _apply_anim_layer(anim_key: String, sample_t: float, mode: int, blend_w: float = 1.0) -> void:
	# mode: 0 = lower-body bones only, 1 = upper-body bones only, 2 = full skeleton (deaths)
	if not _anim_res_map.has(anim_key) or _skel == null:
		return
	var anim_res: Animation = _anim_res_map[anim_key]
	var tracks: Array = _anim_tracks_cache.get(anim_key, [])
	var dur := maxf(0.001, anim_res.length)
	var t_clamped := clampf(sample_t, 0.0, dur)
	var use_blend: bool = (blend_w < 0.999)
	for entry in tracks:
		var e := entry as Array
		var ti := int(e[0])
		var bi := int(e[1])
		if mode == 0 and _is_upper_bone[bi] == 1:
			continue
		if mode == 1 and _is_upper_bone[bi] == 0:
			continue
		if bool(e[2]):
			var p_tgt: Vector3 = anim_res.position_track_interpolate(ti, t_clamped)
			if use_blend:
				p_tgt = _skel.get_bone_pose_position(bi).lerp(p_tgt, blend_w)
			_skel.set_bone_pose_position(bi, p_tgt)
		else:
			var q_tgt: Quaternion = anim_res.rotation_track_interpolate(ti, t_clamped)
			if use_blend:
				q_tgt = _skel.get_bone_pose_rotation(bi).slerp(q_tgt, blend_w)
			_skel.set_bone_pose_rotation(bi, q_tgt)


func get_visual_world_pos() -> Vector3:
	if _prev_phys_pos.distance_squared_to(global_position) > 9.0:
		_prev_phys_pos = global_position
	var frac: float = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var p: Vector3 = _prev_phys_pos.lerp(global_position, frac)
	p.y += _step_smooth_y
	return p


func _process(delta: float) -> void:
	if _pain_sound_cd > 0.0:
		_pain_sound_cd = maxf(0.0, _pain_sound_cd - delta)
	_step_smooth_y = lerpf(_step_smooth_y, 0.0, minf(1.0, 22.0 * delta))
	_visual_crouch_t = lerpf(_visual_crouch_t, 1.0 if is_crouching else 0.0, minf(1.0, 16.0 * delta))
	_tp_recoil_pitch = lerpf(_tp_recoil_pitch, 0.0, minf(1.0, 18.0 * delta))
	_tp_flinch_angles = _tp_flinch_angles.lerp(Vector2.ZERO, minf(1.0, 14.0 * delta))
	if not is_alive and not _corpse_settled:
		_tick_corpse_grounding(delta)
	if _tp_muzzle_timer > 0.0:
		_tp_muzzle_timer -= delta
		if _tp_muzzle_timer <= 0.0:
			if _tp_muzzle_sprite:
				_tp_muzzle_sprite.visible = false
			if _tp_muzzle_light:
				_tp_muzzle_light.visible = false
	if _body_root and (_body_root.visible or is_instance_valid(_bullet_hitboxes)):
		_evaluate_character_pose(delta)
	if is_instance_valid(_bullet_hitboxes):
		_bullet_hitboxes.sync_pose()
	_stabilize_held_weapon()


func _tick_corpse_grounding(delta: float) -> void:
	var w3d := get_world_3d()
	if w3d == null or w3d.direct_space_state == null:
		_corpse_settled = true
		return
	var space := w3d.direct_space_state
	_corpse_vel.y -= GRAVITY_MPS2 * delta
	var cur := global_position
	var step := _corpse_vel * delta
	if step.length_squared() > 0.00001:
		var q_move := PhysicsRayQueryParameters3D.create(cur + Vector3(0.0, 0.45, 0.0), cur + Vector3(0.0, 0.45, 0.0) + step)
		q_move.collision_mask = 1
		var h_move := space.intersect_ray(q_move)
		if not h_move.is_empty():
			var nrm: Vector3 = h_move["normal"]
			if nrm.y < 0.55:
				_corpse_vel.x = 0.0
				_corpse_vel.z = 0.0
			else:
				global_position = (h_move["position"] as Vector3) - Vector3(0.0, 0.42, 0.0)
		else:
			global_position = cur + step

	var q_flr := PhysicsRayQueryParameters3D.create(global_position + Vector3(0.0, 0.65, 0.0), global_position - Vector3(0.0, 0.14, 0.0))
	q_flr.collision_mask = 1
	var h_flr := space.intersect_ray(q_flr)
	if not h_flr.is_empty() and _corpse_vel.y <= 0.25:
		var fp: Vector3 = h_flr["position"]
		var fn: Vector3 = h_flr["normal"]
		global_position.y = fp.y + 0.02
		_corpse_vel.y = 0.0
		var drag: float = maxf(0.0, 1.0 - 9.5 * delta)
		_corpse_vel.x *= drag
		_corpse_vel.z *= drag
		if not _corpse_blood_spawned and is_instance_valid(RoundManager.game_world):
			_corpse_blood_spawned = true
			ImpactEffects.spawn_death_blood_pool(RoundManager.game_world, fp, fn)
		if _corpse_vel.length_squared() < 0.02:
			_corpse_vel = Vector3.ZERO
			_corpse_settled = true
	_prev_phys_pos = global_position


func _evaluate_character_pose(delta: float) -> void:
	if _skel == null or _anim_res_map.is_empty():
		return

	if not is_alive:
		var death_base_y: float = MODEL_CROUCH_OFFSET_Y if _death_anim_key == "crouch_die" else MODEL_STAND_OFFSET_Y
		_body_root.position.y = lerpf(_body_root.position.y, death_base_y, minf(1.0, 16.0 * delta))
		_body_root.position.x = 0.0
		_body_root.position.z = 0.0
		if not _death_anim_key.is_empty() and _anim_res_map.has(_death_anim_key):
			var d_anim: Animation = _anim_res_map[_death_anim_key]
			_death_anim_time = minf(d_anim.length, _death_anim_time + delta)
			var cross_w: float = clampf(_death_anim_time / 0.10, 0.0, 1.0)
			if cross_w < 0.999 and _death_from_pos.size() == _skel.get_bone_count():
				var nb: int = _skel.get_bone_count()
				for bi in range(nb):
					_skel.set_bone_pose_position(bi, _death_from_pos[bi])
					_skel.set_bone_pose_rotation(bi, _death_from_rot[bi])
				_apply_anim_layer(_death_anim_key, _death_anim_time, 2, cross_w)
			else:
				_apply_anim_layer(_death_anim_key, _death_anim_time, 2, 1.0)
		return

	var sub_ofs: Vector3 = get_visual_world_pos() - global_position
	var base_model_y: float = lerpf(MODEL_STAND_OFFSET_Y, MODEL_CROUCH_OFFSET_Y, _visual_crouch_t)
	_body_root.position = Vector3(sub_ofs.x, base_model_y + sub_ofs.y, sub_ofs.z)

	# 1. GoldSrc StudioEstimateGait: orient legs/pelvis into strafe/walk direction & reverse on backpedal!
	var hvel := Vector2(velocity.x, velocity.z)
	var hspd := hvel.length()
	var gait_dir_sign := 1.0
	if hspd > 0.35:
		var move_yaw := atan2(-velocity.x, -velocity.z)
		var rel := wrapf(move_yaw - look_yaw, -PI, PI)
		if absf(rel) > deg_to_rad(106.0):
			move_yaw = wrapf(move_yaw + PI, -PI, PI)
			gait_dir_sign = -1.0
		var clamped_rel := clampf(wrapf(move_yaw - look_yaw, -PI, PI), deg_to_rad(-56.0), deg_to_rad(56.0))
		_gait_yaw = lerp_angle(_gait_yaw, look_yaw + clamped_rel, minf(1.0, 12.0 * delta))
	else:
		_gait_yaw = lerp_angle(_gait_yaw, look_yaw, minf(1.0, 10.0 * delta))

	_body_root.rotation.y = _gait_yaw

	# 2. Select & advance lower-body gait sequence with speed-proportional stride rate!
	var want_gait := "idle1"
	var rate := 1.0
	if is_crouching:
		if hspd > 0.65:
			want_gait = "crouchrun"
			rate = clampf(hspd / 2.6, 0.55, 1.45) * gait_dir_sign
		else:
			want_gait = "crouch_idle"
	elif on_ladder:
		if absf(velocity.y) > 0.35:
			want_gait = "walk" if _anim_res_map.has("walk") else "run"
			rate = clampf(absf(velocity.y) / 4.2, 0.75, 1.35) * (1.0 if velocity.y >= 0.0 else -1.0)
		else:
			want_gait = "idle1"
	elif not is_on_floor():
		want_gait = "jump"
		rate = 1.0
	elif hspd > 4.05:
		want_gait = "run"
		rate = clampf(hspd / 6.7, 0.65, 1.35) * gait_dir_sign
	elif hspd > 0.45:
		want_gait = "walk"
		rate = clampf(hspd / 3.4, 0.60, 1.35) * gait_dir_sign

	if not _anim_res_map.has(want_gait):
		want_gait = "idle1"
	if want_gait != _cur_gait_key:
		var old_anim: Animation = _anim_res_map.get(_cur_gait_key, null)
		var new_anim: Animation = _anim_res_map.get(want_gait, null)
		var norm_phase := 0.0
		if old_anim != null and old_anim.length > 0.05 and _cur_gait_key in ["run", "walk", "crouchrun"] and want_gait in ["run", "walk", "crouchrun"]:
			norm_phase = fposmod(_gait_time / old_anim.length, 1.0)
		_prev_gait_key = _cur_gait_key
		_prev_gait_time = _gait_time
		_cur_gait_key = want_gait
		_gait_blend_alpha = 0.0
		_gait_time = norm_phase * new_anim.length if (new_anim != null and norm_phase > 0.0) else 0.0

	if _gait_blend_alpha < 1.0:
		_gait_blend_alpha = minf(1.0, _gait_blend_alpha + delta * 8.5)
		var p_anim: Animation = _anim_res_map.get(_prev_gait_key, null)
		if p_anim != null:
			_prev_gait_time = fposmod(_prev_gait_time + delta * rate, maxf(0.05, p_anim.length))
			_apply_anim_layer(_prev_gait_key, _prev_gait_time, 0, 1.0)

	var g_anim: Animation = _anim_res_map.get(_cur_gait_key, null)
	if g_anim != null:
		var g_len := maxf(0.05, g_anim.length)
		if _cur_gait_key == "jump":
			_gait_time = minf(g_len, _gait_time + delta * 1.15)
		else:
			_gait_time = fposmod(_gait_time + delta * rate, g_len)
		_apply_anim_layer(_cur_gait_key, _gait_time, 0, _gait_blend_alpha)

	# 3. Smoothly blended upper-body weapon aim posture (stand <-> crouch) + crossfaded shoot/reload/flinch!
	var wid := weapon_ctrl.current_weapon_id if weapon_ctrl else "usp"
	var ext := _get_weapon_anim_ext(wid)
	var stand_aim_key := "ref_aim_" + ext
	if not _anim_res_map.has(stand_aim_key):
		stand_aim_key = "ref_aim_carbine"
	var crouch_aim_key := "crouch_aim_" + ext
	if not _anim_res_map.has(crouch_aim_key):
		crouch_aim_key = "crouch_aim_carbine"

	if _anim_res_map.has(stand_aim_key) and _visual_crouch_t < 0.995:
		var sa_anim: Animation = _anim_res_map[stand_aim_key]
		_upper_aim_time = fposmod(_upper_aim_time + delta, maxf(0.05, sa_anim.length))
		_apply_anim_layer(stand_aim_key, _upper_aim_time, 1, 1.0)
	if _anim_res_map.has(crouch_aim_key) and _visual_crouch_t > 0.005:
		var ca_anim: Animation = _anim_res_map[crouch_aim_key]
		var ca_t: float = fposmod(_upper_aim_time, maxf(0.05, ca_anim.length))
		_apply_anim_layer(crouch_aim_key, ca_t, 1, _visual_crouch_t)

	# Cancel upper reload clip smoothly if WeaponController finished/interrupted reload
	if "reload" in _upper_action_key and weapon_ctrl != null and not weapon_ctrl.is_reloading:
		_upper_action_key = ""

	if not _upper_action_key.is_empty() and _anim_res_map.has(_upper_action_key):
		var act_anim: Animation = _anim_res_map[_upper_action_key]
		_upper_action_time += delta
		if _upper_action_time >= act_anim.length:
			_upper_action_key = ""
		else:
			var w_in: float = clampf(_upper_action_time / 0.045, 0.0, 1.0)
			var w_out: float = clampf((act_anim.length - _upper_action_time) / 0.14, 0.0, 1.0)
			var act_w: float = minf(w_in, w_out)
			_apply_anim_layer(_upper_action_key, _upper_action_time, 1, act_w)

	# 4. Counter-twist Bip01 Spine back to exact look_yaw + pitch aim + procedural recoil & bullet hit-flinch!
	if _pelvis_bone_idx >= 0 and _spine_bone_idx >= 0:
		var yaw_diff := clampf(wrapf(look_yaw - _gait_yaw, -PI, PI), deg_to_rad(-62.0), deg_to_rad(62.0))
		var pitch_aim := clampf(look_pitch * 0.68 + _tp_recoil_pitch + _tp_flinch_angles.x, deg_to_rad(-52.0), deg_to_rad(52.0))
		var roll_flinch := clampf(_tp_flinch_angles.y, deg_to_rad(-18.0), deg_to_rad(18.0))
		var b_pelvis := _skel.get_bone_global_pose(_pelvis_bone_idx).basis
		var r_twist := Basis.from_euler(Vector3(pitch_aim, yaw_diff, roll_flinch), EULER_ORDER_YXZ)
		var q_spine := _skel.get_bone_pose_rotation(_spine_bone_idx)
		var b_new := (b_pelvis.inverse() * r_twist * b_pelvis * Basis(q_spine)).orthonormalized()
		_skel.set_bone_pose_rotation(_spine_bone_idx, b_new.get_rotation_quaternion())


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


func _on_actor_weapon_switched(wid: String, _spec: Dictionary) -> void:
	_upper_action_key = ""
	_update_held_weapon_model(wid)


func _update_held_weapon_model(wid: String) -> void:
	_held_weapon_model = null
	if _hand_attachment == null:
		return
	var old_w := _hand_attachment.get_children()
	for c in old_w:
		if c == _tp_muzzle_sprite or c == _tp_muzzle_light:
			continue
		_hand_attachment.remove_child(c)
		c.queue_free()
	if not is_alive or wid.is_empty() or not GameData.weapons.has(wid):
		return
	var spec: Dictionary = GameData.weapons[wid]
	var p_name := String(spec.get("p_model", "p_" + wid))
	var p_sc := GameData.get_model_scene("weapons/" + p_name)
	if p_sc:
		var p_inst := p_sc.instantiate() as Node3D
		if p_inst == null:
			return
		_configure_character_meshes(p_inst, "w_held")
		p_inst.scale = Vector3.ONE * GameData.get_world_model_scale(wid)
		_hand_attachment.add_child(p_inst)
		_held_weapon_model = p_inst
		_held_weapon_rest_transform = p_inst.transform


func _stabilize_held_weapon() -> void:
	if is_instance_valid(_held_weapon_model):
		# The p_ mesh has no root animation. Keep its normal-scale local transform
		# fixed to the hand bone even after weapon switches and upper-body clips.
		_held_weapon_model.transform = _held_weapon_rest_transform


func _configure_character_meshes(n: Node, material_mode: String = "char") -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.layers = 2
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				var styled := GameData.get_styled_model_material(mat, material_mode)
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_configure_character_meshes(c, material_mode)


func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var a := _find_anim(c)
		if a:
			return a
	return null


func spawn_for_round(pos: Vector3, yaw_rad: float, reset_weapons: bool) -> void:
	var was_alive := is_alive
	if is_human:
		AudioManager.play_2d(AudioManager.cue_path("respawn"), -8.0)
	is_alive = true
	health = 100
	flash_alpha = 0.0
	stamina_factor = 1.0
	is_crouching = false
	velocity = Vector3.ZERO
	in_water = false
	water_depth = 0.0
	_was_in_water = false

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
	_prev_phys_pos = floor_pos
	_step_smooth_y = 0.0
	_visual_crouch_t = 0.0
	_tp_recoil_pitch = 0.0
	_tp_flinch_angles = Vector2.ZERO
	_pain_sound_cd = 0.0
	_corpse_vel = Vector3.ZERO
	_corpse_settled = true
	_corpse_blood_spawned = false
	_gait_blend_alpha = 1.0
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
	var pitch := look_pitch + deg_to_rad(punch_deg.x)
	var yaw := look_yaw + deg_to_rad(punch_deg.y)
	return Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ)


func apply_flashbang(duration: float) -> void:
	flash_alpha = clampf(maxf(flash_alpha, duration * 0.42), 0.0, 2.2)


func _update_hull_height(crouch_want: bool) -> void:
	if crouch_want == is_crouching:
		return
	if not crouch_want and is_crouching:
		# Verify full capsule head clearance before standing up so shoulders never wedge under vents/tables!
		var headroom: float = STAND_HEIGHT - CROUCH_HEIGHT + 0.04
		if test_move(global_transform, Vector3(0.0, headroom, 0.0)):
			return
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(
			global_position + Vector3(0.0, CROUCH_HEIGHT, 0.0),
			global_position + Vector3(0.0, STAND_HEIGHT + 0.05, 0.0)
		)
		q.collision_mask = 1
		if not space.intersect_ray(q).is_empty():
			return

	# Authentic GoldSrc PM_Duck mid-air leg tuck: pull feet upward onto crates/windowsills while keeping visual height seamless!
	var air_tuck_lift: float = 0.0
	if crouch_want and not is_crouching and not is_on_floor() and not on_ladder:
		for cand in [0.40, 0.26, 0.14]:
			var l_val: float = float(cand)
			if not test_move(global_transform, Vector3(0.0, l_val, 0.0)):
				air_tuck_lift = l_val
				break

	is_crouching = crouch_want
	var h := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	_capsule.height = h
	_col_shape.position.y = h * 0.5
	if air_tuck_lift > 0.0:
		global_position.y += air_tuck_lift
		_prev_phys_pos.y += air_tuck_lift
		_step_smooth_y = clampf(_step_smooth_y - air_tuck_lift, -0.68, 0.68)
	if _body_root:
		_body_root.position.y = MODEL_CROUCH_OFFSET_Y if is_crouching else MODEL_STAND_OFFSET_Y


func apply_goldsrc_movement(wish_dir_world: Vector3, want_jump: bool, want_crouch: bool, want_walk: bool, delta: float) -> void:
	_prev_phys_pos = global_position
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
	var lad_info: Dictionary = {}
	var actor_h: float = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("get_ladder_info"):
		lad_info = RoundManager.game_world.get_ladder_info(global_position, actor_h)
		on_ladder = bool(lad_info.get("on_ladder", false))

	in_water = false
	water_depth = 0.0
	if is_instance_valid(RoundManager.game_world) and RoundManager.game_world.has_method("get_water_info"):
		var water_info: Dictionary = RoundManager.game_world.get_water_info(global_position, actor_h)
		in_water = bool(water_info.get("in_water", false))
		water_depth = float(water_info.get("depth", 0.0))
		var water_fx := RoundManager.game_world.get("water") as WaterEffects
		if in_water and not _was_in_water and water_fx != null:
			var splash_strength := clampf(0.65 + absf(velocity.y) * 0.10, 0.65, 1.65)
			water_fx.splash_at(global_position, splash_strength, team)
	_was_in_water = in_water

	var max_spd := weapon_ctrl.get_max_speed_gs() * GameData.SCALE * stamina_factor
	if in_water:
		max_spd *= lerpf(0.82, 0.58, clampf(water_depth / 1.45, 0.0, 1.0))
	if is_crouching:
		max_spd *= 0.34
	elif is_walking:
		max_spd *= 0.52

	if on_ladder:
		var climb_spd := 5.75
		var n_ladder: Vector3 = lad_info.get("normal", Vector3(0, 0, 1))
		var top_y: float = float(lad_info.get("top_y", global_position.y + 4.0))
		var lad_center: Vector3 = lad_info.get("center", global_position)
		var lat_axis: Vector3 = Vector3.UP.cross(n_ladder).normalized()

		if want_jump:
			# Classic CS 1.5 Spacebar kick-off perpendicular to ladder!
			velocity = n_ladder * 5.6 + Vector3(0.0, 2.75, 0.0)
			on_ladder = false
			move_and_slide()
			_tick_footsteps(delta, false)
			return

		if not is_human and absf(bot_ladder_dir) > 0.1:
			# Precision AI Bot ladder climb + automatic top-platform step-forward
			var to_c: Vector3 = lad_center - global_position
			var lat_err: float = to_c.dot(lat_axis)
			if bot_ladder_anchor_valid:
				# Authored rung origins may avoid trim on one side of a narrow
				# opening. Retain that small lateral offset rather than recentering
				# the capsule under the roof lip on every climb frame.
				lat_err += clampf((bot_ladder_anchor - lad_center).dot(lat_axis), -0.32, 0.32)
			velocity = lat_axis * clampf(lat_err * 5.0, -2.5, 2.5)
			if bot_ladder_dir > 0.0:
				velocity.y = climb_spd
				if global_position.y >= top_y - 0.48:
					velocity += (-n_ladder) * 4.4
				else:
					velocity += (-n_ladder) * 1.6
			else:
				velocity.y = -climb_spd
				# Keep clearing the top lip until the capsule is safely below it.
				# Switching to wall attraction on the first airborne frame can
				# pin a descending bot against the ledge with zero actual motion.
				if is_on_floor():
					velocity += n_ladder * 3.8
				elif global_position.y > top_y - 1.15:
					velocity += n_ladder * 1.2
				else:
					velocity += (-n_ladder) * 1.4
		elif not is_human and wish_dir_world.length_squared() > 0.01:
			# Horizontal entry/dismount: do not interpret a level bot's aim as
			# human climb input merely because its feet overlap the ladder brush.
			velocity = Vector3(wish_dir_world.x * max_spd, 0.0, wish_dir_world.z * max_spd)
		elif wish_dir_world.length_squared() > 0.01:
			var fwd := get_look_forward()
			var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
			if flat_fwd.length_squared() > 0.001:
				flat_fwd = flat_fwd.normalized()
			else:
				flat_fwd = -n_ladder
			var fb_dot: float = wish_dir_world.dot(flat_fwd)
			var lat_in: float = wish_dir_world.dot(lat_axis)
			var vy: float = 0.0
			var look_down: bool = (fwd.y < -0.28)
			if fb_dot > 0.15:
				vy = -climb_spd if look_down else climb_spd
			elif fb_dot < -0.15:
				vy = climb_spd if look_down else -climb_spd

			# Allow walking cleanly off the base of the ladder when on floor & moving away
			var moving_away: bool = wish_dir_world.dot(n_ladder) > 0.42
			if is_on_floor() and (vy <= 0.0) and moving_away:
				velocity.x = wish_dir_world.x * max_spd
				velocity.z = wish_dir_world.z * max_spd
				velocity.y = 0.0
			elif vy > 0.0 and global_position.y >= top_y - 0.56:
				# Smooth top-ledge vault over roof/catwalk/vent lip!
				velocity = (-n_ladder) * 4.3 + lat_axis * (lat_in * 2.4) + Vector3(0.0, 4.0, 0.0)
			else:
				# Glue gently against rungs while climbing up/down or strafing laterally
				velocity = (-n_ladder) * 1.55 + lat_axis * (lat_in * 2.8) + Vector3(0.0, vy, 0.0)
		else:
			velocity = Vector3.ZERO

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
		if in_water:
			# Water resistance cushions a fall and permits a gentle swim upwards
			# while the body intersects the real BSP water surface.
			velocity.y = maxf(velocity.y - GRAVITY_MPS2 * 0.24 * delta, -4.2)
			var water_drag := maxf(0.0, 1.0 - 1.55 * delta)
			velocity.x *= water_drag
			velocity.z *= water_drag
			if want_jump:
				velocity.y = 3.4
		else:
			velocity.y -= GRAVITY_MPS2 * delta

	var prev_vy := velocity.y
	var pre_move_y := global_position.y
	var pre_step_vel := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()

	# Smooth downward stair/curb drops so descending stairs glides just as cleanly as climbing!
	if grounded and is_on_floor() and not want_jump:
		var drop_dy := global_position.y - pre_move_y
		if drop_dy < -0.04 and drop_dy > -0.58:
			_step_smooth_y = clampf(_step_smooth_y - drop_dy, -0.62, 0.62)

	# GoldSrc PM_StepMove: smoothly climb 90-degree BSP stairs, curbs & crate ledges (up to 18u = 0.54m)
	if grounded and is_on_wall() and pre_step_vel.length_squared() > 0.02:
		_try_step_up(pre_step_vel * delta, pre_step_vel)

	# Fall damage & landing sound (GoldSrc > 580u/s = 18.1 m/s)
	if not grounded and is_on_floor():
		if not in_water and prev_vy < -18.2:
			var fall_dmg := int((absf(prev_vy) - 18.0) * 11.0)
			if fall_dmg > 0:
				AudioManager.play_3d("player/pl_fallpain%d.wav" % randi_range(1, 3), global_position, 0.0, 22.0)
				damaged_from.emit(global_position, fall_dmg, false)
				_apply_raw_hp_loss(null, fall_dmg, "world", false)
		elif not in_water and prev_vy < -6.5 and not is_walking and not is_crouching:
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

	if not is_on_floor():
		return
	var water_fx: WaterEffects = null
	if in_water and is_instance_valid(RoundManager.game_world):
		water_fx = RoundManager.game_world.get("water") as WaterEffects
	var water_step := water_fx != null
	if (is_crouching or is_walking) and not water_step:
		return
	var hspd := Vector2(velocity.x, velocity.z).length()
	if hspd < (1.0 if water_step else 3.6):
		return
	_step_accum += hspd * delta * (0.34 if water_step else 0.42)
	if _step_accum >= 1.0:
		_step_accum = 0.0
		if water_step:
			water_fx.footstep_at(global_position, team, is_crouching or is_walking)
		else:
			var mchar := _sample_floor_material()
			AudioManager.play_footstep(mchar, global_position, team)


func _try_step_up(horiz_motion: Vector3, preserve_hvel: Vector3) -> void:
	var step_dir := horiz_motion.normalized() * maxf(horiz_motion.length(), 0.08)
	var old_y := global_position.y
	# Test progressive step heights so low tunnel/doorway arches still step over curbs cleanly!
	for sh in [0.22, 0.38, STEP_HEIGHT]:
		var up_vec := Vector3(0.0, float(sh), 0.0)
		if test_move(global_transform, up_vec):
			continue
		var raised_xf := global_transform.translated(up_vec)
		if test_move(raised_xf, step_dir):
			continue
		global_position += up_vec + step_dir
		move_and_collide(Vector3(0.0, -float(sh) - 0.06, 0.0))
		var climbed_dy := global_position.y - old_y
		if climbed_dy > 0.01:
			_step_smooth_y = clampf(_step_smooth_y - climbed_dy, -0.58, 0.58)
		velocity.x = preserve_hvel.x
		velocity.z = preserve_hvel.z
		return


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
	pass


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
		6, 7:
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
		var awav := AudioManager.cue_path("headshot_armor") if hitgroup == 1 else "player/bhit_kevlar-1.wav"
		AudioManager.play_3d(awav, hit_pos, 0.0, 26.0)
	else:
		var fwav := ("player/headshot%d.wav" % randi_range(1, 3)) if hitgroup == 1 else ("player/bhit_flesh-%d.wav" % randi_range(1, 3))
		AudioManager.play_3d(fwav, hit_pos, 0.0, 26.0)

	# CS 1.5 bullet tagging slowdown, directional torso jolt & hit flinch
	stamina_factor = clampf(stamina_factor - 0.28, 0.42, 1.0)
	_last_hitgroup = hitgroup
	trigger_upper_body_action("flinch_head" if hitgroup == 1 else "flinch_gut")

	var src_pos: Vector3 = attacker.global_position if (is_instance_valid(attacker) and attacker != self) else hit_pos
	var has_src: bool = is_instance_valid(attacker) and attacker != self
	var jolt_scale: float = clampf(dmg / 32.0, 0.55, 1.65)
	if has_src:
		var incoming_dir: Vector3 = (global_position - src_pos)
		incoming_dir.y = 0.0
		if incoming_dir.length_squared() > 0.001:
			incoming_dir = incoming_dir.normalized()
			var yaw_b := Basis(Vector3.UP, look_yaw)
			var f_dot: float = (-yaw_b.z).dot(incoming_dir)
			var r_dot: float = yaw_b.x.dot(incoming_dir)
			_tp_flinch_angles.x = clampf(_tp_flinch_angles.x + f_dot * deg_to_rad(9.5 * jolt_scale), deg_to_rad(-18.0), deg_to_rad(18.0))
			_tp_flinch_angles.y = clampf(_tp_flinch_angles.y + r_dot * deg_to_rad(8.5 * jolt_scale), deg_to_rad(-16.0), deg_to_rad(16.0))
			velocity += incoming_dir * clampf(dmg * 0.026, 0.35, 1.85)
	else:
		_tp_flinch_angles.x = clampf(_tp_flinch_angles.x + deg_to_rad(7.0), deg_to_rad(-18.0), deg_to_rad(18.0))

	var final_hp_loss := maxi(1, int(dmg))
	if _pain_sound_cd <= 0.0 and health - final_hp_loss > 0 and final_hp_loss >= 12:
		_pain_sound_cd = 0.55
		var pain_ids := [2, 4, 5, 6, 7]
		var pid: int = pain_ids[randi() % pain_ids.size()]
		AudioManager.play_3d("player/pl_pain%d.wav" % pid, global_position, -2.5, 22.0, randf_range(0.96, 1.05))

	damaged_from.emit(src_pos, final_hp_loss, has_src)
	_apply_raw_hp_loss(attacker, final_hp_loss, weapon_id, hitgroup == 1)
	if is_alive:
		_on_taken_damage_from(attacker, hit_pos)


func apply_explosion_damage(attacker: Node3D, raw_dmg: float, weapon_id: String, blast_origin: Vector3 = Vector3.INF) -> void:
	if not is_alive:
		return
	var dmg := raw_dmg
	if armor > 0:
		var absorbed := minf(float(armor), dmg * 0.35)
		armor = maxi(0, armor - int(absorbed))
		dmg -= absorbed

	var src_pt: Vector3 = blast_origin
	if not src_pt.is_finite():
		src_pt = attacker.global_position if is_instance_valid(attacker) else global_position
	var away: Vector3 = (global_position + Vector3(0.0, 0.9, 0.0)) - src_pt
	var push_scale: float = clampf(raw_dmg / 65.0, 0.25, 1.45)
	if away.length_squared() > 0.001:
		var away_dir: Vector3 = away.normalized()
		velocity += Vector3(away_dir.x * 5.8 * push_scale, maxf(1.6, away_dir.y * 3.8) * push_scale, away_dir.z * 5.8 * push_scale)
	stamina_factor = clampf(stamina_factor - 0.30 * push_scale, 0.42, 1.0)
	trigger_upper_body_action("flinch_gut")

	var loss_i := maxi(1, int(dmg))
	if _pain_sound_cd <= 0.0 and health - loss_i > 0:
		_pain_sound_cd = 0.55
		var pain_ids := [2, 4, 5, 6, 7]
		var pid: int = pain_ids[randi() % pain_ids.size()]
		AudioManager.play_3d("player/pl_pain%d.wav" % pid, global_position, -1.5, 24.0)

	damaged_from.emit(src_pt, loss_i, src_pt.distance_squared_to(global_position) > 0.04)
	_apply_raw_hp_loss(attacker, loss_i, weapon_id, false)
	if is_alive:
		_on_taken_damage_from(attacker, src_pt)


func _on_taken_damage_from(_attacker: Node3D, _hit_pos: Vector3) -> void:
	pass


func _apply_raw_hp_loss(attacker: Node3D, dmg_int: int, weapon_id: String, headshot: bool) -> void:
	health = maxi(0, health - dmg_int)
	health_armor_changed.emit(health, armor, has_helmet)
	if health <= 0:
		_die(attacker, weapon_id, headshot)


func _die(killer: Node3D, weapon_id: String, headshot: bool) -> void:
	if is_human and _body_root != null:
		_gait_yaw = look_yaw
		_evaluate_character_pose(0.016)
	is_alive = false
	if is_instance_valid(_bullet_hitboxes):
		_bullet_hitboxes.sync_pose()
	if is_instance_valid(killer) and killer != self and bool(killer.get("is_human")) and String(killer.get("team")) != team:
		AudioManager.play_2d(AudioManager.cue_path("kill_confirm"), -8.0)
	_col_shape.set_deferred("disabled", true)
	AudioManager.play_3d("player/die%d.wav" % randi_range(1, 3), global_position, 1.0, 32.0)

	# Drop primary (or pistol), C4, CT Defuse Kit, Zeus and ALL carried grenades.
	var drop_w := String(weapon_ctrl.slots.get(1, ""))
	if drop_w.is_empty():
		drop_w = String(weapon_ctrl.slots.get(2, ""))
	if not drop_w.is_empty():
		_spawn_drop_entity(drop_w, 0)
	if String(weapon_ctrl.slots.get(5, "")) == "c4":
		_spawn_drop_entity("c4", 1)
		weapon_ctrl.slots[5] = ""
	var equipment_drop := String(weapon_ctrl.slots.get(4, ""))
	if not equipment_drop.is_empty():
		if int(weapon_ctrl.clips.get(equipment_drop, 0)) > 0:
			_spawn_drop_entity(equipment_drop, 1)
		weapon_ctrl.slots[4] = ""
	if has_defuser:
		has_defuser = false
		_spawn_drop_entity("defuser", 2)

	# If pin was already pulled, drop a live armed grenade; then drop all remaining carried grenades!
	weapon_ctrl.drop_pulled_grenade_on_death()
	var gren_order := ["hegrenade", "flashbang", "smokegrenade", "decoy", "molotov", "incendiary"]
	var gren_spread_idx: int = 3
	for gid_k in gren_order:
		var gid_s := String(gid_k)
		var g_cnt := int(weapon_ctrl.grenades.get(gid_s, 0))
		for _gi in range(g_cnt):
			_spawn_drop_entity(gid_s, gren_spread_idx)
			gren_spread_idx += 1
		weapon_ctrl.grenades[gid_s] = 0

	if _hand_attachment != null:
		var held_kids := _hand_attachment.get_children()
		for c in held_kids:
			if c == _tp_muzzle_sprite or c == _tp_muzzle_light:
				c.visible = false
				continue
			_hand_attachment.remove_child(c)
			c.queue_free()
	_held_weapon_model = null

	# Snapshot current live bone pose so death animation crossfades smoothly without popping!
	_death_from_pos.clear()
	_death_from_rot.clear()
	if _skel != null:
		var nb_snap: int = _skel.get_bone_count()
		for bi in range(nb_snap):
			_death_from_pos.append(_skel.get_bone_pose_position(bi))
			_death_from_rot.append(_skel.get_bone_pose_rotation(bi))

	_corpse_vel = Vector3(velocity.x * 0.55, minf(2.5, velocity.y), velocity.z * 0.55)
	_corpse_settled = false
	_corpse_blood_spawned = false

	_body_root.visible = true
	_body_root.rotation.y = look_yaw
	_death_anim_time = 0.0

	if is_crouching and _anim_res_map.has("crouch_die"):
		_death_anim_key = "crouch_die"
	elif headshot and _anim_res_map.has("head"):
		_death_anim_key = "head"
	elif _last_hitgroup == 3 and randf() < 0.45 and _anim_res_map.has("gutshot"):
		_death_anim_key = "gutshot"
	elif is_instance_valid(killer) and killer != self and randf() < 0.55:
		var to_killer := (killer.global_position - global_position)
		to_killer.y = 0.0
		if to_killer.length_squared() > 0.01:
			to_killer = to_killer.normalized()
			var fwd := Basis(Vector3.UP, look_yaw) * Vector3.FORWARD
			var right := Basis(Vector3.UP, look_yaw).x
			var df := fwd.dot(to_killer)
			var dr := right.dot(to_killer)
			if absf(df) >= absf(dr):
				_death_anim_key = "back" if df > 0.0 else "forward"
			else:
				_death_anim_key = "left" if dr > 0.0 else "right"
	if _death_anim_key.is_empty() or not _anim_res_map.has(_death_anim_key):
		_death_anim_key = "death%d" % randi_range(1, 3)
	_evaluate_character_pose(0.0)

	RoundManager.notify_actor_killed(self, killer, weapon_id, headshot)
	actor_died.emit(self, killer)


func drop_current_weapon() -> void:
	if not is_alive:
		return
	var wid := weapon_ctrl.current_weapon_id
	var spec := weapon_ctrl.get_current_spec()
	var sl := int(spec.get("slot", 3))
	if sl == 4 and bool(spec.get("grenade", false)):
		if weapon_ctrl._grenade_pin_pulled:
			return
		var g_cur := int(weapon_ctrl.grenades.get(wid, 0))
		if g_cur <= 0:
			return
		weapon_ctrl.grenades[wid] = g_cur - 1
		_spawn_drop_entity(wid, 0)
		if int(weapon_ctrl.grenades.get(wid, 0)) > 0:
			weapon_ctrl.equip_weapon_by_id(wid)
		elif not weapon_ctrl.equip_slot(4):
			if not weapon_ctrl.equip_slot(1):
				if not weapon_ctrl.equip_slot(2):
					weapon_ctrl.equip_slot(3)
		return
	if sl not in [1, 2, 5]:
		return
	_spawn_drop_entity(wid, 0)
	weapon_ctrl.slots[sl] = ""
	if not weapon_ctrl.equip_slot(1):
		if not weapon_ctrl.equip_slot(2):
			weapon_ctrl.equip_slot(3)


func _spawn_drop_entity(item_id: String, spread_idx: int = 0) -> void:
	if not is_instance_valid(RoundManager.game_world):
		return
	var drop := DroppedWeapon.new()
	RoundManager.game_world.add_child(drop)

	# Start strictly inside the actor's collision capsule height so crouching under vents/ceilings never spawns out-of-bounds!
	var chest_h: float = 0.54 if is_crouching else 0.94
	var safe_origin: Vector3 = global_position + Vector3(0.0, chest_h, 0.0)

	var base_fwd: Vector3 = get_look_forward()
	var flat_fwd := Vector3(base_fwd.x, 0.0, base_fwd.z)
	if flat_fwd.length_squared() < 0.001:
		flat_fwd = Basis(Vector3.UP, look_yaw) * Vector3.FORWARD
	else:
		flat_fwd = flat_fwd.normalized()

	var launch_dir: Vector3 = base_fwd
	var launch_spd: float = 5.0
	var up_boost: float = 1.85
	if spread_idx > 0:
		# Fan secondary death drops (C4, defuser, grenades) radially so items never stack on the same point!
		var fan_ang: float = float(spread_idx) * 1.18 + randf_range(-0.22, 0.22)
		launch_dir = Basis(Vector3.UP, fan_ang) * flat_fwd
		launch_spd = randf_range(2.6, 3.9)
		up_boost = randf_range(1.65, 2.35)

	# Sweep-check forward spawn offset against Layer 1 walls/crates/doors so throwing nose-to-wall never tunnels!
	var spawn_pos: Vector3 = safe_origin
	var desired_ofs: Vector3 = Vector3(launch_dir.x, 0.0, launch_dir.z)
	if desired_ofs.length_squared() > 0.001:
		desired_ofs = desired_ofs.normalized() * 0.28
		if get_world_3d() != null:
			var space := get_world_3d().direct_space_state
			var q_sp := PhysicsRayQueryParameters3D.create(safe_origin, safe_origin + desired_ofs * 1.65)
			q_sp.collision_mask = 1
			q_sp.hit_from_inside = true
			var h_sp: Dictionary = space.intersect_ray(q_sp)
			if h_sp.is_empty():
				spawn_pos = safe_origin + desired_ofs
			else:
				var wn: Vector3 = h_sp["normal"]
				if wn.length_squared() > 0.001:
					launch_dir = launch_dir.bounce(wn.normalized()) * 0.45

	drop.global_position = spawn_pos

	var clip := int(weapon_ctrl.clips.get(item_id, 0))
	var res := 0
	var is_gren := false
	if GameData.weapons.has(item_id):
		is_gren = bool(GameData.weapons[item_id].get("grenade", false))
		if is_gren:
			clip = 1
		else:
			var at := String(GameData.weapons[item_id].get("ammo_type", "none"))
			res = int(weapon_ctrl.ammo_pool.get(at, 0))

	var throw_v: Vector3 = launch_dir * launch_spd + Vector3(0.0, up_boost, 0.0) + velocity * 0.28
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
	var spec_d: Dictionary = GameData.weapons[id]
	if bool(spec_d.get("grenade", false)):
		var max_g := int(spec_d.get("max_ammo", 1))
		if int(weapon_ctrl.grenades.get(id, 0)) < max_g:
			weapon_ctrl.give_weapon(id, 1, 0)
			weapon_ctrl._emit_ammo()
			AudioManager.play_3d("items/kevlar.wav", global_position, -4.0, 14.0, 1.12)
			return true
		return false
	var sl := int(spec_d.get("slot", 1))
	var held_id := String(weapon_ctrl.slots.get(sl, ""))
	var replacing_spent_equipment := sl == 4 and held_id == id and int(weapon_ctrl.clips.get(id, 0)) <= 0
	if held_id.is_empty() or replacing_spent_equipment:
		weapon_ctrl.give_weapon(id, drop.clip_ammo, drop.reserve_ammo)
		weapon_ctrl.silenced_state[id] = drop.silenced
		AudioManager.play_3d("items/kevlar.wav", global_position, -3.0, 14.0)
		if sl == 1 and weapon_ctrl.current_weapon_id != "c4":
			weapon_ctrl.equip_slot(1)
		return true
	return false


## Team economy support: physically drop a gifted primary weapon toward a broke teammate
## during freezetime (the donor keeps its reserve ammo & rebuys its own gun afterwards).
func drop_weapon_gift(recipient: CSActor, wid: String, clip: int, reserve: int) -> DroppedWeapon:
	if not is_instance_valid(RoundManager.game_world) or not is_inside_tree() or wid.is_empty():
		return null
	var drop := DroppedWeapon.new()
	RoundManager.game_world.add_child(drop)

	var drop_pos: Vector3 = global_position + Vector3(0.0, 0.55, 0.0)
	var toss := Vector3(0.0, 0.7, 0.0)
	if is_instance_valid(recipient):
		var to_rec: Vector3 = recipient.global_position - global_position
		to_rec.y = 0.0
		if to_rec.length() > 0.35:
			var flat := to_rec.normalized()
			drop_pos += flat * minf(1.05, to_rec.length() * 0.55)
			toss = flat * 1.1 + Vector3(0.0, 0.85, 0.0)

	drop.global_position = drop_pos
	drop.setup_drop(wid, clip, reserve, toss, bool(weapon_ctrl.silenced_state.get(wid, false)))
	drop.pickup_lock_actor = self
	drop.pickup_lock_time = 8.0
	RoundManager.dropped_items.append(drop)
	return drop


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
	var held_id := String(weapon_ctrl.slots.get(sl, ""))
	if held_id == wid and (sl != 4 or int(weapon_ctrl.clips.get(wid, 0)) > 0):
		return false
	if not held_id.is_empty() and (sl != 4 or int(weapon_ctrl.clips.get(held_id, 0)) > 0):
		_spawn_drop_entity(held_id)

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
		AudioManager.play_3d("weapons/archi/cs2_ak47/clipin.wav", global_position, -3.0, 14.0)
		weapon_ctrl._emit_ammo()
	return bought
