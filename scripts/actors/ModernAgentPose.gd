class_name ModernAgentPose
extends RefCounted
## Original runtime bridge: native body-only clips; gameplay physics owns motion.
static var sockets: Dictionary = {}
static var animation_tables: Dictionary = {}
static var variant_libraries: Dictionary = {}
var _support_fit := ClassicPoseFit.new()
var clock := 0.0
var action := ""
var action_time := 0.0
var action_weapon := ""
var death_time := 0.0
var selected_gait := "idle_rifle"
var gait_phase := 0.0
var _last_gait := ""
var _blend_time := 1.0
var _blend_pos: Array[Vector3] = []
var _blend_rot: Array[Quaternion] = []
var reaction := ""
var reaction_time := 0.0
var _grounded := true
var _landing := 1.0

static func is_modern(skeleton: Skeleton3D) -> bool:
	return skeleton != null and skeleton.find_bone("root_motion") >= 0 and skeleton.find_bone("hand_R") >= 0

static func role(team: String, class_id: String = "") -> String:
	return String(GameData.modern_agents.get("classes", {}).get(class_id, "sas" if team == "CT" else "phoenix"))

static func prepare_model(model: Node3D, avatar: String) -> void:
	# Six small body files share the already-imported native motion resources.
	# Resolve tracks by bone name, never by SAS/Phoenix's bone indices.
	if avatar in ["sas", "phoenix"] or model.has_meta("modern_motion_ready"):
		return
	var definition: Dictionary = GameData.modern_agents.get("agents", {}).get(avatar, {})
	if definition.is_empty():
		return
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty() or not is_modern(skeletons[0]):
		return
	var skeleton := skeletons[0] as Skeleton3D
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var player := players[0] as AnimationPlayer if not players.is_empty() else AnimationPlayer.new()
	if player.get_parent() == null:
		model.add_child(player)
	player.active = false
	if not variant_libraries.has(avatar):
		var template_scene := GameData.get_model_scene("modern/" + String(definition.family))
		if template_scene == null:
			return
		var template := template_scene.instantiate()
		var sources := template.find_children("*", "AnimationPlayer", true, false)
		if sources.is_empty():
			template.free()
			return
		var source := sources[0] as AnimationPlayer
		var library := AnimationLibrary.new()
		var root := player.get_node(player.root_node)
		var path := String(root.get_path_to(skeleton))
		for key in source.get_animation_list():
			var clip := source.get_animation(key).duplicate() as Animation
			for index in range(clip.get_track_count() - 1, -1, -1):
				var bone := String(clip.track_get_path(index).get_concatenated_subnames())
				if skeleton.find_bone(bone) < 0:
					clip.remove_track(index)
				else:
					clip.track_set_path(index, NodePath(path + ":" + bone))
			library.add_animation(String(key), clip)
		variant_libraries[avatar] = library
		template.free()
	for key in player.get_animation_library_list():
		player.remove_animation_library(key)
	player.add_animation_library("", variant_libraries[avatar])
	model.set_meta("modern_motion_ready", true)

static func table(avatar: String, wid: String) -> Dictionary:
	if sockets.is_empty():
		sockets = JSON.parse_string(FileAccess.get_file_as_string("res://data/modern_agent_sockets.json"))
	return sockets.get(avatar, {}).get(wid, {})

static func socket_basis(avatar: String, wid: String) -> Basis:
	var rows: Array = table(avatar, wid).get("basis", [])
	if rows.size() != 3:
		return Basis.IDENTITY
	return Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2]))

static func fit_prop(prop: Node3D, avatar: String, wid: String) -> void:
	# Socket includes the inverse inch-root scale. Meshes and textures are untouched.
	prop.transform = Transform3D(socket_basis(avatar, wid).scaled(Vector3.ONE * GameData.get_world_model_scale(wid)), Vector3.ZERO)

