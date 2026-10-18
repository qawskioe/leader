extends SceneTree
## 使用正式队列、管线及存档入口；网关仅返回延迟夹具，不调用真实模型。
class Probe extends "res://scripts/voice/voice_test.gd":
	func _prepare_desktop_microphone() -> void:pass
	func _pump_speech() -> void:pass
class Gateway extends Node:
	var fail:=false
	var scope:="independent"
	var packets: Array[Dictionary]=[]
	func exchange(packet: Dictionary) -> Dictionary:
		packets.append(packet.duplicate(true))
		var failed:=fail
		await get_tree().create_timer(.12).timeout
		if failed:return {"ok":false,"error":"isolated notification failure"}
		return {"ok":true,"text":JSON.stringify({"intent":"none","private_interpretation":"同时考虑本人身体通知及已发生任务结果","public_reply":"","speech_style":"","routing_reason":"保持原任务并等待","speech_act":"statement","addressed_person":"","capability_gap":null,"task_status":"none" if scope=="independent" else "active","task_handling":{"state":"none" if scope=="independent" else "wait","scope":scope,"reason":"本轮等待或保持任务"},"conversation":{"addressees":[],"participation":"listen","reason":"没有公开台词"}})}
var voice: Node
var gateway: Gateway
var reports: Array[Dictionary]=[]
var serial:=0
const PERSON="person_003"
func _initialize() -> void:run.call_deferred()
func check(value: bool, message: String) -> bool:
	if value:return true
	push_error(message);quit(1);return false
func stage(kind: String="skill_progress", body_queue: String="deferred") -> Dictionary:
	voice.pipeline.cancel();voice.busy=false;voice._reports_received.clear()
	voice._deferred_judgments.clear();voice.autonomy.requests.clear();voice._pending_inputs.clear()
	serial+=1
	var order:={"id":"combined_order_%d"%serial,"speaker":"player","kind":"speech_intent","text":"继续先前明确请求"}
	var body:={"id":"combined_body_%d"%serial,"speaker":"body","kind":"need_changed","listeners":[PERSON],"text":"本人新近身体需求通知","trigger":{"thirst":82}}
	var task:={"id":"combined_task_%d"%serial,"speaker":"world","kind":kind,"listeners":[PERSON],"original_event":order.duplicate(true),"source_event_id":"combined_action_%d"%serial if kind=="skill_progress" else order.id,"text":"已发生的任务结果或恢复通知"}
	voice.store.hear(PERSON,order);voice.store.hear(PERSON,body);voice.store.hear(PERSON,task)
	voice.store.working_tasks[PERSON]={"request":order,"action_event_id":"combined_action_%d"%serial,"state":"awaiting_judgement" if kind=="skill_progress" else "interrupted_save","progress":[]}
	if body_queue=="deferred":voice._deferred_judgments.append(voice._deferred_judgment(body))
	else:voice.autonomy.requests.append(body.duplicate(true))
	voice.autonomy.requests.append(task.duplicate(true))
	return {"body":body,"task":task}
func body_count(body: Dictionary) -> int:
	return voice._deferred_judgments.filter(func(d):return d.event.id==body.id).size()+voice.autonomy.requests.filter(func(e):return e.id==body.id).size()
func wire(index: int=-1) -> String:
	var packet: Dictionary=gateway.packets[index]
	return packet.prefix+packet.reference+packet.prompt
func settle() -> void:
	await create_timer(.18).timeout
	if not voice.pipeline.busy:voice._finish_turn()
func finish(scene: Node) -> void:
	assert((await voice.mic.stop_for_shutdown()).is_empty())
	scene.queue_free();await process_frame;quit()
