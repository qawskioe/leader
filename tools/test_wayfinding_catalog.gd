extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(45).timeout.connect(func():push_error("wayfinding catalog timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","user://wayfinding_%d.json"%Time.get_ticks_usec(),true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.hunger_rate=0;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var controller=load("res://scripts/skills/controller.gd").new();controller.sim=sim;controller.store=store;scene.add_child(controller)
	assert(controller.initialize("user://skills/wayfinding_%d.json"%Time.get_ticks_usec()).is_empty())
	assert(controller.library.install_builtins().is_empty())
	var ref:=""
	for id in store.people:
		controller.sync_person(id)
		var matches: Array=store.people[id].available_skills.filter(func(skill):return skill.id=="go_to_known")
		assert(matches.size()==1 and matches[0].callable and not matches[0].internal,"四人的日常目录均应开放已有连续寻路能力")
		if id=="person_003":ref=matches[0].ref
	var actor: Node3D=sim.actors.person_003.body
	actor.global_position=sim.STORAGE+Vector3(0,.06,-4);actor.rotation.y=0
	for frame in 12:await physics_frame
	sim.perception.observe("person_003")
	var inventory: int=sim.storage_food
	var before: Vector3=actor.global_position
	var unknown: Dictionary=controller.invoke("person_003","fixture_unknown_destination",{"ref":ref,"arguments":{"object":"not_known_by_role","distance":1.5}})
	assert(not unknown.ok and controller.active.is_empty(),JSON.stringify(unknown))
	assert(Vector2(actor.global_position.x-before.x,actor.global_position.z-before.z).length()<.1,"未知目标不能读取真实位置后自动追踪")
	assert(controller.invoke("person_003","fixture_known_storage",{"ref":ref,"arguments":{"object":"storage","distance":1.5}}).ok)
	var reached: Dictionary=await controller.finished
	assert(reached.success and reached.runtime.returned.code=="at_remembered_location",JSON.stringify(reached.runtime))
	assert(Vector2(actor.global_position.x-sim.STORAGE.x,actor.global_position.z-sim.STORAGE.z).length()<1.6)
	assert(sim.storage_food==inventory and reached.world_facts.is_empty(),"寻路不得取物或结算资源")
	print("WAYFINDING_CATALOG_PASSED daily_visible_callable_unknown_rejected_actual_walk_no_resources")
	scene.queue_free();await create_timer(.2).timeout;quit()
