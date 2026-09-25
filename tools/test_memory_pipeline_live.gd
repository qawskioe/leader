extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var direct: bool=OS.get_cmdline_user_args().has("--direct")
	var store=preload("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	store.hear("person_003",{"id":"earlier","speaker":"player","text":"你记住：那块带白线的石头，我把它放在洞口左边的大树下了。"})
	store.memory.advance(store.memory.policy.day_seconds+1) # 日终整理后，旧经历进入长期检索。
	var gateway=preload("res://scripts/voice/text_gateway_client.gd").new();root.add_child(gateway)
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new();pipeline.store=store;pipeline.gateway=gateway;root.add_child(pipeline)
	var reports: Array=[];pipeline.report_ready.connect(func(r): reports.append(r))
	pipeline.run({"id":"now","speaker":"player","kind":"speech_intent","text":"大山，你叫什么名字？" if direct else "大山，我刚才告诉你，带白线的石头放哪了？","listeners":["person_003"]},{})
	await pipeline.completed
	var ok: bool=reports.size()==1 and not reports[0].has("error")
	if ok: ok=(reports[0].calls.size()==1 and reports[0].get("memory_reads",[]).is_empty()) if direct else not reports[0].get("memory_reads",[]).is_empty()
	if ok:
		var answer: String=reports[0].decision.public_reply
		ok=answer.contains("大山") if direct else (answer.contains("洞口") and answer.contains("左") and answer.contains("树"))
	var file:=FileAccess.open("res://services/luau-runtime/runtime/memory_direct_result.json" if direct else "res://services/luau-runtime/runtime/memory_live_result.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"  "));file.close()
	print("MEMORY_LIVE_PASSED" if ok else "MEMORY_LIVE_FAILED", " direct=",direct," reads=",reports[0].get("memory_reads",[]) if reports.size()==1 else [])
	quit(0 if ok else 1)
