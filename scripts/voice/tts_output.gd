extends AudioStreamPlayer3D
## 音频块抵达后只攒约 170ms 再播放，不等待整句音频。
signal playback_started
signal drained
signal failed(message: String)
var pending: Array[PackedVector2Array] = []
var queued_frames := 0
var received_frames := 0
var next_sequence := 0
var ended := false
var started := false
var complete := false
var error_message := ""
var capacity := 0
var generator_playback: AudioStreamGeneratorPlayback

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 24000
	generator.buffer_length = 0.5
	stream = generator
	position = Vector3(0,1.6,0)
	unit_size = 6.0
	max_distance = 30.0

func push_chunk(event: Dictionary) -> void:
	if complete:return
	if event.get("sample_rate") != 24000 or event.get("sequence") != next_sequence or not event.get("pcm_base64") is String:
		_fail("音频分块采样率或次序错误")
		return
	var pcm := Marshalls.base64_to_raw(event.pcm_base64)
	if pcm.is_empty() or pcm.size()%2 or pcm.size()>16000:
		_fail("音频分块格式错误")
		return
	var frames := PackedVector2Array()
	frames.resize(pcm.size()/2)
	for i in frames.size():
		var value := float(pcm.decode_s16(i*2))/32768.0
		frames[i] = Vector2(value,value)
	pending.append(frames)
	queued_frames += frames.size()
	received_frames += frames.size()
	next_sequence += 1
	if queued_frames > 24000*30:_fail("播放缓冲积压超过三十秒")

func finish() -> void:
	ended = true

func _process(_delta: float) -> void:
	if complete:return
	if not started:
		if queued_frames>=4096 or (ended and queued_frames>0):
			play()
			generator_playback = get_stream_playback()
			capacity = generator_playback.get_frames_available()
			started = true
		else:
			if ended:_fail("上游没有返回可播放的音频")
			return
	while not pending.is_empty() and generator_playback.get_frames_available()>=pending[0].size():
		var frames: PackedVector2Array = pending.pop_front()
		if not generator_playback.push_buffer(frames):
			_fail("写入实时播放缓冲失败")
			return
		queued_frames -= frames.size()
		if received_frames == frames.size() or not has_meta("announced"):
			set_meta("announced",true)
			playback_started.emit()
	if ended and pending.is_empty() and generator_playback.get_frames_available()>=capacity:
		complete = true
		stop()
		generator_playback = null
		drained.emit()

func _fail(message: String) -> void:
	if complete:return
	complete = true
	error_message = message
	stop()
	generator_playback = null
	failed.emit(message)
	drained.emit()

func _exit_tree() -> void:
	stop()
	generator_playback = null
