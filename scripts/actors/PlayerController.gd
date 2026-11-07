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
## Current chase-cam spectator actor (null while dead in deathcam / alive / no target).
var spectator_target: CSActor = null

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
var _vm_muzzle_light: OmniLight3D = null
var _muzzle_timer: float = 0.0
## Barrel tip in viewmodel space — baked per weapon in models_meta.json from
## the REAL idle pose (bind-pose estimates sit far away: the idle animation
## moves the gun, so measuring raw mesh vertices put the flash in the wrong
## side of the screen)
var _vm_muzzle_offset: Vector3 = Vector3(0.18, -0.11, -0.68)
## Ejection port in viewmodel space (baked per weapon) — world shells spawn here
var _vm_eject_offset: Vector3 = Vector3(0.18, -0.14, -0.23)
## Secondary muzzle for dual elites (the left gun), baked as muzzle_alt
var _vm_muzzle_alt: Vector3 = Vector3.ZERO
var _vm_has_muzzle_alt: bool = false
var _bob_phase: float = 0.0
var _sway_offset: Vector2 = Vector2.ZERO
var _vm_kick_z: float = 0.0
var _vm_kick_pitch: float = 0.0
var _vm_kick_roll: float = 0.0
var _vm_vert_lag: float = 0.0
var _vm_draw_offset: float = 0.0
var _dmg_punch: Vector3 = Vector3.ZERO
var _land_dip: float = 0.0
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0
var _was_on_floor: bool = true
var _cur_vm_model_name: String = ""
var _vm_model_root: Node3D = null
var _vm_model_rest_transform: Transform3D = Transform3D.IDENTITY
## wid the current viewmodel instance was built for (lets same-weapon refresh
## events, like silencer toggle completion, skip the rebuild + draw replay)
var _vm_built_for: String = ""
var _vm_silencer_skeleton: Skeleton3D = null
var _vm_silencer_bone: int = -1
var _vm_silencer_visible: bool = true
var _native_cz_spare_removed := false
var _pending_vm_events: Array = []
var _vm_anim_elapsed: float = 0.0
## Last authentic inspection variant per weapon. The first press keeps the
## original clip; subsequent presses rotate through inspect_2 / inspect_3.
var _inspect_variant_indices: Dictionary = {}
var _shake_trauma: float = 0.0
var _shake_time: float = 0.0
var _eye_height_cur: float = 1.66
var _last_in_x: float = 0.0
var _spec_free_orbit_timer: float = 0.0
var _deathcam_timer: float = 0.0
var _deathcam_killer: Node3D = null
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
	_vm_viewport.msaa_3d = Viewport.MSAA_4X
	# Keep the first-person presentation in the same controlled studio world as
	# the Arsenal preview. Map lighting remains on the world/character layers;
	# only this isolated layer receives the viewmodel rig below.
	_vm_viewport.own_world_3d = true
	_vm_container.add_child(_vm_viewport)

	var vm_environment := Environment.new()
	vm_environment.background_mode = Environment.BG_CLEAR_COLOR
	vm_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	vm_environment.ambient_light_color = Color(0.92, 0.90, 0.86)
	vm_environment.ambient_light_energy = 1.45
	vm_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# Chrome needs reflected shapes, not just brighter direct-light highlights.
	# This studio panorama supplies white softboxes and dark contrast bands to
	# the isolated viewmodel world. The viewport background remains transparent.
	var chrome_sky := Sky.new()
	chrome_sky.resource_name = "ViewModelChromeSky"
	chrome_sky.radiance_size = Sky.RADIANCE_SIZE_256
	var chrome_panorama := PanoramaSkyMaterial.new()
	chrome_panorama.resource_name = "ViewModelChromeStudio"
	chrome_panorama.panorama = _create_chrome_studio_panorama()
	chrome_panorama.energy_multiplier = 0.68
	chrome_sky.sky_material = chrome_panorama
	vm_environment.sky = chrome_sky
	vm_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var vm_world_environment := WorldEnvironment.new()
	vm_world_environment.name = "ViewModelStudioEnvironment"
	vm_world_environment.environment = vm_environment
	_vm_viewport.add_child(vm_world_environment)

	var vm_key := DirectionalLight3D.new()
	vm_key.name = "ViewModelStudioKey"
	vm_key.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	vm_key.light_energy = 1.8
	vm_key.light_cull_mask = 4
	vm_key.shadow_enabled = false
	_vm_viewport.add_child(vm_key)

	var vm_fill := DirectionalLight3D.new()
	vm_fill.name = "ViewModelStudioFill"
	vm_fill.rotation_degrees = Vector3(32.0, -142.0, 0.0)
	vm_fill.light_color = Color(0.80, 0.86, 0.95)
	vm_fill.light_energy = 0.65
	vm_fill.light_cull_mask = 4
	vm_fill.shadow_enabled = false
	_vm_viewport.add_child(vm_fill)

	_vm_camera = Camera3D.new()
	_vm_camera.name = "ViewModelCamera"
	_vm_camera.rotation_order = EULER_ORDER_YXZ
	_vm_camera.fov = 65.0
	_vm_camera.near = 0.015
	_vm_camera.far = 6.0
	_vm_camera.cull_mask = 4  # Visual Layer 3 ONLY (first-person weapon + muzzle flash)
	_vm_camera.current = true
	_vm_viewport.add_child(_vm_camera)

	var vm_softbox := OmniLight3D.new()
	vm_softbox.name = "ViewModelStudioSoftbox"
	vm_softbox.position = Vector3(-0.25, 0.35, 0.15)
	vm_softbox.light_energy = 2.5
	vm_softbox.light_specular = 0.45
	vm_softbox.omni_range = 2.5
	vm_softbox.light_cull_mask = 4
	vm_softbox.shadow_enabled = false
	_vm_camera.add_child(vm_softbox)

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
	_muzzle_sprite.shaded = false
	_muzzle_sprite.pixel_size = 0.0028
	_muzzle_sprite.modulate = Color(1.0, 0.90, 0.56, 0.95)
	_muzzle_sprite.position = Vector3(0.18, -0.11, -0.68)
	_muzzle_sprite.visible = false
	viewmodel_pivot.add_child(_muzzle_sprite)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.82, 0.45)
	_muzzle_light.light_energy = 2.8
	_muzzle_light.omni_range = 7.5
	_muzzle_light.visible = false
	camera.add_child(_muzzle_light)

	# The world-space flash still lights the map. This companion light preserves
	# the same pulse inside the isolated first-person studio world.
	_vm_muzzle_light = OmniLight3D.new()
	_vm_muzzle_light.name = "ViewModelMuzzleLight"
	_vm_muzzle_light.light_color = _muzzle_light.light_color
	_vm_muzzle_light.light_energy = _muzzle_light.light_energy
	_vm_muzzle_light.omni_range = _muzzle_light.omni_range
	_vm_muzzle_light.light_cull_mask = 4
	_vm_muzzle_light.shadow_enabled = false
	_vm_muzzle_light.visible = false
	_vm_camera.add_child(_vm_muzzle_light)

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
	damaged_from.connect(_on_player_damaged_from)


