extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("desktop basket timeout");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.enabled=false;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	var camera: Camera3D=player.get_node("Eyes")
	var gather=sim.gathering
	var basket: Dictionary=gather.baskets["1"]
	player.global_position=basket.root.global_position+Vector3(0,0,1.1)
	var fruit: MeshInstance3D=sim._fruit();scene.add_child(fruit)
	gather.hands.player={"material":"food","visual":fruit,"origin":{"resource_id":"fixture_fruit"},"hand":"Hand.R"}
	assert(gather.load_hand("player","1"))
	await physics_frame
	camera.look_at(fruit.global_position)
	var target: String=gather.aimed_target()
	assert(target=="contained/1/0","瞄准篮内果实必须选果实而非容器")
	assert(gather.take_from_basket("player","1",0))
	assert(basket.holder=="" and basket.contents.items.is_empty())
	assert(gather.hands.player.visual==fruit and gather.hands.player.origin.resource_id=="fixture_fruit")
	assert(not gather.take_from_basket("player","1",0),"同一果实不能取两次")
	assert(gather.load_player_hand(),"对准地上篮子时，桌面装篮入口必须使用该篮子")
	assert(basket.holder=="" and basket.contents.items.size()==1 and not gather.hands.has("player"))
	camera.look_at(basket.root.to_global(Vector3(0.38,0.5,0)))
	assert(gather.aimed_target()=="basket/1","瞄准篮沿仍能提篮")
	assert(sim.world_objects.attach_to("basket/1","person_001","Hand.L",gather.hold_pose.bind("person_001")).ok)
	camera.look_at(fruit.global_position)
	assert(not gather.aimed_target().begins_with("contained/"),"不能从别人手持的篮子直接取物")
	print("DESKTOP_BASKET_PASSED contents_rim_ownership_identity_no_duplication")
	scene.queue_free();await process_frame;quit()
