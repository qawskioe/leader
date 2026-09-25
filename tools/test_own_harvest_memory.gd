extends SceneTree
const Store=preload("res://scripts/voice/people_store.gd")
const Sim=preload("res://scripts/survival/simulation.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate(); root.add_child(scene)
	var store:=Store.new(); assert(store.initialize().is_empty())
	var sim:=Sim.new(); sim.scene=scene; sim.store=store; sim.enabled=false; scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var body: CharacterBody3D=sim.actors.person_003.body
	body.position=sim.gathering.baskets["1"].root.global_position+Vector3(0,0.1,1.1)
	await physics_frame
	assert(sim.gathering.pickup("person_003","1"))
	var key: String=sim.gathering.resources.keys()[0]
	var at: Vector3=sim.gathering.resources[key].mesh.global_position
	body.position=Vector3(at.x,0.5,at.z+1.15); body.rotation.y=PI
	await physics_frame
	assert(sim.gathering.harvest("person_003",key))
	assert(not sim.perception.known("person_003","fruit/"+key).available)
	assert(sim.gathering.reserve_fruit("person_003")!=key,"不会重复采自己刚摘掉的果实")
	print("OWN_HARVEST_MEMORY_PASSED")
	scene.queue_free(); await create_timer(0.2).timeout; quit()
