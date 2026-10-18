extends SceneTree
## 独立麦克风生命周期，无世界、HTTP、模型或正式存档。弱引用不延长被测资源寿命。
const Microphone=preload("res://scripts/voice/microphone.gd")

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(12).timeout.connect(func():push_error("microphone lifecycle timeout");quit(1))
	var detach: bool=OS.get_cmdline_user_args().has("--detach-stream")
	var settle: bool=not OS.get_cmdline_user_args().has("--no-settle")
	var buses: int=AudioServer.bus_count
	var mic:=Microphone.new();root.add_child(mic)
	mic.prepare_continuous_input()
	if settle:
		await process_frame;await process_frame
	var stream: WeakRef=weakref(mic.player.stream)
	var playback: WeakRef=weakref(mic.player.get_stream_playback())
	var input_active: bool=mic.player.get_stream_playback().is_playing()
	mic.cancel()
	if mic.recording or not mic.continuous_input or not mic.player.playing:
		push_error("取消单句不能关闭持续收音");quit(1);return
	if OS.get_cmdline_user_args().has("--quit-live"):
		print("MICROPHONE_LIVE_EXIT_PROBE input_playback_active=",input_active)
		quit();return
	if OS.get_cmdline_user_args().has("--shutdown-exit"):
		var stopped: String=await mic.stop_for_shutdown()
		if not stopped.is_empty() or stream.get_ref()!=null or playback.get_ref()!=null or mic.continuous_input:
			push_error("退出前收音资源未完整释放："+stopped);quit(1);return
		assert((await mic.stop_for_shutdown()).is_empty(),"已停止收音的重复关闭须幂等")
		print("MICROPHONE_SHUTDOWN_PASSED input_playback_active=",input_active," stream_playback_released_before_immediate_quit idempotent cloud_calls=0")
		quit();return
	if detach:mic.player.stream=null
	mic.queue_free();await create_timer(0.2).timeout
	var stream_alive: bool=stream.get_ref()!=null
	var playback_alive: bool=playback.get_ref()!=null
	var bus_restored: bool=AudioServer.bus_count==buses
	print("MIC_LIFECYCLE ",JSON.stringify({"detach_stream":detach,"settle_frames":2 if settle else 0,"input_playback_active":input_active,"stream_alive":stream_alive,"playback_alive":playback_alive,"bus_restored":bus_restored,"model_calls":0}))
	if stream_alive or playback_alive or not bus_restored:
		push_error("麦克风销毁后仍有资源或总线残留");quit(1);return
	print("MICROPHONE_LIFECYCLE_PASSED continuous_cancel_preserved_stream_playback_released_bus_restored")
	quit()
