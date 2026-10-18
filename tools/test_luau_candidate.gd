extends SceneTree
## 候选代码只在此独立世界运行；可同时生成后台审查关键帧。
var folder: String
var motion: String
var review_camera: Camera3D
var framing_objects: Array[String]=[]
var view: SubViewport
var frames: Array=[]
var all_frames: Array=[]
var capture_serial:=0
var samples: Array=[]
var capturing:=false
var recording:=false
var start_ms:=0
var last_frame:=0
var label: Label
var stage:="准备"
var facts: Array=[]
var consent_fixture: Array=[]
var trace_log: FileAccess
var operation_serial:=0
var validation_case:="baseline"
var stopping_replay:=false
var invocation_active:=false
var invocation_serial:=0
var replay_scene: Node
var replay_runtime: Node
var timeout_report: Dictionary={}
var replay_budget_seconds:=0
var replay_budget_started_ms:=0
const Snapshot=preload("res://scripts/skills/verification_snapshot.gd")
const Journal=preload("res://scripts/skills/execution_journal.gd")
static func initial_request_progress(character_context: Dictionary, source_id: String) -> Array:
	# 编写上下文是无损压缩的发送副本；宿主日志只能读取解码后的真实记录及原始请求ID。
	var working:=preload("res://scripts/voice/prompt_history.gd").expand(character_context.get("working_context",{}))
	var task: Dictionary=working.get("task",{})
	return task.get("progress",[]) if task.get("request",{}).get("id")==source_id else []
var api: Node
var participants: Node
class ObservedWorld extends "res://scripts/skills/luau_world_adapter.gd":
	var observer: SceneTree
	var after_operations: Array=[]
	var cancel_after_operation: Dictionary={}
	var cancellation_checkpoint: Dictionary={}
	var successful_calls: Dictionary={}
	var transitions: Array=[]
	func finish() -> Dictionary:
		await observer.capture("宿主结束清理：开始连续恢复待机")
		var result: Dictionary=await super.finish()
		await observer.capture("宿主结束清理：恢复完成")
		return result
	func request(operation: String, args: Dictionary) -> Dictionary:
		observer.operation_serial+=1
		var serial: int=observer.operation_serial
		var started:=Time.get_ticks_msec()
		observer.record_partial({"type":"operation_started","request_id":serial,"operation":operation,"arguments":args})
		if observer.needs_action_frame(operation):await observer.capture(operation+" 开始")
		var result: Dictionary=await super.request(operation,args)
		observer.record_partial({"type":"operation_finished","request_id":serial,"step":{"operation":operation,"arguments":args,"result":result,"elapsed_ms":Time.get_ticks_msec()-started}})
		if result.get("ok",false):
			successful_calls[operation]=successful_calls.get(operation,0)+1
			for hook in after_operations:
				if hook.operation!=operation or hook.occurrence!=successful_calls[operation]:continue
				var applied: Dictionary=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,person_id,observer.verification_snapshot,hook.conditions,observer.participants)
				if not applied.ok:
					observer.record_setup_failure(applied,{"phase":"after_operation","operation":operation,"occurrence":hook.occurrence})
					push_error(applied.error);observer._stop_replay(1);return {"ok":false,"code":"verification_condition_failed"}
				var change:={"operation":operation,"occurrence":hook.occurrence,"after_result":result.duplicate(true),"preparation":applied.preparation}
				transitions.append(change);observer.record_partial({"type":"isolated_condition_applied","change":change})
			if not cancel_after_operation.is_empty() and cancel_after_operation.operation==operation and cancel_after_operation.occurrence==successful_calls[operation]:
				# 操作已实际结算，取消真实运行器；未执行的下一步由同请求宿主日志续办。
				cancellation_checkpoint={"operation":operation,"occurrence":successful_calls[operation],"after_result":result.duplicate(true)}
				observer.record_partial({"type":"isolated_cancellation_requested","checkpoint":cancellation_checkpoint})
				observer.replay_runtime.cancel()
		if observer.needs_action_frame(operation):await observer.capture(operation+" / "+str(result.get("code",result.get("ok"))))
		return result
