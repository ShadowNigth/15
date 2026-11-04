class_name GameWorld
extends Node3D
## Main match coordinator for Counter-Strike 1.5 in Godot 4.
## Loads the BSP map, spawns Player + Bots + Hostages, wires HUD & VGUI menus, and runs rounds.

var map_data: Dictionary = {}
var map_runtime: Dictionary = {}
var bot_navigator: BotNavigator = null

var doors: Array = []
var breakables: Array = []
var ladders: Array[AABB] = []
var ladder_volumes: Array = []
var trigger_zones: Array = []
var bombsites: Array[AABB] = []
var buyzones: Array = []
var rescue_zones: Array[AABB] = []
var escape_zones: Array[AABB] = []

var player: PlayerController = null
var bots: Array[CSBot] = []

var hud: CSHud = null
var buy_menu: BuyMenu = null
var team_menu: TeamSelectMenu = null
var radio_menu: RadioMenu = null
var scoreboard: Scoreboard = null
var pause_menu: PauseMenu = null

var _match_started: bool = false
var _bot_name_cursor: int = 0


func _ready() -> void:
	var mname := GameData.selected_map
	map_data = GameData.load_map_data(mname)
	if map_data.is_empty():
		map_data = GameData.load_map_data("de_dust2")

	RoundManager.reset_match(map_data, self)

	# 1. Build 3D BSP Map + Baked Lightmaps + Interactive Brush Entities
	map_runtime = MapLoader.build_map(self, map_data)
	doors = map_runtime.get("doors", [])
	breakables = map_runtime.get("breakables", [])
	ladders.assign(map_runtime.get("ladders", []))
	ladder_volumes = map_runtime.get("ladder_volumes", [])
	trigger_zones = map_runtime.get("triggers", [])
	bombsites.assign(map_runtime.get("bombsites", []))
	buyzones = map_runtime.get("buyzones", [])
	rescue_zones.assign(map_runtime.get("rescue_zones", []))
	escape_zones.assign(map_runtime.get("escape_zones", []))

	# 2. Setup Bot A* Waypoint Graph
	bot_navigator = BotNavigator.new()
	bot_navigator.setup_from_map(map_data)

	# 3. Spawn Hostage NPCs on cs_* maps
	for hinfo in map_data.get("hostages", []):
		var h := HostageNPC.new()
		var p: Array = hinfo["pos"]
		h.spawn_pos = Vector3(float(p[0]), float(p[1]), float(p[2]))
		h.spawn_yaw = float(hinfo.get("yaw", 0.0))
		add_child(h)
		RoundManager.hostages.append(h)

	# 4. Create Human Player (initially waiting for Team Select)
	player = PlayerController.new()
	player.name = "LocalPlayer"
	player.money = GameData.start_money
	add_child(player)

	# Position overview camera until team chosen
	var cams: Array = map_data.get("cameras", [])
	if not cams.is_empty():
		var cp: Array = cams[0]["pos"]
		player.global_position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
		player.look_yaw = float(cams[0].get("yaw", 0.0))
	elif not map_data.get("ct_spawns", []).is_empty():
		var sp: Array = map_data["ct_spawns"][0]["pos"]
		player.global_position = Vector3(float(sp[0]), float(sp[1]) + 1.5, float(sp[2]))

	# 5. Instantiate HUD & VGUI Overlays
	hud = CSHud.new()
	add_child(hud)
	hud.bind_player(player)

	buy_menu = BuyMenu.new()
	add_child(buy_menu)

	team_menu = TeamSelectMenu.new()
	add_child(team_menu)
	team_menu.team_class_chosen.connect(_on_player_team_chosen)

	radio_menu = RadioMenu.new()
	add_child(radio_menu)

	scoreboard = Scoreboard.new()
	add_child(scoreboard)

	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.resume_requested.connect(func(): player.ui_blocking_input = false)
	pause_menu.change_team_requested.connect(func():
		player.ui_blocking_input = true
		team_menu.open_menu()
	)
	pause_menu.add_bot_requested.connect(_spawn_single_bot)
	pause_menu.restart_round_requested.connect(_restart_match)
	pause_menu.exit_to_main_menu_requested.connect(_return_to_main_menu)

	# Open Team Select VGUI on map entry just like Counter-Strike 1.5!
	player.ui_blocking_input = true
	team_menu.open_menu()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).physical_keycode
		if kc == KEY_ESCAPE:
			if buy_menu.is_open:
				buy_menu.close_menu()
			elif team_menu.is_open and _match_started:
				team_menu.close_menu()
				player.ui_blocking_input = false
			elif pause_menu.is_open:
				pause_menu.close_pause()
				player.ui_blocking_input = false
			else:
				player.ui_blocking_input = true
				pause_menu.open_pause()
			return

	if pause_menu.is_open or team_menu.is_open:
		return

	if event.is_action_pressed("buy_menu"):
		if buy_menu.is_open:
			buy_menu.close_menu()
		else:
			buy_menu.open_menu(player)
	elif event.is_action_pressed("team_menu"):
		player.ui_blocking_input = true
		team_menu.open_menu()
	elif event.is_action_pressed("radio_1"):
		radio_menu.toggle_radio("radio1", player)
	elif event.is_action_pressed("radio_2"):
		radio_menu.toggle_radio("radio2", player)
	elif event.is_action_pressed("radio_3"):
		radio_menu.toggle_radio("radio3", player)


