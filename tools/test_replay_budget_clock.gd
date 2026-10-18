extends SceneTree
## 慢帧下实际截止时间不能跟随被截短的帧delta。
class BudgetProbe extends "res://tools/test_luau_candidate.gd":
	var firings: Array=[]
	func _replay_timeout(seconds: int,started_ms: int) -> void:
		firings.append({"seconds":seconds,"elapsed_ms":Time.get_ticks_msec()-started_ms})
		stopping_replay=true
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var probe:=BudgetProbe.new()
	probe.replay_budget_seconds=1;probe.replay_budget_started_ms=Time.get_ticks_msec()
	var frame_timer:=create_timer(1.0)
	for step in 4:
		OS.delay_msec(300)
		await process_frame
		probe._process(0)
	assert(frame_timer.time_left>0,"夹具必须复现帧计时尚未到期")
	assert(probe.firings.size()==1 and probe.firings[0].elapsed_ms>=1000,"实际截止必须触发且只触发一次")
	probe._process(0)
	assert(probe.firings.size()==1,"清理期间不能重复发起退出")
	print("REPLAY_BUDGET_CLOCK_PASSED wall_elapsed_ms=",probe.firings[0].elapsed_ms," frame_timer_remaining=",frame_timer.time_left)
	probe.free();quit()
