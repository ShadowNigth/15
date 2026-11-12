class_name BallisticModel
extends RefCounted
## Godot adaptation, not a claim to reproduce the Source 2 simulation.
const MATERIALS := {"W": [0.80, 0.75], "Y": [0.90, 0.88], "G": [0.18, 0.45], "M": [0.12, 0.35], "V": [0.15, 0.45], "D": [0.25, 0.45], "C": [0.18, 0.40], "T": [0.16, 0.42]}

static func profile(material: String, ammo: String) -> Vector2:
	var values: Array = MATERIALS.get(material, [0.16, 0.40])
	var power := 1.0
	if ammo in ["338magnum", "762nato"]:
		power = 1.25
	elif ammo in ["9mm", "45acp", "57mm", "357sig"]:
		power = 0.55
	elif ammo == "buckshot":
		power = 0.0
	return Vector2(float(values[0]) * power, float(values[1]))

static func find_exit(space: PhysicsDirectSpaceState3D, entry: Dictionary, direction: Vector3, depth: float) -> Dictionary:
	# First front-facing exit on the SAME collision object. Reverse probes must
	# not hit an entry backface, an unrelated wall, or travel backwards.
	var start: Vector3 = entry["position"]
	var steps := mini(48, maxi(1, ceili(depth / 0.025)))
	for index in range(1, steps + 1):
		var distance := minf(depth, float(index) * depth / float(steps))
		var query := PhysicsRayQueryParameters3D.create(start + direction * distance, start + direction * 0.001, 1)
		query.hit_back_faces = false
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit["rid"] != entry["rid"]:
			continue
		var advance: float = (hit["position"] - start).dot(direction)
		if advance > 0.003 and advance <= depth and (hit["normal"] as Vector3).dot(direction) > 0.15:
			hit["thickness"] = advance
			return hit
	return {}

static func damage_retention(profile_value: Vector2, thickness: float) -> float:
	return clampf(profile_value.y * (1.0 - 0.65 * thickness / maxf(0.001, profile_value.x)), 0.05, 0.95)

static func spray_target(spec: Dictionary, shot: int, alternate: bool = false) -> Vector2:
	if shot <= 0: return Vector2.ZERO
	var up := float(spec.get("alt_recoil", spec.get("recoil_up", 1.8))) if alternate else float(spec.get("recoil_up", 1.8))
	var side := float(spec.get("recoil_lat", 0.5))
	var key := String(spec.get("id", ""))
	var knots := [0.0, 0.08, -0.35, 1.5, -1.6, 1.8, -0.7]
	if key == "ak47": knots = [0.0, 0.1, -0.3, 2.0, -2.0, 2.5, -1.2]
	elif key in ["m4a1", "m4a4", "aug", "sg552"]: knots = [0.0, 0.05, 0.3, -1.3, 1.8, -1.0, 0.8]
	var times := [0, 3, 7, 12, 17, 23, 30]
	var yaw := 0.0
	for index in range(1, times.size()):
		if shot <= times[index]:
			yaw = lerpf(knots[index - 1], knots[index], float(shot - times[index - 1]) / float(times[index] - times[index - 1]))
			break
	if shot > 30:
		yaw = float(knots[-1]) + 0.8 * sin(float(shot - 30) * 0.4)
	var pitch := up * 3.0 * (1.0 - exp(-float(shot) * 0.18))
	return Vector2(pitch, yaw * side)

static func spray_kick(spec: Dictionary, shot: int, crouching: bool, alternate: bool = false) -> Vector2:
	var factor := 0.80 if crouching else 1.0
	return (spray_target(spec, shot, alternate) - spray_target(spec, shot - 1, alternate)) * factor
