extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
const Cloud=preload("res://scripts/voice/cloud_client.gd")
class FakeBuilder extends "res://scripts/skills/controller.gd":
	var launches:=0
	func _launch_builder(_python: String, _script: String, _job: String) -> int:
		launches+=1;return 99999999
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Voice.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	voice.skills.queue_free()
	var skills:=FakeBuilder.new();skills.sim=voice.survival;skills.store=voice.store;voice.add_child(skills);skills.set_process(false)
	assert(skills.initialize("res://services/skill-runtime/runtime/request_%d.json"%Time.get_ticks_usec()).is_empty())
	voice.skills=skills;skills.learning_finished.connect(voice._on_learning_finished)
	var original:={"id":"original","kind":"speech_intent","speaker":"player","listeners":["person_003"],"text":"从身边的水源喝一份水"}
	var request:={"goal_id":"drink_nearby"}
	var started: Dictionary=skills.request_learning("person_003",original,request)
	assert(started.ok and skills.launches==1)
	original.text="后来改动的外部对象"
	assert(skills.learning.person_003.original_event.text=="从身边的水源喝一份水","原请求必须冻结")
	assert(not skills.request_learning("person_003",original,request).ok and skills.launches==1)
	skills._end_learning("person_003",true,"测试模拟学会","test_ref")
	assert(voice.autonomy.requests.size()==1)
	assert(voice.autonomy.requests[0].kind=="skill_ready" and voice.autonomy.requests[0].original_event.id=="original")
	assert(voice.autonomy.requests[0].original_event.text=="从身边的水源喝一份水")
	var decision:={"intent":"rest","recipient_id":"","capability_gap":null,"source_object":"","private_interpretation":"停下","public_reply":"","speech_style":"","speech_act":"statement","addressed_person":"","routing_reason":"用户要求停止"}
	voice.store.hear("person_003",{"id":"stop","kind":"speech_intent","speaker":"player","text":"停下"})
	voice._allow_execution=true;voice._job_config=voice.config.duplicate(true)
	voice._on_report({"person_id":"person_003","person_name":"大山","event_id":"stop","decision":decision,"calls":[]})
	assert(voice.autonomy.requests.is_empty(),"停止应撤销学会后的待续请求")
	original.id="second"
	assert(skills.request_learning("person_003",original,request).ok)
	skills.cancel("person_003")
	assert(skills.learning.is_empty() and voice.autonomy.requests.is_empty())
	decision.intent="none";decision["learning_request"]=request
	decision.public_reply="附近没有已知会的人，我先自己尝试学习。";decision.speech_style="平静说明"
	assert(Cloud.validate_decision(JSON.stringify(decision),true).ok)
	voice._allow_execution=false
	voice.store.hear("person_003",{"id":"no_action","kind":"speech_intent","speaker":"player","text":"测试无行动权限"})
	voice._on_report({"person_id":"person_003","person_name":"大山","event_id":"no_action","decision":decision,"calls":[]})
	assert(skills.launches==2 and skills.learning.is_empty(),"无行动权限不启动后台编写")
	decision["skill_call"]={"ref":"fake","arguments":{}}
	assert(not Cloud.validate_decision(JSON.stringify(decision),true).ok)
	voice.autonomy.requests.clear()
	voice._round_events["progress_probe"]={"id":"progress_probe","text":"接近水源并喝水","speaker":"player"}
	var result={"person_id":"person_003","source_event_id":"progress_probe","intent":"skill","success":true,"message":"已接近水源","runtime":{"returned":{"ok":true,"code":"arrived"}}}
	voice._on_skill_result(result)
	assert(voice.autonomy.requests.size()==1)
	assert(voice.autonomy.requests[0].kind=="skill_progress")
	assert(voice.autonomy.requests[0].original_event.text=="接近水源并喝水")
	voice.autonomy.requests.clear()
	result.runtime={"status":"error","code":"cancelled"}
	voice._on_skill_result(result)
	assert(voice.autonomy.requests.is_empty(),"取消不续办")
	result.runtime={"status":"completed","returned":{"ok":true,"code":"arrived"}}
	voice._round_events.progress_probe.skill_followup_step=4
	voice._on_skill_result(result)
	assert(voice.autonomy.requests.is_empty(),"续办有上限")
	voice._on_learning_finished({"person_id":"person_003","ok":true,"message":"已修订","job":"revision_probe","ref":"new_ref","revision_of":"old_ref","original_event":{"id":"teach_once","text":"以后手慢一点"}})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="skill_revised","修订完成必须区别于首次学习续办")
	print("SKILL_REQUEST_CHAIN_PASSED frozen_request, dedupe, continuation, cancel, exclusive_actions; real_model_calls=0")
	scene.queue_free();await create_timer(0.2).timeout;quit()
