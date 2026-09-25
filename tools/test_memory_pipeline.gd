extends SceneTree
class FakeGateway extends Node:
	var prompts: Array=[]
	var modes: Array=[]
	var replies: Array=[]
	func exchange(payload: Dictionary) -> Dictionary:
		prompts.append(payload.prompt);modes.append(payload.mode)
		await get_tree().process_frame
		return {"ok":true,"text":JSON.stringify(replies.pop_front()),"model":"fixture","elapsed_ms":1,"usage":{}}
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var store=preload("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	store.hear("person_003",{"id":"past","speaker":"player","text":"独特记忆：木块先前放在松树边。"})
	store.remember("person_002","secret",{"private_interpretation":"他人的独特私密想法","public_reply":""})
	store.memory.advance(store.memory.policy.day_seconds+1) # 日终整理后，旧经历进入长期检索。
	var gateway:=FakeGateway.new();root.add_child(gateway)
	gateway.replies=[{"recall":{"kind":"heard","keywords":["木块"],"limit":3}},{"task_handling":{"state":"none","reason":"回答历史位置问题"},"private_interpretation":"我回忆起之前听到的位置","public_reply":"之前说是在松树边。","speech_style":"平静","intent":"none","routing_reason":"依据本人回忆回答","speech_act":"reply","addressed_person":"player","recipient_id":"","capability_gap":null,"conversation":{"addressees":["person_003"],"participation":"reply","reason":"玩家问我"}}]
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new();pipeline.store=store;pipeline.gateway=gateway;root.add_child(pipeline)
	var reports: Array=[];pipeline.report_ready.connect(func(r): reports.append(r))
	pipeline.run({"id":"now","speaker":"player","kind":"speech_intent","text":"大山，之前那个东西放在哪里？","listeners":["person_003"]},{})
	await pipeline.completed
	assert(gateway.prompts.size()==2)
	assert(not gateway.prompts[0].contains("独特记忆") and not gateway.prompts[0].contains("他人的独特私密想法"),"默认输入不注入历史或他人隐私")
	assert(gateway.prompts[1].contains("独特记忆") and not gateway.prompts[1].contains("他人的独特私密想法"))
	assert(reports.size()==1 and not reports[0].has("error") and reports[0].memory_reads.size()==1)
	assert(reports[0].calls[0].stage=="decision" and reports[0].calls[1].stage=="decision")
	assert(gateway.modes==["decision","decision"])
	# 另一次请求仍能按需检索；只有最终决策能产生行为。
	var final_decision: Dictionary=reports[0].decision.duplicate(true)
	gateway.prompts.clear();gateway.modes.clear();reports.clear()
	gateway.replies=[{"recall":{"kind":"heard","keywords":["木块"],"limit":3}},final_decision]
	pipeline.run({"id":"recover","speaker":"player","kind":"speech_intent","text":"大山，之前木块放哪里？","listeners":["person_003"]},{})
	await pipeline.completed
	assert(gateway.modes==["decision","decision"])
	assert(reports.size()==1 and not reports[0].has("error") and reports[0].memory_reads.size()==1)
	assert(gateway.prompts[1].contains("独特记忆") and not gateway.prompts[1].contains("他人的独特私密想法"))
	# 已有信息足够时只调用一次，不再支付一次ready预检。
	gateway.modes.clear();reports.clear();gateway.replies=[final_decision]
	pipeline.run({"id":"direct","speaker":"player","kind":"speech_intent","text":"大山，知道了。","listeners":["person_003"]},{})
	await pipeline.completed
	assert(reports.size()==1 and not reports[0].has("error"))
	assert(gateway.modes==["decision"] and reports[0].calls.size()==1)
	# 连续检索也必须有界，防止模型无限往返。
	gateway.modes.clear();reports.clear()
	var recall:={"recall":{"kind":"heard","keywords":["木块"],"limit":3}}
	gateway.replies=[recall,recall,recall]
	pipeline.run({"id":"bounded","speaker":"player","kind":"speech_intent","text":"继续找旧记忆","listeners":["person_003"]},{})
	await pipeline.completed
	assert(gateway.modes.size()==3 and reports[0].has("error") and not reports[0].has("decision"))
	print("MEMORY_PIPELINE_PASSED model_initiated_recall_no_default_history_no_other_private_data")
	quit()
