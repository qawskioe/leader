extends SceneTree
const Log=preload("res://scripts/voice/conversation_log.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var log:=Log.new()
	log.people={"person_001":{"name":"石头"},"person_002":{"name":"小花"}}
	root.add_child(log)
	log.append_record({"type":"transcript","event":{"id":"one","text":"你们怎么想？"}})
	var decision:={"private_interpretation":"测试理解","public_reply":"好","intent":"none"}
	for id in log.people:
		log.append_record({"type":"role_result","report":{"event_id":"one","person_id":id,"person_name":log.people[id].name,"decision":decision,"calls":[]}})
	log.append_record({"type":"tts_generated","event_id":"one","person_id":"person_001","audio_seconds":5.6,"elapsed_ms":2628})
	log.append_record({"type":"public_heard","event_id":"one","speaker":"person_001","listeners":["person_002"]})
	log.append_record({"type":"spoken","event_id":"one","person_id":"person_001"})
	assert(log.turns.size()==1 and log.cards.size()==2)
	var stone:=log._card(log.turns.one,"person_001")
	var flower:=log._card(log.turns.one,"person_002")
	var detail: TreeItem
	for child in stone.get_children():
		if child.get_text(0)=="播放状态": assert(child.get_text(1)=="已说完")
		if child.get_text(0)=="技术详情与原始记录": detail=child
	for child in flower.get_children():
		if child.get_text(0)=="播放状态": assert(child.get_text(1)=="已生成，尚未播放")
	assert(detail.collapsed)
	detail.collapsed=false
	var raw:={"type":"custom","event_id":"one","person_id":"person_001","usage":{"attribution":{"items":{"msg_test":{"input_tokens":1844}}},"output_tokens":131}}
	log.append_record(raw)
	assert(not detail.collapsed)
	assert(detail.get_children().back().get_metadata(1)==raw,"完整原始数据可展开和复制")
	log.append_record({"type":"transcript","event":{"id":"two","text":"第二轮"}})
	assert(log.turns.one!=log.turns.two)
	assert(Log.EXPLANATIONS.has("public_heard") and Log.EXPLANATIONS.has("attribution"))
	print("CONVERSATION_LOG_PASSED: interleaving, independent_status, retained_raw, fold_state, round_boundary, explanations")
	quit()
