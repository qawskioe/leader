extends SceneTree
func _initialize(): run.call_deferred()
func run():
 create_timer(15).timeout.connect(func():push_error("release location timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new()
 assert(store.initialize("res://data/people.json","user://release_location_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 sim.set_physics_process(false)
 var objects=load("res://scripts/skills/world_objects.gd").new();scene.add_child(objects)
 var body:=RigidBody3D.new();scene.add_child(body);objects.register_object("receipt_fixture",body)
 var actor: Node3D=sim.actors.person_003.body
 # 隔离夹具仅构造已持有物品；验证真实 release 入口，不冒充玩家拿取测试。
 assert(objects.attach_to("receipt_fixture","person_003","Hand.R",func():return Transform3D(Basis.IDENTITY,actor.global_position+Vector3.UP)).ok)
 var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id="person_003";api.objects=objects;scene.add_child(api)
 assert(api.acquire().ok)
 var result: Dictionary=await api.request("release",{"object":"receipt_fixture"})
 assert(result.ok and result.has("release_location"))
 assert(objects.objects.receipt_fixture.holder=="" and not body.freeze)
 assert(result.release_location.observation_id==api.observation_id)
 assert(is_equal_approx(result.release_location.grip_position.y,1))
 assert(not result.release_location.known_references.has("receipt_fixture"))
 var failed: Dictionary=await api.request("release",{"object":"receipt_fixture"})
 assert(not failed.ok and not failed.has("release_location"),"失败松手不得产生成功空间反馈")
 await api.finish()
 print("RELEASE_LOCATION_PASSED actual_release_local_frame_failure_no_receipt")
 scene.queue_free();await create_timer(.1).timeout;quit()
