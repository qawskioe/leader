extends SceneTree
## 不启动世界或模型：复现学习结束后、续办尚未调度就收到新教导。
class QuietVoice extends "res://scripts/voice/voice_test.gd":
	func log_event(_record: Dictionary) -> void:
		pass

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
	voice.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	print("LEARNING_RESULT_MEMORY_PASSED immediate_result, continuation_dedupe, private_context, persistence; real_model_calls=0")
	quit()
