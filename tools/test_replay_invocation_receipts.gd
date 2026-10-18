extends SceneTree
## 回放后来被取消时，前次完成与本次取消的返回必须各自落盘。
class Probe extends "res://tools/test_luau_candidate.gd":
	func _initialize() -> void:pass
class Runtime extends Node:
	var observer: SceneTree
	var cancelled:=false
	func run(_program: Dictionary, _arguments: Dictionary, _api: Node, _linked: Dictionary) -> Dictionary:
		await get_tree().process_frame
		if cancelled:observer.stopping_replay=true
		return {"status":"cancelled" if cancelled else "completed","code":"cancelled" if cancelled else "returned","elapsed_ms":2,"returned":{"ok":not cancelled,"code":"waiting"},"trace":[{"private_fixture":"不得重复写入调用回执"}],"context":{"private_fixture":true},"before":{"global_fixture":true}}
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(5).timeout.connect(func():push_error("invocation receipt timeout");quit(1))
	var probe:=Probe.new()
	var file:="user://replay_invocation_receipts_%d.jsonl"%Time.get_ticks_usec()
	probe.trace_log=FileAccess.open(file,FileAccess.WRITE);assert(probe.trace_log!=null)
	probe.start_ms=Time.get_ticks_msec()
	var runtime:=Runtime.new();root.add_child(runtime);runtime.observer=probe
	var first: Dictionary=await probe.invoke(runtime,{}, {"target":"person/person_002"},{},"original/call/0","original",0)
	assert(first.status=="completed" and not probe.invocation_active)
	probe.validation_case="cancel_and_resume";runtime.cancelled=true
	var second: Dictionary=await probe.invoke(runtime,{}, {"target":"water_source"},{},"changed/call/1","changed",1)
	assert(second.status=="cancelled" and probe.stopping_replay and not probe.invocation_active)
	# 仍未close日志也必须能读到已flush的最后取消回执。
	var rows: Array=[]
	for line in FileAccess.get_file_as_string(file).split("\n",false):rows.append(JSON.parse_string(line))
	assert(rows.size()==4 and rows[0].type=="invocation_started" and rows[1].type=="invocation_finished")
	assert(rows[0].invocation_id==rows[1].invocation_id and rows[2].invocation_id==rows[3].invocation_id and rows[0].invocation_id!=rows[2].invocation_id)
	assert(rows[1].root_request_id=="original" and rows[1].arguments.target=="person/person_002" and rows[1].result.returned.ok)
	assert(rows[3].root_request_id=="changed" and rows[3].step_index==1 and rows[3].validation_case=="cancel_and_resume")
	assert(rows[3].result.status=="cancelled" and rows[3].result.returned.code=="waiting")
	for index in [1,3]:assert(rows[index].result.size()==4 and not rows[index].result.has("trace") and not rows[index].result.has("context") and not rows[index].result.has("before"))
	probe.trace_log.close();probe.free();runtime.queue_free()
	print("REPLAY_INVOCATION_RECEIPTS_PASSED completed_and_cancelled_flushed_distinct_calls_source_args_no_context_trace; cloud_calls=0")
	quit()
