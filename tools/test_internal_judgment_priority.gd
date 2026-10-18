extends SceneTree
## 真实输入队列/决策管线，延迟网关仅替代网络；不调用模型或改正式存档。
class Probe extends "res://scripts/voice/voice_test.gd":
	func _prepare_desktop_microphone() -> void:pass
	func _pump_speech() -> void:pass
class DelayedGateway extends Node:
	var control_leaked:=false
	func exchange(_payload: Dictionary) -> Dictionary:
		control_leaked=control_leaked or JSON.stringify(_payload).contains("task_bound")
		await get_tree().create_timer(.12).timeout
		return {"ok":false,"error":"isolated delayed judgment"}
var voice: Node
var reports: Array=[]
var serial:=0
func _initialize() -> void:run.call_deferred()
func check(value: bool, message: String) -> bool:
	if value:return true
	push_error(message);quit(1);return false
func begin(event: Dictionary) -> void:
	voice.busy=true;voice._decisions_done=false;voice._allow_execution=true
	voice._job_config=voice.config.duplicate(true);voice._start_pipeline(event,voice._job_config)
func interrupt_with_input(event: Dictionary) -> bool:
	begin(event)
	serial+=1
	voice._queue_capture({"text_event":{"id":"player_%d"%serial,"speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"请先回答我的新问题"},"config":voice.config.duplicate(true)})
	return check(not voice.busy and not voice.pipeline.busy and voice._deferred_judgments.size()==1,event.kind+"内部判断仍挡住玩家输入")
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("internal judgment test timeout");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	voice=Probe.new();scene.add_child(voice);voice.set_process(false)
	voice.config.local_only=false;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	var fake:=DelayedGateway.new();voice.add_child(fake);voice.pipeline.gateway=fake
	voice.pipeline.report_ready.connect(func(report: Dictionary):reports.append(report))
	for kind in ["need_changed","assistance_completed","received_item","received_water","received_food"]:
		for task_case in ["absent","completed","replaced"]:
			voice.store.working_tasks.erase("person_003")
			if task_case!="absent":voice.store.working_tasks.person_003={"request":{"id":"earlier_task","speaker":"player"},"action_event_id":"earlier_action","state":task_case if task_case=="completed" else "awaiting_judgement","progress":[]}
			var event:={"id":"independent_%s_%s"%[kind,task_case],"speaker":"body" if kind=="need_changed" else "world","kind":kind,"listeners":["person_003"],"text":"本人已有的真实需求或受益事实"}
			var before: int=reports.size()
			if not interrupt_with_input(event):return
			if not check(voice.store.event_for("person_003",event.id).text==event.text,"延期不能丢已听见事实"):return
			voice._process(0);await create_timer(.16).timeout
			if not check(reports.size()==before+1 and reports[-1].event_id.begins_with("player_"),"新输入必须先处理，取消轮次不得发布"):return
			if task_case=="replaced":voice.store.working_tasks.person_003={"request":{"id":"new_request","speaker":"player"},"action_event_id":"new_action","state":"completed","progress":[]}
			if not check(voice._resume_deferred_judgment(),"独立通知不能因无任务、任务终态或替换被吞掉"):return
			await create_timer(.16).timeout
			if not check(reports.size()==before+2 and reports[-1].event_id==event.id and voice._deferred_judgments.is_empty(),"独立通知须恢复一次"):return
		print("INTERNAL_INDEPENDENT_CASE ",kind," absent_completed_replaced=passed")
	for kind in ["skill_ready","skill_revised","session_restored","session_checkpoint","information_unanswered"]:
		var original:={"id":"bound_"+kind,"speaker":"player","kind":"speech_intent","text":"原明确请求"}
		voice.store.working_tasks.person_003={"request":original,"action_event_id":"old_action","state":"awaiting_judgement","progress":[]}
		var event:={"id":"notify_"+kind,"speaker":"world","kind":kind,"listeners":["person_003"],"original_event":original,"text":"原任务的进展"}
		if not interrupt_with_input(event):return
		voice._pending_inputs.clear();voice.store.working_tasks.person_003.action_event_id="replacement_action"
		if not check(not voice._resume_deferred_judgment() and voice._deferred_judgments.is_empty(),"原任务通知必须拒绝旧动作版本"):return
	# 由实际询问等待接口产生、没有已接受任务的玩家触发通知，也是独立待办。
	voice.store.working_tasks.erase("person_003")
	var question:={"id":"independent_question","speaker":"player","kind":"speech_intent","text":"另一个问题"}
	voice.information_waits.begin("person_003","person_001",question,"你知道吗",0)
	var unanswered: Dictionary=voice.information_waits.next_event(100,voice.survival.actors)
	if not check(not unanswered.is_empty(),"须由真实超时接口产生通知"):return
	if not interrupt_with_input(unanswered):return
	voice._pending_inputs.clear();voice.store.working_tasks.person_003={"request":{"id":"later_order","speaker":"player"},"action_event_id":"later_action","state":"completed","progress":[]}
	if not check(voice._resume_deferred_judgment(),"没有已接受任务的询问超时不能错绑后来任务"):return
	await create_timer(.16).timeout
	# 有另一个活动任务时，实际公开询问也遵守人物声明的独立／原任务归属。
	var active_order:={"id":"active_question_order","speaker":"player","kind":"speech_intent","text":"正在办的另一要求"}
	voice.store.hear("person_003",active_order)
	voice.store.working_tasks.person_003={"request":active_order,"action_event_id":"active_question_action","state":"awaiting_judgement","progress":[]}
	var source:={"id":"body_question_source","speaker":"body","kind":"need_changed","listeners":["person_003"],"original_event":active_order,"text":"独立身体判断来源"}
	voice.store.hear("person_003",source);voice.config.autonomy_enabled=true
	for scope in ["independent","existing_request"]:
		voice._deliver_public("person_003",source.id,"隔离询问：你了解当前状况吗",8,{"speech_act":"request","request_kind":"information","addressed_person":"person_001","task_handling":{"scope":scope}})
		if not check(voice.information_waits.pending.has(source.id+"_request_person_001"),"公开询问须经实际入口建立等待"):return
		var pending: Dictionary=voice.information_waits.pending[source.id+"_request_person_001"]
		if not check(pending.original_event.id==(source.id if scope=="independent" else active_order.id),"公开询问必须保留声明的归属"):return
		if not check(voice.store.event_for("person_003",source.id).original_event.id==active_order.id,"询问上下文不能改写已记住的来源"):return
	voice.config.autonomy_enabled=false;voice.autonomy.requests.clear()
	# 已发表/排语音、多听众及真实人物话语继续正常收尾。
	for blocked in ["report","speech","multiple","person"]:
		var event:={"id":"guard_"+blocked,"speaker":"person_001" if blocked=="person" else "world","kind":"social_reply" if blocked=="person" else "assistance_completed","listeners":["person_003","person_002"] if blocked=="multiple" else ["person_003"],"text":"不可撤销的轮次"}
		begin(event)
		if blocked=="report":voice._reports_received.person_003={}
		if blocked=="speech":voice._speech_queue.append({})
		voice._queue_capture({"text_event":{"id":"guard_input","speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"新输入"},"config":voice.config.duplicate(true)})
		if not check(voice.busy and voice.pipeline.busy and voice._deferred_judgments.is_empty(),"已提交/公开/多听众/人物话语不能被延期撤销"):return
		voice._speech_queue.clear();voice.cancel_interaction()
	# NPC接物请求先排队时，玩家输入仍可让未发布的内部判断延期。
	# 只布置接物判断入口，不伪造实际物品转移；三项通知都须原样处理一次。
	var mixed_internal:={"id":"mixed_internal","speaker":"body","kind":"need_changed","listeners":["person_003"],"text":"已有的身体需求"}
	var mixed_offer:={"id":"mixed_npc_offer","speaker":"person_001","kind":"item_offer","listeners":["person_003"],"text":"同伴递来物品"}
	var mixed_player:={"id":"mixed_player","speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"先处理玩家新要求"}
	var mixed_before: int=reports.size()
	var mixed_world_enabled: bool=voice.survival.enabled
	voice.survival.enabled=false # 本段只验证接物判断队列，不模拟物品或物理交付。
	voice.survival.gathering.offers[mixed_offer.id]={"target":"person_003","expires":Time.get_ticks_msec()+10000,"decision_started":false}
	begin(mixed_internal)
	voice._queue_offer(mixed_offer)
	if not check(voice.busy and voice.pipeline.busy,"NPC接物不应自行撤销正在处理的内部判断"):return
	voice._queue_capture({"text_event":mixed_player,"config":voice.config.duplicate(true)})
	if not check(not voice.busy and not voice.pipeline.busy and voice._deferred_judgments.size()==1,"队首NPC接物挡住了后方玩家输入的延期处理"):return
	voice._process(0);await create_timer(.16).timeout
	if not check(reports.size()==mixed_before+1 and reports[-1].event_id==mixed_player.id,"玩家必须先于尚未派发的NPC接物处理"):return
	if not check(voice._pending_inputs.size()==1 and voice._pending_inputs[0].payload==mixed_offer,"延期NPC接物必须保留原始事件"):return
	if not check(not voice.pipeline.busy and voice._decisions_done,"须先完成玩家决策轮次"):return
	voice._finish_turn() # Probe禁用了语音泵；调用它原本会触发的真实文字轮收尾。
	voice._process(0);await create_timer(.16).timeout
	if not check(reports.size()==mixed_before+2 and reports[-1].event_id==mixed_offer.id and voice._pending_inputs.is_empty(),"NPC接物随后须恰好处理一次"):return
	if not check(voice._resume_deferred_judgment(),"原内部判断仍须恢复"):return
	await create_timer(.16).timeout
	if not check(reports.size()==mixed_before+3 and reports[-1].event_id==mixed_internal.id and voice._deferred_judgments.is_empty(),"原内部事实恢复不能丢失或重复"):return
	voice.survival.gathering.offers.erase(mixed_offer.id)
	voice.survival.enabled=mixed_world_enabled
	await create_timer(.2).timeout
	if not check(not fake.control_leaked,"完整模型请求不能混入延期控制包装"):return
	print("INTERNAL_JUDGMENT_PRIORITY_PASSED independent_facts_task_versions_real_question_timeout_fifo_commit_guards_late_reports; cloud_calls=0")
	assert((await voice.mic.stop_for_shutdown()).is_empty())
	scene.queue_free();await process_frame;quit()
