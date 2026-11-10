class_name ModernAgentPose
extends RefCounted
## Original runtime bridge: native body-only clips; gameplay physics owns motion.
static var sockets: Dictionary = {}
var clock := 0.0
var action := ""
var action_time := 0.0
var action_weapon := ""
var death_time := 0.0
var selected_gait := "idle_rifle"

static func is_modern(skeleton: Skeleton3D) -> bool:
	return skeleton != null and skeleton.find_bone("root_motion") >= 0 and skeleton.find_bone("hand_R") >= 0

static func role(team: String) -> String:
	return "sas" if team == "CT" else "phoenix"

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

func trigger(actor, kind: String) -> void:
	if not actor.is_alive:
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
		# Upstream has procedural ragdolls, not death GLB clips. This original,
		# bounded fall freezes the live pose and settles with existing corpse physics.
		death_time = minf(1.0, death_time + delta / 0.8)
		var fall := smoothstep(0.0, 1.0, death_time)
		for i in mini(rig.get_bone_count(), actor._death_from_pos.size()):
			rig.set_bone_pose_position(i, actor._death_from_pos[i])
			rig.set_bone_pose_rotation(i, actor._death_from_rot[i])
		actor._body_root.rotation = Vector3(PI * 0.5 * fall, actor.look_yaw, 0)
		actor._body_root.position = Vector3(0, 0.23 * fall, 0)
		return
	death_time = 0.0
	clock += delta
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
	elif actor.on_ladder or not actor.is_on_floor():
		selected_gait = "inair_stand_" + family
	elif speed > 0.3:
		selected_gait = ("run_" if speed > 4 else "walk_") + direction + "_" + family
		rate = clampf(speed / (6.5 if speed > 4 else 3.4), 0.5, 1.5)
	if not actor._anim_res_map.has(selected_gait):
		selected_gait = "idle_rifle"
	var clip: Animation = actor._anim_res_map[selected_gait]
	actor._apply_anim_layer(selected_gait, fposmod(clock * rate, maxf(0.01, clip.length)), 2)
	var clips: Dictionary = table(role(actor.team), wid).get("clips", {})
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
				actor._apply_anim_layer(key, minf(action_time, active_clip.length), 1, minf(1.0, action_time / 0.035))
				if action_time >= active_clip.length:
					action = ""
			else:
				action = ""
	var spine := rig.find_bone("spine_2")
	if spine >= 0:
		var parent := rig.get_bone_parent(spine)
		var parent_world := rig.global_basis * rig.get_bone_global_pose(parent).basis
		var spine_world := rig.global_basis * rig.get_bone_global_pose(spine).basis
		var right := Basis(Vector3.UP, actor.look_yaw).x
		var pitch := clampf(actor.look_pitch * 0.7 + actor._tp_recoil_pitch, -0.75, 0.75)
		var aimed := Basis(right, pitch) * spine_world
		rig.set_bone_pose_rotation(spine, (parent_world.inverse() * aimed).orthonormalized().get_rotation_quaternion())
	actor._body_root.rotation = Vector3(0, actor.look_yaw, 0)
	actor._body_root.position = actor.get_visual_world_pos() - actor.global_position
