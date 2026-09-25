extends SceneTree
const Client = preload("res://scripts/voice/tts_client.gd")
const Output = preload("res://scripts/voice/tts_output.gd")
var failed := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _run() -> void:
	var client := Client.new()
	client.port = 18093
	root.add_child(client)
	var output := Output.new()
	root.add_child(output)
	var starts: Array = []
	output.playback_started.connect(func(): starts.append(not output.ended))
	client.audio_chunk.connect(output.push_chunk)
	var result: Dictionary = await client.speak("valid","neutral","Kore")
	check(result.ok,"完整流必须成功："+JSON.stringify(result))
	output.finish()
	if not output.complete: await output.drained
	check(output.error_message.is_empty() and output.received_frames==7680,"音频必须完整播放")
	check(starts==[true],"必须且只能在生成结束前启动一次播放")
	client.audio_chunk.disconnect(output.push_chunk)
	for mode in ["truncated","wrong_order","wrong_done","error","bad_json","http_error"]:
		result = await client.speak(mode,"neutral","Kore")
		check(not result.ok,"不得把失败流当成功："+mode)
	var cancel_callback := func(_packet: Dictionary): client.cancel()
	client.audio_chunk.connect(cancel_callback)
	result = await client.speak("cancel","neutral","Kore")
	check(not result.ok and client.active==null,"取消必须关闭连接")
	client.audio_chunk.disconnect(cancel_callback)
	result = await client.speak("valid","neutral","Kore")
	check(result.ok,"取消后下一轮必须可用")
	var overflow := Output.new()
	root.add_child(overflow)
	var pcm := PackedByteArray()
	pcm.resize(4800)
	for i in 301:
		overflow.push_chunk({"sequence":i,"sample_rate":24000,"pcm_base64":Marshalls.raw_to_base64(pcm)})
	check(overflow.complete and not overflow.error_message.is_empty(),"必须限制缓冲积压")
	for node in [client,output,overflow]: node.queue_free()
	await process_frame
	if not failed: print("TTS_CONTRACT_PASSED: stream_before_done, split_json, drain, truncation, sequence, done_counts, upstream_error, cancel_and_reuse, bounded_audio; cloud_calls=0")
	quit(1 if failed else 0)
