extends SceneTree
const Snapshot=preload("res://scripts/skills/verification_snapshot.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=preload("res://scripts/voice/people_store.gd").new()
	assert(store.initialize("res://data/people.json","user://snapshot_memory_%d.json"%Time.get_ticks_usec(),true).is_empty())
	var sim=preload("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;sim.enabled=false;scene.add_child(sim)
	while not sim.ready_for_actions:await physics_frame
	var person:="person_004"
	store.memory.advance(float(store.memory.policy.day_seconds)*2+100)
	sim.perception.clock=store.memory.clock
	var target:="person/person_003"
	sim.perception._record(person,target,"person",sim.actors.person_003.body.global_position,true)
	var data: Dictionary=Snapshot.capture(sim,person)
	# 新建隔离场景的日序是0；仅恢复clock会在第一帧补跑日终，丢掉快照中的位置线索。
	store.memory.consolidated_day=0;store.memory.clock=0
	store.memory.observations[person].clear();sim.perception.memories[person].clear()
	Snapshot.restore(sim,data)
	var restored_day: int=store.memory.consolidated_day
	store.memory.advance(.01)
	var preserved: bool=store.memory.observations[person].has(target)
	store.memory.advance(float(store.memory.policy.day_seconds))
	var new_day_consolidates: bool=not store.memory.observations[person].has(target)
	print("SNAPSHOT_MEMORY_RESULT ",JSON.stringify({"restored_day":restored_day,"target_preserved_after_first_tick":preserved,"new_day_consolidates":new_day_consolidates}))
	var correct: bool=preserved and restored_day==2 and new_day_consolidates
	sim.free();scene.queue_free();await process_frame;await process_frame
	if correct:print("VERIFICATION_SNAPSHOT_MEMORY_PASSED")
	quit(0 if correct else 1)
