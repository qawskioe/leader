extends SceneTree
class Probe extends "res://scripts/voice/voice_test.gd":
	var dispatched: Array=[]
	func _start_pipeline(event: Dictionary, _job: Dictionary) -> void:dispatched.append(event)
class Starting extends Node:
	var pending:=true
	func is_starting() -> bool:return pending
	func cancel() -> void:pending=false
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("skill start priority timeout");quit(1))
	var runner=load("res://scripts/skills/luau_runtime.gd").new()
	runner.running=true;assert(runner.is_starting())
	runner._sequence=1;assert(not runner.is_starting(),"收到首条世界请求就不再阻塞新判断，不能等整个动作完成")
	runner.running=false;runner.free()
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=Probe.new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions:await physics_frame
	voice.config.local_only=false;voice.config.actions_enabled=true;voice.config.autonomy_enabled=false;voice.menu.close()
	var starting:=Starting.new();voice.add_child(starting);voice.skills.active.person_003=starting
	voice.autonomy.offer_request({"id":"old_followup","kind":"skill_progress","speaker":"world","listeners":["person_004"],"original_event":{"speaker":"player","id":"old","text":"旧任务"},"text":"旧结果"},0)
	voice._try_autonomy()
	assert(voice.dispatched.is_empty() and voice.autonomy.requests.size()==1,"不能在首条世界请求尚未到达时抢开另一轮模型")
	starting.pending=false
	# 世界请求到达并发出递物事件，正常排队入口必须先处理接收者。
	voice.survival.handover.pending.priority_offer={}
	voice._player_offers.append({"id":"priority_offer","kind":"item_offer","speaker":"person_003","listeners":["person_004"],"text":"实际递物请求夹具"})
	voice._process(0)
	assert(voice.dispatched.size()==1 and voice.dispatched[0].id=="priority_offer")
	assert(voice.autonomy.requests.size()==1,"背景任务保留，不能靠删除来制造优先级")
	voice.survival.handover.pending.clear();voice.skills.active.clear()
	print("SKILL_START_PRIORITY_PASSED_first_world_request_before_background_no_whole_action_block")
	scene.queue_free();await create_timer(0.2).timeout;quit()
