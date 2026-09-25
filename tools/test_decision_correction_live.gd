extends SceneTree
## 第一次空承诺为故障注入；修正由真实日常模型生成，不执行世界动作。
class Gateway extends "res://scripts/voice/text_gateway_client.gd":
	var injected:=false
	func exchange(request: Dictionary) -> Dictionary:
		if request.mode=="decision" and not injected:
			injected=true
			return {"ok":true,"model":"injected_empty_action","text":JSON.stringify({"intent":"none","private_interpretation":"木块还没搬完","public_reply":"我去拿木块。","speech_style":"平静","routing_reason":"继续","speech_act":"statement","addressed_person":"player","recipient_id":"","capability_gap":null,"task_status":"active","task_handling":{"state":"execute","reason":"继续搬木块"},"conversation":{"addressees":["person_003"],"participation":"reply","reason":"玩家请求"}})}
		return await super.exchange(request)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new()
	var gateway:=Gateway.new();root.add_child(gateway);root.add_child(pipeline)
	pipeline.gateway=gateway;pipeline.store=preload("res://scripts/voice/people_store.gd").new();assert(pipeline.store.initialize().is_empty())
	var reports: Array=[];pipeline.report_ready.connect(func(r):reports.append(r))
	pipeline.run({"id":"correction_live","speaker":"player","kind":"speech_intent","text":"把木块拿过来。如果没有这个能力，说明缺什么，不用假装动手。","listeners":["person_003"]},{})
	await pipeline.completed
	var result: Dictionary=reports[0]
	var passed: bool=reports.size()==1 and not result.has("error") and result.has("decision_correction") and result.calls[-1].stage=="decision_correction"
	var file:=FileAccess.open("res://services/luau-runtime/runtime/decision_correction_live.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("DECISION_CORRECTION_LIVE_PASSED" if passed else "DECISION_CORRECTION_LIVE_FAILED")
	quit(0 if passed else 1)
