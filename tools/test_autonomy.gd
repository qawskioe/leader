extends SceneTree
const Autonomy=preload("res://scripts/survival/autonomy.gd")
const Cloud=preload("res://scripts/voice/cloud_client.gd")
func _initialize() -> void:
	var scheduler:=Autonomy.new()
	var people:={"a":{"needs":{"hunger":85},"survival_observation":{"storage_food_seen":0}},"b":{"needs":{"hunger":10}}}
	var actors:={"a":{"stage":"idle"},"b":{"stage":"idle"}}
	assert(scheduler.next_event(0,people,actors).is_empty())
	assert(scheduler.next_event(8,people,actors).listeners==["a"])
	assert(scheduler.next_event(9,people,actors).is_empty())
	actors.a.stage="to_storage"
	assert(scheduler.next_event(100,people,actors).is_empty())
	actors.a.stage="idle"
	people.a.survival_observation.storage_food_seen=1
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
	print("AUTONOMY_PASSED: needs, busy_suppression, changed_conditions, event_dedupe, repeated_request, cooldown, deferred_budget")
	quit()