var verification_snapshot: Dictionary
func record_setup_failure(result: Dictionary, trigger: Dictionary) -> void:
	var record:=trigger.duplicate(true)
	record["validation_case"]=validation_case
	for key in ["error","condition","searched_distances_m"]:
		if result.has(key):record[key]=result[key]
	var file:=FileAccess.open(motion+"/setup_error.json",FileAccess.WRITE)
	assert(file!=null,"必须保存隔离前提失败的具体原因")
	file.store_string(JSON.stringify(record));file.close()

func record_runtime_failure(result: Dictionary, step_index: int) -> void:
	var diagnostic:={"validation_case":validation_case,"step_index":step_index,"runtime":{}}
	for key in ["status","code","elapsed_ms","operation_elapsed_ms"]:
		if result.has(key):diagnostic.runtime[key]=result[key]
	var file:=FileAccess.open(motion+"/runtime_error.json",FileAccess.WRITE)
	assert(file!=null,"必须保留运行失败的具体结果")
	file.store_string(JSON.stringify(diagnostic));file.close()

static func needs_action_frame(operation: String) -> bool:
	# 查询的完整数值轨迹仍逐条保存；不为读取同一现场重复阻塞渲染两帧。
	# 未知操作按会改变世界处理，不能因漏列新能力而丢掉动作证据。
	return operation not in ["perceive","walk_options","recall_locations","observe","body_point","contact_point","inspect_contents","inspect_body","surface","check_placement","plan_grasp"]

func record_partial(event: Dictionary) -> void:
	# 超时/进程被终止前逐条落盘，不能只在整段技能返回后才保存失败证据。
	if trace_log==null:return
	event["time_ms"]=Time.get_ticks_msec()-start_ms
	event["validation_case"]=validation_case
	trace_log.store_line(JSON.stringify(event));trace_log.flush()

func invoke(runtime: Node, program: Dictionary, arguments: Dictionary, linked: Dictionary, source_id: String, root_id: String, step_index: int) -> Dictionary:
	invocation_serial+=1
	var call:={"invocation_id":invocation_serial,"step_index":step_index,"source_event_id":source_id,"root_request_id":root_id,"arguments":arguments.duplicate(true)}
	call["type"]="invocation_started";record_partial(call.duplicate(true))
	invocation_active=true
	var outcome: Dictionary=await runtime.run(program,arguments,api,linked)
	var receipt: Dictionary={}
	for key in ["status","code","elapsed_ms","returned"]:
		if outcome.has(key):receipt[key]=outcome[key]
	# 取消可能先触发清理；先落盘实际返回，再允许清理释放场景和退出。
	call.type="invocation_finished";call["result"]=receipt;record_partial(call)
	invocation_active=false
	return outcome

func _initialize() -> void: run.call_deferred()
func _process(_delta: float) -> bool:
	# 外部进程预算是实际时间；慢帧下SceneTreeTimer的delta会落后，不能用它做退出截止。
	if replay_budget_seconds>0 and not stopping_replay and Time.get_ticks_msec()-replay_budget_started_ms>=replay_budget_seconds*1000:
		_replay_timeout(replay_budget_seconds,replay_budget_started_ms)
		return false
	if recording and is_instance_valid(api) and api.body_state!=null:
		if not capturing and Time.get_ticks_msec()-last_frame>600: capture.call_deferred(stage)
	return false
static func retain_history(history: Array) -> Array:
	if history.size()<64:return history
	var retained: Array=[]
	for index in range(0,history.size(),2):retained.append(history[index])
	return retained

func capture(title: String) -> void:
	if not recording or view==null: return
	while capturing: await process_frame
	if not recording or not is_instance_valid(label):return
	# 长技能不能耗尽前段额度后丢掉真正执行与结束证据；稀疏保留早期帧，再继续记录。
	frames=retain_history(frames)
	capturing=true;stage=title
	if is_instance_valid(review_camera) and is_instance_valid(api):
		# 镜头随真实角色与本次交互物移动；固定在起点会把走近的身体裁掉。
		var actor_at: Vector3=api.sim.actors[api.person_id].body.global_position
		var low:=actor_at+Vector3(-0.7,-0.2,-0.7)
		var high:=actor_at+Vector3(0.7,2.1,0.7)
		for id in framing_objects:
			if not api.objects.objects.has(id):continue
			var at: Vector3=api.objects.objects[id].body.global_position
			if at.distance_to(actor_at)>6:continue
			low=low.min(at-Vector3.ONE*0.6);high=high.max(at+Vector3.ONE*0.6)
		var center: Vector3=(low+high)*0.5
		var radius: float=(high-low).length()*0.5
		review_camera.global_position=center+Vector3(-1,0.65,1).normalized()*radius/sin(deg_to_rad(review_camera.fov*0.5))*1.1
		review_camera.look_at(center)
	label.text="%.2fs · %s"%[(Time.get_ticks_msec()-start_ms)/1000.0,title]
	await process_frame;await RenderingServer.frame_post_draw
	var file:="frame_%04d.jpg"%capture_serial
	capture_serial+=1
	assert(view.get_texture().get_image().save_jpg(motion+"/"+file,0.85)==OK)
	frames.append({"file":file,"stage":title,"time_ms":Time.get_ticks_msec()-start_ms})
	all_frames.append(frames[-1])
	var manifest:=FileAccess.open(folder+"/preview.json",FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"file":motion.get_file()+"/"+file,"stage":title,"time_ms":Time.get_ticks_msec()-start_ms}));manifest.close()
	last_frame=Time.get_ticks_msec();capturing=false
