class_name HeldWeaponGrip
extends RefCounted
## Dedicated third-person props. Never changes viewmodels or dropped weapons.
static var database: Dictionary = {}

static func entry(wid: String) -> Dictionary:
	if database.is_empty():
		database = JSON.parse_string(FileAccess.get_file_as_string("res://data/held_weapon_grips.json"))
	var model := String(GameData.weapons.get(wid, {}).get("v_model", ""))
	return database.get("models", {}).get(model, {})

static func basis(rows: Array) -> Basis:
	return Basis(Vector3(rows[0][0], rows[1][0], rows[2][0]), Vector3(rows[0][1], rows[1][1], rows[2][1]), Vector3(rows[0][2], rows[1][2], rows[2][2]))

static func settings(avatar: String, wid: String) -> Dictionary:
	return entry(wid).get("agents", {}).get(avatar, {})

static func model(wid: String, side: String = "R") -> String:
	return String(entry(wid).get("parts", {}).get(side, {}).get("model", ""))

static func fit(prop: Node3D, avatar: String, wid: String, side: String = "R") -> void:
	var config: Dictionary = settings(avatar, wid).get(side, {})
	if config.has("basis"):
		prop.transform = Transform3D(basis(config.basis), Vector3.ZERO)

static func support(avatar: String, wid: String) -> Array:
	return settings(avatar, wid).get("support", [])
