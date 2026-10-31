class_name MapLoader
extends RefCounted
## Instantiates a converted Counter-Strike 1.5 BSP map (.glb + baked RGB lightmap + entities).


static func build_map(parent: Node3D, map_data: Dictionary) -> Dictionary:
	var result := {
		"root": null,
		"doors": [],
		"breakables": [],
		"ladders": [],
		"bombsites": [],
		"buyzones": [],
		"rescue_zones": [],
		"escape_zones": [],
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

	# Cache ShaderMaterials per (tex_name, alpha_val, is_water)
	var mat_cache: Dictionary = {}

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

		# Apply GoldSrc baked lightmap shader to all surfaces of this mesh
		if mi.mesh and world_shader:
			for surf_i in range(mi.mesh.get_surface_count()):
				var orig_mat := mi.mesh.surface_get_material(surf_i)
				var tex_safe := orig_mat.resource_name if orig_mat else "default_tex"
				if tex_safe.is_empty() and orig_mat is BaseMaterial3D and orig_mat.albedo_texture:
					tex_safe = orig_mat.albedo_texture.resource_path.get_file().get_basename()
				var tex_path := "res://assets/textures/world/%s.png" % tex_safe
				var albedo := GameData.get_texture(tex_path)
				var tmeta: Dictionary = GameData.world_textures_meta.get(tex_safe, {})
				var is_masked := bool(tmeta.get("masked", tex_safe.begins_with("mask_")))
				var surf_water := is_water or tex_safe.begins_with("water_")

				var ckey := "%s_%.2f_%s" % [tex_safe, alpha_f, str(surf_water)]
				var smat: ShaderMaterial = mat_cache.get(ckey)
				if not smat:
					smat = ShaderMaterial.new()
					smat.shader = world_shader
					if albedo:
						smat.set_shader_parameter("albedo_tex", albedo)
					if lm_tex:
						smat.set_shader_parameter("lightmap_tex", lm_tex)
					smat.set_shader_parameter("use_alpha_scissor", is_masked)
					smat.set_shader_parameter("alpha_Val", alpha_f)
					smat.set_shader_parameter("is_water", surf_water)
					mat_cache[ckey] = smat
				mi.set_surface_override_material(surf_i, smat)

		# Position submodel origin if specified in BSP entity
		if sub_idx > 0 and bmeta.has("origin"):
			var o: Array = bmeta["origin"]
			mi.position += Vector3(float(o[0]), float(o[1]), float(o[2]))

		# Attach static trimesh collision on solid world & solid brush entities
		if is_solid and not is_water and mi.mesh:
			mi.create_trimesh_collision()
			for sc in mi.get_children():
				if sc is StaticBody3D:
					sc.collision_layer = 1
					sc.collision_mask = 0

		# Wrap interactive doors & breakables
		if cname == "func_breakable":
			var brk := BSPBreakable.new()
			brk.name = "Breakable_%d" % sub_idx
			map_root.add_child(brk)
			mi.reparent(brk, true)
			brk.setup_breakable(float(bmeta.get("health", 35.0)), int(bmeta.get("material", 0)))
			for sc in mi.get_children():
				if sc is StaticBody3D:
					sc.set_meta("breakable", brk)
			result["breakables"].append(brk)

		elif cname in ["func_door", "func_door_rotating"]:
			var door := BSPDoor.new()
			door.name = "Door_%d" % sub_idx
			var c_arr: Array = bmeta.get("center", [0.0, 0.0, 0.0])
			door.position = Vector3(float(c_arr[0]), float(c_arr[1]), float(c_arr[2]))
			map_root.add_child(door)
			mi.reparent(door, true)

			if cname == "func_door_rotating":
				var sflags := int(bmeta.get("spawnflags", 0))
				var rot_vec := Vector3(0.0, deg_to_rad(90.0), 0.0)
				if sflags & 64:
					rot_vec = Vector3(deg_to_rad(90.0), 0.0, 0.0)
				elif sflags & 128:
					rot_vec = Vector3(0.0, 0.0, deg_to_rad(90.0))
				door.setup_rotating(rot_vec, float(bmeta.get("speed", 100.0)))
			else:
				var ang: Array = bmeta.get("angles", [0.0, 0.0, 0.0])
				var yaw_gs := deg_to_rad(float(ang[1]))
				var move_dir := Vector3(-sin(yaw_gs), 0.0, -cos(yaw_gs))
				if float(ang[0]) <= -89.0 or absf(float(ang[1]) + 1.0) < 0.1:
					move_dir = Vector3.UP
				elif float(ang[0]) >= 89.0 or absf(float(ang[1]) + 2.0) < 0.1:
					move_dir = Vector3.DOWN
				var aabb := mi.get_aabb()
				var span := absf(move_dir.x) * aabb.size.x + absf(move_dir.y) * aabb.size.y + absf(move_dir.z) * aabb.size.z
				var lip := float(bmeta.get("lip", 8.0)) * GameData.SCALE
				door.setup_sliding(move_dir * maxf(0.4, span - lip), float(bmeta.get("speed", 100.0)))

			for sc in mi.get_children():
				if sc is StaticBody3D:
					sc.set_meta("door", door)
			result["doors"].append(door)

	# 3. Parse AABB zones (Ladders, Bombsites, Buyzones, Rescue zones, Escape zones)
	result["ladders"] = _parse_aabbs(map_data.get("ladders", []), 0.32)
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
