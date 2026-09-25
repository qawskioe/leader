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
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	var fake:=DelayedGateway.new();voice.add_child(fake);voice.pipeline.gateway=fake
	voice.pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	voice.busy=true;voice._job_config=voice.config.duplicate(true)
	voice._start_pipeline({"id":"old","speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"错误的一句"},voice._job_config)
	voice._pending_captures.append({"fixture":true})
	voice.cancel_interaction()
	assert(not voice.busy and not voice.pipeline.busy and voice._pending_captures.is_empty())
	voice.busy=true
	voice._start_pipeline({"id":"new","speaker":"player","kind":"speech_intent","listeners":["person_003"],"text":"正确的新一句"},voice._job_config)
	assert(voice.captions.person_003.hearing_text=="已听见 · 正在理解")
	assert(voice.captions.person_002.hearing_text=="这句话未传给她")
	await create_timer(0.4).timeout
	assert(reports.size()==1 and reports[0].event_id=="new","旧模型结果不能串入新请求")
	assert(voice.captions.person_003.hearing_text=="已听见 · 决策处理失败","模型错误不抹掉已经听见")
	assert(voice.pipeline._active==0 and not voice.pipeline.busy)
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
	print("CANCEL_INTERACTION_PASSED discard_recording, clear_queue, reject_late_reply, next_request_valid")
	scene.queue_free();await create_timer(0.2).timeout;quit()
