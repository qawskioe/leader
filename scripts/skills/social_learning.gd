extends Node
## 只在台词实际传达后建立请求；角色选择老师与是否授课，程序验证权限和时间。
signal event_ready(event: Dictionary)
signal changed(record: Dictionary)
var skills: Node
var sim: Node
var store: RefCounted
var pending: Dictionary={}
var sessions: Dictionary={}
var seen: Dictionary={}
var lesson_seconds:=12.0 # 当前测试用时，不是正式骑射学习时长。
var request_timeout:=90.0

func nearby(a: String, b: String) -> bool:
	return store.people.has(a) and store.people.has(b) and a!=b and sim.actors[a].body.global_position.distance_to(sim.actors[b].body.global_position)<=3.5

func public_decision(speaker: String, event: Dictionary, decision: Dictionary, audience: Array) -> void:
	var action: Dictionary=decision.skill_dialogue
	var target: String=action.person_id
	var ticket: String=str(event.id)+"/"+speaker
	if seen.has(ticket): return
	seen[ticket]=true
	if seen.size()>256: seen.erase(seen.keys()[0])
	if target not in audience or not nearby(speaker,target):
		_feedback(speaker,event,action.goal_id,"对方未在近处听到这次交谈，请重新判断。")
		return
	if action.kind=="ask":
		if sim.actors[speaker].stage!="idle":
			_feedback(speaker,event,action.goal_id,"当前正在忙，尚未开始求教。")
			return
		var original: Dictionary=event.get("original_event",event).duplicate(true)
		var request_id:=ticket+"/lesson"
		pending[request_id]={"student":speaker,"teacher":target,"goal":action.goal_id,"original":original,"elapsed":0.0}
		sim.actors[speaker].stage="skill_wait_teacher"
		store.people[speaker]["learning"]={"message":"正在等"+store.people[target].name+"答复是否愿意教","state":"waiting_teacher"}
		event_ready.emit({"id":request_id,"kind":"skill_lesson_request","speaker":speaker,"listeners":[target],"text":decision.public_reply,"goal_id":action.goal_id,"student_id":speaker,"lesson_request_id":request_id})
		changed.emit({"type":"lesson_requested","person_id":speaker,"teacher":target,"message":"求教已被听见，等待对方自己决定"})
		return
	var request_id: String=event.get("lesson_request_id","")
	if not pending.has(request_id): return
	var request: Dictionary=pending[request_id]
	if request.teacher!=speaker or request.student!=target or request.goal!=action.goal_id: return
	pending.erase(request_id)
	if action.kind=="decline":
		_release(target)
		_feedback(target,request.original,request.goal,store.people[speaker].name+"没有接受这次教学："+decision.public_reply)
		return
	for listener in audience:
		store.remember_skill(listener,speaker,request.goal,"claim",store.people[speaker].name+"亲口表示愿意教",str(event.id))
	_save_knowledge()
	var ref:=""
	for item in skills.library.describe(speaker):
		if skills.library.definitions[item.ref].id==request.goal: ref=item.ref;break
	if ref=="" or sim.actors[speaker].stage!="idle" or not nearby(speaker,target):
		_release(target)
		_feedback(target,request.original,request.goal,"这次没有真正开始教学，对方没有可传授的对应技能或当前不能授课。")
		return
	# 当前不自动赋予复合技能的全部依赖，避免越过独立学习。
	for dependency in skills.library.definitions[ref].get("dependencies",{}).values():
		if skills.library.resolve(target,dependency).is_empty():
			_release(target);_feedback(target,request.original,request.goal,"还缺少这项技能要求的基础技能，本次教学未开始。")
			return
	sessions[request_id]=request.merged({"ref":ref,"elapsed":0.0})
	sim.actors[speaker].stage="skill_teaching";sim.actors[target].stage="skill_studying"
	store.people[speaker]["learning"]={"message":"正在教"+store.people[target].name,"state":"teaching"}
	store.people[target]["learning"]={"message":"正在跟"+store.people[speaker].name+"学习","state":"studying"}
	changed.emit({"type":"lesson_started","person_id":target,"teacher":speaker,"message":"双方开始教学，结束前不会授予技能"})

