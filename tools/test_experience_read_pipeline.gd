extends SceneTree
class Space extends "res://scripts/skills/egocentric_space.gd":
	func capture(id: String) -> Dictionary:
		frames.fixed={"person":id,"transform":Transform3D(Basis.IDENTITY,Vector3(10,0,20)),"created_ms":Time.get_ticks_msec()}
		var samples: Array=[]
		for i in 54:samples.append({"probe":{"x":i*0.75,"y":0,"z":0.75},"position":{"x":0.123456789,"y":0,"z":2.23456789},"state":"visible_surface","surface_kind":"dry_ground"})
		return {"id":"fixed","near_field":{"ground_samples":samples,"landmarks":{},"held_objects":[]}}
	func prepare_context(_id: String, context: Dictionary, observation: Dictionary) -> Dictionary:
		var result:=context.duplicate(true);result.space_observation=observation;return result
class Gateway extends Node:
	var calls:=0
	var snapshots: Array=[]
	var observation_mode:=false
	var space: RefCounted
	func exchange(request: Dictionary) -> Dictionary:
		calls+=1;snapshots.append(request.prompt)
		await get_tree().process_frame
		if calls==1:
			for line in request.prompt.split("\n"):
				if not line.begins_with('{"self":'):continue
				var wire: Dictionary=JSON.parse_string(line)
				if observation_mode:
					var descriptor: Dictionary=wire.self.space_observation.near_field.ground_samples
					assert(descriptor.count==54 and descriptor.max_page_size==64 and space.retained_frames.has("fixed"))
					return {"ok":true,"text":JSON.stringify({"read_experience":{"ref":descriptor.experience_ref,"limit":64}})}
				var ref: String=wire.self.working_context.earlier_today.world.experience_ref
				return {"ok":true,"text":JSON.stringify({"read_experience":{"ref":ref,"offset":0,"limit":1}})}
		if observation_mode:
			var supplement: Dictionary=JSON.parse_string(request.prompt.get_slice("\n你请求的资料：",1))
			assert(supplement.result.records.size()==54 and space.retained_frames.has("fixed"))
			var resolved: Dictionary=space.resolve("person_001",{"observation_id":"fixed","position":supplement.result.records[0].position})
			assert(resolved.ok and resolved.position.distance_to(Vector3(10.123456789,0,22.23456789))<0.00001,"异步读取仍使用保留的同一观察帧，不重新取景或降低坐标精度")
		else:assert(request.prompt.contains('"records"') and request.prompt.contains("older_0"))
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
	var space:=Space.new();pipe.space=space;gateway.space=space;gateway.observation_mode=true;gateway.calls=0;gateway.snapshots.clear();reports.clear()
	pipe.run({"id":"current_observation","speaker":"player","kind":"speech_intent","text":"先看看这里，再等一下","listeners":["person_001"]},{})
	await pipe.completed
	assert(gateway.calls==2 and reports.size()==1 and reports[0].has("decision"))
	assert(reports[0].experience_reads[0].ok and space.retained_frames.is_empty(),"读取和最终决定结束后释放观察租约")
	print("EXPERIENCE_READ_PIPELINE_PASSED frozen_history_and_full_current_observation_read_then_decide")
	quit()
