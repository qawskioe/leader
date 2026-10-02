extends Node
## 每个听众一次日常判断，最多并发两人；技能编写升级不属于此处的二次扮演。

signal report_ready(report: Dictionary)
signal completed
const Cloud = preload("res://scripts/voice/cloud_client.gd")
const Prompt = preload("res://scripts/voice/decision_prompt.gd")

var gateway: Node
var space: RefCounted
var store: RefCounted
var busy := false
var _queue: Array = []
var _active := 0
var _event: Dictionary
var _generation:=0

func cancel() -> void:
	_generation+=1
	_queue.clear();_active=0;busy=false

func run(event: Dictionary, _config: Dictionary) -> void:
	assert(not busy)
	busy = true
	_generation+=1
	_event = event.duplicate(true)
	_queue = ordered_listeners(event,store.people)
	# 先给全体听众记录信息，模型失败也不能抹掉听闻。
	for id in _queue:
		store.hear(id, event)
	_pump()

static func opening_names(text: String, names: Dictionary) -> Array:
	var matches: Array=[]
	for id in names:
		for separator in ["，",",","：",":","！","!"," "]:
			if text.strip_edges().begins_with(str(names[id])+separator):
				matches.append({"id":id,"name":names[id]});break
	return matches

static func ordered_listeners(event: Dictionary, people: Dictionary) -> Array:
	# 只调整已听见者的处理/播放顺序，不替模型决定谁必须回答或禁止谁插话。
	var names: Dictionary={}
	for id in people:names[id]=people[id].name
	var ordered: Array=[]
	var segments: Array=event.get("spatial_segments",[{"text":event.get("text","")}])
	for segment in segments:
		for match_name in opening_names(segment.get("text",""),names):
			var id: String=match_name.id
			if id in event.listeners and id not in ordered and (not segment.has("audience") or segment.audience.has(id)):ordered.append(id)
	for segment in segments:
		var id: String=segment.get("focus_hint","")
		if id in event.listeners and id not in ordered:ordered.append(id)
	for id in event.listeners:
		if id not in ordered:ordered.append(id)
	return ordered

func _pump() -> void:
	if not busy:
		return
	var limit := 2
	while _active < limit and not _queue.is_empty():
		var id: String = _queue.pop_front()
		_active += 1
		_decide(id,_generation)
	if _active == 0 and _queue.is_empty():
		busy = false
		completed.emit()

func _decide(id: String, generation: int) -> void:
	await _decide_gateway_text(id,generation)
	if generation!=_generation: return
	_active -= 1
	_pump.call_deferred()

func _decide_gateway_text(id: String, generation: int) -> void:
	var report := {"event_id":_event.id,"person_id":id,"person_name":store.people[id].name,"calls":[],"executed":false}
	var context: Dictionary = store.context_for(id)
	# 情报交付冻结本次本人已知记录，不能在模型/TTS返回后换成另一时刻的观察。
	# 原始位置只在宿主内留存；模型仍只收到自身坐标系下的观察和记忆。
	var knowledge_snapshot: Dictionary=context.get("survival_observation",{}).get("known_objects",{}).duplicate(true)
	knowledge_snapshot.merge(store.memory.observations[id].duplicate(true),true)
	for field in ["heard_events","reflections","execution_results","skill_knowledge","known_facts"]: context.erase(field)
	var current_event: Dictionary=store.event_for(id,_event.id)
	var frame_token:=""
	if space!=null:
		var observation: Dictionary=space.capture(id)
		frame_token=observation.id
		assert(space.retain_frame(id,frame_token))
		context=space.prepare_context(id,context,observation)
		preload("res://scripts/skills/egocentric_space.gd").sanitize_event(current_event)
	context["memory_access"]=store.memory.catalog(id)
	var experience=preload("res://scripts/voice/experience_view.gd").new()
	context.working_context=experience.build(context.get("working_context",{}))
	context.memory_access.state="近期经历直接提供；earlier_today目录可用read_experience展开，长期记忆用recall检索。"
	current_event=experience.event_view(current_event)
	var handles: Dictionary=preload("res://scripts/voice/skill_handles.gd").bind(context,current_event)
	report["skill_handle_map"]=handles.duplicate()
	var prompt := prompt_for(context,current_event)
	var result: Dictionary = await _with_memory(id,prompt,context,report,generation,experience)
	if generation!=_generation:
		if not frame_token.is_empty():space.release_frame(frame_token)
		return
	if not result.ok:
		report["error"] = result.error
		if result.get("correction_exhausted",false):
			report["correction_exhausted"]=true
			report["error"]="决策修正一次后仍未通过，未播放或执行："+result.error
		if result.has("rejected_output"): report["rejected_output"]=result.rejected_output
	else:
		var parsed := Cloud.validate_decision(result.text,true,_requires_conversation())
		if parsed.ok and ((_event.get("kind","")=="item_offer") != parsed.decision.has("offer_response")):
			parsed={"ok":false,"error":_offer_contract(_event)}
		if not parsed.ok:
			report["error"] = parsed.error
			report["rejected_output"] = result.text
		else:
			preload("res://scripts/voice/skill_handles.gd").resolve(parsed.decision,handles)
			report["decision"] = parsed.decision
			report["knowledge_offer"] = Cloud.knowledge_offer(parsed.decision,context,knowledge_snapshot)
			store.remember(id, _event.id, parsed.decision, context.get("current_action",{}))
	report_ready.emit(report)
	if not frame_token.is_empty():space.release_frame(frame_token)

