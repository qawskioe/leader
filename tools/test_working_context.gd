extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(10).timeout.connect(func():push_error("working context timeout");quit(1))
	var store=preload("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://working_context_%d.json"%Time.get_ticks_usec(),true).is_empty())
	var id:="person_003"
	store.hear(id,{"id":"first","speaker":"player","text":"你背后有什么？"})
	store.remember(id,{"event_id":"first"}.event_id,{"private_interpretation":"不应公开的主观猜测","public_reply":"洞壁和黑暗。"})
	var context: Dictionary=store.context_for(id).working_context
	assert(context.recent_turns[0].own_reply.status=="已生成，尚未播放")
	store.mark_reply(id,"first","已播放完成；附近成员听闻另行记录")
	store.hear(id,{"id":"second","speaker":"player","text":"你刚才不是说知道吗？"})
	context=store.context_for(id).working_context
	assert(context.recent_turns[0].own_reply.text=="洞壁和黑暗。" and context.recent_turns[0].own_reply.status.begins_with("已播放"))
	assert(context.recent_turns[0].own_understanding=="不应公开的主观猜测","自己的当时理解属于短期记忆，与公开台词分开")
	assert(store.context_for("person_002").working_context.recent_turns.is_empty())
	store.hear(id,{"id":"command","speaker":"player","text":"把石块放到水池外面","source_position":[1,2,3]})
	store.remember(id,"command",{"private_interpretation":"先拿起","public_reply":"","skill_call":{"ref":"take","arguments":{"object":"stone_tool"}},"task_status":"active","task_handling":{"state":"execute","scope":"current_request","reason":"测试任务归属"}})
	store.record_execution({"person_id":id,"source_event_id":"command","success":false,"world_position":{"x":100,"y":0,"z":200},"runtime":{"returned":{"code":"no_support","message":"只针对这个点","scope":"selected_point_only"}},"message":"放置失败"})
	store.hear(id,{"id":"correction","speaker":"player","text":"直接放就行了"})
	context=store.context_for(id).working_context
	assert(context.task.request.text=="把石块放到水池外面")
	assert(context.task.last_result.feedback.scope=="selected_point_only")
	assert(not JSON.stringify(context).contains("world_position") and not JSON.stringify(context).contains("source_position"))
	store.hear(id,{"id":"both","speaker":"player","text":"把石块和木块都放到池塘外"})
	store.hear(id,{"id":"start","speaker":"player","text":"没错，开始动手"})
	store.remember(id,"start",{"private_interpretation":"先搬石块","public_reply":"","skill_call":{"ref":"take","arguments":{"object":"stone_tool"}},"task_status":"active","task_handling":{"state":"execute","scope":"current_request","reason":"测试任务归属"}})
	var bound: Dictionary=store.working_tasks[id].request.duplicate(true)
	for n in 10: store.hear(id,{"id":"noise_"+str(n),"speaker":"world","text":"动作反馈"})
	store.hear(id,{"id":"continuation","kind":"skill_progress","speaker":"world","original_event":bound,"text":"拿取成功"})
	store.remember(id,"continuation",{"private_interpretation":"继续放石块，之后搬木块","public_reply":"","skill_call":{"ref":"place","arguments":{"object":"stone_tool"}},"task_status":"active","task_handling":{"state":"execute","scope":"current_request","reason":"测试任务归属"}})
	assert(JSON.stringify(store.working_tasks[id].request.request_context).contains("把石块和木块都放到池塘外"),"续办绑定原始完整要求，不能仅保留开始动手或被短期窗口挤掉")
	assert(store.working_tasks[id].action_event_id=="continuation")
	var received:={"id":"received_bag","kind":"received_item","speaker":"world","text":"同伴把空袋实际交给你"}
	store.hear(id,received)
	store.remember(id,received.id,{"private_interpretation":"收到后还需走近玩家并交付","public_reply":"","skill_call":{"ref":"walk","arguments":{"target":"player"}},"task_status":"active","task_handling":{"state":"execute","scope":"existing_request","reason":"测试任务归属"}})
	assert(store.working_tasks[id].request.id==bound.id,"物品接收是任务进展，不能替换原请求")
	var npc_request:={"id":"npc_request","kind":"social_request","speaker":"person_002","text":"把空水袋交给我"}
	store.hear(id,npc_request)
	store.remember(id,npc_request.id,{"private_interpretation":"接受同伴的请求","public_reply":"","skill_call":{"ref":"take","arguments":{"object":"bag"}},"task_status":"active","task_handling":{"state":"execute","scope":"current_request","reason":"测试任务归属"}})
	store.hear(id,{"id":"npc_received","kind":"received_water","speaker":"person_004","text":"收到水袋"})
	store.remember(id,"npc_received",{"private_interpretation":"继续同伴的请求","public_reply":"","skill_call":{"ref":"give","arguments":{"object":"bag"}},"task_status":"active","task_handling":{"state":"execute","scope":"existing_request","reason":"测试任务归属"}})
	assert(store.working_tasks[id].request.id==npc_request.id,"同伴的明确请求也必须跨接收事件保留")
	assert(not store.is_person_request({"speaker":"person_002","kind":"received_water"}),"普通收到物品不能伪装新的明确请求")
	var helper:="person_004"
	var ask_first:={"id":"ask_before_acting","speaker":"player","kind":"speech_intent","text":"向大山要空袋，再交给我"}
	store.hear(helper,ask_first)
	store.remember(helper,ask_first.id,{"intent":"none","private_interpretation":"先询问大山","public_reply":"大山，请给我空袋。","task_status":"active","task_handling":{"state":"ask","scope":"current_request","reason":"先请求对方递交"},"conversation":{"participation":"reply"}})
	assert(store.working_tasks[helper].request.id==ask_first.id and store.working_tasks[helper].state=="ask","只先开口请求时也必须保存新任务，而非沿用更早的工作")
	store.hear(helper,{"id":"ask_received","kind":"received_item","speaker":"world","text":"空袋实际收到"})
	store.remember(helper,"ask_received",{"private_interpretation":"现在走近玩家","public_reply":"","skill_call":{"ref":"walk","arguments":{"target":"player"}},"task_status":"active","task_handling":{"state":"execute","scope":"existing_request","reason":"测试任务归属"}})
	assert(store.working_tasks[helper].request.id==ask_first.id)
	# 后续旧夹具仍验证原两件物品任务的发送去重。
	store.working_tasks[id].request=bound
	# 只在发送时去重：当前事件/原任务仍各有完整来源，完整存档不修改。
	var wire_context: Dictionary=store.context_for(id)
	var wire_event:={"id":"wire","speaker":"world","kind":"skill_progress","original_event":wire_context.working_context.task.request.duplicate(true),"text":"继续"}
	wire_context.working_context.recent_turns.append({"event":wire_event.duplicate(true)})
	var before:=JSON.stringify(wire_context)
	var prompt: String=preload("res://scripts/voice/decision_pipeline.gd").prompt_for(wire_context,wire_event)
	assert(prompt.contains('"context_ref":"current_event"') and prompt.contains('"context_ref":"self.working_context.task.request"'))
	assert(prompt.contains("把石块和木块都放到池塘外"))
	assert(JSON.stringify(wire_context)==before and wire_event.original_event.has("request_context"),"发送去重不得改写记忆")
	store.memory.advance(301)
	context=store.context_for(id).working_context
	assert(not context.recent_turns.is_empty() and not context.task.is_empty(),"当天短期经历不按300秒或8条清除")
	store.memory.advance(store.memory.policy.day_seconds)
	assert(not store.memory.recall(id,{"kind":"heard","keywords":["背后"],"limit":1}).records.is_empty())
	print("WORKING_CONTEXT_PASSED spoken_status_owner_scope_task_failure_long_term_recall")
	quit()
