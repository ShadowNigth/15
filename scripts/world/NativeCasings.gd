class_name NativeCasings
extends Node
## Cosmetic event queue: source times, late-bound moving port, no gameplay timers.
const MAX_PENDING := 64
var pending: Array[Dictionary] = []
var emitted_count: int = 0

static func events_for(wid: String, clip: String) -> Array:
	var route: Dictionary = GameData.native_casings.get("weapons", {}).get(wid, {})
	return route.get("clips", {}).get(clip, [])

static func frame_from_rows(rows: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2])), Vector3(rows[0][3], rows[1][3], rows[2][3]))

func queue_shot(owner_actor: Node3D, wid: String, clip: String) -> void:
	if not GameData.native_casings_enabled:
		return
	for raw in events_for(wid, clip):
		if pending.size() >= MAX_PENDING:
			pending.pop_front()
		pending.append({"actor": weakref(owner_actor), "weapon": wid, "epoch": owner_actor.weapon_ctrl.casing_epoch, "remaining": float(raw["at"]), "cue": raw})

func clear_all() -> void:
	pending.clear()
	var runner := get_parent().get_node_or_null("__ShellRunner")
	if runner != null:
		runner.clear_all()

func _physics_process(delta: float) -> void:
	for i in range(pending.size() - 1, -1, -1):
		var item := pending[i]
		var a: Node3D = item["actor"].get_ref()
		if not GameData.native_casings_enabled or not is_instance_valid(a) or not a.is_alive or a.weapon_ctrl.current_weapon_id != item["weapon"] or a.weapon_ctrl.casing_epoch != item["epoch"]:
			pending.remove_at(i)
			continue
		item["remaining"] = float(item["remaining"]) - delta
		if float(item["remaining"]) > 0.00001:
			continue
		var cue: Dictionary = item["cue"]
		var frame: Transform3D
		if a.has_method("native_casing_frame"):
			frame = a.native_casing_frame(cue)
		else:
			# Third-person GoldSrc actors have different skeletons. Source cue timing
			# and shell are exact; NPC port placement is an explicit adaptation.
			var aim: Basis = a.get_aim_basis(Vector2.ZERO)
			frame = Transform3D(aim.scaled(Vector3.ONE * 0.0254), a.get_eye_position() - aim.z * 0.38 + aim.x * 0.18 - aim.y * 0.12)
		var lo: Array = cue["speed_min"]
		var hi: Array = cue["speed_max"]
		var speed := Vector3(randf_range(minf(lo[0], hi[0]), maxf(lo[0], hi[0])), randf_range(minf(lo[1], hi[1]), maxf(lo[1], hi[1])), randf_range(minf(lo[2], hi[2]), maxf(lo[2], hi[2])))
		var launch := frame.basis * speed + a.velocity * 0.42
		ImpactEffects.spawn_physical_shell(get_parent(), "native/casing_" + String(cue["model"]), frame.origin, launch)
		emitted_count += 1
		pending.remove_at(i)
