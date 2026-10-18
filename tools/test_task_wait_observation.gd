extends SceneTree
const Autonomy=preload("res://scripts/survival/autonomy.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(5).timeout.connect(func():quit(1))
	var scheduler=Autonomy.new()
	var actors={"a":{"stage":"idle","body":Node3D.new()}}
	root.add_child(actors.a.body)
	var task={"request":{"id":"original","speaker":"player","text":"带我去树林"},"state":"wait","action_event_id":"decision"}
	var tasks={"a":task}
	var memories={"a":{"person/player":{"visible_now":true,"position":[0,0,4.2]}}}
	scheduler.watch_player("a","decision",memories.a["person/player"],Vector3.ZERO)
	finish_watch(scheduler,task,"decision")
	assert(scheduler.next_wait_event(0,tasks,actors,memories).is_empty(),"未变化的等待不能轮询调用模型")
	memories.a["person/player"].position=[0,0,4.19]
	assert(scheduler.next_wait_event(1,tasks,actors,memories).is_empty(),"细微抖动不能触发续办")
	memories.a["person/player"].position=[0,0,1.7]
	assert(scheduler.next_wait_event(2,tasks,actors,memories).is_empty(),"移动过程先合并变化，不在半途调用")
	memories.a["person/player"].position=[0,0,1.4]
	assert(scheduler.next_wait_event(2.3,tasks,actors,memories).is_empty(),"继续靠近会刷新合并窗口")
	assert(scheduler.next_wait_event(2.6,tasks,actors,memories).is_empty(),"观察未稳定半秒不触发")
	var event: Dictionary=scheduler.next_wait_event(2.9,tasks,actors,memories)
	assert(event.get("kind")=="task_observation_changed" and event.original_event.id=="original","跟近后唤醒原请求，不新建目标或指定动作")
	assert(event.trigger.player_distance_m<2 and not event.has("skill_call"))
	assert(scheduler.next_wait_event(3,tasks,actors,memories).is_empty(),"同一观察变化只能触发一次")
	scheduler.watch_player("a","decision",{"visible_now":false},Vector3.ZERO)
	finish_watch(scheduler,task,"decision")
	memories.a["person/player"]={"visible_now":false,"position":[0,0,1]}
	assert(scheduler.next_wait_event(4,tasks,actors,memories).is_empty(),"不可见目标的旧位置不能唤醒")
	memories.a["person/player"].visible_now=true
	assert(scheduler.next_wait_event(5,tasks,actors,memories).is_empty())
	assert(not scheduler.next_wait_event(5.6,tasks,actors,memories).is_empty(),"重新亲眼看见玩家是新事实")
	for state in ["completed","cancelled","refused","paused_budget","action_submitted"]:
		task.state=state;scheduler.watch_player("a","decision",{"visible_now":false},Vector3.ZERO)
		finish_watch(scheduler,task,"decision")
		assert(scheduler.next_wait_event(6,tasks,actors,memories).is_empty(),"观察不能恢复已结束、已暂停或执行中的任务")
	task.state="wait";actors.a.stage="skill_body"
	assert(scheduler.next_wait_event(7,tasks,actors,memories).is_empty(),"执行忙碌时不重叠行动")
	actors.a.stage="idle"
	scheduler.watch_player("a","body_wait",{"visible_now":true,"position":[0,0,4]},Vector3.ZERO)
	finish_watch(scheduler,task,"body_wait")
	memories.a["person/player"]={"visible_now":true,"position":[0,0,1.5]}
	assert(scheduler.next_wait_event(8,tasks,actors,memories).is_empty())
	assert(not scheduler.next_wait_event(8.6,tasks,actors,memories).is_empty(),"中途判断保留原行动来源时，玩家走近仍须唤醒等待任务")
	# 原请求动作开始时很近，走远停下后，使用等待判断实际看到的远处作为新基线。
	scheduler.watch_player("a","new_action",memories.a["person/player"],Vector3.ZERO)
	task.state="action_submitted";task.action_event_id="new_action"
	finish_watch(scheduler,task,"new_action")
	scheduler.watch_player("a","result_wait",{"visible_now":true,"position":[0,0,4]},Vector3.ZERO)
	task.state="wait";task.action_event_id="result_wait"
	finish_watch(scheduler,task,"result_wait")
	# 独立需求、失败和迟到报告都不能替换已接受任务的观察。
	for event_id in ["independent_need","failed_need"]:
		scheduler.watch_player("a",event_id,memories.a["person/player"],Vector3.ZERO)
		if event_id=="independent_need":finish_watch(scheduler,task,event_id,"independent")
		else:scheduler.finish_player_watch({"person_id":"a","event_id":event_id,"error":"fixture"},task)
	assert(scheduler.pending_player_views.is_empty())
	scheduler.watch_player("a","side_question",memories.a["person/player"],Vector3.ZERO)
	scheduler.finish_player_watch({"person_id":"a","event_id":"side_question","decision":{"task_handling":{"scope":"current_request"}}},task,false)
	assert(scheduler.next_wait_event(10,tasks,actors,memories).is_empty())
	var resumed: Dictionary=scheduler.next_wait_event(10.6,tasks,actors,memories)
	assert(resumed.get("source_event_id")=="result_wait","独立判断和失败不能吞掉追上后的原任务续办")
	assert(scheduler.next_wait_event(11,tasks,actors,memories).is_empty())
	task.state="ask"
	scheduler.watch_player("a","ask_close",{"visible_now":true,"position":[0,0,4]},Vector3.ZERO)
	finish_watch(scheduler,task,"ask_close")
	assert(scheduler.next_wait_event(11.1,tasks,actors,memories).is_empty())
	assert(not scheduler.next_wait_event(11.7,tasks,actors,memories).is_empty(),"询问后等待玩家补充时，实际靠近也应交人物判断，不能只等另一句台词")
	scheduler.reset(12)
	assert(scheduler.task_player_views.is_empty() and scheduler.pending_player_views.is_empty())
	actors.a.body.free()
	print("TASK_WAIT_OBSERVATION_PASSED changed_visible_player_once_without_forcing_action")
	quit()

func finish_watch(scheduler: RefCounted, task: Dictionary, event_id: String, scope: String="existing_request") -> void:
	scheduler.finish_player_watch({"person_id":"a","event_id":event_id,"decision":{"task_handling":{"scope":scope}}},task)
