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

func initialize_current(target: String="user://skills/egocentric/library.json") -> String:
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
	store.people[id]["skill_authoring"]={"available":true,"language":"Luau","rule":"利用已开放世界操作或已掌握技能编写新方法；隔离执行及独立审查后才加载"}
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
			var resolved: Dictionary=sim.space.resolve(id,value)
			if not resolved.ok: return {"ok":false,"error":resolved.code}
		elif sim.perception.known(id,value).is_empty() and sim.perception.known(id,"person/"+value).is_empty():
			return {"ok":false,"error":"参数必须指向本人已知的物品或人物"}

	var linked:=library.execution_context(id,call.ref)
	if not linked.ok: return linked
	if active.has(id) or sim.actors[id].stage!="idle": return {"ok":false,"error":"人物正在执行其他行动；若决定中止，请先提交rest，再根据结果执行新动作","category":"busy"}
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
	var adapter=preload("res://scripts/skills/luau_world_adapter.gd").new();adapter.objects=world_objects
	adapter.sim=sim;adapter.person_id=id;adapter.observation_id=call.arguments.target.observation_id if call.arguments.get("target") is Dictionary else observation.id
	add_child(adapter);add_child(runtime);active[id]=runtime
	sim.actors[id].event_id=event_id
	sim.actors[id]["skill_name"]=definition.name
	_run(id,event_id,call.duplicate(true),definition,runtime,adapter,linked.context)
	return {"ok":true,"ref":call.ref,"name":definition.name}

func _run(id: String, event_id: String, call: Dictionary, definition: Dictionary, runtime: Node, adapter: Node, linked: Dictionary) -> void:
	var generation:=_generation
	var outcome: Dictionary=await runtime.run(JSON.parse_string(definition.program_json),call.arguments,adapter,linked)
	active.erase(id);runtime.queue_free();adapter.queue_free()
	if generation!=_generation: return
	var returned: Variant=outcome.get("returned")
	var success: bool=outcome.status=="completed" and returned is Dictionary and returned.get("ok")==true
	var goal_verified:=false
	if definition.id in ["take_object","release_object"]:
		var object: Dictionary=world_objects.objects.get(call.arguments.object,{})
		goal_verified=not object.is_empty() and (object.holder==id if definition.id=="take_object" else object.holder!=id)
		success=success and goal_verified
	if definition.id=="place_object":
		var placement: Dictionary=adapter.placement_result(call.arguments.object,call.arguments.target)
		goal_verified=placement.ok
		success=success and goal_verified
	if definition.id=="give_object":
		var object: Dictionary=world_objects.objects.get(call.arguments.object,{})
		goal_verified=not object.is_empty() and object.holder==call.arguments.recipient
		success=success and goal_verified
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
	outcome["trace"]=steps.slice(maxi(0,steps.size()-32))
	outcome["operation_counts"]=counts;outcome["full_evidence_path"]=evidence_path
	var message: String=("世界状态验证通过" if goal_verified else "技能代码执行结束；整体目标仍需依据实际世界结果判断") if success else "技能执行未完成："+str(outcome.get("code",returned))
	var facts: Array=adapter.world_facts.duplicate(true)
	if not facts.is_empty():
		var effect_counts: Dictionary={}
		for fact in facts:
			var label: String={"taken":"取出","stored":"存入","consumed":"消耗","given":"交付","filled":"装入"}[fact.kind]+("水" if fact.material=="water" else "食物")
			effect_counts[label]=effect_counts.get(label,0)+fact.quantity
		var changes: PackedStringArray=[]
		for label in effect_counts:changes.append(label+str(effect_counts[label])+"份")
		message+=("；实际变化："+"、".join(changes))
	message=definition.name+"："+message
	var remembered_position: Variant=null
	var object_id: String=call.arguments.get("object","")
	if success and world_objects.objects.has(object_id):
		var at: Vector3=world_objects.objects[object_id].body.global_position
		remembered_position={"x":at.x,"y":at.y,"z":at.z}
	finished.emit({"object_id":object_id,"world_position":remembered_position,"person_id":id,"source_event_id":event_id,"intent":"skill","skill_ref":call.ref,"skill_name":definition.name,"success":success,"goal_verified":goal_verified,"message":message,"runtime":outcome,"world_facts":facts})

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

func request_learning(id: String, event: Dictionary, request: Dictionary) -> Dictionary:
	if event.get("kind") in ["skill_ready","skill_revised","skill_progress"]:return {"ok":false,"error":"学习结果不是新的学习请求"}
	for skill in library.describe(id):
		if library.definitions[skill.ref].id==request.goal_id:return {"ok":false,"error":"已掌握同名技能，需要修改时提交修订"}
	var ticket: String="learn/"+id+"/"+event.id
	if accepted.has(ticket):return {"ok":false,"error":"本轮学习已经处理"}
	var started:=_begin_learning(id,request.goal_id,{}, {}, {"goal":request.goal,"player_event":event.duplicate(true)})
	if started.ok:
		accepted[ticket]=true;learning[id]["original_event"]=event.duplicate(true);sim.actors[id].event_id=event.id
	return started

