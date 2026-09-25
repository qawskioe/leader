extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();store.initialize()
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var actor: Dictionary=sim.actors.person_003
	actor.body.global_position=sim.water.SOURCE+Vector3(0,0.6,-0.45);actor.body.rotation.y=0
	for frame in 30: await physics_frame
	var objects=load("res://scripts/skills/world_objects.gd").new();scene.add_child(objects)
	var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id="person_003";api.objects=objects;scene.add_child(api)
	var service=load("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
	var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;scene.add_child(runtime)
	var motor=load("res://scripts/skills/body_motor.gd").new();motor.initialize(actor,"person_003")
	var source:=FileAccess.get_file_as_string("res://data/skills/take_and_release.luau")
	for id in ["container_fixture","tool_fixture"]:
		var body:=RigidBody3D.new();body.freeze=true;body.collision_layer=1;body.collision_mask=1;scene.add_child(body)
		var mesh:=MeshInstance3D.new();mesh.mesh=BoxMesh.new() if id=="tool_fixture" else CylinderMesh.new();mesh.scale=Vector3.ONE*0.1;body.add_child(mesh)
		var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3.ONE*0.1;shape.shape=box;body.add_child(shape)
		body.global_position=motor.point("Hand.R")+Vector3(0,0,0.06)
		objects.register_object(id,body)
		sim.perception._record("person_003",id,"interactable",body.global_position,true)
		await physics_frame
		var result: Dictionary=await runtime.run(source,{"object":id},{"self":"person_003"},api,["observe","reach","grasp","pose_bones","release"])
		assert(result.status=="completed" and result.returned.ok,JSON.stringify(result))
		assert(objects.objects[id].holder=="" and body.collision_layer==1 and body.freeze)
		assert(result.trace.filter(func(step):return step.operation!="host_restore_idle").size()==5)
		body.global_position+=Vector3(5,0,0)
	assert(api.acquire().ok)
	assert(not (await api.request("grasp",{"object":"tool_fixture","person_id":"person_002"})).ok)
	assert(not (await api.request("grasp",{"object":"unknown"})).ok)
	assert(not objects.grasp("tool_fixture","person_003","Hand.R",api.motor).ok,"不能隔空拿取")
	api.cancel()
	print("LUAU_WORLD_PASSED same_skill_two_shapes, contact_required, restore_collision, actor_scope; dispatch_max_ms=",service.max_dispatch_ms)
	scene.queue_free();await create_timer(0.2).timeout;quit()
