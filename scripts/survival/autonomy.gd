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
	ready_at=now+8.0

func offer_request(event: Dictionary, now: float) -> bool:
	if event.id in seen: return false
	seen.append(event.id)
	if seen.size()>256: seen.pop_front()
	# 每次执行结果都是新事实，即使错误文案相同，也必须送回本人判断。
	# 同一event.id仍去重；任务步数上限由调用方控制。
	if event.get("kind","") in ["skill_progress","information_unanswered","social_reply"]:
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
		if event.get("kind","") not in ["skill_progress","skill_ready","skill_revised","social_reply"]: continue
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
		var signature:=_signature(person)
		if elapsed<minimum_interval: continue
		if signatures.get(id,"")==signature and elapsed<retry_seconds: continue
		if urgency>greatest:
			selected=id
			greatest=urgency
	if selected.is_empty(): return {}
	var state:=_need_state(people[selected])
	var changes: Dictionary={}
	for key in state:
		if need_states.has(selected) and need_states[selected].get(key)!=state[key]:
			changes[key]={"before":need_states[selected].get(key),"after":state[key]}
	var reason: String="need_initial" if not signatures.has(selected) else ("need_retry" if changes.is_empty() else "need_changed")
	var trigger:={"reason":reason,"elapsed_seconds":now-float(last.get(selected,now)),"thirst":people[selected].needs.get("thirst",0),"hunger":people[selected].needs.hunger,"changes":changes}
	var previous: String=last_events.get(selected,"")
	signatures[selected]=_signature(people[selected])
	need_states[selected]=state
	_charge(selected,now)
	var event:={"id":"need_%s_%d"%[selected,int(now*1000)],"kind":"need_changed","speaker":"body","listeners":[selected],"trigger":trigger,"source_event_id":previous,"text":"你的饥饿或口渴达到需要处理的程度。按本人需求数值决定优先吃饭还是喝水，结合已知物资、工作和附近成员，可以行动、求助或等待；没有玩家给你下命令。"}
	last_events[selected]=event.id
	return event

func _need_state(person: Dictionary) -> Dictionary:
	var observation: Dictionary=person.get("survival_observation",{})
	return {"thirst_band":int(person.needs.get("thirst",0)/20),"personal_water":observation.get("personal_water",0),"hunger_band":int(person.needs.hunger/20),"storage_food_seen":observation.get("storage_food_seen"),"carried_food":observation.get("carried_food"),"holding_basket":observation.get("holding_basket"),"knowledge_revision":observation.get("knowledge_revision"),"personal_basket_food":observation.get("personal_basket_food")}

func _signature(person: Dictionary) -> String:
	var observation: Dictionary=person.get("survival_observation",{})
	return JSON.stringify([int(person.needs.get("thirst",0)/20),observation.get("personal_water",0),int(person.needs.hunger/20),observation.get("storage_food_seen"),observation.get("carried_food"),observation.get("holding_basket"),observation.get("knowledge_revision"),observation.get("personal_basket_food")])

func _charge(id: String, now: float) -> void:
	last[id]=now
	calls.append(now)
