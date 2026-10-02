extends SceneTree
## 隔离物理与真实Luau桥接，不调用云端模型。
func _initialize():run.call_deferred()
func collision(parent: Node3D, size: Vector3) -> void:
 var child:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;child.shape=shape;parent.add_child(child)
func run() -> void:
 create_timer(20).timeout.connect(func():push_error("settled test timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://settled_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 sim.set_physics_process(false)
 var actor: Node3D=sim.actors.person_003.body;actor.global_position=Vector3(100,2,100);actor.rotation.y=0
 var floor:=StaticBody3D.new();scene.add_child(floor);floor.position=Vector3(100,1.9,101);collision(floor,Vector3(4,.2,4))
 var item:=RigidBody3D.new();scene.add_child(item);item.position=Vector3(100,3,101);collision(item,Vector3(.2,.2,.2));sim.world_objects.register_object("settle_probe",item)
 if OS.get_cmdline_user_args().has("--basket"):
  floor.rotation.z=deg_to_rad(3)
  sim.world_objects.objects["settle_probe"].grip=Vector3(0,.55,0)
  var cylinder:=CylinderShape3D.new();cylinder.radius=.5;cylinder.height=.5
  item.get_child(0).shape=cylinder;item.get_child(0).position.y=.25
 sim.perception._record("person_003","settle_probe","interactable",item.global_position,true)
 var at:=item.global_transform
 assert(sim.world_objects.attach_to("settle_probe","person_003","Hand.L",func():return at).ok)
 await physics_frame
 var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id="person_003";api.objects=sim.world_objects;scene.add_child(api);assert(api.acquire().ok)
 assert((await api.request("check_settled",{"object":"settle_probe"})).code=="still_held")
 assert((await api.request("release",{"object":"settle_probe"})).ok)
 if OS.get_cmdline_user_args().has("--basket"):
  # 斜面静置夹具只验证支撑采样，不冒充篮子的动态落下验收。
  item.global_basis=floor.global_basis;item.global_position=floor.to_global(Vector3(0,.102,0));item.gravity_scale=0;item.linear_velocity=Vector3.ZERO;item.angular_velocity=Vector3.ZERO
 var settled: Dictionary=await api.request("check_settled",{"object":"settle_probe"})
 print("SETTLED_SLOPE_SUPPORT " if OS.get_cmdline_user_args().has("--basket") else "SETTLED_DROP ",settled)
 assert(settled.ok and settled.code=="settled" and settled.stable_seconds>=.3)
 if OS.get_cmdline_user_args().has("--basket"):
  print("SETTLED_SLOPE_PASSED static_cylinder_support_fixture")
  scene.queue_free();await create_timer(.1).timeout;quit();return
 assert(not settled.has("position") and not settled.has("target"),"不能透露被物体遮住的地面坐标")
 assert(api.placement_targets.is_empty(),"落稳检查不伪造指定目的地")
 assert((await api.request("check_settled",{"object":"unknown"})).code=="not_observed")
 item.gravity_scale=0;item.position=Vector3(100,2.7,101);item.linear_velocity=Vector3.ZERO;item.angular_velocity=Vector3.ZERO
 var floating: Dictionary=await api.request("check_settled",{"object":"settle_probe"})
 assert(not floating.ok and not floating.support_confirmed,"悬浮静止不能算落稳")
 item.gravity_scale=1;item.sleeping=false
 assert((await api.request("check_settled",{"object":"settle_probe"})).ok)
 await api.finish()
 var service=load("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
 var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;scene.add_child(runtime)
 var result: Dictionary=await runtime.run('return function(args,context) return world.request("check_settled",{object=args.object}) end',{"object":"settle_probe"},{"self":"person_003"},api,["check_settled"])
 assert(result.status=="completed" and result.returned.ok,JSON.stringify(result))
 assert(api.acquire().ok)
 var wall:=StaticBody3D.new();scene.add_child(wall);wall.position=Vector3(100,3,100.5);collision(wall,Vector3(2,3,.1));await physics_frame
 assert((await api.request("check_settled",{"object":"settle_probe"})).code=="not_observed","遮挡后不得获得物体当前状态")
 wall.queue_free();await physics_frame
 create_timer(.05).timeout.connect(api.cancel)
 assert((await api.request("check_settled",{"object":"settle_probe"})).code=="cancelled")
 print("SETTLED_PASSED drop_held_floating_unknown_occluded_cancel_luau_no_destination")
 scene.queue_free();await create_timer(.1).timeout;quit()
