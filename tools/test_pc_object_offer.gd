extends SceneTree
## 隔离PC准星选择与实体交接；接收决定为测试替身，不调用云端。
var sim: Node
var accept:=false
var offered_count:=0
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(30).timeout.connect(func():push_error("PC object offer timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","user://pc_object_offer_%d.json"%Time.get_ticks_usec(),true).is_empty())
	sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	var target:="person_003"
	var actor: Node3D=sim.actors[target].body
	actor.global_position=sim.STORAGE;actor.rotation=Vector3.ZERO
	player.global_position=sim.STORAGE+Vector3(0,0,1.4);player.rotation=Vector3.ZERO
	var camera: Camera3D=player.get_node("Eyes")
	camera.look_at(actor.global_position+Vector3(0,1.1,0))
	var basket: Dictionary=sim.gathering.baskets["1"]
	assert(sim.world_objects.attach_to("basket/1","player","Hand.R",sim.world_objects.player_hold_transform.bind("basket/1",player)).ok)
	sim.world_objects.sync_held("basket/1")
	sim.perception.observe(target)
	assert(sim.gathering.aimed_target()=="object_offer/"+target+"/basket/1","持篮面对人物必须能递交，不能选到空篮卸货")
	for condition in ["not_seen_by_recipient","recipient_busy"]:
		actor.rotation.y=PI if condition=="not_seen_by_recipient" else 0.0
		sim.actors[target].stage="walking" if condition=="recipient_busy" else "idle"
		var unavailable: Dictionary=sim.handover.player_offer_availability("basket/1",target)
		assert(not unavailable.ok and unavailable.code==condition)
		if sim.gathering.aimed_target()!="object_offer/"+target+"/basket/1":
			push_error("不可递交时仍须保留准星人物并解释原因，不能静默移除目标："+condition)
			scene.queue_free();await process_frame;quit(1);return
		sim.gathering._feedback=0
		Input.action_press("player_interact")
		sim.gathering._player_input(1.2)
		Input.action_release("player_interact")
		assert(sim.gathering.interaction_hint.text==unavailable.message,"正常按键提示须显示真实交接失败原因")
		assert(sim.handover.pending.is_empty() and basket.holder=="player" and offered_count==0,"失败提示不能提交决定或移动物品")
	actor.rotation.y=0;sim.actors[target].stage="idle"
	sim.gathering._player_input(0)
	assert("递篮子给" in sim.gathering.interaction_hint.text,"转身并空闲后须恢复正常递交提示")
	sim.handover.offered.connect(_answer)
	var declined: Dictionary=await sim.handover.give("player","basket/1",target)
	assert(not declined.ok and declined.code=="declined" and basket.holder=="player")
	assert(basket.contents.count==0)
	accept=true
	var received: Dictionary=await sim.handover.give("player","basket/1",target)
	assert(received.ok and basket.holder==target and basket.contents.count==0)
	assert(not (await sim.handover.give("player","basket/1",target)).ok,"同一物品不能重复转移")
	assert(offered_count==2)
	# 任意已登记的实体复用同一入口，不为篮子建立另一套交付实现。
	var block:=RigidBody3D.new();block.name="CarryBlock";block.set_meta("display_name","木块");scene.add_child(block)
	sim.world_objects.register_object("test_block",block)
	assert(sim.world_objects.attach_to("test_block","player","Hand.R",sim.world_objects.player_hold_transform.bind("test_block",player)).ok)
	sim.world_objects.sync_held("test_block");sim.perception.observe(target)
	assert(sim.gathering.aimed_target()=="object_offer/"+target+"/test_block")
	assert((await sim.handover.give("player","test_block",target)).ok)
	assert(sim.world_objects.objects.test_block.holder==target)
	assert(sim.world_objects.objects.test_block.hand=="Hand.L","接收者右手持篮时使用实际空闲左手")
	assert(offered_count==3 and not sim.perception.memories.has("player"),"PC交接不伪造角色记忆")
	print("PC_OBJECT_OFFER_PASSED aimed_basket_decline_accept_no_duplicate_generic_object_free_left")
	scene.queue_free();await process_frame;await process_frame;quit()
func _answer(event: Dictionary) -> void:
	offered_count+=1
	assert(event.item_kind=="object" and event.speaker=="player")
	var object: String=sim.handover.pending[event.id].object
	assert(not sim.handover.player_offer_availability(object,event.listeners[0]).ok,"等待接收时不能反复递交")
	sim.handover.respond.call_deferred(event.id,event.listeners[0],accept)