func _create_chrome_studio_panorama() -> ImageTexture:
	# A small equi rectangular lighting studio: broad neutral ambience, four
	# vertical softboxes and a darker floor. It is generated once per player,
	# needs no HDR download, and Godot filters its radiance for rough surfaces.
	var width := 512
	var height := 256
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	var panels := [
		Vector3(0.10, 0.040, 0.96),
		Vector3(0.36, 0.075, 1.00),
		Vector3(0.64, 0.050, 0.92),
		Vector3(0.88, 0.030, 0.82),
	]
	for y in range(height):
		var v := (float(y) + 0.5) / float(height)
		var horizon := 1.0 - absf(v - 0.5) * 2.0
		var base := Color(0.025, 0.032, 0.045).lerp(Color(0.30, 0.33, 0.38), horizon)
		if v > 0.52:
			base = base.lerp(Color(0.018, 0.022, 0.030), smoothstep(0.52, 0.94, v))
		var vertical_mask := smoothstep(0.08, 0.17, v) * (1.0 - smoothstep(0.72, 0.84, v))
		for x in range(width):
			var u := (float(x) + 0.5) / float(width)
			var color := base
			for panel in panels:
				var distance_u := absf(u - panel.x)
				distance_u = minf(distance_u, 1.0 - distance_u)
				var horizontal_mask := 1.0 - smoothstep(panel.y, panel.y + 0.025, distance_u)
				var reflection := horizontal_mask * vertical_mask * float(panel.z)
				color = color.lerp(Color(0.94, 0.97, 1.0), reflection)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


func spawn_for_round(pos: Vector3, yaw_rad: float, reset_weapons: bool) -> void:
	super.spawn_for_round(pos, yaw_rad, reset_weapons)
	if reset_weapons:
		_native_cz_spare_removed = false
	camera.top_level = false
	_eye_height_cur = 1.66
	_vm_kick_z = 0.0
	_vm_kick_pitch = 0.0
	_vm_kick_roll = 0.0
	_vm_vert_lag = 0.0
	_vm_draw_offset = 0.0
	_dmg_punch = Vector3.ZERO
	_jump_buffer_timer = 0.0
	_coyote_timer = 0.0
	_deathcam_timer = 0.0
	_deathcam_killer = null
	camera.position = Vector3(0.0, 1.66, 0.0)
	camera.rotation = Vector3(0.0, look_yaw, 0.0)
	camera.current = true
	camera.fov = GameData.fov
	if _vm_container:
		_vm_container.visible = true
	viewmodel_pivot.visible = true
	flashlight_spot.visible = false
	nvg_light.visible = nvg_active
	nvg_toggled.emit(nvg_active)
	spectator_target = null
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
		if not is_alive:
			_spec_free_orbit_timer = 2.5
		_sway_offset.x = clampf(_sway_offset.x - mm.relative.x * 0.00017, -0.014, 0.014)
		_sway_offset.y = clampf(_sway_offset.y + mm.relative.y * 0.00017, -0.014, 0.014)

	if not is_alive:
		if _deathcam_timer > 0.0:
			# Guard first 0.95s so combat clicks at the moment of death never accidentally skip your death animation!
			if _deathcam_timer < 1.90 and (event.is_action_pressed("attack1") or event.is_action_pressed("jump") or event.is_action_pressed("attack2")):
				_finish_deathcam_to_spectator()
			return
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
	elif event.is_action_pressed("inspect"):
		_try_inspect_viewmodel()


func _cycle_weapon_slot(step: int) -> void:
	var order := [1, 2, 3, 4, 5]
	var cur_slot := int(weapon_ctrl.get_current_spec().get("slot", 3))
	var idx := order.find(cur_slot)
	for k in range(1, order.size() + 1):
		var next_s: int = order[(idx + step * k + order.size() * 4) % order.size()]
		if weapon_ctrl.equip_slot(next_s):
			return


