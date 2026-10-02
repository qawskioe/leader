extends SceneTree
## 不启动世界或模型：复现学习结束后、续办尚未调度就收到新教导。
class QuietVoice extends "res://scripts/voice/voice_test.gd":
	func log_event(_record: Dictionary) -> void:
		pass

class RejectSkills extends Node:
	func request_learning(_id: String, _event: Dictionary, _request: Dictionary) -> Dictionary:
		return {"ok":false,"error":"缺少编写服务环境"}
	func request_revision(_id: String, _event: Dictionary, _request: Dictionary) -> Dictionary:
		return {"ok":false,"error":"人物正在忙碌"}

func _initialize() -> void:
	var voice:=QuietVoice.new()
	var file:="user://learning_memory_probe_%d.json"%Time.get_ticks_usec()
	assert(voice.store.initialize("res://data/people.json",file,true).is_empty())
	var person:="person_002"
	var original:={"id":"teach_bag","speaker":"player","text":"修正举袋示意"}
	voice._on_learning_finished({"person_id":person,"ok":false,"message":"未落稳",
		"job":"draft_failed","goal_id":"bag_raise_demo","goal":"举袋后释放",
		"original_event":original})
	assert(voice.autonomy.requests.size()==1,"事实记录不能吞掉待续办事件")
	voice.store.hear(person,{"id":"continue_bag","speaker":"player","text":"继续刚才的修正"})
	var turns: Array=voice.store.context_for(person).working_context.recent_turns
	assert(turns[0].event.goal_id=="bag_raise_demo","未调度续办前也必须知道原学习目标")
	assert(turns[0].event.learning_failed and turns[1].event.id=="continue_bag")
	var failure: Dictionary=voice.autonomy.requests[0]
	voice.store.hear(person,failure)
	assert(voice.store.working_context(person).recent_turns.size()==2,"之后调度不能重复记录结果")
	assert(voice.store.working_context("person_003").recent_turns.is_empty(),"学习私有结果不能泄露给旁观者")
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
	voice.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	print("LEARNING_RESULT_MEMORY_PASSED immediate_result, continuation_dedupe, private_context, persistence; real_model_calls=0")
	quit()
