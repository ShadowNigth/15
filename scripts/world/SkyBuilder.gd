class_name SkyBuilder
extends RefCounted
## Builds a GoldSrc 6-sided skybox & WorldEnvironment from res://assets/textures/sky/<skyname>*.png.


static func setup_environment(parent: Node3D, skyname: String) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.54, 0.65)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# World surfaces use EMISSION for baked GoldSrc lightmaps; characters/props use ambient + sun!
	env.ambient_light_color = Color(0.76, 0.75, 0.72)
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	parent.add_child(we)

	# Directional sun light on visual layer 2 (characters & dynamic models) + subtle bounce
	var sun := DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 0.65
	sun.shadow_enabled = false
	parent.add_child(sun)

	# 6-sided unshaded Skybox cube following camera (huge 900m cube)
	var clean_sky := skyname.to_lower().strip_edges()
	var sky_root := Node3D.new()
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

	var half := 420.0
	# Faces inward: [suffix, pos, rot_deg]
	var faces := [
		["ft", Vector3(0, 0, -half), Vector3(0, 0, 0)],
		["bk", Vector3(0, 0, half), Vector3(0, 180, 0)],
		["lf", Vector3(-half, 0, 0), Vector3(0, 90, 0)],
		["rt", Vector3(half, 0, 0), Vector3(0, -90, 0)],
		["up", Vector3(0, half, 0), Vector3(90, 0, 0)],
		["dn", Vector3(0, -half, 0), Vector3(-90, 0, 0)],
	]

	for f in faces:
		var side: String = f[0]
		var tex := GameData.get_texture("res://assets/textures/sky/%s%s.png" % [chosen, side])
		if not tex:
			continue
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(half * 2.004, half * 2.004)
		mi.mesh = qm
		mi.position = f[1]
		mi.rotation_degrees = f[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var sm := StandardMaterial3D.new()
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = tex
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = sm
		sky_root.add_child(mi)

	return we
