extends SceneTree
## 真实 Luna 对照：恢复首轮已播放答复，再分别输入含糊转写与明确追问。
const Store = preload("res://scripts/voice/people_store.gd")
const Pipeline = preload("res://scripts/voice/decision_pipeline.gd")
const Gateway = preload("res://scripts/voice/text_gateway_client.gd")
var failed := false

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var store := Store.new()
	assert(store.initialize().is_empty())
	var gateway := Gateway.new()
	root.add_child(gateway)
	var pipeline := Pipeline.new()
	pipeline.store = store
	pipeline.gateway = gateway
	root.add_child(pipeline)
	var reports: Array = []
	pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	var prior := {"private_interpretation":"我已吃饱，石头辛苦，应当分给他。","public_reply":"我已经吃过了，现在不饿。石头今天搬了很多柴，应该把食物分给他。"}
	for text in ["那你听好心的意思喽。","我是在夸你愿意替别人着想，你怎么想？"]:
		assert(store.initialize().is_empty())
		store.hear("person_003",{"id":"prior","kind":"speech_intent","speaker":"player","text":"你觉得自己应该获得食物吗？"})
		store.remember("person_003","prior",prior)
		store.mark_reply("person_003","prior","已向玩家播放完成；未投递给其他成员")
		pipeline.run({"id":"followup_"+str(reports.size()),"kind":"speech_intent","speaker":"player","text":text,"listeners":["person_003"]},{"text_gateway":true})
		await pipeline.completed
		var report: Dictionary = reports.back()
		if report.has("error") or report.calls[0].model != "gpt-5.6-luna": failed = true
		if report.has("decision") and report.decision.public_reply==prior.public_reply: failed = true
		print("FOLLOWUP_RESULT ",JSON.stringify({"input":text,"report":report}))
	var file := FileAccess.open("res://services/text-gateway/runtime/followup_verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"transport_and_schema_passed":not failed,"semantic_review_required":true,"reports":reports},"\t"))
	print("FOLLOWUP_CONTRACT ","failed" if failed else "passed; semantic output requires review")
	quit(1 if failed else 0)
