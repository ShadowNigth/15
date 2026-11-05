class_name MapLoader
extends RefCounted
## Instantiates a converted Counter-Strike 1.5 BSP map (.glb + baked RGB lightmap + entities).


static func build_map(parent: Node3D, map_data: Dictionary) -> Dictionary:
	ImpactEffects.clear_decals()

	var ladders_typed: Array[AABB] = []
	var bombsites_typed: Array[AABB] = []
	var rescue_typed: Array[AABB] = []
	var escape_typed: Array[AABB] = []
	var water_typed: Array[AABB] = []

	var result := {
		"root": null,
		"doors": [],
		"breakables": [],
		"ladders": ladders_typed,
		"ladder_volumes": [],
		"triggers": [],
		"bombsites": bombsites_typed,
		"buyzones": [],
		"rescue_zones": rescue_typed,
		"escape_zones": escape_typed,
		"water_zones": water_typed,
	}

	var map_root := Node3D.new()
	map_root.name = "BSPMap_" + String(map_data.get("name", "map"))
	parent.add_child(map_root)
	result["root"] = map_root

	# 1. Skybox & Lighting
	SkyBuilder.setup_environment(map_root, String(map_data.get("skyname", "des")))

	# 2. Load .glb geometry & baked GoldSrc RGB lightmap
	var glb_path := String(map_data.get("glb", ""))
	var lm_path := String(map_data.get("lightmap", ""))
	var lm_tex := GameData.get_texture(lm_path)
	var world_shader := load("res://assets/shaders/goldsrc_world.gdshader") as Shader
	var masked_shader := load("res://assets/shaders/goldsrc_world_masked.gdshader") as Shader
	var alpha_shader := load("res://assets/shaders/goldsrc_world_alpha.gdshader") as Shader
	var water_shader := load("res://assets/shaders/water.gdshader") as Shader

	var glb_scene := load(glb_path) as PackedScene
	if not glb_scene:
		push_error("[MapLoader] Could not load map GLB: " + glb_path)
		return result

	var glb_inst := glb_scene.instantiate()
	map_root.add_child(glb_inst)

	# Index brush entity metadata by submodel index
	var brush_by_sub: Dictionary = {}
	for be in map_data.get("brush_entities", []):
		brush_by_sub[int(be.get("submodel", -1))] = be

	# Cache ShaderMaterials per (tex_name, alpha_val, is_masked, is_water) & retain on map_root
	var mat_cache: Dictionary = {}
	map_root.set_meta("world_materials", mat_cache)

	for child in glb_inst.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi := child as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var nname := mi.name

		var sub_idx := 0
		if nname.begins_with("submodel_"):
			sub_idx = int(nname.trim_prefix("submodel_"))

		var bmeta: Dictionary = brush_by_sub.get(sub_idx, {})
		var cname := String(bmeta.get("classname", "worldspawn"))
		var rmode := int(bmeta.get("rendermode", 0))
		var ramt := int(bmeta.get("renderamt", 255))
		var is_solid := bool(bmeta.get("solid", true))
		var is_water := (cname == "func_water")

		# Hide invisible trigger-like func_walls (rendermode != 0 and renderamt == 0)
		if sub_idx > 0 and rmode != 0 and ramt == 0:
			mi.visible = false
			continue

		var alpha_f := 1.0
		if rmode in [1, 2, 5] and ramt < 250:
			alpha_f = clampf(float(ramt) / 255.0, 0.12, 0.95)
		elif is_water:
			alpha_f = 0.78

		var has_ladder_tex := false
		var has_grate_tex := false
		var has_crate_tex := false
		var water_surfaces: Array[int] = []

		# Apply GoldSrc baked lightmap shader (opaque vs alpha-scissor vs translucent)
		mi.layers = 1
		if mi.mesh and world_shader:
			for surf_i in range(mi.mesh.get_surface_count()):
				var orig_mat := mi.mesh.surface_get_material(surf_i)
				var tex_safe := orig_mat.resource_name if orig_mat else "default_tex"
				var albedo: Texture2D = null
				if orig_mat is BaseMaterial3D and (orig_mat as BaseMaterial3D).albedo_texture:
					albedo = (orig_mat as BaseMaterial3D).albedo_texture
					if tex_safe.is_empty():
						tex_safe = albedo.resource_path.get_file().get_basename()
				if albedo == null:
					var tex_path := "res://assets/textures/world/%s.png" % tex_safe
					albedo = GameData.get_texture(tex_path)
				var tlow := tex_safe.to_lower()
				if "ladder" in tlow or "rung" in tlow:
					has_ladder_tex = true
				elif tlow.begins_with("mask_"):
					has_grate_tex = true
				# Site crates: mltrycrtetp / mltrycrtesd2 / sandcrtsmtp / xcrate…
				if "crate" in tlow or "crt" in tlow:
					has_crate_tex = true
				var tmeta: Dictionary = GameData.world_textures_meta.get(tex_safe, {})
				var is_masked := bool(tmeta.get("masked", tex_safe.begins_with("mask_")))
				var surf_water := is_water or "water" in tlow
				if surf_water:
					water_surfaces.append(surf_i)
				var use_alpha := (alpha_f < 0.99) or surf_water

				var ckey := "%s_%.2f_%s_%s" % [tex_safe, alpha_f, str(is_masked), str(surf_water)]
				var smat: ShaderMaterial = mat_cache.get(ckey)
				if not smat:
					smat = ShaderMaterial.new()
					smat.resource_name = tex_safe
					if surf_water and water_shader:
						smat.shader = water_shader
						smat.set_shader_parameter("alpha_Val", minf(alpha_f, 0.76))
					elif use_alpha and alpha_shader:
						smat.shader = alpha_shader
						smat.set_shader_parameter("alpha_Val", alpha_f)
						smat.set_shader_parameter("is_water", false)
					elif is_masked and masked_shader:
						smat.shader = masked_shader
					else:
						smat.shader = world_shader
						var decorative := tlow.begins_with("ad_") or tlow.begins_with("lgt_") \
							or "sign" in tlow or "poster" in tlow or "graff" in tlow \
							or "screen" in tlow or "money" in tlow
						smat.set_shader_parameter("relief_depth", 0.0 if decorative else 0.045)
						smat.set_shader_parameter("detail_strength", 0.12 if decorative else 0.34)
					if albedo:
						smat.set_shader_parameter("albedo_tex", albedo)
					if lm_tex:
						smat.set_shader_parameter("lightmap_tex", lm_tex)
					mat_cache[ckey] = smat
				mi.set_surface_override_material(surf_i, smat)

		# Position submodel origin if specified in BSP entity
		var orig_vec := Vector3.ZERO
		if sub_idx > 0 and bmeta.has("origin"):
			var o: Array = bmeta["origin"]
			orig_vec = Vector3(float(o[0]), float(o[1]), float(o[2]))
			mi.position += orig_vec

		# Attach trimesh collision:
		# - Layer 1 on solid world/brushes (unless pure visual ladder rungs, which go to Layer 8 so climbers never snag!)
		# - Layer 8 on func_illusionary metal ladders/grates so bullets & knives spark/ricochet on metal rungs!
		var pure_ladder_brush: bool = (sub_idx > 0 and has_ladder_tex and cname in ["func_wall", "func_illusionary"])
		if not is_water and mi.mesh and (is_solid or has_ladder_tex or has_grate_tex):
			if water_surfaces.is_empty():
				mi.create_trimesh_collision()
			else:
				# Worldspawn can mix water and solid primitives. Never drop the whole
				# map's collision, but never make the liquid primitive solid either.
				_create_filtered_trimesh_collision(mi, water_surfaces)
			var col_layer: int = 8 if (pure_ladder_brush or not is_solid) else 1
			for sc in mi.get_children():
				if sc is StaticBody3D:
					sc.collision_layer = col_layer
					sc.collision_mask = 0
					if has_ladder_tex:
						sc.set_meta("surface_mat", "L")
					elif has_grate_tex:
						sc.set_meta("surface_mat", "G")

		# Wrap interactive breakables, buttons, and doors
		if cname == "func_breakable":
			var brk := BSPBreakable.new()
			brk.name = "Breakable_%d" % sub_idx
			map_root.add_child(brk)
			mi.reparent(brk, true)
			brk.setup_breakable(float(bmeta.get("health", 35.0)), int(bmeta.get("material", 0)), not has_crate_tex)
			for sc in mi.get_children():
				if sc is StaticBody3D:
					sc.set_meta("breakable", brk)
			result["breakables"].append(brk)

		elif cname in ["func_button", "func_rot_button"]:
			var btn_tgt := String(bmeta.get("target", ""))
			var bc_arr: Array = bmeta.get("center", [0.0, 0.0, 0.0])
			var bc_vec := Vector3(float(bc_arr[0]), float(bc_arr[1]), float(bc_arr[2]))
			for sc in mi.get_children():
				if sc is StaticBody3D:
					sc.set_meta("button_target", btn_tgt)
					sc.set_meta("button_center", bc_vec)

		elif cname in ["func_door", "func_door_rotating"]:
			var lip_raw: float = float(bmeta.get("lip", 0.0))
			# Keep decorative skybox movers (e.g. de_torn jet1..4 with lip=-4096) static
			if absf(lip_raw) >= 1000.0:
				continue

			var door := BSPDoor.new()
			door.name = "Door_%d" % sub_idx
			var c_arr: Array = bmeta.get("center", [0.0, 0.0, 0.0])
			var c_vec := Vector3(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]))
			var is_rot: bool = (cname == "func_door_rotating")
			# Rotating doors pivot around their GoldSrc origin hinge; sliding doors around center
			if is_rot and orig_vec.length_squared() > 0.001:
				door.position = orig_vec
			else:
				door.position = c_vec
			map_root.add_child(door)
			mi.reparent(door, true)

			var d_aabb: AABB
			if bmeta.has("min") and bmeta.has("max"):
				d_aabb = _dict_to_aabb(bmeta, 0.0)
			else:
				var la := mi.get_aabb()
				d_aabb = AABB(mi.global_position + la.position, la.size)

			door.setup_door(
				is_rot,
				bmeta.get("angles", [0.0, 0.0, 0.0]),
				float(bmeta.get("speed", 100.0)),
				lip_raw,
				d_aabb,
				float(bmeta.get("distance", 90.0)),
				float(bmeta.get("wait", 4.0)),
				String(bmeta.get("targetname", "")),
				int(bmeta.get("spawnflags", 0))
			)

			for sc in mi.get_children():
				if sc is StaticBody3D:
					sc.set_meta("door", door)
			result["doors"].append(door)

	# Link adjacent double-door panels (HLSDK LinkDoors: touching closed AABBs with matching target_name)
	var doors_arr: Array = result["doors"]
	for i in range(doors_arr.size()):
		var da: BSPDoor = doors_arr[i]
		var grow_a: AABB = da.closed_aabb.grow(0.38)
		for j in range(i + 1, doors_arr.size()):
			var db: BSPDoor = doors_arr[j]
			if da.target_name == db.target_name and grow_a.intersects(db.closed_aabb):
				da.linked_doors.append(db)
				db.linked_doors.append(da)

	# 3. Parse Precision Metal Ladder Volumes + Trigger Volumes + Objective Zones
	for ldict in map_data.get("ladders", []):
		if not (ldict is Dictionary):
			continue
		var raw_l: AABB = _dict_to_aabb(ldict, 0.0)
		# Horizontal pad 0.48m (> 0.36m capsule radius even flush against walls!), +0.56m top vault extension
		var c_min: Vector3 = raw_l.position - Vector3(0.48, 0.16, 0.48)
		var c_max: Vector3 = raw_l.end + Vector3(0.48, 0.56, 0.48)
		var climb_box := AABB(c_min, c_max - c_min)
		ladders_typed.append(climb_box)
		var thin_axis: Vector3 = Vector3(1, 0, 0) if raw_l.size.x <= raw_l.size.z else Vector3(0, 0, 1)
		result["ladder_volumes"].append({
			"raw_aabb": raw_l,
			"climb_aabb": climb_box,
			"axis": thin_axis,
			"normal": Vector3.ZERO,
			"resolved": false,
		})

	for tdict in map_data.get("triggers", []):
		if tdict is Dictionary:
			var t_tgt := String(tdict.get("target", ""))
			if not t_tgt.is_empty():
				result["triggers"].append({
					"aabb": _dict_to_aabb(tdict, 0.25),
					"target": t_tgt,
				})

	water_typed.assign(_parse_aabbs(map_data.get("water_zones", []), 0.0))
	result["bombsites"] = _parse_aabbs(map_data.get("bombsites", []), 0.5)
	result["rescue_zones"] = _parse_aabbs(map_data.get("rescue_zones", []), 0.6)
	result["escape_zones"] = _parse_aabbs(map_data.get("escape_zones", []), 0.6)

	for bz in map_data.get("buyzones", []):
		var aabb := _dict_to_aabb(bz, 0.5)
		result["buyzones"].append({"aabb": aabb, "team": String(bz.get("team", "0"))})

	# Fallback CS 1.5 spawn buyzones if map doesn't define explicit func_buyzone brushes
	if result["buyzones"].is_empty():
		for sp in map_data.get("ct_spawns", []):
			var p: Array = sp["pos"]
			var v := Vector3(float(p[0]), float(p[1]), float(p[2]))
			result["buyzones"].append({"aabb": AABB(v - Vector3(6, 3, 6), Vector3(12, 6, 12)), "team": "2"})
		for sp in map_data.get("t_spawns", []):
			var p2: Array = sp["pos"]
			var v2 := Vector3(float(p2[0]), float(p2[1]), float(p2[2]))
			result["buyzones"].append({"aabb": AABB(v2 - Vector3(6, 3, 6), Vector3(12, 6, 12)), "team": "1"})

	# Fallback rescue zone near CT spawn on cs_* maps if omitted
	if String(map_data.get("mode", "")) == "cs" and result["rescue_zones"].is_empty():
		var cts: Array = map_data.get("ct_spawns", [])
		if not cts.is_empty():
			var p3: Array = cts[0]["pos"]
			var v3 := Vector3(float(p3[0]), float(p3[1]), float(p3[2]))
			result["rescue_zones"].append(AABB(v3 - Vector3(5, 3, 5), Vector3(10, 6, 10)))

	# 4. Subtle Bombsite decal markers on A / B centers
	for i in range(result["bombsites"].size()):
		var b_aabb: AABB = result["bombsites"][i]
		var marker := Sprite3D.new()
		marker.texture = GameData.get_hud_atlas("c4", 320)
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.modulate = Color(1.0, 0.3, 0.15, 0.65)
		marker.pixel_size = 0.018
		marker.position = b_aabb.get_center() + Vector3(0, 0.4, 0)
		map_root.add_child(marker)

	# 5. Map ambient_generic 3D audio emitters (up to 8 subtle looping ambient emitters)
	var amb_count := 0
	for amb in map_data.get("ambient_sounds", []):
		if amb_count >= 8:
			break
		var srel := String(amb.get("sound", ""))
		var stream := GameData.get_sound(srel)
		if not stream:
			continue
		var ap := AudioStreamPlayer3D.new()
		ap.stream = stream
		var pa: Array = amb["pos"]
		ap.position = Vector3(float(pa[0]), float(pa[1]), float(pa[2]))
		ap.volume_db = -12.0 + GameData.master_volume_db
		ap.unit_size = 5.0
		ap.max_distance = 28.0
		ap.autoplay = true
		map_root.add_child(ap)
		amb_count += 1

	return result


static func _create_filtered_trimesh_collision(mi: MeshInstance3D, skipped: Array[int]) -> void:
	var source := mi.mesh as ArrayMesh
	if source == null:
		mi.create_trimesh_collision()
		return
	var filtered := ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		if surface in skipped:
			continue
		filtered.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(surface))
	if filtered.get_surface_count() == 0:
		return
	var body := StaticBody3D.new()
	body.name = "FilteredWorldCollision"
	mi.add_child(body)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = filtered.create_trimesh_shape()
	body.add_child(collider)


static func _dict_to_aabb(d: Dictionary, expand: float = 0.0) -> AABB:
	var lo: Array = d.get("min", [0, 0, 0])
	var hi: Array = d.get("max", [1, 1, 1])
	var pmin := Vector3(float(lo[0]), float(lo[1]), float(lo[2])) - Vector3.ONE * expand
	var pmax := Vector3(float(hi[0]), float(hi[1]), float(hi[2])) + Vector3.ONE * expand
	return AABB(pmin, pmax - pmin)


static func _parse_aabbs(arr: Array, expand: float = 0.0) -> Array[AABB]:
	var out: Array[AABB] = []
	for item in arr:
		if item is Dictionary:
			out.append(_dict_to_aabb(item, expand))
	return out
