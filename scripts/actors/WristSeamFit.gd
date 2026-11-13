class_name WristSeamFit
extends RefCounted
## Fit in the DESTINATION rig's bind space, after weapon-specific retargeting.
## This avoids reinterpreting ForeTwist coordinates through a different bind roll.
static var cache: Dictionary = {}

static func fit(root: Node3D, rig: Skeleton3D, mesh: ArrayMesh, skin: Skin, key: String) -> ArrayMesh:
	var samples: Array[Dictionary] = []
	var sample_keys: Dictionary = {}
	var wrists: Dictionary = {}
	var elbows: Dictionary = {}
	for source in SportGloves._find_meshes(root):
		if source.skin == null or source.has_meta("native_view_cosmetic") or source.has_meta("sport_gloves"): continue
		var mapped: Array[int] = []
		for bind in source.skin.get_bind_count():
			var name := String(source.skin.get_bind_name(bind))
			var bone := AgentViewArms._bone(rig, name) if not name.is_empty() else source.skin.get_bind_bone(bind)
			var target := -1
			for index in skin.get_bind_count():
				if skin.get_bind_bone(index) == bone and skin.get_bind_pose(index).is_equal_approx(source.skin.get_bind_pose(bind)):
					target = index
					break
			if target < 0:
				target = skin.get_bind_count()
				skin.add_bind(bone, source.skin.get_bind_pose(bind))
			mapped.append(target)
			var bone_name := rig.get_bone_name(bone)
			for side in ["L", "R"]:
				if ("_" + String(side) + "_Hand") in bone_name: wrists[side] = source.skin.get_bind_pose(bind).affine_inverse().origin
				if ("_" + String(side) + "_Forearm") in bone_name: elbows[side] = source.skin.get_bind_pose(bind).affine_inverse().origin
		for surface in source.mesh.get_surface_count():
			if source.mesh.surface_get_material(surface).resource_name != "ct_arms.bmp": continue
			var arrays := source.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = bones.size() / vertices.size()
			for side in ["L", "R"]:
				if not wrists.has(side) or not elbows.has(side): continue
				var wrist: Vector3 = wrists[side]
				var axis: Vector3 = (wrist - elbows[side]).normalized()
				for vertex in vertices.size():
					var dominant := 0
					for slot in stride:
						if weights[vertex * stride + slot] > weights[vertex * stride + dominant]: dominant = slot
					var target_bind: int = mapped[bones[vertex * stride + dominant]]
					if target_bind < 0 or not ("_" + String(side) + "_") in rig.get_bone_name(skin.get_bind_bone(target_bind)): continue
					var along := (vertices[vertex] - wrist).dot(axis)
					if along < -0.16 or along > 0.03 or vertices[vertex].distance_to(wrist) > 0.2: continue
					var influence: Dictionary = {}
					for slot in stride:
						var offset := vertex * stride + slot
						if weights[offset] <= 0: continue
						var target: int = mapped[bones[offset]]
						if target >= 0: influence[target] = float(influence.get(target, 0.0)) + weights[offset]
					if not influence.is_empty():
						var sample_key := String(side) + ":" + str(vertices[vertex].snapped(Vector3.ONE * 0.0001))
						if not sample_keys.has(sample_key):
							samples.append({"side": side, "point": vertices[vertex], "normal": normals[vertex], "weights": influence})
							sample_keys[sample_key] = true
	if cache.has(key): return cache[key]
	if samples.is_empty(): return mesh
	# Average the original influence mix over each longitudinal wrist ring.
	# Nearest individual old-cuff vertices have angular weight discontinuities
	# that create spikes on bare skin with a different topology.
	var profiles: Dictionary = {}
	var counts: Dictionary = {}
	for sample in samples:
		var side: String = sample.side
		var axis: Vector3 = (wrists[side] - elbows[side]).normalized()
		var along: float = (sample.point - wrists[side]).dot(axis)
		var bin_index := int(floor(along / 0.01))
		var profile_key := side + ":" + str(bin_index)
		if not profiles.has(profile_key): profiles[profile_key] = {}
		for bind in sample.weights:
			profiles[profile_key][bind] = float(profiles[profile_key].get(bind, 0.0)) + float(sample.weights[bind])
		counts[profile_key] = int(counts.get(profile_key, 0)) + 1
	for profile_key in profiles:
		for bind in profiles[profile_key]: profiles[profile_key][bind] /= float(counts[profile_key])
	for side in ["L", "R"]:
		var occupied: Array[int] = []
		for bin_index in range(-16, 4):
			if profiles.has(String(side) + ":" + str(bin_index)): occupied.append(bin_index)
		if occupied.is_empty(): continue
		for bin_index in range(-16, 4):
			var profile_key := String(side) + ":" + str(bin_index)
			if profiles.has(profile_key): continue
			var before: int = occupied[0]
			var after: int = occupied[-1]
			for candidate in occupied:
				if candidate <= bin_index: before = candidate
				if candidate >= bin_index:
					after = candidate
					break
			var fraction := clampf(float(bin_index - before) / float(maxi(after - before, 1)), 0, 1)
			var mixed: Dictionary = {}
			for bind in profiles[String(side) + ":" + str(before)]: mixed[bind] = float(profiles[String(side) + ":" + str(before)][bind]) * (1.0 - fraction)
			for bind in profiles[String(side) + ":" + str(after)]: mixed[bind] = float(mixed.get(bind, 0.0)) + float(profiles[String(side) + ":" + str(after)][bind]) * fraction
			profiles[profile_key] = mixed
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int = bones.size() / vertices.size()
		for vertex in vertices.size():
			var dominant := 0
			for slot in stride:
				if weights[vertex * stride + slot] > weights[vertex * stride + dominant]: dominant = slot
			var bone_name := rig.get_bone_name(skin.get_bind_bone(bones[vertex * stride + dominant]))
			var side := "L" if "_L_" in bone_name else "R"
			if not wrists.has(side) or not elbows.has(side): continue
			var wrist: Vector3 = wrists[side]
			var axis: Vector3 = (wrist - elbows[side]).normalized()
			var along := (vertices[vertex] - wrist).dot(axis)
			if along < -0.12 or vertices[vertex].distance_to(wrist) > 0.2: continue
			var location := clampf(along / 0.01, -15.0, 1.0)
			var lower := int(floor(location))
			var target_weights: Dictionary = {}
			for bin_index in [lower, lower + 1]:
				var profile_key := side + ":" + str(bin_index)
				if not profiles.has(profile_key): continue
				var fraction := (1.0 - (location - float(lower))) if bin_index == lower else location - float(lower)
				for bind in profiles[profile_key]:
					target_weights[bind] = float(target_weights.get(bind, 0.0)) + float(profiles[profile_key][bind]) * fraction
			# Transfer a continuous local neighbourhood, not one arbitrarily
			# chosen old triangle vertex or an overly rigid whole-ring average.
			var neighbours: Array[Dictionary] = []
			for sample in samples:
				if sample.side != side: continue
				var distance: float = vertices[vertex].distance_squared_to(sample.point)
				var at := neighbours.size()
				for index in neighbours.size():
					if distance < float(neighbours[index].distance):
						at = index
						break
				if at < 8:
					neighbours.insert(at, {"distance": distance, "weights": sample.weights})
					if neighbours.size() > 8: neighbours.pop_back()
			var local_weights: Dictionary = {}
			var local_total := 0.0
			for sample in neighbours:
				var strength := 1.0 / maxf(float(sample.distance), 0.000025)
				local_total += strength
				for bind in sample.weights: local_weights[bind] = float(local_weights.get(bind, 0.0)) + float(sample.weights[bind]) * strength
			for bind in target_weights: target_weights[bind] *= 0.2
			if local_total > 0.0:
				for bind in local_weights: target_weights[bind] = float(target_weights.get(bind, 0.0)) + float(local_weights[bind]) / local_total * 0.8
			var target_total := 0.0
			for bind in target_weights: target_total += float(target_weights[bind])
			if target_total < 0.00001: continue
			for bind in target_weights: target_weights[bind] /= target_total
			var blend := smoothstep(-0.12, -0.045, along)
			var influence: Dictionary = {}
			for slot in stride:
				var offset := vertex * stride + slot
				influence[bones[offset]] = float(influence.get(bones[offset], 0.0)) + weights[offset] * (1.0 - blend)
			for bind in target_weights: influence[bind] = float(influence.get(bind, 0.0)) + float(target_weights[bind]) * blend
			var ranked := influence.keys()
			ranked.sort_custom(func(a, b): return influence[a] > influence[b])
			var total := 0.0
			for slot in mini(stride, ranked.size()): total += float(influence[ranked[slot]])
			for slot in stride:
				var offset := vertex * stride + slot
				bones[offset] = ranked[slot] if slot < ranked.size() else 0
				weights[offset] = float(influence[ranked[slot]]) / maxf(total, 0.000001) if slot < ranked.size() else 0.0
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		arrays[Mesh.ARRAY_TANGENT] = null
		var temporary := ArrayMesh.new()
		temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var tool := SurfaceTool.new()
		tool.create_from(temporary, 0)
		tool.generate_tangents()
		tool.set_material(mesh.surface_get_material(surface))
		tool.commit(result)
	cache[key] = result
	return result