func _with_memory(id: String, prompt: String, context: Dictionary, report: Dictionary, generation: int, experience: RefCounted=null) -> Dictionary:
	# 直接决策；确实缺少长期依据时，由同一个模型主动请求检索。
	var final_prompt:=prompt+"\n\n"+Prompt.MEMORY
	var memory_count:=0
	for attempt in 5:
		# 实际游玩诊断保留每人的最后一次真实请求，不靠存档重建调用时的观察。
		if "--player-control" in OS.get_cmdline_user_args():
			var diagnostic:=FileAccess.open("user://voice_tests/last_decision_"+id+".txt",FileAccess.WRITE)
			if diagnostic!=null:
				diagnostic.store_string(final_prompt)
				diagnostic.close() # 异步等待期间也必须能完整读取实际输入，不能留着未刷新的尾部。
		var decision: Dictionary=await gateway.exchange({"mode":"decision","prompt":final_prompt})
		if generation!=_generation: return {"ok":false,"error":"判断已取消"}
		report.calls.append({"stage":"decision","model":decision.get("model","文字模型"),"elapsed_ms":decision.get("elapsed_ms",0),"usage":decision.get("usage",{}),"prompt_chars":final_prompt.length(),"fallback_from":decision.get("fallback_from",{}),"stream_diagnostic":decision.get("stream_diagnostic",{})})
		if not decision.ok: return decision
		var parser:=JSON.new()
		var parsed: Variant=parser.data if parser.parse(decision.text)==OK else null
		if not parsed is Dictionary or (not parsed.has("recall") and not parsed.has("memory_mark") and not parsed.has("read_experience")):
			return await _repair_decision(decision,final_prompt,context,report,generation)
		if parsed.size()!=1: return {"ok":false,"error":"补充回忆不能同时提交行动","rejected_output":decision.text}
		if attempt==4: return {"ok":false,"error":"资料读取已达4次上限，未提交行动"}
		var answer: Dictionary
		if parsed.has("read_experience"):
			answer=experience.read(parsed.read_experience) if experience!=null else {"ok":false,"error":"本次没有短期详情目录"}
			if not report.has("experience_reads"):report["experience_reads"]=[]
			report.experience_reads.append({"request":parsed.read_experience,"ok":answer.ok})
		else:
			if memory_count>=2:return {"ok":false,"error":"长期记忆读取已达2次上限，未提交行动"}
			memory_count+=1
			answer=_memory_operation(id,parsed,context,report)
		final_prompt+="\n你请求的资料："+JSON.stringify({"request":parsed,"result":answer})
		if attempt==3: final_prompt+="\n资料读取额度已用完，现在依据已有证据给出最终决策；证据不足应如实说明。"
	return {"ok":false,"error":"判断未完成"}

func _requires_conversation() -> bool:
	# 递物由人物发起，但并不代表听见了一句台词；接收者由世界事件明确指定。
	return _event.get("kind")!="item_offer" and _event.get("speaker","") not in ["","world","body"]

