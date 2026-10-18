extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
const Cloud=preload("res://scripts/voice/cloud_client.gd")
class DispatchProbe extends "res://scripts/voice/voice_test.gd":
	var dispatched: Array=[]
	func config_error(_require_asr: bool) -> String:return ""
	func _start_pipeline(event: Dictionary, _job: Dictionary) -> void:dispatched.append(event.id)
class FakeBuilder extends "res://scripts/skills/controller.gd":
	var launches:=0
	func _launch_builder(_python: String, _script: String, _job: String) -> int:
		launches+=1;return 99999999
func _initialize() -> void:
	create_timer(20).timeout.connect(func():push_error("skill request chain test timeout");quit(1))
	run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=DispatchProbe.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true
	voice.config.autonomy_enabled=false;voice.config.tts_enabled=false
	while not voice.survival.ready_for_actions: await physics_frame
	voice.skills.queue_free()
	var skills:=FakeBuilder.new();skills.sim=voice.survival;skills.store=voice.store;voice.add_child(skills);skills.set_process(false)
	assert(skills.initialize("res://services/skill-runtime/runtime/request_%d.json"%Time.get_ticks_usec()).is_empty())
	voice.skills=skills;skills.learning_finished.connect(voice._on_learning_finished)
	var original:={"id":"original","kind":"speech_intent","speaker":"player","listeners":["person_003"],"text":"从身边的水源喝一份水"}
	var request:={"goal_id":"drink_nearby","goal":"从身边的水源喝一份水"}
	var started: Dictionary=skills.request_learning("person_003",original,request)
	assert(started.ok and skills.launches==1)
	original.text="后来改动的外部对象"
	assert(skills.learning.person_003.original_event.text=="从身边的水源喝一份水","原请求必须冻结")
	assert(not skills.request_learning("person_003",original,request).ok and skills.launches==1)
	skills._end_learning("person_003",true,"测试模拟学会","test_ref")
	assert(voice.autonomy.requests.size()==1)
	assert(voice.autonomy.requests[0].kind=="skill_ready" and voice.autonomy.requests[0].original_event.id=="original")
	assert(voice.autonomy.requests[0].original_event.text=="从身边的水源喝一份水")
	var decision:={"intent":"rest","capability_gap":null,"private_interpretation":"停下","public_reply":"","speech_style":"","speech_act":"statement","addressed_person":"","routing_reason":"用户要求停止"}
	voice.store.hear("person_003",{"id":"stop","kind":"speech_intent","speaker":"player","text":"停下"})
	voice._allow_execution=true;voice._job_config=voice.config.duplicate(true)
	voice._on_report({"person_id":"person_003","person_name":"大山","event_id":"stop","decision":decision,"calls":[]})
	assert(voice.autonomy.requests.is_empty(),"停止应撤销学会后的待续请求")
	original.id="second"
	assert(skills.request_learning("person_003",original,request).ok)
	skills.cancel("person_003")
	assert(skills.learning.is_empty() and voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].learning_failed,"取消学习保留一次失败反馈，不继续编写")
	voice.autonomy.requests.clear()
	decision.intent="none";decision["learning_request"]=request
	decision["task_handling"]={"state":"execute","scope":"current_request","reason":"依据玩家本次请求学习"}
	decision.public_reply="附近没有已知会的人，我先自己尝试学习。";decision.speech_style="平静说明"
	assert(Cloud.validate_decision(JSON.stringify(decision),true).ok)
	voice._allow_execution=false
	voice.store.hear("person_003",{"id":"no_action","kind":"speech_intent","speaker":"player","text":"测试无行动权限"})
	voice.store.remember("person_003","no_action",decision)
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
	voice._round_events.progress_probe.skill_followup_step=16
	voice._on_skill_result(result)
	assert(voice.autonomy.requests.is_empty(),"续办有上限")
	voice._on_learning_finished({"person_id":"person_003","ok":true,"message":"已修订","job":"revision_probe","ref":"new_ref","revision_of":"old_ref","original_event":{"id":"teach_once","text":"以后手慢一点"}})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="skill_revised","修订完成必须区别于首次学习续办")
	var definition:={"id":"revision_probe","name":"修订来源夹具","description":"不执行动作","parameters":{},"program_json":JSON.stringify(preload("res://scripts/skills/luau_contract.gd").make_program("return function() return {ok=true} end",[]))}
	var raw:=JSON.stringify(definition)
	var registered: Dictionary=skills.library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok and skills.library.grant("person_003",registered.ref,"仅离线夹具").is_empty())
	for kind in ["session_restored","skill_progress"]:
		for succeeded in [false,true]:
			voice.autonomy.requests.clear()
			var command:={"id":"old_%s_%s"%[kind,succeeded],"speaker":"player","kind":"speech_intent","text":"原带路请求"}
			var trigger:={"id":command.id+"_trigger","speaker":"world","kind":kind,"original_event":command.duplicate(true),"result":{"success":false,"skill_ref":registered.ref}}
			voice.store.working_tasks.person_003={"request":command.duplicate(true),"state":"action_submitted","action_event_id":trigger.id}
			assert(skills.request_revision("person_003",trigger,{"ref":registered.ref,"feedback":"依据实际失败修订"}).ok)
			var build: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://services/skill-runtime/runtime/jobs/"+skills.learning.person_003.job+"/build_request.json"))
			assert(build.revision.player_event==trigger,"编写材料须保留实际触发通知和失败证据")
			skills._end_learning("person_003",succeeded,"离线模拟结束",registered.ref if succeeded else "")
			var notification: Dictionary=voice.autonomy.requests[-1]
			assert(notification.original_event==command,"学习结果须绑定原请求，不能再嵌套恢复或进展通知")
			assert(notification.source_event_id==trigger.id,"原请求归属和实际触发事件必须分别保留")
			assert(voice.store.working_context("person_003").recent_turns[-1].event.id==notification.id,"过期判断可取消，发生过的学习结果仍须入本人记忆")
			var replacement:={"id":command.id+"_new","speaker":"player","kind":"speech_intent","text":"改去另一个地方"}
			voice.store.hear("person_003",replacement)
			voice.store.remember("person_003",replacement.id,{"intent":"none","private_interpretation":"处理新的目的地","public_reply":"","speech_style":"","task_status":"active","task_handling":{"scope":"current_request","state":"wait"}})
			assert(voice._task_was_cancelled("person_003",notification),"切换目标后学习通知必须由既有版本过滤识别为过期")
			assert(voice._notification_has_task(notification) and not voice._resume_deferred_judgment(),"旧结果不能通过独立通知快捷通道进入模型")
			voice.config.local_only=false;voice._try_autonomy();voice.config.local_only=true
			assert(voice.autonomy.requests.is_empty() and voice.dispatched.is_empty(),"过期结果须由正常调度过滤，不启动模型")
			assert(voice.store.working_tasks.person_003.request.id==replacement.id and voice.store.working_tasks.person_003.state=="wait","旧学习结果不能改写新任务")
	for succeeded in [false,true]:
		voice.autonomy.requests.clear()
		var command:={"id":"independent_root_%s"%succeeded,"speaker":"player","kind":"speech_intent","text":"等待玩家继续原请求"}
		var trigger:={"id":command.id+"_trigger","speaker":"world","kind":"session_restored","original_event":command.duplicate(true)}
		voice.store.working_tasks.person_003={"request":command.duplicate(true),"state":"wait","action_event_id":command.id}
		voice.store.hear("person_003",trigger)
		voice.store.remember("person_003",trigger.id,{"intent":"none","revision_request":{"ref":registered.ref,"feedback":"独立改善方法"},"private_interpretation":"当前任务仍然等待，只独立改善方法","public_reply":"","speech_style":"","task_status":"active","task_handling":{"scope":"independent","state":"execute"}})
		assert(skills.request_revision("person_003",trigger,{"ref":registered.ref,"feedback":"独立改善方法"}).ok)
		skills._end_learning("person_003",succeeded,"离线独立修订结束",registered.ref if succeeded else "")
		var notification: Dictionary=voice.autonomy.requests[-1]
		assert(notification.original_event==command and notification.source_event_id==trigger.id)
		assert(voice.store.working_tasks.person_003.state=="wait" and voice.store.working_tasks.person_003.action_event_id==command.id,"独立修订失败不能暂停或替换正在等待的原任务")
		assert(not voice._notification_has_task(notification) and voice._resume_deferred_judgment(),"独立修订结果仍应通过独立通知通道处理")
		assert(voice.dispatched[-1]==notification.id and voice.autonomy.requests.is_empty())
	print("SKILL_REQUEST_CHAIN_PASSED frozen_request, dedupe, continuation, cancel, exclusive_actions; real_model_calls=0")
	scene.queue_free();await create_timer(0.2).timeout;quit()
