extends SceneTree
var sim: Node
var controller: Node
var scene: Node3D
var object: RigidBody3D
var reference:=""
var interruption:=""
var interrupt_done:=false
var visual_index:=0
var cancelled_stage:=""
const PERSON="person_003"
const ORIGIN=Vector3(70,0,70)
func _initialize():call_deferred("run")
func fail(message: String) -> void:
 push_error(message);quit(1)
func call_pickup(event: String) -> Dictionary:
 var submitted: Dictionary=controller.invoke(PERSON,event,{"ref":reference,"arguments":{"object":"pickup_probe"}})
 assert(submitted.ok,str(submitted))
 if not controller.luau_service.message_received.is_connected(_on_service):controller.luau_service.message_received.connect(_on_service)
 var result: Dictionary=await controller.finished
 var returned: Dictionary=result.get("runtime",{}).get("returned",{})
 print("PICKUP_RESULT ",event," ",returned)
 print("PICKUP_TIMING ",event," ",result.runtime.get("elapsed_ms")," ",JSON.stringify(result.runtime.get("operation_elapsed_ms",{}))," ",JSON.stringify(result.runtime.get("operation_counts",{})))
 return result
func _on_service(event: Dictionary) -> void:
 if "--pickup-visual" in OS.get_cmdline_user_args() and event.get("type")=="world_request" and event.get("request",{}).get("operation")=="reach_with_body":_capture_reach()
 if interruption.is_empty() or interrupt_done or event.get("type")!="world_request" or event.get("request",{}).get("operation")!=("plan_grasp" if interruption=="cancel_plan" else "reach_with_body"):return
 interrupt_done=true
 cancelled_stage=event.request.operation
 if interruption=="cancel_plan":
  controller.cancel.call_deferred(PERSON);return
 await create_timer(.2).timeout
 if interruption=="cancel":controller.cancel(PERSON)
 elif interruption=="move":object.global_position=ORIGIN+Vector3(0,.12,-4)

func _capture_reach() -> void:
 await create_timer(1.5).timeout
 visual_index+=1
 await RenderingServer.frame_post_draw
 var path:="res://services/text-gateway/runtime/play-agent/pickup_pose_%d.png"%visual_index
 get_root().get_texture().get_image().save_png(path)
 print("PICKUP_CAPTURE ",ProjectSettings.globalize_path(path))

func reset_case(distance: float=1.4) -> void:
 sim.world_objects.release_person(PERSON)
 var actor: CharacterBody3D=sim.actors[PERSON].body
 actor.global_position=ORIGIN+Vector3(0,.05,0);actor.rotation.y=0;actor.velocity=Vector3.ZERO
 object.freeze=false;object.global_position=ORIGIN+Vector3(0,.12,distance);object.rotation=Vector3.ZERO;object.linear_velocity=Vector3.ZERO;object.angular_velocity=Vector3.ZERO
 for i in 20:await physics_frame
 sim.perception._record(PERSON,"pickup_probe","interactable",object.global_position,true)

