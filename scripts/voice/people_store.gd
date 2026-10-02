extends RefCounted
## 事实、听闻、主观理解、实际结果和技能索引分别保存。测试角色背景不代表正式设定。

var people: Dictionary = {}
# 只保留本次会话现场；持久记忆仍由人物主动检索。
var working_events: Dictionary = {}
var working_tasks: Dictionary = {}
# 已被本人接受的新明确任务接替的旧请求；只用于本次运行中的迟到事件。
var superseded_tasks: Dictionary = {}
## 触发判断的玩家讲话，不一定是旁听者自主动作的任务来源。
var independent_actions: Dictionary = {}
var memory:=preload("res://scripts/voice/memory_store.gd").new()

func initialize(path: String = "res://data/people.json", memory_file: String="", fresh: bool=false) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Array or parsed.is_empty():
		return "人物数据必须是非空数组"
	var loaded: Dictionary = {}
	for item in parsed:
		if not item is Dictionary:
			return "人物条目格式错误"
		for key in ["id", "node", "name", "model", "voice"]:
			if not item.get(key) is String:
				return "人物缺少字符串字段：" + key
		for key in ["known_facts", "constraints"]:
			if not item.get(key) is Array:
				return "人物缺少数组字段：" + key
			for value in item[key]:
				if not value is String:
					return "人物数组必须包含文字：" + key
		for key in ["identity", "short_term", "needs", "relationships", "current_action"]:
			if not item.get(key) is Dictionary:
				return "人物缺少对象字段：" + key
		if item.id.is_empty() or loaded.has(item.id):
			return "人物 ID 为空或重复"
		item["heard_events"] = []
		item["reflections"] = []
		item["execution_results"] = []
		item["skill_refs"] = []
		item["available_skills"] = []
		item["skill_knowledge"] = []
		if not item.needs.get("hunger") is float and not item.needs.get("hunger") is int:
			return "人物缺少数值饥饿 needs.hunger"
		if item.needs.hunger<0 or item.needs.hunger>100:
			return "饥饿数值必须为 0 至 100"
		loaded[item.id] = item
	working_events.clear(); working_tasks.clear(); independent_actions.clear(); superseded_tasks.clear()
	people = loaded
	memory=preload("res://scripts/voice/memory_store.gd").new()
	var error: String=memory.initialize(memory_file,people.keys(),fresh)
	if error!="": return error
	if not memory.loaded:
		for id in people:
			for index in people[id].known_facts.size(): memory.put(id,"fact",str(index),{"text":people[id].known_facts[index],"source":"开场共同经历"},0.95,true)
	working_events=memory.short_events;working_tasks=memory.tasks
	refresh_memory_views()
	return memory.save()

func hear(id: String, event: Dictionary) -> void:
	for previous in people[id].heard_events:
		if previous.id==event.id: return # 已收到的同一事件在进入决策队列时不重复写记忆。
	var record := event.duplicate(true)
	# 角色不自动知道还有谁听到了，也看不到他人的判断。
	record.erase("listeners")
	record.erase("positions")
	if record.has("spatial_segments"):
		var visible: Array=[]
		var texts: PackedStringArray=[]
		for segment in record.spatial_segments:
			if not segment.audience.has(id): continue
			var own: Dictionary=segment.duplicate(true)
			own["relative_to_self"]=own.audience[id]
			own.erase("audience")
			visible.append(own)
			texts.append(own.text)
		record.spatial_segments=visible
		record.text=" ".join(texts)
	if not working_events.has(id): working_events[id]=[]
	working_events[id].append({"event":record.duplicate(true),"at":memory.clock})
	people[id].heard_events.append(record)
	memory.put(id,"heard",event.id,record)
	if event.get("speaker","") not in ["","world","body"]: memory.contact(id,event.speaker)

func context_for(id: String) -> Dictionary:
	var context: Dictionary = people[id].duplicate(true)
	context.erase("node")
	context.erase("model")
	context.erase("voice")
	context["working_context"]=working_context(id)
	return context

func working_context(id: String) -> Dictionary:
	var turns: Array=[]
	for entry in working_events.get(id,[]):
		var event: Dictionary=entry.event.duplicate(true)
		preload("res://scripts/skills/egocentric_space.gd").sanitize_event(event)
		# 当天保留全部事件，但续办事件不递归重复整段任务现场；任务另行直接提供。
		if event.get("original_event") is Dictionary:
			event["original_event_id"]=event.original_event.get("id","")
			event.erase("original_event")
		var turn:={"event":event}
		for reflection in people[id].reflections:
			if reflection.event_id==entry.event.id:
				turn["own_reply"]={"text":reflection.public_reply,"status":reflection.public_reply_status}
				turn["own_understanding"]=reflection.private_interpretation
		turns.append(turn)
	var task: Dictionary=working_tasks.get(id,{}).duplicate(true)
	task.erase("observations") # 世界坐标在空间层转换，不能直接给模型。
	return {"recent_turns":turns,"task":task,"meaning":"当天短期经历直接可用，own_understanding是自己当时的理解而非世界事实；自己的台词是否真正说出以status为准。task是此前接受的任务记录，不覆盖玩家当前的取消或改口；停止不等于完成。"}

