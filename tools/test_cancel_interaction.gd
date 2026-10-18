extends SceneTree
class DelayedGateway extends Node:
	var calls:=0
	func exchange(_payload: Dictionary) -> Dictionary:
		calls+=1
		var number:=calls
		await get_tree().create_timer(0.25 if number==1 else 0.05).timeout
		return {"ok":false,"error":"fixture_%d"%number}
var reports: Array=[]
class PendingSkills extends Node:
	var active: Dictionary={"person_001":true}
	var learning: Dictionary={"person_002":true}
	var cancelled: Array=[]
	func cancel(id: String) -> void:
		cancelled.append(id)
		active.erase(id);learning.erase(id)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(20).timeout.connect(func():push_error("cancel interaction timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	var fake:=DelayedGateway.new();voice.add_child(fake);voice.pipeline.gateway=fake
	voice.pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	voice.busy=true;voice._job_config=voice.config.duplicate(true)
	voice._start_pipeline({"id":"old","speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"错误的一句"},voice._job_config)
	voice._queue_capture({"event_id":"queued_fixture"})
	voice.cancel_interaction()
	assert(not voice.busy and not voice.pipeline.busy and voice._pending_inputs.is_empty())
	voice.busy=true
	voice._start_pipeline({"id":"new","speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"正确的新一句"},voice._job_config)
	assert(voice.captions.person_003.hearing_text=="已听见 · 正在理解")
	assert(voice.captions.person_002.hearing_text=="这句话未传给她")
	await create_timer(0.4).timeout
	assert(reports.size()==1 and reports[0].event_id=="new","旧模型结果不能串入新请求")
	assert(voice.captions.person_003.hearing_text=="已听见 · 决策处理失败","模型错误不抹掉已经听见")
	assert(voice.pipeline._active==0 and not voice.pipeline.busy)
	# 新输入让尚无决定的世界确认让位；旧事实/任务保留，迟到回调失效。
	voice.set_process(false);voice.config.local_only=false
	voice.store.working_tasks.person_003={"request":{"id":"return_request","speaker":"player","text":"把原袋还给我"},"action_event_id":"take_bag","state":"awaiting_judgement","progress":[{"world_facts":[{"kind":"held","object":"water_bag/1"}]}]}
	var task_before: Dictionary=voice.store.working_tasks.person_003.duplicate(true)
	var new_input:={"id":"player_change","speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"先回答我另一个问题"}
	var old_world: Dictionary
	for kind in ["skill_progress","task_observation_changed"]:
		old_world={"id":"pending_"+kind,"speaker":"world","kind":kind,"listeners":["person_003"],"original_event":task_before.request,"text":"实际世界状态已变化"}
		var before: int=reports.size()
		voice.busy=true;voice._start_pipeline(old_world,voice._job_config)
		voice._queue_capture({"text_event":new_input,"config":voice.config.duplicate(true)})
		if voice.busy or voice.pipeline.busy or voice._deferred_judgments.size()!=1:
			push_error(kind+"未完成判断阻塞了玩家输入");quit(1);return
		assert(voice.store.working_tasks.person_003==task_before,"只让判断让位，不能取消任务或改写世界进展")
		assert(voice.store.event_for("person_003",old_world.id).text==old_world.text,"已听见的世界通知不能丢掉")
		voice._process(0)
		await create_timer(0.12).timeout
		assert(reports.size()==before+1 and reports[-1].event_id==new_input.id,"玩家新输入先响应，旧迟到决定不能发布")
		assert(voice._resume_deferred_judgment(),"独立新问题没有处理旧任务，必须恢复旧通知")
		await create_timer(0.12).timeout
		assert(reports.size()==before+2 and reports[-1].event_id==old_world.id)
	# 原任务已由新决定接续/替换时，不再重放旧通知。
	voice.busy=true;voice._start_pipeline(old_world,voice._job_config)
	voice._queue_capture({"text_event":new_input,"config":voice.config.duplicate(true)})
	voice._pending_inputs.clear()
	voice.store.working_tasks.person_003.action_event_id="new_action"
	assert(not voice._resume_deferred_judgment() and voice._deferred_judgments.is_empty())
	# 未完成转写的队首不能被后来的文字越过。
	voice.busy=true;voice._start_pipeline(old_world,voice._job_config)
	voice._queue_capture({"event_id":"untranscribed"})
	voice._queue_capture({"text_event":new_input,"config":voice.config.duplicate(true)})
	assert(voice.busy and voice.pipeline.busy and voice._deferred_judgments.is_empty())
	voice.cancel_interaction();await create_timer(0.12).timeout
	# 新自主轮次覆盖了听众列表，之前仍在执行/学习的人不能漏掉。
	var original_skills: Node=voice.skills
	var pending:=PendingSkills.new();voice.add_child(pending);voice.skills=pending
	voice._speech_order=["person_003"]
	voice.cancel_interaction()
	assert(pending.active.is_empty() and pending.learning.is_empty(),"取消不能遗漏上一轮仍在执行或学习的人物")
	assert(pending.cancelled.size()==3)
	voice.skills=original_skills
	voice.mic.recording=true
	var generation: int=voice._input_generation
	voice.cancel_interaction()
	assert(not voice.mic.recording and voice._input_generation==generation,"录音时只丢弃本句，不中止此前任务")
	print("CANCEL_INTERACTION_PASSED discard_recording_clear_queue_reject_late_reply_player_priority_observation_deferred_resume_stale_discard_fifo")
	assert((await voice.mic.stop_for_shutdown()).is_empty())
	scene.queue_free();await create_timer(0.2).timeout;quit()
