extends Node
## 复用正在运行的 CapsWriter 服务；每句独立连接，结果不会进入其打字客户端。
const ENDPOINT := "ws://127.0.0.1:6016"
const MAX_CONTEXT_CHARS := 500

static func build_context(names: PackedStringArray, dialogue: Array) -> String:
	# 入口只接受公开称呼和对话摘录，不接收人物资料／反思对象。
	var context := "场景词汇：洞穴、食物、柴火、取水、休息、储食处、篮子、交给、装篮、探索、搬运、果实、吃饭。人物称呼："+"、".join(names).left(100)+"。"
	context += "\n最近公开对话，仅供识别背景，不是本次音频内容："
	for entry in dialogue.slice(maxi(0,dialogue.size()-3)):
		context += "\n"+str(entry.speaker).left(16)+"："+str(entry.text).replace("\n"," ").left(80)
	var boundary := "\n以本次音频为准，不复述或续写背景，不自行更改否定词、人物和数量。"
	return context.left(MAX_CONTEXT_CHARS-boundary.length())+boundary

static func make_payload(wav: PackedByteArray, task_id: String, context: String = "") -> Dictionary:
	if context.length()>MAX_CONTEXT_CHARS:
		return {"ok":false,"error":"识别上下文超过 500 字"}
	var audio := AudioStreamWAV.load_from_buffer(wav)
	if audio == null or audio.format != AudioStreamWAV.FORMAT_16_BITS or audio.stereo or audio.mix_rate != 16000:
		return {"ok":false,"error":"CapsWriter 需要 16kHz 单声道 PCM16 WAV 输入"}
	var raw:=audio.data
	if raw.is_empty() or raw.size()%2 != 0 or raw.size()>16000*2*16:
		return {"ok":false,"error":"CapsWriter 输入为空、损坏或超过 16 秒"}
	var pcm := PackedByteArray()
	pcm.resize(raw.size()*2)
	for i in raw.size()/2:
		pcm.encode_float(i*4,float(raw.decode_s16(i*2))/32768.0)
	return {"ok":true,"payload":{"task_id":task_id,"source":"mic","data":Marshalls.raw_to_base64(pcm),"is_final":true,"time_start":Time.get_unix_time_from_system(),"seg_duration":30.0,"seg_overlap":0.0,"context":context,"language":"Chinese"}}

static func parse_result(raw: String, task_id: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return {"ok":false,"error":"CapsWriter 返回的文本不是有效 JSON"}
	var value: Variant = parser.data
	if not value is Dictionary or value.get("task_id") != task_id or not value.get("is_final") is bool or not value.get("text") is String:
		return {"ok":false,"error":"CapsWriter 返回格式或任务 ID 无效"}
	if not value.is_final:
		return {"ok":true,"pending":true}
	if value.text.strip_edges().is_empty() or value.text.length()>10000:
		return {"ok":false,"error":"CapsWriter 返回空文本或过长文本"}
	return {"ok":true,"text":value.text,"model":"CapsWriter 本机 ASR"}

func transcribe(wav: PackedByteArray, context: String = "") -> Dictionary:
	var task_id := "leader_%s_%s" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var result_box: Dictionary={}
	var script: Script=get_script()
	var task:=WorkerThreadPool.add_task(func(): result_box.value=script.make_payload(wav,task_id,context))
	while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var encoded: Dictionary=result_box.value
	if not encoded.ok:return encoded
	var socket := WebSocketPeer.new()
	socket.supported_protocols = PackedStringArray(["binary"])
	socket.outbound_buffer_size = 2*1024*1024
	socket.inbound_buffer_size = 2*1024*1024
	var started := Time.get_ticks_msec()
	if socket.connect_to_url(ENDPOINT) != OK:
		return {"ok":false,"error":"无法连接 CapsWriter；请启动 start_server.exe（端口 6016）"}
	var sent := false
	while Time.get_ticks_msec()-started < (30000 if sent else 5000):
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			return {"ok":false,"error":"CapsWriter 连接失败或中断；请确认 start_server.exe 正在运行"}
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not sent:
			if socket.send_text(JSON.stringify(encoded.payload)) != OK:
				socket.close()
				return {"ok":false,"error":"CapsWriter 音频发送失败"}
			sent = true
		while socket.get_available_packet_count()>0:
			var result := parse_result(socket.get_packet().get_string_from_utf8(),task_id)
			if not result.get("pending",false):
				socket.close()
				result["elapsed_ms"] = Time.get_ticks_msec()-started
				return result
		await get_tree().process_frame
	socket.close()
	return {"ok":false,"error":"CapsWriter 识别超时；本轮未交给人物模型"}