func _process(delta: float) -> void:
	super._process(delta)

	if _muzzle_timer > 0.0:
		_muzzle_timer -= delta
		if _muzzle_timer <= 0.0:
			_muzzle_sprite.visible = false
			_muzzle_light.visible = false
			_vm_muzzle_light.visible = false

	# Tick frame-exact StudioMDL 5004 weapon foley sound events synced to viewmodel animation!
	if is_alive and not _pending_vm_events.is_empty() and _vm_anim and _vm_anim.is_playing():
		_vm_anim_elapsed += delta
		while not _pending_vm_events.is_empty():
			var ev: Dictionary = _pending_vm_events[0]
			if float(ev.get("t", 0.0)) <= _vm_anim_elapsed + 0.004:
				var wav := GameData.sound_variant(ev)
				if not wav.is_empty():
					AudioManager.play_viewmodel_audio(self, wav, randf_range(0.985, 1.015))
				_pending_vm_events.remove_at(0)
			else:
				break

	if not is_alive:
		_update_spectator_camera(delta)
		return
	if is_instance_valid(_vm_model_root):
		# Animation tracks drive bones, never the model root. Restore the local
		# calibration every frame so interrupted clips cannot accumulate offsets.
		_vm_model_root.transform = _vm_model_rest_transform
		_apply_vm_silencer_visibility()
		_apply_native_prop_visibility()

	# Full display-refresh-rate camera + sub-tick physics & stair interpolation!
	_land_dip = lerpf(_land_dip, 0.0, minf(1.0, 12.0 * delta))
	var target_eye_y := (0.96 if is_crouching else 1.66) - _land_dip * 1.4
	_eye_height_cur = lerpf(_eye_height_cur, target_eye_y, minf(1.0, 16.0 * delta))
	var sub_ofs: Vector3 = get_visual_world_pos() - global_position
	camera.position = sub_ofs + Vector3(0.0, _eye_height_cur, 0.0)

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
	_dmg_punch = _dmg_punch.lerp(Vector3.ZERO, minf(1.0, 13.0 * delta))
	camera.rotation = Vector3(
		look_pitch + deg_to_rad(punch.x) + shake_rot.x + _dmg_punch.x,
		look_yaw + deg_to_rad(punch.y) + shake_rot.y + _dmg_punch.y,
		shake_rot.z + _dmg_punch.z
	)
	if _vm_camera:
		_vm_camera.global_transform = camera.global_transform

	# Viewmodel bobbing, mouse sway, airborne inertia, crouch cant, draw spring & recoil kickback at full render FPS
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, minf(1.0, 9.0 * delta))
	_vm_kick_z = lerpf(_vm_kick_z, 0.0, minf(1.0, 18.0 * delta))
	_vm_kick_pitch = lerpf(_vm_kick_pitch, 0.0, minf(1.0, 16.0 * delta))
	_vm_kick_roll = lerpf(_vm_kick_roll, 0.0, minf(1.0, 15.0 * delta))
	_vm_draw_offset = lerpf(_vm_draw_offset, 0.0, minf(1.0, 18.0 * delta))
	var target_v_lag := clampf(-velocity.y * 0.0022, -0.016, 0.020)
	_vm_vert_lag = lerpf(_vm_vert_lag, target_v_lag, minf(1.0, 12.0 * delta))

	var hspd := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and hspd > 0.4:
		_bob_phase += delta * hspd * 1.42
	else:
		_bob_phase += delta * 1.35
	var move_fac := clampf(hspd / 7.0, 0.0, 1.0)
	var bob_x := sin(_bob_phase) * (0.0060 * move_fac + 0.0007)
	var bob_y := absf(cos(_bob_phase)) * (-0.0072 * move_fac) + sin(_bob_phase * 0.5) * 0.0008 - _land_dip * 0.68 + _vm_vert_lag
	var crouch_ofs := Vector3(-0.005, -0.007, 0.005) * _visual_crouch_t
	var strafe_roll := -_last_in_x * deg_to_rad(0.85) * move_fac - _sway_offset.x * 0.85 + deg_to_rad(1.2) * _visual_crouch_t + _vm_kick_roll
	var native_vm := bool((GameData.models_meta.get("weapons/" + _cur_vm_model_name, {}) as Dictionary).get("native_cs2_animation", false))
	var draw_dip := 0.0 if native_vm else _vm_draw_offset
	viewmodel_holder.scale = Vector3.ONE
	viewmodel_holder.position = Vector3(
		bob_x + _sway_offset.x + crouch_ofs.x,
		bob_y + _sway_offset.y + crouch_ofs.y - draw_dip * 0.065,
		_vm_kick_z + crouch_ofs.z + draw_dip * 0.025
	)
	viewmodel_holder.rotation = Vector3(
		_vm_kick_pitch - draw_dip * 0.22 + _sway_offset.y * 0.6,
		-_sway_offset.x * 1.05,
		strafe_roll
	)
	if _vm_container:
		_vm_container.pivot_offset = _vm_container.size * 0.5
		# cl_righthand=1 must RENDER right-handed: the CS:GO-mod models are
		# authored/animate left-handed (idle muzzle at x<0), so the mirrored
		# scale is what places the weapon on the right side of the screen.
		var native_right := bool((GameData.models_meta.get("weapons/" + _cur_vm_model_name, {}) as Dictionary).get("authored_right_hand", false))
		var mirror := (not GameData.right_hand) if native_right else GameData.right_hand
		_vm_container.scale = Vector2(-1.0 if mirror else 1.0, 1.0)
	_muzzle_sprite.position = _current_vm_muzzle()


func _physics_process(delta: float) -> void:
	if not is_alive:
		return

	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	if is_on_floor():
		_coyote_timer = 0.085
	elif _coyote_timer > 0.0:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	var in_vec := Vector2.ZERO
	if not ui_blocking_input:
		in_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_last_in_x = lerpf(_last_in_x, in_vec.x, minf(1.0, 14.0 * delta))

	var yaw_basis := Basis(Vector3.UP, look_yaw)
	var wish_dir := (yaw_basis * Vector3(in_vec.x, 0.0, in_vec.y))
	if wish_dir.length_squared() > 0.001:
		wish_dir = wish_dir.normalized()

	if (not ui_blocking_input) and Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = 0.11
	var want_jump := _jump_buffer_timer > 0.0 and (is_on_floor() or on_ladder)
	var want_crouch := (not ui_blocking_input) and Input.is_action_pressed("crouch")
	var want_walk := (not ui_blocking_input) and Input.is_action_pressed("walk")

	# Ledge step-off coyote jump forgiveness (85ms grace after walking off a crate/ramp lip)
	if _jump_buffer_timer > 0.0 and not is_on_floor() and not on_ladder and _coyote_timer > 0.0 and not RoundManager.is_movement_frozen():
		velocity.y = JUMP_VEL_MPS * stamina_factor
		stamina_factor = maxf(0.68, stamina_factor - 0.22)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
	elif want_jump:
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0

	var prev_vy := velocity.y
	apply_goldsrc_movement(wish_dir, want_jump, want_crouch, want_walk, delta)
	if is_on_floor() and not _was_on_floor and prev_vy < -3.0:
		_land_dip = clampf(-prev_vy * 0.0044, 0.009, 0.042)
	_was_on_floor = is_on_floor()

	# Primary & secondary attack (just pressed, held, or released)
	if not ui_blocking_input:
		if Input.is_action_just_pressed("attack1"):
			weapon_ctrl.trigger_primary(false, delta)
		elif Input.is_action_pressed("attack1"):
			weapon_ctrl.trigger_primary(true, delta)
		elif Input.is_action_just_released("attack1"):
			weapon_ctrl.release_primary()
		if Input.is_action_just_released("attack2"):
			weapon_ctrl.release_secondary()

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
			elif col is Node and col.has_meta("button_target"):
				var btn_tgt := String(col.get_meta("button_target"))
				var btn_pos: Vector3 = col.get_meta("button_center") if col.has_meta("button_center") else hit["position"]
				AudioManager.play_3d("buttons/blip1.wav", btn_pos, -3.5, 18.0, 1.0, 12.0, team)
				if RoundManager.game_world != null:
					RoundManager.game_world.trigger_map_target(btn_tgt, self)

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
	# The silencer toggle completion also emits weapon_switched (HUD refresh).
	# Same weapon, same viewmodel model: keep the add/detach silencer clip that
	# just played instead of rebuilding the viewmodel and restarting with DRAW.
	if wid == _vm_built_for and viewmodel_holder != null and viewmodel_holder.get_child_count() > 0:
		var spec: Dictionary = GameData.weapons.get(wid, {})
		_vm_silencer_visible = bool(weapon_ctrl.silenced_state.get(wid, false)) and bool(spec.get("silencer", false))
		_apply_vm_muzzle_meta(_cur_vm_model_name, _vm_silencer_visible, _vm_model_root)
		_apply_vm_silencer_visibility()
		return
	_vm_draw_offset = 1.0
	_rebuild_viewmodel(wid)


