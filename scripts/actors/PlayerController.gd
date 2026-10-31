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

var _vm_anim: AnimationPlayer = null
var _muzzle_sprite: Sprite3D = null
var _muzzle_light: OmniLight3D = null
var _muzzle_timer: float = 0.0
var _bob_phase: float = 0.0
var _sway_offset: Vector2 = Vector2.ZERO
var _defusing_c4: PlantedC4 = null
var _spec_index: int = 0
var ui_blocking_input: bool = false


func _ready() -> void:
	is_human = true
	actor_name = GameData.player_name
	super._ready()

	camera = Camera3D.new()
	camera.name = "FPSCamera"
	camera.fov = GameData.fov
	camera.near = 0.025
	camera.far = 950.0
	camera.position = Vector3(0.0, 1.85, 0.0)
	camera.current = true
	add_child(camera)

	# Scaled 0.22 around camera origin: identical perspective size, zero wall clipping inside 0.42m hull!
	viewmodel_pivot = Node3D.new()
	viewmodel_pivot.name = "ViewModelPivot"
	viewmodel_pivot.scale = Vector3(0.22, 0.22, 0.22)
	camera.add_child(viewmodel_pivot)

	viewmodel_holder = Node3D.new()
	viewmodel_holder.name = "ViewModelHolder"
	viewmodel_pivot.add_child(viewmodel_holder)

	_muzzle_sprite = Sprite3D.new()
	_muzzle_sprite.texture = GameData.get_texture("res://assets/sprites/muzzleflash1.png")
	_muzzle_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_sprite.pixel_size = 0.0032
	_muzzle_sprite.modulate = Color(1.0, 0.88, 0.55, 0.92)
	_muzzle_sprite.position = Vector3(0.22, -0.14, -0.82)
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
	camera.current = true
	camera.fov = GameData.fov
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
			sens *= (camera.fov / 90.0)
		var mm := event as InputEventMouseMotion
		look_yaw -= mm.relative.x * sens
		look_pitch = clampf(look_pitch - mm.relative.y * sens, deg_to_rad(-89.0), deg_to_rad(89.0))
		_sway_offset.x = clampf(_sway_offset.x - mm.relative.x * 0.0005, -0.04, 0.04)
		_sway_offset.y = clampf(_sway_offset.y + mm.relative.y * 0.0005, -0.04, 0.04)

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

	apply_goldsrc_movement(wish_dir, want_jump, want_crouch, want_walk, delta)

	# Smooth camera eye height & recoil punch angles
	var target_eye_y := 1.08 if is_crouching else 1.85
	camera.position.y = lerpf(camera.position.y, target_eye_y, minf(1.0, 14.0 * delta))
	var punch := weapon_ctrl.punch_angles
	camera.rotation = Vector3(
		look_pitch + deg_to_rad(punch.x * 1.15),
		look_yaw + deg_to_rad(punch.y * 0.85),
		0.0
	)

	# Viewmodel bobbing & mouse sway (classic GoldSrc cl_bob)
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, minf(1.0, 10.0 * delta))
	var hspd := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspd > 0.4:
		_bob_phase += delta * hspd * 1.65
	var bob_x := sin(_bob_phase) * 0.012 * clampf(hspd / 7.0, 0.0, 1.0)
	var bob_y := absf(cos(_bob_phase)) * -0.014 * clampf(hspd / 7.0, 0.0, 1.0)
	# Mirror X when right-handed (Gooseman's original CS 1.5 .mdl viewmodels were modeled left-handed!)
	var hand_sign := -1.0 if GameData.right_hand else 1.0
	viewmodel_holder.scale.x = hand_sign
	viewmodel_holder.position = Vector3(bob_x + _sway_offset.x, bob_y + _sway_offset.y, 0.0)
	_muzzle_sprite.position.x = -0.22 * hand_sign

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


func _rebuild_viewmodel(wid: String) -> void:
	for c in viewmodel_holder.get_children():
		c.queue_free()
	_vm_anim = null
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var v_name := String(spec.get("v_model", "v_knife"))
	var sc := GameData.get_model_scene("weapons/" + v_name)
	if not sc:
		return
	var inst := sc.instantiate()
	# Disable backface culling when mirrored for cl_righthand 1!
	_prepare_viewmodel_materials(inst)
	viewmodel_holder.add_child(inst)
	_vm_anim = _find_anim(inst)
	var is_sil := bool(weapon_ctrl.silenced_state.get(wid, false)) and bool(spec.get("silencer", false))
	if bool(spec.get("silencer", false)) and not is_sil:
		play_viewmodel_anim("draw_unsil")
	else:
		play_viewmodel_anim("draw")


func _prepare_viewmodel_materials(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.mesh.surface_get_material(s)
				if mat is BaseMaterial3D:
					var dup := mat.duplicate() as BaseMaterial3D
					dup.cull_mode = BaseMaterial3D.CULL_DISABLED
					mi.set_surface_override_material(s, dup)
	for c in n.get_children():
		_prepare_viewmodel_materials(c)


func play_viewmodel_anim(preferred: String) -> void:
	if not _vm_anim:
		return
	var anims := _vm_anim.get_animation_list()
	if anims.has(preferred):
		_vm_anim.stop()
		_vm_anim.play(preferred)
		return
	for a in anims:
		if preferred in a.to_lower():
			_vm_anim.stop()
			_vm_anim.play(a)
			return


func _on_fired_shot(wid: String, silenced: bool) -> void:
	var spec: Dictionary = GameData.weapons.get(wid, {})
	if bool(spec.get("silencer", false)) and not silenced:
		play_viewmodel_anim("shoot1_unsil")
	else:
		play_viewmodel_anim("shoot1")

	if wid != "knife" and not bool(spec.get("grenade", false)) and wid != "c4" and not silenced:
		_muzzle_sprite.visible = true
		_muzzle_light.visible = true
		_muzzle_timer = 0.045


func _on_zoom_changed(fov_deg: float, scoped_overlay: bool) -> void:
	camera.fov = fov_deg
	viewmodel_pivot.visible = not scoped_overlay
	scoped_overlay_changed.emit(scoped_overlay)


func _die(killer: Node3D, weapon_id: String, headshot: bool) -> void:
	viewmodel_pivot.visible = false
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
