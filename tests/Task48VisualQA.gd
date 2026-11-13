extends "res://tests/MissionObjectiveRegressionTest.gd"
## Render real simulated mission states with OpenGL, not the headless dummy.
## xvfb-run godot --path . --disable-render-loop --fixed-fps 60 res://tests/Task48VisualQA.tscn

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Task48VisualQA requires a real rendering display")
		get_tree().quit(1)
		return
	var output := OS.get_environment("TASK48_CAPTURE_DIR")
	if output.is_empty():
		output = OS.get_user_data_dir().path_join("task48-captures")
	DirAccess.make_dir_recursive_absolute(output)
	var cases := [
		{"map": "de_dust2", "bots": 8, "seed": 2, "frames": 1800},
		{"map": "de_inferno", "bots": 10, "seed": 4807, "frames": 1800},
		{"map": "de_train", "bots": 6, "seed": 4808, "frames": 1800},
	]
	var manifest: Array[Dictionary] = []
	for entry in cases:
		seed(int(entry["seed"]))
		var map_name := String(entry["map"])
		var world := _make_world(map_name, int(entry["bots"]))
		if world == null:
			get_tree().quit(1)
			return
		for frame in range(int(entry["frames"])):
			await get_tree().physics_frame
			if RoundManager.state != RoundManager.State.LIVE:
				break
		var subject: Node3D = null
		if subject == null:
			for hostage in RoundManager.hostages:
				if is_instance_valid(hostage) and not hostage.is_rescued and is_instance_valid(hostage.leader):
					subject = hostage
					break
		if subject == null:
			# If rescue finishes before the requested time, retain the actual
			# end-of-round state and observe a surviving rescuer, not a staged NPC.
			for bot in world.bots:
				if bot.team == "CT" and bot.is_alive:
					subject = bot
					break
		if subject == null:
			push_error("No active mission actor available for " + map_name)
			get_tree().quit(1)
			return
		var focus := subject.global_position + Vector3.UP * 1.0
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.fov = 72.0
		camera.near = 0.08
		var desired := focus + Vector3(4.0, 2.0, 5.0)
		var query := PhysicsRayQueryParameters3D.create(focus, desired)
		query.collision_mask = 1
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		camera.global_position = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.30 if not hit.is_empty() else desired
		camera.look_at(focus)
		camera.make_current()
		# Pause only after real simulation, so several render warmup frames show
		# the same gameplay instant without teleporting actors or staging poses.
		get_tree().paused = true
		for warmup in range(4):
			await get_tree().process_frame
			RenderingServer.force_draw(false)
		var image := get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Empty rendered framebuffer for " + map_name)
			get_tree().quit(1)
			return
		var png := output.path_join(map_name + ".png")
		var jpg := output.path_join(map_name + ".jpg")
		if image.save_png(png) != OK:
			get_tree().quit(1)
			return
		# Keep the full PNG as the artifact; a smaller JPEG permits inspection
		# through check annotations when artifact storage is inaccessible.
		image.resize(640, 360, Image.INTERPOLATE_LANCZOS)
		if image.save_jpg(jpg, 0.45) != OK:
			get_tree().quit(1)
			return
		manifest.append({"map": map_name, "subject": str(subject.global_position), "renderer": RenderingServer.get_video_adapter_name(), "rescued": RoundManager.hostages_rescued_this_round})
		print("[TASK48 RENDER] captured ", map_name, " subject=", subject.global_position)
		get_tree().paused = false
		await _free_world(world)
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "  "))
	get_tree().quit(0)
