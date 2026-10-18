extends Node
var build_policy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/skill_build_policy.json"))
## 日常模型只提交引用与参数，不能提交代码、注册或授予技能。
signal finished(result: Dictionary)
signal learning_finished(result: Dictionary)
const Library=preload("res://scripts/skills/library.gd")
var library:=Library.new()
var sim: Node
var store: RefCounted
var active: Dictionary={}
var accepted: Dictionary={}
var _generation:=0
var learning: Dictionary={}
var _learning_clock:=0.0
var luau_service: Node
var world_objects: Node
var learning_drafts: Dictionary={}

func has_starting_call() -> bool:
	for runtime in active.values():
		if runtime.is_starting():return true
	return false

func ensure_luau_world() -> void:
	if not is_instance_valid(luau_service):
		luau_service=preload("res://scripts/skills/luau_service.gd").new();add_child(luau_service)
	if not is_instance_valid(world_objects):
		world_objects=sim.world_objects

	sim.perception.world_objects=world_objects

func initialize_current(target: String="user://skills/simplified/library.json") -> String:
	var error:=initialize(target)
	if error!="": return error
	error=library.install_builtins()
	if error!="": return error
	for id in store.people: sync_person(id)
	return ""

func initialize(path: String) -> String:
	var error:=library.initialize(path,store.people)
	if error!="": return error
	learning_drafts=preload("res://scripts/skills/learning_catalog.gd").scan(store.people.keys())
	for id in store.people: sync_person(id)
	return ""

func sync_person(id: String) -> void:
	store.people[id]["skill_refs"]=library.owners.get(id,[]).duplicate(true)
	store.people[id]["available_skills"]=library.describe(id).filter(func(skill):return not skill.get("internal",false))
	store.people[id]["skill_authoring"]=preload("res://scripts/skills/luau_contract.gd").authoring_context()
	var owned_ids: Array=[]
	for entry in library.owners.get(id,[]): owned_ids.append(library.definitions[entry.ref].id)
	store.people[id]["learning_drafts"]=learning_drafts.get(id,[]).filter(func(draft):return draft.goal_id not in owned_ids)

func invoke(id: String, event_id: String, call: Dictionary) -> Dictionary:
	if not sim.ready_for_actions or not sim.enabled: return {"ok":false,"error":"世界模拟未就绪或已暂停"}
	if not store.people.has(id): return {"ok":false,"error":"人物不存在"}
	var definition:=library.resolve(id,call.get("ref",""))
	if definition.is_empty(): return {"ok":false,"error":"人物没有掌握这个技能"}
	if not call.get("arguments") is Dictionary: return {"ok":false,"error":"技能参数必须是对象"}
	if call.arguments.size()!=definition.parameters.size(): return {"ok":false,"error":"技能参数数量不符"}
	for key in definition.parameters:
		var value: Variant=call.arguments.get(key)
		var kind: String=definition.get("parameter_kinds",{}).get(key,"reference")
		if not Library.valid_argument(value,kind): return {"ok":false,"error":"无效技能参数："+key}
		if kind!="reference":continue
		# 参数边界按数据种类校验，不按技能名称特判；具体操作再检查接触与用途。
		if value is Dictionary:
			var resolved: Dictionary=sim.space.resolve(id,value,INF)
			if not resolved.ok: return {"ok":false,"error":resolved.code}
		elif sim.perception.known(id,value).is_empty() and sim.perception.known(id,"person/"+value).is_empty():
			return {"ok":false,"error":"参数必须指向本人已知的物品或人物"}

	var linked:=library.execution_context(id,call.ref)
	if not linked.ok: return linked
	if active.has(id) or sim.actors[id].stage!="idle": return {"ok":false,"error":"人物正在执行其他行动；若决定替换，可同轮提交rest与skill_call，程序排空旧执行后再调用","category":"busy"}
	var ticket:=id+"/"+event_id
	if accepted.has(ticket): return {"ok":false,"error":"本轮技能调用已处理"}
	accepted[ticket]=true
	if accepted.size()>256: accepted.erase(accepted.keys()[0])
	ensure_luau_world()
	var runtime=preload("res://scripts/skills/luau_library_runtime.gd").new()
	runtime.service=luau_service
	var observation: Dictionary=sim.space.capture(id)
	runtime.context=sim.space.prepare_context(id,store.context_for(id),observation)
	# 对话由角色决策使用；执行已选技能不重复接收短期对话和旧任务。
	runtime.context.erase("working_context")
	runtime.context["task_execution"]=store.skill_execution_context(id,event_id)
	var adapter=preload("res://scripts/skills/luau_world_adapter.gd").new();adapter.objects=world_objects
	adapter.sim=sim;adapter.person_id=id;adapter.observation_id=call.arguments.target.observation_id if call.arguments.get("target") is Dictionary else observation.id
	adapter.bind_request_origin(runtime.context.task_execution.request_id,store.skill_execution_origin(id,event_id,sim.space.frames[observation.id].transform))
	add_child(adapter);add_child(runtime);active[id]=runtime
	adapter.retain_observation(observation.id)
	for value in call.arguments.values():
		if value is Dictionary:adapter.retain_observation(value.observation_id)
	sim.actors[id].event_id=event_id
	sim.actors[id]["skill_name"]=definition.name
	_run(id,event_id,call.duplicate(true),definition,runtime,adapter,linked.context)
	return {"ok":true,"ref":call.ref,"name":definition.name}