func _write_timeout_report() -> void:
	var report:=FileAccess.open(motion+"/replay_timeout.json",FileAccess.WRITE)
	assert(report!=null,"无法保存回放预算耗尽记录")
	report.store_string(JSON.stringify(timeout_report))
	report.close()

func _stop_replay(code: int) -> void:
	if stopping_replay:return
	stopping_replay=true
	recording=false
	# 与正式取消相同：先撤销身体控制，等在途世界协程退出，再释放节点与管道线程。
	if is_instance_valid(replay_runtime):replay_runtime.cancel()
	while invocation_active:await process_frame
	while capturing:await process_frame
	if is_instance_valid(replay_scene):replay_scene.queue_free()
	await process_frame
	await process_frame
	if not timeout_report.is_empty():
		timeout_report.shutdown="drained"
		_write_timeout_report()
	quit(code)

func _replay_timeout(seconds: int, started_ms: int) -> void:
	if stopping_replay:return
	# 超时与原生崩溃分开；未完成清理的报告不能被当作正常预算退出。
	timeout_report={"schema":1,"budget_seconds":seconds,"elapsed_ms":Time.get_ticks_msec()-started_ms,"shutdown":"pending"}
	_write_timeout_report()
	print("LUAU_REPLAY_BUDGET_EXHAUSTED")
	await _stop_replay(1)
