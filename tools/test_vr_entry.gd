extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var rig_script = load("res://scripts/vr/player_rig.gd")
	assert(rig_script != null)
	assert(rig_script.horizontal_direction(Basis.IDENTITY, Vector2(0,1)).is_equal_approx(Vector3.FORWARD))
	assert(rig_script.horizontal_direction(Basis.IDENTITY, Vector2(1,0)).is_equal_approx(Vector3.RIGHT))
	assert(rig_script.horizontal_direction(Basis(Vector3.UP, PI/2), Vector2(0,1)).is_equal_approx(Vector3.LEFT))
	var scene = load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var player = scene.get_node("Player")
	assert(not player.is_vr_active(), "无设备测试不能意外激活 XR")
	assert(player.camera.current)
	# 在无设备环境构造跟踪姿态，验证兼容 Eyes 的位置与朝向同步。
	var rig = rig_script.new()
	player.add_child(rig)
	rig.head = XRCamera3D.new()
	rig.add_child(rig.head)
	rig.head.position = Vector3(0.3,1.4,-0.2)
	rig.head.rotation.y = 0.8
	rig.active = true
	rig.sync_head()
	assert(player.camera.global_transform.is_equal_approx(rig.head.global_transform))
	rig.active = false
	# 默认 OpenXR 映射必须包含代码使用的动作，保存版本固定的映射供启动使用。
	var map := load("res://vr_action_map.tres") as OpenXRActionMap
	var names: Array[String] = []
	for action_set in map.get_action_sets():
		for action in action_set.get_actions(): names.append(action.resource_name)
	assert("primary" in names and "trigger_click" in names, str(names))
	scene.queue_free()
	await process_frame
	print("VR_ENTRY_TEST passed: movement directions, desktop fallback, tracked head pose, action map")
	quit(0)
