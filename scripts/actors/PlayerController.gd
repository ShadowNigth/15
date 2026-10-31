class_name PlayerController
extends CSActor
## First-person human Counter-Strike 1.5 controller:
##   - GoldSrc mouse look, viewmodel rig (v_*.glb + animations + muzzleflash + bob/sway)
##   - Sniper scope FOV, tactical flashlight (F), Nightvision (N), Use/Defuse/Hostage (E)
##   - Spectator camera cycling when dead

signal defuse_progress_changed(ratio: float)
signal scoped_overlay_changed(active: bool)
signal nvg_toggled(active: bool)
signal spectator_target_changed(target_name: String)

var camera: Camera3D = null
var viewmodel_pivot: Node3D = null
var viewmodel_holder: Node3D = null
var flashlight_spot: SpotLight3D = null
var nvg_light: OmniLight3D = null

var _vm_layer: CanvasLayer = null
var _vm_container: SubViewportContainer = null
var _vm_viewport: SubViewport = null
var _vm_camera: Camera3D = null
var _vm_anim: AnimationPlayer = null
var _muzzle_sprite: Sprite3D = null
var _muzzle_light: OmniLight3D = null
var _muzzle_timer: float = 0.0
var _bob_phase: float = 0.0
var _sway_offset: Vector2 = Vector2.ZERO
var _vm_kick_z: float = 0.0
var _vm_kick_pitch: float = 0.0
var _land_dip: float = 0.0
var _was_on_floor: bool = true
var _cur_vm_model_name: String = ""
var _pending_vm_events: Array = []
var _vm_anim_elapsed: float = 0.0
var _shake_trauma: float = 0.0
var _shake_time: float = 0.0
var _elite_muzzle_left: bool = false
var _defusing_c4: PlantedC4 = null
var _spec_index: int = 0
var ui_blocking_input: bool = false


func _ready() -> void:
	is_human = true
	actor_name = GameData.player_name
	super._ready()

	camera = Camera3D.new()
	camera.name = "FPSCamera"
	camera.rotation_order = EULER_ORDER_YXZ
	camera.fov = GameData.fov
	camera.near = 0.05
	camera.far = 1600.0
	camera.cull_mask = 3  # Layers 1 (World) + 2 (Characters/Props); Layer 3 (mask 4) is rendered by _vm_camera!
	camera.position = Vector3(0.0, 1.66, 0.0)
	camera.current = true
	add_child(camera)

	# Dedicated transparent SubViewport for CS 1.5 first-person weapon viewmodel:
	# - Own clean depth buffer -> gun NEVER clips into walls or near-plane!
	# - Native 1:1 GoldSrc metric scale -> crisp textures & authentic 65-deg viewmodel FOV!
	_vm_layer = CanvasLayer.new()
	_vm_layer.name = "ViewModelLayer"
	_vm_layer.layer = 2
	add_child(_vm_layer)

	_vm_container = SubViewportContainer.new()
	_vm_container.name = "ViewModelContainer"
	_vm_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vm_container.stretch = true
	_vm_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vm_layer.add_child(_vm_container)

	_vm_viewport = SubViewport.new()
	_vm_viewport.name = "ViewModelViewport"
	_vm_viewport.transparent_bg = true
	_vm_viewport.handle_input_locally = false
	_vm_viewport.msaa_3d = Viewport.MSAA_2X
	_vm_viewport.world_3d = get_world_3d()
	_vm_container.add_child(_vm_viewport)

	_vm_camera = Camera3D.new()
	_vm_camera.name = "ViewModelCamera"
	_vm_camera.rotation_order = EULER_ORDER_YXZ
	_vm_camera.fov = 65.0
	_vm_camera.near = 0.015
	_vm_camera.far = 6.0
	_vm_camera.cull_mask = 4  # Visual Layer 3 ONLY (first-person weapon + muzzle flash)
	_vm_camera.current = true
	_vm_viewport.add_child(_vm_camera)

	viewmodel_pivot = Node3D.new()
	viewmodel_pivot.name = "ViewModelPivot"
	_vm_camera.add_child(viewmodel_pivot)

	viewmodel_holder = Node3D.new()
	viewmodel_holder.name = "ViewModelHolder"
	viewmodel_pivot.add_child(viewmodel_holder)

	_muzzle_sprite = Sprite3D.new()
	_muzzle_sprite.layers = 4
	_muzzle_sprite.texture = GameData.get_texture("res://assets/sprites/muzzleflash1.png")
	_muzzle_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_sprite.pixel_size = 0.0028
	_muzzle_sprite.modulate = Color(1.0, 0.88, 0.55, 0.92)
	_muzzle_sprite.position = Vector3(0.18, -0.11, -0.68)
	_muzzle_sprite.visible = false
	viewmodel_pivot.add_child(_muzzle_sprite)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.82, 0.45)
	_muzzle_light.light_energy = 2.8
	_muzzle_light.omni_range = 7.5
	_muzzle_light.visible = false
	camera.add_child(_muzzle_light)

	flashlight_spot = SpotLight3D.new()
	flashlight_spot.light_color = Color(1.0, 0.98, 0.90)
	flashlight_spot.light_energy = 2.6
	flashlight_spot.spot_range = 26.0
	flashlight_spot.spot_angle = 28.0
	flashlight_spot.visible = false
	camera.add_child(flashlight_spot)

	nvg_light = OmniLight3D.new()
	nvg_light.light_color = Color(0.25, 1.0, 0.35)
	nvg_light.light_energy = 1.8
	nvg_light.omni_range = 32.0
	nvg_light.visible = false
	camera.add_child(nvg_light)

	weapon_ctrl.weapon_switched.connect(_on_weapon_switched)
	weapon_ctrl.fired_shot.connect(_on_fired_shot)
	weapon_ctrl.zoom_changed.connect(_on_zoom_changed)