func _check_final(text: String, context: Dictionary) -> Dictionary:
	var parsed:=Cloud.validate_decision(text,true,_requires_conversation())
	if not parsed.ok: return parsed
	if ((_event.get("kind","")=="item_offer") != parsed.decision.has("offer_response")):
		return {"ok":false,"error":_offer_contract(_event)}
	var handling_check:=Cloud.validate_task_handling(parsed.decision)
	if not handling_check.ok:return handling_check
	var decision: Dictionary=parsed.decision
	var scope: String=decision.task_handling.scope
	if scope=="current_request" and not store.is_person_request(_event.get("original_event",_event)):
		return {"ok":false,"error":"本次是世界/身体通知，不是人物请求；明确续办旧任务用existing_request，自主活动用independent"}
	if scope=="existing_request" and context.get("working_context",{}).get("task",{}).get("request",{}).is_empty():
		return {"ok":false,"error":"没有此前已接受的请求，不能绑定existing_request"}
	for field in ["addressed_person"]:
		var target: String=decision[field]
		if target!="" and target!="player" and not store.people.has(target):
			var hint:="请使用输入中的人物ID，不使用位置线索ID或人物名字。"
			if target.begins_with("person/") and store.people.has(target.trim_prefix("person/")):
				hint="应填人物ID "+target.trim_prefix("person/")+"；"+target+"只是该人物的位置线索ID。"
			return {"ok":false,"error":field+"不是有效人物ID。"+hint+"本次尚未播放台词或执行动作。"}
	for object_id in context.get("survival_observation",{}).get("known_objects",{}):
		if str(object_id).contains("/") and decision.public_reply.contains(str(object_id)):
			return {"ok":false,"error":"公开台词包含内部物品标识 "+str(object_id)+"。请保留原判断与调用参数，仅用物品名称、本人已知的方向或参照物向玩家说明位置，不编造未知特征。"}
	var catalog: Dictionary=context.get("survival_observation",{}).get("action_catalog",{})
	if decision.intent!="none" and not catalog.has(decision.intent):
		return {"ok":false,"error":"intent不在本次控制目录中；只用none或rest，生活行动从available_skills选择"}
	if decision.skill_call!=null:
		var definition: Dictionary={}
		for skill in context.get("available_skills",[]):
			if skill.ref==decision.skill_call.ref:definition=skill;break
		if definition.is_empty():
			return {"ok":false,"error":"skill_call.ref不是本人已掌握技能；请从本轮available_skills复制ref短编号。没有合适方法时可提出学习或能力缺口，不能把技能名称改填intent，也不能编造引用。"}
		if not definition.get("callable",true): return {"ok":false,"error":"该技能暂不可调用："+str(definition.get("unavailable_reason","依赖不可用"))}
		var parameters: Dictionary=definition.get("parameters",{})
		if decision.skill_call.arguments.size()!=parameters.size():return {"ok":false,"error":"技能参数数量与提供的parameters不一致"}
		for name in parameters:
			if not decision.skill_call.arguments.has(name):return {"ok":false,"error":"技能缺少参数："+str(name)}
			if not preload("res://scripts/skills/library.gd").valid_argument(decision.skill_call.arguments[name],definition.get("parameter_kinds",{}).get(name,"reference")):return {"ok":false,"error":"技能参数类型错误："+str(name)}
	if decision.get("learning_request") is Dictionary:
		for skill in context.get("available_skills",[]):
			if skill.get("id","")==decision.learning_request.goal_id:
				return {"ok":false,"error":"已掌握该目标的技能；继续修改失败草稿也应使用revision_request，ref复制本轮 "+str(skill.ref)+"，feedback保留原教导和失败证据。尚未开始学习或播放台词；不要重新创建同名技能。"}
	if decision.get("revision_request") is Dictionary:
		var revisable:=false
		for skill in context.get("available_skills",[]):
			if skill.ref==decision.revision_request.ref and skill.get("revision_supported",false):revisable=true
		if not revisable:return {"ok":false,"error":"revision_request.ref必须来自本轮available_skills且revision_supported=true"}
	return Cloud.validate_task_handling(decision)

func _repair_decision(result: Dictionary, prompt: String, context: Dictionary, report: Dictionary, generation: int) -> Dictionary:
	var checked:=_check_final(result.text,context)
	if checked.ok: return result
	# 保留同一现场和已取回的记忆，不重新回忆、不先发布未通过的决定。
	report["decision_correction"]={"error":checked.error,"rejected_output":result.text}
	var feedback:={"error":checked.error,"rejected_output":result.text}
	var repair_prompt:=prompt+"\n决策校验结果（本次未执行）："+JSON.stringify(feedback)+"\n依据上述错误和同一现场修正，输出完整决策。本次接口为最终决策。"
	var repaired: Dictionary=await gateway.exchange({"mode":"decision","prompt":repair_prompt})
	if generation!=_generation: return {"ok":false,"error":"判断已取消"}
	report.calls.append({"stage":"decision_correction","model":repaired.get("model","文字模型"),"elapsed_ms":repaired.get("elapsed_ms",0),"usage":repaired.get("usage",{}),"fallback_from":repaired.get("fallback_from",{}),"stream_diagnostic":repaired.get("stream_diagnostic",{})})
	if not repaired.ok: return repaired
	checked=_check_final(repaired.text,context)
	if not checked.ok:
		return {"ok":false,"error":checked.error,"rejected_output":repaired.text,"correction_exhausted":true}
	return repaired

