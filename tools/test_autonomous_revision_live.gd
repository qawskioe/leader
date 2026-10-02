extends SceneTree
## 真实模型隔离回归：使用历史失败技能，不回退正常世界或修改当前默认方法。
const OUT="res://services/skill-runtime/runtime/autonomous_revision_live.json"
var evidence: Dictionary={}
func done(ok: bool, reason: String):
 evidence["passed"]=ok;evidence["reason"]=reason
 var f=FileAccess.open(OUT,FileAccess.WRITE);f.store_string(JSON.stringify(evidence,"  "));f.close()
 print("AUTONOMOUS_REVISION_LIVE ",ok," ",reason)
 quit(0 if ok else 1)
func _initialize():run.call_deferred()
func run():
 if "--live" not in OS.get_cmdline_user_args():done(false,"requires --live");return
 create_timer(600).timeout.connect(func():done(false,"deadline"))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new()
 assert(store.initialize("res://data/people.json","user://revision_live_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;sim.move_speed=4;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
 assert(controller.initialize("res://services/skill-runtime/runtime/autonomous_revision_library.json").is_empty())
 var id="person_002";var old_ref=store.people[id].available_skills[0].ref
 sim.actors[id].body.global_position=sim.STORAGE+Vector3(0,.06,-.96);sim.actors[id].body.rotation.y=0;sim.actors[id].body.velocity=Vector3.ZERO
 store.people[id].needs.hunger=80
 for i in 12:await physics_frame
 sim.perception.observe(id)
 var need={"id":"fixture_need","kind":"need_changed","speaker":"body","text":"你现在很饿，结合本人已知物资和能力自行处理。","listeners":[id]}
 store.hear(id,need)
 assert(controller.invoke(id,need.id,{"ref":old_ref,"arguments":{}}).ok)
 var failed: Dictionary=await controller.finished
 evidence["failure"]=failed
 if failed.success:done(false,"old method did not reproduce failure");return
 store.record_execution(failed)
 var event={"id":"fixture_execution_feedback","kind":"skill_progress","speaker":"world","listeners":[id],"original_event":need,"result":failed,"text":"刚才自主吃饭的实际执行失败了。依据本人经历与当前情况决定下一步。"}
 var gateway=load("res://scripts/voice/text_gateway_client.gd").new();root.add_child(gateway)
 var pipeline=load("res://scripts/voice/decision_pipeline.gd").new();root.add_child(pipeline);pipeline.store=store;pipeline.gateway=gateway;pipeline.space=sim.space
 var reports: Array=[];pipeline.report_ready.connect(func(r):reports.append(r))
 pipeline.run(event,{})
 await pipeline.completed
 evidence["reports"]=reports
 var decision: Dictionary=reports[0].get("decision",{})
 if not decision.get("revision_request") is Dictionary:done(false,"model did not choose revision; inspect actual decision");return
 var requested=controller.request_revision(id,event,decision.revision_request);evidence["request"]=requested
 if not requested.ok:done(false,requested.error);return
 print("AUTONOMOUS_REVISION_REQUESTED ",requested)
 var learned: Dictionary=await controller.learning_finished;evidence["learning"]=learned
 if not learned.ok:done(false,"revision not approved");return
 # 此处只验证新方法实际效果；不冒充日常模型自动续办的现场验收。
 var before: int=sim.storage_food
 assert(controller.invoke(id,"fixture_verify_revised",{"ref":learned.ref,"arguments":{}}).ok)
 var result: Dictionary=await controller.finished;evidence["revised_execution"]=result
 done(result.success and sim.storage_food==before-1 and store.people[id].needs.hunger==35,"real decision, revision, replay and revised execution")
