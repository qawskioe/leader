extends SceneTree
## 无头验证 VR 专用树分级与现有碰撞/桌面路径；真实 XR 性能另测。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var budget = scene.get_node("RenderBudget")
	var outdoor = scene.get_node("Outdoor")
	var near_trees = outdoor.find_children("WoodlandTree_*", "MeshInstance3D", true, false)
	var far_trees = outdoor.find_children("DistantTree_*", "MeshInstance3D", true, false)
	assert(near_trees.size() == 145 and far_trees.size() == 145)
	assert(scene.static_collision_count == 324)
	assert(budget.get_meta("batched_ferns") == 817)
	if OS.get_cmdline_user_args().has("--profile-vr-trees"):
		assert(budget.get_meta("vr_tree_lods", false))
		for tree in near_trees:
			var close = tree.get_parent().get_node("VRClose_"+str(tree.name))
			assert(close.transform.is_equal_approx(tree.transform))
			assert(close.visibility_range_end == tree.visibility_range_begin)
			assert(tree.visibility_range_end == 24.0)
			assert(_triangles(close.mesh) > _triangles(tree.mesh))
		for tree in far_trees:
			assert(tree.visibility_range_begin == 24.0)
			assert(_triangles(tree.mesh) < 10000)
		for tree in outdoor.find_children("ShadowTree_*", "MeshInstance3D", true, false):
			assert(tree.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
			assert(_triangles(tree.mesh) < 3500)
	else:
		assert(not budget.get_meta("vr_tree_lods", false))
		assert(outdoor.find_children("VRClose_*", "MeshInstance3D", true, false).is_empty())
		assert(near_trees[0].visibility_range_end == 28.0)
		assert(_triangles(far_trees[0].mesh) > 80000)
	print("VR_RENDER_BUDGET_PASSED: vr=",budget.get_meta("vr_tree_lods",false)," tree transforms, ranges, triangle budgets, 324 colliders, 817 ferns")
	scene.queue_free()
	await process_frame
	quit()

func _triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in range(mesh.get_surface_count()):
		count += mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX].size()/3
	return count