func _memory_operation(id: String, parsed: Dictionary, context: Dictionary, report: Dictionary) -> Dictionary:
	var answer: Dictionary
	if parsed.has("memory_mark"):
		answer=store.memory.mark(id,parsed.memory_mark)
	elif parsed.has("recall"):
		answer=store.memory.recall(id,parsed.recall)
		if answer.ok:
			if not report.has("memory_reads"): report["memory_reads"]=[]
			report.memory_reads.append({"request":parsed.recall.duplicate(true),"ids":answer.records.map(func(item): return item.id)})
			for item in answer.records:
				if item.kind=="landmark" and space!=null: item.data=space.recalled_landmark(id,item.data,context.space_observation.id)
				elif item.kind=="heard": preload("res://scripts/skills/egocentric_space.gd").sanitize_event(item.data)
				elif item.kind=="action" and item.data.get("runtime") is Dictionary:
					var runtime: Dictionary=item.data.runtime
					var returned: Dictionary=runtime.get("returned",{}) if runtime.get("returned") is Dictionary else {}
					item.data.message=str(item.data.get("skill_name","动作"))+"："+str(runtime.get("code",returned.get("code","")))
					item.data.erase("runtime")
					if item.data.get("world_position") is Dictionary and space!=null:
						var p: Dictionary=item.data.world_position
						item.data["remembered_position"]=space.local_point(id,context.space_observation.id,Vector3(p.x,p.y,p.z))
						item.data["observation_id"]=context.space_observation.id
						item.data["position_note"]="本人当时动作结束的位置，不代表物品现在仍在那里"
					item.data.erase("world_position")
	else: return {"ok":false,"error":"未知记忆操作"}
	var error: String=store.memory.save()
	if error!="": return {"ok":false,"error":error}
	return answer

static func prompt_for(context: Dictionary, event: Dictionary) -> String:
	# 当前事件也已存于当天经历；发送时用显式引用去重，存档保持原样。
	context=context.duplicate(true)
	event=event.duplicate(true)
	var working: Dictionary=context.get("working_context",{})
	for turn in working.get("recent_turns",[]):
		if turn.event.get("id")==event.get("id") and JSON.stringify(turn.event)==JSON.stringify(event):
			turn.event={"id":event.id,"context_ref":"current_event"}
	var request: Dictionary=working.get("task",{}).get("request",{})
	if event.get("original_event") is Dictionary and not request.is_empty() and JSON.stringify(event.original_event)==JSON.stringify(request):
		event.original_event={"id":request.id,"context_ref":"self.working_context.task.request"}
	if not working.is_empty(): context.working_context=preload("res://scripts/voice/prompt_history.gd").compact(working)
	var evidence: Array=[]
	var known_names: Dictionary={str(context.id):str(context.name)}
	for person in context.get("visible_people",[]):
		if person is Dictionary and person.has("id") and person.has("name"): known_names[str(person.id)]=str(person.name)
	for segment in event.get("spatial_segments",[]):
		var focus: String=segment.get("focus_hint","")
		var heard: String=str(segment.text).strip_edges()
		evidence.append({"heard_text":heard,"opening_name_matches":opening_names(heard,known_names),"facing_person":focus,"facing_me":focus==context.id,"facing_fact":("面对你本人" if focus==context.id else ("面对："+str(known_names.get(focus,focus)) if focus!="" else "无法确定面对谁")),"relative_to_self":segment.get("relative_to_self",{})})
	return Prompt.instructions(context,event)+"\n"+wire_context(context,event,evidence,known_names)


static func wire_context(context: Dictionary, event: Dictionary, evidence: Array, names: Dictionary) -> String:
	# 最近经历与更早经历目录放前；当前状态和本次事件放后，避免旧叙述压过新指令。
	# 固定历史前缀也可被上游复用；实际缓存收益以服务返回为准。
	var ordered: Dictionary={}
	if context.has("working_context"): ordered["working_context"]=context.working_context
	for key in context:
		if key!="working_context": ordered[key]=context[key]
	var identity:={"you":{"id":context.id,"name":context.name},"incoming_speaker":{"id":event.get("speaker",""),"name":"发光的玩家" if event.get("speaker","")=="player" else names.get(event.get("speaker",""),event.get("speaker",""))}}
	return JSON.stringify({"self":ordered,"identity_frame":identity,"conversation_evidence":evidence,"current_event":event},"",false)

static func _offer_contract(event: Dictionary) -> String:
	if event.get("kind","")=="item_offer":return "本轮接物决定需要offer_response，值为accept或decline。"
	return "本轮kind="+str(event.get("kind",""))+"，可用决策字段中没有offer_response。"
