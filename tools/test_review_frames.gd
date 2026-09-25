extends SceneTree
const Review=preload("res://tools/test_luau_candidate.gd")
func _initialize() -> void:
	var history: Array=[]
	for serial in 180:
		history=Review.retain_history(history)
		history.append({"file":"frame_%04d.jpg"%serial,"time_ms":serial*100})
		assert(history.size()<=64)
		assert(history[0].time_ms==0,"保留执行前基准")
		assert(history[-1].time_ms==serial*100,"额度耗尽后仍须记录最新动作")
	var previous:=-1
	var names: Dictionary={}
	for frame in history:
		assert(frame.time_ms>previous)
		assert(not names.has(frame.file),"不能覆盖仍被引用的历史图片")
		names[frame.file]=true;previous=frame.time_ms
	print("REVIEW_FRAMES_PASSED bounded_history_keeps_start_and_latest")
	quit()
