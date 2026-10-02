extends SceneTree
## 隔离夹具：实际NPC交接入口把篮子交到玩家右手，再验证玩家采摘装篮。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(45).timeout.connect(func():push_error("received basket test timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	var giver:="person_003"
	sim.actors[giver].body.global_position=Vector3(0,0.1,22);sim.actors[giver].body.rotation=Vector3.ZERO
	player.global_position=Vector3(0,0.1,23.2)
	sim.perception.observe(giver)
	assert(sim.world_objects.attach_to("basket/1",giver,"Hand.R",sim.water.hold_pose.bind(giver)).ok)
	var given: Dictionary=await sim.handover.give(giver,"basket/1","player")
	assert(given.ok and sim.world_objects.objects["basket/1"].hand=="Hand.R")
	var gather: Node=sim.gathering
	var fruit_key: String=gather.resources.keys()[0]
	var at: Vector3=gather.resources[fruit_key].mesh.global_position
	player.global_position=at+Vector3(0,-1.1,1)
	sim.world_objects.sync_held("basket/1")
	assert(gather._reachable("player",at),"采摘前距离与遮挡必须合法，不能把它们误判为空手问题")
	if not gather.harvest("player",fruit_key):
		push_error("右手接到篮子、左手空闲时仍无法采摘；free_unit_hand="+gather.free_unit_hand("player"));quit(1);return
	assert(gather.hands.player.hand=="Hand.L")
	assert(sim.world_objects.objects["basket/1"].hand=="Hand.R")
	assert(gather.free_unit_hand("player")=="" and not gather.harvest("player",fruit_key))
	sim.enabled=true;gather._physics_process(0);sim.enabled=false
	assert(player.get_node("Eyes").to_local(gather.hands.player.visual.global_position).x<0,"左手物资应显示在左侧")
	assert(gather.load_hand("player","1"))
	assert(gather.baskets["1"].contents.count==1 and not gather.hands.has("player"))
	assert(gather.baskets["1"].contents.items[0].origin.resource_id==fruit_key)
	assert(gather.free_unit_hand("player")=="Hand.L" and sim.storage_food==3)
	print("PLAYER_RECEIVED_BASKET_PASSED real_transfer_right_basket_left_harvest_visual_load_origin_no_duplication")
	scene.queue_free();await create_timer(0.2).timeout;quit()