func _process(delta: float) -> void:
	if not is_instance_valid(sim) or not sim.enabled: return
	for key in pending.keys():
		pending[key].elapsed+=delta
		if pending[key].elapsed>=request_timeout:
			var request: Dictionary=pending[key];pending.erase(key);_release(request.student)
			_feedback(request.student,request.original,request.goal,"等待后仍未得到教学答复，可以重新考虑找人或自行学习。")
	for key in sessions.keys():
		var task: Dictionary=sessions[key]
		if not nearby(task.teacher,task.student) or sim.actors[task.teacher].stage!="skill_teaching" or sim.actors[task.student].stage!="skill_studying":
			sessions.erase(key);_release(task.student);_release(task.teacher)
			_feedback(task.student,task.original,task.goal,"教学中断，尚未学成。")
			continue
		task.elapsed+=delta
		if task.elapsed<lesson_seconds: continue
		sessions.erase(key)
		var error: String=skills.library.learn_from(task.student,task.teacher,task.ref,"向"+store.people[task.teacher].name+"学习，实际教学结束后获得")
		_release(task.student);_release(task.teacher)
		if error!="": _feedback(task.student,task.original,task.goal,error);continue
		skills.sync_person(task.student)
		store.remember_skill(task.student,task.teacher,task.goal,"taught","实际完成了这次教学",key)
		store.remember_skill(task.teacher,task.student,task.goal,"taught","刚刚亲自传授并完成教学",key)
		store.record_execution({"person_id":task.student,"source_event_id":task.original.id,"intent":"learn_skill","success":true,"message":"向"+store.people[task.teacher].name+"学会了"+skills.library.definitions[task.ref].name,"skill_ref":task.ref})
		_save_knowledge()
		store.people[task.student]["learning"]={"message":"已向"+store.people[task.teacher].name+"学会技能","completed":true}
		event_ready.emit({"id":key+"/completed","kind":"skill_ready","speaker":"world","listeners":[task.student],"original_event":task.original,"skill_ref":task.ref,"text":"教学已经完成，你获得了该技能。继续此前原请求："+task.original.text+"。不重复学习，不必播报完成。"})
		changed.emit({"type":"lesson_completed","person_id":task.student,"teacher":task.teacher,"skill_ref":task.ref,"message":"教学完成，已获得同一技能版本的索引"})

func _release(id: String) -> void:
	if sim.actors[id].stage in ["skill_wait_teacher","skill_teaching","skill_studying"]:
		sim.actors[id].stage="idle";sim._sync(id)
	store.people[id]["learning"]={}

func _feedback(id: String, original: Dictionary, goal: String, text: String) -> void:
	event_ready.emit({"id":str(original.id)+"/lesson_feedback/"+str(Time.get_ticks_usec()),"kind":"skill_learning_feedback","speaker":"world","listeners":[id],"original_event":original,"goal_id":goal,"text":text})

func cancel(id: String) -> Array:
	var removed: Array=[]
	for key in pending.keys():
		var request: Dictionary=pending[key]
		if id in [request.student,request.teacher]: removed.append(key);pending.erase(key);_release(request.student)
	for key in sessions.keys():
		var task: Dictionary=sessions[key]
		if id in [task.student,task.teacher]: removed.append(key);sessions.erase(key);_release(task.student);_release(task.teacher)
	return removed

func reset() -> void:
	for id in store.people: cancel(id)
	seen.clear()

func _save_knowledge() -> void:
	var error: String=store.memory.save()
	if error!="": changed.emit({"type":"error","message":error})

func load_knowledge() -> void:
	store.refresh_memory_views()
