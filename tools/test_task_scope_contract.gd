extends SceneTree
## 同一个程序合同同时生成完整模型输入与校验；延迟网关不代表模型理解验收。
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
class Gateway extends Node:
	var calls: Array[Dictionary]=[]
	var scope:="existing_request"
	func exchange(request: Dictionary) -> Dictionary:
		calls.append(request.duplicate(true))
		var wire: Dictionary=JSON.parse_string(request.prompt.split("\n")[0])
		var choices: Array=wire.self.get("task_scope_options",[])
		# 旧输入没有明确范围时复现两次现场误选；修正后只能从给出的范围选择。
		var selected: String=scope if scope in choices or calls.size()>1 else "current_request"
		var offer: bool=wire.current_event.get("kind")=="item_offer"
		var state: String="execute" if offer else "none" if selected=="independent" else "completed"
		var decision:={"intent":"none","private_interpretation":"依据实际收物结果处理任务","public_reply":"","speech_style":"","speech_act":"statement","addressed_person":"","routing_reason":"使用本轮允许的任务范围","capability_gap":null,"task_status":"active" if offer else "none" if state=="none" else "completed","task_handling":{"state":state,"scope":selected,"reason":"实际结果已知"},"conversation":null}
		if wire.current_event.get("speaker") not in ["world","body"] and not offer:decision.conversation={"participation":"reply","addressees":["person_002"],"reason":"听见原话"}
		if offer:decision["offer_response"]="accept"
		await get_tree().process_frame
		return {"ok":true,"text":JSON.stringify(decision),"model":"fixture","elapsed_ms":1}

func _initialize() -> void:run.call_deferred()
func check(value: bool, message: String) -> bool:
	if value:return true
	push_error(message);quit(1);return false
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("task scope contract timeout");quit(1))
	var pipeline:=Pipeline.new();root.add_child(pipeline)
	var gateway:=Gateway.new();root.add_child(gateway);pipeline.gateway=gateway
	pipeline.store=preload("res://scripts/voice/people_store.gd").new();assert(pipeline.store.initialize().is_empty())
	var actor:="person_002";pipeline.store.people[actor].available_skills=[]
	var old:={"id":"accepted_basket_return","kind":"speech_intent","speaker":"player","text":"把同一个篮子还给小花","listeners":[actor]}
	var reports: Array[Dictionary]=[]
	pipeline.report_ready.connect(func(report: Dictionary):reports.append(report))
	var scenarios: Array[Dictionary]=[
		{"kind":"received_item","speaker":"world","task":true,"scope":"existing_request","options":["existing_request","independent"]},
		{"kind":"received_item","speaker":"world","task":false,"scope":"independent","options":["independent"]},
		{"kind":"need_changed","speaker":"body","task":true,"scope":"independent","options":["existing_request","independent"]},
		{"kind":"speech_intent","speaker":"player","task":false,"scope":"current_request","options":["current_request","independent"]},
		{"kind":"social_request","speaker":"person_001","task":true,"scope":"current_request","options":["current_request","existing_request","independent"]},
		{"kind":"item_offer","speaker":"person_001","task":true,"scope":"current_request","options":["current_request","existing_request","independent"]},
		{"kind":"skill_progress","speaker":"world","task":true,"scope":"current_request","options":["current_request","existing_request","independent"],"original":true}
	]
	for index in scenarios.size():
		var scenario: Dictionary=scenarios[index]
		pipeline.store.working_tasks.clear();pipeline.store.hear(actor,old)
		if scenario.task:pipeline.store.working_tasks[actor]={"request":old,"state":"wait","action_event_id":old.id}
		var event:={"id":"scope_case_"+str(index),"kind":scenario.kind,"speaker":scenario.speaker,"text":"实际物品交付结果或本次请求","listeners":[actor]}
		if scenario.get("original",false):event["original_event"]=old
		gateway.scope=scenario.scope;gateway.calls.clear();reports.clear()
		pipeline.run(event,{})
		await pipeline.completed
		var wire: Dictionary=JSON.parse_string(gateway.calls[0].prompt.split("\n")[0])
		if not check(wire.self.get("task_scope_options",[])==scenario.options,"完整模型输入没有给出本事件真实可接受的任务范围"):return
		if not check(gateway.calls.size()==1 and reports.size()==1 and not reports[0].has("decision_correction") and not reports[0].has("error"),"明确有效范围的决定仍额外调用校正模型"):return
		if not check(reports[0].decision.task_handling.scope==scenario.scope,"任务范围未按本轮合同保留"):return
		if scenario.speaker in ["world","body"] and not scenario.get("original",false):
			var wrong: Dictionary=reports[0].decision.duplicate(true);wrong.task_handling.scope="current_request"
			wire.self.task_scope_options=["current_request"]
			if not check(not pipeline._check_final(JSON.stringify(wrong),wire.self).ok,"输入描述不能放宽世界通知与人物请求的边界"):return
		if scenario.scope=="independent" and scenario.task:
			if not check(pipeline.store.working_tasks[actor].request.id==old.id and pipeline.store.working_tasks[actor].state=="wait","独立身体通知不能完成另一个请求"):return
	print("TASK_SCOPE_CONTRACT_PASSED full_wire_allowed_scopes_same_validation_single_call_request_followup_npc_offer_independent_no_task_overwrite; cloud_calls=0")
	quit()
