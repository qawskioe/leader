extends SceneTree
## 验证森林接入、玩法锚点与洞内外环境切换；视觉检查另用真实渲染截图。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene: Node3D = load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody3D = scene.get_node("Player")
	player.set_physics_process(false)
	await process_frame
	await process_frame
	var outdoor := scene.get_node("Outdoor")
	assert(outdoor.find_children("WoodlandTree_*", "MeshInstance3D", true, false).size() == 145)
	for tree in outdoor.find_children("WoodlandTree_*", "MeshInstance3D", true, false):
		var distant: Node3D = outdoor.find_child(str(tree.name).replace("WoodlandTree_", "DistantTree_"), true, false)
		assert(distant != null and tree.global_transform.is_equal_approx(distant.global_transform), "树木 LOD 必须在同一位置")
	assert(outdoor.find_children("WoodlandFern_*", "MeshInstance3D", true, false).size() > 400)
	assert(outdoor.find_children("HarvestFruit_*", "MeshInstance3D", true, false).size() == 21)
	assert(outdoor.find_children("Basket_*_Base", "MeshInstance3D", true, false).size() == 2)
	assert(outdoor.find_child("Cenote_water", true, false) != null)
	var atmosphere := scene.get_node("ForestAtmosphere")
	assert(not atmosphere.environment.fog_enabled, "洞内不应出现森林雾")
	var indoor_energy: float = atmosphere.environment.ambient_light_energy
	player.position = Vector3(-1.1, 0.42, 26)
	await process_frame
	await process_frame
	assert(atmosphere.environment.fog_enabled)
	assert(not is_equal_approx(atmosphere.environment.ambient_light_energy, indoor_energy))
	for proxy in outdoor.find_children("Solid_ForestTrunk_*", "MeshInstance3D", true, false):
		assert(not proxy.visible and proxy.has_node("StaticCollision"))
	player.position = Vector3(0, 0.5, 8.4)
	await process_frame
	await process_frame
	assert(not atmosphere.environment.fog_enabled)
	assert(is_equal_approx(atmosphere.environment.ambient_light_energy, indoor_energy))
	print("FOREST_REFERENCE_PASSED: 145_trees, fern_understory, gameplay_anchors, trunk_collision, indoor_outdoor_transition")
	scene.queue_free()
	await process_frame
	quit()
