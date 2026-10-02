extends SceneTree
class Gateway extends Node:
	var calls:=0
	var snapshots: Array=[]
	func exchange(request: Dictionary) -> Dictionary:
		calls+=1;snapshots.append(request.prompt)
		await get_tree().process_frame
		if calls==1:
			for line in request.prompt.split("\n"):
				if not line.begins_with('{"self":'):continue
				var wire: Dictionary=JSON.parse_string(line)
				var ref: String=wire.self.working_context.earlier_today.world.experience_ref
				return {"ok":true,"text":JSON.stringify({"read_experience":{"ref":ref,"offset":0,"limit":1}})}
		assert(request.prompt.contains('"records"') and request.prompt.contains("older_0"))
		return {"ok":true,"text":JSON.stringify({"intent":"none","private_interpretation":"读到本人当天更早经历","public_reply":"","speech_style":"","routing_reason":"当前等待","speech_act":"statement","addressed_person":"","capability_gap":null,"task_status":"active","task_handling":{"state":"wait","scope":"independent","reason":"已有事情在进行"},"conversation":{"addressees":[],"participation":"listen","reason":"无需公开回复"}})}
func _initialize():run.call_deferred()
func run():
	create_timer(15).timeout.connect(func():push_error("experience pipeline timeout");quit(1))
	var store=preload("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","user://experience_pipeline_%d.json"%Time.get_ticks_usec(),true).is_empty())
	for i in 20:store.hear("person_001",{"id":"older_%d"%i,"speaker":"body","kind":"need_changed","text":"饥饿发生变化"})
	var pipe=preload("res://scripts/voice/decision_pipeline.gd").new();root.add_child(pipe)
	var gateway:=Gateway.new();root.add_child(gateway);pipe.store=store;pipe.gateway=gateway
	var reports: Array=[];pipe.report_ready.connect(func(r):reports.append(r))
	pipe.run({"id":"current","speaker":"player","kind":"speech_intent","text":"先等一下","listeners":["person_001"]},{})
	await pipe.completed
	assert(gateway.calls==2 and reports.size()==1 and reports[0].has("decision"),str(reports))
	assert(reports[0].experience_reads[0].ok)
	assert(gateway.snapshots[1].begins_with(gateway.snapshots[0]),"读取后保持原场景")
	assert(not reports[0].has("memory_reads"),"展开当天经历不触发长期回忆")
	print("EXPERIENCE_READ_PIPELINE_PASSED frozen_context_read_then_decide")
	quit()