func run() -> void:
	create_timer(40).timeout.connect(func():push_error("body/task notification timeout");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	voice=Probe.new();scene.add_child(voice);voice.set_process(false)
	voice.config.local_only=false;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	gateway=Gateway.new();voice.add_child(gateway);voice.pipeline.gateway=gateway
	voice.pipeline.report_ready.connect(func(report: Dictionary):reports.append(report))
	if "--combined-write" in OS.get_cmdline_user_args() or "--combined-read" in OS.get_cmdline_user_args():
		voice.session_manager.path="user://sessions/acceptance_combined_notifications.json"
		if "--combined-write" in OS.get_cmdline_user_args():
			var saved_pair:=stage()
			if not check(voice._resume_deferred_judgment(),"写档前合并判断须在途"):return
			if not check((await voice.session_manager.save_game()).is_empty() and body_count(saved_pair.body)==1,"合并在途存档须保留身体一次"):return
			print("BODY_TASK_WRITE_PASSED inflight_combined_original_body_saved_once; cloud_calls=0")
		else:
			if not check(voice.autonomy.requests.is_empty() and voice.skills.active.is_empty(),"读取必须始于新进程默认场景"):return
			if not check((await voice.session_manager.load_game()).is_empty(),"新进程读取合并检查点失败"):return
			var bodies: Array=voice.autonomy.requests.filter(func(e):return e.kind=="need_changed")
			if not check(bodies.size()==1 and voice._round_events.is_empty(),"新进程只保留原身体一次，不能依靠旧轮状态"):return
			# 首次恢复判断前按取消，尚未确认的身体事实仍可恢复。
			voice._speech_order=[PERSON] # 让取消入口实际清理该角色的原待办。
			voice.cancel_interaction()
			if not check(body_count(bodies[0])==1 and voice._resume_deferred_judgment(),"读档后取消不能吞掉原身体通知"):return
			await settle()
			if not check(body_count(bodies[0])==0 and reports[-1].has("decision"),"读档后原身体须有效处理一次"):return
			print("BODY_TASK_READ_PASSED fresh_process_cancel_keeps_original_body_consumed_once; cloud_calls=0")
		await finish(scene);return
	for kind in ["skill_progress","session_restored","session_checkpoint"]:
		for body_queue in ["deferred","requests"]:
			gateway.scope="current_request" if body_queue=="deferred" else "existing_request"
			var pair:=stage(kind,body_queue)
			var calls:=gateway.packets.size()
			if not check(voice._resume_deferred_judgment(),"必须派发已有通知"):return
			if not check(voice.pipeline._event.id==pair.task.id and voice.pipeline._event.has("body_notification"),"身体与已有任务结果仍分别派发"):return
			if not check(body_count(pair.body)==1,"有效决定前必须保留原身体通知"):return
			await settle()
			if not check(reports[-1].has("decision") and gateway.packets.size()==calls+1,"合并必须只产生一次有效决策调用"):return
			if not check(wire().contains(pair.body.id) and wire().contains(pair.task.id) and wire().contains('"body_notification"'),"完整发送输入必须显式含两份通知，不能被已听见事件去重丢掉"):return
			if not check(not voice.store.event_for(PERSON,pair.task.id).has("body_notification") and voice.store.event_for(PERSON,pair.body.id).text==pair.body.text,"合并不得改写已听见的原始任务或身体事件"):return
			if not check(body_count(pair.body)==0 and not voice._resume_deferred_judgment(),"有效决定后不得再单独消费同一身体通知"):return
	# 网络失败仍保留原通知；之后可正常单独判断一次。
	gateway.scope="independent"
	var pair:=stage();gateway.fail=true
	if not check(voice._resume_deferred_judgment(),"错误场景须派发"):return
	await settle();gateway.fail=false
	if not check(reports[-1].has("error") and body_count(pair.body)==1,"失败不能确认身体通知已处理"):return
	if not check(voice._resume_deferred_judgment() and voice.pipeline._event.id==pair.body.id,"失败后须恢复原身体事实"):return
	await settle()
	if not check(body_count(pair.body)==0,"单独恢复后不能重复排队"):return
	pair=stage();gateway.fail=true
	if not check(voice._resume_deferred_judgment(),"失败后取消场景须派发"):return
	await settle();gateway.fail=false;voice.cancel_interaction()
	if not check(body_count(pair.body)==1 and voice._resume_deferred_judgment(),"合并失败后取消不能丢原身体通知"):return
	await settle()
	# 旧版本、终态、他人、独立行动及过期恢复事件不能占用身体通知。
	for invalid in ["action","request","terminal","cancelled","independent","person","checkpoint_version"]:
		pair=stage("session_checkpoint" if invalid=="checkpoint_version" else "skill_progress")
		var queued: Dictionary=voice.autonomy.requests[-1]
		if invalid=="action":queued.source_event_id="older_action"
		if invalid=="request":queued.original_event.id="older_request"
		if invalid=="terminal":voice.store.working_tasks[PERSON].state="completed"
		if invalid=="cancelled":voice._cancelled_player_tasks[PERSON+"/"+pair.task.original_event.id]=true
		if invalid=="independent":voice.store.independent_actions[PERSON+"/"+pair.task.source_event_id]=true
		if invalid=="person":queued.listeners=["person_002"]
		if invalid=="checkpoint_version":voice.store.working_tasks[PERSON].state="action_submitted"
		if not check(voice._resume_deferred_judgment() and voice.pipeline._event.id==pair.body.id and not voice.pipeline._event.has("body_notification"),"失效任务不能合并："+invalid):return
		await settle()
	# 玩家输入抢占后，旧模型返回不得消费身体；任务被替换则仅恢复身体。
	pair=stage()
	if not check(voice._resume_deferred_judgment(),"抢占场景须派发"):return
	var before:=reports.size()
	voice._queue_capture({"text_event":{"id":"preempt_combined","speaker":"player","kind":"speech_intent","listeners":[PERSON],"text":"先处理新问题"},"config":voice.config.duplicate(true)})
	voice._pending_inputs.clear();voice.store.working_tasks[PERSON].action_event_id="replacement_action"
	await create_timer(.18).timeout
	if not check(reports.size()==before and body_count(pair.body)==1,"取消的迟到报告不能消费原通知"):return
	if not check(voice._resume_deferred_judgment() and voice.pipeline._event.id==pair.body.id,"旧任务废弃后独立身体仍须恢复"):return
	await settle()
	# Backspace取消的是交互，合并中尚未确认的身体事实仍保留一次。
	pair=stage("skill_progress","requests")
	if not check(voice._resume_deferred_judgment(),"取消场景须派发"):return
	before=reports.size();voice.cancel_interaction();await create_timer(.18).timeout
	if not check(reports.size()==before and body_count(pair.body)==1,"显式取消不能丢失或重复合并中的身体通知"):return
	if not check(voice._resume_deferred_judgment() and voice.pipeline._event.id==pair.body.id,"取消后恢复原身体通知"):return
	await settle()
	# 真实文件写入失败也不消费通知，随后取消仍须保留。
	pair=stage()
	voice.session_manager.path="user://sessions/combined_failed_%d.json"%Time.get_ticks_usec()
	if not check(DirAccess.make_dir_recursive_absolute(voice.session_manager.path+".tmp")==OK,"须建立临时文件冲突夹具"):return
	if not check(voice._resume_deferred_judgment(),"失败存档场景须派发"):return
	if not check(not (await voice.session_manager.save_game()).is_empty() and body_count(pair.body)==1,"保存失败不能消费身体通知"):return
	voice.cancel_interaction()
	if not check(body_count(pair.body)==1,"保存失败后取消仍须保留身体"):return
	if not check(DirAccess.remove_absolute(voice.session_manager.path+".tmp")==OK,"须清理本次空夹具目录"):return
	# 在合并请求尚未返回时正常保存；读回新检查点，仍只提供一次身体通知。
	pair=stage()
	voice.session_manager.path="user://sessions/combined_notifications_%d.json"%Time.get_ticks_usec()
	if not check(voice._resume_deferred_judgment(),"存档场景须派发"):return
	if not check((await voice.session_manager.save_game()).is_empty(),"合并中保存失败"):return
	if not check(body_count(pair.body)==1,"保存后原身体通知恰好一份"):return
	if not check((await voice.session_manager.load_game()).is_empty(),"合并检查点读档失败"):return
	if not check(body_count(pair.body)==1 and voice.autonomy.requests.filter(func(e):return e.kind=="session_restored").size()==1,"恢复必须重建任务通知并保留原身体一次"):return
	if not check(voice._resume_deferred_judgment() and voice.pipeline._event.has("body_notification"),"恢复后须重新合并当前任务与原身体事实"):return
	await settle()
	if not check(body_count(pair.body)==0 and not voice._resume_deferred_judgment(),"恢复后的有效决定只消费一次"):return
	for packet in gateway.packets:
		if not check(not (packet.prefix+packet.reference+packet.prompt).contains('"task_bound"'),"调度包装不得进入模型输入"):return
	print("BODY_TASK_NOTIFICATIONS_PASSED three_kinds_two_queues_three_scopes_one_call_explicit_input_error_version_preempt_cancel_save_failure_restore; cloud_calls=0")
	await finish(scene)
