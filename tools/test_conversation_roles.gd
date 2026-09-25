extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
const Gateway=preload("res://scripts/voice/text_gateway_client.gd")
const Cloud=preload("res://scripts/voice/cloud_client.gd")
var failures: Array[String]=[]
var results: Array=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	var decision:={"private_interpretation":"旁听","public_reply":"","speech_style":"","intent":"none","routing_reason":"问别人","speech_act":"statement","addressed_person":"","recipient_id":"","capability_gap":null}
	check(not Cloud.validate_decision(JSON.stringify(decision),true,true).ok,"缺交谈判断必须拒绝")
	decision.conversation={"addressees":["person_003"],"participation":"listen","reason":"点名大山"}
	check(Cloud.validate_decision(JSON.stringify(decision),true,true).ok,"允许旁听")
	decision.public_reply="听见了"; decision.speech_style="平静"
	check(not Cloud.validate_decision(JSON.stringify(decision),true,true).ok,"旁听与台词冲突必须拒绝")
	if OS.get_cmdline_user_args().has("--cloud"):
		var gateway=Gateway.new(); root.add_child(gateway)
		var cases:=[
			{"name":"named","text":"大山，你能听见我的话吗？","focus":"person_003","target":"person_003"},
			{"name":"group","text":"大家都能听到我的声音吗？各自回答一下。","focus":"person_003","target":"all"},
			{"name":"facing","text":"你能听见我的话吗？","focus":"person_002","target":"person_002"},
			{"name":"name_over_gaze","text":"月亮，你能听见我的话吗？","focus":"person_003","target":"person_004"},
			{"name":"involved","text":"大山，小花说她一点也不饿，我们不用给她留食物。","focus":"person_003","target":"involved"}]
		for example in cases:
			if OS.get_cmdline_user_args().has("--conflict-only") and example.name!="name_over_gaze": continue
			var store=Store.new(); check(store.initialize().is_empty(),"初始化人物")
			# 夹具明确四人互相可见，提供与实景 visible_people 同类的公共身份，不泄露需求。
			for id in store.people:
				var nearby: Array=[]
				for other in store.people:
					if other!=id: nearby.append({"id":other,"name":store.people[other].name})
				store.people[id]["visible_people"]=nearby
			var pipeline=Pipeline.new(); pipeline.store=store; pipeline.gateway=gateway; root.add_child(pipeline)
			var audience:={}
			for id in store.people: audience[id]={"distance_m":2.0,"angle_degrees":5.0 if id==example.focus else 80.0}
			var event:={"id":"roles_"+example.name,"kind":"speech_intent","speaker":"player","text":example.text,"listeners":store.people.keys(),"spatial_segments":[{"text":example.text,"focus_hint":example.focus,"audience":audience}]}
			var reports: Array=[]
			pipeline.report_ready.connect(func(report): reports.append(report))
			pipeline.run(event,{})
			await pipeline.completed
			for report in reports:
				check(not report.has("error"),example.name+" "+report.person_id+" "+str(report.get("error","")))
				if report.has("error"): continue
				var d: Dictionary=report.decision
				if example.target=="all": check(d.conversation.participation=="reply" and "all" in d.conversation.addressees and not d.public_reply.is_empty(),"群体提问应被理解 "+report.person_id)
				elif example.target=="involved":
					if report.person_id=="person_002": check(d.conversation.participation=="interject" and not d.public_reply.is_empty(),"涉及自身饥饿时允许纠正")
				else:
					check(d.public_reply.is_empty() if report.person_id!=example.target else not d.public_reply.is_empty(),example.name+" 回应对象错误 "+report.person_id)
				print("ROLE_CASE ",example.name," ",report.person_name," ",JSON.stringify(d.conversation)," 台词=",d.public_reply)
				results.append({"case":example.name,"person":report.person_id,"decision":d})
			pipeline.queue_free()
		var file=FileAccess.open("res://services/text-gateway/runtime/conversation_roles_conflict.json" if OS.get_cmdline_user_args().has("--conflict-only") else "res://services/text-gateway/runtime/conversation_roles_final.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"failures":failures,"results":results},"\t"))
	print("CONVERSATION_ROLE_FAILURES ",failures.size()," ",failures)
	quit(0 if failures.is_empty() else 1)
