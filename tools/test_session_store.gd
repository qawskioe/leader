extends SceneTree
const Session=preload("res://scripts/survival/session_store.gd")
func _initialize():run.call_deferred()
func run():
 create_timer(90).timeout.connect(func():push_error("session save timeout");quit(1))
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","",true).is_empty())
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 var library=load("res://scripts/skills/library.gd").new();assert(library.initialize("user://save_library_%d.json"%Time.get_ticks_usec(),store.people).is_empty());assert(library.install_builtins().is_empty())
 var id:="person_003";var actor: Dictionary=sim.actors[id]
 actor.body.global_position=sim.STORAGE+Vector3(0,.06,-.8);actor.body.rotation.y=0
 for i in 12:await physics_frame
 sim.perception.observe(id)
 assert(sim.life_world.take_unit(id,"storage").ok)
 sim.gathering.hands[id].visual.global_position=Vector3(0,2,10)
 assert(sim.gathering.drop_food(id))
 assert(sim.world_objects.attach_to("water_bag/1",id,"Hand.R",sim.water.hold_pose.bind(id)).ok)
 assert(sim.life_world.take_unit(id,"storage").ok)
 assert(sim.gathering.hands[id].hand=="Hand.L")
 scene.get_node("Player").global_position=sim.gathering.baskets["1"].root.global_position+Vector3(0,.1,-.7)
 assert(sim.gathering.pickup("player","1"))
 var fruit: Dictionary=sim.gathering.resources.values()[0];fruit.available=false;fruit.mesh.visible=false;fruit.body.collision_layer=0;fruit.regrow_at=sim.gathering.elapsed+100
 var original:={"id":"save_request","speaker":"player","text":"继续搬运","kind":"speech_intent"}
 store.hear(id,original);store.working_tasks[id]={"request":original,"state":"interrupted_save"}
 store.people[id].needs.hunger=72.0;sim.eaten=5;sim.water.player_thirst=63.0
 var before:=Session.capture(sim,library)
 var path:="user://sessions/test_%d.json"%Time.get_ticks_usec()
 assert(Session.save(path,sim,library).is_empty())
 sim.storage_contents.clear();sim.world_objects._detach("water_bag/1");sim.world_objects._detach("basket/1")
 store.working_tasks.clear();store.people[id].needs.hunger=1
 actor.body.position+=Vector3(4,0,0);fruit.available=true;sim.water.player_thirst=1
 var checked:=Session.read(path,sim);assert(checked.ok,str(checked.get("error")))
 Session.restore(sim,library,checked)
 assert(sim.storage_food==before.world.containers.storage.size() and sim.storage_food==1)
 assert(sim.gathering.loose_food.size()==1 and sim.gathering.hands[id].hand=="Hand.L")
 assert(sim.world_objects.objects["water_bag/1"].holder==id and sim.world_objects.objects["basket/1"].holder=="player")
 var saved_regrow: float=before.world.resources[sim.gathering.resources.keys()[0]].regrow_at
 print("RESTORED_RESOURCE available=",fruit.available," difference=",float(fruit.regrow_at)-saved_regrow)
 assert(not fruit.available and is_equal_approx(float(fruit.regrow_at),saved_regrow))
 assert(store.people[id].needs.hunger==72 and sim.eaten==5 and sim.water.player_thirst==63)
 assert(store.working_tasks[id].request.id==original.id and store.working_events[id][-1].event.id==original.id)
 assert(library.definitions.size()==before.skills.definitions.size())
 assert(scene.get_node("Player").is_physics_processing())
 var count: int=sim.storage_food
 var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string('{"schema":1,"sha256":"bad","payload":"{}"}');f.close()
 assert(not Session.read(path,sim).ok and sim.storage_food==count,"损坏存档在修改世界前拒绝")
 print("SESSION_STORE_PASSED world_food_water_holding_loose_food_resources_task_memory_skills_corrupt_rejected")
 scene.queue_free();await process_frame;quit()
