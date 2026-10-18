extends SceneTree
## 真实池边碰撞场景：已进入所选距离范围后不得追逐初始方向上的固定站位。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(40).timeout.connect(func():push_error("接近范围回归超时");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","user://approach_range_%d.json"%Time.get_ticks_usec(),true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var id:="person_004";var body: CharacterBody3D=sim.actors[id].body
	var points: Array[Vector2]=[Vector2(2.25,.75),Vector2(0,3),Vector2(2.25,.75)]
	for index in points.size():
		var point: Vector2=points[index]
		# 来自1791442064现场；只定位隔离角色，不读取/修改正式存档。
		body.global_position=Vector3(13.356574,.392345,62.458023);body.rotation.y=1.177660
		for frame in 5:await physics_frame
		var api:=preload("res://scripts/skills/luau_world_adapter.gd").new()
		api.sim=sim;api.person_id=id;api.objects=sim.world_objects;scene.add_child(api)
		assert(api.acquire().ok)
		var seen: Dictionary=await api.request("perceive",{})
		var position: Dictionary={}
		for sample in seen.near.ground_samples:
			if sample.state=="visible_surface" and absf(sample.probe.x-point.x)<.01 and absf(sample.probe.z-point.y)<.01:position=sample.position;break
		assert(not position.is_empty(),"夹具目标必须是真实可见的地面")
		var heading_before:=body.rotation.y
		var invalid: Dictionary=await api.request("approach",{"object":{"observation_id":seen.observation_id,"position":position},"keep_heading":"true"})
		assert(not invalid.ok and invalid.code=="invalid_keep_heading","朝向选项必须在动作开始前验证")
		if index==2:physics_frame.connect(api.cancel,CONNECT_ONE_SHOT)
		var arguments:={"object":{"observation_id":seen.observation_id,"position":position},"distance":.25}
		if index==0:arguments["keep_heading"]=true
		var result: Dictionary=await api.request("approach",arguments)
		print("APPROACH_RANGE_CASE ",point," ",JSON.stringify(result))
		if index==2:assert(not result.ok and result.code=="cancelled","范围移动仍须能取消")
		else:assert(result.ok and result.distance_to_selected_point_m<=.251,"实际已到范围内，不得继续追逐固定站位："+str(result))
		if index==0:assert(absf(angle_difference(heading_before,body.rotation.y))<.001,"侧走应保持身体和视野朝向")
		elif index==1:assert(absf(angle_difference(heading_before,body.rotation.y))>.01,"普通走路仍随移动方向转身")
		assert(not sim.actors[id].has("motion_stop_distance"),"运动结束不能把范围泄露到下次动作")
		assert(not sim.actors[id].has("keep_motion_heading"),"朝向选项不能泄露到下一次动作")
		await api.finish();api.queue_free();await physics_frame
	print("APPROACH_RANGE_PASSED actual_terrain, distance_contract, heading_choice, cancellation, cleanup; real_model_calls=0")
	scene.queue_free();await process_frame;quit()
