extends SceneTree
## 验证编写传输格式与隔离执行边界；不启动世界，不调用模型。
const History=preload("res://scripts/voice/prompt_history.gd")
const Candidate=preload("res://tools/test_luau_candidate.gd")
const Journal=preload("res://scripts/skills/execution_journal.gd")
func _initialize() -> void:
	create_timer(5).timeout.connect(func():quit(1))
	var source_id:="event_123456789_"+"skill_result_".repeat(8)
	var working:={"recent_turns":[],"task":{"request":{"id":source_id},"action_event_id":source_id,"progress":[]}}
	var instruction:="已有世界操作及结果是本人当前请求的实际进展，恢复后不能再次消费已经消耗的物资。".repeat(3)
	for index in 110:
		working.recent_turns.append({"event":{"id":source_id+str(index),"speaker":"body","source_event_id":source_id,"text":instruction},"own_reply":{"text":"","status":"保持沉默"}})
	for index in 4:
		working.task.progress.append({"person_id":"person_001","source_event_id":source_id,"skill_ref":"method@fixture","success":true,"runtime":{"status":"completed","phase_summary":[{"operation":"consume_contents","quantity":1}]},"world_facts":[{"kind":"consumed","material":"water","quantity":1,"source_event_id":source_id}],"message":"已实际消费"})
	var wire:=History.compact(working)
	assert(wire.task.progress[0].has("record_ref"),"夹具必须产生现场报错的记录引用格式")
	assert(wire.has("event_id_aliases") and wire.has("turn_layouts"),"同时覆盖请求ID别名和长历史列式布局")
	var before:=JSON.stringify(wire)
	var restored:=History.expand(wire)
	assert(restored==working,"字段、原始事件ID、说明、沉默、顺序及真实结果必须完整恢复")
	var progress:=Candidate.initial_request_progress({"working_context":wire},source_id)
	assert(progress==working.task.progress,"隔离入口必须读取原请求的完整执行进展")
	var context:=Journal.context("person_001",source_id,progress)
	assert(context.calls.size()==4 and context.calls[0].facts[0].quantity==1 and context.calls[0].source_event_id==source_id)
	assert(Candidate.initial_request_progress({"working_context":wire},"another_request").is_empty(),"不能把旧请求进展放进新请求")
	assert(Candidate.initial_request_progress({},source_id).is_empty(),"尚无进行中的任务时正常使用空进展")
	progress[0].world_facts[0].quantity=999
	assert(JSON.stringify(wire)==before,"解码与执行上下文修改不能回写编写请求或正式记忆")
	print("VERIFICATION_TASK_HISTORY_PASSED record_layout_original_ids_full_text_silent_rows_request_isolation_no_mutation; model_calls=0")
	quit()