func spawn_for_round(pos: Vector3, yaw_rad: float, reset_weapons: bool) -> void:
	super.spawn_for_round(pos, yaw_rad, reset_weapons)
	camera.top_level = false
	camera.position = Vector3(0.0, 1.66, 0.0)
	camera.rotation = Vector3(0.0, look_yaw, 0.0)
	camera.current = true
	camera.fov = GameData.fov
	if _vm_viewport and _vm_viewport.world_3d != get_world_3d():
		_vm_viewport.world_3d = get_world_3d()
	if _vm_container:
		_vm_container.visible = true
	viewmodel_pivot.visible = true
	flashlight_spot.visible = false
	nvg_light.visible = nvg_active
	nvg_toggled.emit(nvg_active)
	spectator_target_changed.emit("")
	_rebuild_viewmodel(weapon_ctrl.current_weapon_id)


func _unhandled_input(event: InputEvent) -> void:
	if ui_blocking_input:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens := GameData.mouse_sensitivity * 0.0022
		if camera.fov < 60.0:
			sens *= (camera.fov / 74.0)
		var mm := event as InputEventMouseMotion
		var pitch_sign := 1.0 if GameData.invert_mouse_y else -1.0
		look_yaw -= mm.relative.x * sens
		look_pitch = clampf(look_pitch + mm.relative.y * sens * pitch_sign, deg_to_rad(-89.0), deg_to_rad(89.0))
		_sway_offset.x = clampf(_sway_offset.x - mm.relative.x * 0.00025, -0.02, 0.02)
		_sway_offset.y = clampf(_sway_offset.y + mm.relative.y * 0.00025, -0.02, 0.02)

	if not is_alive:
		if event.is_action_pressed("attack1") or event.is_action_pressed("jump"):
			_cycle_spectator(1)
		elif event.is_action_pressed("attack2"):
			_cycle_spectator(-1)
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_weapon_slot(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_weapon_slot(1)

	if event.is_action_pressed("slot_1"):
		weapon_ctrl.equip_slot(1)
	elif event.is_action_pressed("slot_2"):
		weapon_ctrl.equip_slot(2)
	elif event.is_action_pressed("slot_3"):
		weapon_ctrl.equip_slot(3)
	elif event.is_action_pressed("slot_4"):
		weapon_ctrl.equip_slot(4)
	elif event.is_action_pressed("slot_5"):
		weapon_ctrl.equip_slot(5)
	elif event.is_action_pressed("last_weapon"):
		weapon_ctrl.quick_switch_last()
	elif event.is_action_pressed("reload"):
		weapon_ctrl.start_reload()
	elif event.is_action_pressed("drop"):
		drop_current_weapon()
	elif event.is_action_pressed("attack2"):
		weapon_ctrl.trigger_secondary()
	elif event.is_action_pressed("buy_ammo1"):
		buy_ammo_for_slot(1, false)
	elif event.is_action_pressed("buy_ammo2"):
		buy_ammo_for_slot(2, false)
	elif event.is_action_pressed("flashlight"):
		flashlight_spot.visible = not flashlight_spot.visible
		AudioManager.play_3d("items/nvg_off.wav", global_position, -6.0, 12.0, 1.35)
	elif event.is_action_pressed("nightvision") and has_nvg:
		nvg_active = not nvg_active
		nvg_light.visible = nvg_active
		AudioManager.play_2d("items/nvg_on.wav" if nvg_active else "items/nvg_off.wav", -3.0)
		nvg_toggled.emit(nvg_active)


func _cycle_weapon_slot(step: int) -> void:
	var order := [1, 2, 3, 4, 5]
	var cur_slot := int(weapon_ctrl.get_current_spec().get("slot", 3))
	var idx := order.find(cur_slot)
	for k in range(1, order.size() + 1):
		var next_s: int = order[(idx + step * k + order.size() * 4) % order.size()]
		if weapon_ctrl.equip_slot(next_s):
			return


func _physics_process(delta: float) -> void:
	if _muzzle_timer > 0.0:
		_muzzle_timer -= delta
		if _muzzle_timer <= 0.0:
			_muzzle_sprite.visible = false
			_muzzle_light.visible = false

	# Tick frame-exact StudioMDL 5004 weapon foley sound events synced to viewmodel animation!
	if is_alive and not _pending_vm_events.is_empty() and _vm_anim and _vm_anim.is_playing():
		_vm_anim_elapsed += delta
		while not _pending_vm_events.is_empty():
			var ev: Dictionary = _pending_vm_events[0]
			if float(ev.get("t", 0.0)) <= _vm_anim_elapsed + 0.004:
				var wav := String(ev.get("wav", ""))
				if not wav.is_empty():
					AudioManager.play_2d(wav, -2.2, randf_range(0.985, 1.015))
				_pending_vm_events.remove_at(0)
			else:
				break

	if not is_alive:
		_update_spectator_camera(delta)
		return

	var in_vec := Vector2.ZERO
	if not ui_blocking_input:
		in_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var yaw_basis := Basis(Vector3.UP, look_yaw)
	var wish_dir := (yaw_basis * Vector3(in_vec.x, 0.0, in_vec.y))
	if wish_dir.length_squared() > 0.001:
		wish_dir = wish_dir.normalized()

	var want_jump := (not ui_blocking_input) and Input.is_action_just_pressed("jump")
	var want_crouch := (not ui_blocking_input) and Input.is_action_pressed("crouch")
	var want_walk := (not ui_blocking_input) and Input.is_action_pressed("walk")

	var prev_vy := velocity.y
	apply_goldsrc_movement(wish_dir, want_jump, want_crouch, want_walk, delta)
	if is_on_floor() and not _was_on_floor and prev_vy < -3.0:
		_land_dip = clampf(-prev_vy * 0.0042, 0.008, 0.038)
	_was_on_floor = is_on_floor()
	_land_dip = lerpf(_land_dip, 0.0, minf(1.0, 12.0 * delta))

	# Smooth camera eye height & recoil punch angles + explosion camera shake
	var target_eye_y := (0.96 if is_crouching else 1.66) - _land_dip * 1.4
	camera.position.y = lerpf(camera.position.y, target_eye_y, minf(1.0, 14.0 * delta))
	var shake_rot := Vector3.ZERO
	if _shake_trauma > 0.001:
		_shake_time += delta * 38.0
		_shake_trauma = maxf(0.0, _shake_trauma - delta * 2.15)
		var amt := _shake_trauma * _shake_trauma
		shake_rot = Vector3(
			sin(_shake_time * 1.3) * 0.065 * amt,
			cos(_shake_time * 1.7) * 0.055 * amt,
			sin(_shake_time * 2.3) * 0.045 * amt
		)
	var punch := weapon_ctrl.punch_angles
	camera.rotation = Vector3(
		look_pitch + deg_to_rad(punch.x * 1.15) + shake_rot.x,
		look_yaw + deg_to_rad(punch.y * 0.85) + shake_rot.y,
		shake_rot.z
	)
	if _vm_camera:
		_vm_camera.global_transform = camera.global_transform
	if _vm_viewport and _vm_viewport.world_3d != get_world_3d():
		_vm_viewport.world_3d = get_world_3d()

	# Viewmodel bobbing, mouse sway, strafe tilt & recoil spring kickback (classic GoldSrc cl_bob + kick)
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, minf(1.0, 10.0 * delta))
	_vm_kick_z = lerpf(_vm_kick_z, 0.0, minf(1.0, 18.0 * delta))
	_vm_kick_pitch = lerpf(_vm_kick_pitch, 0.0, minf(1.0, 16.0 * delta))
	var hspd := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspd > 0.4:
		_bob_phase += delta * hspd * 1.65
	else:
		_bob_phase += delta * 1.35
	var move_fac := clampf(hspd / 7.0, 0.0, 1.0)
	var bob_x := sin(_bob_phase) * (0.0085 * move_fac + 0.0008)
	var bob_y := absf(cos(_bob_phase)) * (-0.0105 * move_fac) + sin(_bob_phase * 0.5) * 0.0009 - _land_dip * 0.65
	var strafe_roll := -in_vec.x * deg_to_rad(1.15) * move_fac
	viewmodel_holder.scale = Vector3.ONE
	viewmodel_holder.position = Vector3(bob_x + _sway_offset.x, bob_y + _sway_offset.y, _vm_kick_z)
	viewmodel_holder.rotation = Vector3(_vm_kick_pitch, -_sway_offset.x * 1.6, strafe_roll)
	if _vm_container:
		# cs15_retail v_*.mdl models are authored right-handed at scale (1,1,1);
		# flip 2D SubViewportContainer when left-handed (cl_righthand 0) so 3D Skeleton3D never gets negative scale!
		_vm_container.pivot_offset = _vm_container.size * 0.5
		_vm_container.scale = Vector2(1.0 if GameData.right_hand else -1.0, 1.0)
	_muzzle_sprite.position.x = -0.16 if _elite_muzzle_left else 0.18

	# Primary attack (just pressed or held)
	if not ui_blocking_input:
		if Input.is_action_just_pressed("attack1"):
			weapon_ctrl.trigger_primary(false, delta)
		elif Input.is_action_pressed("attack1"):
			weapon_ctrl.trigger_primary(true, delta)
		elif Input.is_action_just_released("attack1"):
			weapon_ctrl.release_primary()

		# Use key (E): Defuse C4, Lead Hostage, Open Door
		_handle_use_interaction(delta)


