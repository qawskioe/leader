extends RefCounted
## 诊断只记录状态、时间和耗时，不记录音频、识别文本或密钥。
static func record(kind: String, values: Dictionary={}) -> void:
	var row:=values.duplicate()
	row["kind"]=kind
	row["unix_ms"]=int(Time.get_unix_time_from_system()*1000)
	row["ticks_ms"]=Time.get_ticks_msec()
	row["pid"]=OS.get_process_id()
	var path:="res://services/text-gateway/runtime/vr_audio_game_%d.jsonl"%OS.get_process_id()
	var file:=FileAccess.open(path,FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file!=null:
		file.seek_end();file.store_line(JSON.stringify(row))
