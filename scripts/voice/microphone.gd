extends Node
## 仅按住说话时保留本句音频；VR 预热设备，未按键采样直接丢弃。
signal captured(result: Dictionary)
signal chunk_ready(pcm: PackedByteArray)
signal cancelled
const MAX_SECONDS := 15.0
var effect: AudioEffectCapture
var player: AudioStreamPlayer
var recording := false
var samples := PackedFloat32Array()
var noise_floor_db := -48.0
var _overflow := false
var _bus := -1
var _discarded_start := 0
var _chunk_cursor := 0
var continuous_input := false
var level_db:=-100.0
var _jobs: Array=[]
var _cancel_generation:=0
var recovering:=false
var reconnect_required:=false
const AudioTrace=preload("res://scripts/vr/audio_trace.gd")

func prepare_continuous_input() -> void:
	continuous_input = true
	var started := Time.get_ticks_usec()
	if not player.playing: player.play()
	effect.clear_buffer()
	print("MIC_DEVICE_WARMUP_MS ",(Time.get_ticks_usec()-started)/1000.0)
	AudioTrace.record("mic_warmup",{"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"device":AudioServer.input_device})

func invalidate_connection() -> void:
	reconnect_required=true

func recover_connection(device: String) -> bool:
	if recovering: return false
	recovering=true
	if recording: cancel()
	# 只在唤醒或用户主动恢复时重开，不在每句话开始时重复打开设备。
	var started:=Time.get_ticks_usec()
	if device not in AudioServer.get_input_device_list():
		recovering=false
		AudioTrace.record("mic_reconnect",{"ok":false,"reason":"device_missing","device":device})
		return false
	# WASAPI 的 setter 只排队；连续写回原设备会覆盖切换请求。
	# 保持输入活动，让音频线程实际完成两次切换，不在主线程 stop/play 重开 COM。
	if not player.playing: player.play()
	var intermediate:="Default" if device!="Default" else ""
	if intermediate.is_empty():
		for candidate in AudioServer.get_input_device_list():
			if candidate!="Default":
				intermediate=candidate;break
	if intermediate.is_empty():
		recovering=false
		return false
	var switched:=await _switch_input_device(intermediate)
	# 即使中途超时，也要把请求恢复到用户指定设备。
	var restored:=await _switch_input_device(device)
	effect.clear_buffer()
	continuous_input=true
	reconnect_required=not (switched and restored);recovering=false
	AudioTrace.record("mic_reconnect",{"ok":not reconnect_required,"device":AudioServer.input_device,"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"signal_verified":false})
	return not reconnect_required

func _switch_input_device(device: String) -> bool:
	AudioServer.input_device=device
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		await get_tree().create_timer(0.05).timeout
		if AudioServer.input_device==device:
			return true
	return false

func _ready() -> void:
	AudioServer.add_bus()
	_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bus, "VoiceInputCapture")
	AudioServer.set_bus_mute(_bus, true)
	effect = AudioEffectCapture.new()
	# XR 首帧/失焦期间主线程可能停顿，缓存覆盖整句上限；仍检查实际丢帧。
	effect.buffer_length = MAX_SECONDS + 1.0
	AudioServer.add_bus_effect(_bus, effect)
	player = AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = "VoiceInputCapture"
	add_child(player)

func start() -> void:
	if recovering: return
	level_db=-100.0
	var started := Time.get_ticks_usec()
	samples.clear()
	_chunk_cursor = 0
	_overflow = false
	effect.clear_buffer()
	_discarded_start = effect.get_discarded_frames()
	recording = true
	if not player.playing: player.play()
	print("MIC_START_MS ",(Time.get_ticks_usec()-started)/1000.0)
	AudioTrace.record("mic_start",{"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"device":AudioServer.input_device})

func _process(_delta: float) -> void:
	while not _jobs.is_empty():
		var job: Dictionary=_jobs[0]
		if not WorkerThreadPool.is_task_completed(job.task): break
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.pop_front()
		if job.generation!=_cancel_generation: continue
		var prepared: Dictionary=job.result.value
		prepared["capture_context"]=job.context
		AudioTrace.record("mic_result",{"ok":prepared.ok,"peak_db":prepared.get("peak_db",-100),"prepare_ms":prepared.get("prepare_ms",0)})
		var dispatched:=Time.get_ticks_usec()
		captured.emit(prepared)
		print("MIC_PREPARE_ASYNC_MS worker=",prepared.get("prepare_ms",0)," dispatch=",(Time.get_ticks_usec()-dispatched)/1000.0)
	if not recording:
		if continuous_input: effect.clear_buffer()
		return
	_drain()
	if samples.size() >= int(AudioServer.get_mix_rate() * MAX_SECONDS):
		cancel()
		captured.emit({"ok":false,"error":"录音达到 15 秒上限，已取消，不会自动提交。请松开 V 后重新录音。"})

func _drain() -> void:
	_overflow = _overflow or effect.get_discarded_frames() > _discarded_start
	var frames := effect.get_buffer(effect.get_frames_available())
	var energy:=0.0
	for frame in frames:
		var mono: float=(frame.x + frame.y) * 0.5
		samples.append(mono);energy+=mono*mono
	if not frames.is_empty(): level_db=20.0*log(maxf(sqrt(energy/frames.size()),0.00001))/log(10.0)
	# 没有流式消费者时不重复编码每个音频块（当前 CapsWriter 使用整句）。
	if chunk_ready.get_connections().is_empty():
		_chunk_cursor = samples.size()
		return
	var block := int(AudioServer.get_mix_rate()/10.0)
	while samples.size()-_chunk_cursor >= block:
		_emit_chunk(_chunk_cursor+block)

func _emit_chunk(end_index: int) -> void:
	var wav := encode_wav(samples.slice(_chunk_cursor,end_index),int(AudioServer.get_mix_rate()))
	_chunk_cursor = end_index
	if wav.size()>44:chunk_ready.emit(wav.slice(44))

func cancel() -> void:
	_cancel_generation+=1
	AudioTrace.record("mic_cancel",{"recording":recording})
	recording = false
	if not continuous_input: player.stop()
	effect.clear_buffer()
	samples.clear()
	cancelled.emit()

func finish(context: Dictionary={}) -> void:
	if not recording:
		return
	var started := Time.get_ticks_usec()
	_drain()
	if samples.size()>_chunk_cursor:_emit_chunk(samples.size())
	recording = false
	if not continuous_input: player.stop()
	var stopped := Time.get_ticks_usec()
	if _overflow:
		captured.emit({"ok":false,"error":"录音缓冲区溢出，请重新录音"})
		return
	var holder: Dictionary={}
	var frozen:=samples.duplicate()
	var rate:=int(AudioServer.get_mix_rate())
	var threshold:=noise_floor_db
	var script: Script=get_script()
	var task:=WorkerThreadPool.add_task(func(): holder.value=script.prepare_recording(frozen,rate,threshold))
	_jobs.append({"task":task,"result":holder,"generation":_cancel_generation,"context":context.duplicate(true)})
	print("MIC_FINISH_QUEUED_MS ",(Time.get_ticks_usec()-started)/1000.0)

static func prepare_recording(data: PackedFloat32Array, rate: int, threshold: float) -> Dictionary:
	var started:=Time.get_ticks_usec()
	var analysis := analyze(data, rate, threshold)
	var peak := 0.0
	for sample in data: peak = maxf(peak,absf(sample))
	if analysis.ok:
		analysis["wav"] = encode_wav(data,rate)
	analysis["peak_db"]=linear_to_db(maxf(peak,0.000001))
	analysis["prepare_ms"]=(Time.get_ticks_usec()-started)/1000.0
	return analysis

static func analyze(data: PackedFloat32Array, rate: int, threshold_db: float) -> Dictionary:
	if rate <= 0 or data.size() < rate * 0.20:
		return {"ok":false,"error":"录音不足 0.2 秒，或没有收到麦克风数据"}
	var power := 0.0
	var active := 0
	var clipped := 0
	# 按 20ms 音频块过滤静音，避免一句话前后的停顿降低传播距离。
	var block := maxi(1, rate / 50)
	for start_index in range(0, data.size(), block):
		var end_index := mini(start_index + block, data.size())
		var block_power := 0.0
		for i in range(start_index, end_index):
			block_power += data[i] * data[i]
			if absf(data[i]) >= 0.99:
				clipped += 1
		var count := end_index - start_index
		var db := 10.0 * log(maxf(block_power / count, 1e-12)) / log(10.0)
		if db >= threshold_db:
			power += block_power
			active += count
	if active < rate * 0.12:
		return {"ok":false,"error":"未检测到足够的有效声音；检查输入设备和噪声阈值"}
	return {"ok":true,"db":10.0*log(maxf(power/active,1e-12))/log(10.0),"duration_seconds":float(data.size())/rate,"clipped_ratio":float(clipped)/data.size()}

static func radius_for(db: float, quiet: float, loud: float) -> float:
	return lerpf(2.0, 20.0, clampf((db - quiet) / (loud - quiet), 0, 1))

static func encode_wav(data: PackedFloat32Array, source_rate: int) -> PackedByteArray:
	const TARGET := 16000
	var count := int(float(data.size()) * TARGET / source_rate)
	var wav := PackedByteArray()
	wav.resize(44 + count * 2)
	for pair in [[0,"RIFF"],[8,"WAVE"],[12,"fmt "],[36,"data"]]:
		var bytes: PackedByteArray = pair[1].to_ascii_buffer()
		for i in bytes.size():
			wav[pair[0]+i] = bytes[i]
	wav.encode_u32(4, 36 + count * 2)
	wav.encode_u32(16, 16)
	wav.encode_u16(20, 1)
	wav.encode_u16(22, 1)
	wav.encode_u32(24, TARGET)
	wav.encode_u32(28, TARGET * 2)
	wav.encode_u16(32, 2)
	wav.encode_u16(34, 16)
	wav.encode_u32(40, count * 2)
	for i in count:
		var at := float(i) * source_rate / TARGET
		var left := mini(int(at), data.size()-1)
		var sample := lerpf(data[left], data[mini(left+1,data.size()-1)], at-left)
		wav.encode_s16(44+i*2, int(clampf(sample,-1,1)*32767))
	return wav

func _exit_tree() -> void:
	for job in _jobs: WorkerThreadPool.wait_for_task_completion(job.task)
	if is_instance_valid(player):
		player.stop()
	if _bus >= 0:
		AudioServer.remove_bus(_bus)
