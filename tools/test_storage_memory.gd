extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.enabled=false;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var id:="person_001"
	for who in [id,"person_002"]:
		sim.perception._record(who,"storage","storage",sim.STORAGE,true,{"food_count":3})
	sim.storage_contents.clear();sim._refresh_visuals()
	var actor: Dictionary=sim.actors[id]
	actor.body.global_position=sim.STORAGE+Vector3(0.8,0,0)
	sim.perception.note_storage_action(id,0)
	assert(sim.perception.known(id,"storage").extra.food_count==0)
	assert(store.memory.observations[id].storage.extra.food_count==0)
	assert(not store.memory.observations[id].storage.available)
	assert(store.memory.observations.person_002.storage.extra.food_count==3,"未目击者不能自动获得新库存")
	var remembered: Array=store.memory.retained(id,"landmark")
	var found:=false
	for record in remembered:
		if record.id=="storage":found=true;assert(record.extra.food_count==0)
	assert(found)
	sim.perception.note_storage_action(id,1)
	assert(store.memory.observations[id].storage.extra.food_count==null,"放入一份不能声称知道总量")
	assert(store.memory.observations[id].storage.extra.own_transfer==1)
	sim.perception.note_storage_action(id,-1)
	assert(store.memory.observations[id].storage.available==null)
	assert(store.memory.observations[id].storage.extra.own_transfer==-1)
	print("STORAGE_MEMORY_PASSED empty_check_persisted_owner_only_no_omniscient_total")
	scene.queue_free();await process_frame;quit()