static func fit_support(skeleton: Skeleton3D, fit: ClassicPoseFit, appearance: String, wid: String) -> void:
	if not ModernAgentPose.is_modern(skeleton) or int(GameData.weapons.get(wid, {}).get("slot", 0)) != 1:
		return
	var support: Array = ModernAgentPose.table(appearance, wid).get("support", [])
	if support.size() == 3:
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_R"))
		fit.fit_modern_support(skeleton, hand * Vector3(support[0], support[1], support[2]))
		var rotation: Array = ModernAgentPose.table(appearance, wid).get("support_rotation", [])
		if rotation.size() == 4:
			fit.orient_modern_wrist(skeleton, hand.basis.orthonormalized() * Basis(Quaternion(rotation[0], rotation[1], rotation[2], rotation[3])))

func trigger(actor, kind: String) -> void:
	if not actor.is_alive:
		return
	if kind in ["flinch_head", "flinch_gut"]:
		reaction = "head_flinch" if kind == "flinch_head" else "gut_flinch"
		reaction_time = 0.0
		return
	if kind not in ["shoot", "reload", "draw"]:
		return
	action = kind
	action_time = 0.0
	action_weapon = actor.weapon_ctrl.current_weapon_id

func tick(actor, delta: float) -> void:
	var rig: Skeleton3D = actor._skel
	if rig == null:
		return
	if not actor.is_alive:
		death_time += delta
		var key: String = actor._death_anim_key
		for i in mini(rig.get_bone_count(), actor._death_from_pos.size()):
			rig.set_bone_pose_position(i, actor._death_from_pos[i])
			rig.set_bone_pose_rotation(i, actor._death_from_rot[i])
		actor._body_root.rotation = Vector3(0, actor.look_yaw, 0)
		actor._body_root.position = Vector3.ZERO
		if actor._anim_res_map.has(key):
			var death_clip: Animation = actor._anim_res_map[key]
			actor._apply_anim_layer(key, minf(death_time, death_clip.length), 2, smoothstep(0.0, 0.16, death_time))
		# Keep limbs on the local corpse support plane; existing corpse physics
		# still handles gravity, slope support and world collision.
		var lowest := 0.0
		for name in ["pelvis", "head_0", "hand_L", "hand_R", "ankle_L", "ankle_R"]:
			var bone := rig.find_bone(name)
			if bone >= 0:
				var world := rig.global_transform * rig.get_bone_global_pose(bone).origin
				lowest = minf(lowest, world.y - actor.global_position.y - 0.035)
		actor._body_root.position.y -= lowest
		return
	death_time = 0.0
	_support_fit.restore()
	clock += delta
	var prior_pos: Array[Vector3] = []
	var prior_rot: Array[Quaternion] = []
	for bone in rig.get_bone_count():
		prior_pos.append(rig.get_bone_pose_position(bone))
		prior_rot.append(rig.get_bone_pose_rotation(bone))
	# Reset sparse channels so a previous reload cannot leak into a new weapon pose.
	rig.reset_bone_poses()
	var wid: String = actor.weapon_ctrl.current_weapon_id
	var spec: Dictionary = actor.weapon_ctrl.get_current_spec()
	var family := "knife" if int(spec.get("slot", 0)) == 3 else ("pistol" if int(spec.get("slot", 0)) == 2 else "rifle")
	if bool(spec.get("grenade", false)):
		family = "grenade"
	var horizontal := Vector3(actor.velocity.x, 0, actor.velocity.z)
	var speed := horizontal.length()
	var local := Basis(Vector3.UP, actor.look_yaw).inverse() * horizontal
	var direction := "n" if local.z < 0 else "s"
	if absf(local.x) > absf(local.z):
		direction = "e" if local.x > 0 else "w"
	selected_gait = "idle_" + family
	var rate := 1.0
	if actor.is_crouching:
		selected_gait = "crouch_" + direction + "_" + family if speed > 0.3 else "idle_crouch_" + family
		rate = clampf(speed / 2.5, 0.5, 1.5) if speed > 0.3 else 1.0
	elif actor.on_ladder:
		selected_gait = "walk_n_" + family
		rate = clampf(absf(actor.velocity.y) / 3.0, 0.0, 1.5)
	elif not actor.is_on_floor():
		selected_gait = ("jump_stand_" if actor.velocity.y > 0.4 else "inair_stand_") + family
	elif speed > 0.3:
		selected_gait = ("run_" if speed > 4 else "walk_") + direction + "_" + family
		rate = clampf(speed / (6.5 if speed > 4 else 3.4), 0.5, 1.5)
	if not actor._anim_res_map.has(selected_gait):
		selected_gait = "idle_rifle"
	var clip: Animation = actor._anim_res_map[selected_gait]
	if selected_gait != _last_gait:
		_blend_pos = prior_pos
		_blend_rot = prior_rot
		_blend_time = 0.0
		_last_gait = selected_gait
	gait_phase = fposmod(gait_phase + delta * rate / maxf(0.01, clip.length), 1.0)
	actor._apply_anim_layer(selected_gait, gait_phase * clip.length, 2)
	var clips: Dictionary = table(role(actor.team, actor.class_id), wid).get("clips", {})
	var hold: String = clips.get("idle_crouch" if actor.is_crouching else "idle", "idle_" + family)
	if actor._anim_res_map.has(hold):
		var held_clip: Animation = actor._anim_res_map[hold]
		actor._apply_anim_layer(hold, fposmod(clock, maxf(0.01, held_clip.length)), 1)
	if not action.is_empty():
		if action_weapon != wid or (action == "reload" and not actor.weapon_ctrl.is_reloading):
			action = ""
		else:
			var key: String = clips.get(action + ("_crouch" if actor.is_crouching else ""), clips.get(action, ""))
			if actor._anim_res_map.has(key):
				var active_clip: Animation = actor._anim_res_map[key]
				action_time += delta
				actor._apply_anim_layer(key, minf(action_time, active_clip.length), 1, minf(minf(1.0, action_time / 0.045), maxf(0.0, (active_clip.length - action_time) / 0.10)))
				if action_time >= active_clip.length:
					action = ""
			else:
				action = ""
	if not reaction.is_empty() and actor._anim_res_map.has(reaction):
		var react_clip: Animation = actor._anim_res_map[reaction]
		reaction_time += delta
		var weight := sin(PI * clampf(reaction_time / maxf(0.01, react_clip.length), 0, 1)) * 0.45
		actor._apply_anim_layer(reaction, reaction_time, 1, weight)
		if reaction_time >= react_clip.length:
			reaction = ""
	# Smooth changes of direction, stance and airborne state without restarting
	# the stride clock as speed changes. Never crossfade IK-corrected wrists.
	_blend_time += delta
	var blend := smoothstep(0.0, 0.16, _blend_time)
	if blend < 1.0 and _blend_pos.size() == rig.get_bone_count():
		for bone in rig.get_bone_count():
			rig.set_bone_pose_position(bone, _blend_pos[bone].lerp(rig.get_bone_pose_position(bone), blend))
			rig.set_bone_pose_rotation(bone, _blend_rot[bone].slerp(rig.get_bone_pose_rotation(bone), blend))
	var spine := rig.find_bone("spine_2")
	if spine >= 0:
		var parent := rig.get_bone_parent(spine)
		var parent_world := rig.global_basis * rig.get_bone_global_pose(parent).basis
		var spine_world := rig.global_basis * rig.get_bone_global_pose(spine).basis
		var right := Basis(Vector3.UP, actor.look_yaw).x
		var pitch := clampf(actor.look_pitch * 0.7 + actor._tp_recoil_pitch, -0.75, 0.75)
		var aimed := Basis(right, pitch) * spine_world
		rig.set_bone_pose_rotation(spine, (parent_world.inverse() * aimed).orthonormalized().get_rotation_quaternion())
	# The p_ meshes retain the established classic grip. Fit the support hand
	# to that grip, not to the differently proportioned source weapon. Reloads,
	# draws and one-handed tools retain their unpinned native animation.
	if int(spec.get("slot", 0)) == 1 and action in ["", "shoot"]:
		fit_support(rig, _support_fit, role(actor.team, actor.class_id), wid)
	actor._body_root.rotation = Vector3(0, actor.look_yaw, 0)
	actor._body_root.position = actor.get_visual_world_pos() - actor.global_position
	if actor.is_on_floor() and not _grounded:
		_landing = 0.0
	_grounded = actor.is_on_floor()
	_landing = minf(1.0, _landing + delta / 0.22)
	actor._body_root.position.y -= sin(_landing * PI) * 0.035
