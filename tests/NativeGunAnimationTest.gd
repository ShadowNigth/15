extends Node
## Production PlayerController, all 42 native gun/utility rigs and pose matrices.
var _checks := 0
var _failures: Array[String] = []
var _capture := false
var _output := "/tmp/native-gun-captures"


func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	call_deferred("_run")


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error("[NATIVE GUN TEST] " + message)


func _skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child in root.get_children():
		var result := _skeleton(child)
		if result != null:
			return result
	return null


func _run() -> void:
	var reports: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/native_gun_animation_report.json"))
	_expect(reports.size() == 42, "35 firearms, six grenades and C4")
	GameData.select_knife("original")
	GameData.select_glove("classic")
	GameData.selected_map = "de_dust2"
	GameData.bot_count = 2
	GameData.freeze_time = 600.0
	var world := (load("res://scenes/GameWorld.tscn") as PackedScene).instantiate() as GameWorld
	add_child(world)
	world._on_player_team_chosen("CT", "urban")
	world.team_menu.close_menu()
	var player := world.player
	var source_clips := 0
	for raw_wid in reports:
		var wid := String(raw_wid)
		var report: Dictionary = reports[wid]
		var spec: Dictionary = GameData.weapons[wid]
		var meta: Dictionary = GameData.models_meta["weapons/" + String(spec["v_model"])]
		player.weapon_ctrl.give_weapon(wid, maxi(1, int(spec.get("clip_size", 1))), 90)
		player.weapon_ctrl.equip_weapon_by_id(wid)
		player._rebuild_viewmodel(wid)
		player._play_idle_viewmodel()
		var anim: AnimationPlayer = player._vm_anim
		_expect(anim != null, wid + " production animated viewmodel")
		if anim == null:
			continue
		var skeleton := _skeleton(player._vm_model_root)
		_expect(skeleton != null, wid + " original skeleton retained")
		if skeleton == null:
			continue
		source_clips += int(report["source_clip_count"])
		for clip in report["clips"]:
			_expect(anim.has_animation(String(clip)), wid + " native clip " + String(clip))
			if anim.has_animation(String(clip)):
				_expect(absf(anim.get_animation(String(clip)).length - float(report["durations"][clip])) < 0.002, wid + " unmodified source clip duration " + String(clip))
		for clip in report["pose_checkpoints"]:
			player.play_viewmodel_sequence([clip])
			for point in report["pose_checkpoints"][clip]:
				anim.seek(minf(float(point["t"]), anim.get_animation(String(clip)).length - 0.00001), true)
				skeleton.force_update_all_bone_transforms()
				for bone_name in point["bones"]:
					var bone := skeleton.find_bone(String(bone_name))
					_expect(bone >= 0, wid + " bone " + String(bone_name))
					if bone < 0:
						continue
					var expected: Array = point["bones"][bone_name]
					var actual := skeleton.get_bone_global_pose(bone)
					var position := Vector3(float(expected[0][3]),float(expected[1][3]),float(expected[2][3]))
					_expect(actual.origin.distance_to(position) < 0.002, wid + " " + String(clip) + " native pivot " + String(bone_name) + " at " + str(point["t"]))
					var expected_basis := Basis(Vector3(expected[0][0],expected[1][0],expected[2][0]), Vector3(expected[0][1],expected[1][1],expected[2][1]), Vector3(expected[0][2],expected[1][2],expected[2][2]))
					_expect(actual.basis.x.distance_to(expected_basis.x) + actual.basis.y.distance_to(expected_basis.y) + actual.basis.z.distance_to(expected_basis.z) < 0.015, wid + " " + String(clip) + " native axes/parity " + String(bone_name))
		for clip in ["reload", "start_reload", "insert", "after_reload", "add_silencer", "detach_silencer"]:
			if anim.has_animation(clip) and (meta["gameplay_seq_durations"] as Dictionary).has(clip):
				player.play_viewmodel_sequence([clip])
				_expect(absf(anim.get_animation(clip).length / anim.speed_scale - float(meta["gameplay_seq_durations"][clip])) < 0.003, wid + " preserves action timing " + clip)
		for hand in [true, false]:
			GameData.right_hand = hand
			_expect(player._is_viewmodel_mirrored() == not hand, wid + " native handedness")
		GameData.right_hand = true
		if _capture:
			for clip in ["idle", "shoot1", "reload", "inspect", "inspect_2", "add_silencer", "pullpin", "throw", "underhand", "pressbutton"]:
				if not anim.has_animation(clip):
					continue
				player.play_viewmodel_sequence([clip])
				anim.seek(anim.get_animation(clip).length * (0.45 if clip != "shoot1" else 0.12), true)
				await _save(wid + "_" + clip)
		# Sport geometry must receive the same native animation without replacement.
		GameData.select_glove("amphibious")
		player._rebuild_viewmodel(wid)
		player._play_idle_viewmodel()
		_expect(player._vm_anim != null, wid + " native rig supports original Sport geometry")
		GameData.select_glove("classic")
	_expect(source_clips > 280, "All available source clips counted: " + str(source_clips))
	world.queue_free()
	AudioManager.stop_all()
	await get_tree().process_frame
	print("[NATIVE GUN TEST] %s: %d checks, %d source clips, 42 rigs" % ["PASS" if _failures.is_empty() else "FAIL", _checks, source_clips])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _save(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(_output)
	get_tree().paused = true
	for frame in range(3):
		await get_tree().process_frame
		RenderingServer.force_draw(false)
	var image := get_viewport().get_texture().get_image()
	_expect(image != null and not image.is_empty(), "Framebuffer " + name)
	if image != null and not image.is_empty():
		image.save_png(_output.path_join(name + ".png"))
		image.resize(480,270,Image.INTERPOLATE_LANCZOS)
		image.save_jpg(_output.path_join(name + ".jpg"),0.35)
	get_tree().paused = false
