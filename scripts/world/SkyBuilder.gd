class_name SkyBuilder
extends Node3D
## Builds a seamless camera-centered GoldSrc 6-sided skybox & character lighting rig.


func _process(_delta: float) -> void:
	var vp := get_viewport()
	if vp:
		var cam := vp.get_camera_3d()
		if is_instance_valid(cam):
			global_position = cam.global_position


static func setup_environment(parent: Node3D, skyname: String) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.56, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Ambient illuminates characters, viewmodels, and props (world shader has ambient_light_disabled)
	env.ambient_light_color = Color(0.92, 0.90, 0.86)
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	parent.add_child(we)

	# Key + Fill directional lights masked to Visual Layers 2 & 3 (mask 6 = Characters + Viewmodels)
	# so BSP world brushes (Layer 1) use pure hlrad lightmaps while characters & weapons look crisp!
	var sun := DirectionalLight3D.new()
	sun.name = "CharacterSunLight"
	sun.rotation_degrees = Vector3(-48.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.15
	sun.light_cull_mask = 6
	sun.shadow_enabled = false
	parent.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "CharacterFillLight"
	fill.rotation_degrees = Vector3(32.0, -142.0, 0.0)
	fill.light_color = Color(0.80, 0.86, 0.95)
	fill.light_energy = 0.55
	fill.light_cull_mask = 6
	fill.shadow_enabled = false
	parent.add_child(fill)

	# 6-sided seamless GoldSrc skybox centered on active Camera3D every frame
	var clean_sky := skyname.to_lower().strip_edges()
	var sky_root := SkyBuilder.new()
	sky_root.name = "GoldSrcSkybox"
	parent.add_child(sky_root)

	var candidates := [clean_sky, clean_sky + "_", "des", "2desert", "morningdew", "city1"]
	var chosen := ""
	for c in candidates:
		if ResourceLoader.exists("res://assets/textures/sky/%sft.png" % c):
			chosen = c
			break

	if chosen.is_empty():
		return we

	var half := 550.0
	# Exact GoldSrc / Quake-2 skybox face mapping verified edge-by-edge:
	# ft (-Z) -> right connects to lf (+X) -> bk (+Z) -> rt (-X) -> ft (-Z)
	var faces := [
		["ft", Vector3(0.0, 0.0, -half), Vector3(0.0, 0.0, 0.0)],
		["lf", Vector3(half, 0.0, 0.0), Vector3(0.0, -90.0, 0.0)],
		["bk", Vector3(0.0, 0.0, half), Vector3(0.0, 180.0, 0.0)],
		["rt", Vector3(-half, 0.0, 0.0), Vector3(0.0, 90.0, 0.0)],
		["up", Vector3(0.0, half, 0.0), Vector3(90.0, 90.0, 0.0)],
		["dn", Vector3(0.0, -half, 0.0), Vector3(-90.0, 90.0, 0.0)],
	]

	for f in faces:
		var side: String = f[0]
		var tex := GameData.get_texture("res://assets/textures/sky/%s%s.png" % [chosen, side])
		if not tex:
			continue
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(half * 2.002, half * 2.002)
		mi.mesh = qm
		mi.position = f[1]
		mi.rotation_degrees = f[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = tex
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sm.texture_repeat = false  # Prevents opposite-edge wrap seams along sky borders!
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = sm
		sky_root.add_child(mi)

	return we
