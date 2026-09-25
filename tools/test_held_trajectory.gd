extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice=load("res://scripts/voice/voice_test.gd").new();scene.add_child(voice)
	var audit=preload("res://tools/test_release_physics.gd").AuditObjects.new()
	voice.skills.add_child(audit);voice.skills.world_objects=audit
	await preload("res://scripts/skills/luau_playtest.gd").prepare(voice,"user://skills/luau/replay_%d.json"%Time.get_ticks_usec())
	voice.set_process(false)
	var refs: Dictionary={}
	for entry in voice.skills.library.describe("person_003"): refs[voice.skills.library.definitions[entry.ref].id]=entry.ref
	var results: Array=[]
	var targets:=[Vector3(2.25,0.305639863014221,0.75),Vector3(-0.75,0.0765087604522705,0.75)]
	for step in 2:
		var goal: String="take_object" if step==0 else "place_object"
		var args: Dictionary={"object":"stone_tool"}
		if step>0:
			var observation: Dictionary=voice.survival.space.capture("person_003")
			args.target={"observation_id":observation.id,"position":voice.survival.space.xyz(targets[step-1])}
		assert(voice.skills.invoke("person_003","replay_"+str(step),{"ref":refs[goal],"arguments":args}).ok)
		var result: Dictionary=await voice.skills.finished
		results.append(result)
		print("REPLAY_STEP ",step," ",result.message)
	for frame in 60: await physics_frame
	var file:=FileAccess.open("res://services/luau-runtime/runtime/held_trajectory.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"results":results,"samples":audit.samples},"  "));file.close()
	var passed: bool=results[0].success and results[1].success
	print("HELD_TRAJECTORY_PASSED" if passed else "HELD_TRAJECTORY_FAILED")
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
