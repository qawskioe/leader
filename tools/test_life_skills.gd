extends SceneTree
var controller: Node
var sim: Node
var refs: Dictionary={}
func _initialize() -> void: run.call_deferred()
func invoke(id: String, args: Dictionary={}) -> Dictionary:
	var submitted: Dictionary=controller.invoke("person_003","life_"+id+"_"+str(Time.get_ticks_usec()),{"ref":refs[id],"arguments":args})
	assert(submitted.ok,JSON.stringify(submitted))
	var outcome: Dictionary=await controller.finished
	print("LIFE_RESULT ",id," ",JSON.stringify(outcome.runtime.get("returned",{"code":outcome.runtime.get("code"),"success":outcome.success})))
	return outcome
func run() -> void:
	create_timer(170).timeout.connect(func():push_error("life skills timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;sim.move_speed=4;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/life_"+str(Time.get_ticks_usec())+".json").is_empty())
	assert(controller.library.install_builtins().is_empty())
	controller.sync_person("person_003")
	for definition in controller.library.describe("person_003"):refs[controller.library.definitions[definition.ref].id]=definition.ref
	assert(refs.has("eat") and refs.has("gather_food") and refs.has("fetch_water"))
	var actor: Node3D=sim.actors.person_003.body
	actor.global_position=sim.STORAGE+Vector3(0,0,-0.8);actor.rotation.y=PI/2
	for frame in 10:await physics_frame
	store.people.person_003.needs.hunger=80
	var before: int=sim.storage_food
	var eaten: Dictionary=await invoke("eat")
	if not eaten.success:push_error("eat failed");quit(1);return
	assert(sim.storage_food==before-1 and sim.eaten==1 and store.people.person_003.needs.hunger==35 and sim.gathering.hands.get("person_003",{}).is_empty())
	var fetched: Dictionary=await invoke("fetch_food")
	assert(fetched.success and sim.storage_food==before-2)
	var stored: Dictionary=await invoke("store_held_food")
	if not stored.success:print("STORE_FAILURE ",JSON.stringify(stored.runtime));quit(1);return
	assert(stored.success and sim.storage_food==before-1 and sim.gathering.hands.get("person_003",{}).is_empty())
	actor.global_position=sim.water.SOURCE+Vector3(0,0.6,-0.65);actor.rotation.y=0
	for frame in 30:await physics_frame
	store.people.person_003.needs.thirst=80
	var drunk: Dictionary=await invoke("drink")
	if not drunk.success:push_error("drink failed");quit(1);return
	assert(sim.water.consumed==1 and store.people.person_003.needs.thirst<40)
	print("LIFE_SKILLS_PASSED real_luau_take_contact_consume_food_water")
	scene.queue_free();await create_timer(0.2).timeout;quit()
