class_name MenuBackdrop
extends SubViewportContainer
## Presentation-only world: no actors, physics, round registration or gameplay RNG.
const MAPS := ["de_dust2", "de_aztec", "cs_italy"]
const LABELS := ["Dust II · Desierto", "Aztec · Ruinas", "Italy · Ciudad"]
const SETTINGS := "user://menu_presentation.cfg"
var selection := "de_dust2"
var motion := true
var viewport: SubViewport
var scenery: Node3D
var camera: Camera3D
var origin := Vector3.ZERO
var yaw := 0.0
var clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var config := ConfigFile.new()
	if config.load(SETTINGS) == OK:
		selection = str(config.get_value("background", "map", selection))
		motion = bool(config.get_value("background", "motion", true))
	if selection not in MAPS:
		selection = MAPS[0]
	change_background(selection, false)

func save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("background", "map", selection)
	config.set_value("background", "motion", motion)
	if config.save(SETTINGS) != OK:
		push_warning("No se pudo guardar el fondo del menú")

func change_background(map_id: String, persist: bool = true) -> void:
	if map_id not in MAPS:
		return
	if scenery:
		viewport.remove_child(scenery)
		scenery.queue_free()
	selection = map_id
	clock = 0.0
	scenery = Node3D.new()
	viewport.add_child(scenery)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/" + map_id + ".json"))
	SkyBuilder.setup_environment(scenery, str(data.get("skyname", "des")))
	var scene := load(str(data.glb)) as PackedScene
	if scene:
		var model := scene.instantiate()
		scenery.add_child(model)
		var lightmap := GameData.get_texture(str(data.lightmap))
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			for index in range(mesh.mesh.get_surface_count()):
				var source := mesh.mesh.surface_get_material(index) as StandardMaterial3D
				if source and source.albedo_texture:
					var mat := ShaderMaterial.new()
					mat.shader = load("res://assets/shaders/goldsrc_world.gdshader")
					mat.set_shader_parameter("albedo_tex", source.albedo_texture)
					mat.set_shader_parameter("lightmap_tex", lightmap)
					mesh.set_surface_override_material(index, mat)
	var spawn: Dictionary = data.t_spawns[0]
	if map_id == "de_dust2":
		spawn = {"pos": [25.0, 5.5, 23.0], "yaw": 0.0}
	var p: Array = spawn.pos
	origin = Vector3(p[0], p[1] + 1.65, p[2])
	yaw = float(spawn.yaw)
	camera = Camera3D.new()
	camera.fov = 65
	scenery.add_child(camera)
	camera.position = origin
	camera.rotation.y = yaw
	if persist:
		save_preferences()

func _process(delta: float) -> void:
	if camera and motion:
		clock += delta
		# Tiny bounded cinematic pan; never travels through map geometry.
		camera.rotation.y = yaw + sin(clock * 0.12) * 0.10
		camera.rotation.x = -0.025 + sin(clock * 0.09) * 0.018
