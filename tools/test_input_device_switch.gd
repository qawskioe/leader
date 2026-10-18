extends SceneTree
## 真实设备阻塞由独立WASAPI探针复现；这里用慢设备替身验证调度与退出边界。
class SlowMic extends "res://scripts/voice/microphone.gd":
	static func switch_input_device_on_worker(device: String) -> bool:
		OS.delay_msec(200)
		return device=="valid"
var last_tick:=0
var max_gap_ms:=0.0
var frames:=0
var measure:=false
func _initialize() -> void:
	Engine.max_fps=120
	process_frame.connect(tick)
	create_timer(8).timeout.connect(func():quit(1))
	run.call_deferred()
func tick() -> void:
	var now:=Time.get_ticks_usec()
	if measure and last_tick!=0:
		max_gap_ms=maxf(max_gap_ms,(now-last_tick)/1000.0)
		frames+=1
	last_tick=now
func run() -> void:
	var mic:=SlowMic.new();root.add_child(mic)
	measure=true;last_tick=Time.get_ticks_usec()
	assert(await mic._switch_input_device("valid"),"设备事务返回真实成功结果")
	await process_frame;await process_frame
	measure=false
	assert(frames>=5 and max_gap_ms<80.0,"慢设备不能冻结主线程")
	assert(mic._device_switch_tasks.is_empty(),"完成的工作任务必须收束")
	assert(not await mic._switch_input_device("invalid"),"失败不能转换成成功")
	mic._switch_input_device("unload")
	assert(mic._device_switch_tasks.size()==1)
	root.remove_child(mic)
	assert(mic._device_switch_tasks.is_empty() and mic._exiting,"退出等待设备线程，并使迟到协程失效")
	await process_frame;await process_frame
	mic.free()
	print("INPUT_DEVICE_SWITCH_PASSED async_slow_device_true_failure_exit_join; max_frame_gap_ms=",max_gap_ms," model_calls=0")
	quit()
