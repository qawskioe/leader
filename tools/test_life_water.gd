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
	create_timer(240).timeout.connect(func():push_error("life skills timeout");quit(1))
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
	actor.global_position=sim.water.bags["1"].root.global_position+Vector3(0,0.1,-0.8);actor.rotation.y=0
	for frame in 30:await physics_frame
	var outcome: Dictionary=await invoke("fetch_water")
	if not outcome.success:
		var file:=FileAccess.open("res://services/text-gateway/runtime/water_failure.json",FileAccess.WRITE);file.store_string(JSON.stringify(outcome,"  "));file.close()
		push_error("fetch water failed");quit(1);return
	var bag: Dictionary=sim.water.bags[str(outcome.runtime.returned.object).trim_prefix("water_bag/")]
	assert(sim.water.drawn>0 and bag.contents.count>0 and bag.holder=="")
	print("LIFE_WATER_PASSED real_luau_fill_carry_release")
	scene.queue_free();await create_timer(0.2).timeout;quit()
