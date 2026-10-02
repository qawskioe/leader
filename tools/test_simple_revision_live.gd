extends SceneTree
func _initialize():run.call_deferred()
func run():
 assert(OS.get_cmdline_user_args().has("--live"))
 create_timer(650).timeout.connect(func():push_error("simple skill timeout");quit(1))
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
 var release_ref:=""
 for entry in controller.library.describe("person_003"):
  if entry.id=="release_object":release_ref=entry.ref
 var event:={"id":"simple_release_revision","kind":"speech_intent","speaker":"player","text":"请检查并修订松手技能：按照简化交互规则直接松开本人持有的物品，不增加伸手、蹲下或骨骼步骤，保留现有参数与归属检查。"}
 var started: Dictionary=controller.request_revision("person_003",event,{"ref":release_ref,"feedback":event.text})
 assert(started.ok)
 print("SIMPLE_REVISION_JOB ",started.job)
 var learned: Dictionary=await controller.learning_finished
 print("SIMPLE_REVISION_RESULT ",JSON.stringify(learned))
 if not learned.ok:quit(1);return
 assert(controller.invoke("person_003","simple_release_after_learning",{"ref":learned.ref,"arguments":{"object":"basket/1"}}).ok)
 var released: Dictionary=await controller.finished
 assert(released.success and sim.world_objects.objects["basket/1"].holder=="")
 print("SIMPLE_REVISION_LIVE_PASSED ",started.job)
 scene.queue_free();await create_timer(.1).timeout;quit()
