extends SceneTree

class ASR extends Node:
	signal finished(response: Dictionary)
	var calls := 0
	func transcribe(_wav: PackedByteArray, _context: String = "") -> Dictionary:
		calls += 1
		return await finished

class Probe extends "res://scripts/voice/voice_test.gd":
	var delivered: Array[Dictionary] = []
	func _start_pipeline(event: Dictionary, _job: Dictionary) -> void:
		delivered.append(event.duplicate(true))

func _initialize() -> void: run.call_deferred()

func capture(voice: Node) -> Dictionary:
	var eye: Camera3D = voice.get_parent().get_node("Player/Eyes")
	var positions: Dictionary = {}
	for id in voice.store.people:
		positions[id] = voice.get_parent().get_node("People/" + voice.store.people[id].node).global_position + Vector3(0, 1.6, 0)
	var pcm := PackedFloat32Array()
	pcm.resize(8000)
	for index in pcm.size(): pcm[index] = 0.2 * sin(index * 0.1)
	return {"ok": true, "wav": voice.Mic.encode_wav(pcm, 16000), "db": -17.0, "duration_seconds": 0.5, "clipped_ratio": 0.0,
		"capture_context": {"source": eye.global_position, "positions": positions, "config": voice.config.duplicate(true),
			"samples": [{"time": 0.0, "source": eye.global_position, "forward": -eye.global_basis.z, "positions": positions}]}}

func run() -> void:
	create_timer(15).timeout.connect(func(): push_error("voice preprocessing timeout"); quit(1))
	var scene = load("res://scenes/initial_base.tscn").instantiate(); root.add_child(scene)
	var voice = Probe.new(); scene.add_child(voice); voice.set_process(false)
	while not voice.survival.ready_for_actions: await physics_frame
	voice.config.local_only = false; voice.config.autonomy_enabled = false; voice.config.capswriter_asr = true
	voice.survival.enabled = false; voice.menu.close()
	voice.capswriter.queue_free()
	var asr := ASR.new(); voice.add_child(asr); voice.capswriter = asr
	voice.busy = true; voice._display_event_id = "ongoing_npc_turn"
	voice._event_rounds["ongoing_npc_turn"] = 12; voice._display_round = 12
	voice._job_config = {"marker": "ongoing"}; voice._event_started = 12345
	var audio := capture(voice)
	voice._on_captured(audio)
	await process_frame
	assert(asr.calls == 1, "人物忙碌不能阻塞本地转写的启动")
	assert(voice.delivered.is_empty(), "转写不能抢先发起人物决策")
	var original_position: Vector3 = scene.get_node("Player").position
	scene.get_node("Player").position += Vector3(30, 0, 0)
	asr.finished.emit({"ok": true, "text": "先接住水袋，暂时不要喝。", "elapsed_ms": 5})
	await process_frame
	assert(voice.last_player_transcript == "先接住水袋，暂时不要喝。", "人物忙碌期间也要立即显示已识别原话")
	assert(voice.busy and voice._display_event_id == "ongoing_npc_turn", "转写不得替换在途人物轮次")
	assert(voice._job_config.marker == "ongoing" and voice._event_started == 12345, "转写不得改在途配置和计时")
	assert(voice.delivered.is_empty())
	scene.get_node("Player").position = original_position
	assert(voice.say_text("随后补充的话").is_empty())
	voice._queue_offer({"id": "later_receipt", "kind": "received_item", "speaker": "world", "listeners": ["person_001"], "text": "随后发生的交付"})
	voice.busy = false; voice._process(0)
	assert(voice.delivered.size() == 1 and voice.delivered[0].text == "先接住水袋，暂时不要喝。")
	assert(voice.last_player_transcript == "随后补充的话", "先发语音开始执行不能覆盖后来发出的原话")
	assert(voice.delivered[0].source_position == [audio.capture_context.source.x, audio.capture_context.source.y, audio.capture_context.source.z], "转写后仍使用原录音空间，不能重新取景")
	assert(not voice.delivered[0].listeners.is_empty())
	voice.busy = false; voice._process(0)
	assert(voice.delivered[-1].text == "随后补充的话", "后发文字不能越过先发语音")
	voice.busy = false; voice._process(0)
	assert(voice.delivered[-1].id == "later_receipt" and voice._pending_inputs.is_empty(), "交付继续按真实发送顺序处理")
	scene.get_node("Player").position = original_position
	voice.busy = true; voice._on_captured(capture(voice))
	asr.finished.emit({"ok": false, "error": "测试中的识别失败"})
	await process_frame
	assert(voice.busy, "转写失败不能释放其他在途人物决策")
	voice.busy = false; voice._process(0)
	assert(voice.delivered.size() == 3 and voice._pending_inputs.is_empty(), "失败语音不进入人物决策，后续输入不被堵住")
	voice.busy = true; voice._on_captured(capture(voice))
	voice.cancel_interaction()
	asr.finished.emit({"ok": true, "text": "取消后迟到的文字", "elapsed_ms": 5})
	await process_frame
	assert(voice.last_player_transcript != "取消后迟到的文字" and voice._pending_inputs.is_empty(), "取消后迟到的识别不得显示或执行")
	assert(voice.delivered.size() == 3)
	voice.busy = true; voice._on_captured(capture(voice)); voice._on_captured(capture(voice))
	assert(asr.calls == 4, "本地识别自身保持串行")
	asr.finished.emit({"ok": true, "text": "第四句", "elapsed_ms": 5})
	voice._process(0)
	assert(asr.calls == 5 and voice.busy)
	asr.finished.emit({"ok": true, "text": "第五句", "elapsed_ms": 5})
	await process_frame
	assert(voice.last_player_transcript == "第五句")
	voice.busy = false; voice._process(0)
	assert(voice.delivered[-1].text == "第四句" and voice.last_player_transcript == "第五句", "先发语音执行时不得覆盖已识别的新一句")
	voice.busy = false; voice._process(0)
	assert(voice.delivered[-1].text == "第五句" and voice._pending_inputs.is_empty())
	print("VOICE_PREPROCESSING_PASSED busy_asr_immediate_text_mixed_fifo_frozen_space_failure_cancel; real_model_calls=0")
	scene.queue_free(); await process_frame; quit()
