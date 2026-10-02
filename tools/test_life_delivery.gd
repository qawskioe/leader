extends SceneTree
## 独立同意夹具：测试真实物资守恒/帮助来源与消耗，接收决定使用明确的测试替身。
var facts: Array=[]
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(500).timeout.connect(func():push_error("delivery_timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/delivery_"+str(Time.get_ticks_usec())+".json").is_empty());assert(controller.library.install_builtins().is_empty())
	var refs: Dictionary={}
	for row in controller.library.describe("person_003"):refs[controller.library.definitions[row.ref].id]=row.ref
	sim.actors.person_003.body.global_position=sim.STORAGE+Vector3(0,0,-0.7);sim.actors.person_003.body.rotation.y=0
	sim.actors.person_002.body.global_position=sim.STORAGE+Vector3(1.3,0,-0.7);sim.actors.person_002.body.rotation.y=-PI/2
	for frame in 15:await physics_frame
	sim.actors.person_003.body.rotation.y=PI/2
	sim.perception.observe("person_003")
	sim.actors.person_003.body.rotation.y=0
	sim.perception.observe("person_003")
	sim.life_world.fact.connect(func(event:Dictionary):facts.append(event))
	sim.handover.offered.connect(func(event: Dictionary):sim.handover.respond.call_deferred(event.id,"person_002",true))
	sim.actors.person_003.assistance={"request_id":"help_fixture","requester_id":"person_002","helper_id":"person_003"}
	assert(controller.invoke("person_003","delivery",{"ref":refs.give_food,"arguments":{"source":"storage","recipient":"person_002"}}).ok)
	var given: Dictionary=await controller.finished
	if not given.success:push_error("delivery_failed "+JSON.stringify(given.runtime.get("returned",given.runtime.get("code"))));quit(1);return
	assert(sim.storage_food==2 and sim.gathering.hands.has("person_002") and not sim.gathering.hands.has("person_003"))
	assert(sim.gathering.hands.person_002.origin.request_id=="help_fixture")
	store.people.person_002.needs.hunger=80
	assert(controller.invoke("person_002","consume_received",{"ref":refs.eat,"arguments":{"source":"hand"}}).ok)
	var consumed: Dictionary=await controller.finished
	assert(consumed.success and sim.eaten==1 and sim.storage_food==2 and store.people.person_002.needs.hunger==35)
	assert(facts.any(func(f):return f.kind=="consumed" and f.origin.get("request_id")=="help_fixture"))
	print("FOOD_DELIVERY_PASSED selected_source_transferred_conserved_origin_consumed")
	if "--food-only" in OS.get_cmdline_user_args():
		scene.queue_free();await create_timer(.2).timeout;quit();return
	sim.actors.person_003.body.global_position=sim.water.bags["1"].root.global_position+Vector3(0,0.1,-0.8);sim.actors.person_003.body.rotation.y=0
	for frame in 15:await physics_frame
	assert(controller.invoke("person_003","water_delivery",{"ref":refs.give_water,"arguments":{"recipient":"person_002"}}).ok)
	var water: Dictionary=await controller.finished
	if not water.success:push_error("water_delivery_failed "+JSON.stringify(water.runtime.get("returned",water.runtime.get("code"))));quit(1);return
	assert(sim.water.held("person_002")!="" and sim.water.bags[sim.water.held("person_002")].contents.count>0)
	assert(facts.any(func(f):return f.kind=="given" and f.material=="water" and f.origin.get("request_id")=="help_fixture"))
	print("LIFE_DELIVERY_PASSED actual_unit_transferred_conserved_origin_consumed")
	scene.queue_free();await create_timer(.2).timeout;quit()
