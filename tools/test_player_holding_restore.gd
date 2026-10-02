extends SceneTree
## 隔离夹具：正常递交/拿取后，比较正式存档恢复前后的持物姿态。
const Session=preload("res://scripts/survival/session_store.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	create_timer(60).timeout.connect(func():push_error("player holding restore timeout");quit(1))
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();assert(store.initialize("res://data/people.json","",true).is_empty())
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	sim.enabled=false
	var player: Node3D=scene.get_node("Player");player.set_physics_process(false)
	var library=load("res://scripts/skills/library.gd").new()
	assert(library.initialize("user://holding_library_%d.json"%Time.get_ticks_usec(),store.people).is_empty())
	assert(library.install_builtins().is_empty())
	var objects: Node=sim.world_objects
	for kind in ["received_basket","picked_basket","received_water"]:
		player.global_position=Vector3(0,0.1,23.2);player.rotation=Vector3(0,0.4,0);player.get_node("Eyes").rotation.x=-0.3
		var key: String="water_bag/1" if kind=="received_water" else "basket/1"
		if kind=="picked_basket":
			player.global_position=sim.gathering.baskets["1"].root.global_position+Vector3(0,0,1.1)
			assert(sim.gathering.pickup("player","1"))
		else:
			sim.actors.person_003.body.global_position=Vector3(0,0.1,22)
			sim.actors.person_003.body.rotation=Vector3.ZERO
			sim.perception.observe("person_003")
			assert(objects.attach_to(key,"person_003","Hand.R",sim.water.hold_pose.bind("person_003")).ok)
			assert((await sim.handover.give("person_003",key,"player")).ok)
		var expected: Array=[]
		var hand: String=objects.objects[key].hand
		for pitch in [-0.3,0.35]:
			player.get_node("Eyes").rotation.x=pitch;objects.sync_held(key)
			expected.append(objects.objects[key].body.global_transform)
		var path:="user://sessions/holding_%d.json"%Time.get_ticks_usec()
		assert(Session.save(path,sim,library).is_empty())
		var checked:=Session.read(path,sim);assert(checked.ok,str(checked.get("error")))
		objects._detach(key);Session.restore(sim,library,checked);player.set_physics_process(false)
		for i in 2:
			player.get_node("Eyes").rotation.x=[-0.3,0.35][i];objects.sync_held(key)
			var actual: Transform3D=objects.objects[key].body.global_transform
			if not actual.is_equal_approx(expected[i]):
				push_error("持物恢复改变姿态：%s hand=%s before=%s after=%s"%[kind,hand,expected[i].origin,actual.origin]);quit(1);return
		assert(objects.objects[key].hand==hand)
		objects._detach(key)
	print("PLAYER_HOLDING_RESTORE_PASSED receive_pickup_save_load_pitch_same_hand_same_pose")
	scene.queue_free();await process_frame;quit()