func _run(id: String, event_id: String, call: Dictionary, definition: Dictionary, runtime: Node, adapter: Node, linked: Dictionary) -> void:
	var generation:=_generation
	var outcome: Dictionary=await runtime.run(JSON.parse_string(definition.program_json),call.arguments,adapter,linked)
	if generation==_generation:
		var argument_frames: Dictionary=adapter.argument_motion_frames(outcome.get("trace",[]))
		if not argument_frames.is_empty():outcome["argument_frames"]=argument_frames
	active.erase(id);runtime.queue_free();adapter.queue_free()
	if generation!=_generation: return
	var returned: Variant=outcome.get("returned")
	var success: bool=outcome.status=="completed" and returned is Dictionary and returned.get("ok")==true
	var cancelled: bool=outcome.status=="cancelled" or outcome.get("code","")=="cancelled"
	# success只说明这次代码正常结束且方法返回ok；世界回执记录实际效果。
	# 不按技能名字推断任务完成，原请求仍交给角色结合全程证据判断。
	# 感知采样属于执行证据，不反复塞进人物的每条记忆和对话上下文。
	var evidence_path:="user://skills/executions/"+(id+"/"+event_id).sha256_text()+".json"
	var save_error:=DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_path).get_base_dir())
	if save_error==OK:
		var file:=FileAccess.open(evidence_path,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(outcome));file.close()
		else:push_error("无法保存技能执行证据："+evidence_path)
	else:push_error("无法创建技能执行证据目录")
	var steps: Array=[];var counts: Dictionary={}
	for step in outcome.get("trace",[]):
		counts[step.operation]=counts.get(step.operation,0)+1
		if step.operation not in ["perceive","recall_locations","walk_options"]:steps.append(step)
	var facts: Array=adapter.world_facts.duplicate(true)
	# 先从全程真实轨迹提取续办证据；下方裁剪不得丢掉早期受阻路线。
	var journal_evidence:=preload("res://scripts/skills/execution_journal.gd").execution_evidence(call.arguments,definition.get("parameter_kinds",{}),outcome)
	outcome.erase("argument_frames")
	# 公开结果与人物动作摘要先覆盖全程，不能被后续轨迹截断吞掉空物品交接。
	var feedback_details:=execution_feedback_details({"success":success,"cancelled":cancelled,"world_facts":facts,"runtime":outcome})
	# 尾部原始轨迹可以限长，但供人物判断的动作摘要必须先覆盖全程。
	outcome["phase_summary"]=preload("res://scripts/skills/egocentric_space.gd").execution_phases(outcome.get("trace",[]))
	outcome["trace"]=steps.slice(maxi(0,steps.size()-32))
	outcome["operation_counts"]=counts;outcome["full_evidence_path"]=evidence_path
	var message: String="技能代码执行结束；整体目标仍需依据实际世界结果判断" if success else "技能执行未完成："+str(outcome.get("code",returned))
	if cancelled:message="动作已停止；已发生的世界变化保留"
	if not facts.is_empty():
		message+=("；实际变化："+effect_summary(facts))
	message=definition.name+"："+message
	var remembered_position: Variant=null
	var object_id: String=call.arguments.get("object","")
	if success and world_objects.objects.has(object_id):
		var at: Vector3=world_objects.objects[object_id].body.global_position
		remembered_position={"x":at.x,"y":at.y,"z":at.z}
	var execution:={"object_id":object_id,"world_position":remembered_position,"person_id":id,"source_event_id":event_id,"intent":"skill","skill_ref":call.ref,"skill_name":definition.name,"success":success,"cancelled":cancelled,"message":message,"runtime":outcome,"world_facts":facts,"feedback_details":feedback_details}
	execution.merge(journal_evidence)
	finished.emit(execution)

