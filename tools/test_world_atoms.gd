extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	create_timer(20).timeout.connect(func():push_error("world atoms timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize().is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	assert(sim.storage_contents.count==3 and sim.storage_food==3)
	assert(sim.world_objects.objects.has("basket/1") and sim.gathering.baskets["1"].body is RigidBody3D)
	assert(sim.life_world.supplies.size()==sim.gathering.resources.size()+1)
	print("WORLD_ATOMS_PASSED canonical_storage_rigid_baskets_registered_supplies")
	scene.queue_free();await process_frame;quit()
