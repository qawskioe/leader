extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
const Gateway=preload("res://scripts/voice/text_gateway_client.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var base:="user://voice_tests/1789519693_3558"
	var snapshot: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+"_people.json"))
	var event: Dictionary={}
	for line in FileAccess.get_file_as_string(base+".jsonl").split("\n",false):
		var record: Dictionary=JSON.parse_string(line)
		if record.get("type")=="transcript" and record.event.id=="event_1789519769_79855918": event=record.event
	assert(not event.is_empty())
	var results: Array=[]
	var failures: Array=[]
	var gateway=Gateway.new();root.add_child(gateway)
	for attempt in 2:
		var store=Store.new();store.people=snapshot.people.duplicate(true)
		# 快照采于该轮之后；移除本轮及之后的听闻/反思，避免“已听见石头答复”污染重放。
		for person in store.people.values():
			for field in ["heard_events","reflections"]:
				var records: Array=person.get(field,[])
				for i in records.size():
					if records[i].get("id",records[i].get("event_id",""))==event.id:
						person[field]=records.slice(0,i)
						break
		var pipeline=Pipeline.new();pipeline.store=store;pipeline.gateway=gateway;root.add_child(pipeline)
		var reports: Array=[]
		pipeline.report_ready.connect(func(report):reports.append(report))
		pipeline.run(event,{})
		await pipeline.completed
		for report in reports:
			var row:={"attempt":attempt,"person":report.person_id,"decision":report.get("decision"),"error":report.get("error")}
			results.append(row);print("REPLAY ",JSON.stringify(row))
			if report.has("error"): failures.append(row);continue
			var d: Dictionary=report.decision
			var expected: bool=report.person_id=="person_001"
			if (not d.public_reply.is_empty())!=expected or "石头哥" in d.public_reply: failures.append(row)
		pipeline.queue_free()
	var output=FileAccess.open("res://services/text-gateway/runtime/conversation_replay.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"failures":failures.size(),"results":results},"\t"))
	print("REPLAY_FAILURES ",failures.size())
	quit(0 if failures.is_empty() else 1)

