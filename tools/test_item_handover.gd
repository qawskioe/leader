extends SceneTree
var voice: Node
var mode:="accept"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(35).timeout.connect(func():push_error("item handover timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true;voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	var sim=voice.survival;voice.skills.ensure_luau_world()
	var giver:="person_003";var recipient:="person_002"
	sim.actors[giver].body.global_position=Vector3(3,0,6);sim.actors[giver].body.rotation.y=0
	var player=scene.get_node("Player");player.set_physics_process(false);player.global_position=Vector3(3,0,7.5)
	assert(sim.water.pickup(giver,"1"))
	sim.perception.observe(giver)
	var ref:=""
	for skill in voice.skills.library.describe(giver):
		if voice.skills.library.definitions[skill.ref].id=="give_object":ref=skill.ref
	assert(not ref.is_empty())
	var submitted: Dictionary=voice.skills.invoke(giver,"empty_bag",{"ref":ref,"arguments":{"object":"water_bag/1","recipient":"player"}})
	assert(submitted.ok,JSON.stringify(submitted))
	var actual: Dictionary=await voice.skills.finished
	assert(actual.success and sim.water.held("player")=="1",JSON.stringify(actual))
	assert(actual.runtime.trace.any(func(step):return step.operation=="handover" and step.result.ok),"交接依据真实世界操作回执")
	assert(sim.water.bags["1"].contents.count==0 and sim.water.drawn==0,"交空袋不能先去取水或生成水")
	assert(sim.water.drop("player"))
	# 同一入口对另一种注册物体成立；这里明确是离线交接/决策夹具。
	var block:=RigidBody3D.new();scene.add_child(block)
	sim.world_objects.register_object("test_block",block)
	var occupied_left:=RigidBody3D.new();scene.add_child(occupied_left);sim.world_objects.register_object("occupied_left",occupied_left)
	sim.handover.offered.connect(func(event): reply.call_deferred(event))
	for answer in ["decline","occupied","right_occupied","withdraw","expire","accept"]:
		mode=answer
		sim.actors[recipient].body.global_position=Vector3(3,0,7.3);sim.actors[recipient].body.rotation.y=PI
		sim.perception.observe(giver)
		assert(sim.world_objects.attach_to("test_block",giver,"Hand.R",sim.water.hold_pose.bind(giver)).ok)
		var outcome: Dictionary=await sim.handover.give(giver,"test_block",recipient)
		assert(outcome.ok==(answer in ["accept","right_occupied"]),JSON.stringify(outcome))
		assert(outcome.code=={"decline":"declined","occupied":"recipient_occupied","withdraw":"not_held","expire":"offer_expired","accept":"transferred","right_occupied":"transferred"}[answer],JSON.stringify(outcome))
		assert(sim.world_objects.objects.test_block.holder==(recipient if answer in ["accept","right_occupied"] else "" if answer=="withdraw" else giver))
		if answer=="accept":
			assert(not sim.water.free_hand(recipient,"Hand.R"),"接收后右手确实被占用，不能覆盖同一只手")
			assert(voice._pending_inputs.any(func(entry):return entry.payload.get("kind")=="received_item"))
		if answer=="right_occupied":
			assert(sim.world_objects.objects.test_block.hand=="Hand.L" and sim.gathering.hands.has(recipient),"左手接物不得覆盖右手原物资")
			var expected: Transform3D=sim.world_objects.carry_transform("test_block",sim.actors[recipient].body,"Hand.L")
			assert(sim.world_objects.objects.test_block.body.global_transform.is_equal_approx(expected),"接收后必须使用固定携带槽")
		if sim.world_objects.objects.occupied_left.holder!="":sim.world_objects.release("occupied_left",recipient)
		if sim.gathering.hands.has(recipient):sim.gathering.hands[recipient].visual.queue_free()
		sim.gathering.hands.erase(recipient)
		if sim.world_objects.objects.test_block.holder!="":sim.world_objects.release("test_block",sim.world_objects.objects.test_block.holder)
	assert(sim.world_objects.attach_to("test_block",giver,"Hand.R",sim.water.hold_pose.bind(giver)).ok)
	player.global_position=Vector3(20,0,7)
	var far: Dictionary=await sim.handover.give(giver,"test_block","player")
	assert(not far.ok and far.code=="out_of_reach" and sim.world_objects.objects.test_block.holder==giver)
	player.global_position=Vector3(3,0,7.5)
	assert((await sim.handover.give(giver,"test_block","player")).ok)
	# headless无法进入鼠标捕获态；这里只验证G所用的物理操作，按键在实际场景验证。
	assert(sim.world_objects.drop_held("player").ok)
	assert(sim.world_objects.objects.test_block.holder=="" and not block.freeze,"收到的普通物品必须可解除持有")
	mode="accept"
	assert(sim.world_objects.attach_to("occupied_left",recipient,"Hand.R",sim.water.hold_pose.bind(recipient)).ok)
	var food:=Node3D.new();scene.add_child(food);food.global_position=sim.water.hold_pose(giver).origin
	sim.gathering.hands[giver]={"material":"food","origin":{},"visual":food,"hand":"Hand.R"}
	sim.perception.observe(giver)
	var given: Dictionary=await sim.handover.give_unit(giver,recipient)
	assert(given.ok and not sim.gathering.hands.has(giver))
	assert(sim.gathering.hands[recipient].hand=="Hand.L" and not sim.water.free_hand(recipient,"Hand.L"))
	print("UNIT_LEFT_HAND_TRANSFER_PASSED")
	print("ITEM_HANDOVER_PASSED actual_luau_empty_bag_generic_object_consent_decline_both_occupied_left_hand_withdraw_expiry_distance")
	scene.queue_free();await create_timer(0.2).timeout;quit()

func reply(event: Dictionary) -> void:
	var sim=voice.survival
	voice._round_events[event.id]=event
	if mode in ["occupied","right_occupied"]:
		var visual:=Node3D.new();voice.get_parent().add_child(visual)
		sim.gathering.hands[event.listeners[0]]={"material":"food","origin":{},"visual":visual}
	if mode=="occupied":assert(sim.world_objects.attach_to("occupied_left",event.listeners[0],"Hand.L",sim.water.hold_pose.bind(event.listeners[0])).ok)
	if mode=="withdraw":sim.world_objects.release("test_block",event.speaker)
	if mode=="expire":sim.handover.pending[event.id].expires=0
	voice._resolve_player_offer({"event_id":event.id,"person_id":event.listeners[0],"decision":{"offer_response":"decline" if mode=="decline" else "accept"}})
