extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
const Cloud=preload("res://scripts/voice/cloud_client.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var store:=Store.new(); assert(store.initialize().is_empty())
	var sim:=Sim.new(); sim.scene=scene; sim.store=store; sim.enabled=false; scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var old: Variant=sim.perception.position_of("person_001","basket/1")
	assert(old!=null and not sim.perception.known("person_001","arrival_fruit_area").extra.has("food_count"))
	assert(sim.perception.nearest("person_001","fruit").is_empty())
	sim.gathering.baskets["1"].root.position.x+=20
	sim.perception.reset(); sim.perception.seed_arrival(sim.actors.keys())
	assert(sim.perception.position_of("person_001","basket/1")==old,"开场回忆来自经历数据，不查询篮子实时位置")
	sim.perception.note_storage_action("person_001",1)
	var storage: Dictionary=sim.perception.known("person_001","storage")
	assert(storage.available and storage.extra.own_transfer==1 and storage.extra.food_count==null,"本人存放不能继续沿用空库存，也不能推断未观察的总量")
	var decision:={"intent":"none","recipient_id":"","speech_act":"statement","addressed_person":"","private_interpretation":"等一下","public_reply":"","speech_style":"","routing_reason":"等待","capability_gap":null}
	assert(Cloud.validate_decision(JSON.stringify(decision),true).ok)
	decision.public_reply="好"
	assert(not Cloud.validate_decision(JSON.stringify(decision),true).ok)
	print("ARRIVAL_KNOWLEDGE_PASSED: remembered_route_and_baskets, no_live_refresh, no_invented_fruit_count, silent_style_optional")
	scene.queue_free(); await create_timer(0.2).timeout; quit()
