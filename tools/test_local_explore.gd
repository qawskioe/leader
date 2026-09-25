extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("local explore test timeout");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	sim.enabled=false
	var id:="person_003"
	var actor: Dictionary=sim.actors[id]
	var origin: Vector3=actor.body.global_position
	var revision: int=sim.perception.revisions[id]
	sim.perception._record(id,"surface/person/"+id,"surface",origin+Vector3(0.3,0,0),true,{"anchor_person":id})
	sim.perception._record(id,"surface/person/"+id,"surface",origin+Vector3(0,0,0.3),true,{"anchor_person":id})
	assert(sim.perception.revisions[id]==revision,"转身导致脚边参考点变化不等于发现新物资，不能重新触发需求判断")
	sim.perception._record(id,"test_visible_food","fruit",origin+Vector3(1,0,1),true)
	assert(sim.perception.revisions[id]>revision,"真正发现物品仍应触发知识变化")
	# 远处食物线索不能劫持附近找工具的通用探索。
	sim.perception.memories[id]["distant_food"]={"id":"distant_food","kind":"forage_area","position":[-9,0.4,48],"available":true,"visible_now":false,"observed_at_seconds":-1.0}
	actor.intent="explore";actor.stage="scanning";actor.elapsed=3.0;actor.scan_phase=0
	actor.search_before=sim.perception.revisions.get(id,0)
	sim._scan(id,0)
	assert(actor.stage=="exploring" and not actor.path.is_empty())
	assert(origin.distance_to(actor.path[-1])<7.0,"附近探索不应自动前往远处果林")
	var results: Array=[]
	sim.action_result.connect(func(r):results.append(r))
	actor.scan_phase=1;actor.elapsed=3.0
	sim._scan(id,0)
	assert(results.size()==1 and not results[0].message.contains("可采果实"),"不能拿旧果实记录冒充本次发现")
	assert(results[0].scope=="local_search_only" and not results[0].search.target_directed,"局部搜索成功不能暗示已按任务目标寻路")
	assert(results[0].search.movement_target_distance_m==[4,6])
	print("LOCAL_EXPLORE_PASSED nearby_route_truthful_result")
	scene.queue_free();await process_frame;quit()
