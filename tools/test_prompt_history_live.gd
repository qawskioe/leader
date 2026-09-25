extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var store=preload("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var id:="person_003"
	store.hear(id,{"id":"instruction","speaker":"player","text":"把木块和石块都放到洞口左边的大树下。"})
	var text:="你的饥饿或口渴达到需要处理的程度。按本人需求数值决定优先吃饭还是喝水，结合已知物资、工作和附近成员，可以行动、求助或等待；没有玩家给你下命令。"
	# 超过列式发送阈值，验证真实模型仍能读出最初原话；不依赖回忆接口。
	for n in 130:
		store.hear(id,{"id":"body_"+str(n),"kind":"need_changed","speaker":"body","text":text,"trigger":{"hunger":60+n*0.1,"thirst":30}})
	var gateway=preload("res://scripts/voice/text_gateway_client.gd").new();root.add_child(gateway)
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new();pipeline.store=store;pipeline.gateway=gateway;root.add_child(pipeline)
	var reports: Array=[];pipeline.report_ready.connect(func(r):reports.append(r))
	pipeline.run({"id":"question","speaker":"player","kind":"speech_intent","text":"大山，先不用动手。我刚才让你把哪两样东西放在哪里？","listeners":[id]}, {})
	await pipeline.completed
	var ok: bool=reports.size()==1 and not reports[0].has("error")
	if ok:
		var answer: String=reports[0].decision.public_reply
		ok=answer.contains("木块") and answer.contains("石块") and answer.contains("左") and answer.contains("树") and reports[0].calls.size()==1 and reports[0].get("memory_reads",[]).is_empty()
	var file:=FileAccess.open("res://services/luau-runtime/runtime/prompt_history_live.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(reports));file.close()
	print("PROMPT_HISTORY_LIVE_PASSED" if ok else "PROMPT_HISTORY_LIVE_FAILED")
	quit(0 if ok else 1)
