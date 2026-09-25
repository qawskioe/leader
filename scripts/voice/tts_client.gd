extends Node
## 读取本机 NDJSON 流；HTTP 200 或 TCP 关闭均不等于音频生成成功。
signal audio_chunk(packet: Dictionary)
signal generation_done
const KEY_PATH := "res://services/gemini-tts/runtime/gateway-key.txt"
var active: HTTPClient
var cancelled := false
var port := 18092

static func config_error() -> String:
	if not FileAccess.file_exists(KEY_PATH):
		return "请通过‘启动语音测试.cmd’启动 Gemini TTS 本机网关"
	return ""

func cancel() -> void:
	cancelled = true
	if active != null: active.close()

func speak(text: String, style: String, voice: String) -> Dictionary:
	if active != null: return {"ok":false,"error":"TTS 请求正在进行"}
	var error := config_error()
	if not error.is_empty(): return {"ok":false,"error":error}
	cancelled = false
	active = HTTPClient.new()
	active.read_chunk_size = 8192
	var result: Dictionary = await _receive(text, style, voice)
	active.close()
	active = null
	return result

func _receive(text: String, style: String, voice: String) -> Dictionary:
	var started := Time.get_ticks_msec()
	if active.connect_to_host("127.0.0.1",port) != OK:
		return {"ok":false,"error":"无法连接 TTS 本机网关"}
	var sent := false
	var headers_checked := false
	var pending := PackedByteArray()
	var sequence := 0
	var total_bytes := 0
	while not cancelled and Time.get_ticks_msec()-started < 100000:
		if active.poll() != OK:
			return {"ok":false,"error":"TTS 连接失败或音频流中断"}
		var state := active.get_status()
		if state == HTTPClient.STATUS_CONNECTED and not sent:
			var key := FileAccess.get_file_as_string(KEY_PATH).strip_edges()
			var err := active.request(HTTPClient.METHOD_POST,"/speak",PackedStringArray(["Content-Type: application/json","Authorization: Bearer " + key]),JSON.stringify({"text":text,"style":style,"voice":voice}))
			if err != OK: return {"ok":false,"error":"无法提交公开台词"}
			sent = true
		elif state == HTTPClient.STATUS_BODY:
			if not headers_checked:
				if active.get_response_code() != 200:
					return {"ok":false,"error":"TTS HTTP %d；检查本机服务、额度与权限" % active.get_response_code()}
				headers_checked = true
			var chunk := active.read_response_body_chunk()
			pending.append_array(chunk)
			if pending.size() > 65536: return {"ok":false,"error":"TTS 消息超过大小上限"}
			var newline := pending.find(10)
			while newline >= 0:
				var parser := JSON.new()
				if parser.parse(pending.slice(0,newline).get_string_from_utf8()) != OK:
					return {"ok":false,"error":"TTS 消息不是有效 JSON"}
				var packet: Variant = parser.data
				pending = pending.slice(newline+1)
				if not packet is Dictionary: return {"ok":false,"error":"TTS 消息不是 JSON 对象"}
				match packet.get("type"):
					"audio":
						if packet.get("sequence") != sequence or packet.get("sample_rate") != 24000 or not packet.get("pcm_base64") is String:
							return {"ok":false,"error":"TTS 音频次序或格式错误"}
						var pcm := Marshalls.base64_to_raw(packet.pcm_base64)
						if pcm.is_empty() or pcm.size()%2 or pcm.size()>4800:
							return {"ok":false,"error":"TTS PCM 分块无效"}
						total_bytes += pcm.size()
						if total_bytes > 1440000: return {"ok":false,"error":"TTS 音频超过 30 秒"}
						sequence += 1
						audio_chunk.emit(packet)
						if cancelled: return {"ok":false,"error":"语音播放已取消"}
					"done":
						if sequence == 0 or packet.get("chunks") != sequence or packet.get("audio_bytes") != total_bytes:
							return {"ok":false,"error":"TTS 完成标记与接收音频不一致"}
						generation_done.emit()
						return {"ok":true,"chunks":sequence,"audio_seconds":total_bytes/48000.0,"elapsed_ms":Time.get_ticks_msec()-started}
					"error": return {"ok":false,"error":str(packet.get("error","TTS 失败"))}
					_: return {"ok":false,"error":"未知 TTS 消息类型"}
				newline = pending.find(10)
		elif state in [HTTPClient.STATUS_DISCONNECTED,HTTPClient.STATUS_CONNECTION_ERROR,HTTPClient.STATUS_CANT_CONNECT,HTTPClient.STATUS_CANT_RESOLVE,HTTPClient.STATUS_TLS_HANDSHAKE_ERROR] or (sent and state == HTTPClient.STATUS_CONNECTED):
			return {"ok":false,"error":"TTS 音频流结束但缺少完成标记"}
		await get_tree().process_frame
	return {"ok":false,"error":"TTS 已取消" if cancelled else "TTS 等待超过 100 秒"}

func _exit_tree() -> void:
	cancel()
