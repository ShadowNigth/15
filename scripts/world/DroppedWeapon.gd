class_name DroppedWeapon
extends Node3D
## Physical dropped weapon / C4 backpack / Defuse thighpack on the ground.

var item_id: String = ""  # weapon_id or "defuser"
var clip_ammo: int = 0
var reserve_ammo: int = 0
var silenced: bool = false
var _vel: Vector3 = Vector3.ZERO
var _pickup_cooldown: float = 0.55
var _settled: bool = false


func setup_drop(id: String, clip: int, reserve: int, throw_vel: Vector3, is_silenced: bool = false) -> void:
	item_id = id
	clip_ammo = clip
	reserve_ammo = reserve
	silenced = is_silenced
	_vel = throw_vel

	var mdl_name := "w_ak47"
	if id == "defuser":
		mdl_name = "w_thighpack"
	elif id == "c4":
		mdl_name = "w_backpack"
	elif GameData.weapons.has(id):
		mdl_name = String(GameData.weapons[id].get("w_model", "w_" + id))

	var sc := GameData.get_model_scene("weapons/" + mdl_name)
	if sc:
		var inst := sc.instantiate()
		add_child(inst)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.12, 0.18)
		mi.mesh = bm
		add_child(mi)


func _physics_process(delta: float) -> void:
	if _pickup_cooldown > 0.0:
		_pickup_cooldown -= delta

	if not _settled:
		_vel.y -= 18.0 * delta
		var from := global_position
		var to := from + _vel * delta
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.15, 0), to)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit:
			global_position = hit["position"] + Vector3(0, 0.04, 0)
			_vel = Vector3.ZERO
			_settled = true
		else:
			global_position = to

	if _pickup_cooldown <= 0.0:
		_check_actor_pickup()


func _check_actor_pickup() -> void:
	for a in RoundManager.actors:
		if not is_instance_valid(a) or not bool(a.get("is_alive")):
			continue
		if a.global_position.distance_squared_to(global_position) > 1.35:
			continue
		if a.has_method("try_pickup_dropped") and a.try_pickup_dropped(self):
			RoundManager.dropped_items.erase(self)
			queue_free()
			return