func _on_player_damaged_from(source_pos: Vector3, dmg_amount: int, directional: bool) -> void:
	var mag: float = clampf(float(dmg_amount) / 34.0, 0.25, 1.45)
	if directional:
		var rel: Vector3 = source_pos - global_position
		rel.y = 0.0
		if rel.length_squared() > 0.001:
			rel = rel.normalized()
			var yb := Basis(Vector3.UP, look_yaw)
			var f_dot: float = (-yb.z).dot(rel)
			var r_dot: float = yb.x.dot(rel)
			_dmg_punch.x = clampf(_dmg_punch.x + (-f_dot * 0.042 + 0.018) * mag, -0.09, 0.09)
			_dmg_punch.z = clampf(_dmg_punch.z - r_dot * 0.048 * mag, -0.09, 0.09)
			return
	_dmg_punch.x = clampf(_dmg_punch.x + 0.035 * mag, -0.09, 0.09)


func apply_camera_shake(intensity: float) -> void:
	_shake_trauma = clampf(_shake_trauma + intensity, 0.0, 1.35)


func _rebuild_viewmodel(wid: String) -> void:
	_vm_model_root = null
	_vm_model_rest_transform = Transform3D.IDENTITY
	var old_children := viewmodel_holder.get_children()
	for c in old_children:
		viewmodel_holder.remove_child(c)
		c.queue_free()
	_vm_anim = null
	_vm_silencer_skeleton = null
	_vm_silencer_bone = -1
	_pending_vm_events.clear()
	AudioManager.stop_viewmodel_audio(self)
	_vm_anim_elapsed = 0.0
	_elite_muzzle_left = false
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var v_name := String(spec.get("v_model", "v_knife"))
	_cur_vm_model_name = v_name
	_vm_built_for = wid
	var sc := GameData.get_model_scene("weapons/" + v_name)
	if not sc:
		return
	var inst := sc.instantiate()
	# Native GoldSrc camera-space framing (verified across rifles, pistols, knife, grenades & C4)
	var native_knife := bool((GameData.models_meta.get("weapons/" + v_name, {}) as Dictionary).get("native_cs2_animation", false))
	# Native rigs already use eye-relative Source coordinates. Do not add the
	# old Kukri placement or mirror their right-hand choreography a second time.
	inst.position = Vector3(0.0635, -0.0381, 0.0) if native_knife else Vector3(0.0, -0.015, -0.03)
	_vm_camera.fov = 53.668 if native_knife else 65.0
	var mirror := (not GameData.right_hand) if native_knife else GameData.right_hand
	_vm_container.scale = Vector2(-1.0 if mirror else 1.0, 1.0)
	viewmodel_holder.add_child(inst)
	SportGloves.apply(inst, v_name)
	_prepare_viewmodel_materials(inst, native_knife)
	_vm_model_root = inst as Node3D
	if _vm_model_root != null:
		_vm_model_rest_transform = _vm_model_root.transform
	var is_sil := bool(weapon_ctrl.silenced_state.get(wid, false)) and bool(spec.get("silencer", false))
	_configure_vm_silencer(inst, wid, is_sil)
	_apply_vm_muzzle_meta(v_name, is_sil, inst)
	_vm_anim = _find_anim(inst)
	if _vm_anim:
		# Run animation before this controller restores the calibrated root.
		_vm_anim.process_priority = -100
		for aname in _vm_anim.get_animation_list():
			var low := aname.to_lower()
			var anim_res := _vm_anim.get_animation(aname)
			if anim_res:
				anim_res.loop_mode = Animation.LOOP_LINEAR if low.begins_with("idle") or low in ["hold_high", "hold_low"] else Animation.LOOP_NONE
		if not _vm_anim.animation_finished.is_connected(_on_vm_anim_finished):
			_vm_anim.animation_finished.connect(_on_vm_anim_finished)

	if bool(spec.get("grenade", false)):
		play_viewmodel_sequence(["deploy", "draw", "idle"])
	elif bool(spec.get("silencer", false)) and not is_sil:
		play_viewmodel_sequence(["draw_unsil", "draw", "idle_unsil"])
	else:
		play_viewmodel_sequence(["draw", "deploy", "idle", "idle1", "idle3"])


## Baked idle-pose muzzle/eject data from models_meta.json. Falls back to the
## bind-pose estimate when a model has no baked entry.
func _apply_vm_muzzle_meta(v_name: String, is_sil: bool, inst: Node) -> void:
	var mmeta: Dictionary = GameData.models_meta.get("weapons/" + v_name, {})
	_vm_has_muzzle_alt = false
	_vm_muzzle_alt = Vector3.ZERO
	var mz: Variant = mmeta.get("muzzle")
	if not is_sil and mmeta.has("muzzle_unsil"):
		mz = mmeta.get("muzzle_unsil")
	if mz is Array and (mz as Array).size() >= 3:
		_vm_muzzle_offset = Vector3(float(mz[0]), float(mz[1]), float(mz[2]))
	else:
		_vm_muzzle_offset = _compute_vm_muzzle_offset(inst)
	var alt: Variant = mmeta.get("muzzle_alt")
	if alt is Array and (alt as Array).size() >= 3:
		_vm_muzzle_alt = Vector3(float(alt[0]), float(alt[1]), float(alt[2]))
		_vm_has_muzzle_alt = true
	var ej: Variant = mmeta.get("eject")
	if ej is Array and (ej as Array).size() >= 3:
		_vm_eject_offset = Vector3(float(ej[0]), float(ej[1]), float(ej[2]))
	else:
		_vm_eject_offset = _vm_muzzle_offset + Vector3(0.0, -0.03, 0.45)
	_muzzle_sprite.position = _current_vm_muzzle()


