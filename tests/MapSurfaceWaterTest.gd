extends Node
## Real BSP material/water integration test.
##   godot --headless --path . res://tests/MapSurfaceWaterTest.tscn

const EXPECTED_WATER_ZONES := {
	"as_oilrig": 3,
	"cs_estate": 1,
	"cs_militia": 2,
	"cs_siege": 9,
	"de_aztec": 3,
	"de_chateau": 18,
	"de_piranesi": 1,
	"de_survivor": 1,
	"de_torn": 11,
}

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[MAP SURFACE/WATER TEST] " + description)


func _run() -> void:
	var total_zones := 0
	for map_name in EXPECTED_WATER_ZONES:
		var data := GameData.load_map_data(String(map_name))
		var zones: Array = data.get("water_zones", [])
		total_zones += zones.size()
		_expect(zones.size() == int(EXPECTED_WATER_ZONES[map_name]), "%s preserves its BSP water volumes" % map_name)
		for zone in zones:
			_expect(zone is Dictionary and (zone as Dictionary).has("min") and (zone as Dictionary).has("max"),
				"%s water volume has bounded BSP geometry" % map_name)
	_expect(EXPECTED_WATER_ZONES.size() == 9 and total_zones == 49,
		"All nine water maps expose exactly 49 authentic water volumes")

	# A worldspawn mesh may contain both solid architecture and one liquid primitive.
	var source := ArrayMesh.new()
	for index in range(2):
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var offset := float(index) * 2.0
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(offset, 0.0, 0.0), Vector3(offset + 1.0, 0.0, 0.0), Vector3(offset, 0.0, 1.0),
		])
		source.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var holder := MeshInstance3D.new()
	holder.mesh = source
	add_child(holder)
	MapLoader._create_filtered_trimesh_collision(holder, [1])
	var body := holder.get_child(0) as StaticBody3D
	var collision := body.get_child(0) as CollisionShape3D if body != null else null
	var shape := collision.shape as ConcavePolygonShape3D if collision != null else null
	_expect(shape != null and shape.get_faces().size() == 3,
		"Mixed worldspawn collision excludes only the liquid primitive")
	_expect(source.get_surface_count() == 2, "Filtered collision never alters the visible source mesh")
	holder.queue_free()

	GameData.bot_count = 0
	GameData.start_money = 16000
	GameData.selected_map = "de_aztec"
	var packed := load("res://scenes/GameWorld.tscn") as PackedScene
	_expect(packed != null, "GameWorld loads for the Aztec water integration")
	if packed == null:
		_finish()
		return
	var world := packed.instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban")
	world.team_menu.close_menu()
	RoundManager.state = RoundManager.State.LIVE
	_expect(world.water != null and world.water_zones.size() == 3,
		"GameWorld installs WaterEffects for all three Aztec river sections")

	var world_shader := load("res://assets/shaders/goldsrc_world.gdshader") as Shader
	var water_shader := load("res://assets/shaders/water.gdshader") as Shader
	var materials: Dictionary = (world.map_runtime["root"] as Node3D).get_meta("world_materials", {})
	var relief_materials := 0
	var water_materials := 0
	var original_bindings := 0
	for raw in materials.values():
		var material := raw as ShaderMaterial
		if material == null or material.shader == null:
			continue
		var bound := material.get_shader_parameter("albedo_tex") as Texture2D
		if bound != null and bound.resource_path.begins_with("res://assets/textures/world/"):
			var texture_name := bound.resource_path.get_file().get_basename()
			var logical: Dictionary = GameData.world_textures_meta.get(texture_name, {})
			if not logical.is_empty() and bound.get_width() == int(logical.get("w", 0)) and bound.get_height() == int(logical.get("h", 0)):
				original_bindings += 1
		if material.shader == water_shader:
			water_materials += 1
		elif material.shader == world_shader:
			if float(material.get_shader_parameter("relief_depth")) > 0.0:
				relief_materials += 1
	_expect(relief_materials >= 12, "Opaque Aztec walls and floors receive height relief and definition")
	_expect(water_materials > 0, "Aztec water meshes use the dedicated animated water shader")
	_expect(original_bindings > 0, "Rendered BSP shaders bind original-resolution world artwork")
	_expect(not DirAccess.dir_exists_absolute("res://assets/textures/world/hd"), "World HD override directory is fully removed")
	_expect(world_shader.code.contains("dFdx") and world_shader.code.contains("textureLod"),
		"Architectural relief uses derivative normals and mip-stable detail")
	_expect(water_shader.code.contains("hint_screen_texture") and water_shader.code.contains("TIME"),
		"Water combines animated waves with actual screen refraction")

	var zone: AABB = world.water_zones[0]
	var center := zone.get_center()
	var surface_y := zone.end.y
	var feet := Vector3(center.x, surface_y - 0.20, center.z)
	var above := Vector3(center.x, surface_y + 2.0, center.z)
	var below := Vector3(center.x, surface_y - 2.0, center.z)
	var info := world.get_water_info(feet)
	_expect(bool(info.get("in_water", false)) and float(info.get("depth", 0.0)) > 0.19,
		"Actor body query detects wading depth at the river surface")
	_expect(not bool(world.get_water_info(above).get("in_water", true)),
		"Actors above the river do not inherit water physics")
	var outside := feet + Vector3(zone.size.x + 2.0, 0.0, 0.0)
	_expect(not bool(world.get_water_info(outside).get("in_water", true)),
		"Water physics remains bounded to the authentic river footprint")
	var ray_hit := world.water.get_water_ray_hit(above, below)
	_expect(not ray_hit.is_empty() and absf((ray_hit["position"] as Vector3).y - surface_y) < 0.001,
		"Ray query intersects the exact BSP water plane")

	var before := world.water._ripples.size()
	world.player.weapon_ctrl._fire_penetrating_ray(above, Vector3.DOWN, 5.0, 30.0, 1.0, 1.0, 0)
	_expect(world.water._ripples.size() == before + 1,
		"A real weapon ray crossing water creates an impact ring and droplets")

	before = world.water._ripples.size()
	var grenade := GrenadeProjectile.new()
	world.add_child(grenade)
	grenade.set_physics_process(false)
	grenade.global_position = above
	grenade.velocity = Vector3(0.0, -8.0, 0.0)
	grenade.fuse_left = 10.0
	grenade._physics_process(0.20)
	_expect(world.water._ripples.size() == before + 1 and grenade.velocity.length() < 12.3,
		"A grenade crossing the surface splashes and loses energy to water resistance")
	grenade.queue_free()

	before = world.water._ripples.size()
	_expect(world.water.footstep_at(feet, "CT", false) and world.water._ripples.size() == before + 1,
		"Wading footsteps emit original water audio and a smaller physical ripple")

	world.player.global_position = feet
	world.player.velocity = Vector3(0.0, -12.0, 0.0)
	world.player.apply_goldsrc_movement(Vector3.ZERO, false, false, false, 1.0 / 60.0)
	_expect(world.player.in_water and world.player.water_depth > 0.19,
		"The real GoldSrc actor controller receives its water state")
	_expect(world.player.velocity.y >= -4.2001,
		"Water resistance cushions downward velocity instead of applying full air gravity")

	world.queue_free()
	await get_tree().process_frame
	AudioManager.stop_all()
	# Fixed-FPS headless frames can elapse faster than one audio mix block.
	OS.delay_msec(50)
	await get_tree().process_frame
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("[MAP SURFACE/WATER TEST] PASS: %d checks; 9 maps, 49 BSP water volumes, relief, bullets, grenades and wading." % _checks)
		get_tree().quit()
	else:
		printerr("[MAP SURFACE/WATER TEST] FAIL: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			printerr(" - " + failure)
		get_tree().quit(1)
