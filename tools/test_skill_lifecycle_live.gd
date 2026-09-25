extends SceneTree
## 真实模型端到端回归；独立技能库，不授予正式人物，关闭 TTS。
var voice: Node
var reports: Array=[]
var learned: Array=[]
var results: Array=[]
var failures: Array=[]
var phases: Array=[]
var folder: String

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func request(label: String, text: String) -> bool:
	var start_result:=results.size()
	var start_report:=reports.size()
	var start_learned:=learned.size()
	var start_consumed: int=voice.survival.water.consumed
	voice.store.people.person_003.needs.thirst=80
	voice.survival._sync("person_003")
	voice.busy=true
	voice._decisions_done=false
	voice._allow_execution=true
	voice._job_config=voice.config.duplicate(true)
	voice._start_pipeline({"id":label,"kind":"speech_intent","speaker":"player","listeners":["person_003"],"text":text},voice._job_config)
	var deadline:=Time.get_ticks_msec()+540000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
		if reports.size()>start_report and reports[-1].has("error"): break
		if learned.size()>start_learned and not learned[-1].ok: break
		if results.size()>start_result and not voice.busy and voice.autonomy.requests.is_empty(): break
		if reports.size()>start_report and not voice.busy and voice.skills.learning.is_empty() and voice.skills.active.is_empty() and learned.size()==start_learned: break
	var executed: bool=results.size()>start_result and results[-1].success
	var passed: bool=executed and voice.survival.water.consumed==start_consumed+1 and voice.store.people.person_003.needs.thirst<45
	phases.append({"name":label,"passed":passed,"new_learning":learned.size()-start_learned,"new_results":results.size()-start_result,"consumed":voice.survival.water.consumed})
	print("LIFECYCLE_PHASE ",JSON.stringify(phases[-1]))
	check(executed,label+" did not actually execute")
	check(voice.survival.water.consumed==start_consumed+1,label+" did not consume exactly one water portion")
	check(voice.store.people.person_003.needs.thirst<45,label+" did not reduce thirst")
	return passed

func run() -> void:
	folder="res://services/skill-runtime/runtime/lifecycle_%d_%d"%[Time.get_unix_time_from_system(),OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var scene=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	voice=load("res://scripts/voice/voice_test.gd").new()
	voice.name="VoiceTest"
	scene.add_child(voice)
	voice.config.autonomy_enabled=true
	voice.config.tts_enabled=false
	voice.config.local_only=false
	voice.config.actions_enabled=true
	voice.menu.close()
	check(voice.skills.initialize(folder+"/library.json").is_empty(),"isolated library")
	voice.capability_gap_path=folder+"/gaps.json"
	voice._snapshot_path=folder+"/people.json"
	voice.pipeline.report_ready.connect(func(r: Dictionary): reports.append(r))
	voice.skills.learning_finished.connect(func(r: Dictionary): learned.append(r))
	voice.skills.finished.connect(func(r: Dictionary): results.append(r))
	var sim: Node=voice.survival
	while not sim.ready_for_actions: await physics_frame
	for id in voice.store.people:
		voice.store.people[id].needs.hunger=0
		voice.store.people[id].needs.thirst=0
		voice.store.people[id].needs.fatigue=0
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://services/skill-runtime/runtime/approach_package.json"))
	var registered: Dictionary=voice.skills.library.register_verified(package.definition,package.receipt)
	check(registered.ok,"approach registration")
	check(voice.skills.library.grant("person_003",registered.ref,"独立测试预设").is_empty(),"approach grant")
	voice.skills.sync_person("person_003")
	sim.actors.person_003.body.global_position=sim.water.SOURCE+Vector3(-1,0.6,-1)
	sim.perception._record("person_003","water_source","water_source",sim.water.SOURCE,true)
	sim._sync("person_003")
	if await request("learn_drink","大山，请从你旁边的水源喝一份水。如果还不会，先学会，再继续执行。"):
		check(learned.size()==1 and sim.water.consumed==1,"base learned and consumed exactly once")
		sim.actors.person_003.body.global_position=sim.water.SOURCE+Vector3(-6,0.6,-6)
		sim._sync("person_003")
		if await request("learn_composite","大山，请先走到你知道的水源旁边，再喝一份水；如果没有这个复合技能，就先学会再完成。"):
			check(learned.size()==2 and sim.water.consumed==2,"composite learned and consumed once")
			var previous_learning:=learned.size()
			sim.actors.person_003.body.global_position=sim.water.SOURCE+Vector3(-5,0.6,-5)
			sim._sync("person_003")
			await request("reuse","大山，再用刚才学会的接近水源再饮水技能，走过去喝一份水。")
			check(learned.size()==previous_learning and sim.water.consumed==3,"reuse without rebuilding")
			voice.config.autonomy_enabled=false
			var ref: String=learned[-1].ref
			var before: int=sim.water.consumed
			var before_results:=results.size()
			sim.actors.person_003.body.global_position=sim.water.SOURCE+Vector3(-6,0.6,-6)
			var submitted: Dictionary=voice.skills.invoke("person_003","cancel_probe",{"ref":ref,"arguments":{"source":"water_source"}})
			check(submitted.ok,"cancellation invocation")
			await create_timer(0.15).timeout
			voice.skills.cancel("person_003")
			var deadline:=Time.get_ticks_msec()+5000
			while results.size()==before_results and Time.get_ticks_msec()<deadline: await process_frame
			await create_timer(1.2).timeout
			check(results.size()>before_results and not results[-1].success,"cancelled result")
			check(sim.water.consumed==before and sim.actors.person_003.stage=="idle" and voice.skills.active.is_empty(),"cancel releases actor without water consumption")
			var reloaded=load("res://scripts/skills/library.gd").new()
			check(reloaded.initialize(folder+"/library.json",voice.store.people).is_empty(),"reload persisted library")
			check(not reloaded.resolve("person_003",ref).is_empty(),"reload preserves learned reference")
			check(reloaded.resolve("person_002",ref).is_empty(),"other person does not automatically learn")
	var file:=FileAccess.open(folder+"/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"phases":phases,"reports":reports,"learning":learned,"results":results},"\t"))
	file.close()
	print("LIFECYCLE_RESULT ",folder," failures=",failures)
	scene.queue_free()
	await create_timer(0.3).timeout
	quit(0 if failures.is_empty() else 1)
