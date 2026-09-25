extends SceneTree
## 同一合成录音先不带、再带上下文走真实 CapsWriter；不模拟改善率。
const Caps = preload("res://scripts/voice/capswriter_client.gd")
const Mic = preload("res://scripts/voice/microphone.gd")
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var client := Caps.new()
	root.add_child(client)
	var context := Caps.build_context(PackedStringArray(["石头","小花","大山","月亮"]),[
		{"speaker":"玩家","text":"你觉得自己应该获得食物吗？"},
		{"speaker":"大山","text":"我已经吃过了，现在不饿。石头搬了很多柴，应该把食物分给他。"}])
	var results: Array = []
	var failed := false
	for path in ["res://tools/fixtures/command.wav","res://services/gemini-tts/runtime/asr_context_fixture.wav"]:
		var source := AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(path))
		if source==null or source.stereo or source.format!=AudioStreamWAV.FORMAT_16_BITS:
			push_error("无效测试音频")
			quit(1)
			return
		var samples := PackedFloat32Array()
		var frames := source.data.size()/2
		samples.resize(int(float(frames)*16000/source.mix_rate))
		for i in samples.size():
			var position := float(i)*source.mix_rate/16000.0
			var lo := int(position)
			samples[i] = lerpf(float(source.data.decode_s16(lo*2)),float(source.data.decode_s16(mini(lo+1,frames-1)*2)),position-lo)/32768.0
		var wav := Mic.encode_wav(samples,16000)
		for hint in ["",context]:
			var response: Dictionary = await client.transcribe(wav,hint)
			results.append({"fixture":path,"context_enabled":not hint.is_empty(),"result":response})
			print("ASR_CONTEXT_RESULT ",JSON.stringify(results.back()))
			if not response.ok: failed = true
	var file := FileAccess.open("res://services/text-gateway/runtime/asr_context_verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"context":context,"results":results,"synthetic_audio_only":true},"\t"))
	quit(1 if failed else 0)
