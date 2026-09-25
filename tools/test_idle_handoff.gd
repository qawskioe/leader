extends SceneTree
func _initialize(): run.call_deferred()
func run():
 var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
 var store=load("res://scripts/voice/people_store.gd").new();store.initialize()
 var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
 while not sim.ready_for_actions:await physics_frame
 for i in 10:await process_frame
 var api=load("res://scripts/skills/world_adapter.gd").new();api.sim=sim;api.person_id="person_002";scene.add_child(api)
 assert(api.acquire().ok)
 var hold: Dictionary=await api.operate("pose_bones",[{},0.3])
 assert(hold.ok and hold.timing.simulated_elapsed_seconds>=0.3)
 assert(hold.timing.simulated_elapsed_seconds<0.3+hold.timing.last_step_seconds+0.001)
 var samples: Array[Vector3]=[]
 var observe=func():samples.append(api.motor.point("Hand.R"))
 process_frame.connect(observe)
 await api.finish()
 for i in 5:await process_frame
 process_frame.disconnect(observe)
 var largest:=0.0
 for i in range(1,samples.size()):largest=maxf(largest,samples[i].distance_to(samples[i-1]))
 print("IDLE_HANDOFF_MAX_STEP_M=",largest)
 if largest>0.06:push_error("宿主交还待机时发生手部跳变");quit(1);return
 assert(sim.actors.person_002.stage=="idle" and sim.actors.person_002.animation.is_playing())
 print("IDLE_HANDOFF_PASSED")
 scene.queue_free();await create_timer(.2).timeout;quit()