func _handle_use_interaction(delta: float) -> void:
	if Input.is_action_just_pressed("use"):
		var eye := get_eye_position()
		var fwd := get_look_forward()
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(eye, eye + fwd * 2.8)
		q.collision_mask = 1 | 2
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		if hit:
			var col = hit["collider"]
			if col is HostageNPC:
				(col as HostageNPC).interact(self)
			elif col is Node and col.has_meta("door"):
				var door = col.get_meta("door")
				if is_instance_valid(door) and door.has_method("interact"):
					door.call("interact", self)

	# Continuous hold E to defuse planted C4 (CT only)
	if team == "CT" and Input.is_action_pressed("use") and is_instance_valid(RoundManager.planted_c4):
		var c4 := RoundManager.planted_c4 as PlantedC4
		if c4 and global_position.distance_to(c4.global_position) <= 2.5:
			_defusing_c4 = c4
			var prog := c4.begin_or_continue_defuse(self, delta)
			defuse_progress_changed.emit(prog)
			return

	if _defusing_c4 != null:
		if is_instance_valid(_defusing_c4):
			_defusing_c4.cancel_defuse(self)
		_defusing_c4 = null
		defuse_progress_changed.emit(0.0)


func _on_weapon_switched(wid: String, _spec: Dictionary) -> void:
	scoped_overlay_changed.emit(false)
	camera.fov = GameData.fov
	_rebuild_viewmodel(wid)


