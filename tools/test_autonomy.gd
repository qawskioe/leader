extends SceneTree
const Autonomy=preload("res://scripts/survival/autonomy.gd")
func _initialize() -> void:
	var scheduler:=Autonomy.new()
	var people:={"a":{"needs":{"hunger":85},"survival_observation":{"known_objects":{"storage":{"kind":"storage","available":false,"position":[0,0,1],"extra":{"food_count":0}}}}},"b":{"needs":{"hunger":10}}}
	var actors:={"a":{"stage":"idle"},"b":{"stage":"idle"}}
	assert(scheduler.next_event(0,people,actors).is_empty())
	assert(scheduler.next_event(8,people,actors).listeners==["a"])
	assert(scheduler.next_event(9,people,actors).is_empty())
	actors.a.stage="to_storage"
	assert(scheduler.next_event(100,people,actors).is_empty())
	actors.a.stage="idle"
	people.a.survival_observation.known_objects.storage.available=true
	people.a.survival_observation.known_objects.storage.extra.food_count=1
	assert(scheduler.next_event(30,people,actors).listeners==["a"])
	people.a.needs.hunger=40
	assert(scheduler.next_event(31,people,actors).is_empty())
	var request:={"id":"request1","speaker":"a","listeners":["b"],"text":"请帮我搬一份食物","kind":"social_request"}
	assert(scheduler.offer_request(request,31))
	assert(not scheduler.offer_request(request,32))
	assert(scheduler.next_event(32,people,actors).id=="request1")
	request.id="request2"
	assert(not scheduler.offer_request(request,33),"重复内容请求在等待期不反复调用")
	request.id="request_changed"
	request.text="这里被挡住了，能过来看看吗？"
	assert(scheduler.offer_request(request,34))
	assert(scheduler.next_event(34,people,actors).is_empty(),"人物判断间隔")
	assert(scheduler.next_event(53,people,actors).id=="request_changed")
	request.id="request3"
	request.text="新事件"
	assert(scheduler.offer_request(request,54))
	assert(scheduler.next_event(60,people,actors).is_empty(),"一分钟预算用尽后延后，不丢事件")
	assert(scheduler.requests.size()==1)
	assert(scheduler.next_event(94,people,actors).id=="request3")
	for kind in ["session_restored","session_checkpoint"]:
		var continuation:=Autonomy.new()
		assert(continuation.offer_request({"id":kind,"kind":kind,"speaker":"world","listeners":["b"],"text":"继续已接受请求","original_event":{"id":"player_goal","speaker":"player","text":"带我回大山"}},0))
		assert(continuation.next_task_event(0,actors).get("id","")==kind,"关闭自主需求时，存取后的已接受任务仍应进入任务续办队列")
	for speaker in ["world","body"]:
		var notices:=Autonomy.new()
		var event:={"id":speaker+"_first","kind":"assistance_completed" if speaker=="world" else "need_changed","speaker":speaker,"listeners":["b"],"text":"相同文字的两次真实通知"}
		assert(notices.offer_request(event,0))
		assert(not notices.offer_request(event,1),"同一事件身份仍去重")
		event.id=speaker+"_second"
		assert(notices.offer_request(event,2) and notices.requests.size()==2,"不同事件不能仅因文字相同被吞掉")
	resource_checks()
	print("AUTONOMY_PASSED: needs, busy_suppression, changed_conditions, event_dedupe, repeated_request, cooldown, deferred_budget_distinct_internal_same_text")
	quit()

func resource_checks() -> void:
	var scheduler:=Autonomy.new()
	var known:={"basket/1":{"kind":"basket","available":false,"position":[0,0,1],"extra":{"food_count":0,"holder":"other"}},"person/player":{"kind":"person","available":true,"position":[0,0,2],"extra":{}}}
	var people:={"a":{"needs":{"hunger":100,"thirst":40},"survival_observation":{"knowledge_revision":1,"known_objects":known}}}
	var actors:={"a":{"stage":"idle"}}
	assert(not scheduler.next_event(8,people,actors).is_empty())
	people.a.survival_observation.knowledge_revision=100
	known["basket/1"].position=[5,0,1];known["person/player"].position=[5,0,2]
	assert(scheduler.next_event(28,people,actors).is_empty(),"空篮、人物位置和笼统知识修订不能催发相同饥饿判断")
	known["fruit/1"]={"kind":"fruit","available":true,"position":[0,0,3],"extra":{}}
	var changed: Dictionary=scheduler.next_event(48,people,actors)
	assert(changed.trigger.reason=="need_changed" and changed.trigger.changes.resources.objects==["fruit/1"],"新发现可吃的果子仍立即通知，变化只列相关物品")
	var described: Dictionary=preload("res://scripts/voice/turn_context.gd").describe(changed,people)
	assert(described.cause.contains("fruit/1") and described.cause.contains("相关的食物或水源"))
	people.a.survival_observation.storage_food_seen=42
	assert(scheduler.next_event(68,people,actors).is_empty(),"临时视野库存字段变化不能覆盖已知物资的稳定依据")
	known["basket/1"].extra.food_count=2
	assert(not scheduler.next_event(68,people,actors).is_empty(),"他人持有的新食物也是可求助的新机会")
	known["basket/1"].position=[8,0,1];known["fruit/1"].observed_at_seconds=999
	assert(scheduler.next_event(88,people,actors).is_empty(),"持有食物的普通移动和观察时刻不重复通知")
	known["fruit/1"].position=[0.1,0,3]
	assert(scheduler.next_event(108,people,actors).is_empty(),"细微位置抖动不重复通知")
	known["fruit/1"].position=[0.3,0,3]
	assert(not scheduler.next_event(128,people,actors).is_empty(),"可用物资的累积实质位移仍通知")
	known["fruit/1"].available=false
	assert(not scheduler.next_event(148,people,actors).is_empty(),"已知食物消失仍通知")
	known["water_source"]={"kind":"water_source","available":true,"position":[0,0,4],"extra":{}}
	known["storage"]={"kind":"storage","available":null,"position":[0,0,5],"extra":{"food_count":null}}
	people.a.survival_observation.storage_food_seen=null
	assert(scheduler.next_event(168,people,actors).is_empty(),"当前仅饥饿时新水源不反复触发食物判断")
	people.a.needs.thirst=60
	assert(not scheduler.next_event(188,people,actors).is_empty(),"口渴达到条件后水源进入本轮依据")
	known["water_bag/1"]={"kind":"water_bag","available":false,"position":[0,0,1],"extra":{"water":2,"holder":"other"}}
	assert(not scheduler.next_event(208,people,actors).is_empty(),"他人持有的水仍是可求助的机会")
	assert(scheduler.next_event(228,people,actors).is_empty())
	assert(scheduler.next_event(298,people,actors).trigger.reason=="need_retry","保持90秒复查，不永久静默")
