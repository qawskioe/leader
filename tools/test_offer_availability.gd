extends SceneTree
func _initialize():run.call_deferred()
func run():
 create_timer(15).timeout.connect(func():push_error("offer check timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","user://offer_check_%d.json"%Time.get_ticks_usec(),true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 sim.enabled=false
 var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
 var actor: Node3D=sim.actors.person_003.body;actor.rotation.y=0
 player.global_position=actor.global_position+Vector3(0,0,1.7);player.rotation=Vector3.ZERO;player.get_node("Eyes").rotation=Vector3.ZERO
 var bag: Dictionary=sim.water.bags["1"];bag.root.global_position=player.global_position+Vector3(0,.8,-.3)
 assert(sim.water.pickup("player","1"));sim.world_objects.sync_held("water_bag/1")
 assert(sim.gathering.offer_availability("person_003","water").ok)
 assert(sim.water.player_hint().begins_with("F · 递水袋"))
 var offer: String=sim.gathering.offer_item("person_003","water")
 assert(not offer.is_empty())
 sim.enabled=true;sim.gathering._physics_process(0);sim.enabled=false
 assert(sim.gathering.offers.has(offer),"等待监测必须使用与提交相同的范围，不能原地撤回")
 assert(sim.water.player_hint()=="已递出，正在等待对方决定")
 assert(not sim.gathering.resolve_offer(offer,"person_003",false).success and bag.holder=="player")
 offer=sim.gathering.offer_item("person_003","water")
 assert(not offer.is_empty())
 player.position.z+=1
 sim.enabled=true;sim.gathering._physics_process(0);sim.enabled=false
 assert(not sim.gathering.offers.has(offer) and bag.holder=="player")
 assert(not sim.gathering.offer_availability("person_003","water").ok)
 assert(not sim.water.player_hint().begins_with("F · 递水袋"))
 player.position.z-=1;sim.world_objects.sync_held("water_bag/1")
 var block:=RigidBody3D.new();scene.add_child(block);sim.world_objects.register_object("occupied_right",block)
 assert(sim.world_objects.attach_to("occupied_right","person_003","Hand.R",func():return actor.global_transform).ok)
 offer=sim.gathering.offer_item("person_003","water")
 assert(not offer.is_empty())
 assert(sim.gathering.resolve_offer(offer,"person_003",true).success)
 assert(bag.holder=="person_003" and sim.world_objects.objects["water_bag/1"].hand=="Hand.L")
 print("OFFER_AVAILABILITY_PASSED hint_submit_pending_decline_distance_accept_free_left")
 scene.queue_free();await process_frame;quit()
