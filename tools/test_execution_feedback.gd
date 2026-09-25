extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
class FakeGateway extends Node:
	var calls: Array=[]
	func exchange(payload: Dictionary) -> Dictionary:
		calls.append(payload)
		await get_tree().process_frame
		# 受益后选择正常行动，不能被旧的“仅社交”开关吞掉。
		return {"ok":true,"model":"fixture","text":JSON.stringify({"intent":"rest","capability_gap":null,"private_interpretation":"测试理解","public_reply":"","speech_act":"statement","addressed_person":"","speech_style":"neutral","routing_reason":"吃完后选择休息","task_status":"active","task_handling":{"state":"execute","scope":"independent","reason":"正常休息"},"conversation":{"participation":"listen","addressees":[],"reason":"真实世界结果反馈"}})}
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	create_timer(15).timeout.connect(func():push_error("feedback_timeout");quit(1))
	var scene: Node=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	voice.name="VoiceTest"
	scene.add_child(voice)
	voice.config.tts_enabled=false
	voice.config.local_only=true
	voice.config.actions_enabled=true
	voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	var fake:=FakeGateway.new()
	voice.add_child(fake)
	voice.pipeline.gateway=fake
	voice.store.hear("person_001",{"id":"fixture","kind":"need_changed","speaker":"body","text":"测试夹具：尝试取食"})
	voice.store.remember("person_001","fixture",{"private_interpretation":"测试","public_reply":""})
	voice._on_action_result({"person_id":"person_001","source_event_id":"fixture","intent":"fetch_food","success":false,"message":"测试夹具：没有食物"})
	for frame in 5: await process_frame
	assert(fake.calls.is_empty(),"仅本地模式不允许发送执行反馈")
	assert(voice._execution_feedback.is_empty(),"普通行动失败只更新状态，不调用模型播报")
	var origin:={"request_id":"help_fixture","requester_id":"person_002","helper_id":"person_003","request_text":"请帮忙搬食物"}
	voice._on_world_fact({"person_id":"person_001","source_event_id":"stolen","kind":"consumed","material":"food","quantity":1,"origin":origin})
	assert(voice._execution_feedback.is_empty(),"旁人吃掉不算请求者满足需求")
	var meal:={"person_id":"person_002","source_event_id":"meal","kind":"consumed","material":"food","quantity":1,"origin":origin}
	voice._on_world_fact(meal)
	voice._on_world_fact(meal)
	assert(voice._execution_feedback.size()==1,"同一帮助经历只安排一次社交判断")
	voice.config.local_only=false
	var deadline:=Time.get_ticks_msec()+3000
	while (not voice._execution_feedback.is_empty() or voice.busy) and Time.get_ticks_msec()<deadline: await process_frame
	assert(fake.calls.size()==1,"每个结果只反馈一次")
	assert(fake.calls[0].prompt.contains("assistance_completed"),"社交判断包含真实帮助关联")
	var executed:=false
	for result in voice.store.people.person_002.execution_results:
		if result.intent=="rest" and result.success:executed=true
	assert(executed,"真实受益后的决策必须经过正常世界执行")
	assert(voice._execution_feedback.is_empty(),"后续普通动作不能再次触发受益判断")
	assert(voice.store.people.person_001.execution_results[0].success==false,"实际执行失败仍保留记录")
	print("EXECUTION_FEEDBACK_PASSED: ordinary_actions_no_model, wrong_eater_no_social, assistance_once, real_followup_executed_no_feedback_loop, local_mode_no_network; cloud_calls=0")
	scene.queue_free()
	await create_timer(0.15).timeout
	quit()
