extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("content interaction timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	# 离线接触夹具固定现场；不声称已经有搬动/倾倒容器的完整技能动画。
	sim.set_physics_process(false);sim.gathering.set_physics_process(false);sim.water.set_physics_process(false);sim.world_objects.set_physics_process(false)
	var id:="person_003"
	sim.actors[id].body.global_position=Vector3(3,0,6);sim.actors[id].body.rotation.y=0
	var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id=id;api.objects=sim.world_objects;scene.add_child(api)
	var service=load("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
	var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;scene.add_child(runtime)
	var code:="""return function(args)
    local before=world.request("inspect_contents",{object=args.source})
    if not before.ok then return before end
    return world.request("transfer_contents",{source=args.source,target=args.target,quantity=1})
end"""
	for kind in ["water_bag","basket"]:
		var first: String=kind+"/1"
		var second: String=kind+"/2"
		var source: Dictionary=sim.content_interaction.containers[first].record
		var target: Dictionary=sim.content_interaction.containers[second].record
		if kind=="water_bag": source.body.freeze=true;target.body.freeze=true
		source.root.global_position=Vector3(3.3,0.3,6.7)
		target.root.global_position=source.root.global_position+Vector3(0.1,0,0.2)
		for index in 2:
			var item:={"origin":{"collector_id":id,"resource_id":"original_"+str(index)}}
			if kind=="basket":
				var visual: MeshInstance3D=sim._fruit();source.root.add_child(visual);item["visual"]=visual
			assert(source.contents.add(item).ok)
		if kind=="basket":sim.gathering._layout("1")
		await physics_frame
		sim.perception.observe(id)
		assert(sim.content_interaction.inspect(id,first).quantity==2)
		assert(sim.content_interaction.transfer(id,first,second,1).code=="source_not_held")
		assert(sim.water.pickup(id,"1") if kind=="water_bag" else sim.gathering.pickup(id,"1"))
		# 持有水袋时会更新其真实位置，目标开口据该现场对齐。
		target.root.global_position=source.root.global_position+Vector3(0.1,0,0.2)
		await physics_frame
		sim.perception.observe(id)
		var original: Dictionary=source.contents.items[0]
		var result: Dictionary=await runtime.run(code,{"source":first,"target":second},{},api,["inspect_contents","transfer_contents"])
		assert(result.status=="completed" and result.returned.ok,JSON.stringify(result))
		assert(source.contents.count==1 and target.contents.count==1 and is_same(target.contents.items[0],original))
		if kind=="basket":
			assert(original.visual.get_parent()==target.root,"真实食物外观必须随同一份内容物转到目标篮子")
			assert(target.contents.items[0].origin.resource_id=="original_0")
		# 在原型可伸手范围内但开口不接触，不能隔空转移。
		target.root.global_position=source.root.global_position+Vector3(0.8,0,0)
		await physics_frame
		sim.perception.observe(id)
		var rejected: Dictionary=sim.content_interaction.transfer(id,first,second,1)
		assert(rejected.code=="openings_not_in_contact" and source.contents.count==1 and target.contents.count==1,JSON.stringify(rejected))
		target.root.global_position=source.root.global_position+Vector3(0.1,0,0.2)
		await physics_frame;sim.perception.observe(id)
		target.holder="person_002"
		assert(sim.content_interaction.transfer(id,first,second,1).code=="held_by_other")
		target.holder=""
		while target.contents.free_space>0:
			var item:={"origin":{}}
			if kind=="basket":
				var visual: MeshInstance3D=sim._fruit();target.root.add_child(visual);item["visual"]=visual
			assert(target.contents.add(item).ok)
		assert(sim.content_interaction.transfer(id,first,second,1).code=="container_full")
		assert(source.contents.count==1)
		if kind=="water_bag":
			assert(sim.water.drink(id) and source.contents.count==0,"原生喝水必须消费同一内容物组件")
			assert(sim.water.drop(id))
		else:
			assert(sim._take_personal(id) and source.contents.count==0,"原生取食必须从同一内容物组件拿出")
			sim.actors[id].carried=0
	api._owned=true
	var inspected: Dictionary=await api.request("inspect_contents",{"object":"basket/1"})
	assert(inspected.ok and inspected.opening.observation_id==api.observation_id and inspected.opening.position is Dictionary,"开口信息必须使用本人的观察参照系")
	assert(not (await api.request("transfer_contents",{"source":"basket/1","target":"basket/2","quantity":0.5})).ok)
	assert(not (await api.request("inspect_contents",{"object":"basket/1","person_id":"person_002"})).ok)
	assert(not (await api.request("inspect_contents",{"object":"unseen_container"})).ok)
	api._owned=false
	print("CONTENT_INTERACTION_PASSED real_luau_water_food_identity_contact_capacity_ownership_consumption")
	scene.queue_free();await create_timer(0.2).timeout;quit()
