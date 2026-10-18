extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
const Hands=preload("res://scripts/vr/hand_interaction.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(35).timeout.connect(func():push_error("VR grab fixture timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var store=Store.new()
	assert(store.initialize().is_empty())
	var sim=Sim.new()
	sim.scene=scene; sim.store=store; scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var player=scene.get_node("Player")
	player.set_physics_process(false)
	var hands=Hands.new(); hands.sim=sim
	var basket: Dictionary=sim.gathering.baskets["1"]
	player.global_position=basket.root.global_position+Vector3(0,0,1)
	assert(hands.grab("left",Vector3(1000,1000,1000)).begins_with("手靠近"))
	hands.grab("left",basket.root.to_global(Vector3(-0.34,0.4,0)))
	assert(basket.holder=="player" and hands.held.left.kind=="basket")
	assert(not sim.gathering.pickup("person_003","1"))
	var key: String=sim.gathering.resources.keys()[0]
	var fruit: Dictionary=sim.gathering.resources[key]
	player.global_position=fruit.mesh.global_position+Vector3(0,-0.6,0.7)
	hands.grab("right",fruit.mesh.global_position)
	assert(sim.gathering.hands.has("player") and not fruit.available)
	assert(not sim.gathering.harvest("player",key))
	# 空处松开和再次拿取另由test_vr_loose_food验证；这里继续验证真实装篮和递交。
	await physics_frame
	await physics_frame
	assert(hands.release("right",basket.root.global_position+Vector3(0,0.25,0))=="已装篮")
	assert(basket.contents.items.size()==1 and not sim.gathering.hands.has("player"))
	assert(basket.contents.items[0].origin.resource_id==key)
	# 放在地上的篮子也可独立取出内容物；中心不再选择容器。
	basket.holder=""; basket.reserved=""; hands.held.erase("left")
	player.global_position=basket.root.global_position+Vector3(0,0,1)
	var visual: Node3D=basket.contents.items[0].visual
	assert(hands.candidate(visual.global_position)[0]=="contained")
	hands.grab("right",visual.global_position)
	assert(basket.contents.items.is_empty() and sim.gathering.hands.player.visual==visual)
	assert(hands.release("right",basket.root.to_global(Vector3(0,0.25,0)))=="已装篮")
	assert(basket.contents.items.size()==1 and basket.contents.items[0].visual==visual)
	hands.grab("right",visual.global_position)
	var target: String="person_003"
	var at: Vector3=sim.actors[target].body.to_global(Vector3(0,1.1,0.4))
	player.global_position=sim.actors[target].body.global_position+Vector3(0,0,0.6)
	visual.global_position=at
	var offer: String=sim.gathering.offer_food(target)
	assert(offer!="")
	assert(not sim.gathering.resolve_offer(offer,target,false).success)
	assert(sim.gathering.hands.has("player") and sim.actors[target].carried==0)
	offer=sim.gathering.offer_food(target)
	var cancelled: Array=[]
	sim.gathering.interaction_result.connect(func(r):cancelled.append(r))
	visual.global_position=at+Vector3(3,0,0)
	sim.gathering._physics_process(0)
	assert(not sim.gathering.offers.has(offer))
	assert(cancelled.size()==1 and cancelled[0].message.contains("撤回"))
	sim.gathering._physics_process(0)
	assert(cancelled.size()==1,"撤回提示不能每帧重复")
	assert(not sim.gathering.resolve_offer(offer,target,true).success)
	visual.global_position=at
	offer=sim.gathering.offer_food(target)
	sim.gathering.offers[offer].expires=Time.get_ticks_msec()-1
	sim.gathering._physics_process(0)
	assert(cancelled.size()==2 and cancelled[1].message.contains("超时"))
	assert(not sim.gathering.resolve_offer(offer,target,true).success)
	assert(sim.gathering.hands.has("player") and sim.actors[target].carried==0)
	visual.global_position=at
	offer=sim.gathering.offer_food(target)
	assert(offer!="")
	if OS.get_cmdline_user_args().has("--cloud"):
		# 模型等待期间冻结夹具的物理位置；实际运行仍会持续检查撤回和距离。
		sim.enabled=false
		var gateway=load("res://scripts/voice/text_gateway_client.gd").new(); root.add_child(gateway)
		var event:={"id":offer,"kind":"item_offer","speaker":"player","text":"玩家把一颗食物递到你面前，仍在玩家手里。请决定接受还是拒绝，尚未交付。"}
		var pipeline=load("res://scripts/voice/decision_pipeline.gd")
		var response: Dictionary=await gateway.exchange({"mode":"decision","prompt":pipeline.prompt_for(store.context_for(target),event)})
		assert(response.ok)
		print("OFFER_RAW ",response.text)
		var decision: Dictionary=load("res://scripts/voice/cloud_client.gd").validate_decision(response.text,true,true)
		if not decision.ok:
			push_error(str(decision)); quit(1); return
		print("OFFER_LIVE ",JSON.stringify(decision.decision))
		assert(decision.decision.offer_response=="accept","本次无冲突的饥饿角色应接受递来的食物")
		# 等待真实模型时不让测试提议过期；只影响夹具，不改变正式45秒期限。
		sim.gathering.offers[offer].expires=Time.get_ticks_msec()+1000
	var outcome: Dictionary=sim.gathering.resolve_offer(offer,target,true)
	assert(outcome.success and sim.actors[target].carried==1)
	assert(not sim.gathering.hands.has("player") and sim.actors[target].food_origin.resource_id==key)
	assert(sim.actors[target].food_origin.giver_id=="player")
	assert(not sim.gathering.resolve_offer(offer,target,true).success)
	hands.reconcile(); assert(not hands.held.has("right"))
	print("VR_GRAB_PASSED proximity, ownership, harvest, no duplication, release proximity, provenance")
	scene.queue_free(); await process_frame; quit()
