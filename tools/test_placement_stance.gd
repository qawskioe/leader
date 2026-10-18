extends SceneTree
## 隔离世界操作夹具：站位调整保留人物选定落点及真实碰撞，不调用云端。
const ACTOR_ID:="person_003"
var scene: Node3D
var sim: Node
var actor: CharacterBody3D
var objects: Node
var api: Node
var selected: Vector3

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(30).timeout.connect(func():push_error("placement stance timeout");quit(1))
	for object_id in ["water_bag/2","basket/1"]:
		await prepare(object_id)
		var result: Dictionary=await api.request("move_held",arguments(object_id))
		assert(result.ok and result.stance_adjusted,str(result))
		var bottom: Vector3=objects.bottom(object_id)
		assert(Vector2(bottom.x-selected.x,bottom.z-selected.z).length()<.001)
		assert(absf(bottom.y-selected.y-.015)<.001)
		assert(objects.release_contacts(object_id).is_empty())
		assert((await api.request("release",{"object":object_id})).ok)
		assert(objects.objects[object_id].holder=="")
		await cleanup()
	# 原内置技能仍会接近至0.45米；整条Luau链应自然受益，不改技能的距离参数。
	await prepare("water_bag/2",1.1)
	var service:=preload("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
	var runtime:=preload("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;scene.add_child(runtime)
	api.cancel() # 交由真实运行时重新取得执行权。
	var placed: Dictionary=await runtime.run(FileAccess.get_file_as_string("res://data/skills/place_object.luau"),arguments("water_bag/2"),{},api,["observe","surface","approach","move_held","release","check_placement"])
	assert(placed.status=="completed" and placed.returned.ok,str(placed))
	var adjusted_steps: Array=placed.trace.filter(func(step):return step.operation=="move_held" and step.result.get("stance_adjusted",false))
	assert(adjusted_steps.size()==1)
	assert(objects.objects["water_bag/2"].holder=="")
	assert(Vector2(objects.bottom("water_bag/2").x-selected.x,objects.bottom("water_bag/2").z-selected.z).length()<.01)
	await cleanup()
	for kind in ["person","environment"]:
		await prepare("water_bag/2")
		var blocker: CollisionObject3D=CharacterBody3D.new() if kind=="person" else StaticBody3D.new()
		blocker.collision_layer=2 if kind=="person" else 1
		scene.add_child(blocker)
		var shape:=CollisionShape3D.new()
		var box:=BoxShape3D.new();box.size=Vector3(.1,.3,.1)
		shape.shape=box;blocker.add_child(shape)
		blocker.global_position=selected+Vector3(.18,.2,0)
		await physics_frame
		var before:=actor.global_position
		var result: Dictionary=await api.request("move_held",arguments("water_bag/2"))
		assert(not result.ok and result.code=="placement_blocked",str(result))
		assert(result.contacts.has(kind),str(result))
		assert(actor.global_position.distance_to(before)<.01)
		assert(objects.objects["water_bag/2"].holder==ACTOR_ID)
		await cleanup()
	await prepare("water_bag/2")
	var wall:=StaticBody3D.new();scene.add_child(wall)
	var wall_shape:=CollisionShape3D.new()
	var wall_box:=BoxShape3D.new();wall_box.size=Vector3(2,2,.1)
	wall_shape.shape=wall_box;wall.add_child(wall_shape)
	wall.global_position=actor.global_position+Vector3(0,1,-.36)
	await physics_frame
	var blocked: Dictionary=await api.request("move_held",arguments("water_bag/2"))
	assert(not blocked.ok and blocked.code=="stance_blocked",str(blocked))
	assert(objects.objects["water_bag/2"].holder==ACTOR_ID)
	assert(objects.objects["water_bag/2"].attachment_frame=="body")
	await cleanup()
	await prepare("water_bag/2")
	cancel_when_moving.call_deferred()
	var cancelled: Dictionary=await api.request("move_held",arguments("water_bag/2"))
	assert(not cancelled.ok and cancelled.code=="cancelled",str(cancelled))
	assert(objects.objects["water_bag/2"].holder==ACTOR_ID)
	assert(sim.actors[ACTOR_ID].stage=="idle")
	await cleanup()
	print("PLACEMENT_STANCE_PASSED water_bag_basket_same_target_luau_chain_peer_wall_blocked_retreat_cancel")
	quit()

func prepare(object_id: String, distance: float=.45) -> void:
	scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","",true).is_empty())
	sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	# 平地夹具隔离站位问题；原洞穴凹凸地面仍可合法拒绝宽物体放置。
	var floor_body:=StaticBody3D.new();scene.add_child(floor_body)
	var floor_shape:=CollisionShape3D.new()
	var floor_box:=BoxShape3D.new();floor_box.size=Vector3(10,.2,10)
	floor_shape.shape=floor_box;floor_body.add_child(floor_shape)
	floor_body.global_position=Vector3(0,9.9,3)
	actor=sim.actors[ACTOR_ID].body
	actor.global_position=Vector3(0,10.1,3);actor.rotation.y=0
	for other in sim.actors:
		if other!=ACTOR_ID:sim.actors[other].body.global_position+=Vector3(8,0,0)
	for frame in 20:await physics_frame
	objects=sim.world_objects
	var item: Dictionary=objects.objects[object_id]
	assert(objects.attach_to(object_id,ACTOR_ID,"Hand.R",func():return objects.carry_transform(object_id,actor,"Hand.R")).ok)
	api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id=ACTOR_ID;api.objects=objects;scene.add_child(api)
	assert(api.acquire().ok)
	var point: Vector3=actor.global_position+Vector3(0,0,distance)
	var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.3,1,[actor.get_rid(),item.body.get_rid()]))
	assert(not hit.is_empty())
	selected=hit.position

func arguments(object_id: String) -> Dictionary:
	return {"object":object_id,"seconds":.2,"target":{"observation_id":api.observation_id,"position":sim.space.local_point(ACTOR_ID,api.observation_id,selected)}}

func cancel_when_moving() -> void:
	while sim.actors[ACTOR_ID].stage!="skill_moving":await physics_frame
	api.cancel()

func cleanup() -> void:
	await api.finish()
	scene.queue_free();await create_timer(.1).timeout
