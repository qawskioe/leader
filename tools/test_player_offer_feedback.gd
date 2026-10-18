extends SceneTree

func _initialize() -> void:run.call_deferred()

func run() -> void:
	create_timer(15).timeout.connect(func():push_error("player offer feedback timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true;voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	var sim=voice.survival;sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	var target:="person_003";var actor: Dictionary=sim.actors[target]
	var at: Vector3=actor.body.to_global(Vector3(0,1.1,0.4))
	player.global_position=actor.body.global_position+Vector3(0,0,0.6)
	var bag: Dictionary=sim.water.bags["1"]
	bag.root.global_position=at;bag.contents.clear();bag.contents.add({"source":"fixture"})
	assert(sim.water.pickup("player","1"));bag.root.global_position=at
	var receipts: Array[Dictionary]=[]
	sim.gathering.interaction_result.connect(func(result: Dictionary):receipts.append(result.duplicate(true)))
	var offered: String=sim.gathering.offer_item(target,"water")
	assert(not offered.is_empty())
	sim.gathering.interaction_result.emit({"action":"递水袋","ok":true,"pending":true})
	assert("等待对方决定" in sim.gathering.interaction_hint.text)
	var refused: Dictionary=sim.gathering.resolve_offer(offered,target,false)
	assert(not refused.success and bag.holder=="player")
	if receipts.size()!=2 or receipts[-1].get("pending",true) or receipts[-1].get("offer_id")!=offered:
		push_error("实际拒绝没有结束玩家的等待提示")
		scene.queue_free();await process_frame;quit(1);return
	assert("拒绝" in sim.gathering.interaction_hint.text)
	offered=sim.gathering.offer_item(target,"water")
	assert(not offered.is_empty())
	sim.gathering.interaction_result.emit({"action":"递水袋","ok":true,"pending":true})
	voice._pending_inputs.clear()
	voice._resolve_player_offer({"event_id":offered,"person_id":target,"decision":{"offer_response":"accept"}})
	assert(bag.holder==target and bag.contents.count==1)
	assert(receipts[-1].ok and not receipts[-1].pending and receipts[-1].offer_id==offered)
	assert(sim.store.people[target].name in sim.gathering.interaction_hint.text and "等待" not in sim.gathering.interaction_hint.text)
	# 重复/迟到的旧回调不能盖掉玩家随后正在看的反馈。
	sim.gathering.interaction_result.emit({"action":"后来完成的取水","ok":true})
	var later: String=sim.gathering.interaction_hint.text
	var count:=receipts.size()
	assert(not sim.gathering.resolve_offer(offered,target,true).success)
	assert(receipts.size()==count and sim.gathering.interaction_hint.text==later)
	# 窗口失焦不延长已结束的结果；计时输入仍由原入口取消。
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	sim.gathering._player_input(2.1)
	assert(sim.gathering._feedback==0,"隐藏提示的反馈时间也必须流逝")
	print("PLAYER_OFFER_FEEDBACK_PASSED consent_result_decline_late_callback_hidden_expiry")
	scene.queue_free();await process_frame;quit()
