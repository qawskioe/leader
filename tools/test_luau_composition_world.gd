extends SceneTree
## 离线接触夹具：验证正式控制器与真实刚体，不冒充玩家自然地面拿取或视觉验收。
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("composition_world_timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/composition_world_"+str(Time.get_ticks_usec())+".json").is_empty())
	assert(controller.library.install_builtins().is_empty())
	var dependencies: Dictionary={}
	for skill in controller.library.describe("person_003"):
		var definition: Dictionary=controller.library.definitions[skill.ref]
		if definition.id in ["take_object","release_object"]: dependencies[definition.id]=skill.ref
	var source:="""return function(args, context)
    local taken=skills.call("take_object",args,context)
    if not taken.ok then return taken end
    return skills.call("release_object",args,context)
end"""
	var definition:={"id":"test_take_release","name":"测试拿起再松手","description":"复用两个固定版本技能","parameters":{"object":"本人已知物品"},"dependencies":dependencies,"program_json":JSON.stringify(load("res://scripts/skills/luau_contract.gd").make_program(source,[]))}
	var raw:=JSON.stringify(definition)
	var registered: Dictionary=controller.library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok and controller.library.grant("person_003",registered.ref,"离线测试批准").is_empty())
	controller.sync_person("person_003");controller.ensure_luau_world()
	var actor: Dictionary=sim.actors.person_003
	var motor=load("res://scripts/skills/body_motor.gd").new();motor.initialize(actor,"person_003")
	for id in ["test_box","test_cylinder"]:
		var body:=RigidBody3D.new();body.freeze=true;body.collision_layer=4;body.collision_mask=7;scene.add_child(body)
		var collider:=CollisionShape3D.new();var shape:=SphereShape3D.new();shape.radius=0.05;collider.shape=shape;body.add_child(collider)
		var visual:=MeshInstance3D.new();visual.mesh=BoxMesh.new() if id=="test_box" else CylinderMesh.new();visual.scale=Vector3.ONE*0.1;body.add_child(visual)
		body.global_position=motor.point("Hand.R")+Vector3(0,0,0.06)
		sim.world_objects.register_object(id,body)
		sim.perception._record("person_003",id,"interactable",body.global_position,true)
		await physics_frame
		var submitted: Dictionary=controller.invoke("person_003",id,{"ref":registered.ref,"arguments":{"object":id}})
		assert(submitted.ok,JSON.stringify(submitted))
		var result: Dictionary=await controller.finished
		assert(result.success and not result.goal_verified,JSON.stringify(result))
		assert(not result.message.contains("世界状态验证通过"),"组合代码返回ok不等于拥有整体目标验收器")
		assert(sim.world_objects.objects[id].holder=="" and body.freeze and body.collision_layer==4 and body.collision_mask==7)
		var operations: Array=result.runtime.trace.map(func(step):return step.operation)
		assert("grasp" in operations and operations[-2]=="release" and operations[-1]=="host_restore_idle",JSON.stringify(operations))
		assert(actor.stage=="idle" and not actor.has("skill_owner"))
		body.global_position+=Vector3(5,0,0)
	# 新组合的接收者参数同样走通用人物认知检查，不添加技能名字分支。
	var give_ref:=""
	for skill in controller.library.describe("person_003"):
		if controller.library.definitions[skill.ref].id=="give_object": give_ref=skill.ref
	definition.id="test_take_give";definition.name="测试拿起递交"
	definition.parameters={"object":"本人已知物品","recipient":"本人已知人物"}
	definition.dependencies={"take":dependencies.take_object,"give":give_ref}
	source='return function(args,context) local r=skills.call("take",{object=args.object},context) if not r.ok then return r end return skills.call("give",args,context) end'
	definition.program_json=JSON.stringify(load("res://scripts/skills/luau_contract.gd").make_program(source,[]))
	raw=JSON.stringify(definition)
	registered=controller.library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok and controller.library.grant("person_003",registered.ref,"离线测试批准").is_empty())
	var object: RigidBody3D=sim.world_objects.objects.test_box.body
	object.global_position=motor.point("Hand.R")+Vector3(0,0,0.06)
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	player.global_position=actor.body.global_position+Vector3(0,0,1.4)
	sim.perception.observe("person_003")
	assert(not controller.invoke("person_003","unknown_recipient",{"ref":registered.ref,"arguments":{"object":"test_box","recipient":"unknown_person"}}).ok)
	var call: Dictionary=controller.invoke("person_003","take_give",{"ref":registered.ref,"arguments":{"object":"test_box","recipient":"player"}})
	assert(call.ok,JSON.stringify(call))
	var given: Dictionary=await controller.finished
	assert(given.success and sim.world_objects.objects.test_box.holder=="player",JSON.stringify(given))
	print("LUAU_COMPOSITION_WORLD_PASSED two_objects_one_actor_real_grasp_release")
	scene.queue_free();await create_timer(0.2).timeout;quit()
