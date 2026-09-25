extends SceneTree
## 真实本机识别与文字模型 端到端测试：合成语音代替麦克风，实际 V 输入、传播、决策和 3D 播放。
const Voice = preload("res://scripts/voice/voice_test.gd")
var voice: Node
var started := 0
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		var file := FileAccess.open("res://services/text-gateway/runtime/game_verification.json",FileAccess.WRITE)
		file.store_string(JSON.stringify({"result":"failed","error":message,"log_path":ProjectSettings.globalize_path(voice._log_path) if is_instance_valid(voice) else "","real_upstream":true},"\t"))
		push_error("GAME_FAILED " + message)
		quit(1)

func _run() -> void:
	var scene: Node = load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	voice = scene.get_node_or_null("VoiceTest")
	if voice == null:
		voice = Voice.new()
		voice.name = "VoiceTest"
		scene.add_child(voice)
	voice.cancel_recording_on_focus_loss = false
	var file := FileAccess.open("res://tools/fixtures/command.wav", FileAccess.READ)
	check(file != null, "缺少真实上游生成的语音夹具")
	if failed: return
	var wav := file.get_buffer(file.get_length())
	var stream := AudioStreamWAV.load_from_buffer(wav)
	check(stream != null, "语音夹具无法解码")
	if failed: return
	voice.mic.player.stream = stream
	voice.config.capswriter_asr = true
	voice.config.local_only = false
	voice.config.tts_enabled = true
	voice.config.actions_enabled = false
	voice.survival.enabled = false
	# 只变更本轮位置夹具：两名听众在近处，其余两人在范围外。
	scene.get_node("Player").position = Vector3(0,0,0)
	var index := 0
	for id in voice.store.people:
		var person: Node3D = scene.get_node("People/" + voice.store.people[id].node)
		person.position = Vector3(1+index,0,0) if index < 2 else Vector3(100+index,0,0)
		index += 1
	voice.menu.panel.hide()
	# 自动化期间禁用焦点取消，避免工具窗口切换干扰合成输入。
	voice.set_process_input(false)
	voice.log_event({"type":"qa","message":"真实本机识别与文字模型 测试；以合成语音替代麦克风，两名听众、两名范围外成员；无行动执行"})
	started = Time.get_ticks_msec()
	var pressed := InputEventKey.new()
	pressed.physical_keycode = KEY_V
	pressed.pressed = true
	voice._input(pressed)
	check(voice.mic.recording, "录音未开始")
	await create_timer(stream.get_length()+0.3).timeout
	var released := InputEventKey.new()
	released.physical_keycode = KEY_V
	voice._input(released)
	check(voice.busy, "音频未送出")
	if failed: return
	while voice.busy and Time.get_ticks_msec()-started < 850000:
		await create_timer(0.5).timeout
	check(not voice.busy, "整轮超时")
	var index2 := 0
	for id in voice.store.people:
		var p: Dictionary = voice.store.people[id]
		check(p.heard_events.size() == (1 if index2 < 2 else 0), "听闻范围错误：" + id)
		check(p.reflections.size() == (1 if index2 < 2 else 0), "私下判断缺失／越界：" + id)
		if failed: return
		index2 += 1
	var records: Array = []
	for line in FileAccess.get_file_as_string(voice._log_path).split("\n",false):
		records.append(JSON.parse_string(line))
	var text_calls := 0
	var spoken := 0
	var tts_calls := 0
	var errors := 0
	var forbidden_voice_calls := 0
	var streamed_starts := 0
	var first_reply_ms := -1
	var total_ms := -1
	var transcript_complete := false
	var asr_calls := 0
	var submitted := false
	var no_early_reply := true
	for record in records:
		if record.type == "asr_request":
			asr_calls += 1
			check(submitted and not record.while_recording,"本机识别不得早于松开 V")
			check(record.get("context_characters",0)>0 and record.get("context","").contains("石头"),"实际识别请求必须携带场景上下文")
		if record.type == "role_result":
			check(not record.report.has("error"),"文字模型判断失败")
			text_calls += record.report.calls.size()
		if record.type == "spoken": spoken += 1
		if record.type == "tts_request": tts_calls += 1
		if record.type == "error": errors += 1
		if record.type == "input_streaming":forbidden_voice_calls+=1
		if record.type == "speaking_started" and record.get("before_speech_done",false):
			streamed_starts += 1
			if first_reply_ms<0:first_reply_ms=int(record.elapsed_ms)
		if record.type == "completed":total_ms=int(record.elapsed_ms)
		if record.type == "transcript":transcript_complete=record.event.text.contains("食物") and record.event.text.contains("休息")
		if record.type == "utterance_finished":submitted=not record.while_recording
		if record.type in ["role_result","live_role_result","speaking_started"] and not submitted:no_early_reply=false
		if record.type == "speaking_started" and record.get("while_recording",false):no_early_reply=false
	check(errors == 0, "存在语音错误")
	check(forbidden_voice_calls==0 and asr_calls==1,"只允许结束后本机识别")
	check(spoken > 0 and streamed_starts > 0,"必须实际流式播放公开答复，不能等待整句完成")
	check(transcript_complete,"必须收到测试句尾的食物与休息安排")
	check(submitted and no_early_reply,"结束录音前不得进行人物决策或播放回复")
	check(text_calls==2,"两位听众必须各调用一次独立文字模型")
	if failed: return
	voice.menu.open()
	if DisplayServer.get_name() != "headless":
		for frame in range(8): await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://previews/game_output.png")
	var report := {"result":"passed","route":"capswriter_structured_llm_cloud_tts","external_text_model_calls":text_calls,"private_state_extracted":true,"real_upstream":true,"real_microphone":false,"renderer":DisplayServer.get_name(),"listeners":2,"outside_listeners":2,"spoken":spoken,"tts_calls":tts_calls,"forbidden_input_stream_calls":forbidden_voice_calls,"streamed_starts":streamed_starts,"first_reply_ms":first_reply_ms,"turn_ms":total_ms,"elapsed_ms":Time.get_ticks_msec()-started,"log_path":ProjectSettings.globalize_path(voice._log_path)}
	var output := FileAccess.open("res://services/text-gateway/runtime/game_verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("GAME_PASSED ",JSON.stringify(report))
	quit()
