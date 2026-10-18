extends SceneTree
const History=preload("res://scripts/voice/prompt_history.gd")
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")

func _initialize() -> void:
	create_timer(10).timeout.connect(func():push_error("result reference test timeout");quit(1))
	var feedback:={"source_event_id":"event_1792224126_518819199","cancelled":true,"success":false,"context_ref":"完整业务记录中的普通字段也要保留","message":"保留真实中断、本人目击、物品来源和每段运动回执。".repeat(15),"runtime":{"status":"cancelled","elapsed_ms":1250,"movements":[{"x":0.123456789,"y":null,"z":2.0}]}}
	var result:={"person_id":"person_002","source_event_id":"event_1792224126_518819199","success":false,"feedback":feedback.duplicate(true)}
	var progress:={"person_id":"person_002","source_event_id":"event_1792224126_518819199","message":"继续原任务","feedback":feedback.duplicate(true)}
	var working:={"recent_turns":[
		{"event":{"id":"execution","kind":"skill_execution","result":result.duplicate(true)},"own_understanding":"动作实际中断"},
		{"event":{"id":"progress","kind":"skill_progress","result":progress},"own_understanding":"等待后继续"},
	],"task":{"request":{"id":"request","text":"把原物交回来"},"progress":[result.duplicate(true)],"last_result":result.duplicate(true)}}
	var original:=var_to_bytes(working)
	var packed:=History.compact(working)
	var readable:=History.expand_layouts(packed)
	assert(readable.recent_turns[1].event.result.feedback=={"context_ref":"self.working_context.recent_turns.0.event.result.feedback"},"同次执行的相同反馈不能在两类事件里重复展开")
	assert(readable.task.progress[0]=={"context_ref":"self.working_context.recent_turns.0.event.result"})
	assert(readable.task.last_result==readable.task.progress[0],"任务进度和末次结果复用同一完整载荷")
	assert(var_to_bytes(History.expand(packed))==original,"保留全部事件身份、顺序、本人理解、取消、来源、精确数值及字段类型")
	assert(var_to_bytes(working)==original,"发送副本不能修改本人记忆或任务")
	assert(JSON.stringify(packed).length()<JSON.stringify(working).length())
	# execution/progress包装各自保留，宿主提供的相同移动历史与执行摘要只发一份。
	var movement:={"request_id":"event_1792226281_244555184","entries":[{"observation_id":"frame_before_cancel","standing_position":{"x":0.123456789,"y":null,"z":2.0},"cancelled":true}],"meaning":"保留该次实际移动、观察帧和中断事实。".repeat(12)}
	var summary:={"success":false,"elapsed_ms":1432,"phases":[{"code":"cancelled","count":1,"duration":1.0}],"meaning":"本段结果不证明原任务已经完成。".repeat(12)}
	var detailed:={"recent_turns":[
		{"event":{"id":"execution_detail","kind":"skill_execution","result":{"stage":"execution","movement_history":movement.duplicate(true),"execution_summary":summary.duplicate(true)}},"own_understanding":"实际移动后中断"},
		{"event":{"id":"progress_detail","kind":"skill_progress","result":{"stage":"progress","movement_history":movement.duplicate(true),"execution_summary":summary.duplicate(true)}},"own_understanding":"保留原要求，等候续办"},
	],"task":{"progress":[{"stage":"task_progress","feedback":{"movement_history":movement.duplicate(true),"execution_summary":summary.duplicate(true)}}]}}
	var detailed_source:=var_to_bytes(detailed)
	var detailed_packed:=History.compact(detailed)
	var detailed_readable:=History.expand_layouts(detailed_packed)
	assert(detailed_readable.recent_turns[1].event.result.movement_history=={"context_ref":"self.working_context.recent_turns.0.event.result.movement_history"},"同次执行的移动历史不能在不同事件包装中重复发送")
	assert(detailed_readable.recent_turns[1].event.result.execution_summary=={"context_ref":"self.working_context.recent_turns.0.event.result.execution_summary"},"相同执行摘要须复用首份完整记录")
	assert(detailed_readable.task.progress[0].feedback.movement_history==detailed_readable.recent_turns[1].event.result.movement_history,"嵌套反馈沿用同一份真实移动历史")
	assert(var_to_bytes(History.expand(detailed_packed))==detailed_source and var_to_bytes(detailed)==detailed_source,"运动/观察/取消、事件理解、数组数值类型及原件须完整保留")
	assert(JSON.stringify(detailed_packed).length()<JSON.stringify(detailed).length())
	detailed.recent_turns[1].event.result.movement_history.entries[0].standing_position.x=0.123456788
	detailed.recent_turns[1].event.result.execution_summary.phases[0].duration=1
	var distinct_source:=var_to_bytes(detailed)
	var distinct:=History.compact(detailed)
	var distinct_readable:=History.expand_layouts(distinct)
	assert(not distinct_readable.recent_turns[1].event.result.movement_history.has("context_ref") and not distinct_readable.recent_turns[1].event.result.execution_summary.has("context_ref"),"微小坐标差异和int/float差异不能复用")
	assert(var_to_bytes(History.expand(distinct))==distinct_source)
	var detailed_history:={"recent_turns":[]}
	for index in 130:
		var turn: Dictionary=detailed.recent_turns[index%2].duplicate(true)
		turn.event.id=str(index)
		turn.event.result["batch_index"]=index
		detailed_history.recent_turns.append(turn)
	var detailed_table:=History.compact(detailed_history)
	assert(detailed_table.has("turn_layouts") and var_to_bytes(History.expand(detailed_table))==var_to_bytes(detailed_history),"长历史行布局中的子载荷引用也须保留完整事件和类型")
	var variants:={"recent_turns":[],"task":{"progress":[],"last_result":{"ok":true}}}
	for value in [1,1.0,null,"1"]:
		variants.task.progress.append({"value":value,"message":"相同说明必须保留不同结果".repeat(15)})
	variants.task.progress.append({"message":"相同说明必须保留不同结果".repeat(15)})
	variants.task.progress.append({"ok":true})
	variants.task.progress.append({"context_ref":null})
	variants.task.progress.append({"context_ref":42})
	var variants_before:=var_to_bytes(variants)
	var typed:=History.compact(variants)
	assert(var_to_bytes(History.expand(typed))==variants_before,"数字类型、null、缺字段不能相互替代")
	assert(History.expand_layouts(typed).task.progress[-3]=={"ok":true},"引用更大时保留短结果")
	var long_history:={"recent_turns":[],"task":{}}
	for index in 130:
		long_history.recent_turns.append({"event":{"id":str(index),"kind":"skill_progress","result":result.duplicate(true)},"own_understanding":"第%d次判断"%index})
	var table:=History.compact(long_history)
	assert(table.has("turn_layouts") and var_to_bytes(History.expand(table))==var_to_bytes(long_history),"先展开列布局再解析结果引用，不能丢失数组下标关联")
	var context:={"id":"person_002","name":"小花","available_skills":[],"working_context":detailed}
	var source:=var_to_bytes(context)
	var packet:=Pipeline.request_for(context,{"id":"new_order","kind":"speech_intent","speaker":"player","text":"继续吧"})
	var wire: Dictionary=JSON.parse_string(packet.prompt)
	assert(History.expand(wire.self.working_context)==JSON.parse_string(JSON.stringify(detailed)),"完整发送输入须可恢复为同一次JSON传输的全部事实")
	assert(packet.prefix.contains("context_ref") and var_to_bytes(context)==source)
	print("PROMPT_RESULT_REFERENCE_PASSED shared_feedback_movement_summary_task_results_typed_lossless_size_guard_table_wire")
	quit()