## Active muzzle point (dual elites alternate between both guns).
func _current_vm_muzzle() -> Vector3:
	if _vm_has_muzzle_alt and _elite_muzzle_left:
		return _vm_muzzle_alt
	return _vm_muzzle_offset


## World-space position of a viewmodel-local point. With cl_righthand=1 the
## Legacy rigs mirror for right-hand view; native rigs mirror for left-hand
## view. World-space shells, tracers and lights must follow the same parity.
func _is_viewmodel_mirrored() -> bool:
	var mmeta: Dictionary = GameData.models_meta.get("weapons/" + _cur_vm_model_name, {})
	return not GameData.right_hand if bool(mmeta.get("authored_right_hand", false)) else GameData.right_hand


func get_vm_world_point(local_p: Vector3) -> Vector3:
	var p := local_p
	if _is_viewmodel_mirrored():
		p.x = -p.x
	if _vm_camera != null:
		return _vm_camera.global_transform * p
	return camera.global_transform * p


func native_casing_clip() -> String:
	return String(_vm_anim.current_animation) if _vm_anim != null else "shoot1"


func native_casing_frame(cue: Dictionary) -> Transform3D:
	if is_instance_valid(_vm_model_root):
		var skeletons := _vm_model_root.find_children("*", "Skeleton3D", true, false)
		for sk in skeletons:
			var bone: int = sk.find_bone(String(cue["bone"]))
			if bone >= 0:
				return sk.global_transform * sk.get_bone_global_pose(bone) * NativeCasings.frame_from_rows(cue["frame"])
	return Transform3D(camera.global_basis.scaled(Vector3.ONE * 0.0254), get_vm_eject_world())


func get_vm_eject_world() -> Vector3:
	return get_vm_world_point(_vm_eject_offset)


func get_vm_muzzle_world() -> Vector3:
	return get_vm_world_point(_current_vm_muzzle())


## Collects every vertex of the loaded viewmodel (bind pose, pivot space).
func _collect_vm_vertices(n: Node, base: Transform3D, out: PackedVector3Array) -> void:
	var t: Transform3D = base
	if n is Node3D:
		t = base * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var arrs := mi.mesh.surface_get_arrays(s)
				if arrs.size() > Mesh.ARRAY_VERTEX:
					var vs: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
					for v in vs:
						out.append(t * v)
	for c in n.get_children():
		_collect_vm_vertices(c, t, out)


## Barrel tip of the CURRENT viewmodel: robust front-cluster estimate that
## ignores stray bind-pose geometry (CS:GO-mod models contain junk vertices).
func _compute_vm_muzzle_offset(root: Node) -> Vector3:
	var pts := PackedVector3Array()
	_collect_vm_vertices(root, Transform3D(), pts)
	if pts.size() < 64:
		return Vector3(0.18, -0.11, -0.68)
	var fpts := PackedVector3Array()
	for p in pts:
		if p.y < 1.0 and absf(p.z) < 1.6:
			fpts.append(p)
	if fpts.size() < 64:
		fpts = pts
	var min_y := 1e9
	var max_y := -1e9
	var min_z := 1e9
	for p in fpts:
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
		min_z = minf(min_z, p.z)
	var h: float = maxf(0.05, max_y - min_y)
	var band_lo: float = min_y + 0.45 * h
	var band_hi: float = min_y + 0.90 * h
	var front_z := 1e9
	for p in fpts:
		if p.y >= band_lo and p.y <= band_hi:
			front_z = minf(front_z, p.z)
	if front_z > 1e8:
		front_z = min_z
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	for p in fpts:
		if p.y >= band_lo and p.y <= band_hi and p.z <= front_z + 0.14:
			xs.append(p.x)
			ys.append(p.y)
	if xs.is_empty():
		return Vector3(0.18, -0.11, -0.68)
	xs.sort()
	ys.sort()
	var mx: float = xs[xs.size() / 2]
	var my: float = ys[ys.size() / 2]
	return Vector3(mx, my, front_z + 0.05)


func _configure_vm_silencer(inst: Node, wid: String, visible: bool) -> void:
	_vm_silencer_visible = visible
	var bone_name := String({
		"m4a1": "v_weapon.M4A1_Silencer",
		"usp": "v_weapon_silencer",
	}.get(wid, ""))
	if bone_name.is_empty():
		return
	var skeletons := inst.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_vm_silencer_skeleton = skeletons[0] as Skeleton3D
	_vm_silencer_bone = _vm_silencer_skeleton.find_bone(bone_name)
	_apply_vm_silencer_visibility()


func _apply_vm_silencer_visibility() -> void:
	if not is_instance_valid(_vm_silencer_skeleton) or _vm_silencer_bone < 0:
		return
	# Add/detach clips already move the suppressor between the hand and barrel.
	# Keep it visible for the whole transition instead of collapsing its bone
	# until the state flips at the end. Idle/draw still follow the actual state.
	var transitioning := weapon_ctrl != null and weapon_ctrl.is_attaching_silencer
	var target_scale := Vector3.ONE if _vm_silencer_visible or transitioning else Vector3.ONE * 0.0001
	_vm_silencer_skeleton.set_bone_pose_scale(_vm_silencer_bone, target_scale)