func remember_skill(id: String, subject: String, goal: String, kind: String, source: String, event_id: String) -> void:
	assert(people.has(id) and people.has(subject))
	assert(kind in ["observed","claim","taught","test_history"])
	var records: Array=people[id].skill_knowledge
	for item in records:
		if item.event_id==event_id and item.person_id==subject and item.goal_id==goal: return
	records.append({"person_id":subject,"goal_id":goal,"source_kind":kind,"source":source,"event_id":event_id,"recorded_at":Time.get_datetime_string_from_system(),"meaning":"过去的线索，不保证对方现在有空或愿意教"})
	memory.put(id,"skill",event_id+"/"+subject+"/"+goal,records[-1],0.7)

func remember(id: String, event_id: String, decision: Dictionary, action_snapshot: Dictionary={}) -> void:
	var has_action: bool=decision.get("skill_call")!=null or decision.get("intent","none") not in ["none", ""] or decision.get("learning_request")!=null or decision.get("revision_request")!=null
	var event: Dictionary=event_for(id,event_id)
	var previous: Dictionary=working_tasks.get(id,{})
	# 对话参与和任务归属是不同维度：沉默执行本次命令不能被错接到旧任务。
	var scope: String=decision.get("task_handling",{}).get("scope","independent")
	var independent: bool=scope=="independent"
	var notification: bool=scope=="existing_request"
	var cancels_existing: bool=notification and decision.get("task_handling",{}).get("state")=="cancelled"
	if has_action and independent: independent_actions[id+"/"+event_id]=true
	# 先询问/等待/说明受阻也已开始处理请求，不能等到真正动手才记住任务来源。
	var accepts_request: bool=is_person_request(event.get("original_event",event)) and decision.get("task_status")=="active" and decision.get("task_handling",{}).get("state") in ["ask","wait","blocked"]
	if (has_action or accepts_request) and not independent:
		var request: Dictionary=event.get("original_event",event).duplicate(true)
		# 收到物品/身体需求是中途事实，不是新任务。保留玩家或同伴的明确原请求。
		if notification:
			request=previous.request.duplicate(true)
		preload("res://scripts/skills/egocentric_space.gd").sanitize_event(request)
		# “开始/继续”是触发语，任务还依赖此前原话与澄清；绑定当时现场，
		# 不能让后续动作结果挤出短期窗口后只剩这句省略语。语义仍由人物判断。
		if not request.has("request_context"):
			var evidence: Array=[]
			for turn in working_context(id).recent_turns:
				if turn.event.get("speaker")!="player": continue
				evidence.append({"id":turn.event.id,"text":turn.event.get("text",""),"own_reply":turn.get("own_reply",{})})
			request["request_context"]=evidence
		var old_request: Dictionary=previous.get("request",{})
		if is_person_request(old_request) and is_person_request(request) and old_request.get("id")!=request.id:
			superseded_tasks[id+"/"+str(old_request.id)]=request.id
		var same: bool=previous.get("request",{}).get("id")==request.id
		working_tasks[id]={"request":request,"action_event_id":event_id,"state":"action_submitted" if has_action else decision.task_handling.state,"last_call":decision.get("skill_call"),"understanding":previous.get("understanding",decision.private_interpretation) if same else decision.private_interpretation,"observations":previous.get("observations",{}) if same else memory.observations[id].duplicate(true),"progress":previous.get("progress",[]) if same else [],"meaning":"正在处理的明确请求，已选择一步行动或询问/等待/受阻，不代表整个请求完成；understanding是接下任务时自己的理解，观察位置是当时所见，不保证物品现在仍在那里。"}
		# 等待已启动的动作时，完成通知仍来自动作原来的事件，而非这句新话。
		# 使用模型实际收到的快照：模型思考期间动作可能已结束。
		if not has_action and decision.get("task_handling",{}).get("state")=="wait" and action_snapshot.get("status")=="执行中" and action_snapshot.get("source_event_id","")!="":
			var running_source: String=action_snapshot.source_event_id
			working_tasks[id].action_event_id=running_source
			working_tasks[id]["waiting_action_event_id"]=running_source
			working_tasks[id]["wait_decision_event_id"]=event_id
			for result in people[id].execution_results:
				if result.get("source_event_id")==running_source:
					var outcome:={"result":result.duplicate(true)}
					preload("res://scripts/skills/egocentric_space.gd").sanitize_event(outcome)
					working_tasks[id]["last_result"]=outcome.result
	elif not independent and working_tasks.has(id) and event_for(id,event_id).get("kind","")=="skill_progress":
		working_tasks[id].state="stopped_no_action"
		working_tasks[id]["stop_reason"]=decision.get("routing_reason","")
	if not independent and working_tasks.has(id) and decision.has("task_handling"):
		working_tasks[id]["handling"]=decision.task_handling.duplicate(true)
		if decision.task_handling.state not in ["execute","none"]: working_tasks[id].state=decision.task_handling.state
		memory.dirty=true
	if not independent and working_tasks.has(id) and decision.get("task_status") in ["completed","cancelled"]:
		working_tasks[id].state=decision.task_status
		memory.dirty=true
	people[id].reflections.append({"event_id":event_id,"recorded_time":Time.get_datetime_string_from_system(),"private_interpretation":decision.private_interpretation,"public_reply":decision.public_reply,"public_reply_status":"保持沉默" if decision.public_reply.strip_edges().is_empty() else "已生成，尚未播放"})
	memory.put(id,"reflection",event_id,people[id].reflections[-1],0.4)

