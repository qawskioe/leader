extends SceneTree
const Cloud=preload("res://scripts/voice/cloud_client.gd")
class Gateway extends Node:
	var replies: Array=[]
	var prompts: Array=[]
	var modes: Array=[]
	var published: Array=[]
	func exchange(request: Dictionary) -> Dictionary:
		assert(published.is_empty(),"校验通过前不能发出可播放或可执行的报告")
		prompts.append(request.prompt);modes.append(request.mode)
		assert(not replies.is_empty(),"不能无限重试")
		await get_tree().process_frame
		return {"ok":true,"text":JSON.stringify(replies.pop_front()),"model":"fixture","elapsed_ms":1}
func _initialize() -> void: run.call_deferred()
func base(state: String) -> Dictionary:
	return {"intent":"none","private_interpretation":"木块尚未搬完","public_reply":"","speech_style":"","routing_reason":"处理当前任务","speech_act":"statement","addressed_person":"","recipient_id":"","capability_gap":null,"task_status":"active","task_handling":{"state":state,"reason":"等待同伴确认位置"},"conversation":{"addressees":["person_003"],"participation":"reply","reason":"原任务仍在进行"}}
func run() -> void:
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new()
	var gateway:=Gateway.new();root.add_child(gateway);root.add_child(pipeline)
	pipeline.gateway=gateway;pipeline.store=preload("res://scripts/voice/people_store.gd").new();assert(pipeline.store.initialize().is_empty())
	pipeline.store.people.person_003.available_skills=[{"ref":"take_object@fixture","parameters":{"object":"物品ID"},"revision_supported":true}]
	pipeline.report_ready.connect(func(r):gateway.published.append(r))
	var invalid:=base("execute");invalid.public_reply="我去拿木块。";invalid.speech_style="平静"
	var wait:=base("wait")
	var execute:=base("execute");execute.skill_call={"ref":"skill_1","arguments":{"object":"wood_block"}}
	var revision:=base("execute");revision.revision_request={"ref":"skill_1","feedback":"伸手时慢一些"}
	var blocked:=base("blocked");blocked.task_handling.reason="当前没有返回最后所见位置并重新观察的技能"
	for decision in [wait,execute,blocked]: assert(Cloud.validate_task_handling(Cloud.validate_decision(JSON.stringify(decision),true,true).decision).ok)
	var ask:=base("ask");ask.public_reply="小花，你知道木块在哪里吗？";ask.speech_style="平静";ask.speech_act="request";ask.addressed_person="person_002"
	assert(Cloud.validate_task_handling(Cloud.validate_decision(JSON.stringify(ask),true,true).decision).ok)
	assert(not Cloud.validate_task_handling(Cloud.validate_decision(JSON.stringify(invalid),true,true).decision).ok)
	for scenario in ["fixed","wait","execute","revision","exhausted"]:
		gateway.published.clear();gateway.prompts.clear();gateway.modes.clear()
		match scenario:
			"fixed": gateway.replies=[invalid,blocked]
			"wait": gateway.replies=[wait]
			"execute": gateway.replies=[execute]
			"revision": gateway.replies=[revision]
			"exhausted": gateway.replies=[invalid,invalid]
		pipeline.run({"id":scenario,"speaker":"player","kind":"speech_intent","text":"把两件东西搬到干地，石块已经放好了，继续木块。","listeners":["person_003"]},{})
		await pipeline.completed
		assert(gateway.published.size()==1)
		var report: Dictionary=gateway.published[0]
		if scenario in ["fixed","exhausted"]:
			assert(gateway.modes==["decision","decision"])
			assert(gateway.prompts[1].begins_with(gateway.prompts[0]),"修正须保留完整原情景")
			assert(report.calls[1].stage=="decision_correction")
		else: assert(gateway.modes==["decision"])
		if scenario=="exhausted":
			assert(report.has("error") and report.correction_exhausted and not report.has("decision"))
		else:
			assert(not report.has("error"))
			if scenario=="fixed": assert(report.decision.task_handling.state=="blocked" and report.decision.public_reply.is_empty())
			if scenario=="execute":
				assert(report.decision.skill_call.ref=="take_object@fixture","执行和存档必须还原完整版本，不能传短编号")
				assert(report.skill_handle_map.skill_1=="take_object@fixture")
			if scenario=="revision":assert(report.decision.revision_request.ref=="take_object@fixture")
	var catalog_context:={"available_skills":[],"survival_observation":{"action_catalog":{"none":"不行动","give_food":"递给实际接收者"}}}
	var wrong:=base("execute");wrong.skill_call={"ref":"give_food","arguments":{"recipient_id":"player"}}
	assert(pipeline._check_final(JSON.stringify(wrong),catalog_context).error.contains("属于旧行为"))
	wrong.skill_call=null;wrong.intent="give_food";wrong.recipient_id="player"
	assert(pipeline._check_final(JSON.stringify(wrong),catalog_context).ok)
	# 口头承诺不等于物理递物；反馈必须明确事件事实，避免原样重试。
	var verbal:=base("none");verbal.task_status="none";verbal.offer_response="accept"
	pipeline._event={"kind":"speech_intent"}
	var mismatch: Dictionary=pipeline._check_final(JSON.stringify(verbal),catalog_context)
	assert(not mismatch.ok and mismatch.error.contains("kind=speech_intent") and mismatch.error.contains("删除该字段"))
	verbal.erase("offer_response")
	assert(pipeline._check_final(JSON.stringify(verbal),catalog_context).ok)
	pipeline._event={"kind":"item_offer"}
	assert(not pipeline._check_final(JSON.stringify(verbal),catalog_context).ok)
	verbal.offer_response="accept";verbal.task_handling.state="wait";verbal.task_status="active"
	assert("不需要玩家再次确认" in Cloud.validate_task_handling(verbal).error)
	verbal.offer_response="accept";verbal.task_handling.state="execute";verbal.task_status="active"
	assert(pipeline._check_final(JSON.stringify(verbal),catalog_context).ok)
	pipeline._event={"kind":"speech_intent"}
	var spoken:=base("none");spoken.task_status="none";spoken.public_reply="找到basket/1了。";spoken.speech_style="平静"
	catalog_context.survival_observation["known_objects"]={"basket/1":{}}
	assert(pipeline._check_final(JSON.stringify(spoken),catalog_context).error.contains("内部物品标识"))
	spoken.public_reply="找到篮子了，就在前方偏右。"
	assert(pipeline._check_final(JSON.stringify(spoken),catalog_context).ok)
	var bad_target:=ask.duplicate(true);bad_target.addressed_person="person/person_002"
	var target_error: Dictionary=pipeline._check_final(JSON.stringify(bad_target),catalog_context)
	assert(not target_error.ok and target_error.error.contains("应填人物ID person_002"))
	bad_target.addressed_person="person_002"
	assert(pipeline._check_final(JSON.stringify(bad_target),catalog_context).ok,"正确人物ID仍可发起实际询问")
	bad_target.addressed_person="person_999"
	assert(not pipeline._check_final(JSON.stringify(bad_target),catalog_context).ok,"不存在的人物不能播放后无声丢失请求")
	print("DECISION_CORRECTION_PASSED one_retry_original_context_no_unvalidated_publication_wait_action_blocked")
	quit()