func request_revision(id: String, event: Dictionary, request: Dictionary) -> Dictionary:
	if event.get("kind") in ["skill_ready","skill_revised","skill_progress"]: return {"ok":false,"error":"学习完成通知不是新的教导，不能重复提交同一修订"}
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

func _begin_learning(id: String, goal: String, dependencies: Dictionary, revision: Dictionary={}, creation: Dictionary={}) -> Dictionary:
	if not sim.ready_for_actions or not sim.enabled or not store.people.has(id): return {"ok":false,"error":"人物或模拟未就绪"}
	if active.has(id) or learning.has(id) or sim.actors[id].stage!="idle": return {"ok":false,"error":"人物正在忙碌"}
	var job:="job_%d_%d"%[Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var python:=ProjectSettings.globalize_path("res://services/text-gateway/.venv/Scripts/python.exe")
	var script:=ProjectSettings.globalize_path("res://services/skill-runtime/luau_builder.py")
	if not FileAccess.file_exists(python): return {"ok":false,"error":"缺少编写服务 Python 环境"}
	var directory:="res://services/skill-runtime/runtime/jobs/"+job
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))!=OK: return {"ok":false,"error":"无法创建编写目录"}
	var request_file:=FileAccess.open(directory+"/build_request.json",FileAccess.WRITE)
	if request_file==null: return {"ok":false,"error":"无法保存编写目标"}
	var character_context: Dictionary=sim.space.prepare_context(id,store.context_for(id),sim.space.capture(id))
	# 修订请求明确需要该技能的执行证据；只读相关记录，不恢复整包历史注入。
	if not revision.is_empty():
		var evidence: Dictionary=store.memory.recall(id,{"kind":"action","keywords":[str(revision.ref)],"limit":4})
		character_context["execution_results"]=evidence.records.map(func(item): return item.data) if evidence.ok else []
		for record in character_context.execution_results:
			if record.get("world_position") is Dictionary:
				var p: Dictionary=record.world_position
				record["remembered_position"]=sim.space.local_point(id,character_context.space_observation.id,Vector3(p.x,p.y,p.z))
				record["observation_id"]=character_context.space_observation.id
			record.erase("world_position")
		character_context["heard_events"]=[revision.player_event.duplicate(true)]
	character_context["body_control"]=preload("res://scripts/skills/body_motor.gd").describe(sim.actors[id].skeleton)
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
	learning[id]={"job":job,"pid":pid,"started":Time.get_ticks_msec(),"goal_id":goal,"goal":creation.get("goal",revision.get("feedback","")),"revision_of":revision.get("ref","")}
	sim.actors[id].stage="skill_learning";sim.actors[id]["skill_owner"]=get_instance_id()
	store.people[id]["learning"]={"message":"正在学习：准备编写技能","job":job}
	return {"ok":true,"job":job}

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
		store.people[id]["learning"]={"message":status.get("message","正在学习"),"job":task.job,"model":status.get("model",""),"review":status.get("review",{}),"state":status.get("state","")}
		if status.get("state")=="failed": _end_learning(id,false,status.message);continue
		if status.get("state")!="ready": continue
		var package: Variant=JSON.parse_string(FileAccess.get_file_as_string(folder+"package.json"))
		if not package is Dictionary or not package.get("definition") is Dictionary or not package.get("receipt") is Dictionary:
			_end_learning(id,false,"编写结果包无效");continue
		var registered:=library.register_verified(package.definition,package.receipt)
		if not registered.ok: _end_learning(id,false,registered.error);continue
		var origin: String=task.get("revision_of","")
		var error:=library.grant(id,registered.ref,"强模型 "+str(status.get("model",""))+" 编写，独立场景验证后掌握") if origin=="" else library.revise(id,origin,registered.ref,"依据教导修订；旧版本保留："+origin)
		if error!="": _end_learning(id,false,error);continue
		sync_person(id)
		_end_learning(id,true,("已学会：" if origin=="" else "已修订：")+package.definition.name,registered.ref)

func _end_learning(id: String, ok: bool, message: String, ref: String="") -> void:
	var task: Dictionary=learning[id];learning.erase(id)
	learning_drafts=preload("res://scripts/skills/learning_catalog.gd").scan(store.people.keys())
	sync_person(id)
	if sim.actors[id].get("skill_owner")==get_instance_id():
		sim.actors[id].erase("skill_owner");sim.actors[id].stage="idle";sim._sync(id)
	var details: Dictionary=store.people[id].get("learning",{}).duplicate(true)
	details.merge({"message":message,"completed":ok,"job":task.job},true)
	store.people[id]["learning"]=details
	learning_finished.emit({"person_id":id,"ok":ok,"message":message,"ref":ref,"job":task.job,"revision_of":task.get("revision_of",""),"original_event":task.get("original_event",{}),"goal_id":task.get("goal_id",""),"goal":task.get("goal","")})
