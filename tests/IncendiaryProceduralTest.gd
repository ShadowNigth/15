extends Node
## Deterministic procedural-fire coverage on real collision geometry.
##   godot --headless --path . res://tests/IncendiaryProceduralTest.tscn

var _checks := 0
var _failures: Array[String] = []
var _world: Node3D = null
var _floor: StaticBody3D = null


func _ready() -> void:
	call_deferred("_run")


func _expect(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		push_error("[INCENDIARY PROCEDURAL TEST] " + description)


func _make_collision(size: Vector3, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	_world.add_child(body)
	body.position = pos
	body.add_child(collision)
	return body


func _make_area(pos: Vector3, seed_value: int) -> IncendiaryArea:
	var area := IncendiaryArea.new()
	_world.add_child(area)
	area.global_position = pos
	area.setup_fire(null, "molotov", seed_value)
	area.set_physics_process(false)
	area.set_process(false)
	area._tick = 999.0
	return area


func _profile_signature(area: IncendiaryArea) -> String:
	return (
		"%d|%.5f|%.5f|%.5f|%d|%.5f"
		% [
			area.target_patch_count,
			area.radius,
			area.envelope_aspect,
			area.propagation_heading,
			area._branch_budget,
			area._branch_arc,
		]
	)


func _distribution_signature(area: IncendiaryArea) -> String:
	var parts: Array[String] = []
	for patch in area._patches:
		var pos: Vector3 = patch["pos"]
		parts.append("%.3f,%.3f,%.3f,%.3f" % [pos.x, pos.y, pos.z, float(patch["radius"])])
	return "|".join(parts)


func _mesh_signature(area: IncendiaryArea) -> String:
	var flame := area._flames[0]["node"] as MeshInstance3D
	var mesh := flame.mesh as ArrayMesh
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var signature := str(vertices.size())
	for index in range(mini(12, vertices.size())):
		signature += str(vertices[index])
	return signature


func _expand(area: IncendiaryArea, steps: int = 132) -> void:
	for step in range(steps):
		area._physics_process(0.052)
		if step % 8 == 0:
			area._process(0.052)


func _run() -> void:
	_world = Node3D.new()
	add_child(_world)
	_floor = _make_collision(Vector3(18.0, 0.20, 18.0), Vector3(0.0, -0.10, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame

	var areas: Array[IncendiaryArea] = [
		_make_area(Vector3(-3.2, 0.03, 0.0), 13579),
		_make_area(Vector3(0.0, 0.03, 0.0), 24680),
		_make_area(Vector3(3.2, 0.03, 0.0), 97531),
	]
	var profiles := {}
	var initial_meshes := {}
	for area in areas:
		_expect(
			area._patches.size() == 1 and area._flames.size() == 1,
			"Every throw begins with its own ignition mesh"
		)
		_expect(
			area._burst.one_shot and area._burst.emitting,
			"Every impact creates an initial GPU flame burst"
		)
		profiles[_profile_signature(area)] = true
		initial_meshes[_mesh_signature(area)] = true
	_expect(
		profiles.size() == areas.size(),
		"Seeded throws randomize area, aspect, direction and branch configuration"
	)
	_expect(
		initial_meshes.size() == areas.size(),
		"Seeded throws generate different flame geometry rather than rescaling one prefab"
	)

	var distributions := {}
	for area in areas:
		_expand(area)
		distributions[_distribution_signature(area)] = true
		_expect(
			area._patches.size() >= 8 and area._patches.size() <= area.target_patch_count,
			(
				"Connected propagation produces a substantial bounded layout (seed %d: %d/%d patches)"
				% [area.simulation_seed, area._patches.size(), area.target_patch_count]
			)
		)
		_expect(
			area._walkers.is_empty() or area._patches.size() == area.target_patch_count,
			(
				"Expansion stops at its fuel limit (seed %d: %d/%d patches, %d walkers)"
				% [
					area.simulation_seed,
					area._patches.size(),
					area.target_patch_count,
					area._walkers.size()
				]
			)
		)
		_expect(
			(
				area._ember_process.emission_point_count == area._patches.size()
				and area._smoke_process.emission_point_texture.get_width() == area._patches.size()
			),
			"GPU emission points follow the actual connected burning zones"
		)
		_expect(
			area.envelope_aspect < 1.0 and area.envelope_aspect >= 0.48,
			"The fuel envelope is asymmetric rather than a perfect circle"
		)
		var outside := false
		for patch in area._patches:
			var pos: Vector3 = patch["pos"]
			if Vector2(pos.x, pos.z).length() > area.radius * 1.08 + 0.001:
				outside = true
		_expect(not outside, "No branch exceeds its randomized maximum fuel travel")
	_expect(
		distributions.size() == areas.size(),
		"Every seed creates a distinct connected patch distribution"
	)

	var repeat_a := _make_area(Vector3.ZERO, 55555)
	var repeat_b := _make_area(Vector3.ZERO, 55555)
	_expand(repeat_a, 36)
	_expand(repeat_b, 36)
	_expect(
		(
			_profile_signature(repeat_a) == _profile_signature(repeat_b)
			and _distribution_signature(repeat_a) == _distribution_signature(repeat_b)
		),
		"An explicit test seed reproduces exactly the same simulation"
	)

	var random_a := _make_area(Vector3.ZERO, 0)
	var random_b := _make_area(Vector3.ZERO, 0)
	_expect(
		random_a.simulation_seed != random_b.simulation_seed,
		"Normal throws independently randomize their simulation seed"
	)

	var fading := areas[0]
	fading.life_left = 0.40
	fading._physics_process(0.016)
	fading._process(0.016)
	var fading_values_valid := true
	var visible_flames := 0
	for entry in fading._flames:
		var flame := entry["node"] as MeshInstance3D
		if not flame.visible:
			continue
		visible_flames += 1
		var material := entry["material"] as ShaderMaterial
		fading_values_valid = (
			fading_values_valid
			and float(material.get_shader_parameter("fade")) < 0.50
			and float(material.get_shader_parameter("height_fade")) < 1.0
		)
	_expect(
		visible_flames > 0 and fading_values_valid,
		"Visible flame opacity and height decline progressively near exhaustion"
	)
	_expect(
		not fading._ember_particles.emitting and not fading._smoke_particles.emitting,
		"GPU emitters stop producing new particles while existing particles dissipate"
	)
	fading.life_left = -0.01
	fading._process(0.016)
	var hidden := true
	for entry in fading._flames:
		hidden = hidden and not (entry["node"] as MeshInstance3D).visible
	_expect(
		(
			hidden
			and not fading.is_queued_for_deletion()
			and fading._nearest_patch(Vector3.ZERO).is_empty()
		),
		"Burnout hides dead flames and damage before final particle cleanup"
	)
	fading.life_left = -1.14
	fading._physics_process(0.02)
	_expect(
		fading.is_queued_for_deletion(), "The completed independent simulation cleans itself up"
	)

	for area in areas:
		if is_instance_valid(area) and not area.is_queued_for_deletion():
			area.queue_free()
	for area in [repeat_a, repeat_b, random_a, random_b]:
		area.queue_free()
	_floor.queue_free()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print(
			(
				"[INCENDIARY PROCEDURAL TEST] PASS: %d checks; independent seeds, meshes, branches, GPU emission and progressive burnout."
				% _checks
			)
		)
		get_tree().quit()
	else:
		printerr("[INCENDIARY PROCEDURAL TEST] FAIL: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			printerr(" - " + failure)
		get_tree().quit(1)
