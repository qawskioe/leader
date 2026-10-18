extends SceneTree

class Probe extends "res://scripts/voice/voice_test.gd":
	var delivered: Array[Dictionary]=[]
	func _start_pipeline(event: Dictionary, _job: Dictionary) -> void:
		delivered.append(event.duplicate(true))

func _initialize() -> void: run.call_deferred()

func run() -> void:
	create_timer(12).timeout.connect(func():push_error("player input order timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=Probe.new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions:await physics_frame
	voice.config.local_only=false;voice.config.autonomy_enabled=false;voice.config.actions_enabled=true
	voice.survival.enabled=false
	voice.menu.close();voice.busy=true
	assert(voice.say_text("石头，接住水袋后先保管，暂时不要喝。").is_empty())
	var first: Dictionary=voice._pending_inputs[0].payload.text_event.duplicate(true)
	voice.survival.gathering.offers["later_offer"]={"target":"person_001","expires":Time.get_ticks_msec()+10000,"decision_started":false}
	voice._queue_offer({"id":"later_offer","kind":"item_offer","speaker":"player","listeners":["person_001"],"text":"随后递出水袋"})
	voice.busy=false;voice._process(0)
	assert(voice.delivered.size()==1 and voice.delivered[0].id==first.id,"后发生的递物不能超越先前玩家原话")
	voice.busy=false;voice._process(0)
	assert(voice.delivered[-1].id=="later_offer","之后仍须处理真实递物，不能靠丢弃事件通过")
	assert(voice.say_text("接物以后还是先保管。").is_empty())
	var second: Dictionary=voice._pending_inputs[0].payload.text_event.duplicate(true)
	voice._queue_offer({"id":"later_offer_result","kind":"received_water","speaker":"world","listeners":["person_001"],"text":"实际已接收水袋"})
	voice.busy=false;voice._process(0)
	assert(voice.delivered[-1].id==second.id,"交付结果也不能越过已经发送的后续教导")
	voice.busy=false;voice._process(0)
	assert(voice.delivered[-1].id=="later_offer_result")
	assert(voice._pending_inputs.is_empty())
	# 反向顺序同样保持FIFO，不把所有玩家话语硬置于物理事件之前。
	voice._queue_offer({"id":"earlier_receipt","kind":"received_item","speaker":"world","listeners":["person_001"],"text":"早先的实际交付"})
	assert(voice.say_text("后来才说的话。").is_empty())
	var third: Dictionary=voice._pending_inputs[1].payload.text_event.duplicate(true)
	voice.busy=false;voice._process(0)
	assert(voice.delivered[-1].id=="earlier_receipt")
	voice.busy=false;voice._process(0)
	assert(voice.delivered[-1].id==third.id and voice._pending_inputs.is_empty())
	# 无玩家待处理时，NPC接物和世界回执仍保持原有顺序。
	voice.survival.gathering.offers["npc_only"]={"target":"person_001","expires":Time.get_ticks_msec()+10000,"decision_started":false}
	voice._queue_offer({"id":"npc_only","kind":"item_offer","speaker":"person_002","listeners":["person_001"],"text":"同伴递物"})
	voice._queue_offer({"id":"after_npc_receipt","kind":"received_item","speaker":"world","listeners":["person_001"],"text":"后来的实际交付"})
	voice.busy=false;voice._process(0)
	assert(voice.delivered[-1].id=="npc_only","无玩家输入时不应重排NPC及世界回执")
	voice.busy=false;voice._process(0)
	assert(voice.delivered[-1].id=="after_npc_receipt" and voice._pending_inputs.is_empty())
	# 玩家可以越过未派发NPC接物，但不能越过比自己更早的真实交付。
	voice.survival.gathering.offers["deferred_npc"]={"target":"person_001","expires":Time.get_ticks_msec()+10000,"decision_started":false}
	voice._queue_offer({"id":"deferred_npc","kind":"item_offer","speaker":"person_002","listeners":["person_001"],"text":"待判断同伴递物"})
	voice._queue_offer({"id":"before_player_receipt","kind":"received_item","speaker":"world","listeners":["person_001"],"text":"玩家说话前的实际交付"})
	assert(voice.say_text("随后提交的玩家话语").is_empty())
	var fourth: Dictionary=voice._pending_inputs[2].payload.text_event.duplicate(true)
	for expected in ["before_player_receipt",fourth.id,"deferred_npc"]:
		voice.busy=false;voice._process(0)
		assert(voice.delivered[-1].id==expected,"延期NPC时仍须保留真实交付与玩家输入的相对顺序")
	assert(voice._pending_inputs.is_empty())
	voice.survival.gathering.offers.clear()
	print("PLAYER_INPUT_ORDER_PASSED speech_offer_receipt_fifo_no_loss_original_snapshot")
	scene.queue_free();await process_frame;quit()
