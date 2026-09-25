extends SceneTree
## 格式拒绝必须留下原文，并且不能进入人物记忆或执行入口。
class Gateway extends Node:
	var output := "{\"current_event\":{}}"
	func exchange(_request: Dictionary) -> Dictionary:
		return {"ok":true,"text":output,"model":"fixture"}
var reports: Array=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var pipeline=load("res://scripts/voice/decision_pipeline.gd").new()
	var gateway=Gateway.new()
	root.add_child(gateway)
	root.add_child(pipeline)
	pipeline.gateway=gateway
	pipeline.store=load("res://scripts/voice/people_store.gd").new()
	assert(pipeline.store.initialize().is_empty())
	pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	pipeline.run({"id":"rejected","kind":"speech_intent","speaker":"player","listeners":["person_003"],"text":"喝水"},{})
	while pipeline.busy: await process_frame
	assert(reports.size()==1)
	assert(reports[0].error.ends_with("决策包含未知字段：current_event") and reports[0].correction_exhausted)
	assert(reports[0].rejected_output==gateway.output)
	assert(not reports[0].has("decision"))
	var cloud=load("res://scripts/voice/cloud_client.gd")
	var decision={"intent":"none","private_interpretation":"听见了","public_reply":"好","speech_style":"平静","routing_reason":"回答","speech_act":"reply","addressed_person":"player","request_kind":null}
	assert(cloud.validate_decision(JSON.stringify(decision)).ok)
	decision.request_kind=""
	assert(cloud.validate_decision(JSON.stringify(decision)).ok)
	decision.speech_act="request"
	assert(not cloud.validate_decision(JSON.stringify(decision)).ok)
	print("DECISION_REJECTION_PASSED raw_output_preserved, no_decision_emitted")
	pipeline.queue_free()
	gateway.queue_free()
	await process_frame
	quit()
