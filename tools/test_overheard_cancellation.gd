extends SceneTree
func _initialize() -> void:
	var store=preload("res://scripts/voice/people_store.gd").new()
	assert(store.initialize().is_empty())
	var id:="person_002"
	var original:={"id":"gather_request","speaker":"player","kind":"speech_intent","text":"小花，寻找指定篮子。"}
	store.hear(id,original)
	store.remember(id,original.id,{"intent":"explore","private_interpretation":"寻找指定篮子","public_reply":""})
	var heard:={"id":"cancel_while_asking_other","speaker":"player","kind":"speech_intent","text":"月亮，小花在哪里？我想取消她找指定篮子的任务。"}
	store.hear(id,heard)
	store.remember(id,heard.id,{"intent":"none","private_interpretation":"玩家在找我，并取消我的任务","public_reply":"我在这里，不再找篮子了。","conversation":{"participation":"interject"},"task_status":"cancelled","task_handling":{"state":"cancelled","reason":"我已听到对本人旧任务的取消要求"}})
	if store.working_tasks[id].state!="cancelled":
		push_error("模型明确取消本人旧任务，插话分类不能丢掉取消结果")
		quit(1);return
	assert(store.working_tasks[id].request.id==original.id,"取消应关闭旧任务，不能把问别人位置变成自己的新任务")
	store.record_execution({"person_id":id,"source_event_id":original.id,"intent":"explore","success":true,"message":"迟到的搜索结果"})
	assert(store.working_tasks[id].state=="cancelled","迟到结果不能复活被取消的任务")
	store.hear(id,{"id":"new_request","speaker":"player","text":"小花，去采果子。"})
	store.remember(id,"new_request",{"intent":"gather_food","private_interpretation":"采果子","public_reply":""})
	store.hear(id,{"id":"unrelated","speaker":"player","text":"月亮，休息好了吗？"})
	store.remember(id,"unrelated",{"intent":"none","private_interpretation":"与我无关","public_reply":"","conversation":{"participation":"listen"},"task_status":"none","task_handling":{"state":"none","reason":"旁听"}})
	assert(store.working_tasks[id].request.id=="new_request" and store.working_tasks[id].state=="action_submitted","普通旁听不能改变本人任务")
	store.working_tasks[id].state="paused_budget"
	store.hear(id,{"id":"stop_paused","speaker":"player","text":"月亮，告诉小花停止采果。"})
	store.remember(id,"stop_paused",{"intent":"rest","private_interpretation":"已经听见取消要求，停下","public_reply":"","conversation":{"participation":"interject"},"task_status":"cancelled","task_handling":{"state":"cancelled","reason":"停止本人旧任务"}})
	assert(store.working_tasks[id].state=="cancelled" and store.working_tasks[id].request.id=="new_request","停止动作及预算暂停不能让取消要求替换原任务身份")
	print("OVERHEARD_CANCELLATION_PASSED")
	quit()