func is_person_request(event: Dictionary) -> bool:
	return event.get("speaker")=="player" or (people.has(event.get("speaker","")) and event.get("kind") in ["social_request","information_request","item_offer"])

func mark_reply(id: String, event_id: String, status: String) -> void:
	assert(status in ["正在向玩家播放，尚未完整说完","已向玩家播放完成；未投递给其他成员","已播放完成；附近成员听闻另行记录","播放失败，不能确认玩家听到了完整答复"])
	for reflection in people[id].reflections:
		if reflection.event_id == event_id:
			reflection.public_reply_status = status
			memory.put(id,"reflection",event_id,reflection,0.4)
			return
	assert(false,"播放事件找不到对应的人物答复："+event_id)

func record_execution(result: Dictionary) -> void:
	var person: Dictionary=people[result.person_id]
	var record:=result.duplicate(true)
	record["recorded_time"]=Time.get_datetime_string_from_system()
	if working_tasks.has(result.person_id) and working_tasks[result.person_id].get("action_event_id","")==str(result.source_event_id):
		var outcome: Dictionary={"result":record.duplicate(true)}
		preload("res://scripts/skills/egocentric_space.gd").sanitize_event(outcome)
		working_tasks[result.person_id]["last_result"]=outcome.result
		working_tasks[result.person_id].progress.append(outcome.result.duplicate(true))
		if working_tasks[result.person_id].get("state")!="cancelled":
			working_tasks[result.person_id].state="awaiting_judgement"
	# 本人刚做过的动作属于当天经历；自主行动也不能只存入需要检索的长期记录。
	var feedback:={"id":str(result.source_event_id)+"/execution/"+str(result.get("skill_ref",result.get("intent","action"))),"kind":"skill_execution","speaker":"world","text":str(result.get("message","动作结果")),"result":record.duplicate(true)}
	preload("res://scripts/skills/egocentric_space.gd").sanitize_event(feedback)
	hear(result.person_id,feedback)
	person.execution_results.append(record)
	memory.put(result.person_id,"action",str(result.source_event_id)+"/"+str(result.get("skill_ref",result.get("intent","action"))),record,0.5)

func execution_evidence(id: String, ref: String) -> Array:
	# 修订读取本人该版本的真实执行记录，包含尚未日终整理的短期动作。
	# 不能用只检索长期记忆的recall代替，否则刚发生的失败会被漏掉。
	return people[id].execution_results.filter(func(record):return record.get("skill_ref","")==ref).slice(-4).duplicate(true)

func save_snapshot(path: String) -> Error:
	var memory_error: String=memory.save()
	if memory_error!="": push_error(memory_error);return ERR_CANT_CREATE
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema":1,"people":people}, "\t"))
	return OK

func event_for(id: String, event_id: String) -> Dictionary:
	for event in people[id].heard_events:
		if event.id==event_id: return event.duplicate(true)
	assert(false,"找不到本轮听闻："+event_id)
	return {}

func refresh_memory_views() -> void:
	for id in people:
		people[id].heard_events=memory.retained(id,"heard")
		people[id].reflections=memory.retained(id,"reflection")
		people[id].execution_results=memory.retained(id,"action")
		people[id].skill_knowledge=memory.retained(id,"skill")
