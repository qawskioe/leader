extends SceneTree
var failures: Array=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
func run() -> void:
	var scene=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var store=load("res://scripts/voice/people_store.gd").new();store.initialize()
	var sim=load("res://scripts/survival/simulation.gd").new();sim.scene=scene;sim.store=store;scene.add_child(sim)
	while not sim.ready_for_actions: await physics_frame
	var actor: Dictionary=sim.actors.person_003
	actor.body.global_position=sim.water.SOURCE+Vector3(0,0.6,-0.45)
	actor.body.rotation.y=0
	for frame in 20: await physics_frame
	sim.perception._record("person_003","water_source","water_source",sim.water.SOURCE,true)
	store.people.person_003.needs.thirst=80
	var api=load("res://scripts/skills/world_adapter.gd").new();api.sim=sim;api.person_id="person_003";scene.add_child(api)
	check(api.acquire().ok,"acquire")
	check(not (await api.operate("sip_water",["Hand.R"])).ok,"cannot drink without water")
	check(not (await api.operate("pose",[{"Spine":{"x":999,"y":0,"z":0}},1.0])).ok,"reject angle outside bounds")
	var pose: Dictionary=await api.operate("pose",[{"lower_hips":0.5,"Spine":{"x":15,"y":0,"z":0},"Chest":{"x":5,"y":0,"z":0}},0.5])
	var hips: int=actor.skeleton.find_bone("Hips")
	var lowered: Vector3=actor.skeleton.get_bone_pose_position(hips)
	api.motor.start()
	check(actor.skeleton.get_bone_pose_position(hips).is_equal_approx(lowered),"phase transition preserves lowered hips")
	var spine: Quaternion=actor.skeleton.get_bone_pose_rotation(actor.skeleton.find_bone("Spine"))
	var reach: Dictionary=await api.operate("reach_hand",["Hand.R","water_source",0.8])
	check(pose.ok and reach.ok,"reach water: "+JSON.stringify(reach))
	check(actor.skeleton.get_bone_pose_rotation(actor.skeleton.find_bone("Spine")).is_equal_approx(spine),"hand IK preserves trunk pose")
	print("BODY_CONTACT ",api.motor.point("Hand.R")," source=",sim.water.SOURCE)
	var scoop: Dictionary=await api.operate("scoop_water",["water_source","Hand.R"])
	check(scoop.ok,"scoop: "+JSON.stringify(scoop))
	check(store.people.person_003.needs.thirst>=80 and sim.water.consumed==0,"scoop does not quench thirst")
	check(not (await api.operate("sip_water",["Hand.R"])).ok,"cannot sip at source")
	reach=await api.operate("reach_hand",["Hand.R","mouth",0.8])
	check(reach.ok,"reach mouth: "+JSON.stringify(reach))
	check((await api.operate("sip_water",["Hand.R"])).ok,"sip after physical contact")
	check(sim.water.consumed==1 and store.people.person_003.needs.thirst<40,"real consumption")
	check((await api.operate("relax",[0.5])).ok,"relax")
	api.cancel()
	check(actor.stage=="idle" and not is_instance_valid(api.motor.held_water),"cancel clears body and visual")
	check(api.acquire().ok,"reacquire after cancellation")
	create_timer(0.1).timeout.connect(api.cancel)
	var cancelled: Dictionary=await api.operate("pose",[{"lower_hips":0.5},1.0])
	check(cancelled.code=="cancelled" and actor.stage=="idle","interrupt interpolation releases actor")
	print("BODY_SKILL_TEST failures=",failures)
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if failures.is_empty() else 1)
