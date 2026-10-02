extends SceneTree
## 隔离夹具：用正式Luau技能验证来源选择和物资守恒，不调用云端。
var controller: Node
var refs: Dictionary={}
func _initialize() -> void:run.call_deferred()
func invoke(skill: String, source: String) -> Dictionary:
	var submitted: Dictionary=controller.invoke("person_002","source_%d"%Time.get_ticks_usec(),{"ref":refs[skill],"arguments":{"source":source}})
	assert(submitted.ok,str(submitted))
	return await controller.finished
func run() -> void:
	create_timer(90).timeout.connect(func():push_error("food source timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","",true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/source_%d.json"%Time.get_ticks_usec()).is_empty())
	assert(controller.library.install_builtins().is_empty())
	for row in controller.library.describe("person_002"):refs[controller.library.definitions[row.ref].id]=row.ref
	var basket: Dictionary=sim.gathering.baskets["1"]
	for i in 2:assert(basket.contents.add({"material":"food","origin":{"resource_id":"source_choice_%d"%i}}).ok)
	var actor: Node3D=sim.actors.person_002.body
	actor.global_position=basket.root.global_position+Vector3(0,0,-0.9);actor.rotation=Vector3.ZERO
	for i in 10:await physics_frame
	sim.perception.observe("person_002")
	store.people.person_002.needs.hunger=90
	var outcome:=await invoke("eat","basket/1")
	assert(outcome.success,str(outcome.runtime.get("returned")))
	assert(basket.contents.count==1 and sim.storage_food==3 and sim.eaten==1)
	for step in outcome.runtime.trace:
		if step.operation in ["access_source","take_unit"]:assert(step.arguments.source=="basket/1")
	assert((await invoke("fetch_food","basket/1")).success)
	assert(basket.contents.count==0 and sim.storage_food==3 and sim.gathering.hands.person_002.origin.resource_id=="source_choice_1")
	assert((await invoke("eat","hand")).success)
	assert(sim.eaten==2 and not sim.gathering.hands.has("person_002"))
	var missing:=await invoke("eat","basket/1")
	assert(not missing.success and missing.runtime.returned.code=="content_missing")
	assert(sim.storage_food==3 and sim.eaten==2,"指定篮子空了不能改吃储食处")
	var empty_hand:=await invoke("eat","hand")
	assert(not empty_hand.success and empty_hand.runtime.returned.code=="no_food_in_hand")
	var water: RigidBody3D=sim.water.bags["1"].body
	water.freeze=true;water.global_position=actor.global_position+actor.global_basis.z*0.8+Vector3(0,0.2,0)
	sim.perception.observe("person_002")
	var wrong_material:=await invoke("eat","water_bag/1")
	assert(not wrong_material.success and wrong_material.runtime.returned.code=="source_not_food")
	assert(not sim.gathering.hands.has("person_002") and sim.water.consumed==0)
	print("FOOD_SOURCE_CHOICE_PASSED basket_one_each_hand_empty_wrong_material_no_storage_fallback")
	scene.queue_free();await process_frame;quit()
