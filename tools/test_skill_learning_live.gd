extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Voice.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.autonomy_enabled=false;voice.config.tts_enabled=false;voice.config.local_only=false;voice.config.actions_enabled=true
	voice.menu.close()
	while not voice.survival.ready_for_actions: await physics_frame
	var sim: Node=voice.survival
	sim.actors.person_003.body.global_position=sim.water.SOURCE+Vector3(-0.8,0.6,-0.8)
	sim.store.people.person_003.needs.thirst=80
	sim.store.people.person_003.needs.hunger=10
	sim._sync("person_003")
	var learned: Array=[];voice.skills.learning_finished.connect(func(result: Dictionary): learned.append(result))
	var started: Dictionary=voice.skills.learn_drink("person_003")
	if not started.ok: push_error(started.error);quit(1);return
	print("LEARNING_STARTED ",started.job)
	var began: int=Time.get_ticks_msec()
	while learned.is_empty() and Time.get_ticks_msec()-began<490000: await create_timer(0.25).timeout
	if learned.is_empty() or not learned[0].ok:
		print("LEARNING_FAILED ",learned);scene.queue_free();await create_timer(0.2).timeout;quit(1);return
	var results: Array=[];voice.skills.finished.connect(func(result: Dictionary):results.append(result))
	var reports: Array=[];voice.pipeline.report_ready.connect(func(report: Dictionary):reports.append(report))
	var before: float=sim.store.people.person_003.needs.thirst
	var consumed: int=sim.water.consumed
	voice._job_config=voice.config.duplicate(true);voice._allow_execution=true;voice.busy=true
	voice._start_pipeline({"id":"generated_drink_use","kind":"speech_intent","speaker":"player","listeners":["person_003"],"text":"大山，就从你身旁这个水源喝一份水。"},voice._job_config)
	var deadline:=Time.get_ticks_msec()+100000
	while results.is_empty() and Time.get_ticks_msec()<deadline:
		await create_timer(0.2).timeout
		if not reports.is_empty() and reports[0].has("error"): break
	var passed: bool=not results.is_empty() and results[0].success and sim.water.consumed==consumed+1 and sim.store.people.person_003.needs.thirst<before-40
	var file:=FileAccess.open("res://services/skill-runtime/runtime/learning_live_result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"learning":learned,"reports":reports,"results":results,"thirst_before":before,"thirst_after":sim.store.people.person_003.needs.thirst,"consumed_delta":sim.water.consumed-consumed},"  "))
	print("LEARNING_LIVE_RESULT ",passed," thirst ",before," -> ",sim.store.people.person_003.needs.thirst)
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
