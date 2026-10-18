extends SceneTree
## 顺序替换不需中间模型，仍遵守旧控制排空、任务/取消/存档与当前权限。
const Cloud=preload("res://scripts/voice/cloud_client.gd")
const Pipeline=preload("res://scripts/voice/decision_pipeline.gd")
class Probe extends "res://scripts/voice/voice_test.gd":
	var logged: Array=[]
	func log_event(record: Dictionary) -> void:logged.append(record.duplicate(true))
	func _prepare_desktop_microphone() -> void:pass
	func _pump_speech() -> void:pass
	func _show_execution_result(_result: Dictionary) -> void:pass
class Skills extends Node:
	var active: Dictionary={}
	var learning: Dictionary={}
	var _generation:=0
	var calls: Array=[]
	var cancelled: Array=[]
	func cancel(id: String) -> void:cancelled.append(id) # 保留active，模拟世界协程尚未排空。
	func invoke(id: String, event: String, call: Dictionary) -> Dictionary:
		assert(not active.has(id),"不能越过旧世界协程启动新方法")
		calls.append({"person":id,"event":event,"call":call.duplicate(true)})
		return {"ok":true,"name":"夹具方法","ref":call.ref}
	func reset_context() -> void:_generation+=1;active.clear()
class Gateway extends Node:
	var calls:=0
	func exchange(_payload: Dictionary) -> Dictionary:
		calls+=1;await get_tree().process_frame
		var decision:=payload("current_request")
		decision.skill_call.ref="skill_1"
		return {"ok":true,"text":JSON.stringify(decision),"model":"fixture","elapsed_ms":1}
	static func payload(scope: String) -> Dictionary:
		return {"intent":"rest","skill_call":{"ref":"next@fixture","arguments":{}},"private_interpretation":"停止旧动作，再执行已明确选定的新方法","public_reply":"","speech_style":"","routing_reason":"途中换目标","speech_act":"statement","addressed_person":"","capability_gap":null,"task_status":"active","task_handling":{"state":"execute","scope":scope,"reason":"明确顺序替换"},"conversation":{"participation":"reply","addressees":["person_003"],"reason":"回应本次请求"}}
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(40).timeout.connect(func():push_error("skill replacement timeout");quit(1))
	var pipeline:=Pipeline.new();root.add_child(pipeline)
	pipeline.store=preload("res://scripts/voice/people_store.gd").new();assert(pipeline.store.initialize().is_empty())
	pipeline.store.people.person_003.available_skills=[{"id":"next","ref":"next@fixture","parameters":{},"callable":true}]
	pipeline.store.people.person_003.survival_observation={"action_catalog":preload("res://scripts/survival/action_catalog.gd").DESCRIPTIONS}
	var gateway:=Gateway.new();root.add_child(gateway);pipeline.gateway=gateway
	var reports: Array=[];pipeline.report_ready.connect(func(r):reports.append(r))
	pipeline.run({"id":"replace_contract","kind":"speech_intent","speaker":"player","text":"改去水源","listeners":["person_003"]},{})
	await pipeline.completed
	if gateway.calls!=1 or reports.size()!=1 or reports[0].has("error") or reports[0].has("decision_correction"):
		push_error("replacement contract: "+JSON.stringify({"calls":gateway.calls,"reports":reports.size(),"error":reports[0].get("error","") if not reports.is_empty() else "no report","correction":reports[0].get("decision_correction",{}).get("error","") if not reports.is_empty() else ""}))
		quit(1);return
	assert(gateway.calls==1 and reports.size()==1 and not reports[0].has("error") and not reports[0].has("decision_correction"),"完整模型合同必须一次接受明确停止后调用")
	var invalid:=Gateway.payload("current_request");invalid.learning_request={"goal_id":"another","goal":"再学一个方法"}
	assert(not Cloud.validate_decision(JSON.stringify(invalid),true,true).ok,"顺序替换不能混入学习")
	invalid=Gateway.payload("current_request");invalid.task_status="completed"
	assert(not Cloud.validate_decision(JSON.stringify(invalid),true,true).ok,"尚待执行的新方法不能提前完成")
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Probe.new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions:await physics_frame
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false;voice.config.actions_enabled=true
	voice._job_config=voice.config.duplicate(true);voice._allow_execution=true
	var controller: Node=voice.skills
	var skills:=Skills.new();voice.add_child(skills);voice.skills=skills
	var person:="person_003";var supplies:=JSON.stringify(voice.survival.life_world.supplies)
	for scenario in ["draining","already_ended","passive_listener","cancelled","replaced","new_control","disabled","checkpoint","reset"]:
		skills.calls.clear();skills.active.clear();voice.logged.clear();voice.autonomy.requests.clear()
		voice.config.actions_enabled=true;voice._allow_execution=true
		var event:={"id":"replace_"+scenario,"kind":"speech_intent","speaker":"player","text":"途中换目标","listeners":[person]}
		voice._round_events[event.id]=event;voice.store.hear(person,event)
		var decision:=Gateway.payload("current_request");voice.store.remember(person,event.id,decision)
		if scenario!="already_ended":skills.active[person]=true
		voice._on_report({"person_id":person,"event_id":event.id,"decision":decision})
		if scenario!="already_ended":
			assert(skills.calls.is_empty(),"取消发起不等于旧世界协程已经退出")
			await process_frame
			assert(skills.calls.is_empty(),"排空前不得提交新控制")
			match scenario:
				"passive_listener":
					var next:=Gateway.payload("independent");next.intent="none";next.skill_call=null;next.task_status="none";next.task_handling.state="none";next.conversation.participation="listen"
					voice.store.hear(person,{"id":event.id+"_listen","kind":"speech_intent","speaker":"player","text":"我正在和旁边的人说话","listeners":[person]})
					voice.store.remember(person,event.id+"_listen",next)
					voice._on_report({"person_id":person,"event_id":event.id+"_listen","decision":next})
				"cancelled":voice._input_generation+=1
				"replaced":voice.store.working_tasks[person].action_event_id="newer_request"
				"new_control":
					var next:=Gateway.payload("independent");next.skill_call=null;next.conversation=null
					voice._on_report({"person_id":person,"event_id":"new_control_stop","decision":next})
				"disabled":voice.config.actions_enabled=false
				"checkpoint":voice._input_generation+=1;voice._allow_execution=false # 正式_quiesce同一版本撤销入口。
				"reset":skills._generation+=1
			skills.active.clear()
			for frame in 3:await process_frame
		var should_start: bool=scenario in ["draining","already_ended","passive_listener"]
		assert(skills.calls.size()==(1 if should_start else 0),"停止后的调用未遵守任务/取消/权限/存档版本："+scenario)
		assert(voice.autonomy.requests.is_empty(),"明确顺序替换的中间停止不能再次排模型")
		if should_start:
			assert(skills.calls[0].event==event.id and voice.store.working_tasks[person].state=="action_submitted")
			assert(not voice.logged.any(func(e):return e.type=="action_result" and e.get("result",{}).get("intent")=="rest"),"不能伪造新方法完成前的停止成功续判")
	assert(JSON.stringify(voice.survival.life_world.supplies)==supplies,"安排替换不能改变物资")
	# 以下是无模型的真实Luau/世界协程验证，不把直接前提设置称为游玩。
	voice.skills=controller;voice._allow_execution=true;voice.logged.clear();voice.autonomy.requests.clear()
	assert(controller.initialize_current("user://skills/replacement_%d.json"%Time.get_ticks_usec()).is_empty())
	var sim: Node=voice.survival;var actor: Dictionary=sim.actors[person]
	actor.body.global_position=sim.STORAGE+Vector3(0,.06,-.8);actor.body.rotation.y=0
	for frame in 10:await physics_frame
	sim.perception.observe(person);assert(sim.life_world.take_unit(person,"storage").ok)
	var consume_ref:=""
	for item in controller.library.describe(person):
		if item.id=="bring_to_mouth":consume_ref=item.ref
	assert(not consume_ref.is_empty())
	var original:={"id":"replace_real_old","kind":"speech_intent","speaker":"player","text":"吃掉手中这份食物","listeners":[person]}
	voice._round_events[original.id]=original;voice.store.hear(person,original)
	var old:=Gateway.payload("current_request");old.intent="none";old.skill_call.ref=consume_ref
	voice.store.remember(person,original.id,old);voice._on_report({"person_id":person,"event_id":original.id,"decision":old})
	var until:=Time.get_ticks_msec()+10000
	while controller.active.has(person) and controller.active[person].runner._pending_operations==0 and Time.get_ticks_msec()<until:await process_frame
	assert(controller.active.has(person) and controller.active[person].runner._pending_operations>0,"必须在真实世界操作等待期间替换")
	var old_runner: Node=controller.active[person].runner;var drained:={"done":false}
	old_runner.finished.connect(func(result: Dictionary):
		assert(old_runner._pending_operations==0 and result.status=="cancelled","旧调用须取消且排空才算结束")
		drained.done=true)
	var replacement: Dictionary=original.duplicate(true);replacement.id="replace_real_new";replacement.text="先停下，再吃这同一份食物"
	voice._round_events[replacement.id]=replacement;voice.store.hear(person,replacement)
	var next:=Gateway.payload("current_request");next.skill_call.ref=consume_ref
	voice.store.remember(person,replacement.id,next);voice._on_report({"person_id":person,"event_id":replacement.id,"decision":next})
	assert(voice.autonomy.requests.is_empty(),"取消在途操作不能先排中间续判")
	while (controller.active.has(person) or voice._pending_skill_replacements.has(person)) and Time.get_ticks_msec()<until:await process_frame
	assert(drained.done and not controller.active.has(person),"真实后继必须等待旧调用排空并最终结束")
	var old_results: Array=voice.store.people[person].execution_results.filter(func(r):return r.source_event_id==original.id)
	var new_results: Array=voice.store.people[person].execution_results.filter(func(r):return r.source_event_id==replacement.id)
	assert(old_results.size()==1 and old_results[0].cancelled and new_results.size()==1 and new_results[0].success,"保留各一次真实取消及后继成功")
	var old_receipt:=-1;var new_submission:=-1
	for index in voice.logged.size():
		var record: Dictionary=voice.logged[index]
		if record.type=="action_result" and record.result.source_event_id==original.id:old_receipt=index
		if record.type=="skill_submitted" and record.event_id==replacement.id:
			assert(new_submission==-1,"后继不得重复提交");new_submission=index
	assert(old_receipt>=0 and new_submission>old_receipt,"新提交必须晚于真实旧回执")
	assert(not sim.gathering.hands.has(person) and sim.storage_food==2,"同一份食物仅消费一次，不能重复拿取/结算")
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="skill_progress" and voice.autonomy.requests[0].original_event.id==replacement.id,"仅后继真实完成排一次判断")
	# 明确停止并等待：真实在途操作取消后，不再判断一次已经选定的等待状态。
	voice.autonomy.requests.clear();voice.logged.clear()
	assert(sim.life_world.take_unit(person,"storage").ok)
	var waiting_old: Dictionary=original.duplicate(true);waiting_old.id="wait_real_old"
	voice._round_events[waiting_old.id]=waiting_old;voice.store.hear(person,waiting_old)
	voice.store.remember(person,waiting_old.id,old);voice._on_report({"person_id":person,"event_id":waiting_old.id,"decision":old})
	until=Time.get_ticks_msec()+10000
	while controller.active.has(person) and controller.active[person].runner._pending_operations==0 and Time.get_ticks_msec()<until:await process_frame
	assert(controller.active.has(person) and controller.active[person].runner._pending_operations>0)
	var stop:={"id":"wait_real_stop","kind":"speech_intent","speaker":"player","text":"先停下，等我叫你再继续","listeners":[person]}
	voice._round_events[stop.id]=stop;voice.store.hear(person,stop)
	var wait_stop:=Gateway.payload("existing_request");wait_stop.skill_call=null;wait_stop.task_handling.state="wait"
	var checked: Dictionary=Cloud.validate_decision(JSON.stringify(wait_stop),true,true)
	assert(checked.ok and Cloud.validate_task_handling(checked.decision).ok)
	voice.store.remember(person,stop.id,wait_stop);voice._on_report({"person_id":person,"event_id":stop.id,"decision":wait_stop})
	assert(voice.store.working_tasks[person].state=="wait" and voice.autonomy.requests.is_empty())
	while controller.active.has(person) and Time.get_ticks_msec()<until:await process_frame
	assert(not controller.active.has(person) and voice.store.working_tasks[person].state=="wait","迟到取消回执不得覆盖已选定的等待状态")
	assert(voice.autonomy.requests.is_empty() and sim.gathering.hands.has(person),"取消保留实际未吃掉的食物，不增加确认判断")
	var stop_results: Array=voice.store.people[person].execution_results.filter(func(r):return r.source_event_id==stop.id)
	assert(stop_results.size()==1 and stop_results[0].intent=="rest" and stop_results[0].success,"减少续判仍必须保存真实停止事实")
	assert(voice.logged.any(func(e):return e.type=="action_result" and e.result.source_event_id==stop.id),"停止事实仍向日志和反馈发布")
	var late_cancel: Array=voice.store.people[person].execution_results.filter(func(r):return r.source_event_id==waiting_old.id)
	assert(late_cancel.size()==1 and late_cancel[0].cancelled)
	# 玩家新出现的实际观察仍能唤醒等待；不因减少确认而冻结任务。
	var at: Vector3=actor.body.global_position
	voice.autonomy.watch_player(person,stop.id,{"visible_now":false},at)
	voice.autonomy.finish_player_watch({"person_id":person,"event_id":stop.id,"decision":wait_stop},voice.store.working_tasks[person])
	var visible_player:={person:{"person/player":{"visible_now":true,"position":[at.x,at.y,at.z+2]}}}
	assert(voice.autonomy.next_wait_event(1000,voice.store.working_tasks,sim.actors,visible_player).is_empty())
	var wake: Dictionary=voice.autonomy.next_wait_event(1000.6,voice.store.working_tasks,sim.actors,visible_player)
	assert(wake.get("source_event_id")==stop.id and wake.original_event.id==waiting_old.id,"等待仍沿原请求响应真实观察变化")
	print("SKILL_REPLACEMENT_PASSED single_model_full_contract_drained_once_idle_passive_listener_cancel_task_version_new_control_permissions_checkpoint_reset_no_intermediate_judgment; cloud_calls=0")
	scene.queue_free();pipeline.queue_free();gateway.queue_free();await create_timer(0.2).timeout;quit()
