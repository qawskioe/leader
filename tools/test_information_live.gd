extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate(); root.add_child(scene)
	var voice:=Voice.new(); voice.name="VoiceTest"; scene.add_child(voice)
	voice.config.local_only=false; voice.config.autonomy_enabled=true; voice.config.tts_enabled=true
	voice.menu.close()
	while not voice.survival.ready_for_actions: await physics_frame
	var sim: Node=voice.survival
	sim.hunger_rate=0
	for id in voice.store.people: voice.store.people[id].needs.hunger=10
	sim.actors.person_001.body.position=Vector3(1,0.2,6)
	sim.actors.person_002.body.position=Vector3(4,0.2,6)
	sim.perception.memories.person_002.erase("basket/1"); sim.perception.memories.person_002.erase("basket/2")
	voice.store.people.person_002.known_facts=["测试情境：自己没有留意篮子放在哪里，想问同伴。"]
	voice.store.hear("person_002",{"id":"info_seed","kind":"need_changed","speaker":"body","text":"不知道篮子位置"})
	voice._deliver_public("person_002","info_seed","石头，你记得篮子最后放在哪里吗？",12,{"speech_act":"request","request_kind":"information","addressed_person":"person_001"})
	var reports: Array=[]
	voice.pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	var deadline:=Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.25).timeout
		if not sim.perception.known("person_002","basket/1").is_empty() and not voice.busy: break
	var learned: Dictionary=sim.perception.known("person_002","basket/1")
	var passed: bool=not learned.is_empty() and learned.get("heard_from")=="person_001" and voice.help_tasks.tasks.is_empty() and not reports.is_empty() and reports[0].decision.intent=="none"
	var file:=FileAccess.open("res://services/text-gateway/runtime/information_live.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"learned":learned,"reports":reports,"log":voice._log_path},"  "))
	print("INFORMATION_LIVE ",passed," model_calls=",reports.size())
	scene.queue_free(); await create_timer(0.2).timeout; quit(0 if passed else 1)
