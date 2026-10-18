extends SceneTree
class Probe extends "res://scripts/voice/voice_test.gd":
	var delivered: Array=[]
	func _start_pipeline(event: Dictionary, _job: Dictionary) -> void: delivered.append(event.duplicate(true))
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("text input queue timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=Probe.new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions: await physics_frame
	voice.config.local_only=false;voice.config.autonomy_enabled=false
	voice.busy=true
	assert(voice.say_text("石头，过来").is_empty())
	assert(voice._queued_capture_count()==1 and voice.delivered.is_empty())
	var event: Dictionary=voice._pending_inputs[0].payload.text_event.duplicate(true)
	var original: Vector3=scene.get_node("Player").position
	scene.get_node("Player").position+=Vector3(30,0,0)
	assert("没有人听见" in voice.say_text("无人听见的句子"))
	assert(voice._queued_capture_count()==1,"无人听见不能入队或伪装完成")
	scene.get_node("Player").position=original+Vector3(0.1,0,0)
	assert(voice.say_text("第二句").is_empty())
	voice.busy=false;voice._process(0)
	assert(voice.delivered[0]==event,"转头移动不能重算已发送的话的空间信息")
	assert(voice._pending_inputs[0].payload.text_event.text=="第二句","保持发送顺序")
	assert(voice.say_text("第三句").is_empty())
	assert(voice.say_text("第四句").is_empty())
	assert(not voice.say_text("超过队列").is_empty())
	voice.cancel_interaction()
	assert(voice._pending_inputs.is_empty(),"取消必须丢弃排队文字")
	var input:=LineEdit.new();root.add_child(input);input.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner()==input)
	voice.menu.close();voice.busy=false;voice.config.actions_enabled=true
	# 排队入口夹具：不模拟物品已转移，只验证输入框不能饿死此前的接物判断。
	voice.survival.gathering.offers["typing_offer"]={"target":"person_003","expires":Time.get_ticks_msec()+10000,"decision_started":false}
	voice._queue_offer({"id":"typing_offer","kind":"item_offer","speaker":"player","listeners":["person_003"],"text":"此前已递出的物品"})
	assert(voice.say_text("排队的新话").is_empty())
	voice._process(0)
	voice.survival.gathering.offers.erase("typing_offer")
	assert(voice.delivered[-1].id=="typing_offer","输入下一句话时，已排队递物必须继续处理")
	assert(voice._queued_capture_count()==1,"按顺序接物不能删除排队玩家输入")
	voice._pending_inputs.clear()
	input.queue_free()
	print("TEXT_INPUT_QUEUE_PASSED snapshot_fifo_limit_cancel")
	scene.queue_free();await process_frame;quit()
