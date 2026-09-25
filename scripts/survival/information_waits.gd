extends RefCounted
## 记录本人问过却尚未听到答复的询问，不向本人泄露目标是否听见。
const WAIT_SECONDS:=45.0
const MAX_CHECKS:=2
var pending: Dictionary={}
var checks: Dictionary={}

func begin(speaker: String, target: String, event: Dictionary, question: String, now: float) -> void:
	var original: Dictionary=event.get("original_event",event).duplicate(true)
	var key: String=str(original.id)+"/"+speaker+"/"+target
	if int(checks.get(key,0))>=MAX_CHECKS:return
	# 新询问替换同一人对同一对象的旧等待，避免旧计时器追着新问题触发。
	for id in pending.keys():
		if pending[id].speaker==speaker and pending[id].target==target:pending.erase(id)
	var id: String=str(event.id)+"_request_"+target
	pending[id]={"speaker":speaker,"target":target,"source_event_id":event.id,"original_event":original,"question":question,"due":now+WAIT_SECONDS,"key":key}

func heard_reply(reply_event_id: String, speaker: String, audience: Array) -> String:
	if not pending.has(reply_event_id):return ""
	var wait: Dictionary=pending[reply_event_id]
	if speaker!=wait.target or wait.speaker not in audience:return ""
	pending.erase(reply_event_id)
	return wait.speaker

func next_event(now: float, actors: Dictionary) -> Dictionary:
	for id in pending:
		var wait: Dictionary=pending[id]
		if wait.get("notified",false) or now<wait.due or actors[wait.speaker].stage!="idle":continue
		wait["notified"]=true
		var count: int=int(checks.get(wait.key,0))+1
		checks[wait.key]=count
		if checks.size()>256:checks.erase(checks.keys()[0])
		return {"id":id+"_unanswered","kind":"information_unanswered","speaker":"world","listeners":[wait.speaker],"source_event_id":wait.source_event_id,"original_event":wait.original_event,"text":"你先前问：“%s”。已经等了一段时间，尚未听到对应回答。你不知道对方是否听见，也不能据此认定对方拒绝。结合原请求与当前观察，自行决定靠近、换办法、继续等待或向玩家说明；不要把询问当作完成。"%wait.question,"trigger":{"reason":"no_reply_heard","wait_seconds":WAIT_SECONDS,"check_number":count,"max_checks":MAX_CHECKS}}
	return {}

func reset() -> void:
	pending.clear();checks.clear()
