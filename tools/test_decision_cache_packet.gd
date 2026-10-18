extends SceneTree
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
func _initialize() -> void:
	create_timer(10).timeout.connect(func():push_error("cache packet test timeout");quit(1))
	var context:={"id":"person_001","name":"石头","needs":{"hunger":12},"available_skills":[{"ref":"skill_1","name":"递交物品","description":"交给实际接收者，保留拒绝结果","parameters":{"object":"实际物品","recipient":"已知人物"},"parameter_kinds":{"object":"reference","recipient":"reference"},"callable":true}],"working_context":{"task":{"request":{"id":"order","text":"拿空水袋装两份水，不喝，再交给我"},"progress":[{"facts":[{"kind":"stored","material":"water","quantity":1,"target":"water_bag/1"}]}]},"recent_turns":[]}}
	var event:={"id":"event_1","kind":"speech_intent","speaker":"player","text":"继续刚才的事情","original_event":{"id":"order","text":"拿空水袋装两份水，不喝，再交给我"}}
	var original:=context.duplicate(true)
	var first:=Pipeline.request_for(context,event)
	context.needs.hunger=27;context.available_skills[0].callable=false;context.available_skills[0]["unavailable_reason"]="依赖不可用"
	event.id="event_2";event.text="先等一下"
	var second:=Pipeline.request_for(context,event)
	assert(first.prefix==second.prefix and first.reference==second.reference,"当前状态和可用性不能改变稳定目录")
	assert(first.prompt!=second.prompt)
	var catalog: Dictionary=JSON.parse_string(first.reference)
	assert(catalog.skill_catalog[0].parameters==original.available_skills[0].parameters)
	assert(not catalog.skill_catalog[0].has("callable"))
	var wire: Dictionary=JSON.parse_string(second.prompt)
	assert(wire.self.available_skills==[{"ref":"skill_1","callable":false,"unavailable_reason":"依赖不可用"}])
	assert(wire.self.needs.hunger==27 and wire.current_event.text=="先等一下")
	assert(wire.current_event.original_event.context_ref=="self.working_context.task.request" and second.prompt.contains("两份水"),"相同原话的去重引用必须仍指向完整请求")
	assert(second.prompt.contains("stored") and second.prompt.contains("water_bag/1"),"原任务与进展不能因缓存拆分而丢失")
	assert(context.available_skills[0].has("parameters"),"整理输入不能改变宿主目录")
	assert(first.prefix.count("资料接口")==1)
	assert(first.reference.count("递交物品")==1 and not first.prompt.contains("交给实际接收者"),"目录仅发送一次")
	print("DECISION_CACHE_PACKET_PASSED stable_boundaries_current_availability_original_task_progress_parameters_no_mutation")
	quit()
