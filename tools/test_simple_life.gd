extends SceneTree
func _initialize():run.call_deferred()
func run():
 create_timer(30).timeout.connect(func():push_error("simple life timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://simple_life_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 var actor: Dictionary=sim.actors.person_003
 actor.body.global_position=sim.STORAGE+Vector3(0,.06,-.8);actor.body.rotation.y=0
 for i in 12:await physics_frame
 sim.perception.observe("person_003")
 var life=sim.life_world
 # 复现正常游玩：右手握篮子，左手空闲仍应能取食。
 var block:=RigidBody3D.new();scene.add_child(block);sim.world_objects.register_object("occupied_right",block)
 assert(sim.world_objects.attach_to("occupied_right","person_003","Hand.R",func():return actor.body.global_transform).ok)
 var left_take: Dictionary=life.take_unit("person_003","storage")
 print("FREE_LEFT_TAKE ",left_take)
 assert(left_take.ok,"右手占用不能阻止空着的左手取物")
 assert(life.held_unit("person_003").hand=="Hand.L")
 assert(not sim.water.free_hand("person_003","Hand.L") and not sim.water.free_hand("person_003","Hand.R"))
 var saved: Dictionary=load("res://scripts/skills/verification_snapshot.gd").capture(sim,"person_003")
 assert(saved.hands.person_003.hand=="Hand.L")
 assert(life.put_unit("person_003","storage").ok)
 var stop_api=load("res://scripts/skills/luau_world_adapter.gd").new();stop_api.sim=sim;stop_api.person_id="person_003";stop_api.objects=sim.world_objects;scene.add_child(stop_api)
 assert(stop_api.acquire().ok)
 stop_api.cancel()
 print("CANCEL_HELD_OBJECT ",sim.world_objects.objects.occupied_right.holder)
 assert(sim.world_objects.objects.occupied_right.holder=="person_003","停止动作不能松开此前持有的物品")
 assert(sim.world_objects.objects.occupied_right.hand=="Hand.R" and sim.world_objects.objects.occupied_right.body.freeze)
 assert(actor.stage=="idle" and not stop_api._owned)
 var service=load("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
 var runtime=load("res://scripts/skills/luau_runtime.gd").new();runtime.service=service;scene.add_child(runtime)
 var fault: Dictionary=await runtime.run('return function() error("fixture_failure") end',{},{},stop_api,[])
 assert(fault.status=="error" and str(fault.code).contains("fixture_failure"))
 assert(sim.world_objects.objects.occupied_right.holder=="person_003" and actor.stage=="idle","执行器报错不能额外改变持有物归属")
 runtime.queue_free();service.queue_free()
 stop_api.queue_free()
 assert(sim.world_objects.release("occupied_right","person_003").ok)
 var before: int=sim.storage_food
 assert(life.take_unit("person_003","storage").ok)
 assert(sim.storage_food==before-1)
 assert(life.take_unit("person_003","storage").code=="hand_occupied")
 assert(life.put_unit("person_003","storage").ok and sim.storage_food==before)
 actor.body.position.z-=4
 sim.perception.observe("person_003")
 assert(not life.take_unit("person_003","storage").ok and sim.storage_food==before)
 actor.body.global_position=sim.STORAGE+Vector3(0,.06,-.8)
 sim.perception.observe("person_003")
 assert(life.take_unit("person_003","storage").ok)
 store.people.person_003.needs.hunger=80
 var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id="person_003";api.objects=sim.world_objects;scene.add_child(api);assert(api.acquire().ok)
 create_timer(.1).timeout.connect(func():api.cancel())
 var cancelled: Dictionary=await api.request("consume_unit",{})
 assert(cancelled.code=="cancelled" and not life.held_unit("person_003").is_empty() and store.people.person_003.needs.hunger==80)
 assert(api.acquire().ok)
 assert((await api.request("consume_unit",{})).ok)
 assert(life.held_unit("person_003").is_empty() and store.people.person_003.needs.hunger==35)
 assert(life.consume_unit("person_003").code=="empty_hand")
 # 隔离布置水袋与水源，验证同一套内容物结算，不通过容器口接触。
 var bag: Dictionary=sim.water.bags["1"]
 bag.body.global_position=actor.body.to_global(Vector3(.3,.8,.5));bag.body.linear_velocity=Vector3.ZERO
 assert(sim.world_objects.grasp("water_bag/1","person_003","Hand.L",api.body_state).ok)
 actor.body.global_position=sim.water.SOURCE+Vector3(0,.1,-.7);actor.body.rotation.y=0
 for i in 12:await physics_frame
 sim.perception.observe("person_003")
 var source:=""
 for key in life.supplies:
  if life.supplies[key].flowing:source=key;break
 assert(not source.is_empty())
 var filled: Dictionary=await api.request("fill_container",{"source":source,"target":"water_bag/1"})
 print("SIMPLE_FILL_RESULT ",filled)
 assert(filled.ok and bag.contents.count>0)
 var water_before: int=bag.contents.count
 store.people.person_003.needs.thirst=80
 assert((await api.request("consume_contents",{"object":"water_bag/1"})).ok)
 assert(bag.contents.count==water_before-1 and store.people.person_003.needs.thirst<40)
 actor.body.position.z-=5
 sim.perception.observe("person_003")
 assert(not life.fill_container("person_003",source,"water_bag/1").ok)
 assert(bag.contents.count==water_before-1)
 await api.finish()
 print("SIMPLE_LIFE_PASSED take_store_range_cancel_consume_conservation_no_contact")
 scene.queue_free();await create_timer(.1).timeout;quit()
