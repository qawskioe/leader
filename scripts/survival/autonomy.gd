extends RefCounted
## 程序只安排何时判断，不替模型选择动作。时钟使用游戏进程的单调时间。
var last: Dictionary={}
var signatures: Dictionary={}
var need_states: Dictionary={}
var last_events: Dictionary={}
var requests: Array[Dictionary]=[]
var seen: Array[String]=[]
var calls: Array[float]=[]
var repeated: Dictionary={}
var task_player_views: Dictionary={}
var pending_player_views: Dictionary={}
var retry_seconds:=90.0
var minimum_interval:=20.0
var calls_per_minute:=4
var ready_at:=8.0

func reset(now: float) -> void:
	last.clear()
	signatures.clear()
	need_states.clear(); last_events.clear()
	requests.clear()
	seen.clear()
	calls.clear()
	repeated.clear()
	task_player_views.clear()
	pending_player_views.clear()
	ready_at=now+8.0

func watch_player(id: String, event_id: String, observation: Dictionary, own_position: Vector3) -> void:
	# 保存判断开始时本人看到的事实；模型返回前玩家可能已经跟近，不能以返回时现场作为旧基线。
	pending_player_views[id]={"event_id":event_id,"view":_player_view(observation,own_position)}

func finish_player_watch(report: Dictionary, task: Dictionary, belongs_to_task: bool=true) -> void:
	var id: String=report.person_id
	var pending: Dictionary=pending_player_views.get(id,{})
	if pending.is_empty() or pending.event_id!=report.event_id:return
	pending_player_views.erase(id)
	if not report.has("decision") or not belongs_to_task:return
	# 身体需求或旁听可能独立于原任务，不能覆盖原任务等待的距离基线。
	if report.decision.task_handling.scope=="independent":return
	if task.get("state") not in ["wait","ask"] or task.get("request",{}).get("speaker")!="player":
		task_player_views.erase(id)
		return
	# 等待判断与行动来源可能不同：例如中途需求判断选择继续等待，
	# 或判断时旧动作仍在执行。通知关联真实任务，基线仍取该判断开始时的观察。
	task_player_views[id]={"event_id":task.action_event_id,"view":pending.view,"dispatched":false}

static func _player_view(observation: Dictionary, own_position: Vector3) -> Dictionary:
	if not observation.get("visible_now",false):return {"visible":false}
	var at: Array=observation.position
	return {"visible":true,"distance_m":own_position.distance_to(Vector3(at[0],at[1],at[2]))}

func next_wait_event(now: float, tasks: Dictionary, actors: Dictionary, memories: Dictionary) -> Dictionary:
	for id in tasks:
		var task: Dictionary=tasks[id]
		if task.get("state") not in ["wait","ask"] or task.get("request",{}).get("speaker")!="player" or actors[id].stage!="idle":continue
		var watched: Dictionary=task_player_views.get(id,{})
		if watched.is_empty() or watched.dispatched or watched.event_id!=task.get("action_event_id",""):continue
		var current:=_player_view(memories.get(id,{}).get("person/player",{}),actors[id].body.global_position)
		if not current.visible:continue
		var before: Dictionary=watched.view
		var movement_threshold: float=preload("res://scripts/survival/perception.gd").SIGNIFICANT_MOVE_M
		if before.visible and absf(current.distance_m-before.distance_m)<movement_threshold:
			watched.erase("pending_view");watched.erase("pending_since")
			continue
		# 玩家走近通常持续一段时间；合并半秒内的连续变化，避免在半途和到达后各等一轮模型。
		if not watched.has("pending_view") or absf(current.distance_m-watched.pending_view.distance_m)>=movement_threshold:
			watched["pending_view"]=current;watched["pending_since"]=now
			continue
		if now-watched.pending_since<0.5:continue
		watched.dispatched=true
		return {"id":"task_observation_%s_%d"%[id,Time.get_ticks_usec()],"kind":"task_observation_changed","speaker":"world","listeners":[id],"source_event_id":watched.event_id,"original_event":task.request.duplicate(true),"trigger":{"observed_at_seconds":now,"player_visible":true,"player_distance_m":current.distance_m},"text":"你重新看见玩家，或观察到玩家与你的距离发生变化。结合当前亲眼观察和原请求，决定继续行动还是保持等待。"}
	return {}