func run() -> void:
	var job:="";var motion_dir:="motion_luau"
	var replay_seconds:=155
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--skill-job="): job=arg.trim_prefix("--skill-job=")
		if arg.begins_with("--motion-dir="): motion_dir=arg.trim_prefix("--motion-dir=")
		if arg.begins_with("--replay-budget-seconds="):
			var value:=arg.trim_prefix("--replay-budget-seconds=")
			if not value.is_valid_int() or int(value)<5 or int(value)>590:push_error("回放预算参数无效");await _stop_replay(2);return
			replay_seconds=int(value)
	if not job.is_valid_identifier() or not motion_dir.is_valid_identifier(): await _stop_replay(2);return
	folder="res://services/skill-runtime/runtime/jobs/"+job;motion=folder+"/"+motion_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(motion))
	trace_log=FileAccess.open(motion+"/partial_trace.jsonl",FileAccess.WRITE)
	assert(trace_log!=null,"无法保存独立验证执行证据")
	replay_budget_started_ms=Time.get_ticks_msec()
	replay_budget_seconds=replay_seconds
	var request: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/build_request.json"))
	verification_snapshot=request.verification_snapshot
	var source: Dictionary=request.get("revision",{}).get("player_event",request.get("creation",{}).get("player_event",{}))
	assert(not source.get("id","").is_empty(),"隔离验证必须保留实际编写请求的事件来源")
	var person: String=request.verification_snapshot.person_id
	var definition: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/candidate_definition.json"))
	var program: Dictionary=JSON.parse_string(definition.program_json)
	if not preload("res://scripts/skills/luau_contract.gd").valid(program): await _stop_replay(2);return
	var parent: Node=root
	if DisplayServer.get_name()!="headless":
		root.unfocusable=true;view=SubViewport.new();view.size=Vector2i(800,600);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view);parent=view
	var scene=load("res://scenes/initial_base.tscn").instantiate();replay_scene=scene;parent.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();store.initialize()
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:
		await physics_frame
		if stopping_replay:return
	var actor: Dictionary=sim.actors[person]
	var objects: Node=sim.world_objects
	if request.verification_snapshot.objects.has("wood_block") or request.verification_snapshot.objects.has("stone_tool"):
		preload("res://scripts/skills/luau_playtest.gd").populate(sim,objects,person)
	Snapshot.restore(sim,request.verification_snapshot)
	actor.event_id=source.id
	for frame in 5:
		await physics_frame
		if stopping_replay:return
	api=ObservedWorld.new();api.sim=sim;api.person_id=person;api.objects=objects;api.observer=self;scene.add_child(api)
	sim.perception.observe(person)
	sim.life_world.fact.connect(func(event: Dictionary):
		facts.append(event.duplicate(true));record_partial({"type":"world_fact","fact":event.duplicate(true)}))
	sim.handover.offered.connect(func(event: Dictionary):
		assert(participants!=null,"递交前必须初始化隔离参与者控制器")
		var answer: String=participants.handover_answer(event.listeners[0])
		consent_fixture.append({"event_id":event.id,"recipient":event.listeners[0],"answer":answer,"source":"隔离接收测试替身，非真实模型决定"})
		sim.handover.respond.call_deferred(event.id,event.listeners[0],answer=="accept"))
	if view!=null:
		for mesh in actor.body.find_children("*","VisualInstance3D",true,false): mesh.layers=2
		for object in objects.objects.values():
			for mesh in object.body.find_children("*","VisualInstance3D",true,false): mesh.layers=2
		for light in scene.find_children("*","Light3D",true,false): light.visible=false
		var camera:=Camera3D.new();review_camera=camera;camera.cull_mask=2;camera.fov=45;scene.add_child(camera)
		camera.global_position=actor.body.global_position+Vector3(-2.2,1.5,2.2);camera.look_at(actor.body.global_position+Vector3(0,1,0));camera.current=true
		var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR;environment.background_color=Color(0.15,0.17,0.19);environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color.WHITE;environment.ambient_light_energy=0.9;camera.environment=environment
		var light:=OmniLight3D.new();light.light_cull_mask=2;light.omni_range=6;light.light_energy=1.3;scene.add_child(light);light.global_position=camera.global_position
		var canvas:=CanvasLayer.new();scene.add_child(canvas);label=Label.new();label.position=Vector2(15,15);label.add_theme_font_size_override("font_size",22);canvas.add_child(label)
	var service=load("res://scripts/skills/luau_service.gd").new();scene.add_child(service)
	var runtime=load("res://scripts/skills/luau_library_runtime.gd").new();replay_runtime=runtime;runtime.service=service;scene.add_child(runtime)
	var library=preload("res://scripts/skills/library.gd").new()
	library.path=folder+"/verification_library.json";library.definitions=request.owned_skills.duplicate(true);library.owners={person:[]}
	for ref in library.definitions:library.owners[person].append({"ref":ref,"source":"隔离快照中已掌握"})
	var raw:=JSON.stringify(definition)
	var registered: Dictionary=library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	if not registered.ok:push_error(registered.error);await _stop_replay(1);return
	assert(library.grant(person,registered.ref,"候选仅限隔离进程").is_empty())
	var linked: Dictionary=library.execution_context(person,registered.ref)
	if not linked.ok:push_error(linked.error);await _stop_replay(1);return
	# 后续修订会覆盖任务目录的候选；每轮回放固定实际使用的入口和依赖代码。
	var code_scope:={"entry":definition.duplicate(true),"definitions":{}}
	for ref in linked.context.definitions:
		if ref!=registered.ref:code_scope.definitions[ref]=library.definitions[ref].duplicate(true)
	var scope_file:=FileAccess.open(motion+"/code_scope.json",FileAccess.WRITE)
	assert(scope_file!=null,"无法保存本次执行代码版本")
	scope_file.store_string(JSON.stringify(code_scope));scope_file.close()
	var observation: Dictionary=sim.space.capture(person)
	var saved_origin: Dictionary=request.verification_snapshot.get("host_execution_origin",{})
	var original_origin: Array=saved_origin.transform if saved_origin.get("request_id")==source.id else Snapshot.transform(sim.space.frames[observation.id].transform)
	assert(Journal.valid_origin(original_origin),"隔离请求原点损坏")
	api.bind_request_origin(source.id,Snapshot.restored_transform(original_origin))
	runtime.context=sim.space.prepare_context(person,store.context_for(person),observation)
	runtime.context.erase("working_context")
	var initial_progress:=initial_request_progress(request.character_context,source.id)
	runtime.context["task_execution"]=Journal.context(person,source.id,initial_progress)
	var baseline_context: Dictionary=runtime.context.task_execution.duplicate(true)
	api.observation_id=observation.id
	var arguments: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/test_arguments.json"))
	for key in arguments:
		if arguments[key] is String and objects.objects.has(arguments[key]):framing_objects.append(arguments[key])
		if arguments[key] is Dictionary and arguments[key].has("observation_id"):arguments[key].observation_id=observation.id
		if not library.valid_argument(arguments[key],definition.get("parameter_kinds",{}).get(key,"reference")):
			push_error("验证参数无效："+key);await _stop_replay(1);return
	var before:=Snapshot.evidence(sim,person)
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"/outcome_plan.json"))
	start_ms=Time.get_ticks_msec()
	participants=preload("res://scripts/skills/verification_participants.gd").new();scene.add_child(participants)
	participants.configure(sim,person,plan.get("participant_behaviors",[]),record_partial)
	recording=view!=null
	await capture("执行前")
	if stopping_replay:return
	var outcome: Dictionary=await invoke(runtime,program,arguments,linked.context,source.id,source.id,0)
	if stopping_replay:return
	if outcome.status!="completed":
		record_runtime_failure(outcome,0)
		push_error("隔离技能运行失败，具体结果已保存");await _stop_replay(1);return
	await capture("执行后")
	if stopping_replay:return
	recording=false
	while capturing:await process_frame
	# 保留实际执行结束现场，便于后续针对失败环节修订；不伪造成功或覆盖原输入快照。
	var snapshot_file:=FileAccess.open(motion+"/final_snapshot.json",FileAccess.WRITE)
	assert(snapshot_file!=null,"无法保存验证结束现场")
	snapshot_file.store_string(JSON.stringify(Snapshot.capture(sim,person)));snapshot_file.close()
	var returned: Dictionary=outcome.get("returned",{}) if outcome.get("returned") is Dictionary else {}
	var failures: Array=[]
	if outcome.status!="completed" or not returned.get("ok",false):failures.append("技能实际执行未完成")
	if outcome.get("trace",[]).is_empty():failures.append("没有世界交互证据，不能只返回成功")
	var baseline_result:={"source_event_id":source.id,"task_execution_before":baseline_context,"before":before,"after":Snapshot.evidence(sim,person),"facts":facts.duplicate(true),"consent_fixture":consent_fixture.duplicate(true),"participant_fixture":participants.evidence(),"runtime":outcome,"arguments":arguments,"failures":failures}
	var cases: Array=[]
	var case_file:=folder+"/verification_cases.json"
	if FileAccess.file_exists(case_file):cases=JSON.parse_string(FileAccess.get_file_as_string(case_file))
	var evidence_cases: Array=[]
	for spec in cases:
		validation_case=spec.name
		participants.reset([])
		Snapshot.restore(sim,request.verification_snapshot)
		for frame in 2:
			await physics_frame
			if stopping_replay:return
		participants.reset(plan.get("participant_behaviors",[]))
		actor.event_id=source.id
		var sequence: Array=[];var previous: Dictionary={}
		var journals: Dictionary={source.id:initial_progress.duplicate(true)}
		var request_origins: Dictionary={source.id:original_origin.duplicate(true)}
		var current_request: String=source.id
		for step in spec.steps:
			if step.has("request"):
				current_request=source.id if step.request=="original" else source.id+"/isolated/"+spec.name+"/"+step.request
			if not journals.has(current_request):journals[current_request]=[]
			actor.event_id=current_request+"/call/"+str(sequence.size())
			var preparation: Dictionary=await preload("res://scripts/skills/verification_conditions.gd").apply(sim,person,request.verification_snapshot,step.conditions,participants)
			if not preparation.ok:
				record_setup_failure(preparation,{"phase":"before_call","step_index":sequence.size()})
				push_error(preparation.error);await _stop_replay(1);return
			facts.clear();consent_fixture.clear()
			var test_args: Variant=previous.get("resume_arguments") if step.get("resume_previous",false) else step.arguments
			if not test_args is Dictionary or test_args.size()!=definition.parameters.size():push_error("隔离续办/调用参数不完整");await _stop_replay(1);return
			for key in definition.parameters:
				if not test_args.has(key) or not library.valid_argument(test_args[key],definition.get("parameter_kinds",{}).get(key,"reference")):push_error("隔离调用参数无效："+key);await _stop_replay(1);return
			api.queue_free();await process_frame
			if stopping_replay:return
			api=ObservedWorld.new();api.sim=sim;api.person_id=person;api.objects=objects;api.observer=self;scene.add_child(api)
			api.after_operations=step.get("after_operations",[])
			api.cancel_after_operation=step.get("cancel_after_operation",{})
			sim.perception.observe(person)
			var seen: Dictionary=sim.space.capture(person)
			if not request_origins.has(current_request):request_origins[current_request]=Snapshot.transform(sim.space.frames[seen.id].transform)
			api.bind_request_origin(current_request,Snapshot.restored_transform(request_origins[current_request]))
			runtime.context=sim.space.prepare_context(person,store.context_for(person),seen);api.observation_id=seen.id
			runtime.context.erase("working_context")
			runtime.context["task_execution"]=Journal.context(person,current_request,journals[current_request])
			var call_context: Dictionary=runtime.context.task_execution.duplicate(true)
			var prior: Dictionary=Snapshot.evidence(sim,person)
			var trial: Dictionary=await invoke(runtime,program,test_args,linked.context,actor.event_id,current_request,sequence.size())
			if stopping_replay:return
			var expected_cancel: bool=not api.cancel_after_operation.is_empty()
			if trial.status!="completed" and not (expected_cancel and trial.status=="cancelled" and not api.cancellation_checkpoint.is_empty()):
				record_runtime_failure(trial,sequence.size())
				push_error("隔离场景代码未正常结束");await _stop_replay(1);return
			if expected_cancel and trial.status=="completed":
				record_setup_failure({"error":"声明的取消操作未触发；选择本步骤实际成功调用的操作及次数","condition":api.cancel_after_operation.duplicate(true)},{"phase":"cancel_after_operation","step_index":sequence.size()})
				push_error("隔离取消触发点未出现");await _stop_replay(1);return
			previous=trial.get("returned",{}) if trial.get("returned") is Dictionary else {}
			var journal_record:={"person_id":person,"source_event_id":actor.event_id,"skill_ref":registered.ref,"runtime":trial.duplicate(true),"world_facts":facts.duplicate(true)}
			journal_record.merge(Journal.execution_evidence(test_args,definition.get("parameter_kinds",{}),trial))
			journals[current_request].append(journal_record)
			sequence.append({"source_event_id":actor.event_id,"root_request_id":current_request,"task_execution_before":call_context,"task_execution_after":Journal.context(person,current_request,journals[current_request]),"retained_request_ids":journals.keys(),"resume_from_step":sequence.size()-1 if step.get("resume_previous",false) else -1,"preparation":preparation.preparation,"transitions":api.transitions.duplicate(true),"cancellation_checkpoint":api.cancellation_checkpoint.duplicate(true),"arguments":test_args.duplicate(true),"before":prior,"after":Snapshot.evidence(sim,person),"runtime":trial,"facts":facts.duplicate(true),"consent_fixture":consent_fixture.duplicate(true),"participant_fixture":participants.evidence()})
		evidence_cases.append({"name":spec.name,"steps":sequence})
	baseline_result["validation_cases"]=evidence_cases
	var file:=FileAccess.open(motion+"/motion.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"faults":[],"frames":frames,"all_frames":all_frames,"samples":samples,"result":baseline_result,"note":"baseline使用原始快照，必须独立满足原目标；validation_cases是同一代码的隔离条件与连续调用证据，各场景分别恢复快照，不能把不同场景物资合计。前提设置由宿主执行，不授予候选改变世界的权限。额外场景中的ok=false可能是正确安全停止；声明取消时，宿主在真实成功操作后取消运行器，保留checkpoint、cancelled状态、世界事实及同请求进展，是否满足原要求仍由固定条件与独立审查判断。NPC接受递物使用明确测试替身，不证明真实人物会同意。"}));file.close()
	print("LUAU_CANDIDATE_RESULT failures=",failures," frames=",frames.size())
	await _stop_replay(0 if failures.is_empty() else 1)