func _apply_native_prop_visibility() -> void:
	if _vm_built_for != "cz75" or _vm_anim == null:
		return
	var meta: Dictionary = GameData.models_meta.get("weapons/" + _cur_vm_model_name, {})
	var markers: Dictionary = meta.get("cz_spare_detach_times", {})
	var marker: Variant = markers.get(String(_vm_anim.current_animation))
	if marker != null and _vm_anim.current_animation_position >= float(marker):
		_native_cz_spare_removed = true
	if _native_cz_spare_removed:
		var skeletons := _vm_model_root.find_children("*", "Skeleton3D", true, false)
		if not skeletons.is_empty():
			var skeleton := skeletons[0] as Skeleton3D
			var bone := skeleton.find_bone("v_weapon_cz_magazine2")
			if bone >= 0:
				skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.0001)


func _prepare_viewmodel_materials(n: Node, native_arms: bool = false) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.layers = 4  # Visual Layer 3: rendered exclusively by _vm_camera!
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(s)
				var name_lower := mat.resource_name.to_lower() if mat != null else ""
				var arm_surface := name_lower.contains("glove") or name_lower == "ct_arms.bmp"
				# Native knives reflect only their original arms; native guns
				# retain the original reflected geometry for every surface.
				var native_gun := bool((GameData.models_meta.get("weapons/" + _cur_vm_model_name, {}) as Dictionary).get("native_gun_animations", false))
				var material_mode := "vm_flip" if native_gun or (native_arms and arm_surface) else "vm"
				var styled := GameData.get_styled_model_material(mat, material_mode)
				if styled:
					mi.set_surface_override_material(s, styled)
	for c in n.get_children():
		_prepare_viewmodel_materials(c, native_arms)


func _start_vm_clip(anim_name: String) -> void:
	if _vm_built_for == "cz75" and _native_cz_spare_removed:
		var followup := ""
		if anim_name in ["reload", "reload_unsil"]:
			followup = "reloadFollowup"
		elif anim_name == "reload_empty":
			followup = "reloadFollowupEmpty"
		elif anim_name == "draw":
			followup = "draw_2"
		if not followup.is_empty() and _vm_anim.has_animation(followup):
			anim_name = followup
	if not anim_name.begins_with("shoot") and not anim_name.begins_with("idle") and anim_name != "fire":
		weapon_ctrl.casing_epoch += 1
	_vm_anim.stop()
	_vm_anim.speed_scale = 1.0
	_vm_anim.play(anim_name)
	_vm_anim.advance(0.0)
	_pending_vm_events.clear()
	# Natural idle/hold transitions let the last one-shot decay; new actions cancel it.
	if not anim_name.to_lower().begins_with("idle") and anim_name not in ["hold_high", "hold_low"]:
		AudioManager.stop_viewmodel_audio(self)
	_vm_anim_elapsed = 0.0
	if not _cur_vm_model_name.is_empty():
		var mmeta: Dictionary = GameData.models_meta.get("weapons/" + _cur_vm_model_name, {})
		var event_time_scale := 1.0
		if bool(mmeta.get("native_gun_animations", false)):
			var action_names := ["reload", "reload_unsil", "reload_empty", "start_reload", "insert", "after_reload", "add_silencer", "detach_silencer", "pullpin", "pressbutton", "prepare", "reloadFollowup", "reloadFollowupEmpty"]
			if anim_name in action_names:
				var gameplay: Dictionary = mmeta.get("gameplay_seq_durations", {})
				var timing_name := "reload_empty" if anim_name == "reloadFollowupEmpty" else "reload" if anim_name == "reloadFollowup" else anim_name
				var duration := float(gameplay.get(timing_name, _vm_anim.get_animation(anim_name).length))
				if anim_name == "pressbutton":
					duration = 3.0
				elif anim_name == "pullpin":
					duration = 0.32 if weapon_ctrl._grenade_lob_mode else 0.36
				elif anim_name == "prepare":
					duration = float(weapon_ctrl.get_current_spec().get("primary_delay", 0.20))
				event_time_scale = duration / maxf(_vm_anim.get_animation(anim_name).length, 0.001)
				_vm_anim.speed_scale = 1.0 / maxf(event_time_scale, 0.001)
		var ev_map: Dictionary = mmeta.get("seq_events", {})
		if ev_map.has(anim_name):
			var raw_evs: Array = ev_map[anim_name]
			for item in raw_evs:
				if item is Dictionary:
					var d_ev := (item as Dictionary).duplicate()
					d_ev["t"] = float(d_ev.get("t", 0.0)) * event_time_scale
					if float(d_ev.get("t", 0.0)) <= 0.01:
						var w0 := GameData.sound_variant(d_ev)
						if not w0.is_empty():
							AudioManager.play_viewmodel_audio(self, w0)
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
		var hold_clip := "hold_low" if weapon_ctrl._grenade_lob_mode else "hold_high"
		if _vm_anim.has_animation(hold_clip):
			play_viewmodel_sequence([hold_clip])
		return
	if low in ["throw", "underhand", "hold_high", "hold_low"]:
		return
	if low == "pressbutton" and weapon_ctrl.plant_progress > 0.0:
		return
	if weapon_ctrl.is_reloading and low in ["start_reload", "insert"]:
		return
	_play_idle_viewmodel()


func _available_inspection_clips() -> Array:
	var available: Array = []
	if _vm_anim == null:
		return available
	var mmeta: Dictionary = GameData.models_meta.get("weapons/" + _cur_vm_model_name, {})
	var configured: Array = mmeta.get("inspect_clips", [])
	# Keep the historical fallback for models without an explicit variant list.
	if configured.is_empty():
		configured = ["inspect", "inspect_unsil", "inspect_1"]
	for raw_name in configured:
		var clip_name := String(raw_name)
		if _vm_anim.has_animation(clip_name):
			available.append(clip_name)
	return available


## CS-style weapon inspect (T): rotate through every authentic variant. C4 can
## inspect while held, but never while planting; reload locking is unchanged.
func _try_inspect_viewmodel() -> void:
	if not is_alive or weapon_ctrl == null:
		return
	if weapon_ctrl.is_reloading or weapon_ctrl.plant_progress > 0.0:
		return
	var available := _available_inspection_clips()
	if available.is_empty():
		return
	var wid := weapon_ctrl.current_weapon_id
	var inspection_key := wid + ":" + _cur_vm_model_name if wid == "knife" else wid
	var next_index := (int(_inspect_variant_indices.get(inspection_key, -1)) + 1) % available.size()
	_inspect_variant_indices[inspection_key] = next_index
	play_viewmodel_sequence([available[next_index]])