func _container_name(id: String) -> String:
	var record: Dictionary=sim.content_interaction.containers[id].record
	return str(record.root.get_meta("display_name","容器"))

func execution_feedback_details(result: Dictionary) -> String:
	var details: PackedStringArray=[]
	var facts: Array=result.get("world_facts",[])
	if not facts.is_empty():details.append(effect_summary(facts))
	var trace: Array=result.get("runtime",{}).get("trace",[])
	# trace由Godot实际接口生成；技能returned和人物私下理解不是公开世界回执。
	for index in range(trace.size()-1,-1,-1):
		var step: Dictionary=trace[index]
		var actual: Dictionary=step.result
		if step.operation=="handover" and actual.get("ok",false) and actual.get("code")=="transferred":
			var recipient: String=actual.recipient_id
			var name: String=sim.world_objects.observable_extra(actual.object).name
			details.append("已将"+name+"交给"+("玩家" if recipient=="player" else store.people[recipient].name))
			break
	if not result.success and not result.get("cancelled",false):
		for index in range(trace.size()-1,-1,-1):
			var step: Dictionary=trace[index]
			if step.operation in ["perceive","recall_locations","walk_options","observe"]:continue
			# 已恢复的旧失败不再当成本次失败原因，只说明最后一次实际操作的拒绝。
			if not step.result.get("ok",false) and not str(step.result.get("message","")).is_empty():
				details.append(step.result.message)
			break
	return " · ".join(details)

func effect_summary(facts: Array) -> String:
	# 同一份物资可以经历采集、入篮、出篮和入库；不能合并不同环节后冒充采集量。
	var counts: Dictionary={}
	for fact in facts:
		var material: String={"food":"食物","water":"水"}[fact.material]
		var label: String
		match fact.kind:
			"taken":
				label=("从"+_container_name(fact.source)+"取出") if sim.content_interaction.containers.has(fact.source) else "从资源点取得"
			"stored","filled":label="存入"+_container_name(fact.target) if fact.kind=="stored" else "装入"+_container_name(fact.target)
			"consumed":label="消耗"
			"given":label="交给"+("玩家" if fact.recipient_id=="player" else store.people[fact.recipient_id].name)
			_:assert(false,"未知物资结算类型："+str(fact.kind))
		label+=material
		counts[label]=counts.get(label,0)+fact.quantity
	var changes: PackedStringArray=[]
	for label in counts:changes.append(label+str(counts[label])+"份")
	return "、".join(changes)

