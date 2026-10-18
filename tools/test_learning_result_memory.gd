extends SceneTree
## 不启动世界或模型：复现学习结束后、续办尚未调度就收到新教导。
class QuietVoice extends "res://scripts/voice/voice_test.gd":
	func log_event(_record: Dictionary) -> void:
		pass

class RejectSkills extends Node:
	var received: Array=[]
	func request_learning(_id: String, _event: Dictionary, _request: Dictionary) -> Dictionary:
		received.append(_event.duplicate(true))
		return {"ok":false,"error":"缺少编写服务环境"}
	func request_revision(_id: String, _event: Dictionary, _request: Dictionary) -> Dictionary:
		return {"ok":false,"error":"人物正在忙碌"}

func _initialize() -> void:
	create_timer(10).timeout.connect(func():push_error("学习反馈夹具超时");quit(1))
	var voice:=QuietVoice.new()
	var file:="user://learning_memory_probe_%d.json"%Time.get_ticks_usec()
	assert(voice.store.initialize("res://data/people.json",file,true).is_empty())
	var person:="person_002"
	var review_marker:="host_only_review_"+"x".repeat(1048576)
	voice.store.people[person]["learning"]={"state":"failed","goal":"带玩家找到熟人","message":"这次没有学会","technical_message":"host_only_builder_event","review":{"issues":[{"runtime":{"trace":[review_marker]}}]}}
	var public_context: Dictionary=voice.store.context_for(person)
	assert(public_context.learning.state=="failed" and public_context.learning.goal=="带玩家找到熟人" and public_context.learning.message=="这次没有学会")
	assert(not public_context.learning.has("review") and not public_context.learning.has("technical_message"),"离线验收轨迹属于开发记录，不能成为人物上下文")
	var wire: Dictionary=preload("res://scripts/voice/decision_pipeline.gd").request_for(public_context,{"id":"review_isolation_probe","speaker":"player","text":"继续"})
	assert(not JSON.stringify(wire).contains("host_only_"),"完整日常模型输入不得包含原始编写事件或验收轨迹")
	assert(voice.store.people[person].learning.review.issues[0].runtime.trace[0]==review_marker,"人物上下文隔离不能删掉开发诊断原件")
	var original:={"id":"teach_bag","speaker":"player","text":"修正举袋示意"}
	voice.store.working_tasks[person]={"request":original,"state":"action_submitted"}
	voice._on_learning_finished({"person_id":person,"ok":false,"message":"未落稳",
		"job":"draft_failed","goal_id":"bag_raise_demo","goal":"举袋后释放",
		"original_event":original})
	assert(voice.store.working_tasks[person].state=="paused_budget","结束的失败学习不能在读取存档时自动重启")
	assert(voice.autonomy.requests.size()==1,"事实记录不能吞掉待续办事件")
	voice.store.hear(person,{"id":"continue_bag","speaker":"player","text":"继续刚才的修正"})
	var turns: Array=voice.store.context_for(person).working_context.recent_turns
	assert(turns[0].event.goal_id=="bag_raise_demo","未调度续办前也必须知道原学习目标")
	assert(turns[0].event.learning_failed and turns[1].event.id=="continue_bag")
	var failure: Dictionary=voice.autonomy.requests[0]
	voice.store.hear(person,failure)
	assert(voice.store.working_context(person).recent_turns.size()==2,"之后调度不能重复记录结果")
	assert(voice.store.working_context("person_003").recent_turns.is_empty(),"学习私有结果不能泄露给旁观者")
	assert((await voice.store.memory.flush_pending(self)).is_empty())
	var restored=preload("res://scripts/voice/people_store.gd").new()
	assert(restored.initialize("res://data/people.json",file).is_empty())
	assert(restored.working_context(person).recent_turns[0].event.goal_id=="bag_raise_demo")
	voice._on_learning_finished({"person_id":person,"ok":true,"message":"已学会",
		"job":"draft_ready","ref":"verified_ref","original_event":original})
	assert(voice.store.working_context(person).recent_turns[-1].event.kind=="skill_ready")
	var command:={"id":"gather_four","speaker":"player","kind":"speech_intent","text":"右手拿篮，采四个果子存好"}
	voice._on_learning_finished({"person_id":person,"ok":true,"message":"已修订",
		"job":"gather_ready","ref":"gather_new","revision_of":"gather_old","original_event":command})
	var continued: Dictionary=voice.autonomy.requests[-1]
	assert(continued.kind=="skill_revised" and continued.original_event==command)
	assert(continued.source_event_id==command.id and continued.skill_ref=="gather_new")
	assert(voice.store.working_context(person).recent_turns[-1].event.kind=="skill_revised","续办排队前保存学习结果")
	voice._allow_execution=true;voice.config["actions_enabled"]=true;voice._job_config={"actions_enabled":true}
	var reject:=RejectSkills.new();voice.add_child(reject);voice.skills=reject
	for kind in ["learn","revise"]:
		var input:={"id":"rejected_"+kind,"speaker":"player","kind":"speech_intent","text":"学会新的方法"}
		voice.store.hear(person,input)
		voice.store.working_tasks[person]={"request":input,"action_event_id":input.id,"state":"action_submitted"}
		var count: int=voice.autonomy.requests.size()
		if kind=="learn":voice._begin_self_learning(person,input.id,{"learning_request":{"goal_id":"new_method","goal":"新方法"}})
		else:voice._begin_revision(person,input.id,{"ref":"known_skill","feedback":"修正方法"})
		assert(voice.autonomy.requests.size()==count+1,"立即拒绝必须进入本人续办队列")
		var denied: Dictionary=voice.autonomy.requests[-1]
		assert(denied.learning_failed and not denied.learning_started and denied.original_event==input)
		assert(denied.text.contains("环境" if kind=="learn" else "忙碌"))
		assert(voice.store.working_tasks[person].state=="submission_failed")
		assert(voice.store.working_context(person).recent_turns[-1].event.id==denied.id)
		assert(not voice.store.working_context("person_003").recent_turns.any(func(t):return t.event.id==denied.id))
		if kind=="learn":
			var before: int=voice.autonomy.requests.size()
			voice._begin_self_learning(person,denied.id,{"learning_request":{"goal_id":"new_method","goal":"新方法"}})
			var received: Dictionary=reject.received[-1]
			assert(received.id==denied.id and received.learning_failed and received.original_event.id==input.id,"当前失败身份必须传到提交边界，不能解包成原请求")
			assert(voice.autonomy.requests.size()==before,"失败反馈的重复提交不能继续生成反馈循环")
			assert(voice.store.working_tasks[person].state=="paused_budget")
	var source:={"id":"drink_return_request","kind":"speech_intent","speaker":"player","text":"喝一份水后把原袋还给我"}
	var need:={"id":"thirst_changed","kind":"need_changed","speaker":"body","text":"你的口渴需要处理"}
	voice.store.hear(person,source);voice.store.hear(person,need)
	voice.store.working_tasks[person]={"request":source.duplicate(true),"state":"action_submitted","action_event_id":need.id}
	var continuation:={"learning_request":{"goal_id":"drink_return","goal":"喝一份并归还原袋"},"task_handling":{"scope":"existing_request","state":"execute"}}
	voice._begin_self_learning(person,need.id,continuation)
	var received: Dictionary=reject.received[-1]
	assert(received.id==need.id and received.kind=="need_changed","当前事实身份不能被原请求覆盖")
	assert(received.original_event==source,"继续原任务的编写目标必须绑定玩家原话，不能改成身体需求")
	assert(not voice.store.event_for(person,need.id).has("original_event"),"来源绑定只用于提交副本，不改人物听闻记录")
	var failure_event:={"id":"drink_return_failed","kind":"skill_progress","speaker":"world","learning_failed":true,"original_event":source.duplicate(true)}
	voice.store.hear(person,failure_event)
	voice._begin_self_learning(person,failure_event.id,continuation)
	received=reject.received[-1]
	assert(received.learning_failed and received.kind=="skill_progress" and received.original_event==source,"来源绑定不能绕过当前学习失败检查")
	for kind in ["session_restored","skill_progress"]:
		var root_request:={"id":"rejected_root_"+kind,"speaker":"player","kind":"speech_intent","text":"原带路请求"}
		var trigger:={"id":root_request.id+"_trigger","speaker":"world","kind":kind,"original_event":root_request.duplicate(true)}
		voice.store.hear(person,trigger)
		voice.store.working_tasks[person]={"request":root_request,"action_event_id":trigger.id,"state":"action_submitted"}
		voice._begin_revision(person,trigger.id,{"ref":"known_skill","feedback":"修正当前方法"})
		var rejected: Dictionary=voice.autonomy.requests[-1]
		assert(rejected.learning_failed and rejected.original_event==root_request and rejected.source_event_id==trigger.id,"立即拒绝保留触发身份，续办须绑定原请求")
		assert(voice._notification_has_task(rejected),"立即拒绝不能把原任务结果误判为独立通知")
		voice.store.superseded_tasks[person+"/"+root_request.id]="new_request"
		assert(voice._task_was_cancelled(person,rejected),"后来的新任务须能过滤已拒绝的旧学习通知")
	assert((await voice.store.memory.flush_pending(self)).is_empty())
	voice.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	print("LEARNING_RESULT_MEMORY_PASSED immediate_result, continuation_dedupe, private_context, persistence; real_model_calls=0")
	quit()