func _play_idle_viewmodel() -> void:
	if not _vm_anim:
		return
	var wid := weapon_ctrl.current_weapon_id
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var is_sil := bool(weapon_ctrl.silenced_state.get(wid, false)) and bool(spec.get("silencer", false))
	if wid == "elite" and int(weapon_ctrl.clips.get(wid, 2)) <= 1:
		play_viewmodel_sequence(["idle_bothempty" if int(weapon_ctrl.clips.get(wid, 2)) == 0 else "idle_leftempty", "idle"])
		return
	if int(weapon_ctrl.clips.get(wid, 1)) == 0 and _vm_anim != null and _vm_anim.has_animation("idle_empty"):
		play_viewmodel_sequence(["idle_empty"])
		return
	if bool(spec.get("silencer", false)) and not is_sil:
		play_viewmodel_sequence(["idle_unsil", "idle", "idle1"])
	else:
		play_viewmodel_sequence(["idle", "idle1", "idle3"])


func _on_fired_shot(wid: String, silenced: bool) -> void:
	var spec: Dictionary = GameData.weapons.get(wid, {})
	var rem_clip := int(weapon_ctrl.clips.get(wid, 1))
	var kick_scale := clampf(float(spec.get("recoil_up", 1.5)) / 3.5, 0.35, 1.35)
	_vm_kick_z = clampf(_vm_kick_z + 0.017 * kick_scale, 0.0, 0.040)
	_vm_kick_pitch = clampf(_vm_kick_pitch + deg_to_rad(1.95 * kick_scale), 0.0, deg_to_rad(5.2))
	_vm_kick_roll = clampf(_vm_kick_roll + deg_to_rad(randf_range(-1.1, 1.1) * kick_scale), deg_to_rad(-2.8), deg_to_rad(2.8))

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
	elif wid == "glock18":
		_elite_muzzle_left = false
		if bool(weapon_ctrl.burst_state.get("glock18", false)):
			# Burst cycles the three cyclic frames IN ORDER: shoot -> shoot2 -> shoot3
			if rem_clip == 0:
				play_viewmodel_sequence(["shoot_empty", "shoot"])
			else:
				var b_pick: String = ["shoot", "shoot2", "shoot3"][clampi(weapon_ctrl.glock_burst_frame - 1, 0, 2)]
				play_viewmodel_sequence([b_pick, "shoot"])
		else:
			# Keep the accepted semi-auto shoot2 -> shoot3 route. The refined GLB
			# gives all three clips the same mechanical slide cycle.
			if rem_clip == 0:
				play_viewmodel_sequence(["shoot_empty", "shoot2"])
			else:
				play_viewmodel_sequence(["shoot2", "shoot3"])
	elif wid == "revolver":
		_elite_muzzle_left = false
		if weapon_ctrl.revolver_alt_fire:
			play_viewmodel_sequence(["alt%d" % randi_range(1, 3), "alt1", "fire"])
		else:
			play_viewmodel_sequence(["fire", "shoot1"])
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

	if wid != "knife" and wid != "taser" and not bool(spec.get("grenade", false)) and wid != "c4":
		var muz_ofs: Vector3 = _current_vm_muzzle()
		var is_rifle_w: bool = int(spec.get("slot", 1)) == 1
		if viewmodel_pivot != null:
			ImpactEffects.spawn_barrel_smoke(viewmodel_pivot, muz_ofs + Vector3(0.0, 0.0, 0.02), is_rifle_w, 4, false)
		if not silenced:
			_muzzle_sprite.texture = GameData.get_texture("res://assets/sprites/muzzleflash%d.png" % randi_range(1, 4))
			_muzzle_sprite.rotation.z = randf() * TAU
			var mscale: float = clampf(0.86 + kick_scale * 0.28, 0.85, 1.38) * randf_range(0.92, 1.08)
			_muzzle_sprite.scale = Vector3.ONE * mscale
			_muzzle_sprite.visible = true
			var mlp := _current_vm_muzzle()
			if _is_viewmodel_mirrored():
				mlp.x = -mlp.x
			_muzzle_light.position = mlp
			_muzzle_light.light_energy = 2.2 + kick_scale * 1.15
			_muzzle_light.visible = true
			_vm_muzzle_light.position = mlp
			_vm_muzzle_light.light_energy = _muzzle_light.light_energy
			_vm_muzzle_light.visible = true
			_muzzle_timer = 0.045


func _on_zoom_changed(fov_deg: float, scoped_overlay: bool) -> void:
	camera.fov = fov_deg
	viewmodel_pivot.visible = not scoped_overlay
	if _vm_container:
		_vm_container.visible = not scoped_overlay
	scoped_overlay_changed.emit(scoped_overlay)


func _die(killer: Node3D, weapon_id: String, headshot: bool) -> void:
	_pending_vm_events.clear()
	AudioManager.stop_viewmodel_audio(self)
	var eye_xf: Transform3D = camera.global_transform
	viewmodel_pivot.visible = false
	if _vm_container:
		_vm_container.visible = false
	scoped_overlay_changed.emit(false)
	defuse_progress_changed.emit(0.0)
	camera.fov = GameData.fov
	super._die(killer, weapon_id, headshot)

	# Keep camera seamlessly at death eye transform & pull back into CS 1.5 3rd-person Deathcam!
	camera.top_level = true
	camera.global_transform = eye_xf
	_deathcam_timer = 2.85
	_spec_free_orbit_timer = 0.0
	spectator_target = null
	if is_instance_valid(killer) and killer != self:
		_deathcam_killer = killer
		spectator_target_changed.emit("Killed by %s [%s]" % [String(killer.get("actor_name")), weapon_id.to_upper()])
	else:
		_deathcam_killer = null
		spectator_target_changed.emit("")


func _finish_deathcam_to_spectator() -> void:
	_deathcam_timer = 0.0
	var alive_list: Array = []
	for a in RoundManager.actors:
		if is_instance_valid(a) and a != self and bool(a.get("is_alive")):
			alive_list.append(a)
	if alive_list.is_empty():
		spectator_target = null
		spectator_target_changed.emit("")
		return
	var found_idx: int = -1
	if is_instance_valid(_deathcam_killer):
		found_idx = alive_list.find(_deathcam_killer)
	if found_idx >= 0:
		_spec_index = found_idx
	else:
		_spec_index = clampi(_spec_index, 0, alive_list.size() - 1)
	var tgt := alive_list[_spec_index] as CSActor
	spectator_target = tgt
	spectator_target_changed.emit("%s (%s - %d HP)" % [tgt.actor_name, tgt.team, tgt.health])


