extends Node3D
var checks := 0
var failures := 0
var bot_navigator: BotNavigator = null
var camera: Camera3D
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[DROP RAGDOLL] " + message)
func _ready() -> void:
	_run.call_deferred()
func capture(label: String) -> void:
	DirAccess.make_dir_recursive_absolute("/tmp/modern-captures")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/modern-captures/"+label+".png")
func box(pos: Vector3, size: Vector3, angle: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	body.rotation.z = angle
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	body.add_child(mi)
	add_child(body)
func check_drop(wid: String) -> void:
	var drop := DroppedWeapon.new()
	add_child(drop)
	drop.setup_drop(wid,17,51,Vector3.ZERO)
	drop.set_physics_process(false)
	drop.position = Vector3(0,3,0)
	drop._pitch = 0.35
	drop._yaw = 0.8
	drop._roll = -0.2
	drop._sync_visual_and_hitbox()
	expect(drop._hit_col.shape is ConcavePolygonShape3D, "surface collider " + wid)
	if drop._hit_col.shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = drop._hit_col.shape.get_faces()
		var visual := PackedVector3Array()
		for child in drop._visual_root.get_children():
			drop._collect_mesh_faces(child,Transform3D.IDENTITY,visual)
		expect(faces.size()==visual.size() and faces.size()>2,"triangle count " + wid)
		var error := 0.0
		for i in mini(faces.size(),visual.size()):
			error = maxf(error,faces[i].distance_to(visual[i]))
		expect(error<0.00001,"mesh collision alignment " + wid + str(error))
		expect(drop._visual_root.basis.is_equal_approx(drop._hit_col.basis),"shared rotation " + wid)
		# Flush the StaticBody transform before querying the physics broadphase.
		drop.force_update_transform()
		drop._hit_col.force_update_transform()
		await get_tree().physics_frame
		await get_tree().physics_frame
		# Avoid sub-millimetre decorative triangles: a ray through their exact
		# centroid is sensitive to physics float tolerances, not hitbox alignment.
		var triangle := 0
		var largest := 0.0
		for i in range(0,faces.size(),3):
			var area := (faces[i+1]-faces[i]).cross(faces[i+2]-faces[i]).length_squared()
			if area > largest:
				largest = area
				triangle = i
		var a := drop._hit_col.global_transform * faces[triangle]
		var b := drop._hit_col.global_transform * faces[triangle+1]
		var c := drop._hit_col.global_transform * faces[triangle+2]
		var n := (b-a).cross(c-a).normalized()
		if n.length()>0.5:
			var center := (a+b+c)/3.0
			var query := PhysicsRayQueryParameters3D.create(center+n*0.2,center-n*0.2,4)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			expect(not hit.is_empty() and hit.collider==drop,"ray hits model surface " + wid)
	drop.queue_free()
	await get_tree().physics_frame
func capture_drop_surfaces() -> void:
	var drops: Array[DroppedWeapon] = []
	var names := ["ak47", "glock18", "knife", "hegrenade"]
	for i in names.size():
		var drop := DroppedWeapon.new()
		add_child(drop)
		drop.setup_drop(names[i],0,0,Vector3.ZERO)
		drop.set_physics_process(false)
		drop.position = Vector3(-0.8 if i%2==0 else 0.8,drop._half_extents.y+0.02,4.15 if i<2 else 2.85)
		drop._pitch = 0.0
		drop._yaw = 0.3
		drop._roll = 0.0
		drop._sync_visual_and_hitbox()
		var wire := ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(0.15,1.0,0.5)
		wire.surface_begin(Mesh.PRIMITIVE_LINES,material)
		var faces: PackedVector3Array = drop._hit_col.shape.get_faces()
		for n in range(0,faces.size(),3):
			for pair in [[0,1],[1,2],[2,0]]:
				wire.surface_add_vertex(faces[n+pair[0]]+Vector3.UP*0.001)
				wire.surface_add_vertex(faces[n+pair[1]]+Vector3.UP*0.001)
		wire.surface_end()
		var overlay := MeshInstance3D.new()
		overlay.mesh = wire
		drop._visual_root.add_child(overlay)
		drops.append(drop)
	camera.look_at_from_position(Vector3(2.1,2.7,6.7),Vector3(0,0.1,3.5))
	await get_tree().process_frame
	await capture("drop_surface_collisions")
	for drop in drops: drop.queue_free()
	await get_tree().process_frame
	camera.look_at_from_position(Vector3(4,3.3,5),Vector3(0,0.5,0))


func actor_at(cid: String, pos: Vector3, classic: bool = false) -> CSBot:
	var saved: Dictionary = GameData.modern_agents.classes.duplicate()
	if classic: GameData.modern_agents.classes.erase(cid)
	var actor := CSBot.new()
	actor.team = "CT" if cid in ["sas","urban","gsg9","gign"] else "T"
	add_child(actor)
	actor.set_team_and_class(actor.team,cid)
	actor.spawn_for_round(pos,0,true)
	GameData.modern_agents.classes = saved
	actor.set_physics_process(false)
	actor.weapon_ctrl.set_process(false)
	actor.velocity = Vector3(0.5,0,-0.2)
	actor._evaluate_character_pose(0.2)
	actor._die(null,"ak47",false)
	expect(is_instance_valid(actor._ragdoll),"death creates articulated body " + cid)
	if is_instance_valid(actor._ragdoll):
		expect(actor._ragdoll.links.size()==11,"all eleven body segments " + cid)
		expect(actor._ragdoll.get_children().filter(func(n):return n is ConeTwistJoint3D).size()==10,"ten limited joints " + cid)
		for link in actor._ragdoll.links:
			expect(link.body.global_basis.get_scale().is_equal_approx(Vector3.ONE),"metric physics body " + cid)
	return actor
func _run() -> void:
	RoundManager.set_process(false)
	RoundManager.state = RoundManager.State.LIVE
	RoundManager.game_world = self
	camera = Camera3D.new()
	camera.fov = 55
	add_child(camera)
	camera.current = true
	camera.look_at_from_position(Vector3(4,3.3,5),Vector3(0,0.5,0))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12,0.16,0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.8
	camera.environment = env
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-20,0)
	add_child(light)
	box(Vector3(0,-0.25,0),Vector3(30,0.5,30))
	box(Vector3(-2,0.20,0),Vector3(2,0.25,3),0.20)
	box(Vector3(1.5,0.18,-1),Vector3(1.5,0.36,1.0))
	await get_tree().physics_frame
	for wid in GameData.weapons: await check_drop(wid)
	for option in GameData.get_knife_options():
		GameData.select_knife(option.id)
		await check_drop("knife")
	GameData.select_knife("original")
	await check_drop("defuser")
	await capture_drop_surfaces()
	for cid in GameData.modern_agents.classes:
		if cid in ["sas","terror"]: continue
		var actor := actor_at(cid,Vector3(0,0.1,0))
		await get_tree().physics_frame
		actor.queue_free()
		await get_tree().physics_frame
	var classic := actor_at("sas",Vector3(0,0.1,0),true)
	await get_tree().physics_frame
	classic.queue_free()
	await get_tree().physics_frame
	var first := actor_at("sas",Vector3(-1.8,0.8,0))
	var second := actor_at("terror",Vector3(1.5,0.6,-0.8))
	await capture("ragdoll_start")
	for frame in 240:
		await get_tree().physics_frame
		if frame==50: await capture("ragdoll_falling")
	await capture("ragdoll_rest")
	for actor in [first,second]:
		for link in actor._ragdoll.links:
			expect(link.body.global_position.is_finite(),"finite settled body")
			expect(link.body.global_position.y>-0.2,"body stays above floor")
		var pelvis: RigidBody3D = actor._ragdoll.links[0].body
		expect(pelvis.global_position.y<0.85,"gravity collapses standing pose")
		actor._ragdoll.apply_bullet_impulse(pelvis,pelvis.global_position,Vector3.RIGHT,80)
		actor._ragdoll.apply_explosion_impulse(pelvis.global_position-Vector3(1,0,0),5,10)
	await get_tree().physics_frame
	expect(first._ragdoll.links[0].body.linear_velocity.length()>0.1,"impacts wake articulated corpse")
	await capture("ragdoll_impulse")
	first.spawn_for_round(Vector3(0,0.1,0),0,true)
	expect(not is_instance_valid(first._ragdoll),"respawn removes ragdoll")
	expect(first._skel.get_bone_global_pose_override(first._skel.find_bone("pelvis")).is_equal_approx(Transform3D.IDENTITY),"respawn clears overrides")
	print("[DROP RAGDOLL] PASS: %d checks; %d failures" % [checks,failures])
	get_tree().quit(0 if failures==0 else 1)
