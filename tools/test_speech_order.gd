extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
const TtsTest=preload("res://tools/test_tts_controller.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	scene.add_child(voice)
	voice.config.autonomy_enabled=false
	voice.survival.enabled=false
	voice.tts.queue_free()
	voice.tts=TtsTest.FakeTTS.new()
	voice.add_child(voice.tts)
	voice.busy=true
	voice._job_config={"tts_enabled":true,"actions_enabled":false}
	voice._speech_order=["person_003","person_001"]
	var decision:={"intent":"none","private_interpretation":"顺序测试","public_reply":"后问的石头","speech_style":"neutral","routing_reason":"夹具"}
	voice.store.remember("person_001","order",decision)
	voice._on_report({"person_id":"person_001","person_name":"石头","event_id":"order","calls":[],"decision":decision.duplicate(true)})
	await create_timer(0.05).timeout
	assert(voice.tts.calls.is_empty(),"后问者先返回时不能抢先播放")
	decision.public_reply="先问的大山"
	voice.store.remember("person_003","order",decision)
	voice._on_report({"person_id":"person_003","person_name":"大山","event_id":"order","calls":[],"decision":decision})
	voice._on_completed()
	var deadline:=Time.get_ticks_msec()+5000
	while voice.busy and Time.get_ticks_msec()<deadline: await process_frame
	assert(not voice.busy)
	assert(voice.tts.calls[0].text=="先问的大山" and voice.tts.calls[1].text=="后问的石头")
	print("SPEECH_ORDER_PASSED: out_of_order_model_results, ordered_public_speech")
	scene.queue_free()
	await create_timer(0.15).timeout
	quit()
