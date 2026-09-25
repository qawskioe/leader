extends SceneTree
const Spatial=preload("res://scripts/voice/spatial_speech.gd")
const Mic=preload("res://scripts/voice/microphone.gd")
const Store=preload("res://scripts/voice/people_store.gd")
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
const Gateway=preload("res://scripts/voice/text_gateway_client.gd")
const Voice=preload("res://scripts/voice/voice_test.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var positions:={"front":Vector3(0,0,-2),"back":Vector3(0,0,2),"far":Vector3(0,0,8)}
	var perception:=Spatial.perception(Vector3.ZERO,Vector3.FORWARD,positions,5)
	assert(perception.heard.has("back") and not perception.heard.has("far"))
	assert(perception.focus_hint=="front")
	var pcm:=PackedFloat32Array()
	pcm.resize(16000*4)
	for index in pcm.size(): pcm[index]=0.1*sin(index*0.1) if index<30000 or index>34000 else 0.0
	var samples: Array=[]
	for index in 40:
		samples.append({"time":index*0.1,"forward":Vector3.FORWARD if index<20 else Vector3.RIGHT})
	var parts:=Spatial.split(Mic.encode_wav(pcm,16000),samples)
	assert(parts.size()==2 and parts[0].end>=1.8 and parts[0].end<=2.2)
	assert(parts[1].start==parts[0].end and parts[1].end==4.0)
	var store:=Store.new()
	assert(store.initialize().is_empty())
	var audience:={"person_001":{},"person_002":{},"person_003":{}}
	var event:={"id":"turn","kind":"speech_intent","speaker":"player","text":"我让你这么做的吗？你觉得他做得怎么样？旁边看着的那个谁？","listeners":audience.keys(),"spatial_segments":[
		{"start_seconds":0,"end_seconds":2,"text":"我让你这么做的吗？","focus_hint":"person_003","audience":audience},
		{"start_seconds":2,"end_seconds":5,"text":"你觉得他做得怎么样？旁边看着的那个谁？","focus_hint":"person_002","audience":audience}]}
	store.hear("person_003",{"id":"command","kind":"speech_intent","speaker":"player","text":"你呀，去把食物糕搬给大山吃。"})
	store.record_execution({"person_id":"person_003","source_event_id":"command","intent":"fetch_food","success":true,"message":"已把一份食物搬到公共食盘，其他人可以取食"})
	for id in audience:
		store.hear(id,{"id":"witness","kind":"observed_action","speaker":"world","actor_id":"person_003","text":"大山把一份食物放到了公共食盘"})
		store.hear(id,event)
	store.hear("person_003",{"id":"later","kind":"public_speech","speaker":"person_001","text":"测试后来听闻"})
	assert(store.event_for("person_003","turn").id=="turn")
	assert(not store.event_for("person_001","turn").spatial_segments[0].has("audience"))
	var isolated: Dictionary=event.duplicate(true)
	isolated.id="partial"
	isolated.spatial_segments[0].audience={"person_003":{}}
	store.hear("person_001",isolated)
	assert(not store.event_for("person_001","partial").text.contains("我让你"))
	# 场景实际投递：公开文字只记听闻，不触发人物模型；成功目击不泄露饥饿。
	var scene: Node=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	scene.add_child(voice)
	voice.config.local_only=true
	voice.survival.enabled=false
	await physics_frame
	var actor: Node3D=scene.get_node("People/Person03")
	var observer: Node3D=scene.get_node("People/Person02")
	actor.position=Vector3(0,0,6)
	observer.position=Vector3(0,0,4)
	observer.rotation=Vector3.ZERO
	await physics_frame
	voice._deliver_public("person_003","spoken_fixture","食物放下了",8)
	assert(voice.store.people.person_002.heard_events.back().kind=="public_speech")
	voice._record_witnesses({"success":true,"intent":"fetch_food","person_id":"person_003","source_event_id":"fixture","hunger":77})
	assert(voice.store.people.person_002.heard_events.back().kind=="observed_action")
	assert(not JSON.stringify(voice.store.people.person_002.heard_events.back()).contains("hunger"))
	assert(not voice.pipeline.busy)
	scene.queue_free()
	await create_timer(0.15).timeout
	print("SPATIAL_PASSED: turning_audio_boundaries, rear_hearing, partial_information, event_identity, public_hearing, witnessed_result, no_recursive_calls")
	if OS.get_cmdline_user_args().has("--cloud"):
		var gateway:=Gateway.new()
		root.add_child(gateway)
		var pipeline:=Pipeline.new()
		pipeline.store=store
		pipeline.gateway=gateway
		root.add_child(pipeline)
		var reports: Array=[]
		pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
		pipeline.run(event,{"text_gateway":true})
		await pipeline.completed
		for report in reports:
			assert(not report.has("error"),str(report))
			assert(report.decision.intent=="none")
			print("SPATIAL_LUNA ",JSON.stringify({"person":report.person_name,"decision":report.decision,"elapsed_ms":report.calls[0].elapsed_ms}))
		var file:=FileAccess.open("res://services/text-gateway/runtime/spatial_verification.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(reports,"\t"))
		print("SPATIAL_CLOUD_SCHEMA_PASSED; read responses for semantic assessment")
	quit()
