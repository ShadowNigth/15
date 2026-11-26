extends Node

var failures := 0
var checks := 0

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 15: push_error(message)

func bind_name(skin: Skin, rig: Skeleton3D, index: int) -> String:
	var name := String(skin.get_bind_name(index))
	return name if not name.is_empty() else String(rig.get_bone_name(skin.get_bind_bone(index)))

func _ready() -> void:
	for model in ["moto_smoke_out", "sport_native"]:
		var definition: Dictionary = NativeViewRig.catalog().gloves[model]
		var source := (load(String(definition.model)) as PackedScene).instantiate()
		add_child(source)
		for mesh in SportGloves._find_meshes(source):
			var rig := mesh.get_node(mesh.skeleton) as Skeleton3D
			for surface in mesh.mesh.get_surface_count():
				var name := String(mesh.mesh.surface_get_material(surface).resource_name).to_lower()
				if not name.begins_with("glove_"): continue
				var side := "L" if name.ends_with("_left") else "R"
				var other := "R" if side == "L" else "L"
				var original := mesh.mesh.surface_get_arrays(surface)
				var swapped := mesh.mesh.surface_get_arrays(surface)
				var transform := NativeViewRig._hand_rest_frame(rig, other) * NativeViewRig._hand_rest_frame(rig, side).affine_inverse()
				expect(absf(transform.basis.determinant() - 1.0) < 0.0001, "Exchange must be a rotation, not a reflection")
				expect(NativeViewRig._swap_glove_surface(swapped, mesh.skin, rig, side), "Glove exchange failed: " + model + " " + side)
				var old_vertices: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
				var new_vertices: PackedVector3Array = swapped[Mesh.ARRAY_VERTEX]
				var old_normals: PackedVector3Array = original[Mesh.ARRAY_NORMAL]
				var new_normals: PackedVector3Array = swapped[Mesh.ARRAY_NORMAL]
				var original_bones: PackedInt32Array = original[Mesh.ARRAY_BONES]
				var original_weights: PackedFloat32Array = original[Mesh.ARRAY_WEIGHTS]
				var influences := original_bones.size() / old_vertices.size()
				for i in old_vertices.size():
					var adjustment := Vector3.ZERO
					for influence in influences:
						var offset := i * influences + influence
						if original_weights[offset] <= 0.00001: continue
						var source_name := bind_name(mesh.skin, rig, original_bones[offset])
						var position := source_name.find("_" + side)
						var target_name := source_name.substr(0, position) + "_" + other + source_name.substr(position + 2)
						var source_rest := rig.get_bone_global_rest(rig.find_bone(source_name)).origin
						var target_rest := rig.get_bone_global_rest(rig.find_bone(target_name)).origin
						adjustment += (target_rest - transform * source_rest) * original_weights[offset]
					expect(new_vertices[i].distance_to(transform * old_vertices[i] + adjustment * 0.5) < 0.00001, "Vertex correction must be bounded and follow the opposite joints")
				# UV/normal seams often duplicate spatial vertices. The joint
				# adjustment must not pull those copies apart in the rest mesh.
				var first_at_position: Dictionary = {}
				for i in old_vertices.size():
					var p := old_vertices[i]
					var key := Vector3i(roundi(p.x * 100000.0), roundi(p.y * 100000.0), roundi(p.z * 100000.0))
					if first_at_position.has(key):
						expect(new_vertices[i].distance_to(new_vertices[int(first_at_position[key])]) < 0.0001, "Joint adjustment opened a duplicated-vertex seam")
					else:
						first_at_position[key] = i
				for i in old_normals.size():
					expect(new_normals[i].distance_to(transform.basis * old_normals[i]) < 0.00001, "Normal not rotated")
				expect(original[Mesh.ARRAY_TEX_UV] == swapped[Mesh.ARRAY_TEX_UV], "UVs must remain with the original glove")
				expect(original[Mesh.ARRAY_INDEX] == swapped[Mesh.ARRAY_INDEX], "Triangles must remain unchanged")
				expect(original[Mesh.ARRAY_WEIGHTS] == swapped[Mesh.ARRAY_WEIGHTS], "Skin weights must remain unchanged")
				var bones: PackedInt32Array = original[Mesh.ARRAY_BONES]
				var new_bones: PackedInt32Array = swapped[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = original[Mesh.ARRAY_WEIGHTS]
				for i in bones.size():
					if weights[i] <= 0.00001: continue
					var before := bind_name(mesh.skin, rig, bones[i])
					var after := bind_name(mesh.skin, rig, new_bones[i])
					var position := before.find("_" + side)
					expect(position >= 0 and after == before.substr(0, position) + "_" + other + before.substr(position + 2), "Bone must drive the opposite hand")
		source.queue_free()
	print("GLOVE HAND EXCHANGE: ", checks, " checks, ", failures, " failures")
	get_tree().quit(1 if failures else 0)
