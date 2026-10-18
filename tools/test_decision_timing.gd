extends SceneTree
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
class Gateway extends Node:
	var mode:="normal"
	var order:=0
	var packets: Array=[]
	func exchange(packet: Dictionary) -> Dictionary:
		order+=1
		var current:=order
		packets.append(packet.duplicate(true))
		if mode=="immediate_failure":return {"ok":false,"error":"fixture unavailable"}
		# 启动首帧delta可大于80ms，单个SceneTreeTimer会在同帧到期；按真实时钟延迟。
		var ready_at:=Time.get_ticks_msec()+80
		while Time.get_ticks_msec()<ready_at:await get_tree().create_timer(.01).timeout
		if mode=="recall" and current==1:return {"ok":true,"model":"fixture","text":JSON.stringify({"recall":{"kind":"heard","keywords":["计时夹具"],"limit":1}}),"elapsed_ms":7}
		return {"ok":true,"model":"fixture","text":JSON.stringify({"intent":"none","private_interpretation":"只验证计时边界","public_reply":"","speech_style":"","speech_act":"statement","addressed_person":"","routing_reason":"不提交行动","capability_gap":null,"task_status":"none","task_handling":{"state":"none","scope":"independent","reason":"保持旁听"},"conversation":{"participation":"listen","addressees":[],"reason":"已听见"}}),"elapsed_ms":7}

func _initialize() -> void:run.call_deferred()
func verify(report: Dictionary) -> void:
	var timing: Dictionary=report.timing
	assert(timing.queued_msec<=timing.started_msec and timing.started_msec<=timing.finished_msec)
	assert(timing.queue_wait_ms==timing.started_msec-timing.queued_msec and timing.active_ms==timing.finished_msec-timing.started_msec)
	var last: int=timing.started_msec
	for call in report.calls:
		assert(call.has("attempts") and call.attempts==null,"未提供上游尝试的旧网关必须保持未知，不伪造空列表或零消耗")
		assert(call.client_timing.started_msec>=last and call.client_timing.finished_msec>=call.client_timing.started_msec)
		last=call.client_timing.finished_msec
	assert(last<=timing.finished_msec)

func run() -> void:
	create_timer(12).timeout.connect(func():push_error("decision timing timeout");quit(1))
	var pipeline:=Pipeline.new();root.add_child(pipeline)
	var gateway:=Gateway.new();root.add_child(gateway);pipeline.gateway=gateway
	pipeline.store=preload("res://scripts/voice/people_store.gd").new();assert(pipeline.store.initialize().is_empty())
	var reports: Array=[];pipeline.report_ready.connect(func(report: Dictionary):reports.append(report))
	var observation_starts: Dictionary={}
	pipeline.decision_started.connect(func(id: String, event_id: String):observation_starts[id]={"event_id":event_id,"at":Time.get_ticks_msec()})
	var event:={"id":"timing_parallel","speaker":"player","kind":"speech_intent","text":"大家先听着","listeners":["person_001","person_002","person_003"]}
	pipeline.run(event,{})
	assert(observation_starts.size()==2 and not observation_starts.has("person_003"),"排队听众不能提前冻结等待观察")
	await pipeline.completed
	assert(reports.size()==3)
	for report in reports:
		assert(not report.has("error"));verify(report)
	print("DECISION_TIMING_SAMPLE ",JSON.stringify(reports.map(func(report):return {"person":report.person_id,"timing":report.timing,"client":report.calls[0].client_timing})))
	assert(reports[2].timing.started_msec>=mini(reports[0].timing.finished_msec,reports[1].timing.finished_msec),"第三人必须在一个实际并发位置释放后开始")
	assert(reports[2].timing.queue_wait_ms>=70,"真实延迟网关的排队必须可见，不能沿用全听众同时开始的旧时间")
	assert(observation_starts.person_003.event_id==event.id and observation_starts.person_003.at>=mini(reports[0].timing.finished_msec,reports[1].timing.finished_msec),"等待观察必须在本人实际取现场时冻结")
	for mode in ["recall","immediate_failure"]:
		reports.clear();gateway.mode=mode;gateway.order=0
		event.id="timing_"+mode;event.listeners=["person_003"]
		pipeline.run(event,{})
		# 立即失败可同步完成；不能在信号已经发出后才等待它。
		if pipeline.busy:await pipeline.completed
		assert(reports.size()==1);verify(reports[0])
		assert(reports[0].calls.size()==(2 if mode=="recall" else 1))
		assert(reports[0].has("error")== (mode=="immediate_failure"))
	# 旧网关仍在返回时开始新轮，旧时钟与报告不能串入新轮。
	reports.clear();gateway.mode="normal";event.id="timing_cancelled"
	pipeline.run(event,{})
	await create_timer(.02).timeout
	pipeline.cancel()
	var new_start:=Time.get_ticks_msec();event.id="timing_after_cancel"
	pipeline.run(event,{});await pipeline.completed
	await create_timer(.1).timeout
	assert(reports.size()==1 and reports[0].event_id==event.id and reports[0].timing.queued_msec>=new_start)
	verify(reports[0])
	for packet in gateway.packets:
		var wire: String=packet.prefix+packet.reference+packet.prompt
		assert(not wire.contains("queue_wait_ms") and not wire.contains("client_timing") and not wire.contains("monotonic_ms"),"计时不进入模型输入")
	assert(not JSON.stringify(pipeline.store.working_tasks).contains("queued_msec"),"诊断时钟不写任务存档")
	pipeline.queue_free();gateway.queue_free();await process_frame
	print("DECISION_TIMING_PASSED two_active_three_listeners_queue_recall_immediate_failure_cancel_new_generation_no_model_or_task_metadata; cloud_calls=0")
	quit()
