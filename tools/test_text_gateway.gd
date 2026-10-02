extends SceneTree
const Store = preload("res://scripts/voice/people_store.gd")
const Pipeline = preload("res://scripts/voice/decision_pipeline.gd")


class FakeGateway extends Node:
	var prompts: Array = []
	var active := 0
	var peak := 0
	var invalid := false
	func exchange(payload: Dictionary) -> Dictionary:
		prompts.append(payload.prompt)
		active += 1
		peak = maxi(active,peak)
		await get_tree().process_frame
		active -= 1
		if invalid: return {"ok":true,"text":"无效结构"}
		return {"ok":true,"text":JSON.stringify({"intent":"none","capability_gap":null,"private_interpretation":"本人测试理解","speech_act":"statement","addressed_person":"","speech_style":"neutral","public_reply":"收到","routing_reason":"测试不触发本地升级","task_status":"none","task_handling":{"state":"none","scope":"independent","reason":"确认收到"},"conversation":{"participation":"reply","addressees":[],"reason":"测试交谈"}})}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var store := Store.new()
	assert(store.initialize("res://data/people.json","user://gateway_test_%d.json"%Time.get_ticks_usec(),true).is_empty())
	store.hear("person_001",{"id":"private_a","speaker":"body","kind":"body_state","text":"PRIVATE_A_574"})
	store.hear("person_002",{"id":"private_b","speaker":"body","kind":"body_state","text":"PRIVATE_B_936"})
	var client := FakeGateway.new()
	root.add_child(client)
	var pipeline := Pipeline.new()
	pipeline.store = store
	pipeline.gateway = client
	root.add_child(pipeline)
	var reports: Array = []
	pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	pipeline.run({"id":"text-contract","kind":"speech_intent","text":"石头去拿食物","listeners":["person_001","person_002"]},{"text_gateway":true})
	await pipeline.completed
	assert(client.prompts.size()==2 and client.peak==2,"独立人物决策应并行且不在本地升级")
	assert(client.prompts[0].contains("PRIVATE_A_574") and not client.prompts[0].contains("PRIVATE_B_936"),"第一人的隐私隔离")
	assert(client.prompts[1].contains("PRIVATE_B_936") and not client.prompts[1].contains("PRIVATE_A_574"),"第二人的隐私隔离")
	assert(store.people.person_003.heard_events.is_empty(),"范围外人物不能知道事件")
	assert(reports.size()==2 and reports[0].executed==false)
	store.mark_reply("person_001","text-contract","已向玩家播放完成；未投递给其他成员")
	client.invalid = true
	pipeline.run({"id":"invalid","listeners":["person_001"]},{"text_gateway":true})
	await pipeline.completed
	assert(reports[2].has("error") and store.people.person_001.reflections.size()==1,"无效输出不能记为计划")
	var wire_lines: Array=Array(client.prompts[2].split("\n")).filter(func(line):return line.begins_with('{"self":'))
	assert(wire_lines.size()==1)
	var request_data: Dictionary = JSON.parse_string(wire_lines[0])
	assert(request_data.current_event.id=="invalid","新事件不能被旧问题覆盖")
	assert(not request_data.current_event.has("listeners"),"当前事件也必须隔离听众名单")
	assert(JSON.stringify(request_data.self.working_context).contains("已向玩家播放完成"),"模型必须知道上一句已向玩家说完")
	var cloud = load("res://scripts/voice/cloud_client.gd")
	var valid := {"intent":"none","capability_gap":null,"private_interpretation":"饿","speech_act":"statement","addressed_person":"","speech_style":"neutral","public_reply":"","routing_reason":"简单"}
	assert(cloud.validate_decision(JSON.stringify(valid)).ok,"允许沉默与空计划")
	var legacy: Dictionary=valid.duplicate(true)
	legacy.erase("speech_act")
	assert(not cloud.validate_decision(JSON.stringify(legacy),true).ok,"生产链路禁止漏交流字段后静默降级")
	var bad := valid.duplicate(true)
	bad.intent="move_any_bone"
	assert(not cloud.validate_decision(JSON.stringify(bad)).ok,"拒绝未开放的控制权限")
	bad = valid.duplicate(true)
	bad.erase("speech_style")
	assert(not cloud.validate_decision(JSON.stringify(bad)).ok,"缺失公开语气不能静默补默认值")
	bad = valid.duplicate(true)
	bad.speech_style = "private_anger"
	assert(cloud.validate_decision(JSON.stringify(bad)).ok,"自由语气描述仍被保留")
	bad = valid.duplicate(true)
	bad["world_state"] = {"food":99}
	assert(not cloud.validate_decision(JSON.stringify(bad)).ok,"拒绝额外世界状态字段")
	bad = valid.duplicate(true)
	bad.public_reply = "字".repeat(1001)
	assert(not cloud.validate_decision(JSON.stringify(bad)).ok,"拒绝超过声音端上限的台词")
	bad = valid.duplicate(true)
	bad.intended_actions = [""]
	assert(not cloud.validate_decision(JSON.stringify(bad)).ok,"拒绝已删除的文字计划字段")
	print("TEXT_GATEWAY_CONTRACT_PASSED: isolated_context, two_parallel_decisions, no_local_escalation, invalid_decision")
	quit()
