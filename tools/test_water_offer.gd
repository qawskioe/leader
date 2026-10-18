extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(15).timeout.connect(func():push_error("water offer timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	voice.set_process(false);voice.config.local_only=true;voice.config.autonomy_enabled=false
	while not voice.survival.ready_for_actions:await physics_frame
	var sim=voice.survival;sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	var target: String="person_003"
	var actor: Dictionary=sim.actors[target]
	var at: Vector3=actor.body.to_global(Vector3(0,1.1,0.4))
	player.global_position=actor.body.global_position+Vector3(0,0,0.6)
	var bag: Dictionary=sim.water.bags["1"]
	bag.root.global_position=at;bag.contents.clear();bag.contents.add({"source":"fixture"});bag.contents.add({"source":"fixture"})
	assert(sim.water.pickup("player","1"));bag.root.global_position=at
	var offered: String=sim.gathering.offer_item(target,"water")
	assert(offered!="" and bag.holder=="player","递出不是已经转移")
	assert(voice._pending_inputs.back().payload.item_kind=="water")
	assert(not sim.gathering.resolve_offer(offered,target,false).success)
	assert(bag.holder=="player" and bag.contents.count==2)
	offered=sim.gathering.offer_item(target,"water")
	sim.gathering.offers[offered].expires=Time.get_ticks_msec()-1
	assert(not sim.gathering.resolve_offer(offered,target,true).success)
	offered=sim.gathering.offer_item(target,"water")
	player.global_position+=Vector3(3,0,0)
	assert(not sim.gathering.resolve_offer(offered,target,true).success)
	assert(bag.holder=="player")
	player.global_position-=Vector3(3,0,0)
	bag.root.global_position=at
	offered=sim.gathering.offer_item(target,"water")
	assert(sim.world_objects.release("water_bag/1","player").ok)
	assert(not sim.gathering.resolve_offer(offered,target,true).success,"放下后迟到答复不能交付")
	bag.root.global_position=at
	assert(sim.water.pickup("player","1"));bag.root.global_position=at
	offered=sim.gathering.offer_item(target,"water")
	actor.stage="skill"
	assert(not sim.gathering.resolve_offer(offered,target,true).success,"接收者占用不能强塞")
	actor.stage="idle"
	offered=sim.gathering.offer_item(target,"water")
	voice._pending_inputs.clear()
	voice._resolve_player_offer({"event_id":offered,"person_id":target,"decision":{"offer_response":"accept"}})
	assert(bag.holder==target and bag.contents.count==2)
	assert(voice._pending_inputs.size()==1 and voice._pending_inputs[0].payload.kind=="received_water")
	assert(not sim.gathering.resolve_offer(offered,target,true).success,"不能重复转移")
	# 空袋同样是可交付的物品，接受并不意味着自动生成水。
	assert(sim.world_objects.release("water_bag/1",target).ok)
	bag.contents.clear();bag.root.global_position=at
	assert(sim.water.pickup("player","1"));bag.root.global_position=at
	offered=sim.gathering.offer_item(target,"water")
	assert(sim.gathering.resolve_offer(offered,target,true).success and bag.contents.count==0)
	# 已知但未注册的测试物品不能把接口缺口误报成物品消失。
	voice.skills.ensure_luau_world()
	var adapter=load("res://scripts/skills/luau_world_adapter.gd").new()
	adapter.sim=sim;adapter.person_id=target;adapter.objects=voice.skills.world_objects;adapter._owned=true
	var unknown: Dictionary=await adapter.request("observe",{"object":"unseen_bag"})
	assert(unknown.code=="not_observed")
	sim.perception._record(target,"known_unregistered","object",actor.body.global_position,true,{})
	var unsupported: Dictionary=await adapter.request("observe",{"object":"known_unregistered"})
	assert(unsupported.code=="unsupported_interaction" and not unsupported.message.is_empty())
	assert(bag.holder==target and bag.contents.count==0,"能力检查不能改变物品")
	assert(voice.skills.library.describe(target).any(func(entry):return entry.has("object_requirement")))
	adapter.free()
	print("WATER_OFFER_PASSED consent_decline_expiry_withdraw_busy_received_water_no_duplication_empty_container")
	scene.queue_free();await create_timer(0.2).timeout;quit()