func apply_camera_shake(intensity: float) -> void:
	_shake_trauma = clampf(_shake_trauma + intensity, 0.0, 1.35)


func _rebuild_viewmodel(wid: String) -> void:
	var old_children := viewmodel_holder.get_children()
	for c in old_children:
		viewmodel_holder.remove_child(c)
		c.queue_free()
	_vm_anim = null
	_pending_vm_events.clear()
	_vm_anim_elapsed = 0.0
	_elite_muzzle_left = false
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var v_name := String(spec.get("v_model", "v_knife"))
	_cur_vm_model_name = v_name
	var sc := GameData.get_model_scene("weapons/" + v_name)
	if not sc:
		return
	var inst := sc.instantiate()
	# Native GoldSrc camera-space framing (verified across rifles, pistols, knife, grenades & C4)
	inst.position = Vector3(0.0, -0.015, -0.03)
	_prepare_viewmodel_materials(inst)
	viewmodel_holder.add_child(inst)
	_vm_anim = _find_anim(inst)
	if _vm_anim:
		for aname in _vm_anim.get_animation_list():
			var low := aname.to_lower()
			var anim_res := _vm_anim.get_animation(aname)
			if anim_res:
				anim_res.loop_mode = Animation.LOOP_LINEAR if low.begins_with("idle") else Animation.LOOP_NONE
		if not _vm_anim.animation_finished.is_connected(_on_vm_anim_finished):
			_vm_anim.animation_finished.connect(_on_vm_anim_finished)

	var is_sil := bool(weapon_ctrl.silenced_state.get(wid, false)) and bool(spec.get("silencer", false))
	if bool(spec.get("grenade", false)):
		play_viewmodel_sequence(["deploy", "draw", "idle"])
	elif bool(spec.get("silencer", false)) and not is_sil:
		play_viewmodel_sequence(["draw_unsil", "draw", "idle_unsil"])
	else:
		play_viewmodel_sequence(["draw", "deploy", "idle", "idle1", "idle3"])