func offer_request(event: Dictionary, now: float) -> bool:
	if event.id in seen: return false
	seen.append(event.id)
	if seen.size()>256: seen.pop_front()
	# 每次执行结果都是新事实，即使错误文案相同，也必须送回本人判断。
	# 同一event.id仍去重；任务步数上限由调用方控制。
	# 程序事实／检查点可能文字相同但来源或时刻不同；身份去重即可，不能当重复请求吞掉。
	if event.get("speaker") in ["world","body"] or event.get("kind","") in ["skill_progress","information_unanswered","social_reply"]:
		requests.append(event.duplicate(true))
		return true
	var key: String=event.speaker+"/"+event.listeners[0]+"/"+event.text.strip_edges()
	if now-float(repeated.get(key,-10000.0))<retry_seconds: return false
	repeated[key]=now
	if repeated.size()>256: repeated.erase(repeated.keys()[0])
	requests.append(event.duplicate(true))
	return true

func next_task_event(now: float, actors: Dictionary) -> Dictionary:
	# 玩家任务的结果续办独立于饥饿等自主活动；不继承20秒需求判断间隔。
	for index in requests.size():
		var event: Dictionary=requests[index]
		if event.get("kind","") not in ["skill_progress","skill_ready","skill_revised","social_reply","session_restored","session_checkpoint"]: continue
		if event.get("original_event",{}).get("speaker")!="player": continue
		# 忙碌拒绝正是需要决定是否中止旧动作的时刻，不能等旧动作完成才告知。
		var busy_failure: bool=event.get("result",{}).get("category")=="busy" and not event.get("result",{}).get("success",true)
		if actors[event.listeners[0]].stage!="idle" and not busy_failure: continue
		requests.remove_at(index)
		last_events[event.listeners[0]]=event.id
		return event
	return {}

func next_event(now: float, people: Dictionary, actors: Dictionary) -> Dictionary:
	while not calls.is_empty() and calls[0]<=now-60.0: calls.pop_front()
	if now<ready_at or calls.size()>=calls_per_minute: return {}
	for index in requests.size():
		var request: Dictionary=requests[index]
		var id: String=request.listeners[0]
		if actors[id].stage!="idle" or now-float(last.get(id,-10000.0))<minimum_interval: continue
		requests.remove_at(index)
		_charge(id,now)
		last_events[id]=request.id
		return request
	var selected:=""
	var greatest:=-1.0
	for id in people:
		var person: Dictionary=people[id]
		var promise: Dictionary=person.get("help_context",{}).get("heard_help_promise",{})
		var plate: Variant=person.get("survival_observation",{}).get("carried_food",0)
		if not promise.is_empty() and promise.get("wait_seconds_left",0)>0 and person.needs.get("thirst",0)<60 and person.needs.hunger<95 and (plate==null or plate==0): continue
		var urgency: float=maxf(person.needs.hunger,person.needs.get("thirst",0))
		if urgency<60 or actors[id].stage!="idle": continue
		var elapsed:=now-float(last.get(id,-10000.0))
		var signature:=JSON.stringify(_need_state(person,need_states.get(id,{})))
		if elapsed<minimum_interval: continue
		if signatures.get(id,"")==signature and elapsed<retry_seconds: continue
		if urgency>greatest:
			selected=id
			greatest=urgency
	if selected.is_empty(): return {}
	var state:=_need_state(people[selected],need_states.get(selected,{}))
	var changes: Dictionary={}
	for key in state:
		if need_states.has(selected) and need_states[selected].get(key)!=state[key]:
			if key=="resources":
				var before: Dictionary=need_states[selected].get(key,{})
				var objects: Array=[]
				for object_id in before.keys()+state.resources.keys():
					if object_id not in objects and before.get(object_id)!=state.resources.get(object_id):objects.append(object_id)
				changes[key]={"objects":objects}
			else:changes[key]={"before":need_states[selected].get(key),"after":state[key]}
	var reason: String="need_initial" if not signatures.has(selected) else ("need_retry" if changes.is_empty() else "need_changed")
	var trigger:={"reason":reason,"elapsed_seconds":now-float(last.get(selected,now)),"thirst":people[selected].needs.get("thirst",0),"hunger":people[selected].needs.hunger,"changes":changes}
	var previous: String=last_events.get(selected,"")
	signatures[selected]=JSON.stringify(state)
	need_states[selected]=state
	_charge(selected,now)
	var event:={"id":"need_%s_%d"%[selected,int(now*1000)],"kind":"need_changed","speaker":"body","listeners":[selected],"trigger":trigger,"source_event_id":previous,"text":"当前身体需求需要处理。结合本人需求、已知物资、已接受的任务和附近成员，判断此刻要行动、求助还是等待。"}
	last_events[selected]=event.id
	return event

