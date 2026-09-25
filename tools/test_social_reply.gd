extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("social reply test timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true;voice.config.autonomy_enabled=true
	while not voice.survival.ready_for_actions:await physics_frame
	var sim=voice.survival;sim.enabled=false
	var a:="person_003";var b:="person_004"
	sim.actors[a].body.global_position=Vector3(2,0,6)
	sim.actors[b].body.global_position=Vector3(3.5,0,6)
	await physics_frame
	var original:={"id":"give_requested","kind":"speech_intent","speaker":"player","text":"空水袋原样交给月亮，不用装水"}
	voice.store.hear(a,original)
	voice.store.working_tasks[a]={"request":original,"state":"ask","progress":[]}
	var ask:={"speech_act":"request","request_kind":"help","addressed_person":b}
	var answer:={"speech_act":"reply","addressed_person":a}
	voice._deliver_public(a,original.id,"月亮，请看这边。",12,ask)
	assert(voice.autonomy.requests.size()==1)
	var request: Dictionary=voice.autonomy.requests.pop_front()
	assert(not request.has("original_event"),"请求者的完整任务与私下上下文不能发给别人")
	voice._round_events[request.id]=request;voice.store.hear(b,request)
	voice._deliver_public(b,request.id,"我转过来看你。",0.1,answer)
	assert(voice.autonomy.requests.is_empty(),"未听见答复不能续接")
	var after_action:={"id":"look_result","kind":"skill_progress","speaker":"world","original_event":request,"text":"转身实际完成"}
	voice._round_events[after_action.id]=after_action;voice.store.hear(b,after_action)
	voice._deliver_public(b,after_action.id,"我转过来看你。",12,answer)
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].kind=="social_reply")
	var follow: Dictionary=voice.autonomy.requests[0]
	assert(follow.original_event==original and follow.listeners==[a],"必须接回请求者自己的原任务")
	voice._deliver_public(b,request.id,"我转过来看你。",12,answer)
	assert(voice.autonomy.requests.size()==1,"同一答复只续接一次")
	voice._round_events[follow.id]=follow;voice.store.hear(a,follow)
	voice._deliver_public(a,follow.id,"知道了。",12,{"speech_act":"reply","addressed_person":b})
	assert(voice.autonomy.requests.size()==1,"回话的回话不自动循环")
	assert(voice.autonomy.next_task_event(0,sim.actors).id==follow.id,"原玩家任务的答复不等待饥饿预算")
	var second:={"id":"ask_again","kind":"skill_progress","speaker":"world","original_event":original,"text":"尚未交付"}
	voice.store.hear(a,second)
	voice._deliver_public(a,second.id,"月亮，再看这边。",12,ask)
	var cancelled: Dictionary=voice.autonomy.requests.pop_front()
	voice._round_events[cancelled.id]=cancelled;voice.store.hear(b,cancelled)
	voice.store.working_tasks[a].state="cancelled"
	voice._deliver_public(b,cancelled.id,"我看着你。",12,answer)
	assert(voice.autonomy.requests.is_empty(),"迟到的答复不能复活取消的任务")
	for index in 2:
		var distinct:=follow.duplicate(true);distinct.id="distinct_reply_"+str(index)
		assert(voice.autonomy.offer_request(distinct,0),"分别对应不同请求的真实答复不能只因文字相同被冷却丢弃")
	print("SOCIAL_REPLY_PASSED actual_hearing_exact_request_no_private_leak_no_echo_cancelled_not_revived")
	scene.queue_free();await create_timer(0.2).timeout;quit()