func checkpoint_stop() -> void:
	for id in active.keys():active[id].cancel()
	for id in learning.keys():
		_cancel_learning_worker(id,"session_checkpoint")
		_end_learning(id,false,"存档中断编写，草稿保留")

func cancel(id: String) -> void:
	if active.has(id): active[id].cancel()
	if learning.has(id):
		_cancel_learning_worker(id,"player_cancel")
		_end_learning(id,false,"已取消学习，不再继续原请求")

func _cancel_learning_worker(id: String, reason: String) -> void:
	var file:=FileAccess.open("res://services/skill-runtime/runtime/jobs/"+str(learning[id].job)+"/cancelled",FileAccess.WRITE)
	if file!=null:file.store_string(reason);file.close()

func reset_context() -> void:
	_generation+=1
	for runtime in active.values(): runtime.cancel()
	for id in learning.keys():
		_cancel_learning_worker(id,"context_reset")
		_end_learning(id,false,"情境重置，取消本次学习")

static func learning_event_error(event: Dictionary) -> String:
	if event.get("kind") in ["skill_ready","skill_revised"] or event.get("learning_failed",false):return "学习结果不是新的学习请求"
	if event.get("kind")=="skill_progress" and event.get("original_event",{}).is_empty():return "技能反馈缺少对应的未完成目标"
	return ""

func request_learning(id: String, event: Dictionary, request: Dictionary) -> Dictionary:
	var gate:=learning_event_error(event)
	if not gate.is_empty():return {"ok":false,"error":gate}
	# 先检查当前事件，再使用原请求绑定版本/目标；不能丢掉失败或完成身份。
	var original: Dictionary=event.get("original_event",event)
	for skill in library.describe(id):
		if library.definitions[skill.ref].id==request.goal_id:return {"ok":false,"error":"已掌握同名技能，需要修改时提交修订"}
	var ticket: String="learn/"+id+"/"+original.id
	if accepted.has(ticket):return {"ok":false,"error":"本轮学习已经处理"}
	var started:=_begin_learning(id,request.goal_id,{}, {}, {"goal":request.goal,"player_event":original.duplicate(true)})
	if started.ok:
		accepted[ticket]=true;learning[id]["original_event"]=original.duplicate(true);sim.actors[id].event_id=event.id
	return started

static func revision_event_error(event: Dictionary, ref: String) -> String:
	if event.get("kind") in ["skill_ready","skill_revised"] or event.get("learning_failed",false):
		return "学习结果本身不是新的修订依据，不能自动循环修订"
	if event.get("kind") in ["skill_progress","skill_execution"]:
		var result: Dictionary=event.get("result",{})
		if result.is_empty() or result.get("cancelled",false) or result.get("runtime",{}).get("code","")=="cancelled":
			return "自主修订须基于本人该版本的实际执行证据；取消或其他技能结果不能作为依据"
		# 玩家请求可以先停动作再修订；此时依据是续办原请求，不是把停止当成目标技能失败。
		if event.get("original_event",{}).get("speaker")=="player":return ""
		if result.get("skill_ref","")!=ref:
			return "自主修订须基于本人该版本的实际执行证据；取消或其他技能结果不能作为依据"
	return ""

func request_revision(id: String, event: Dictionary, request: Dictionary) -> Dictionary:
	var gate:=revision_event_error(event,request.ref)
	if not gate.is_empty():return {"ok":false,"error":gate}
	var definition:=library.resolve(id,request.ref)
	if definition.is_empty(): return {"ok":false,"error":"人物尚未掌握此技能"}
	var current:=false
	for item in library.describe(id):
		if item.ref==request.ref: current=true
	if not current: return {"ok":false,"error":"请基于当前技能版本修订"}
	var ticket: String="revise/"+id+"/"+event.id
	if accepted.has(ticket): return {"ok":false,"error":"本轮修订已处理"}
	var revision:={"ref":request.ref,"feedback":request.feedback,"definition":definition,"player_event":event.duplicate(true)}
	var started:=_begin_learning(id,definition.id,{},revision)
	if started.ok:
		accepted[ticket]=true
		learning[id]["original_event"]=event.duplicate(true)
		sim.actors[id].event_id=event.id
	return started