func _on_player_team_chosen(tm: String, cid: String) -> void:
	player.ui_blocking_input = false
	player.set_team_and_class(tm, cid)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if not _match_started:
		_match_started = true
		_populate_initial_bots(tm)
		RoundManager.start_new_round()
	elif RoundManager.state == RoundManager.State.FREEZE:
		# Spawn immediately during freeze time
		var sp := _pick_spawn_for_team(tm, 0)
		player.spawn_for_round(sp["pos"], sp["yaw"], true)


func _populate_initial_bots(human_team: String) -> void:
	var total_bots := GameData.bot_count
	# Balance teams (e.g. if human is CT and bot_count=9 -> 4 CT bots + 5 T bots = 5v5!)
	var enemy_team := "T" if human_team == "CT" else "CT"
	var enemy_count := int(ceil(float(total_bots) * 0.5))
	var ally_count := total_bots - enemy_count

	for _i in range(enemy_count):
		_spawn_single_bot(enemy_team)
	for _j in range(ally_count):
		_spawn_single_bot(human_team)


func _spawn_single_bot(tm: String) -> void:
	var bot := CSBot.new()
	var bname: String = CSBot.BOT_NAMES[_bot_name_cursor % CSBot.BOT_NAMES.size()]
	_bot_name_cursor += 1
	bot.actor_name = bname
	bot.skill_level = GameData.bot_difficulty
	bot.money = GameData.start_money

	var clist: Array = GameData.classes.get(tm, [])
	var cid := "urban" if tm == "CT" else "terror"
	if not clist.is_empty():
		cid = String(clist[randi() % clist.size()]["id"])

	add_child(bot)
	bot.set_team_and_class(tm, cid)
	bots.append(bot)


func prepare_round_entities(reset_all_gear: bool) -> void:
	ImpactEffects.clear_decals()
	if bot_navigator != null:
		bot_navigator.reset_round_weights()

	# 1. Clear dropped weapons and planted C4
	for d in RoundManager.dropped_items:
		if is_instance_valid(d):
			d.queue_free()
	RoundManager.dropped_items.clear()

	if is_instance_valid(RoundManager.planted_c4):
		RoundManager.planted_c4.queue_free()
		RoundManager.planted_c4 = null

	# 2. Reset doors, breakables, and hostages
	for dr in doors:
		if is_instance_valid(dr) and dr.has_method("reset_for_round"):
			dr.reset_for_round()
	for br in breakables:
		if is_instance_valid(br) and br.has_method("reset_for_round"):
			br.reset_for_round()
	for h in RoundManager.hostages:
		if is_instance_valid(h) and h.has_method("reset_for_round"):
			h.reset_for_round()

	# 3. Reset player camera top_level in case they were spectating
	player.camera.top_level = false
	player.camera.position = Vector3(0.0, 1.85, 0.0)

	# 4. Spawn all CT and T actors across distinct BSP spawn points
	var ct_idx := 0
	var t_idx := 0
	var ct_actors: Array[CSActor] = []
	var t_actors: Array[CSActor] = []

	for a in RoundManager.actors:
		if not is_instance_valid(a):
			continue
		var actor := a as CSActor
		actor.is_vip = false
		if reset_all_gear:
			actor.money = GameData.start_money
		if actor.team == "CT":
			ct_actors.append(actor)
		else:
			t_actors.append(actor)

	# Designate 1 CT as VIP on as_* Assassination maps
	if String(map_data.get("mode", "")) == "as" and not ct_actors.is_empty():
		var vip_actor: CSActor = ct_actors[randi() % ct_actors.size()]
		vip_actor.is_vip = true

	for ca in ct_actors:
		var sp := _pick_spawn_for_team("VIP" if ca.is_vip else "CT", ct_idx)
		ct_idx += 1
		ca.spawn_for_round(sp["pos"], sp["yaw"], reset_all_gear)

	for ta in t_actors:
		var sp2 := _pick_spawn_for_team("T", t_idx)
		t_idx += 1
		ta.spawn_for_round(sp2["pos"], sp2["yaw"], reset_all_gear)

	# 5. Assign exactly one C4 on de_* maps. Survivors retain their other
	# equipment, so remove every carried bomb before the new random assignment.
	# Otherwise a surviving carrier plus the new carrier creates two bombs.
	if String(map_data.get("mode", "de")) == "de" and not t_actors.is_empty():
		for raw in t_actors:
			var t := raw as CSActor
			t.weapon_ctrl.slots[5] = ""
			if t.weapon_ctrl.current_weapon_id == "c4":
				if not t.weapon_ctrl.equip_slot(2):
					t.weapon_ctrl.equip_slot(3)
		var carrier: CSActor = t_actors[randi() % t_actors.size()]
		carrier.weapon_ctrl.give_weapon("c4", 1, 0)
		if carrier.is_human:
			RoundManager.center_message.emit("You are carrying the C4! Plant it at Bombsite A or B.", 3.2)


