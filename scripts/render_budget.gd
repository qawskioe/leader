extends Node
## 静态森林渲染优化：叶面裁切、独立阴影代理、按空间分块的蕨类实例化。

func _ready() -> void:
	_setup.call_deferred()

func _setup() -> void:
	var scene := get_parent()
	prepare_character_materials(scene.get_node("People"))
	var outdoor := scene.get_node("Outdoor") as Node3D
	var sun := scene.get_node("OutdoorSun") as DirectionalLight3D
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 55.0
	var groups: Dictionary = {}
	for node in outdoor.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var label := str(mesh.name)
		for index in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(index) as BaseMaterial3D
			if material != null and (material.resource_name.contains("leaves") or material.resource_name.contains("fern")):
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.33
		if label.begins_with("ShadowTree_"):
			mesh.visible = true
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			mesh.visibility_range_end = 55.0
		elif label.begins_with("WoodlandTree_") or label.begins_with("DistantTree_") or label.begins_with("GroveTree_") or label.begins_with("YoungTree_"):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif label.begins_with("Meadow_") or label.begins_with("Underbrush_"):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_end = 60.0
		if label.begins_with("WoodlandFern_") or label.begins_with("TransitionFern_"):
			var local := outdoor.to_local(mesh.global_position)
			var cell := Vector2i(floori(local.x / 16.0), floori(local.z / 16.0))
			var key := str(mesh.mesh.get_rid().get_id()) + ":" + str(cell)
			if not groups.has(key): groups[key] = {"cell":cell, "mesh":mesh.mesh, "nodes":[]}
			groups[key].nodes.append(mesh)
	var total := 0
	for key in groups:
		var group: Dictionary = groups[key]
		var cell: Vector2i = group.cell
		var origin := Vector3((cell.x + 0.5) * 16.0, 0, (cell.y + 0.5) * 16.0)
		var instance := MultiMeshInstance3D.new()
		instance.name = "FernBatch_" + str(total)
		instance.position = origin
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 60.0
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = group.mesh
		multi.instance_count = group.nodes.size()
		instance.multimesh = multi
		outdoor.add_child(instance)
		for index in range(group.nodes.size()):
			var original := group.nodes[index] as MeshInstance3D
			multi.set_instance_transform(index, instance.global_transform.affine_inverse() * original.global_transform)
			original.visible = false
		total += group.nodes.size()
	set_meta("batched_ferns", total)
	set_meta("fern_batches", groups.size())
	var xr := XRServer.find_interface("OpenXR")
	if ((xr != null and xr.is_initialized()) or OS.get_cmdline_user_args().has("--profile-vr-trees")) and not OS.get_cmdline_user_args().has("--profile-desktop-trees"):
		_apply_vr_tree_lods(outdoor)
	print("RENDER_BUDGET_READY: fern_instances=", total, " batches=", groups.size())

func _apply_vr_tree_lods(outdoor: Node3D) -> void:
	var close_range := 10.0
	var mid_range := 24.0
	var library := (load("res://assets/environment/vr_tree_lods.glb") as PackedScene).instantiate()
	var meshes: Dictionary = {}
	for node in library.find_children("*", "MeshInstance3D", true, false):
		meshes[str(node.name)] = node.mesh
		for surface in range(node.mesh.get_surface_count()):
			var material := node.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.resource_name.contains("leaves"):
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.33
	for node in outdoor.find_children("*", "MeshInstance3D", true, false):
		var tree := node as MeshInstance3D
		var label := str(tree.name)
		if label.begins_with("WoodlandTree_") or label.begins_with("GroveTree_"):
			# 近处继续使用原网格，新增实例共享资源，仅在 10 m 内显示。
			var close := MeshInstance3D.new()
			close.name = "VRClose_" + label
			close.mesh = tree.mesh
			close.transform = tree.transform
			close.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			close.visibility_range_end = close_range
			tree.get_parent().add_child(close)
			tree.mesh = meshes.VRTree_Mid
			tree.visibility_range_begin = close_range
			tree.visibility_range_begin_margin = 0.0
			if label.begins_with("WoodlandTree_"):
				tree.visibility_range_end = mid_range
				tree.visibility_range_end_margin = 0.0
		elif label.begins_with("DistantTree_"):
			tree.mesh = meshes.VRTree_Far
			tree.visibility_range_begin = mid_range
			tree.visibility_range_begin_margin = 0.0
		elif label.begins_with("YoungTree_"):
			tree.mesh = meshes.VRTree_Mid
		elif label.begins_with("ShadowTree_"):
			tree.mesh = meshes.VRTree_Shadow
	library.free()
	set_meta("vr_tree_lods", true)
	print("VR_TREE_LODS_READY: close=",close_range,"m mid=",mid_range,"m")

static func prepare_character_materials(people: Node) -> void:
	for node in people.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for index in range(mesh.mesh.get_surface_count()):
			var material := mesh.mesh.surface_get_material(index) as BaseMaterial3D
			if material != null and material.resource_name.begins_with("PersonHair_"):
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = 0.3
