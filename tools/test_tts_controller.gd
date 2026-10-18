extends SceneTree
## 用私密哨兵检查控制器边界，空回复和错误决策不能进入 TTS。
const Voice = preload("res://scripts/voice/voice_test.gd")
var failed := false

class FakeTTS extends Node:
	signal audio_chunk(packet: Dictionary)
	var calls: Array = []
	func cancel() -> void: pass
	func speak(text: String, style: String, voice: String) -> Dictionary:
		calls.append({"text":text,"style":style,"voice":voice})
		var pcm := PackedByteArray()
		pcm.resize(4800)
		for i in 4:
			audio_chunk.emit({"sequence":i,"sample_rate":24000,"pcm_base64":Marshalls.raw_to_base64(pcm)})
			await get_tree().create_timer(0.07).timeout
		return {"ok":true,"elapsed_ms":280,"audio_seconds":0.4}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _run() -> void:
	var scene: Node = load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice: Node = scene.get_node_or_null("VoiceTest")
	if voice == null:
		voice = Voice.new()
		voice.name = "VoiceTest"
		scene.add_child(voice)
	voice.store.memory.path = "user://voice_tests/tts_controller_fixture_memory.json"
	voice.config.actions_enabled = false
	voice.config.autonomy_enabled = false
	voice.config.tts_enabled = true # 本测试使用 FakeTTS，不访问语音服务。
	voice.survival.enabled = false
	voice.tts.queue_free()
	var fake := FakeTTS.new()
	voice.add_child(fake)
	voice.tts = fake
	voice.busy = true
	voice._event_started = Time.get_ticks_msec()
	voice._job_config = {"tts_enabled":true}
	var decision := {"intent":"none","private_interpretation":"PRIVATE_SENTINEL_847：我绝不会说出来","public_reply":"好，我去。","speech_style":"neutral","routing_reason":"测试"}
	var report := {"person_id":"person_001","person_name":"石头","event_id":"fixture","calls":[],"decision":decision}
	voice.store.hear("person_001",{"id":"fixture","kind":"player_speech","speaker":"player","text":"请回应","listeners":["person_001"]})
	voice.store.remember("person_001","fixture",decision)
	voice._on_report(report)
	var silent := report.duplicate(true)
	silent.decision.public_reply = " "
	voice._on_report(silent)
	voice._on_report({"person_id":"person_002","person_name":"小花","event_id":"fixture","calls":[],"error":"无效结构"})
	voice._on_completed()
	check(voice.busy,"决策完成后仍需等待语音播放")
	var deadline := Time.get_ticks_msec()+5000
	while voice.busy and Time.get_ticks_msec()<deadline: await process_frame
	check(not voice.busy,"播放排空后应结束本轮")
	check(voice.captions.person_001.speech_label.text=="好，我去。","头顶只显示公开台词")
	check(not voice.captions.person_001.speaking and voice.captions.person_001.remaining>0,"播放结束短暂保留字幕")
	check(voice.store.people.person_001.reflections[0].public_reply_status=="已播放完成；附近成员听闻另行记录","播放成功必须写回人物答复状态")
	check(voice.store.people.person_002.heard_events.back().kind=="public_speech","附近成员记录公开台词")
	check(not JSON.stringify(voice.store.people.person_002.heard_events).contains("PRIVATE_SENTINEL_847"),"听众不能获得发言者私下理解")
	check(fake.calls==[{"text":"好，我去。","style":"neutral","voice":"Puck"}],"只能发送公开台词与语气；沉默和无效决策不调用 TTS")
	check(not JSON.stringify(fake.calls).contains("PRIVATE_SENTINEL"),"内心活动不可泄露")
	check(voice._public_dialogue==[{"speaker":"石头","text":"好，我去。"}],"ASR 对话只记录实际播放成功的公开台词")
	check(not JSON.stringify(voice._public_dialogue).contains("PRIVATE_SENTINEL"),"ASR 上下文不可包含内心")
	voice.reset_context()
	check(voice.captions.person_001.speech_label.text.is_empty(),"重置清空头顶台词")
	check(voice._public_dialogue.is_empty(),"重置角色时同步清空识别对话")
	if not failed: print("TTS_CONTROLLER_PASSED: private_boundary, silence, invalid_decision, turn_waits_for_playback; cloud_calls=0")
	scene.queue_free()
	await create_timer(0.15).timeout
	quit(1 if failed else 0)
