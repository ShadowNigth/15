class_name KillContext
extends RefCounted
## Immutable trigger-time facts; ray-local smoke/penetration are accumulated separately.
const FLAGS := ["headshot", "through_smoke", "no_scope", "attacker_blind", "penetration"]
const BADGES := {
	"headshot": ["headshot", "HEADSHOT", "Disparo en la cabeza"],
	"through_smoke": ["smoke", "SMOKE", "A traves del humo"],
	"no_scope": ["noscope", "NO SCOPE", "Sin mira telescopica"],
	"attacker_blind": ["blind", "BLIND", "Atacante cegado"],
	"penetration": ["penetrate", "WALLBANG", "A traves de una pared"]
}

static func capture(attacker: Node, spec: Dictionary, zoom: int) -> Dictionary:
	var result := {"no_scope": bool(spec.get("sniper_scope", false)) and zoom < 0,
		"attacker_blind": attacker is CSActor and (attacker as CSActor).flash_alpha > 0.2,
		"through_smoke": false, "penetration": false}
	var clouds: Array[Dictionary] = []
	for cloud in RoundManager.smoke_volumes:
		if not is_instance_valid(cloud) or not cloud is SmokeCloudVolume:
			continue
		var positions := PackedVector3Array()
		var opacity := PackedFloat32Array()
		for i in range(cloud._v_count):
			var alpha: float = cloud.voxel_opacity(i)
			if alpha > 0.008:
				positions.append(cloud.global_position + cloud._v_pos[i])
				opacity.append(alpha)
		clouds.append({"positions": positions, "opacity": opacity})
	result["_smoke"] = clouds
	return result

static func crosses_smoke(snapshot: Dictionary, a: Vector3, b: Vector3) -> bool:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.0001:
		return false
	for cloud in snapshot.get("_smoke", []):
		var depth := 0.0
		var positions: PackedVector3Array = cloud["positions"]
		var opacity: PackedFloat32Array = cloud["opacity"]
		for i in range(positions.size()):
			var t := clampf((positions[i] - a).dot(ab) / length_sq, 0.0, 1.0)
			var distance := positions[i].distance_to(a + ab * t)
			if distance < 1.75:
				depth += (1.0 - distance / 1.75) * opacity[i]
				if depth >= 1.32:
					return true
	return false

static func confirmed(snapshot: Dictionary, headshot: bool) -> Dictionary:
	var result := {}
	for flag in FLAGS:
		result[flag] = bool(snapshot.get(flag, false))
	result["headshot"] = headshot
	return result

static func icon(flag: String) -> Texture2D:
	if not BADGES.has(flag):
		return null
	return GameData.get_texture("res://assets/polish/kill_%s.png" % BADGES[flag][0])
