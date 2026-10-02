extends SceneTree
## 隔离采果回归：仅初始化临时世界和技能库，不改原技能或正常人物状态。
var controller: Node
var sim: Node
var refs: Dictionary={}
var person:="person_003"
var _next_report:=0
func _process(_delta: float) -> bool:
	if is_instance_valid(controller) and Time.get_ticks_msec()>_next_report:
		_next_report=Time.get_ticks_msec()+15000
		print("GATHER_PROGRESS storage=",sim.storage_food," harvested=",sim.gathering.harvested," actor=",sim.actors[person].body.global_position)
		for runtime in controller.active.values():
			if is_instance_valid(runtime.runner) and not runtime.runner.trace.is_empty():
				var step: Dictionary=runtime.runner.trace[-1]
				print("GATHER_LAST_OP ",step.operation," ",step.result.get("code",""))
	return false
func _initialize() -> void: run.call_deferred()
func invoke(id: String, args: Dictionary={}) -> Dictionary:
	var submitted: Dictionary=controller.invoke(person,"life_"+id+"_"+str(Time.get_ticks_usec()),{"ref":refs[id],"arguments":args})
	assert(submitted.ok,JSON.stringify(submitted))
	var outcome: Dictionary=await controller.finished
	print("LIFE_RESULT ",id," ",JSON.stringify(outcome.runtime.get("returned",{"code":outcome.runtime.get("code"),"success":outcome.success})))
	return outcome
func run() -> void:
	create_timer(1100 if (OS.get_cmdline_user_args().has("--revise-live") or Array(OS.get_cmdline_user_args()).any(func(a):return a.begins_with("--resume-revision="))) else 240).timeout.connect(func():push_error("life skills timeout");quit(1))
	var snapshot: Dictionary={}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot-job="):
			var job: String=arg.trim_prefix("--snapshot-job=")
			assert(job.is_valid_identifier() and job.begins_with("job_"))
			var request: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://services/skill-runtime/runtime/jobs/"+job+"/build_request.json"))
			snapshot=request.verification_snapshot
			person=snapshot.person_id
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://gather_test_%d.json"%Time.get_ticks_usec(),true).is_empty())
	sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;sim.move_speed=4;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize_current("user://skills/gather_test_%d.json"%Time.get_ticks_usec()).is_empty())
	for definition in controller.library.describe(person):refs[controller.library.definitions[definition.ref].id]=definition.ref
	assert(refs.has("eat") and refs.has("gather_food") and refs.has("fetch_water"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resume-revision="):
			var job: String=arg.trim_prefix("--resume-revision=")
			assert(job.begins_with("job_") and "/" not in job and "\\" not in job)
			var request: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://services/skill-runtime/runtime/jobs/"+job+"/build_request.json"))
			assert(request.revision.ref==refs.gather_food,"只能续验同一版本，不能套用过期现场")
			preload("res://scripts/skills/verification_snapshot.gd").restore(sim,request.verification_snapshot)
			await revise_live({},sim.storage_food)
			return
	var actor: Node3D=sim.actors[person].body
	if snapshot.is_empty():
		actor.global_position=sim.gathering.baskets["1"].root.global_position+Vector3(0,0.1,-0.8);actor.rotation.y=0
	else:
		preload("res://scripts/skills/verification_snapshot.gd").restore(sim,snapshot)
	for frame in 30:await physics_frame
	if OS.get_cmdline_user_args().has("--right-hand"):
		var held: Dictionary=await invoke("take_in_hand",{"object":"basket/1","hand":"Hand.R"})
		assert(held.success)
	var before: int=sim.storage_food
	var outcome: Dictionary=await invoke("gather_food")
	if not outcome.success:
		var file:=FileAccess.open("res://services/text-gateway/runtime/life_failure.json",FileAccess.WRITE);file.store_string(JSON.stringify(outcome,"  "));file.close()
		if OS.get_cmdline_user_args().has("--revise-live"):
			await revise_live(outcome,before)
			return
		for key in sim.gathering.baskets:
			var basket: Dictionary=sim.gathering.baskets[key]
			var eye: Vector3=actor.global_position+Vector3(0,1.6,0)
			var at: Vector3=basket.root.global_position+Vector3(0,0.4,0)
			var query:=PhysicsRayQueryParameters3D.create(eye,at,1,[actor.get_rid(),basket.body.get_rid(),scene.get_node("Player").get_rid()])
			var hit: Dictionary=scene.get_world_3d().direct_space_state.intersect_ray(query)
			print("BASKET_DIAGNOSTIC ",key," actual=",at," actor=",actor.global_position," visible=",sim.perception.sees(person,at,basket.body.get_rid())," obstruction=",str(hit.collider.get_path()) if not hit.is_empty() else "none")
		push_error("gather failed");quit(1);return
	assert(sim.storage_food>before and sim.gathering.harvested>0)
	print("LIFE_GATHER_PASSED real_luau_gather_store")
	scene.queue_free();await create_timer(0.2).timeout;quit()

func revise_live(failed: Dictionary, initial_storage: int) -> void:
	# 明确的真实强模型隔离修订；不替代日常模型选择，不修改正常人物技能库。
	if not failed.is_empty():controller.store.record_execution(failed)
	var event:={"id":"fixture_gather_revision_%d"%Time.get_ticks_usec(),"speaker":"player","kind":"speech_intent","text":"依据刚才采果失败的真实证据修订采果方法：保持当前抓握时，原胸前目标会让篮子在终点与身体重叠。请自行选择可执行的目标或交互方式，完成实际装篮并带回储存；不能修改世界规则、绕过碰撞、伪造库存或重复失败坐标。保留当前已经摘下的食物和持物状态，先观察再决定。"}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--revision-feedback="):
			event.text+="\n"+FileAccess.get_file_as_string(arg.trim_prefix("--revision-feedback="))
	var requested: Dictionary=controller.request_revision(person,event,{"ref":refs.gather_food,"feedback":event.text})
	print("GATHER_REVISION_REQUEST ",JSON.stringify(requested))
	if not requested.ok:quit(1);return
	var learned: Dictionary=await controller.learning_finished
	print("GATHER_REVISION_LEARNED ",JSON.stringify(learned))
	if not learned.ok:quit(1);return
	assert(controller.invoke(person,"fixture_verify_gather_revision",{"ref":learned.ref,"arguments":{}}).ok)
	var result: Dictionary=await controller.finished
	var passed: bool=result.success and sim.storage_food>initial_storage
	var report:={"passed":passed,"job":requested.job,"learning":learned,"execution":result,"storage_before":initial_storage,"storage_after":sim.storage_food,"harvested":sim.gathering.harvested}
	var file:=FileAccess.open("res://services/skill-runtime/runtime/gather_revision_live.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("GATHER_REVISION_EXECUTED ",passed," storage=",sim.storage_food," result=",JSON.stringify(result.runtime.get("returned",{})))
	quit(0 if passed else 1)
