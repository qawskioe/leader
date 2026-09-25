extends RefCounted
## 承诺与实际进度分开：本人知道执行结果，请求者只知道听到的答应。
var tasks: Dictionary={}
var promises: Dictionary={}

func accept(assistance: Dictionary, helper: String, now: float, event_id: String = "") -> void:
	if assistance.is_empty(): return
	var id: String=assistance.request_id
	if tasks.has(id) and tasks[id].status=="satisfied": return
	tasks[id]={"assistance":assistance.duplicate(true),"helper":helper,"event_id":event_id,"status":"working","last_result":"","next_check":now+20.0}

func heard_acceptance(assistance: Dictionary, helper: String, text: String, now: float) -> void:
	if assistance.is_empty(): return
	promises[assistance.requester_id]={"request_id":assistance.request_id,"helper_id":helper,"last_heard":text,"wait_until":now+240.0}

func world_fact(value: Dictionary) -> void:
	var origin: Dictionary=value.get("origin",{})
	var request_id: String=origin.get("request_id","")
	if value.kind=="given" and tasks.has(request_id) and value.get("recipient_id")==tasks[request_id].assistance.requester_id:
		tasks[request_id].status="delivered"
	if value.kind=="consumed":
		if origin.get("requester_id")==value.person_id and tasks.has(request_id): tasks[request_id].status="satisfied"
		promises.erase(value.person_id)

func context(id: String, now: float) -> Dictionary:
	var own: Array=[]
	for task in tasks.values():
		if task.helper==id and task.status not in ["satisfied","cancelled"]: own.append(task.duplicate(true))
	var waiting: Dictionary=promises.get(id,{}).duplicate(true)
	if not waiting.is_empty():
		waiting["wait_seconds_left"]=maxf(0,waiting.wait_until-now)
		waiting.erase("wait_until")
	return {"own_help_tasks":own,"heard_help_promise":waiting}

func reset() -> void:
	tasks.clear(); promises.clear()

func cancel_helper(helper: String) -> Array:
	var cancelled: Array=[]
	for id in tasks:
		if tasks[id].helper==helper and tasks[id].status not in ["satisfied","cancelled"]:
			tasks[id].status="cancelled"
			cancelled.append(id)
	return cancelled
