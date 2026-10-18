extends SceneTree
## 池边真实世界回归：预判保守时调用实际运动，不修改正式人物、物资或存档。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(90).timeout.connect(func():push_error("可见地面试走回归超时");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","user://navigation_trial_%d.json"%Time.get_ticks_usec(),true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var id:="person_004";var body: CharacterBody3D=sim.actors[id].body
	# 取自1791442064的池边停留点；这是隔离测试前提，不是玩家游玩。
	body.global_position=Vector3(13.356574,.392345,62.458023);body.rotation.y=1.177660
	for frame in 5:await physics_frame
	var api:=preload("res://scripts/skills/luau_world_adapter.gd").new()
	api.sim=sim;api.person_id=id;api.objects=sim.world_objects;scene.add_child(api)
	assert(api.acquire().ok)
	var observed: Dictionary=await api.request("walk_options",{})
	var confirmed:=0;var visible:=0
	for sample in observed.near.ground_samples:
		if sample.state!="visible_surface":continue
		visible+=1
		if sample.path_clear:confirmed+=1
	assert(visible>0 and confirmed==0,"须复现可见地面全部未确认的现场前提")
	await api.finish();api.queue_free();await physics_frame
	var controller:=preload("res://scripts/skills/controller.gd").new()
	controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/navigation_trial_%d.json"%Time.get_ticks_usec()).is_empty())
	assert(controller.library.install_builtins().is_empty());controller.sync_person(id)
	var ref:="";var drink_ref:=""
	for entry in controller.library.describe(id):
		if entry.id=="go_to_known":ref=entry.ref
		elif entry.id=="drink":drink_ref=entry.ref
	assert(not ref.is_empty() and not drink_ref.is_empty())
	assert(controller.invoke(id,"isolated_navigation_trial",{"ref":ref,"arguments":{"object":"water_source","distance":1.0}}).ok)
	var result: Dictionary=await controller.finished
	var distance:=Vector2(body.global_position.x-sim.water.SOURCE.x,body.global_position.z-sim.water.SOURCE.z).length()
	print("NAVIGATION_TRIAL_RESULT ",JSON.stringify({"success":result.success,"returned":result.runtime.get("returned",{}),"operation_counts":result.runtime.get("operation_counts",{}),"distance_to_source_m":distance,"visible":visible,"confirmed":confirmed}))
	assert(result.success and distance<=1.01,"观察到的平缓地面须可经真实移动到达，不能只因未确认预判退出")
	# 第二个隔离用例回到同一物理起点，让普通饮水组合自行调用新的共用方法。
	body.global_position=Vector3(13.356574,.392345,62.458023);body.rotation.y=1.177660
	for frame in 5:await physics_frame
	store.people[id].needs.thirst=80
	var consumed: int=sim.water.consumed
	assert(controller.invoke(id,"isolated_drink_trial",{"ref":drink_ref,"arguments":{}}).ok)
	var drunk: Dictionary=await controller.finished
	print("NAVIGATION_DRINK_RESULT ",JSON.stringify({"success":drunk.success,"consumed":sim.water.consumed-consumed,"thirst":store.people[id].needs.thirst,"operation_counts":drunk.runtime.get("operation_counts",{})}))
	assert(drunk.success and sim.water.consumed==consumed+1 and store.people[id].needs.thirst<40,"上层饮水须实际取水消费，不能只返回成功")
	assert(sim.gathering.hands.get(id,{}).is_empty(),"喝下的水不能留在手中重复消费")
	print("NAVIGATION_TRIAL_PASSED real_terrain, real_luau, conservative_preview, source_reached, water_consumed; real_model_calls=0")
	scene.queue_free();await process_frame;quit()
