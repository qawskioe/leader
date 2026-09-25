extends SceneTree
const Tasks=preload("res://scripts/survival/help_tasks.gd")
const Autonomy=preload("res://scripts/survival/autonomy.gd")
func _initialize() -> void:
	var tasks:=Tasks.new()
	var aid:={"request_id":"request","requester_id":"a","helper_id":"b","request_text":"帮我取得食物"}
	var actors:={"a":{"stage":"idle"},"b":{"stage":"idle"}}
	tasks.accept(aid,"b",0)
	tasks.heard_acceptance(aid,"b","我去采集",1)
	tasks.result({"person_id":"b","success":true,"intent":"gather_food","message":"卸到储食处","assistance":aid},80)
	assert(tasks.tasks.request.status=="needs_decision")
	assert(tasks.next_event(82,actors).kind=="help_continue")
	assert(tasks.next_event(83,actors).is_empty())
	assert(tasks.context("a",83).own_help_tasks.is_empty())
	assert(not JSON.stringify(tasks.context("a",83)).contains("卸到储食处"),"请求者不会获得远程实际进度")
	var scheduler:=Autonomy.new()
	var people:={"a":{"needs":{"hunger":85},"survival_observation":{"carried_food":0},"help_context":tasks.context("a",100)}}
	assert(scheduler.next_event(100,people,actors).is_empty(),"承诺等待期内不重复派人")
	people.a.survival_observation.carried_food=1
	assert(scheduler.next_event(101,people,actors).listeners==["a"],"收到食物后可以处理自己的需求")
	tasks.accept(aid,"b",102)
	tasks.result({"person_id":"b","success":true,"intent":"give_food","recipient_id":"a","message":"已交到手中","assistance":aid},110)
	assert(tasks.tasks.request.status=="delivered" and tasks.next_event(300,actors).is_empty())
	tasks.result({"person_id":"a","success":true,"intent":"eat","message":"吃到了","food_origin":aid},115)
	assert(tasks.tasks.request.status=="satisfied" and tasks.promises.is_empty())
	var other:=aid.duplicate(true)
	other.request_id="second"
	tasks.accept(other,"b",120)
	assert(tasks.cancel_helper("b")==["second"])
	assert(tasks.next_event(300,actors).is_empty(),"明确中止后不能恢复旧帮助")
	print("HELP_TASKS_PASSED: persistent_goal, continuation, bounded_retry, promise_wait, perception_boundary, completion")
	quit()
