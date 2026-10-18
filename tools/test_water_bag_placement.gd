extends SceneTree
## 离线真实地形回归：位置来自2026-10-13果树林脚边放袋失败；不恢复或写入正式存档。
const PERSON:="person_004"
const OBJECT:="water_bag/1"
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(20).timeout.connect(func():quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=preload("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","",true).is_empty())
	var sim=preload("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var actor: CharacterBody3D=sim.actors[PERSON].body
	actor.global_position=Vector3(-10.643301,0.515667,44.280712);actor.rotation.y=2.951324
	var objects: Node=sim.world_objects
	var item: Dictionary=objects.objects[OBJECT]
	for frame in 20:await physics_frame
	assert(objects.attach_to(OBJECT,PERSON,"Hand.R",func():return objects.carry_transform(OBJECT,actor,"Hand.R")).ok)
	var api=preload("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id=PERSON;api.objects=objects;scene.add_child(api)
	assert(api.acquire().ok)
	var point: Vector3=actor.global_position+actor.global_basis.z*.28
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.3,1,[actor.get_rid(),item.body.get_rid()]))
	assert(not hit.is_empty() and hit.normal.y>.8)
	var target: Dictionary={"observation_id":api.observation_id,"position":sim.space.local_point(PERSON,api.observation_id,hit.position)}
	var service=preload("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
	var runtime=preload("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;scene.add_child(runtime)
	api.cancel()
	var outcome: Dictionary=await runtime.run(FileAccess.get_file_as_string("res://data/skills/place_object.luau"),{"object":OBJECT,"target":target},{},api,["observe","surface","approach","move_held","release","check_placement"])
	var initial: Dictionary=outcome.get("returned",{})
	for frame in 180:await physics_frame
	var final: Dictionary=api.placement_result(OBJECT,target)
	var adjusted: bool=outcome.get("trace",[]).any(func(step):return step.operation=="move_held" and step.result.get("stance_adjusted",false))
	print("WATER_BAG_PLACEMENT_RESULT ",JSON.stringify({"runtime_status":outcome.status,"stance_adjusted":adjusted,"initial_ok":initial.get("ok",false),"initial_code":initial.get("code",""),"initial_speed":initial.get("speed",-1),"later_ok":final.ok,"later_horizontal_error":final.horizontal_error,"later_speed":final.speed}))
	var passed: bool=outcome.status=="completed" and initial.get("ok",false) and adjusted and final.ok and objects.objects[OBJECT].holder==""
	await api.finish();scene.queue_free();await process_frame;await process_frame
	if passed:print("WATER_BAG_PLACEMENT_PASSED actual_terrain_stance_adjustment_stays_near_target")
	quit(0 if passed else 1)