func _need_state(person: Dictionary, previous: Dictionary={}) -> Dictionary:
	var observation: Dictionary=person.get("survival_observation",{})
	return {"thirst_band":int(person.needs.get("thirst",0)/20),"personal_water":observation.get("personal_water",0),"hunger_band":int(person.needs.hunger/20),"carried_food":observation.get("carried_food"),"holding_basket":observation.get("holding_basket"),"resources":_need_resources(person,previous.get("resources",{})),"personal_basket_food":observation.get("personal_basket_food")}

func _need_resources(person: Dictionary, previous: Dictionary) -> Dictionary:
	# 调度依据本人已知的相关物资；笼统知识版本包含人物/空容器移动，不能催发需求。
	# 这份投影只用于触发去重，完整观察与精确坐标仍照常提供给人物判断。
	var result: Dictionary={}
	var hungry: bool=person.needs.hunger>=60
	var thirsty: bool=person.needs.get("thirst",0)>=60
	var known: Dictionary=person.get("survival_observation",{}).get("known_objects",{})
	for key in known:
		var entry: Dictionary=known[key]
		var extra: Dictionary=entry.get("extra",{})
		var kind: String=entry.kind
		var food_count: Variant=extra.get("food_count",0)
		var water_count: Variant=extra.get("water",0)
		# 亲手存取只确认本次变化，库存总量可为null；不能据此伪造正数物资。
		var food: int=1 if kind=="fruit" and entry.get("available",false) else (0 if food_count==null else int(food_count))
		var water: int=1 if kind=="water_source" and entry.get("available",false) else (0 if water_count==null else int(water_count))
		if not ((hungry and food>0) or (thirsty and water>0)):continue
		var fact:={"kind":kind,"available":entry.get("available",false),"holder":extra.get("holder","")}
		if hungry:fact["food"]=food
		if thirsty:fact["water"]=water
		# 别人手中的食水可求助；普通携带移动不改变这项机会。落地物资有实质移动才通知。
		if fact.holder=="" and fact.available and entry.has("position"):
			var position: Array=entry.position
			var prior: Dictionary=previous.get(key,{}).duplicate()
			var anchor: Array=prior.get("position",position)
			prior.erase("position")
			if prior==fact and Vector3(position[0],position[1],position[2]).distance_to(Vector3(anchor[0],anchor[1],anchor[2]))<preload("res://scripts/survival/perception.gd").SIGNIFICANT_MOVE_M:
				position=anchor
			fact["position"]=position.duplicate()
		result[key]=fact
	return result

func _charge(id: String, now: float) -> void:
	last[id]=now
	calls.append(now)
