extends SceneTree
const Voice=preload("res://scripts/voice/voice_test.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var scene: Node3D=load("res://scenes/initial_base.tscn").instantiate();root.add_child(scene)
	var voice:=Voice.new();voice.name="VoiceTest";scene.add_child(voice)
	voice.config.local_only=false;voice.config.autonomy_enabled=true;voice.config.actions_enabled=true;voice.config.tts_enabled=false
	voice.menu.close()
	while not voice.survival.ready_for_actions: await physics_frame
	var sim: Node=voice.survival
	for id in voice.store.people:
		voice.store.people[id].needs.hunger=10
		voice.store.people[id].needs.thirst=80 if id=="person_001" else 10
		sim._sync(id)
	var reports: Array=[]
	voice.pipeline.report_ready.connect(func(report: Dictionary):reports.append(report))
	var deadline:=Time.get_ticks_msec()+300000
	while Time.get_ticks_msec()<deadline and sim.water.consumed==0: await create_timer(0.25).timeout
	var passed: bool=sim.water.consumed>0 and voice.store.people.person_001.needs.thirst<60 and not reports.is_empty()
	var file:=FileAccess.open("res://services/text-gateway/runtime/water_live.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"reports":reports,"consumed":sim.water.consumed,"thirst":voice.store.people.person_001.needs.thirst},"  "))
	print("WATER_LIVE ",passed," calls=",reports.size()," consumed=",sim.water.consumed)
	scene.queue_free();await create_timer(0.2).timeout;quit(0 if passed else 1)
