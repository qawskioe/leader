extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(35).timeout.connect(func():push_error("water object test timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true;voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	var sim=voice.survival;voice.skills.ensure_luau_world()
	var id: String="person_003"
	var bag: Dictionary=sim.water.bags["1"]
	bag.contents.clear();bag.contents.add({"source":"fixture"});bag.contents.add({"source":"fixture"})
	bag.body.global_position=sim.water.SOURCE+Vector3(0,1,0) # 离线接触夹具放在现有水边地面，不增加支撑或冻结。
	await create_timer(1.0).timeout # 等容器自然落稳后再安排接近，不冻结物体。
	var actor: CharacterBody3D=sim.actors[id].body
	actor.global_position=bag.root.global_position+Vector3(0,-0.25,-0.65);actor.rotation.y=0
	await physics_frame;await physics_frame
	sim.perception.observe(id)
	var observed: Dictionary=sim.perception.known(id,"water_bag/1")
	assert(observed.kind=="water_bag" and observed.extra.graspable and observed.extra.water==2,JSON.stringify(observed))
	# 这是身体接触/所有权夹具；移动目标的完整拿取仍需实际游玩验证。
	var adapter=load("res://scripts/skills/luau_world_adapter.gd").new();adapter.sim=sim;adapter.person_id=id;adapter.objects=sim.world_objects;scene.add_child(adapter)
	var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=voice.skills.luau_service;scene.add_child(runtime)
	var warm: Dictionary=await runtime.run("return function() return {ok=true} end",{},{},adapter,[])
	assert(warm.status=="completed")
	# 可抓握属性不能冒充接触；远处伸手必须保留实际距离且不能偷偷移动人物。
	# 远距反馈用独立静止目标，避免水边自由落体遮挡变成target_lost测试。
	var distant:=RigidBody3D.new();distant.freeze=true;scene.add_child(distant)
	distant.global_position=actor.to_global(Vector3(0,1.2,4))
	sim.world_objects.register_object("reach_fixture",distant)
	sim.perception.observe(id)
	var feet: Vector3=actor.global_position
	var remote: Dictionary=await runtime.run('return function(args) return world.request("reach",{object=args.object,hand="Hand.R",seconds=0.2}) end',{"object":"reach_fixture"},{},adapter,["reach"])
	assert(remote.status=="completed" and not remote.returned.ok,JSON.stringify(remote))
	assert(remote.returned.code=="reach_finished" and remote.returned.distance_m>2 and remote.returned.contact_limit_m==0.16,JSON.stringify(remote))
	assert("没有移动脚步" in remote.returned.message)
	assert(Vector2(actor.global_position.x,actor.global_position.z).distance_to(Vector2(feet.x,feet.z))<0.01)
	# 常驻服务已就绪后再布置接触，避免把首次进程启动期间的自由落体当成抓握失败。
	var motor=preload("res://scripts/skills/body_motor.gd").new();motor.initialize(sim.actors[id],id)
	sim.actors[id].animation.stop(true)
	motor.reach("Hand.R",actor.to_global(Vector3(-0.65,1.0,0.45)),true)
	bag.body.global_transform=Transform3D(Basis.IDENTITY,motor.point("Hand.R")-bag.grip)
	bag.body.linear_velocity=Vector3.ZERO;bag.body.angular_velocity=Vector3.ZERO
	sim.perception.observe(id)
	var source:="""return function(args)
local before=world.request("observe",{object=args.object})
local held=world.request("grasp",{object=args.object,hand="Hand.R"})
if not held.ok then return held end
local moved=world.request("pose_bones",{pose={["UpperArm.R"]={rotation={x=0,y=45,z=45}}},seconds=0.4})
if not moved.ok then return moved end
local after=world.request("observe",{object=args.object})
return {ok=true,before=before.grip_position,after=after.grip_position}
end"""
	var taken: Dictionary=await runtime.run(source,{"object":"water_bag/1"},{},adapter,["observe","grasp","pose_bones"])
	assert(taken.status=="completed" and taken.returned.ok,JSON.stringify(taken))
	var before: Dictionary=taken.returned.before;var after: Dictionary=taken.returned.after
	assert(Vector3(before.x,before.y,before.z).distance_to(Vector3(after.x,after.y,after.z))>0.05,"容器必须跟随真实骨骼动作")
	assert(sim.water.held(id)=="1" and voice.skills.world_objects.objects["water_bag/1"].holder==id)
	assert(not sim.water.pickup("person_002","1"),"同一水袋不能重复持有")
	assert(sim.water.drink(id) and bag.contents.count==1,"骨骼拿起的容器仍用同一份水量")
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	player.global_position=actor.global_position+Vector3(-1,0,0)
	assert(sim.water.give(id,"player").success)
	assert(sim.water.held(id)=="" and sim.water.held("player")=="1")
	assert(not sim.world_objects.held.keys().any(func(key):return str(key).begins_with(id+"/")))
	assert(sim.water.drop("player"))
	assert(bag.holder=="" and not bag.body.freeze and bag.body.collision_layer==4)
	var release_height: float=bag.body.global_position.y
	await create_timer(0.6).timeout
	assert(bag.body.global_position.y<release_height-0.1,"松手后按物理落下")
	assert(bag.body.global_position.y>-2,"不能掉进虚空")
	print("LUAU_WATER_OBJECT_PASSED shared_ownership_body_grasp_drink_transfer_physical_release")
	scene.queue_free();await create_timer(0.2).timeout;quit()
