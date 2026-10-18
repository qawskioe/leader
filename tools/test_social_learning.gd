extends SceneTree
var events: Array=[]
var teacher_ref:=""
func _initialize() -> void:
	create_timer(20).timeout.connect(func():push_error("social learning test timeout");quit(1))
	run.call_deferred()
func decision(kind: String, target: String) -> Dictionary:
	var chosen:={"intent":"none","capability_gap":null,"skill_dialogue":{"kind":kind,"person_id":target,"goal_id":"drink_nearby","reason":"测试角色依据自己的经历作出选择"},"public_reply":"测试中实际说出的话","speech_style":"平静","speech_act":"request" if kind=="ask" else "reply","addressed_person":target,"private_interpretation":"测试","routing_reason":"测试"}
	if kind=="teach":chosen.skill_dialogue["ref"]=teacher_ref
	return chosen
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true
	voice.config.tts_enabled=false;voice.config.autonomy_enabled=false;voice._allow_execution=true;voice._job_config=voice.config.duplicate(true)
	while not voice.survival.ready_for_actions: await physics_frame
	voice.store.memory.path="user://memory/social_test_"+str(Time.get_ticks_usec())+".json"
	voice.store.memory.dirty=true
	var sim: Node=voice.survival
	sim.actors.person_002.body.global_position=Vector3(0,0.1,6)
	sim.actors.person_003.body.global_position=Vector3(1,0.1,6)
	var path:="res://services/skill-runtime/runtime/social_%d.json"%Time.get_ticks_usec()
	assert(voice.skills.initialize(path).is_empty())
	var definition: Dictionary={"id":"drink_nearby","name":"传授测试方法","description":"只验证索引传授，不执行喝水","parameters":{},"program_json":JSON.stringify(preload("res://scripts/skills/luau_contract.gd").make_program("return function(args,context) return {ok=true} end",[]))}
	var raw:=JSON.stringify(definition)
	var registered: Dictionary=voice.skills.library.register_verified(definition,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":raw,"definition_sha256":raw.sha256_text()})
	assert(registered.ok and voice.skills.library.grant("person_002",registered.ref,"测试老师").is_empty())
	teacher_ref=registered.ref
	voice.skills.sync_person("person_002")
	var social: Node=voice.social_learning;social.lesson_seconds=0.25;social.event_ready.connect(func(e: Dictionary): events.append(e))
	assert(voice.store.context_for("person_003").skill_knowledge.is_empty(),"老师会技能不等于学生自动知道")
	voice.store.remember_skill("person_003","person_002","drink_nearby","observed","过去亲眼见过","past")
	assert(not JSON.stringify(voice.store.context_for("person_003")).contains(registered.ref),"线索不能泄露他人技能实现引用")
	var original={"id":"drink_request","kind":"speech_intent","speaker":"player","text":"大山喝水"}
	voice.store.hear("person_003",original)
	var ask:=decision("ask","person_002")
	# 玩家描述的学习目标不是方法的内部ID；真实公开入口须按老师明确选择的版本授课。
	var topic_event:=original.duplicate(true);topic_event.id="different_learning_topic"
	voice.store.hear("person_003",topic_event)
	var topic_ask:=ask.duplicate(true);topic_ask.skill_dialogue.goal_id="my_requested_ability"
	voice._deliver_public("person_003",topic_event.id,topic_ask.public_reply,10,topic_ask)
	var topic_request: Dictionary=events[-1]
	voice.store.hear("person_002",topic_request)
	var chosen_method:=decision("teach","person_003");chosen_method.skill_dialogue.goal_id=topic_ask.skill_dialogue.goal_id
	voice._deliver_public("person_002",topic_request.id,chosen_method.public_reply,10,chosen_method)
	assert(social.sessions.has(topic_request.lesson_request_id) and social.sessions[topic_request.lesson_request_id].ref==registered.ref,"求教目标名不同仍应开始教授本人选择的方法")
	social.cancel("person_002");events.clear()
	assert(social.pending.is_empty(),"生成台词不代表已经被听见")
	var invitation:={"id":"teacher_invitation","kind":"speech_intent","speaker":"player","text":"请教同伴这个方法","private_interpretation":"仅老师自己的理解"}
	voice.store.hear("person_002",invitation)
	var invite:=decision("teach","person_003");invite.public_reply="愿意的话，可以跟我学这个方法。"
	voice._deliver_public("person_002",invitation.id,invite.public_reply,10,invite)
	assert(events.size()==1 and events[-1].kind=="skill_lesson_offer","主动teach必须让学生实际收到邀请，不能静默吞掉")
	var offered: Dictionary=events[-1]
	assert(offered.listeners==["person_003"] and offered.speaker=="person_002" and offered.goal_id=="drink_nearby")
	assert(voice.store.is_person_request(offered),"教学邀请是人物交谈，不是身体或世界通知")
	assert(not offered.has("original_event") and not JSON.stringify(offered).contains(registered.ref) and not JSON.stringify(offered).contains("private_interpretation"),"教学邀请只传公开信息")
	assert(social.pending.is_empty() and social.sessions.is_empty() and sim.actors.person_003.stage=="idle" and voice.skills.library.resolve("person_003",registered.ref).is_empty(),"邀请不等于学生同意，也不授予技能")
	var knowledge: Array=voice.store.context_for("person_003").skill_knowledge
	assert(not knowledge.is_empty() and not JSON.stringify(knowledge).contains(registered.ref),"学生只得到被实际听见的能力线索")
	# 同一次公开发言不会重复发邀请；失效的旧求教不能变成新邀请。
	social.public_decision("person_002",invitation,decision("teach","person_003"),["person_003"])
	assert(events.size()==1)
	var expired:={"id":"expired_teacher_reply","kind":"skill_lesson_request","lesson_request_id":"expired"}
	social.public_decision("person_002",expired,decision("teach","person_003"),["person_003"])
	assert(events[-1].kind=="skill_learning_feedback" and events[-1].listeners==["person_002"] and social.sessions.is_empty(),"失效的授课请求返回本人判断，不可自动转为邀请")
	var unowned:=decision("teach","person_003");unowned.skill_dialogue.ref="unknown_method@not_owned"
	social.public_decision("person_002",{"id":"unowned_invitation"},unowned,["person_003"])
	assert(events[-1].kind=="skill_learning_feedback" and social.sessions.is_empty(),"没有掌握的方法不能作为有效邀请")
	# 测试夹具显式模拟完整播放，生产入口由真实播放完成调用。
	voice._deliver_public("person_003",original.id,ask.public_reply,10,ask)
	assert(social.pending.size()==1 and events[-1].kind=="skill_lesson_request")
	var request: Dictionary=events[-1]
	assert(not request.has("original_event"),"老师只收到公开求教，不得到学生的私下上下文")
	assert(voice.skills.library.resolve("person_003",registered.ref).is_empty())
	assert(voice.store.is_person_request(request),"求教也是人物请求")
	var mismatched: Dictionary=request.duplicate(true);mismatched.id+="_wrong_goal"
	var wrong_goal:=decision("teach","person_003");wrong_goal.skill_dialogue.goal_id="other_method"
	social.public_decision("person_002",mismatched,wrong_goal,["person_003"])
	assert(social.pending.has(request.lesson_request_id) and social.sessions.is_empty() and events[-1].kind=="skill_learning_feedback","不匹配的技能不能消耗原求教票据")
	var missing_method: Dictionary=request.duplicate(true);missing_method.id+="_unowned_method"
	social.public_decision("person_002",missing_method,unowned,["person_003"])
	assert(social.pending.has(request.lesson_request_id) and events[-1].listeners==["person_002"],"失效的授课引用须告知老师，保留仍有效的求教")
	# 求教等待已超过授课时长，不能把等老师的时间算成实际学习。
	social.pending[request.lesson_request_id].elapsed=social.lesson_seconds+1.0
	social.public_decision("person_002",request,decision("teach","person_003"),["person_003"])
	assert(social.sessions.size()==1 and voice.skills.library.resolve("person_003",registered.ref).is_empty(),"教学开始不能立即授予")
	assert(social.sessions[request.lesson_request_id].elapsed==0.0,"实际授课必须从零计时，不继承求教等待")
	await create_timer(.1).timeout
	assert(voice.skills.library.resolve("person_003",registered.ref).is_empty(),"正式教学时间不足时不能授予")
	# 普通对话已结束且被别人的回合覆盖，Backspace仍须取消实际教学和求教。
	var fourth_before: Vector3=sim.actors.person_004.body.global_position
	sim.actors.person_004.body.global_position=Vector3(1.5,.1,6)
	social.public_decision("person_004",{"id":"pending_during_lesson"},decision("ask","person_002"),["person_002"])
	assert(social.pending.size()==1)
	voice._speech_order=["person_001"]
	voice.cancel_interaction()
	assert(social.sessions.is_empty() and social.pending.is_empty(),"取消入口必须覆盖最新对话之外的授课双方与待答复学生")
	await create_timer(.4).timeout
	assert(voice.skills.library.resolve("person_003",registered.ref).is_empty() and voice.skills.library.resolve("person_004",registered.ref).is_empty(),"中断后越过原教学时限也不得授予")
	for id in ["person_002","person_003","person_004"]:assert(sim.actors[id].stage=="idle")
	sim.actors.person_004.body.global_position=fourth_before
	voice._allow_execution=true
	original.id="drink_request_2"
	voice.store.working_tasks["person_003"]={"request":original.duplicate(true)}
	var continuing:=ask.duplicate(true);continuing.task_handling={"scope":"existing_request"}
	var continuing_offer:=offered.duplicate(true);continuing_offer.id="continue_invitation"
	social.public_decision("person_003",continuing_offer,continuing,["person_002"])
	request=events[-1]
	assert(not request.has("original_event") and not JSON.stringify(request).contains(original.text),"继续原任务求教也不向老师泄露私有原请求")
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
	# 同一方法ID可以有不同版本；不能回退成目录中第一个同名方法。
	var newer:=definition.duplicate(true);newer.name+="第二版"
	var newer_raw:=JSON.stringify(newer)
	var second: Dictionary=voice.skills.library.register_verified(newer,{"verifier":"leader-luau-tests-v1","passed":true,"definition_json":newer_raw,"definition_sha256":newer_raw.sha256_text()})
	assert(second.ok and second.ref!=registered.ref and voice.skills.library.grant("person_002",second.ref,"测试老师的另一版本").is_empty())
	teacher_ref=second.ref
	original.id="selected_version_request"
	social.public_decision("person_004",original,decision("ask","person_002"),["person_002"])
	request=events[-1]
	social.public_decision("person_002",request,decision("teach","person_004"),["person_004"])
	assert(social.sessions[request.lesson_request_id].ref==second.ref)
	await create_timer(.4).timeout
	assert(not voice.skills.library.resolve("person_004",second.ref).is_empty() and voice.skills.library.resolve("person_004",registered.ref).is_empty(),"只授予老师明确选择的版本")
	teacher_ref=registered.ref
	original.id="timeout_probe";social.request_timeout=0.05
	social.public_decision("person_004",original,decision("ask","person_002"),["person_002"])
	await create_timer(0.1).timeout
	assert(social.pending.is_empty() and events[-1].kind=="skill_learning_feedback","无回应会返回本人重新决定")
	assert((await voice.store.memory.flush_pending(self)).is_empty())
	var restored=load("res://scripts/voice/people_store.gd").new()
	assert(restored.initialize("res://data/people.json",voice.store.memory.path).is_empty())
	social.store=restored;social.load_knowledge()
	assert(not restored.people.person_003.skill_knowledge.is_empty(),"线索记忆独立保存并可重载")
	social.store=voice.store
	print("SOCIAL_LEARNING_PASSED private_knowledge, actual_speech_gate, public_invitation_student_choice, stale_and_mismatched_ticket, teacher_consent, delayed_grant, cancellation, shared_version, original_request, persistence; model_calls=0")
	voice.cancel_interaction()
	scene.queue_free();await create_timer(0.2).timeout;quit()
