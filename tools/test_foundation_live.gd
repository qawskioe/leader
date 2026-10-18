extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate()
	root.add_child(scene)
	var voice:=Voice.new()
	voice.name="VoiceTest"; scene.add_child(voice)
	voice.config.local_only=false; voice.config.autonomy_enabled=true
	voice.config.actions_enabled=true; voice.config.tts_enabled=false
	voice.menu.close()
	while not voice.survival.ready_for_actions: await physics_frame
	var sim: Node=voice.survival
	sim.hunger_rate=0
	for id in voice.store.people: voice.store.people[id].needs.hunger=85 if id=="person_002" else 10
	sim.actors.person_001.body.position=Vector3(4,0.2,6)
	sim.actors.person_002.body.position=Vector3(1,0.2,6)
	await physics_frame
	# 初始观察和一句请求为夹具，观察仍经真实朝向／遮挡判断。
	for id in ["person_001","person_002"]:
		for angle in [0.0,PI/2,PI,PI*1.5]:
			sim.actors[id].body.rotation.y=angle; sim.perception.observe(id)
		sim._sync(id)
	voice.store.hear("person_002",{"id":"seed","kind":"need_changed","speaker":"body","text":"需要食物"})
	voice._deliver_public("person_002","seed","石头，能拿一份食物直接交给我吗？",12,{"intent":"none","speech_act":"request","addressed_person":"person_001"})
	var reports: Array=[]
	voice.pipeline.report_ready.connect(func(report: Dictionary): reports.append(report))
	var deadline:=Time.get_ticks_msec()+180000
	while Time.get_ticks_msec()<deadline:
		await create_timer(0.25).timeout
		if sim.eaten==1 and not voice.busy and voice._execution_feedback.is_empty(): break
	var root_id:="seed_request_person_001"
	var passed: bool=sim.eaten==1 and sim.storage_food==2 and voice.help_tasks.tasks.has(root_id) and voice.help_tasks.tasks[root_id].status=="satisfied" and reports.all(func(r: Dictionary): return not r.has("error"))
	var file:=FileAccess.open("res://services/text-gateway/runtime/foundation_live.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"reports":reports,"tasks":voice.help_tasks.tasks,"eaten":sim.eaten,"stock":sim.storage_food},"  "))
	print("FOUNDATION_LIVE ",JSON.stringify({"passed":passed,"calls":reports.size(),"eaten":sim.eaten,"stock":sim.storage_food}))
	scene.queue_free(); await create_timer(0.15).timeout
	quit(0 if passed else 1)
