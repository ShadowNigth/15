extends Node3D
var checks: int = 0
var failures: int = 0
func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[UTILITY PROPAGATION] " + label)

func block(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(7771)
	RoundManager.set_process(false)
	RoundManager.actors.clear()
	RoundManager.smoke_volumes.clear()
	RoundManager.incendiary_areas.clear()
	block(Vector3(0, -0.25, 0), Vector3(40, 0.5, 40))
	block(Vector3(0, 3, 0), Vector3(0.3, 6, 30))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var fire := IncendiaryArea.new()
	add_child(fire)
	fire.position = Vector3(-2, 0.02, 0)
	fire.setup_fire(null, "molotov", 7771)
	for frame in range(110):
		await get_tree().physics_frame
	expect(fire._patches.size() > 5, "seeded fire genuinely expands")
	for patch in fire._patches:
		var point := fire.to_global(patch.pos as Vector3)
		expect(point.x < -0.14, "fire cannot cross solid wall")
		expect(absf(point.y) < 0.08, "patches follow supporting floor")
		var connected := (patch.pos as Vector3).length() < 0.1
		for other in fire._patches:
			if other != patch and (patch.pos as Vector3).distance_to(other.pos as Vector3) < 1.64:
				connected = true
		expect(connected, "fire patches remain connected, not isolated islands")
	expect(fire._project_candidate(Vector3.ZERO, Vector3(24, 0, 0)) == null, "unsupported candidates rejected")
	var cloud := SmokeCloudVolume.new()
	add_child(cloud)
	cloud.setup_cloud(fire.global_position)
	cloud.age = 2.0
	expect(cloud._v_count > 20, "smoke flood fill creates volume")
	for i in range(cloud._v_count):
		expect((cloud.global_position+cloud._v_pos[i]).x < 0.15, "smoke voxel centers do not cross wall")
	var before := cloud.get_density_at(cloud.global_position+Vector3.UP)
	expect(before > 0.24, "mature smoke has real density")
	fire._extinguish_smoked_patches()
	var extinguished := 0
	for patch in fire._patches:
		if patch.has("extinguished_at"):
			extinguished += 1
	expect(extinguished > 0, "visible dense smoke extinguishes actual fuel patches")
	cloud.apply_explosion_impulse(cloud.cloud_center, 5.0, 1.0)
	expect(cloud.get_density_at(cloud.global_position+Vector3.UP) <= before, "explosion carves smoke rather than increasing density")
	cloud.apply_bullet_wake(Vector3(-5, 1, 0), Vector3(5, 1, 0), 1.0)
	expect(cloud.get_density_at(Vector3(3, 1, 0)) == 0.0, "wake cannot create density through wall")
	# Exercise the real swept projectile, not a duplicate of the bounce formula.
	var grenade := GrenadeProjectile.new()
	add_child(grenade)
	grenade.position = Vector3(-0.55, 1.6, 6)
	grenade.setup_grenade("hegrenade", null, Vector3(9, 0, 0))
	grenade.fuse_left = 10.0
	for frame in range(5):
		await get_tree().physics_frame
	expect(grenade.velocity.x < 0, "wall bounce reverses incoming normal velocity")
	expect(grenade.global_position.x < -0.15, "sweep prevents wall tunneling")
	expect(grenade._bounces >= 1, "bounce passes through native impact/audio path")
	grenade.queue_free()
	fire.queue_free()
	cloud.queue_free()
	await get_tree().process_frame
	print("[UTILITY PROPAGATION] %s: %d checks, %d failures" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
