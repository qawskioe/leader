extends SceneTree
const Selector=preload("res://scripts/player_target_selector.gd")
func _initialize():run.call_deferred()
func run():
	create_timer(20).timeout.connect(func():push_error("player target selector timeout");quit(1))
	var camera:=Camera3D.new();root.add_child(camera)
	for reversed in [false,true]:
		var picker:=Selector.new(camera)
		var candidates: Array=[["source",Vector3(0,-1,-1.4)],["person",Vector3(0,0,-1)]]
		if reversed:candidates.reverse()
		for pair in candidates:picker.consider(pair[0],pair[1],2.6,.65)
		assert(picker.target=="person","准星人物优先于偏下方水源，不依赖类别遍历顺序")
	var picker:=Selector.new(camera)
	picker.consider("far",Vector3(0,0,-3),2.6,.65)
	picker.consider("behind",Vector3(0,0,1),2.6,.65)
	assert(picker.target.is_empty())
	picker.consider("container",Vector3(.2,0,-1),2.6,.94)
	picker.consider("content",Vector3(0,0,-1.1),2.6,0,.16)
	assert(picker.target=="content","真实内容物与容器也使用同一视线比较")
	# 实际世界中，NPC与水源同时处于旧宽锥体内；两个F入口须选同一人物。
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false);player.set_process(false)
	player.global_position=sim.water.SOURCE+Vector3(0,.1,-1)
	var actor: Node3D=sim.actors.person_003.body;actor.global_position=sim.water.SOURCE+Vector3(.4,.1,.1)
	var bag: Dictionary=sim.water.bags["1"];bag.root.global_position=player.global_position+Vector3(.4,.6,.2)
	assert(sim.water.pickup("player","1"))
	var eyes: Camera3D=player.get_node("Eyes");eyes.look_at(actor.global_position+Vector3.UP)
	assert(sim.water.player_target()=="water/offer/person_003")
	assert(sim.gathering.aimed_target()==sim.water.player_target(),"人物、容器、水源没有第二套类别优先顺序")
	eyes.look_at(sim.water.SOURCE)
	assert(sim.gathering.aimed_target()=="water/fill/1","重新瞄准水源仍可以取水")
	scene.queue_free();camera.queue_free();await process_frame
	print("PLAYER_TARGET_SELECTOR_PASSED insertion_order_aim_range_content_real_water_person")
	quit()
