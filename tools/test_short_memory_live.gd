extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/short_live_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var id:="person_003";var sim=voice.survival;var store=voice.store
	var refs: Dictionary={}
	for entry in voice.skills.library.describe(id): refs[voice.skills.library.definitions[entry.ref].id]=entry.ref
	var request:={"id":"short_task","kind":"speech_intent","speaker":"player","text":"大山，把你面前那两个东西全搬到池塘外面去。","listeners":[id]}
	store.hear(id,request)
	var outcome: Dictionary={}
	for goal in ["take_object","place_object"]:
		var args: Dictionary={"object":"stone_tool"}
		if goal=="place_object":
			var observation: Dictionary=sim.space.capture(id)
			var sample: Dictionary={}
			for point in observation.near_field.ground_samples:
				if point.get("surface_kind")=="dry_ground" and absf(point.position.x-3)<0.01 and absf(point.position.z-0.75)<0.01: sample=point
			assert(not sample.is_empty())
			args.target={"observation_id":observation.id,"position":sample.position}
		var event:={"id":goal,"kind":"skill_progress","speaker":"world","text":"继续原任务","original_event":request}
		if store.working_tasks.has(id): event.original_event=store.working_tasks[id].request.duplicate(true)
		store.hear(id,event)
		store.remember(id,goal,{"private_interpretation":"目标是石块和木块，都要搬到池塘外，木块尚未处理","public_reply":"","skill_call":{"ref":refs[goal],"arguments":args}})
		assert(voice.skills.invoke(id,goal,{"ref":refs[goal],"arguments":args}).ok)
		outcome=await voice.skills.finished
		if not outcome.success: print("SHORT_LIVE_SETUP_FAILED ",outcome.message);scene.queue_free();await create_timer(0.2).timeout;quit(1);return
	# 放好第一件后转离木块；不把它的真实新位置重新灌给角色。
	# 明确让背部朝向原始物品位置，采用+Z为人物正前方。
	var away: Vector3=sim.actors[id].body.global_position-voice.skills.world_objects.objects.wood_block.body.global_position
	sim.actors[id].body.rotation.y=atan2(away.x,away.z)
	sim.perception.observe(id)
	assert(not sim.perception.known(id,"wood_block").visible_now)
	var pipeline=preload("res://scripts/voice/decision_pipeline.gd").new();pipeline.store=store;pipeline.space=sim.space;pipeline.gateway=voice.pipeline.gateway;scene.add_child(pipeline)
	var reports: Array=[];pipeline.report_ready.connect(func(r):reports.append(r))
	pipeline.run({"id":"after_stone","kind":"skill_progress","speaker":"world","text":"石块已在池塘外干地放稳，请根据实际结果继续处理原请求。","original_event":store.working_tasks[id].request.duplicate(true),"result":outcome,"listeners":[id]}, {})
	await pipeline.completed
	var passed: bool=reports.size()==1 and not reports[0].has("error")
	if passed:
		var decision: Dictionary=reports[0].decision
		passed=decision.private_interpretation.contains("木块") and not decision.public_reply.contains("哪个") and not decision.public_reply.contains("哪一件") and reports[0].get("memory_reads",[]).is_empty()
	var file:=FileAccess.open("res://services/luau-runtime/runtime/short_memory_live.json",FileAccess.WRITE);file.store_string(JSON.stringify(reports,"  "));file.close()
	print("SHORT_MEMORY_LIVE_PASSED" if passed else "SHORT_MEMORY_LIVE_FAILED")
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