func _prepare_viewmodel_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.layers = 4  # Visual Layer 3: rendered exclusively by _vm_camera!
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				var styled := GameData.get_styled_model_material(mat, "vm")
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_prepare_viewmodel_materials(c)


func _start_vm_clip(anim_name: String) -> void:
	_vm_anim.stop()
	_vm_anim.play(anim_name)
	_vm_anim.advance(0.0)
	_pending_vm_events.clear()
	_vm_anim_elapsed = 0.0
	if not _cur_vm_model_name.is_empty():
		var mmeta: Dictionary = GameData.models_meta.get("weapons/" + _cur_vm_model_name, {})
		var ev_map: Dictionary = mmeta.get("seq_events", {})
		if ev_map.has(anim_name):
			var raw_evs: Array = ev_map[anim_name]
			for item in raw_evs:
				if item is Dictionary:
					var d_ev := item as Dictionary
					if float(d_ev.get("t", 0.0)) <= 0.01:
						var w0 := String(d_ev.get("wav", ""))
						if not w0.is_empty():
							AudioManager.play_2d(w0, -2.2)
					else:
						_pending_vm_events.append(d_ev)


func play_viewmodel_sequence(candidates: Array) -> void:
	if not _vm_anim:
		return
	var anims := _vm_anim.get_animation_list()
	# 1. Exact match against candidate priority list
	for c in candidates:
		var cname := String(c)
		if anims.has(cname):
			_start_vm_clip(cname)
			return
		for a in anims:
			if a.to_lower() == cname.to_lower():
				_start_vm_clip(a)
				return
	# 2. Prefix / substring fallback
	for c in candidates:
		var clow := String(c).to_lower()
		for a in anims:
			if a.to_lower().begins_with(clow):
				_start_vm_clip(a)
				return
		for a in anims:
			if a.to_lower().find(clow) >= 0:
				_start_vm_clip(a)
				return


func play_viewmodel_anim(preferred: String) -> void:
	play_viewmodel_sequence([preferred])


func _on_vm_anim_finished(anim_name: String) -> void:
	if not _vm_anim or not is_alive:
		return
	var low := anim_name.to_lower()
	# Hold final frame while grenade pin is pulled or while actively throwing/planting
	if low == "pullpin" and weapon_ctrl._grenade_pin_pulled:
		return
	if low == "throw":
		return
	if low == "pressbutton" and weapon_ctrl.plant_progress > 0.0:
		return
	if weapon_ctrl.is_reloading and low in ["start_reload", "insert"]:
		return
	_play_idle_viewmodel()


func _play_idle_viewmodel() -> void:
	if not _vm_anim:
		return
	var wid := weapon_ctrl.current_weapon_id
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var is_sil := bool(weapon_ctrl.silenced_state.get(wid, false)) and bool(spec.get("silencer", false))
	if bool(spec.get("silencer", false)) and not is_sil:
		play_viewmodel_sequence(["idle_unsil", "idle", "idle1"])
	else:
		play_viewmodel_sequence(["idle", "idle1", "idle3"])


