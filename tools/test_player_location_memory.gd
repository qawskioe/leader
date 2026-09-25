extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice);voice.set_process(false)
	while not voice.survival.ready_for_actions:await physics_frame
	var sim=voice.survival;var id:="person_001";var body: Node3D=sim.actors[id].body
	var player: Node3D=scene.get_node("Player")
	var original:=player.global_position
	var toward:=original-body.global_position;body.rotation.y=atan2(toward.x,toward.z)
	sim.perception.observe(id)
	assert(sim.perception.known(id,"person/player").visible_now)
	body.rotation.y+=PI
	player.global_position+=Vector3(20,0,0)
	sim._physics_process(6.0)
	var remembered: Dictionary=sim.perception.known(id,"person/player")
	assert(not remembered.is_empty() and not remembered.visible_now)
	assert(Vector3(remembered.position[0],remembered.position[1],remembered.position[2]).distance_to(original)<0.01)
	print("PLAYER_LOCATION_MEMORY_PASSED unseen_person_retained_without_tracking")
	scene.queue_free();await create_timer(0.2).timeout;quit()
