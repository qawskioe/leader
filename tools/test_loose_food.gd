extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	sim.enabled=false
	var player: Node3D=scene.get_node("Player")
	player.set_physics_process(false)
	var gather=sim.gathering
	gather.set_process(false)
	var fruit: MeshInstance3D=sim._fruit();scene.add_child(fruit)
	fruit.global_position=player.global_position+Vector3(0.7,1.4,0)
	gather.hands.player={"visual":fruit,"origin":{"collector_id":"person_001"}}
	await physics_frame
	var y:=fruit.global_position.y
	assert(gather.drop_food("player"),"自由空间应能松手")
	assert(not gather.hands.has("player") and gather.loose_food.size()==1)
	assert(not gather.drop_food("player"),"不能重复生成")
	await create_timer(1.2).timeout
	var key: String=gather.loose_food.keys()[0]
	var body: RigidBody3D=gather.loose_food[key].body
	assert(body.global_position.y<y-0.2,"重力应让食物落下")
	assert(body.global_position.y>player.global_position.y-0.5,"实体地面应支撑食物")
	assert(gather.take_loose_food("player",key),"附近落地食物应能拾回")
	assert(gather.loose_food.is_empty() and gather.hands.player.visual==fruit)
	assert(gather.hands.player.origin.collector_id=="person_001","保留同一物品来源")
	assert(not gather.take_loose_food("player",key),"不能重复拾取")
	gather.reset();assert(gather.loose_food.is_empty() and gather.hands.is_empty())
	print("LOOSE_FOOD_PASSED gravity_ground_pickup_identity_no_duplicates")
	scene.queue_free();await process_frame;quit()
