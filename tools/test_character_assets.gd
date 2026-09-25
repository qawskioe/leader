extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for index in range(1,5):
		var model: Node3D = load("res://assets/characters/person_v2_%02d.glb" % index).instantiate()
		root.add_child(model)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		assert(skeleton.get_bone_count() == 18)
		for name in ["Root", "Hips", "Head", "Hand.R", "Hand.L", "Foot.R", "Foot.L"]:
			assert(skeleton.find_bone(name) >= 0)
		var animation := model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		for clip in ["Idle", "Walk"]:
			assert(animation.has_animation(clip))
			animation.play(clip)
			for time in [0.0,0.25,0.5,0.75]:
				animation.seek(time,true)
				for bone in range(18): assert(skeleton.get_bone_global_pose(bone).is_finite())
		var triangles := 0
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh
			assert(mesh != null and mesh.get_surface_count() > 0)
			for surface in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface)
				triangles += arrays[Mesh.ARRAY_INDEX].size() / 3
		assert(triangles < 60000, "角色超过本次几何预算")
		print("CHARACTER_ASSET_OK id=", index, " bones=18 triangles=", triangles)
		model.queue_free()
		await process_frame
	print("CHARACTER_ASSETS_PASSED")
	quit()
