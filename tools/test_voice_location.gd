extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.set_process(false)
	while not voice.survival.ready_for_actions: await physics_frame
	var sim=voice.survival;sim.enabled=false
	var receiver: CharacterBody3D=sim.actors.person_001.body
	var speaker: CharacterBody3D=sim.actors.person_002.body
	receiver.position=Vector3(1,0.2,6);receiver.rotation.y=-PI/2
	speaker.position=Vector3(4,0.2,6)
	sim.actors.person_003.body.position=Vector3(80,0.2,80)
	sim.perception.memories.person_001.clear();sim.perception.memories.person_003.clear()
	await physics_frame
	assert(not sim.perception.sees("person_001",speaker.global_position+Vector3.UP))
	assert(sim.perception.known("person_001","person/person_002").is_empty())
	sim.perception.clock=20
	var revision: int=sim.perception.revisions.person_001
	voice._deliver_public("person_002","voice_probe","我在这里。",12)
	assert(sim.perception.revisions.person_001==revision,"声源定位不能重复触发无关的饥饿模型调用")
	var heard: Dictionary=sim.perception.known("person_001","person/person_002")
	assert(not heard.visible_now and heard.heard_from=="person_002" and heard.source_event_id=="voice_probe")
	assert(heard.position_error_per_axis_m==2 and heard.source.contains("听到"))
	assert(Vector3(heard.position[0],heard.position[1],heard.position[2]).distance_to(speaker.global_position)<=2)
	assert(sim.perception.known("person_003","person/person_002").is_empty(),"范围外听众不能获得声源位置")
	voice.config.autonomy_enabled=true
	voice._round_events["reply_probe"]={"id":"reply_probe","kind":"information_request","speaker":"person_001","text":"你在哪里？"}
	voice.store.hear("person_002",{"id":"reply_probe","kind":"information_request","speaker":"person_001","text":"你在哪里？"})
	var reply:={"speech_act":"reply","addressed_person":"person_001","request_kind":"information"}
	voice._deliver_public("person_002","reply_probe","我在这里。",12,reply)
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="information_received","询问者应能根据实际听到的回答声源继续判断")
	voice.store.hear("person_002",{"id":"thanks_probe","kind":"information_received","speaker":"person_001","text":"听到了，谢谢"})
	voice._deliver_public("person_002","thanks_probe","好。",12,reply)
	assert(voice.autonomy.requests.size()==1,"普通后续回应不能仅因声源更新就无限互相唤醒")
	var position: Array=heard.position.duplicate()
	speaker.global_position=Vector3(50,0.2,50);sim.perception.observe("person_001")
	assert(sim.perception.known("person_001","person/person_002").position==position,"听闻不能跟踪后来未看见的移动")
	speaker.position=Vector3(4,0.2,6);receiver.rotation.y=PI/2
	await physics_frame
	sim.perception.clock=30;sim.perception.observe("person_001")
	var seen: Dictionary=sim.perception.known("person_001","person/person_002")
	assert(seen.visible_now and not seen.has("position_error_per_axis_m"))
	voice._deliver_public("person_002","voice_seen","就在这里。",12)
	assert(sim.perception.known("person_001","person/person_002")==seen,"已目视确认的位置不能被粗略听声覆盖")
	# 发声者问远处目标：未被听到也要记录本人在等答复。
	voice.autonomy.requests.clear()
	speaker.position=Vector3(50,0.2,50)
	var question:={"id":"wait_probe","speaker":"player","kind":"speech_intent","text":"问问她在哪"}
	voice.store.hear("person_001",question)
	voice._deliver_public("person_001","wait_probe","你在哪里？",12,{"speech_act":"request","request_kind":"information","addressed_person":"person_002"})
	assert(voice.information_waits.pending.has("wait_probe_request_person_002"))
	assert(voice.autonomy.requests.is_empty(),"目标未听见不能强行收到询问")
	var unanswered: Dictionary=voice.information_waits.next_event(voice._autonomy_clock+46,sim.actors)
	assert(not unanswered.is_empty())
	voice.autonomy.offer_request(unanswered,voice._autonomy_clock+46)
	# 稍后真实听到回答；眼前人物不产生新声源位置，也必须交回询问者处理。
	speaker.position=Vector3(4,0.2,6)
	await physics_frame
	sim.perception.observe("person_001")
	var response:={"id":"wait_probe_request_person_002","kind":"information_request","speaker":"person_001","text":"你在哪里？","source_event_id":"wait_probe"}
	voice._round_events[response.id]=response
	voice.store.hear("person_002",response)
	voice._deliver_public("person_002",response.id,"就在你眼前。",12,reply)
	assert(voice.information_waits.pending.is_empty())
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="information_received")
	assert(voice.autonomy.requests[0].listeners==["person_001"])
	print("VOICE_LOCATION_PASSED heard_only_coarse_not_tracking_visual_priority_range")
	scene.queue_free();await create_timer(0.2).timeout;quit()