func run():
 if DisplayServer.get_name()!="headless":assert("--outdoor-preview" in OS.get_cmdline_user_args(),"可视夹具必须关闭正常游戏自动启动")
 create_timer(240).timeout.connect(func():fail("automatic pickup timeout"))
 scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://pickup_memory_%d.json"%Time.get_ticks_usec(),true).is_empty())
 sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;sim.move_speed=3;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 var floor:=StaticBody3D.new();floor.collision_layer=1;floor.collision_mask=0
 var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(14,.2,14);shape.shape=box;floor.add_child(shape);scene.add_child(floor);floor.global_position=ORIGIN-Vector3(0,.1,0)
 if "--pickup-visual" in OS.get_cmdline_user_args():
  var surface:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(14,14);surface.mesh=plane;floor.add_child(surface);surface.position.y=.1
  var camera:=Camera3D.new();scene.add_child(camera);camera.global_position=ORIGIN+Vector3(3,1.8,3.8);camera.look_at(ORIGIN+Vector3(0,.8,1.3));camera.current=true
  var light:=OmniLight3D.new();scene.add_child(light);light.global_position=ORIGIN+Vector3(0,3,2);light.light_energy=1.0;light.omni_range=8
 object=RigidBody3D.new();object.collision_layer=4;object.collision_mask=7
 var collision:=CollisionShape3D.new();var mesh:=BoxShape3D.new();mesh.size=Vector3(.18,.2,.18);collision.shape=mesh;object.add_child(collision);scene.add_child(object);object.global_position=ORIGIN+Vector3(0,.12,2)
 var appearance:=MeshInstance3D.new();var cube:=BoxMesh.new();cube.size=Vector3(.18,.2,.18);appearance.mesh=cube;object.add_child(appearance)
 var color:=StandardMaterial3D.new();color.albedo_color=Color("df6d38");appearance.material_override=color
 sim.world_objects.register_object("pickup_probe",object,Vector3(0,.08,-.05))
 var actor: CharacterBody3D=sim.actors[PERSON].body
 actor.global_position=ORIGIN+Vector3(0,.05,0);actor.rotation.y=PI;actor.velocity=Vector3.ZERO
 for i in 30:await physics_frame
 sim.perception._record(PERSON,"pickup_probe","interactable",object.global_position,true)
 controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
 assert(controller.initialize_current("user://skills/pickup_%d.json"%Time.get_ticks_usec()).is_empty())
 for entry in controller.library.describe(PERSON):
  if controller.library.definitions[entry.ref].id=="take_object":reference=entry.ref
 assert(not reference.is_empty())
 if "--pickup-benchmark" not in OS.get_cmdline_user_args() and "--pickup-visual" not in OS.get_cmdline_user_args():
  actor.rotation.y=0
  sim.actors[PERSON].animation.pause()
  # 排除物理自然沉降；这里专门验证规划器本身没有写入世界状态。
  object.freeze=true
  var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id=PERSON;api.objects=sim.world_objects;scene.add_child(api)
  assert(api.acquire().ok)
  var before_pose: Dictionary=api.motor.bone_snapshot()
  var before_object:=object.global_transform
  var before_actor:=actor.global_transform
  var plan: Dictionary=await api.request("plan_grasp",{"object":"pickup_probe","hand":"Hand.L"})
  assert(plan.ok,str(plan))
  assert(api.motor.bone_snapshot()==before_pose,"预检不能摆动渲染骨架")
  assert(object.global_transform.is_equal_approx(before_object),"预检不能移动物品")
  assert(actor.global_transform.is_equal_approx(before_actor),"预检不能移动人物")
  assert(sim.world_objects.objects.pickup_probe.holder=="")
  print("PREFLIGHT_PURE_PASSED ",plan.planning_ms," ms total; ",plan.max_slice_ms," ms max slice")
  await api.finish();api.queue_free()
  object.freeze=false
  actor.rotation.y=PI
 var result:=await call_pickup("floor_two_meters_behind")
 if not result.success:
  var file:=FileAccess.open("res://services/text-gateway/runtime/play-agent/pickup_failure.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
  fail("automatic floor pickup failed");return
 assert(sim.world_objects.objects.pickup_probe.holder==PERSON)
 assert(result.runtime.operation_counts.get("reach_with_body",0)==1,"常见拿取必须只伸手一次")
 assert(actor.global_position.distance_to(ORIGIN)>.5,"程序自行走近")
 if "--pickup-visual" in OS.get_cmdline_user_args() or "--pickup-benchmark" in OS.get_cmdline_user_args():
  print("PICKUP_SINGLE_RUN_PASSED")
  scene.queue_free();await create_timer(.2).timeout;quit();return
 # 已经拿住再次调用不能走开或复制物品。
 var held_at:=actor.global_position
 var repeated:=await call_pickup("already_held")
 assert(repeated.success and actor.global_position.distance_to(held_at)<.01)
 await reset_case()
 for hand in ["Hand.L","Hand.R"]:
  var dummy:=RigidBody3D.new();scene.add_child(dummy)
  sim.world_objects.register_object(hand,dummy)
  assert(sim.world_objects.attach_to(hand,PERSON,hand,func():return actor.global_transform).ok)
 var start:=actor.global_position
 var occupied:=await call_pickup("hands_occupied")
 assert(not occupied.success and occupied.runtime.returned.code=="hands_occupied")
 assert(actor.global_position.distance_to(start)<.01,"手满时不得先走近")
 sim.world_objects.release_person(PERSON)
 await reset_case()
 interruption="move";interrupt_done=false
 var changed:=await call_pickup("target_moved")
 assert(not changed.success and changed.runtime.returned.code=="target_changed")
 assert(sim.world_objects.objects.pickup_probe.holder=="")
 await reset_case()
 interruption="cancel";interrupt_done=false
 var cancelled:=await call_pickup("cancel_during_reach")
 assert(not cancelled.success and sim.actors[PERSON].stage=="idle")
 assert(sim.world_objects.objects.pickup_probe.holder=="")
 assert(sim.actors[PERSON].skeleton.get_children().filter(func(node):return node is SkeletonModifier3D).is_empty(),"取消必须移除IK修改器")
 await reset_case()
 interruption="cancel_plan";interrupt_done=false
 var cancelled_plan:=await call_pickup("cancel_during_preflight")
 assert(not cancelled_plan.success and cancelled_stage=="plan_grasp")
 assert(sim.actors[PERSON].stage=="idle" and sim.world_objects.objects.pickup_probe.holder=="")
 print("AUTOMATIC_PICKUP_PASSED one_call, turn, approach, body_reach, grasp, already_held, hands_occupied, target_changed, cancellation, planning_cancel; model_calls=0")
 scene.queue_free();await create_timer(.2).timeout;quit()
