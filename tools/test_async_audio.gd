extends SceneTree
var results: Array=[]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var mic=load("res://scripts/voice/microphone.gd").new();root.add_child(mic)
	mic.captured.connect(func(result: Dictionary): results.append(result))
	mic.samples.resize(601088);mic.samples.fill(0.2);mic.recording=true
	var started:=Time.get_ticks_usec()
	mic.finish({"utterance":"original"})
	var immediate_ms: float=(Time.get_ticks_usec()-started)/1000.0
	assert(results.is_empty(),"松键不在主线程处理整段音频")
	assert(immediate_ms<15.0,"松键提交不应明显阻塞")
	while results.is_empty(): await process_frame
	assert(results[0].ok and results[0].capture_context.utterance=="original")
	assert(results[0].wav.size()>100000)
	mic.samples.resize(601088);mic.samples.fill(0.2);mic.recording=true;mic.finish()
	mic.cancel()
	while not mic._jobs.is_empty(): await process_frame
	assert(results.size()==1,"取消后后台音频结果不得重新送出")
	print("ASYNC_AUDIO_PASSED release_ms=",immediate_ms," worker_ms=",results[0].prepare_ms," cancelled_result_discarded=true")
	mic.queue_free();await process_frame;quit()