func _cycle_spectator(step: int) -> void:
	var alive_list: Array = []
	for a in RoundManager.actors:
		if is_instance_valid(a) and a != self and bool(a.get("is_alive")):
			alive_list.append(a)
	if alive_list.is_empty():
		spectator_target = null
		spectator_target_changed.emit("")
		return
	_spec_index = (_spec_index + step + alive_list.size() * 4) % alive_list.size()
	var tgt: CSActor = alive_list[_spec_index]
	spectator_target = tgt
	spectator_target_changed.emit("%s (%s - %d HP)" % [tgt.actor_name, tgt.team, tgt.health])


func _update_spectator_camera(delta: float) -> void:
	# Phase 1: Authentic CS 1.5 3rd-Person Deathcam watching your own body collapse & settle!
	if _deathcam_timer > 0.0:
		_deathcam_timer -= delta
		if _deathcam_timer <= 0.0:
			_finish_deathcam_to_spectator()
		else:
			var body_focus: Vector3 = global_position + Vector3(0.0, 0.68, 0.0)
			if _spec_free_orbit_timer > 0.0:
				_spec_free_orbit_timer = maxf(0.0, _spec_free_orbit_timer - delta)
			else:
				var desired_yaw: float = look_yaw
				if is_instance_valid(_deathcam_killer):
					var to_k: Vector3 = _deathcam_killer.global_position - global_position
					if Vector2(to_k.x, to_k.z).length_squared() > 0.04:
						desired_yaw = atan2(-to_k.x, -to_k.z)
				look_yaw = lerp_angle(look_yaw, desired_yaw, minf(1.0, 3.8 * delta))
				look_pitch = lerpf(look_pitch, deg_to_rad(-24.0), minf(1.0, 4.2 * delta))

			var d_pitch: float = clampf(look_pitch, deg_to_rad(-62.0), deg_to_rad(18.0))
			var d_basis := Basis.from_euler(Vector3(d_pitch, look_yaw, 0.0), EULER_ORDER_YXZ)
			var pull_t: float = clampf((2.85 - _deathcam_timer) / 0.65, 0.15, 1.0)
			var death_cam_pos: Vector3 = body_focus + d_basis.z * (2.65 * pull_t) + Vector3(0.0, 0.55 * pull_t, 0.0)

			if get_world_3d() != null and get_world_3d().direct_space_state != null:
				var sp_d := get_world_3d().direct_space_state
				var q_d := PhysicsRayQueryParameters3D.create(body_focus + Vector3(0.0, 0.25, 0.0), death_cam_pos)
				q_d.collision_mask = 1
				var h_d: Dictionary = sp_d.intersect_ray(q_d)
				if not h_d.is_empty():
					var hp_d: Vector3 = h_d["position"]
					var hn_d: Vector3 = h_d["normal"]
					death_cam_pos = hp_d + hn_d * 0.24

			camera.top_level = true
			camera.global_position = camera.global_position.lerp(death_cam_pos, minf(1.0, 9.5 * delta))
			if camera.global_position.distance_squared_to(body_focus) > 0.02:
				camera.look_at(body_focus, Vector3.UP)
			return

	# Phase 2: Chase-Cam Spectator on Killer / Surviving Bots
	var alive_list: Array = []
	for a in RoundManager.actors:
		if is_instance_valid(a) and a != self and bool(a.get("is_alive")):
			alive_list.append(a)
	if alive_list.is_empty():
		return
	_spec_index = clampi(_spec_index, 0, alive_list.size() - 1)
	var tgt: CSActor = alive_list[_spec_index]
	spectator_target = tgt
	var tgt_vis: Vector3 = tgt.get_visual_world_pos()
	var focus_pt: Vector3 = tgt_vis + Vector3(0.0, 1.42, 0.0)

	if _spec_free_orbit_timer > 0.0:
		_spec_free_orbit_timer = maxf(0.0, _spec_free_orbit_timer - delta)
	else:
		look_yaw = lerp_angle(look_yaw, tgt.look_yaw, minf(1.0, 4.5 * delta))
		look_pitch = lerpf(look_pitch, deg_to_rad(-16.0), minf(1.0, 4.5 * delta))

	var cam_pitch := clampf(look_pitch, deg_to_rad(-58.0), deg_to_rad(32.0))
	var orbit_basis := Basis.from_euler(Vector3(cam_pitch, look_yaw, 0.0), EULER_ORDER_YXZ)
	var desired_pos: Vector3 = focus_pt + orbit_basis.z * 3.1 + Vector3(0.0, 0.35, 0.0)

	# Spring-arm wall raycast so chase-cam never clips inside BSP walls/ceilings!
	if get_world_3d() != null:
		var sp := get_world_3d().direct_space_state
		if sp != null:
			var q_cam := PhysicsRayQueryParameters3D.create(focus_pt, desired_pos)
			q_cam.collision_mask = 1
			var h_cam := sp.intersect_ray(q_cam)
			if not h_cam.is_empty():
				var hp: Vector3 = h_cam["position"]
				var hn: Vector3 = h_cam["normal"]
				desired_pos = hp + hn * 0.24

	camera.top_level = true
	if camera.global_position.distance_to(desired_pos) > 12.0:
		camera.global_position = desired_pos
	else:
		camera.global_position = camera.global_position.lerp(desired_pos, minf(1.0, 16.0 * delta))
	camera.look_at(focus_pt, Vector3.UP)


# The camera sits at 1.66 m (and interpolates duck/steps), not the generic
# bot eye at 1.85 m. Use its actual optical ray for every human attack.
func get_eye_position() -> Vector3:
	if is_instance_valid(camera):
		return camera.global_position
	return super.get_eye_position()


func get_aim_basis(punch_deg: Vector2) -> Basis:
	if is_instance_valid(camera):
		return camera.global_basis.orthonormalized()
	return super.get_aim_basis(punch_deg)