func recover_verified_job(job: String) -> Dictionary:
	var pattern:=RegEx.new();pattern.compile("^job_[0-9]+_[0-9]+$")
	if pattern.search(job)==null:return {"ok":false,"error":"恢复任务编号无效"}
	var folder:="res://services/skill-runtime/runtime/jobs/"+job+"/"
	var status: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+"status.json")) if FileAccess.file_exists(folder+"status.json") else null
	var request: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+"build_request.json")) if FileAccess.file_exists(folder+"build_request.json") else null
	var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+"package.json")) if FileAccess.file_exists(folder+"package.json") else null
	if not status is Dictionary or status.get("state")!="ready":return {"ok":false,"error":"任务尚未验证通过，不能恢复技能"}
	if not request is Dictionary or not request.get("character_context") is Dictionary or not package is Dictionary or not package.get("definition") is Dictionary or not package.get("receipt") is Dictionary:
		return {"ok":false,"error":"恢复任务资料不完整"}
	var id: String=str(request.character_context.get("id",""))
	if not sim.ready_for_actions or not store.people.has(id) or active.has(id) or learning.has(id) or sim.actors[id].stage!="idle":return {"ok":false,"error":"人物未就绪或正在执行行动"}
	var revision: Variant=request.get("revision",{})
	var creation: Variant=request.get("creation",{})
	if not revision is Dictionary or not creation is Dictionary:return {"ok":false,"error":"恢复任务目标格式无效"}
	var origin: String=str(revision.get("ref",""))
	var definition: Dictionary=package.definition
	if not Library._valid_definition(definition) or definition.id!=request.get("goal_id") or definition.get("revision_of","")!=origin:return {"ok":false,"error":"验证结果与恢复目标或原版本不匹配"}
	var ref:=Library._reference(definition)
	var current:=""
	for skill in library.describe(id):
		if skill.id==definition.id:current=skill.ref
	if current==ref:
		var checked:=library.register_verified(definition,package.receipt)
		if not checked.ok:return checked
		return {"ok":true,"person_id":id,"job":job,"ref":ref,"already_loaded":true}
	if current!=origin:return {"ok":false,"error":"当前技能版本与恢复任务的原版本冲突，未覆盖"}
	var event: Variant=revision.get("player_event",creation.get("player_event",{}))
	if not event is Dictionary or not event.get("id") is String or event.id.is_empty():return {"ok":false,"error":"恢复任务缺少原始人物事件"}
	learning[id]={"job":job,"pid":0,"started":Time.get_ticks_msec(),"goal_id":definition.id,"goal":creation.get("goal",revision.get("feedback","")),"revision_of":origin,"original_event":event.duplicate(true),"expected_ref":ref}
	sim.actors[id].stage="skill_learning";sim.actors[id]["skill_owner"]=get_instance_id()
	store.people[id]["learning"]=_learning_status(learning[id],{"state":"ready","message":"正在恢复已验证技能"})
	return {"ok":true,"person_id":id,"job":job,"ref":ref,"already_loaded":false}