func _on_fired_shot(wid: String, silenced: bool) -> void:
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var rem_clip := int(weapon_ctrl.clips.get(wid, 1))
	var kick_scale := clampf(float(spec.get("recoil_up", 1.5)) / 3.5, 0.35, 1.35)
	_vm_kick_z = clampf(_vm_kick_z + 0.016 * kick_scale, 0.0, 0.038)
	_vm_kick_pitch = clampf(_vm_kick_pitch + deg_to_rad(1.8 * kick_scale), 0.0, deg_to_rad(4.8))

	if wid == "elite":
		_elite_muzzle_left = not _elite_muzzle_left
		if _elite_muzzle_left:
			var r_idx := randi_range(1, 5)
			if rem_clip <= 1:
				play_viewmodel_sequence(["shoot_leftlast", "shoot_left%d" % r_idx, "shoot_left1"])
			else:
				play_viewmodel_sequence(["shoot_left%d" % r_idx, "shoot_left1"])
		else:
			var l_idx := randi_range(1, 5)
			if rem_clip == 0:
				play_viewmodel_sequence(["shoot_rightlast", "shoot_right%d" % l_idx, "shoot_right1"])
			else:
				play_viewmodel_sequence(["shoot_right%d" % l_idx, "shoot_right1"])
	elif bool(spec.get("silencer", false)) and not silenced:
		var u_idx := randi_range(1, 3)
		if rem_clip == 0:
			play_viewmodel_sequence(["shootlast_unsil", "shoot%d_unsil" % u_idx, "shoot1_unsil", "shoot1"])
		else:
			play_viewmodel_sequence(["shoot%d_unsil" % u_idx, "shoot1_unsil", "shoot_unsil", "shoot1"])
	else:
		_elite_muzzle_left = false
		var s_idx := randi_range(1, 3)
		if rem_clip == 0:
			play_viewmodel_sequence(["shootlast", "shoot%d" % s_idx, "shoot1", "shoot", "shoot_2"])
		else:
			play_viewmodel_sequence(["shoot%d" % s_idx, "shoot1", "shoot", "shoot_2"])

	if wid != "knife" and not bool(spec.get("grenade", false)) and wid != "c4" and not silenced:
		_muzzle_sprite.visible = true
		_muzzle_light.visible = true
		_muzzle_timer = 0.045


func _on_zoom_changed(fov_deg: float, scoped_overlay: bool) -> void:
	camera.fov = fov_deg
	viewmodel_pivot.visible = not scoped_overlay
	if _vm_container:
		_vm_container.visible = not scoped_overlay
	scoped_overlay_changed.emit(scoped_overlay)


func _die(killer: Node3D, weapon_id: String, headshot: bool) -> void:
	viewmodel_pivot.visible = false
	if _vm_container:
		_vm_container.visible = false
	scoped_overlay_changed.emit(false)
	defuse_progress_changed.emit(0.0)
	camera.fov = GameData.fov
	super._die(killer, weapon_id, headshot)


func _cycle_spectator(step: int) -> void:
	var alive_list: Array = []
	for a in RoundManager.actors:
		if is_instance_valid(a) and a != self and bool(a.get("is_alive")):
			alive_list.append(a)
	if alive_list.is_empty():
		spectator_target_changed.emit("")
		return
	_spec_index = (_spec_index + step + alive_list.size() * 4) % alive_list.size()
	var tgt: CSActor = alive_list[_spec_index]
	spectator_target_changed.emit("%s (%s - %d HP)" % [tgt.actor_name, tgt.team, tgt.health])


func _update_spectator_camera(delta: float) -> void:
	var alive_list: Array = []
	for a in RoundManager.actors:
		if is_instance_valid(a) and a != self and bool(a.get("is_alive")):
			alive_list.append(a)
	if alive_list.is_empty():
		return
	_spec_index = clampi(_spec_index, 0, alive_list.size() - 1)
	var tgt: CSActor = alive_list[_spec_index]
	var behind := -tgt.get_look_forward() * 2.8 + Vector3(0.0, 2.0, 0.0)
	camera.top_level = true
	camera.global_position = camera.global_position.lerp(tgt.global_position + behind, minf(1.0, 8.0 * delta))
	camera.look_at(tgt.global_position + Vector3(0.0, 1.35, 0.0), Vector3.UP)
