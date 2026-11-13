class_name WristSeamFit
extends RefCounted
## Preserve the original per-weapon cuff topology and its exact animated binds.
## Dedicated agent forearms remain proximal; their texture continues over cuff.
static var enabled := true
static var cache: Dictionary = {}
static var profiles_by_key: Dictionary = {}

static func vertex(arrays: Array, index: int, mapped: Array[int] = []) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride: int = bones.size() / vertices.size()
	var influence: Dictionary = {}
	for slot in stride:
		var bind := bones[index * stride + slot]
		if not mapped.is_empty(): bind = mapped[bind]
		if weights[index * stride + slot] > 0:
			influence[bind] = float(influence.get(bind, 0.0)) + weights[index * stride + slot]
	return {"p": vertices[index], "n": arrays[Mesh.ARRAY_NORMAL][index], "uv": arrays[Mesh.ARRAY_TEX_UV][index], "w": influence}

static func interpolate(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var weights: Dictionary = {}
	for bind in a.w: weights[bind] = float(a.w[bind]) * (1.0 - t)
	for bind in b.w: weights[bind] = float(weights.get(bind, 0.0)) + float(b.w[bind]) * t
	return {"p": a.p.lerp(b.p, t), "n": a.n.lerp(b.n, t).normalized(), "uv": a.uv.lerp(b.uv, t), "w": weights}

static func clip(triangle: Array, wrist: Vector3, axis: Vector3, plane: float, distal: bool) -> Array:
	var output: Array = []
	for i in triangle.size():
		var a: Dictionary = triangle[i]
		var b: Dictionary = triangle[(i + 1) % triangle.size()]
		var da: float = (a.p - wrist).dot(axis) - plane
		var db: float = (b.p - wrist).dot(axis) - plane
		var inside_a := da >= 0 if distal else da <= 0
		var inside_b := db >= 0 if distal else db <= 0
		if inside_a: output.append(a)
		if inside_a != inside_b: output.append(interpolate(a, b, da / (da - db)))
	return output

static func emit(tool: SurfaceTool, polygon: Array) -> void:
	for index in range(1, polygon.size() - 1):
		for data in [polygon[0], polygon[index], polygon[index + 1]]:
			var ranked: Array = data.w.keys()
			ranked.sort_custom(func(a, b): return data.w[a] > data.w[b])
			var total := 0.0
			for i in mini(4, ranked.size()): total += float(data.w[ranked[i]])
			var bones := PackedInt32Array([0, 0, 0, 0])
			var weights := PackedFloat32Array([0, 0, 0, 0])
			for i in mini(4, ranked.size()):
				bones[i] = ranked[i]
				weights[i] = float(data.w[ranked[i]]) / maxf(total, 0.000001)
			tool.set_normal(data.n)
			tool.set_uv(data.uv)
			tool.set_bones(bones)
			tool.set_weights(weights)
			tool.add_vertex(data.p)

static func side_of(data: Dictionary, skin: Skin, rig: Skeleton3D) -> String:
	var dominant := -1
	var maximum := -1.0
	for bind in data.w:
		if float(data.w[bind]) > maximum:
			maximum = float(data.w[bind])
			dominant = int(bind)
	var name := rig.get_bone_name(skin.get_bind_bone(dominant))
	return "L" if "_L_" in name else "R"

static func is_bare(avatar: String) -> bool:
	return avatar in ["leet", "phoenix", "phoenix_a"]

static func layer_point(point: Vector3, wrist: Vector3, axis: Vector3, profile: Dictionary, bare: bool) -> Vector3:
	var along := (point - wrist).dot(axis)
	var radial := point - wrist - axis * along
	if radial.length_squared() < 0.000001: return point
	var direction := radial.normalized()
	var radius := INF if bare else 0.0
	for sample in profile.points:
		radius = minf(radius, float(sample.radius)) if bare else maxf(radius, float(sample.radius))
	if not is_finite(radius) or radius <= 0.0: radius = 0.05
	var target_radius := maxf(0.02, radius - 0.007) if bare else radius + 0.006
	var blend := smoothstep(float(profile.start) - 0.09, float(profile.start) + 0.008, along)
	return wrist + axis * along + direction * lerpf(radial.length(), target_radius, blend)

static func fit(root: Node3D, rig: Skeleton3D, mesh: ArrayMesh, skin: Skin, key: String, avatar: String = "sas") -> ArrayMesh:
	var wrists: Dictionary = {}
	var axes: Dictionary = {}
	var references: Array[Dictionary] = []
	# Bind reconstruction intentionally runs even on a geometry cache hit.
	for original in SportGloves._find_meshes(root):
		if original.skin == null or original.has_meta("native_view_cosmetic") or original.has_meta("sport_gloves"): continue
		var mapped: Array[int] = []
		for bind in original.skin.get_bind_count():
			var name := String(original.skin.get_bind_name(bind))
			var bone := AgentViewArms._bone(rig, name) if not name.is_empty() else original.skin.get_bind_bone(bind)
			var target := -1
			for i in skin.get_bind_count():
				if skin.get_bind_bone(i) == bone and skin.get_bind_pose(i).is_equal_approx(original.skin.get_bind_pose(bind)):
					target = i
					break
			if target < 0:
				target = skin.get_bind_count()
				skin.add_bind(bone, original.skin.get_bind_pose(bind))
			mapped.append(target)
		for side in ["L", "R"]:
			var hand := Transform3D.IDENTITY
			var elbow := Transform3D.IDENTITY
			for bind in original.skin.get_bind_count():
				var bone := skin.get_bind_bone(mapped[bind])
				var name := rig.get_bone_name(bone)
				if ("_" + String(side) + "_Hand") in name: hand = original.skin.get_bind_pose(bind).affine_inverse()
				if ("_" + String(side) + "_Forearm") in name: elbow = original.skin.get_bind_pose(bind).affine_inverse()
			wrists[side] = hand.origin
			axes[side] = (hand.origin - elbow.origin).normalized()
		for surface in original.mesh.get_surface_count():
			if original.mesh.surface_get_material(surface).resource_name == "ct_arms.bmp":
				references.append({"arrays": original.mesh.surface_get_arrays(surface), "mapped": mapped})
	var profiles: Dictionary = {}
	for side in ["L", "R"]:
		profiles[side] = {"start": INF, "points": []}
	# Read the actually selected glove, not a fixed Sport or classic radius.
	for glove in SportGloves._find_meshes(root):
		if glove.skin == null: continue
		for surface in glove.mesh.get_surface_count():
			var material := glove.mesh.surface_get_material(surface)
			if not glove.has_meta("sport_gloves") and material.resource_name != "ct_base_glove.bmp": continue
			var arrays := glove.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride: int = binds.size() / vertices.size()
			var candidates: Dictionary = {"L": [], "R": []}
			for index in vertices.size():
				var dominant := 0
				for slot in stride:
					if weights[index * stride + slot] > weights[index * stride + dominant]: dominant = slot
				var bind := binds[index * stride + dominant]
				var name := String(glove.skin.get_bind_name(bind))
				var bone := AgentViewArms._bone(rig, name) if not name.is_empty() else glove.skin.get_bind_bone(bind)
				var side := "L" if "_L_" in rig.get_bone_name(bone) else "R"
				var axis: Vector3 = axes[side]
				var delta: Vector3 = vertices[index] - wrists[side]
				var along := delta.dot(axis)
				var radial := delta - axis * along
				profiles[side].start = minf(float(profiles[side].start), along)
				candidates[side].append({"along": along, "direction": radial.normalized(), "radius": radial.length()})
			for side in ["L", "R"]:
				for sample in candidates[side]:
					if float(sample.along) < float(profiles[side].start) + 0.018:
						profiles[side].points.append(sample)
	for side in ["L", "R"]:
		if not is_finite(float(profiles[side].start)): profiles[side].start = -0.05
	profiles_by_key[key] = {"profiles": profiles, "wrists": wrists, "axes": axes, "bare": is_bare(avatar)}
	if cache.has(key): return cache[key]
	if references.is_empty(): return mesh
	var result := ArrayMesh.new()
	var samples: Dictionary = {"L": [], "R": []}
	# Remove the imported distal end instead of deforming a foreign wrist mesh.
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var material := mesh.surface_get_material(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var data: Array[Dictionary] = []
		for i in vertices.size():
			var item := vertex(arrays, i)
			data.append(item)
			var side := side_of(item, skin, rig)
			if (item.p - wrists[side]).dot(axes[side]) > -0.23:
				samples[side].append({"data": item, "material": material})
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in range(0, indices.size(), 3):
			var triangle: Array = [data[indices[index]], data[indices[index + 1]], data[indices[index + 2]]]
			var side := side_of(triangle[0], skin, rig)
			emit(tool, clip(triangle, wrists[side], axes[side], -0.105, false))
		tool.set_material(material)
		tool.generate_tangents()
		tool.commit(result)
	# Retain the real cuff's geometry, topology and matrices, up to the glove.
	for side in ["L", "R"]:
		if samples[side].is_empty(): continue
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var material: Material = samples[side][0].material
		for reference in references:
			var arrays: Array = reference.arrays
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var data: Array[Dictionary] = []
			for i in vertices.size():
				var item := vertex(arrays, i, reference.mapped)
				var nearest := INF
				var chosen: Dictionary = samples[side][0]
				if side_of(item, skin, rig) == side and (item.p - wrists[side]).dot(axes[side]) > -0.18:
					for sample in samples[side]:
						var distance: float = item.p.distance_squared_to(sample.data.p)
						if distance < nearest:
							nearest = distance
							chosen = sample
					item.uv = chosen.data.uv
					material = chosen.material
				if side_of(item, skin, rig) == side:
					item.p = layer_point(item.p, wrists[side], axes[side], profiles[side], is_bare(avatar))
					var axis: Vector3 = axes[side]
					var delta: Vector3 = item.p - wrists[side]
					var radial := (delta - axis * delta.dot(axis)).normalized()
					var blend := smoothstep(float(profiles[side].start) - 0.09, float(profiles[side].start) + 0.008, delta.dot(axis))
					item.n = item.n.lerp(radial, blend).normalized()
				data.append(item)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for index in range(0, indices.size(), 3):
				var triangle: Array = [data[indices[index]], data[indices[index + 1]], data[indices[index + 2]]]
				if side_of(triangle[0], skin, rig) != side: continue
				var end: float = float(profiles[side].start) + (0.028 if is_bare(avatar) else 0.018)
				var polygon := clip(triangle, wrists[side], axes[side], -0.15, true)
				emit(tool, clip(polygon, wrists[side], axes[side], end, false))
		tool.set_material(material)
		tool.generate_tangents()
		tool.commit(result)
	cache[key] = result
	return result
