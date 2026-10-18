extends SceneTree
## 真实登记/报告/控制器拒绝链；不调用模型，不改正式存档。
class Probe extends "res://scripts/voice/voice_test.gd":
	var logged: Array=[]
	func log_event(entry: Dictionary) -> void:logged.append(entry)
	func _prepare_desktop_microphone() -> void:pass
	func _pump_speech() -> void:pass

func _initialize() -> void:run.call_deferred()

func check(value: bool, message: String) -> bool:
	if value:return true
	push_error(message);quit(1);return false

func run() -> void:
	create_timer(25).timeout.connect(func():push_error("skill start feedback timeout");quit(1))
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Probe.new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions:await physics_frame
	voice.config.local_only=true;voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	voice.config.actions_enabled=true;voice._job_config=voice.config.duplicate(true);voice._allow_execution=true
	var person:="person_003"
	var ref:=""
	for item in voice.skills.library.owners[person]:
		if voice.skills.library.definitions[item.ref].id=="drink":ref=item.ref
	if not check(not ref.is_empty(),"夹具需真实已掌握的饮水方法"):return
	var supplies_before: String=JSON.stringify(voice.survival.life_world.supplies)
	for cause in ["busy","paused"]:
		var event:={"id":"start_rejected_"+cause,"speaker":"player","kind":"speech_intent","listeners":[person],"text":"请喝一份水"}
		voice._round_events[event.id]=event;voice.store.hear(person,event)
		var decision:={"intent":"none","skill_call":{"ref":ref,"arguments":{}},"private_interpretation":"准备使用已掌握的方法","public_reply":"","task_status":"active","task_handling":{"state":"execute","scope":"current_request","reason":"处理原请求"}}
		voice.store.remember(person,event.id,decision)
		if not check(voice.store.working_tasks[person].state=="action_submitted","报告前需经过正式任务登记"):return
		voice.survival.actors[person].stage="water_source" if cause=="busy" else "idle"
		voice.survival.enabled=cause=="busy"
		voice._on_report({"person_id":person,"event_id":event.id,"decision":decision,"calls":[]})
		var results: Array=voice.store.people[person].execution_results.filter(func(r: Dictionary):return r.get("source_event_id")==event.id)
		if not check(results.size()==1 and not results[0].success,"启动拒绝必须生成恰好一个失败回执"):return
		if cause=="busy" and not check(results[0].category=="busy","保留真实忙碌拒绝分类"):return
		var task: Dictionary=voice.store.working_tasks[person]
		if not check(task.state=="awaiting_judgement" and task.request.id==event.id and task.action_event_id==event.id and task.progress.size()==1,"失败不能丢原任务或滞留已提交"):return
		var continuation: Dictionary=voice.autonomy.next_task_event(voice._autonomy_clock,voice.survival.actors)
		if not check(continuation.get("kind")=="skill_progress" and continuation.original_event.id==event.id,"忙碌时仍须交回原任务判断"):return
		if not check(voice.autonomy.next_task_event(voice._autonomy_clock,voice.survival.actors).is_empty(),"同一拒绝不能重复续办"):return
		if not check(voice.skills.active.is_empty() and not voice.skills.accepted.has(person+"/"+event.id),"拒绝不得启动世界操作或占用执行票据"):return
		print("SKILL_START_REJECTED ",cause," receipt=1 task=awaiting_judgement continuation=1")
	if not check(JSON.stringify(voice.survival.life_world.supplies)==supplies_before,"拒绝不能改变资源"):return
	voice.survival.actors[person].stage="idle";voice.survival.enabled=false
	print("SKILL_START_FEEDBACK_PASSED busy_paused_real_report_one_receipt_task_identity_continuation_no_world_change; cloud_calls=0")
	scene.queue_free();await create_timer(0.2).timeout;quit()
