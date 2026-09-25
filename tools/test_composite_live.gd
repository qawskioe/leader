extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Voice.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.autonomy_enabled=true;voice.config.tts_enabled=false;voice.config.local_only=false;voice.config.actions_enabled=true;voice.menu.close()
	while not voice.survival.ready_for_actions: await physics_frame
	var package: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://services/skill-runtime/runtime/approach_package.json"))
	var registered: Dictionary=voice.skills.library.register_verified(package.definition,package.receipt)
	assert(registered.ok)
	assert(voice.skills.library.grant("person_003",registered.ref,"预设基础技能，独立场景验证通过").is_empty())
	voice.skills.sync_person("person_003")
	assert(voice.skills._composition_dependencies("person_003").size()==2,"需要已掌握的两个基础技能")
	var sim: Node=voice.survival
	for id in voice.store.people:
		voice.store.people[id].needs.hunger=10;voice.store.people[id].needs.thirst=10
	sim.actors.person_003.body.global_position=sim.water.SOURCE+Vector3(-6,0.6,-6)
	voice.store.people.person_003.needs.thirst=80;sim._sync("person_003")
	var reports: Array=[];var learned: Array=[];var results: Array=[]
	voice.pipeline.report_ready.connect(func(r: Dictionary): reports.append(r))
	voice.skills.learning_finished.connect(func(r: Dictionary):learned.append(r))
	voice.skills.finished.connect(func(r: Dictionary):results.append(r))
	voice._job_config=voice.config.duplicate(true);voice._allow_execution=true;voice.busy=true
	voice._start_pipeline({"id":"compose_request","kind":"speech_intent","speaker":"player","listeners":["person_003"],"text":"大山，先走到你知道的那个水源旁边，再喝一份水。"},voice._job_config)
	var deadline:=Time.get_ticks_msec()+540000
	while results.is_empty() and Time.get_ticks_msec()<deadline:
		await create_timer(0.2).timeout
		if not reports.is_empty() and reports[0].has("error"):break
		if not learned.is_empty() and not learned[0].ok:break
	var passed: bool=not results.is_empty() and results[0].success and sim.water.consumed==1 and voice.store.people.person_003.needs.thirst<45
	if passed:
		var count:=0
		for item in results[0].runtime.trace:
			if item.operation=="skill_call" and item.phase=="start":count+=1
		passed=count==2
	var file:=FileAccess.open("res://services/skill-runtime/runtime/composite_live_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"reports":reports,"learning":learned,"results":results,"consumed":sim.water.consumed,"thirst":voice.store.people.person_003.needs.thirst},"  "))
	print("COMPOSITE_LIVE ",passed," nested_skill_calls=2 consumed=",sim.water.consumed)
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
