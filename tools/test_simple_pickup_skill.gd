extends SceneTree
func _initialize():run.call_deferred()
func run():
 create_timer(40).timeout.connect(func():push_error("simple skill timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://simple_pickup_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 var actor: Dictionary=sim.actors.person_003
 actor.body.global_position=sim.gathering.baskets["1"].root.global_position+Vector3(0,.06,-.8);actor.body.rotation.y=0
 for i in 12:await physics_frame
 sim.perception.observe("person_003")
 var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
 assert(controller.initialize_current("user://skills/simple_pickup_%d.json"%Time.get_ticks_usec()).is_empty())
 var ref:=""
 for entry in controller.library.describe("person_003"):
  if entry.id=="take_object":ref=entry.ref
 assert(not ref.is_empty())
 assert(controller.invoke("person_003","simple_pickup",{"ref":ref,"arguments":{"object":"basket/1"}}).ok)
 var result: Dictionary=await controller.finished
 print("SIMPLE_SKILL_RESULT ",result.success," ",result.runtime.get("returned"))
 assert(result.success)
 var operations: Array=[]
 for step in result.runtime.trace:
  operations.append(step.operation)
  assert(step.operation not in ["plan_grasp","reach_with_body","reach","pose","pose_bones","reach_point"],"普通拿取不得走精细骨骼链路")
 assert(sim.world_objects.objects["basket/1"].holder=="person_003")
 assert(sim.world_objects.release_contacts("basket/1").is_empty(),"固定持物槽不能与本人身体重叠")
 var api=load("res://scripts/skills/luau_world_adapter.gd").new();api.sim=sim;api.person_id="person_003";api.objects=sim.world_objects;scene.add_child(api);assert(api.acquire().ok)
 assert((await api.request("pose_bones",{"pose":{},"seconds":.2})).code=="unsupported_operation")
 assert(sim.world_objects.objects["basket/1"].attachment.is_valid(),"后续携带不能重新接回骨骼连接")
 var snapshots=load("res://scripts/skills/verification_snapshot.gd")
 var original: Transform3D=sim.world_objects.objects["basket/1"].body.global_transform
 var saved: Dictionary=JSON.parse_string(JSON.stringify(snapshots.capture(sim,"person_003")))
 snapshots.restore(sim,saved)
 sim.world_objects.sync_held("basket/1")
 assert(sim.world_objects.objects["basket/1"].body.global_transform.is_equal_approx(original))
 assert(sim.world_objects.objects["basket/1"].attachment.is_valid())
 var observation: Dictionary=await api.request("perceive",{})
 var placed:=false
 for sample in observation.near.ground_samples:
  if sample.state!="visible_surface":continue
  var p: Dictionary=sample.position
  var distance:=Vector2(p.x,p.z).length()
  if distance<.8 or distance>1.2:continue
  var target:={"observation_id":observation.observation_id,"position":p}
  var moved: Dictionary=await api.request("move_held",{"object":"basket/1","target":target,"seconds":.2})
  if not moved.ok:continue
  var released: Dictionary=await api.request("release",{"object":"basket/1"})
  assert(released.ok)
  var checked: Dictionary=await api.request("check_placement",{"object":"basket/1","target":target})
  print("SIMPLE_PLACEMENT_RESULT ",checked)
  assert(checked.ok)
  placed=true;break
 assert(placed,"附近可见地面必须存在一次成功放置")
 await api.finish()
 print("SIMPLE_PICKUP_SKILL_PASSED ",operations," placement_without_ik")
 scene.queue_free();await create_timer(.1).timeout;quit()
