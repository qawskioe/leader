extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	# 无界面夹具验证交互入口与世界状态；真实F/Q/G另在正常游戏中验证。
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store:=Store.new();assert(store.initialize().is_empty())
	var sim:=Sim.new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	var camera: Camera3D=player.get_node("Eyes")
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var at: Vector3=sim.water.bags["1"].root.global_position
	player.global_position=at+Vector3(0,0,1);camera.look_at(at)
	assert(sim.water.player_interact())
	assert(sim.water.held("player")=="1")
	camera.rotation=Vector3.ZERO
	await physics_frame;await physics_frame
	var held_local: Vector3=camera.to_local(sim.water.bags["1"].root.global_position)
	if held_local.z>=-0.5:
		push_error("桌面手持水袋没有位于摄像机前方："+str(held_local));quit(1);return
	camera.rotation.x=-0.6
	await physics_frame;await physics_frame
	assert(camera.to_local(sim.water.bags["1"].root.global_position).distance_to(held_local)<0.001,"俯仰后手持水袋仍应保持在视野中")
	player.global_position=sim.water.SOURCE+Vector3(0,0.5,1);camera.look_at(sim.water.SOURCE)
	assert(sim.water.player_interact())
	assert(sim.water.bags["1"].contents.count==3)
	assert(sim.water.drink("player"))
	assert(sim.water.bags["1"].contents.count==2)
	assert(sim.water.drop("player"))
	assert(sim.water.held("player")=="" and sim.water.bags["1"].contents.count==2)
	assert(sim.water.drawn==3 and sim.water.consumed==1)
	print("PLAYER_WATER_PASSED interaction_pickup_fill_drink_drop_camera_pose")
	scene.queue_free();await create_timer(0.2).timeout;quit()
