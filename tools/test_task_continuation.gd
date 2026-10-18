extends SceneTree
class Probe extends "res://scripts/voice/voice_test.gd":
	var dispatched: Dictionary={}
	var logged: Array=[]
	func log_event(entry: Dictionary) -> void: logged.append(entry)
	func _start_pipeline(event: Dictionary, _job: Dictionary) -> void: dispatched=event
	func _prepare_desktop_microphone() -> void: pass # 本夹具验证任务队列，不启动实体麦克风。
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(12).timeout.connect(func():quit(1))
	var scheduler=preload("res://scripts/survival/autonomy.gd").new()
	var actors={"a":{"stage":"idle"}}
	scheduler.reset(0)
	var request={"id":"next","kind":"skill_progress","speaker":"world","listeners":["a"],"text":"拿起完成，原请求放远一点","original_event":{"speaker":"player","text":"放远一点"}}
	assert(scheduler.offer_request(request,1))
	assert(scheduler.next_task_event(1,actors).id=="next","任务续办不能被自主活动的启动延时和间隔阻断")
	assert(scheduler.next_task_event(1,actors).is_empty(),"不能重复续办")
	request.id="same_result"
	assert(scheduler.offer_request(request,1.1),"新的执行结果即使文字相同也不能被静默丢弃")
	assert(scheduler.next_task_event(1.1,actors).id=="same_result")
	request.id="busy";request.text="新结果";actors.a.stage="skill_body"
	scheduler.offer_request(request,2)
	assert(scheduler.next_task_event(2,actors).is_empty())
	actors.a.stage="idle";assert(scheduler.next_task_event(3,actors).id=="busy")
	request.id="busy_failure";request.result={"success":false,"category":"busy"};actors.a.stage="water_source"
	scheduler.offer_request(request,3.1)
	assert(scheduler.next_task_event(3.1,actors).id=="busy_failure","忙碌拒绝必须在旧行动结束前交回判断")
	request.erase("result");actors.a.stage="idle"
	request.id="npc";request.text="其他人物任务";request.original_event.speaker="other"
	scheduler.offer_request(request,4)
	assert(scheduler.next_task_event(4,actors).is_empty())
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=Probe.new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions: await physics_frame
	voice.config.autonomy_enabled=false;voice.config.actions_enabled=true;voice.config.local_only=false;voice.menu.close()
	voice._round_events["task"]={"id":"task","speaker":"player","text":"放远一点"}
	voice._on_skill_result({"person_id":"person_003","source_event_id":"task","success":true,"message":"已拿起","runtime":{"status":"completed"}})
	voice._try_autonomy()
	assert(voice.dispatched.get("kind")=="skill_progress" and voice.dispatched.original_event.text=="放远一点","正式入口必须在自主关闭时派发玩家任务续办")
	voice.autonomy.requests.clear()
	voice._round_events["food_task"]={"id":"food_task","speaker":"player","text":"取食物回来交给我"}
	voice._on_action_result({"person_id":"person_003","source_event_id":"food_task","intent":"fetch_food","success":true,"message":"已取得一份食物，拿在手中"})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].original_event.text=="取食物回来交给我","普通取食完成也必须继续玩家的交付请求")
	voice.autonomy.requests.clear()
	voice._round_events["body_task"]={"id":"body_task","speaker":"body","text":"自己饿了"}
	voice._on_action_result({"person_id":"person_003","source_event_id":"body_task","intent":"fetch_food","success":true,"message":"已取得一份食物"})
	assert(voice.autonomy.requests.is_empty(),"不能把普通自主动作完成都变成玩家任务续接")
	# 玩家问月亮，小花旁听后自行找吃的，不等于接受了玩家的问路任务。
	var heard:={"id":"overheard","speaker":"player","text":"月亮，小花在哪里？"}
	voice._round_events[heard.id]=heard
	voice.store.hear("person_002",heard)
	voice.store.working_tasks.person_002={"request":{"id":"prior"},"state":"active","action_event_id":"prior"}
	voice.store.remember("person_002",heard.id,{"intent":"explore","private_interpretation":"不是问我，我自己找吃的","public_reply":"","conversation":{"participation":"listen"},"task_handling":{"state":"execute","scope":"independent","reason":"处理自身饥饿"},"task_status":"active"})
	assert(voice.store.working_tasks.person_002.request.id=="prior","旁听中的自主行为不能覆盖此前的任务")
	voice._on_action_result({"person_id":"person_002","source_event_id":heard.id,"intent":"explore","success":true,"message":"更新周围观察"})
	assert(voice.autonomy.requests.is_empty(),"旁听者探索完成不能续办向别人提出的问话")
	var silent:={"id":"silent_request","speaker":"player","text":"小花，给我拿份食物"}
	voice._round_events[silent.id]=silent
	voice.store.hear("person_002",silent)
	voice.store.remember("person_002",silent.id,{"intent":"fetch_food","private_interpretation":"先取再交付","public_reply":"","conversation":{"participation":"reply"},"task_handling":{"state":"execute","scope":"current_request","reason":"承接取食交付"},"task_status":"active"})
	voice._on_action_result({"person_id":"person_002","source_event_id":silent.id,"intent":"fetch_food","success":true,"message":"已取食物"})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].original_event.id==silent.id,"沉默承接命令仍然必须续办交付，不能把是否发声当作任务判断")
	voice.autonomy.requests.clear()
	var need:={"id":"interrupted_by_hunger","speaker":"body","text":"现在饿了"}
	voice._round_events[need.id]=need
	voice.store.hear("person_002",need)
	voice.store.remember("person_002",need.id,{"intent":"eat","private_interpretation":"先吃饭，交付任务还没完成","public_reply":"","task_status":"active","task_handling":{"state":"execute","scope":"existing_request","reason":"处理中途需求后继续交付"}})
	assert(voice.store.working_tasks.person_002.request.id==silent.id,"身体需求不能覆盖未完成的玩家任务")
	voice._on_action_result({"person_id":"person_002","source_event_id":need.id,"intent":"eat","success":true,"message":"吃完了食物"})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].original_event.id==silent.id,"吃完应根据真实结果继续原来的任务，而非丢掉原命令")
	assert(voice.autonomy.requests[0].skill_followup_step==2,"中途需求不能重置原任务的续办预算")
	voice.autonomy.requests.clear()
	voice.store.working_tasks.person_002.state="paused_budget"
	voice.store.working_tasks.person_002["stop_reason"]="已达到续办预算"
	var paused_before: String=JSON.stringify(voice.store.working_tasks.person_002)
	var thirsty:={"id":"drink_while_paused","speaker":"body","text":"口渴了"}
	voice._round_events[thirsty.id]=thirsty;voice.store.hear("person_002",thirsty)
	voice.store.remember("person_002",thirsty.id,{"intent":"drink","private_interpretation":"先喝水，原任务仍暂停","public_reply":"","task_status":"active","task_handling":{"state":"execute","scope":"independent","reason":"满足自身需求"}})
	voice._on_action_result({"person_id":"person_002","source_event_id":thirsty.id,"intent":"drink","success":true,"message":"喝完水"})
	assert(JSON.stringify(voice.store.working_tasks.person_002)==paused_before,"预算暂停的请求与进度必须保留，身体行为不能覆盖或恢复它")
	assert(voice.autonomy.requests.is_empty(),"喝水完成不能绕过预算重新开始带路")
	voice.store.working_tasks.person_002.state="cancelled"
	need=need.duplicate(true);need.id="after_cancel";voice.store.hear("person_002",need)
	voice.store.remember("person_002",need.id,{"intent":"eat","private_interpretation":"自己吃饭","public_reply":"","task_handling":{"state":"execute","scope":"independent","reason":"满足自身需求"}})
	assert(voice.store.working_tasks.person_002.state=="cancelled","自主吃饭不能恢复已取消的玩家任务")
	voice._round_events["fifth"]={"id":"fifth","speaker":"player","text":"继续","skill_followup_step":4}
	voice._on_skill_result({"person_id":"person_003","source_event_id":"fifth","success":false,"message":"碰撞，需要重新观察","runtime":{"status":"completed"}})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].skill_followup_step==5,"正常重试不能在第四次后无声停止")
	voice.autonomy.requests.clear()
	voice._round_events["limit"]={"id":"limit","speaker":"player","text":"继续","skill_followup_step":16}
	voice._on_skill_result({"person_id":"person_003","source_event_id":"limit","success":false,"message":"仍未完成","runtime":{"status":"completed"}})
	assert(voice.autonomy.requests.is_empty())
	assert(voice.logged.any(func(e):return e.get("type")=="error" and e.get("message","").contains("16次")),"预算耗尽必须明确报告")
	# 已取消的任务只保留实际结果，不再花一次模型调用重新确认取消。
	voice.autonomy.requests.clear()
	voice.store.working_tasks.person_003={"request":{"id":"food_task","speaker":"player","text":"取食物回来"},"action_event_id":"food_task","state":"cancelled","progress":[]}
	voice.autonomy.offer_request({"id":"pending_old","kind":"skill_progress","listeners":["person_003"],"original_event":voice._round_events.food_task,"text":"旧结果"},1)
	voice.autonomy.offer_request({"id":"unrelated","kind":"skill_progress","listeners":["person_003"],"original_event":{"id":"other_task","speaker":"player"},"text":"另一项任务"},1)
	voice._job_config={"tts_enabled":false,"actions_enabled":false}
	voice.store.hear("person_003",{"id":"side_cancel","kind":"information_request","speaker":"person_004","text":"这次问题不问了"})
	voice._on_report({"person_id":"person_003","event_id":"side_cancel","decision":{"intent":"none","public_reply":"","task_handling":{"state":"cancelled","scope":"current_request","reason":"只结束当前同伴问题"}}})
	assert(voice.autonomy.requests.size()==2,"结束旁支问题不能清除原玩家任务的待办结果")
	voice._on_report({"person_id":"person_003","event_id":"cancel","decision":{"intent":"none","public_reply":"","task_handling":{"state":"cancelled","scope":"existing_request","reason":"取消原任务"}}})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].id=="unrelated")
	voice._on_action_result({"person_id":"person_003","source_event_id":"food_task","intent":"fetch_food","success":true,"message":"迟到结果"})
	assert(voice.store.working_tasks.person_003.state=="cancelled")
	assert(voice.autonomy.requests.size()==1)
	voice.store.working_tasks.person_003={"request":{"id":"new_task"},"state":"active"}
	voice._queue_task_result({"person_id":"person_003","source_event_id":"food_task","success":true,"message":"旧结果再次迟到"})
	assert(voice.autonomy.requests.size()==1,"新任务不能让旧取消任务复活")
	voice._queue_task_result({"person_id":"person_003","source_event_id":"fifth","cancelled":true,"success":false,"message":"旧行为中断"})
	assert(voice.autonomy.requests.size()==1,"普通行为的cancelled标志也必须生效")
	# 新的明确行动请求被人物接受后，队列与稍后返回的旧结果都不能复活旧任务。
	voice.autonomy.requests.clear();voice.dispatched.clear()
	voice.store.working_tasks.erase("person_003")
	var first:={"id":"superseded_walk","speaker":"player","text":"回到我身边"}
	var newer:={"id":"new_water","speaker":"player","text":"去取水"}
	var decision:={"intent":"fetch_water","private_interpretation":"接受新的安排","public_reply":"","conversation":{"participation":"reply"},"task_handling":{"state":"execute","scope":"current_request","reason":"执行新安排"},"task_status":"active"}
	voice.store.hear("person_003",first);voice.store.remember("person_003",first.id,decision)
	voice._round_events[first.id]=first
	voice._queue_task_result({"person_id":"person_003","source_event_id":first.id,"success":true,"message":"旧一步已完成"})
	assert(voice.autonomy.requests.size()==1)
	voice.store.hear("person_003",newer);voice.store.remember("person_003",newer.id,decision)
	assert(voice.store.superseded_tasks.get("person_003/"+first.id)==newer.id)
	voice.busy=false;voice._try_autonomy()
	assert(voice.dispatched.is_empty() and voice.autonomy.requests.is_empty(),"已入队的旧任务也必须失效")
	voice._queue_task_result({"person_id":"person_003","source_event_id":first.id,"success":true,"message":"更晚返回的旧结果"})
	assert(voice.autonomy.requests.is_empty())
	voice._round_events[newer.id]=newer
	voice._queue_task_result({"person_id":"person_003","source_event_id":newer.id,"success":true,"message":"新任务结果"})
	voice._try_autonomy()
	assert(voice.dispatched.original_event.id==newer.id,"只阻止旧任务，不阻止新任务继续")
	voice.autonomy.requests.clear()
	var npc:={"id":"npc_step","kind":"social_request","speaker":"person_004","text":"把空袋交给我"}
	voice._round_events[npc.id]=npc
	voice.store.working_tasks.person_003={"request":npc,"action_event_id":npc.id,"state":"action_submitted","progress":[]}
	voice._on_skill_result({"person_id":"person_003","source_event_id":npc.id,"success":true,"message":"已经拿到空袋","runtime":{"status":"completed"}})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].original_event==npc,"同伴明确请求不能在动作后无声停止")
	voice.autonomy.requests.clear()
	voice._round_events.unsolicited={"id":"unsolicited","kind":"received_water","speaker":"person_004","text":"收到水袋"}
	voice._queue_task_result({"person_id":"person_003","source_event_id":"unsolicited","success":true,"message":"自发行动完成"})
	assert(voice.autonomy.requests.is_empty(),"普通自主行动仍不自动循环调用")
	var overheard_npc:={"id":"overheard_continue_npc","kind":"speech_intent","speaker":"player","text":"月亮，继续向大山要水袋"}
	voice.store.hear("person_003",overheard_npc);voice._round_events[overheard_npc.id]=overheard_npc
	voice.store.remember("person_003",overheard_npc.id,{"intent":"rest","private_interpretation":"插话说明我继续处理月亮先前的请求","public_reply":"","conversation":{"participation":"interject"},"task_status":"active","task_handling":{"state":"execute","scope":"existing_request","reason":"推进已有任务"}})
	assert(voice.store.working_tasks.person_003.request.id==npc.id,"插话不能把月亮的请求误改成玩家直接给大山的命令")
	voice._on_action_result({"person_id":"person_003","source_event_id":overheard_npc.id,"intent":"rest","success":true,"message":"旧任务的一步"})
	assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].original_event.id==npc.id,"旁听触发旧任务动作后仍要回到旧任务")
	for scenario in ["waiting_stop","failed_stop","other_source","skill_result","execute_stop"]:
		voice.autonomy.requests.clear()
		var stop:={"id":"stop_"+scenario,"speaker":"player","kind":"speech_intent","text":"停止后等我"}
		voice._round_events[stop.id]=stop;voice.store.hear("person_003",stop)
		var selected:={"intent":"rest","private_interpretation":"明确等待或继续判断","public_reply":"","task_status":"active","task_handling":{"state":"execute" if scenario=="execute_stop" else "wait","scope":"current_request","reason":"处理原请求"}}
		voice.store.remember("person_003",stop.id,selected)
		if scenario=="other_source":voice.store.working_tasks.person_003.action_event_id="newer_stop_source"
		voice._on_action_result({"person_id":"person_003","source_event_id":stop.id,"intent":"skill" if scenario=="skill_result" else "rest","success":scenario!="failed_stop","message":"真实停止或失败结果"})
		assert(voice.autonomy.requests.size()==(0 if scenario=="waiting_stop" else 1),"只能省掉当前来源、成功停止且已明确等待的确认："+scenario)
		if scenario=="waiting_stop":
			assert(voice.store.working_tasks.person_003.state=="wait" and voice.store.working_tasks.person_003.progress.size()==1)
		elif scenario!="other_source":assert(voice.store.working_tasks.person_003.state=="awaiting_judgement")
	# 新命令选择等待旧动作，结果必须续办新命令；覆盖模型返回前/后两种完成时序。
	for finished_early in [false,true]:
		voice.autonomy.requests.clear()
		var suffix:="early" if finished_early else "late"
		var start:={"id":"running_"+suffix,"kind":"speech_intent","speaker":"player","text":"小花，去采果子"}
		var repeat:={"id":"repeat_"+suffix,"kind":"speech_intent","speaker":"player","text":"小花，采好后带回来"}
		voice._round_events[start.id]=start;voice._round_events[repeat.id]=repeat
		voice.store.hear("person_002",start)
		voice.store.remember("person_002",start.id,{"intent":"gather_food","private_interpretation":"已开始采集","public_reply":"","task_handling":{"state":"execute","scope":"current_request","reason":"承接采集请求"},"task_status":"active"})
		var snapshot:={"status":"执行中","intent":"gather_food","source_event_id":start.id}
		var outcome:={"person_id":"person_002","source_event_id":start.id,"intent":"gather_food","success":true,"message":"卸下四份果子"}
		if finished_early:
			voice._on_action_result(outcome)
			voice.autonomy.requests.clear() # 老事件仍在seen中，不能阻止新请求拿到完成结果。
		voice.store.hear("person_002",repeat)
		var waiting:={"intent":"none","private_interpretation":"等待已启动的采集完成","public_reply":"","conversation":{"participation":"reply"},"task_status":"active","task_handling":{"state":"wait","scope":"current_request","reason":"采集已经在执行，不重复启动"}}
		voice.store.remember("person_002",repeat.id,waiting,snapshot)
		assert(voice.store.working_tasks.person_002.action_event_id==start.id)
		assert(voice.store.working_tasks.person_002.request.id==repeat.id)
		if finished_early: voice._resume_waited_result({"person_id":"person_002","event_id":repeat.id,"decision":waiting})
		else: voice._on_action_result(outcome)
		assert(voice.autonomy.requests.size()==1 and voice.autonomy.requests[0].original_event.id==repeat.id,"无论动作先完成还是模型先返回，新请求都须拿到真实结果")
		voice._resume_waited_result({"person_id":"person_002","event_id":repeat.id,"decision":waiting})
		assert(voice.autonomy.requests.size()==1,"不能为同一等待重复派发结果")
	# 同一句玩家输入可让不同人物分别推进新旧任务，结果不能共用全局去重身份。
	voice.autonomy.requests.clear()
	var shared:={"id":"shared_player_round","kind":"speech_intent","speaker":"player","text":"小花，带我去储食处"}
	var prior_loan:={"id":"prior_loan","kind":"social_request","speaker":"person_004","text":"石头，借给我篮子"}
	voice._round_events[shared.id]=shared
	voice.store.working_tasks.person_001={"request":prior_loan,"action_event_id":shared.id,"state":"action_submitted","progress":[]}
	voice.store.working_tasks.person_002={"request":shared,"action_event_id":shared.id,"state":"action_submitted","progress":[]}
	var first_result:={"person_id":"person_001","source_event_id":shared.id,"success":true,"message":"原篮已交付","runtime":{"status":"completed"}}
	var second_result:={"person_id":"person_002","source_event_id":shared.id,"success":false,"message":"等待玩家跟上","runtime":{"status":"completed","returned":{"code":"waiting_for_player"}}}
	voice._on_skill_result(first_result)
	voice._on_skill_result(second_result)
	assert(voice.autonomy.requests.size()==2,"同一轮不同人物的实际结果都必须入队，不能吞掉第二人的续办")
	var seen_ids: Array=[]
	for event in voice.autonomy.requests:
		var person: String=event.result.person_id
		assert(event.listeners==[person] and event.source_event_id==shared.id)
		assert(event.original_event.id==(prior_loan.id if person=="person_001" else shared.id),"各人结果必须保留各自绑定的原请求")
		assert(not event.id in seen_ids,"全局来源表不能被另一人的结果覆盖")
		seen_ids.append(event.id)
	voice._queue_task_result(first_result);voice._queue_task_result(second_result)
	assert(voice.autonomy.requests.size()==2,"同一人物同一动作结果仍只排一次")
	scene.queue_free();await create_timer(0.2).timeout
	print("TASK_CONTINUATION_PASSED scheduler_and_game_dispatch_autonomy_off");quit()