func _pick_spawn_for_team(tm: String, index: int) -> Dictionary:
	var list: Array = []
	if tm == "VIP" and not map_data.get("vip_spawns", []).is_empty():
		list = map_data["vip_spawns"]
	elif tm in ["CT", "VIP"]:
		list = map_data.get("ct_spawns", [])
	else:
		list = map_data.get("t_spawns", [])

	if list.is_empty():
		return {"pos": Vector3(float(index) * 1.5, 2.0, 0.0), "yaw": 0.0}

	var entry: Dictionary = list[index % list.size()]
	var pa: Array = entry["pos"]
	return {
		"pos": Vector3(float(pa[0]), float(pa[1]), float(pa[2])),
		"yaw": float(entry.get("yaw", 0.0)),
	}


func _restart_match() -> void:
	RoundManager.ct_score = 0
	RoundManager.t_score = 0
	RoundManager.round_number = 0
	for a in RoundManager.actors:
		if is_instance_valid(a):
			a.set("kills", 0)
			a.set("deaths", 0)
	RoundManager.start_new_round()


func _return_to_main_menu() -> void:
	RoundManager.state = RoundManager.State.WAITING
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")


# --- SPATIAL ZONE QUERIES ---

func is_in_buyzone(pos: Vector3, tm: String) -> bool:
	var t_code := "2" if tm == "CT" else "1"
	for bz in buyzones:
		var aabb: AABB = bz["aabb"]
		var zt := String(bz["team"])
		if (zt == "0" or zt == t_code) and aabb.has_point(pos):
			return true
	return false


func is_in_bombsite(pos: Vector3) -> bool:
	for b in bombsites:
		if b.has_point(pos):
			return true
	return false


func is_in_rescue_zone(pos: Vector3) -> bool:
	for r in rescue_zones:
		if r.has_point(pos):
			return true
	return false


func is_in_escape_zone(pos: Vector3) -> bool:
	for e in escape_zones:
		if e.has_point(pos):
			return true
	return false


func is_on_ladder(pos: Vector3) -> bool:
	for l in ladders:
		if l.has_point(pos):
			return true
	return false


func get_ladder_info(feet_pos: Vector3, actor_height: float = 1.75) -> Dictionary:
	var y_lo: float = feet_pos.y + 0.08
	var y_hi: float = feet_pos.y + actor_height
	for lv_raw in ladder_volumes:
		var lv: Dictionary = lv_raw
		var cb: AABB = lv["climb_aabb"]
		if feet_pos.x < cb.position.x or feet_pos.x > cb.end.x:
			continue
		if feet_pos.z < cb.position.z or feet_pos.z > cb.end.z:
			continue
		if y_hi < cb.position.y or y_lo > cb.end.y:
			continue

		var raw_box: AABB = lv["raw_aabb"]
		var raw_c: Vector3 = raw_box.get_center()
		if not bool(lv["resolved"]) and get_world_3d() != null:
			var space := get_world_3d().direct_space_state
			if space != null:
				var ax: Vector3 = lv["axis"]
				var q_pos := PhysicsRayQueryParameters3D.create(raw_c, raw_c + ax * 0.78)
				q_pos.collision_mask = 1
				var q_neg := PhysicsRayQueryParameters3D.create(raw_c, raw_c - ax * 0.78)
				q_neg.collision_mask = 1
				var hit_pos_side: bool = not space.intersect_ray(q_pos).is_empty()
				var hit_neg_side: bool = not space.intersect_ray(q_neg).is_empty()
				if hit_pos_side and not hit_neg_side:
					lv["normal"] = -ax
				elif hit_neg_side and not hit_pos_side:
					lv["normal"] = ax
				lv["resolved"] = true

		var nrm: Vector3 = lv["normal"]
		if nrm.length_squared() < 0.01:
			var ax2: Vector3 = lv["axis"]
			var side_dot: float = (feet_pos - raw_c).dot(ax2)
			nrm = ax2 if side_dot >= 0.0 else -ax2

		return {
			"on_ladder": true,
			"normal": nrm,
			"top_y": raw_box.end.y,
			"bottom_y": raw_box.position.y,
			"center": raw_c,
		}
	return {"on_ladder": false}


func trigger_map_target(target_id: String, actor: Node3D = null) -> bool:
	if target_id.is_empty():
		return false
	var fired := false
	for dr in doors:
		if is_instance_valid(dr) and (dr as BSPDoor).target_name == target_id:
			(dr as BSPDoor).force_open(actor)
			fired = true
	return fired


func _physics_process(_delta: float) -> void:
	if trigger_zones.is_empty():
		return
	for tz_raw in trigger_zones:
		var tz: Dictionary = tz_raw
		var box: AABB = tz["aabb"]
		var tgt: String = tz["target"]
		for a in RoundManager.actors:
			if is_instance_valid(a) and a.is_alive:
				if box.has_point(a.global_position + Vector3(0.0, 0.9, 0.0)):
					trigger_map_target(tgt, a)
					break

