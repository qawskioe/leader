extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate(); root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new(); scene.add_child(voice)
	voice.config.local_only=true; voice.survival.enabled=false
	await create_timer(0.3).timeout
	var output: TextEdit=voice.menu.output
	output.text="人物状态：正在等待玩家，查看行动结果。\n".repeat(23000)
	var original:=output.text.length()
	var started:=Time.get_ticks_usec()
	voice.log_event({"type":"vr_interaction","hand":"right","pressed":true,"message":"测试握键"})
	var elapsed:=(Time.get_ticks_usec()-started)/1000.0
	print("INTERACTION_LOG_MS ",elapsed," history_chars=",original)
	assert(output.text.length()>original and output.text.ends_with("测试握键\n\n"),"必须保留历史并追加记录")
	assert(elapsed<250,"追加一条交互不能重排全部历史")
	var data:={"intent":"none","recipient_id":"","capability_gap":null,"private_interpretation":"旁听","speech_act":"statement","addressed_person":"","speech_style":"","public_reply":"","routing_reason":"未被询问","offer_response":null}
	var result=load("res://scripts/voice/cloud_client.gd").validate_decision(JSON.stringify(data),true)
	assert(result.ok and not result.decision.has("offer_response"))
	data.offer_response="invalid"
	assert(not load("res://scripts/voice/cloud_client.gd").validate_decision(JSON.stringify(data),true).ok)
	scene.queue_free();await create_timer(0.3).timeout
	print("INTERACTION_LOG_TEST_PASSED")
	quit()
