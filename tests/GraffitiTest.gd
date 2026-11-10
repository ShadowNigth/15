extends Node3D
var failures := 0
var checks := 0
var sprayer: GraffitiSprayer
var camera: Camera3D
var wall: StaticBody3D

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: " + message)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.09, 0.11, 0.14))
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.11, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.85
	environment.environment = env
	add_child(environment)
	wall = StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.1)
	shape.shape = box
	wall.add_child(shape)
	var visual := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = box.size
	visual.mesh = wall_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.45, 0.39)
	visual.material_override = mat
	wall.add_child(visual)
	add_child(wall)
	camera = Camera3D.new()
	camera.position = Vector3(0, 0, 2)
	camera.current = true
	add_child(camera)
	sprayer = GraffitiSprayer.new()
	add_child(sprayer)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(sprayer.catalog.items.size() == 3, "three items")
	for item in sprayer.catalog.items:
		var texture := load("res://" + str(item.texture)) as Texture2D
		check(texture != null, "local texture " + str(item.id))
		check(texture.get_image().detect_alpha() != Image.ALPHA_NONE, "transparent background")
	check(sprayer.build_surface(camera) != null, "flat wall supported")
	camera.position.x = 1.9
	check(sprayer.build_surface(camera) == null, "wall edge rejected")
	camera.position = Vector3(0, 0, 4)
	check(sprayer.build_surface(camera) == null, "out of range")
	camera.position = Vector3(0, 0, 2)
	wall.rotation.y = 0.5
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(sprayer.build_surface(camera) != null, "angled wall supported")
	wall.rotation.y = 0
	wall.collision_layer = 2
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(sprayer.build_surface(camera) == null, "actor layer excluded")
	wall.collision_layer = 1
	wall.rotation.x = PI / 2
	camera.position = Vector3(0, 2, 0)
	camera.rotation.x = -PI / 2
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(sprayer.build_surface(camera) == null, "floors rejected")
	wall.rotation.x = 0
	camera.rotation.x = 0
	camera.position = Vector3(0, 0, 2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	sprayer.selected = 0
	check(sprayer.spray(camera), "first spray")
	check(not sprayer.spray(camera), "cooldown blocks repetition")
	check(sprayer.marks.size() == 1, "one mark after blocked action")
	var first := sprayer.marks[0]
	check(first.mesh.get_surface_count() == 1, "mesh surface")
	check(first.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 81, "81 validated samples")
	check(first.material_override is StandardMaterial3D, "compatibility material")
	check(first.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "no shadow")
	sprayer._expire(first)
	await get_tree().process_frame
	check(sprayer.marks.is_empty() and not is_instance_valid(first), "expiry removes mark")
	for i in 34:
		sprayer.cooldown = 0
		sprayer.spray(camera)
	check(sprayer.marks.size() == 32, "bounded mark count")
	for mark in sprayer.marks.duplicate():
		sprayer._expire(mark)
	await get_tree().process_frame
	# Render the actual implementation, all three selected local images on one wall.
	for i in 3:
		camera.position.x = (i - 1) * 0.85
		sprayer.selected = i
		sprayer.cooldown = 0
		check(sprayer.spray(camera), "render sample " + str(i))
	camera.position = Vector3(0, 0, 2.2)
	sprayer.show_notice("Muestra: V pintar · J cambiar", 30)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var capture := OS.get_environment("GRAFFITI_CAPTURE")
	if not capture.is_empty():
		get_viewport().get_texture().get_image().save_png(capture)
	var remaining := sprayer.marks.duplicate()
	sprayer.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	for mark in remaining:
		check(not is_instance_valid(mark), "teardown removes world paint")
	print("PASS: Graffiti ", checks, " checks; failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)
