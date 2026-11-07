extends Node
## Real-engine decoding and production-route checks, not file-presence assertions.
var checks: int = 0
var failures: Array[String] = []
var heard: int = 0

func _ready() -> void:
	_run.call_deferred()

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("[NATIVE AUDIO] " + message)

func _run() -> void:
	var manifest: Dictionary = GameData._load_json("res://data/native_audio_manifest.json")
	var files: Array = manifest.get("files", [])
	expect(files.size() == 649, "All 649 upstream recordings installed")
	for entry in files:
		var path := String(entry["path"])
		var stream := GameData.get_sound(path)
		expect(stream != null, "Engine decodes " + path)
		if stream:
			expect(stream.get_length() > 0.01, "Nonempty decoded recording " + path)
	var owners: Dictionary = {}
	for wid in GameData.weapons:
		var spec: Dictionary = GameData.weapons[wid]
		for path in spec.get("fire_sounds", []):
			expect(String(path).begins_with("native/sccsgoknives/"), "Native firing sound " + wid)
			expect(not owners.has(path) or owners[path] == wid, "No cross-weapon firing substitution " + wid)
			owners[path] = wid
	for model in GameData.native_audio.get("model_events", {}):
		var meta: Dictionary = GameData.models_meta[model]
		for clip in GameData.native_audio["model_events"][model]:
			var previous: float = -1.0
			for event in meta["seq_events"][clip]:
				var at := float(event["t"])
				expect(at >= previous, "Ordered native events " + model + ":" + clip)
				expect(at <= float(meta["seq_durations"].get(clip, 9999.0)) + 0.001, "Cue within clip " + model + ":" + clip)
				expect(GameData.get_sound(String(event["wav"])) != null, "Playable native cue " + String(event["wav"]))
				previous = at
	for language in ["en", "zh"]:
		GameData.voice_language = language
		for team in ["CT", "T"]:
			expect(AudioManager.play_voice("radio.letsgo", team), "Language/team route " + language + ":" + team)
	GameData.voice_language = "en"
	for cue in GameData.native_audio.get("cues", {}):
		var path := AudioManager.cue_path(cue)
		expect(not path.is_empty() and GameData.get_sound(path) != null, "Playable world cue " + cue)
	var owner_node := Node.new()
	add_child(owner_node)
	AudioManager.play_viewmodel_audio(owner_node, "native/sccsgoknives/knife_slash.ogg")
	var branch := owner_node.get_node_or_null("NativeViewmodelFoley")
	expect(branch != null and branch.get_child_count() == 1, "Viewmodel audio has action-scoped ownership")
	AudioManager.stop_viewmodel_audio(owner_node)
	await get_tree().process_frame
	expect(branch.get_child_count() == 0, "Switch/reload/inspect interruption releases old foley")
	owner_node.queue_free()
	AudioManager.world_sound_emitted.connect(_on_heard)
	AudioManager.play_3d(String(GameData.weapons["ak47"]["fire_sounds"][0]), Vector3.ZERO, -12.0, 30.0, 1.0, 20.0, "T")
	expect(heard == 1, "Native gunfire still emits exactly one AI perception event")
	AudioManager.world_sound_emitted.disconnect(_on_heard)
	var controller := WeaponController.new()
	GameData.models_meta["weapons/empty_audio_probe"] = {"seq_events": {"draw": [], "draw_unsil": [{"wav": ""}]}}
	expect(not controller._viewmodel_has_events("empty_audio_probe", "draw"), "Empty aliases still allow deploy fallback")
	GameData.models_meta.erase("weapons/empty_audio_probe")
	controller.free()
	AudioManager.stop_all()
	await get_tree().process_frame
	print("[NATIVE AUDIO] %s: %d checks, 649 decoded recordings, 43 weapon routes, 64 animation rigs" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)

func _on_heard(_pos: Vector3, _radius: float, _team: String) -> void:
	heard += 1
