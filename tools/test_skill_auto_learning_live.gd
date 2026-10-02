extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Voice.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.autonomy_enabled=true;voice.config.tts_enabled=false;voice.config.local_only=false;voice.config.actions_enabled=true
	voice.menu.close()
	while not voice.survival.ready_for_actions: await physics_frame
	assert(voice.skills.initialize("res://services/skill-runtime/runtime/auto_learning_%d.json"%Time.get_ticks_usec()).is_empty())
	var sim: Node=voice.survival
	for id in voice.store.people:
		voice.store.people[id].needs.hunger=10;voice.store.people[id].needs.thirst=10
	sim.actors.person_003.body.global_position=sim.water.SOURCE+Vector3(-0.8,0.6,-0.8)
	voice.store.people.person_003.needs.thirst=80
	sim._sync("person_003")
	var reports: Array=[];var learned: Array=[];var results: Array=[]
	voice.pipeline.report_ready.connect(func(report: Dictionary):reports.append(report))
	voice.skills.learning_finished.connect(func(result: Dictionary):learned.append(result))
	voice.skills.finished.connect(func(result: Dictionary):results.append(result))
	voice._job_config=voice.config.duplicate(true);voice._allow_execution=true;voice.busy=true
	var consumed: int=sim.water.consumed
	voice._start_pipeline({"id":"one_player_request","kind":"speech_intent","speaker":"player","listeners":["person_003"],"text":"大山，从你身旁这个水源喝一份水。"},voice._job_config)
	var deadline:=Time.get_ticks_msec()+540000
	while results.is_empty() and Time.get_ticks_msec()<deadline:
		await create_timer(0.2).timeout
		if not reports.is_empty() and (reports[0].has("error") or reports[0].decision.get("learning_request")==null):break
		if not learned.is_empty() and not learned[0].ok:break
	var passed: bool=not learned.is_empty() and learned[0].ok and reports.size()>=2 and not results.is_empty() and results[0].success and sim.water.consumed==consumed+1 and voice.store.people.person_003.needs.thirst<45
	if passed:
		var resumed: Dictionary=voice.store.event_for("person_003",results[0].source_event_id)
		passed=resumed.kind=="skill_ready" and resumed.original_event.id=="one_player_request"
	var file:=FileAccess.open("res://services/skill-runtime/runtime/auto_learning_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"reports":reports,"learning":learned,"results":results,"consumed_delta":sim.water.consumed-consumed,"thirst":voice.store.people.person_003.needs.thirst},"  "))
	print("AUTO_LEARNING_LIVE ",passed," reports=",reports.size()," consumed=",sim.water.consumed-consumed)
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