func _begin_learning(id: String, goal: String, dependencies: Dictionary, revision: Dictionary={}, creation: Dictionary={}) -> Dictionary:
	if not sim.ready_for_actions or not sim.enabled or not store.people.has(id): return {"ok":false,"error":"人物或模拟未就绪"}
	if active.has(id) or learning.has(id) or sim.actors[id].stage!="idle": return {"ok":false,"error":"人物正在忙碌"}
	var job:="job_%d_%d"%[Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var python:=ProjectSettings.globalize_path("res://services/text-gateway/.venv/Scripts/python.exe")
	var script:=ProjectSettings.globalize_path("res://services/skill-runtime/luau_builder.py")
	if not FileAccess.file_exists(python): return {"ok":false,"error":"缺少编写服务 Python 环境"}
	var directory:="res://services/skill-runtime/runtime/jobs/"+job
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK: return {"ok":false,"error":"无法创建编写目录"}
	var index_error: String=preload("res://scripts/skills/learning_catalog.gd").write_context(directory,id,goal,creation.get("goal",revision.get("feedback","")))
	if not index_error.is_empty():return {"ok":false,"error":index_error}
	var request_file:=FileAccess.open(directory+"/build_request.json",FileAccess.WRITE)
	if request_file==null: return {"ok":false,"error":"无法保存编写目标"}
	var character_context: Dictionary=sim.space.prepare_context(id,store.context_for(id),sim.space.capture(id))
	# 修订请求明确需要该技能的执行证据；只读相关记录，不恢复整包历史注入。
	if not revision.is_empty():
		character_context["execution_results"]=store.execution_evidence(id,str(revision.ref))
		for record in character_context.execution_results:
			if record.get("world_position") is Dictionary:
				var p: Dictionary=record.world_position
				record["remembered_position"]=sim.space.local_point(id,character_context.space_observation.id,Vector3(p.x,p.y,p.z))
				record["observation_id"]=character_context.space_observation.id
			record.erase("world_position")
		character_context["heard_events"]=[revision.player_event.duplicate(true)]
	character_context["interaction_rules"]={"mode":"simplified","range_m":preload("res://scripts/skills/interaction_range.gd").RADIUS_M,"meaning":"骨骼不决定普通行为成败；使用当前世界操作目录，近距、可见性、归属与库存真实结算。"}
	character_context.interaction_rules["vision"]=preload("res://scripts/survival/perception.gd").vision_rules()
	var owned: Dictionary={}
	for entry in library.describe(id):
		var bundle:=library.execution_context(id,entry.ref)
		if not bundle.ok:continue
		for ref in bundle.context.definitions:owned[ref]=library.definitions[ref].duplicate(true)
	var original: Dictionary=revision.get("player_event",creation.get("player_event",{}))
	character_context["heard_events"]=[original.duplicate(true)]
	# 编写沿用日常判断的无损历史编码，不能重复发送未压缩的同一批当天经历。
	if character_context.has("working_context"):
		character_context.working_context=preload("res://scripts/voice/prompt_history.gd").compact(character_context.working_context)
	var snapshot:=preload("res://scripts/skills/verification_snapshot.gd").capture(sim,id)
	request_file.store_string(JSON.stringify({"goal_id":goal,"dependencies":dependencies,"character_context":character_context,"revision":revision,"creation":creation,"owned_skills":owned,"world_operations":preload("res://scripts/skills/luau_contract.gd").OPERATIONS,"verification_snapshot":snapshot}));request_file.close()
	var pid:=_launch_builder(python,script,job)
	if pid<0: return {"ok":false,"error":"无法启动后台编写进程"}
	learning[id]={"job":job,"pid":pid,"started":Time.get_ticks_msec(),"goal_id":goal,"goal":creation.get("goal",revision.get("feedback","")),"revision_of":revision.get("ref",""),"original_event":original.duplicate(true)}
	sim.actors[id].stage="skill_learning";sim.actors[id]["skill_owner"]=get_instance_id()
	store.people[id]["learning"]=_learning_status(learning[id],{"state":"preparing","message":"正在学习：准备编写技能"})
	return {"ok":true,"job":job}

func _learning_status(task: Dictionary, status: Dictionary) -> Dictionary:
	# 学习目标和原话属于当前任务；开发工具进度不能覆盖它们。
	var phase: String=status.get("state","preparing")
	var technical: String=status.get("message","")
	var labels:={"preparing":"正在准备学习","planning":"正在整理目标与验收条件","writing":"正在编写和检查方法","testing":"正在验证方法","ready":"方法已通过验证，正在载入"}
	return {"state":phase,"message":labels.get(phase,technical),"technical_message":technical,"job":task.job,"model":status.get("model",""),"review":status.get("review",{}),"goal_id":task.get("goal_id",""),"goal":task.get("goal",""),"request_text":task.get("original_event",{}).get("text","")}

func _launch_builder(python: String, script: String, job: String) -> int:
	return OS.create_process(python,PackedStringArray(["-X","utf8",script,job]),false)

func _process(delta: float) -> void:
	_learning_clock+=delta
	if _learning_clock<0.4: return
	_learning_clock=0
	for id in learning.keys():
		var task: Dictionary=learning[id]
		var folder: String="res://services/skill-runtime/runtime/jobs/"+task.job+"/"
		if Time.get_ticks_msec()-task.started>int((build_policy.budget_seconds+build_policy.host_grace_seconds)*1000):
			_cancel_learning_worker(id,"host_timeout")
			_end_learning(id,false,"编写或验证超时，未加载");continue
		if not FileAccess.file_exists(folder+"status.json"):
			if not OS.is_process_running(task.pid): _end_learning(id,false,"后台编写进程未正常启动")
			continue
		var status: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+"status.json"))
		if not status is Dictionary: continue # 原子替换中的短暂读取失败，下次轮询。
		store.people[id]["learning"]=_learning_status(task,status)
		if status.get("state")=="failed": _end_learning(id,false,status.message);continue
		if status.get("state")!="ready": continue
		var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+"package.json"))
		if not package is Dictionary or not package.get("definition") is Dictionary or not package.get("receipt") is Dictionary:
			_end_learning(id,false,"编写结果包无效");continue
		if task.has("expected_ref") and Library._reference(package.definition)!=task.expected_ref:
			_end_learning(id,false,"恢复期间技能结果版本发生变化，未加载");continue
		var registered:=library.register_verified(package.definition,package.receipt)
		if not registered.ok: _end_learning(id,false,registered.error);continue
		var origin: String=task.get("revision_of","")
		var error:=library.grant(id,registered.ref,"强模型 "+str(status.get("model",""))+" 编写，独立场景验证后掌握") if origin=="" else library.revise(id,origin,registered.ref,"依据教导修订；旧版本保留："+origin)
		if error!="": _end_learning(id,false,error);continue
		sync_person(id)
		_end_learning(id,true,("已学会：" if origin=="" else "已修订：")+package.definition.name,registered.ref)

func _end_learning(id: String, ok: bool, message: String, ref: String="") -> void:
	var task: Dictionary=learning[id];learning.erase(id)
	learning_drafts=preload("res://scripts/skills/learning_catalog.gd").refresh_job(store.people.keys(),task.job)
	sync_person(id)
	if sim.actors[id].get("skill_owner")==get_instance_id():
		sim.actors[id].erase("skill_owner");sim.actors[id].stage="idle";sim._sync(id)
	var details: Dictionary=store.people[id].get("learning",{}).duplicate(true)
	details.merge({"message":message,"completed":ok,"state":"loaded" if ok else "failed","job":task.job},true)
	store.people[id]["learning"]=details
	# 编写材料保留实际触发通知；完成后的续办归属仍是该通知绑定的原请求。
	var trigger: Dictionary=task.get("original_event",{})
	var original: Dictionary=trigger.get("original_event",trigger).duplicate(true)
	learning_finished.emit({"person_id":id,"ok":ok,"message":message,"ref":ref,"job":task.job,"revision_of":task.get("revision_of",""),"source_event_id":trigger.get("id",""),"original_event":original,"goal_id":task.get("goal_id",""),"goal":task.get("goal","")})
