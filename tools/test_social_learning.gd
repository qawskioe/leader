extends SceneTree
const Cloud=preload("res://scripts/voice/cloud_client.gd")
var events: Array=[]
func _initialize() -> void: run.call_deferred()
func decision(kind: String, target: String) -> Dictionary:
	return {"intent":"none","recipient_id":"","capability_gap":null,"skill_dialogue":{"kind":kind,"person_id":target,"goal_id":"drink_nearby","reason":"测试角色依据自己的经历作出选择"},"public_reply":"测试中实际说出的话","speech_style":"平静","speech_act":"request" if kind=="ask" else "reply","addressed_person":target,"private_interpretation":"测试","routing_reason":"测试"}
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.config.tts_enabled=false;voice.config.autonomy_enabled=false;voice._allow_execution=true;voice._job_config=voice.config.duplicate(true)
	while not voice.survival.ready_for_actions: await physics_frame
	var sim: Node=voice.survival
	sim.actors.person_002.body.global_position=Vector3(0,0.1,6)
	sim.actors.person_003.body.global_position=Vector3(1,0.1,6)
	var path:="res://services/skill-runtime/runtime/social_%d.json"%Time.get_ticks_usec()
	assert(voice.skills.initialize(path).is_empty())
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://services/skill-runtime/runtime/lesson_teacher_package.json"))
	var registered: Dictionary=voice.skills.library.register_verified(package.definition,package.receipt)
	assert(registered.ok and voice.skills.library.grant("person_002",registered.ref,"测试老师").is_empty())
	voice.skills.sync_person("person_002")
	var social: Node=voice.social_learning;social.lesson_seconds=0.25;social.event_ready.connect(func(e: Dictionary): events.append(e))
	assert(voice.store.context_for("person_003").skill_knowledge.is_empty(),"老师会技能不等于学生自动知道")
	voice.store.remember_skill("person_003","person_002","drink_nearby","observed","过去亲眼见过","past")
	assert(not JSON.stringify(voice.store.context_for("person_003")).contains(registered.ref),"线索不能泄露他人技能实现引用")
	var original={"id":"drink_request","kind":"speech_intent","speaker":"player","text":"大山喝水"}
	voice.store.hear("person_003",original)
	var ask:=decision("ask","person_002")
	assert(Cloud.validate_decision(JSON.stringify(ask),true).ok)
	voice._on_report({"person_id":"person_003","person_name":"大山","event_id":original.id,"decision":ask,"calls":[]})
	assert(social.pending.is_empty(),"生成台词不代表已经被听见")
	# 测试夹具显式模拟完整播放，生产入口由真实播放完成调用。
	voice._deliver_public("person_003",original.id,ask.public_reply,10,ask)
	assert(social.pending.size()==1 and events[-1].kind=="skill_lesson_request")
	var request: Dictionary=events[-1]
	assert(not request.has("original_event"),"老师只收到公开求教，不得到学生的私下上下文")
	assert(voice.skills.library.resolve("person_003",registered.ref).is_empty())
	social.public_decision("person_002",request,decision("teach","person_003"),["person_003"])
	assert(social.sessions.size()==1 and voice.skills.library.resolve("person_003",registered.ref).is_empty(),"教学开始不能立即授予")
	social.cancel("person_003")
	assert(social.sessions.is_empty() and voice.skills.library.resolve("person_003",registered.ref).is_empty(),"取消不授予")
	original.id="drink_request_2"
	social.public_decision("person_003",original,ask,["person_002"])
	request=events[-1]
	social.public_decision("person_002",request,decision("teach","person_003"),["person_003"])
	await create_timer(0.4).timeout
	assert(not voice.skills.library.resolve("person_003",registered.ref).is_empty())
	assert(events[-1].kind=="skill_ready" and events[-1].original_event.id==original.id,"学成后继续原任务")
	assert(voice.skills.learning.is_empty(),"传授不启动强模型重新编写")
	assert(voice.skills.library.describe("person_003")[0].ref==registered.ref,"共享同一个版本索引")
	original.id="decline_probe"
	social.public_decision("person_004",original,decision("ask","person_002"),["person_002"])
	# person_004 不在附近，应收到实际距离失败而非读取老师技能库。
	assert(events[-1].kind=="skill_learning_feedback")
	sim.actors.person_004.body.global_position=Vector3(1.5,0.1,6)
	original.id="decline_nearby"
	social.public_decision("person_004",original,decision("ask","person_002"),["person_002"])
	request=events[-1]
	social.public_decision("person_002",request,decision("decline","person_004"),["person_004"])
	assert(events[-1].kind=="skill_learning_feedback" and events[-1].original_event.id==original.id)
	assert(voice.skills.library.resolve("person_004",registered.ref).is_empty(),"拒绝不会授予")
	original.id="timeout_probe";social.request_timeout=0.05
	social.public_decision("person_004",original,decision("ask","person_002"),["person_002"])
	await create_timer(0.1).timeout
	assert(social.pending.is_empty() and events[-1].kind=="skill_learning_feedback","无回应会返回本人重新决定")
	var restored=load("res://scripts/voice/people_store.gd").new();restored.initialize()
	social.store=restored;social.load_knowledge()
	assert(not restored.people.person_003.skill_knowledge.is_empty(),"线索记忆独立保存并可重载")
	social.store=voice.store
	print("SOCIAL_LEARNING_PASSED private_knowledge, actual_speech_gate, teacher_consent, delayed_grant, cancellation, shared_version, original_request, persistence; model_calls=0")
	scene.queue_free();await create_timer(0.2).timeout;quit()
